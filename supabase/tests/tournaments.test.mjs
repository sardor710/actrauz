// Milestone 5a: tournament categories, registration, partners and the
// waitlist. The `app` functions are called with a fixed clock.

import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { after, before, beforeEach, test } from 'node:test';
import { asAnon, asUser, createUser, errorOf, expectError, freshDb } from './helpers/db.mjs';
import { addPhone, addVenue, tashkent } from './helpers/fixtures.mjs';

let db;
let pool;
let venueId;

// Sunday evening in Tashkent. Tournaments start on 10 December; registration
// closes at 00:00 that day unless a test sets its own deadline.
const now = tashkent('2026-11-22', 20);
const later = (hours, minutes = 0) => new Date(Date.parse(now) + (hours * 60 + minutes) * 60000).toISOString();

before(async () => {
  db = await freshDb('tournaments');
  pool = db.pool;
  venueId = await addVenue(pool, { name: 'Test venue' });
});
after(() => db.end());

beforeEach(async () => {
  await pool.query('delete from notifications');
  await pool.query('delete from tournament_registrations');
  await pool.query('delete from tournament_categories');
  await pool.query('delete from tournaments');
  await pool.query('delete from phone_lookups');
});

const one = async (sql, params) => (await pool.query(sql, params)).rows[0];

async function player(name, levels = {}) {
  const id = await createUser(pool, name);
  await pool.query(`update profiles set city_id = 'tashkent' where id = $1`, [id]);
  for (const [sportId, level] of Object.entries(levels)) {
    await pool.query(`insert into player_levels (user_id, sport_id, level) values ($1, $2, $3)`, [id, sportId, level]);
  }
  return id;
}

async function block(user) {
  await pool.query(
    `insert into reliability_events (user_id, kind, delta, ref, created_at) values
       ($1, 'no_show', -20, 'b1', $2), ($1, 'no_show', -20, 'b2', $2)`,
    [user, now],
  );
}

async function tournament({ starts = '2026-12-10', ends = starts, deadline = null, sport = 'padel', title = 'Cup', city = 'tashkent' } = {}) {
  const { rows } = await pool.query(
    `insert into tournaments (city_id, sport_id, venue_id, title_en, title_ru, title_uz, starts_on, ends_on, registration_deadline)
     values ($1, $2, $3, $4, $4 || ' ru', $4 || ' uz', $5, $6, $7) returning id`,
    [city, sport, venueId, title, starts, ends, deadline],
  );
  return rows[0].id;
}

async function category(tournamentId, { kind = 'singles', cap = 2, fee = 100000, min = 1, max = 5, waitlist = true, name = 'Open' } = {}) {
  const { rows } = await pool.query(
    `insert into tournament_categories (tournament_id, name_en, name_ru, name_uz, kind, cap, fee, min_level, max_level, waitlist_enabled)
     values ($1, $2, $2, $2, $3, $4, $5, $6, $7, $8) returning id`,
    [tournamentId, name, kind, cap, fee, min, max, waitlist],
  );
  await pool.query(`select app.sync_tournament_summary($1)`, [tournamentId]);
  return rows[0].id;
}

const rj = (sql, params) => one(`select app.registration_json(${sql}) as r`, params).then((r) => r.r);
const register = (user, cat, partner = null, when = now) => rj(`app.register($1, $2, $3, $4)`, [user, cat, partner, when]);
const respond = (user, id, accept, when = now) => rj(`app.respond_partner($1, $2, $3, $4)`, [user, id, accept, when]);
const cancel = (user, id, when = now) => rj(`app.cancel_registration($1, $2, $3)`, [user, id, when]);
const joinWaitlist = (user, cat, partner = null, when = now) => rj(`app.join_waitlist($1, $2, $3, $4)`, [user, cat, partner, when]);
const claim = (user, id, when = now) => rj(`app.claim_offer($1, $2, $3)`, [user, id, when]);
const expire = (when) => one(`select app.expire_tournament_entries($1) as n`, [when]).then((r) => r.n);
const catView = (id, user = null) =>
  one(`select app.category_json(c, $2) as c from tournament_categories c where c.id = $1`, [id, user]).then((r) => r.c);
const tView = (id, user = null, when = now) =>
  one(`select app.tournament_json(t, $2, $3) as t from tournaments t where t.id = $1`, [id, user, when]).then((r) => r.t);
const statusOf = (id) => one(`select status from tournament_registrations where id = $1`, [id]).then((r) => r.status);
const summary = (id) => one(`select min_fee, max_fee, slots_total, slots_filled from tournaments where id = $1`, [id]);
const notesOf = (user, kind) =>
  pool
    .query(`select * from notifications where user_id = $1 ${kind ? 'and kind = $2' : ''} order by created_at, id`, kind ? [user, kind] : [user])
    .then((r) => r.rows);

// --- migration -------------------------------------------------------------

test('existing tournaments get one default category and a deadline; the backfill runs once', async () => {
  const { rows } = await pool.query(
    `insert into tournaments (city_id, sport_id, title_en, starts_on, ends_on, min_fee, max_fee, slots_total, slots_filled)
     values ('tashkent', 'padel', 'Legacy', '2026-12-12', '2026-12-13', 50000, 90000, 16, 7) returning id`,
  );
  const id = rows[0].id;
  await pool.query(`select app.backfill_tournaments()`);
  await pool.query(`select app.backfill_tournaments()`);

  const cats = (await pool.query(`select * from tournament_categories where tournament_id = $1`, [id])).rows;
  assert.equal(cats.length, 1);
  const expectedId = (await one(`select md5('actra:default-category:' || $1::text)::uuid as id`, [id])).id;
  assert.equal(cats[0].id, expectedId);
  assert.equal(cats[0].kind, 'singles');
  assert.equal(cats[0].gender, 'open');
  assert.equal(cats[0].fee, 50000);
  assert.equal(cats[0].cap, 16);
  assert.equal(cats[0].min_level, 1);
  assert.equal(cats[0].max_level, 5);

  // Summary columns now come from the category: the fake count becomes 0.
  assert.deepEqual(await summary(id), { min_fee: 50000, max_fee: 50000, slots_total: 16, slots_filled: 0 });
  const t = await one(`select registration_deadline from tournaments where id = $1`, [id]);
  assert.equal(t.registration_deadline.toISOString(), new Date('2026-12-12T00:00:00+05:00').toISOString());

  // A tournament with zero slots still gets a category it can use.
  const zero = await pool.query(
    `insert into tournaments (city_id, sport_id, title_en, starts_on, ends_on) values ('tashkent', 'padel', 'Zero', '2026-12-12', '2026-12-12') returning id`,
  );
  await pool.query(`select app.backfill_tournaments()`);
  assert.equal((await one(`select cap from tournament_categories where tournament_id = $1`, [zero.rows[0].id])).cap, 1);
});

test('a tournament without a stored deadline closes at 00:00 venue time on its first day', async () => {
  const t = await tournament();
  await category(t);
  const view = await tView(t, null);
  assert.equal(view.registration_deadline_local, '2026-12-10T00:00:00');
  assert.equal(view.registration_open, true);
  assert.equal((await tView(t, null, tashkent('2026-12-10', 0))).registration_open, false);
});

// --- singles ---------------------------------------------------------------

test('singles: register counts, the fee is locked, the third player gets full', async () => {
  const t = await tournament();
  const cat = await category(t, { cap: 2, fee: 120000 });
  const [a, b, c] = [await player('A'), await player('B'), await player('C')];

  const ra = await register(a, cat);
  assert.equal(ra.status, 'registered');
  assert.equal(ra.fee, 120000);
  assert.equal(ra.currency, 'UZS');
  assert.equal(ra.paid, false);
  assert.deepEqual(ra.registrant, { id: a, name: 'A' });
  assert.equal(ra.partner, null);
  assert.equal(JSON.stringify(ra).includes('+998'), false);
  assert.equal((await catView(cat)).filled, 1);

  await pool.query(`update tournament_categories set fee = 999 where id = $1`, [cat]);
  assert.equal((await one(`select fee from tournament_registrations where id = $1`, [ra.id])).fee, 120000);

  await register(b, cat);
  const view = await catView(cat);
  assert.equal(view.filled, 2);
  assert.equal(view.cap, 2);
  assert.equal(view.full, true);
  assert.equal(await errorOf(register(c, cat)), 'full');
  assert.equal(await errorOf(register(a, cat)), 'already_registered');

  const notes = await notesOf(a, 'tournament_registered');
  assert.equal(notes.length, 1);
  assert.equal(notes[0].category, 'tournaments');
  assert.equal(notes[0].payload.registration_id, ra.id);
  assert.equal(notes[0].payload.tournament_id, t);
  assert.equal(notes[0].payload.category_id, cat);
  assert.deepEqual(notes[0].payload.title, { uz: 'Cup uz', ru: 'Cup ru', en: 'Cup' });
  assert.deepEqual(notes[0].payload.category_name, { uz: 'Open', ru: 'Open', en: 'Open' });
});

test('register rules: unknown category, partner on singles, inactive tournament', async () => {
  const t = await tournament();
  const cat = await category(t);
  const [a, b] = [await player('A'), await player('B')];
  assert.equal(await errorOf(register(a, randomUUID())), 'not_found');
  assert.equal(await errorOf(register(a, cat, b)), 'invalid_argument');
  await pool.query(`update tournaments set active = false where id = $1`, [t]);
  assert.equal(await errorOf(register(a, cat)), 'not_found');
});

test('levels: the registrant and, for pairs, the partner must be in range', async () => {
  const t = await tournament();
  const singles = await category(t, { min: 2, max: 4 });
  const pairs = await category(t, { kind: 'pairs', min: 2, max: 4, name: 'Pairs' });
  const low = await player('Low'); // no level row counts as 1
  const mid = await player('Mid', { padel: 3 });
  const high = await player('High', { padel: 5 });
  assert.equal(await errorOf(register(low, singles)), 'level_out_of_range');
  assert.equal(await errorOf(register(high, singles)), 'level_out_of_range');
  assert.equal((await register(mid, singles)).status, 'registered');
  assert.equal(await errorOf(register(mid, pairs, high)), 'level_out_of_range');
  assert.equal(await errorOf(register(mid, pairs, low)), 'level_out_of_range');
});

test('a blocked player cannot register, accept, join the waitlist or claim', async () => {
  const t = await tournament();
  const cat = await category(t, { cap: 1 });
  const pairs = await category(t, { kind: 'pairs', cap: 2, name: 'Pairs' });
  const [a, b, bad] = [await player('A'), await player('B'), await player('Bad')];
  const pending = await register(a, pairs, bad);
  await register(b, cat);
  await block(bad);
  assert.equal(await errorOf(register(bad, cat)), 'reliability_too_low');
  assert.equal(await errorOf(joinWaitlist(bad, cat)), 'reliability_too_low');
  assert.equal(await errorOf(respond(bad, pending.id, true)), 'reliability_too_low');
  assert.equal(await statusOf(pending.id), 'pending_partner');

  // Offered before being blocked: the claim is refused, the offer stands.
  const w = await player('W');
  const t2 = await tournament({ title: 'Second' });
  const cat2 = await category(t2, { cap: 1 });
  const first = await register(b, cat2);
  const jw = await joinWaitlist(w, cat2);
  await cancel(b, first.id, later(1));
  assert.equal(await statusOf(jw.id), 'offered');
  await block(w);
  assert.equal(await errorOf(claim(w, jw.id, later(2))), 'reliability_too_low');
  assert.equal(await statusOf(jw.id), 'offered');
});

// --- follow-up rulings ----------------------------------------------------------

test('lazy expiry: an expired offer holds no spot before the job runs', async () => {
  const t = await tournament();
  const cat = await category(t, { cap: 1 });
  const [a, w, n] = [await player('A'), await player('W'), await player('N')];
  const ra = await register(a, cat);
  const jw = await joinWaitlist(w, cat, null, later(0, 1));
  await cancel(a, ra.id, later(1));
  assert.equal(await statusOf(jw.id), 'offered');
  // The offer ran out at later(25); no job since. The newcomer gets the spot.
  assert.equal((await register(n, cat, null, later(25, 1))).status, 'registered');
  assert.equal(await statusOf(jw.id), 'lapsed');
  assert.equal((await catView(cat)).filled, 1);
  assert.equal((await summary(t)).slots_filled, 1);
});

test('lazy expiry: an expired pending pair frees both players before the job runs', async () => {
  const t = await tournament();
  const cat = await category(t, { kind: 'pairs', cap: 2 });
  const [a, p, q] = [await player('A'), await player('P'), await player('Q')];
  const old = await register(a, cat, p);
  // Past 48 hours, no job: A registers again with someone else.
  const again = await register(a, cat, q, later(48, 1));
  assert.equal(again.status, 'pending_partner');
  assert.equal(await statusOf(old.id), 'expired');
  assert.equal((await notesOf(a, 'tournament_partner_expired')).length, 1);
  // And the swept entry is not swept or notified twice by the job.
  await expire(later(48, 2));
  assert.equal((await notesOf(a, 'tournament_partner_expired')).length, 1);
});

test('lazy expiry: an accepting partner is not blocked by an expired offer holding the last spot', async () => {
  const t = await tournament();
  const cat = await category(t, { kind: 'pairs', cap: 1 });
  const [a, ap, w, wp, b, bp] = await Promise.all(['A', 'AP', 'W', 'WP', 'B', 'BP'].map((x) => player(x)));
  const ra = await register(a, cat, ap);
  await respond(ap, ra.id, true);
  const jw = await joinWaitlist(w, cat, wp, later(0, 1));
  await respond(wp, jw.id, true, later(0, 2));
  await cancel(a, ra.id, later(1));
  assert.equal(await statusOf(jw.id), 'offered');
  const rb = await register(b, cat, bp, later(24, 30));
  // W's offer ran out at later(25): BP's accept takes the spot.
  assert.equal((await respond(bp, rb.id, true, later(25, 1))).status, 'registered');
  assert.equal(await statusOf(jw.id), 'lapsed');
});

test('accepting re-checks both players\' levels', async () => {
  const t = await tournament();
  const cat = await category(t, { kind: 'pairs', cap: 2, min: 2, max: 4 });
  const a = await player('A', { padel: 3 });
  const p = await player('P', { padel: 3 });
  const r = await register(a, cat, p);
  await pool.query(`update player_levels set level = 5 where user_id = $1`, [p]);
  assert.equal(await errorOf(respond(p, r.id, true)), 'level_out_of_range');
  await pool.query(`update player_levels set level = 3 where user_id = $1`, [p]);
  await pool.query(`update player_levels set level = 1 where user_id = $1`, [a]);
  assert.equal(await errorOf(respond(p, r.id, true)), 'level_out_of_range');
  assert.equal(await statusOf(r.id), 'pending_partner');
});

test('an unconfirmed waitlisted pair expires after 48 hours and is reminded before the deadline', async () => {
  const t = await tournament({ deadline: tashkent('2026-11-24', 12) });
  const cat = await category(t, { kind: 'pairs', cap: 1 });
  const [a, ap, b, bp] = await Promise.all(['A', 'AP', 'B', 'BP'].map((x) => player(x)));
  const ra = await register(a, cat, ap);
  await respond(ap, ra.id, true);
  const wb = await joinWaitlist(b, cat, bp);
  // 48 hours from now is after the deadline: the invite runs to the deadline.
  assert.equal(wb.partner_expires_local, '2026-11-24T12:00:00');
  await expire(tashkent('2026-11-23', 13));
  assert.equal((await notesOf(b, 'tournament_deadline_reminder')).length, 1);
  await expire(tashkent('2026-11-24', 12, 1));
  assert.equal(await statusOf(wb.id), 'expired');
  const notes = await notesOf(b, 'tournament_partner_expired');
  assert.equal(notes.length, 1);
  assert.equal(notes[0].payload.registration_id, wb.id);
});

test('an unconfirmed waitlisted pair cannot be accepted after 48 hours', async () => {
  const t = await tournament();
  const cat = await category(t, { kind: 'pairs', cap: 1 });
  const [a, ap, b, bp] = await Promise.all(['A', 'AP', 'B', 'BP'].map((x) => player(x)));
  const ra = await register(a, cat, ap);
  await respond(ap, ra.id, true);
  const wb = await joinWaitlist(b, cat, bp);
  assert.equal(wb.partner_expires_local, '2026-11-24T20:00:00');
  assert.equal(await errorOf(respond(bp, wb.id, true, later(48, 1))), 'not_found');
  assert.equal(await expire(later(48, 1)), 1);
  assert.equal(await statusOf(wb.id), 'expired');
});

test('waitlist_place counts only entries that can be offered', async () => {
  const t = await tournament();
  const cat = await category(t, { kind: 'pairs', cap: 1 });
  const [a, ap, b, bp, c, cp] = await Promise.all(['A', 'AP', 'B', 'BP', 'C', 'CP'].map((x) => player(x)));
  const ra = await register(a, cat, ap);
  await respond(ap, ra.id, true);
  const wb = await joinWaitlist(b, cat, bp, later(0, 1));
  const wc = await joinWaitlist(c, cat, cp, later(0, 2));
  assert.equal(wb.waitlist_place, null);
  const confirmed = await respond(cp, wc.id, true, later(0, 3));
  // B joined first but is still waiting on its partner: C is next in line.
  assert.equal(confirmed.waitlist_place, 1);
  const b2 = await respond(bp, wb.id, true, later(0, 4));
  assert.equal(b2.waitlist_place, 1);
  const view = await one(`select app.registration_json(r) as r from tournament_registrations r where r.id = $1`, [wc.id]);
  assert.equal(view.r.waitlist_place, 2);
});

test('cancel and claim on an inactive tournament get not_found', async () => {
  const t = await tournament();
  const cat = await category(t, { cap: 1 });
  const [a, w] = [await player('A'), await player('W')];
  const ra = await register(a, cat);
  const jw = await joinWaitlist(w, cat);
  const rb = await register(await player('B'), await category(t, { cap: 2, name: 'Other' }));
  await cancel(a, ra.id, later(1));
  await pool.query(`update tournaments set active = false where id = $1`, [t]);
  assert.equal(await errorOf(claim(w, jw.id, later(2))), 'not_found');
  assert.equal(await errorOf(cancel(rb.registrant.id, rb.id, later(2))), 'not_found');
  assert.equal(await statusOf(jw.id), 'offered');
  assert.equal(await statusOf(rb.id), 'registered');
});

test('unknown entries: respond, cancel and claim all get not_found', async () => {
  const a = await player('A');
  const id = randomUUID();
  assert.equal(await errorOf(respond(a, id, true)), 'not_found');
  assert.equal(await errorOf(cancel(a, id)), 'not_found');
  assert.equal(await errorOf(claim(a, id)), 'not_found');
});

// --- waitlist and offers -----------------------------------------------------

test('cancel frees the spot and offers it to the first waitlisted player', async () => {
  const t = await tournament();
  const cat = await category(t, { cap: 2 });
  const [a, b, w1, w2] = [await player('A'), await player('B'), await player('W1'), await player('W2')];
  const ra = await register(a, cat);
  await register(b, cat);
  const j1 = await joinWaitlist(w1, cat, null, later(0, 1));
  const j2 = await joinWaitlist(w2, cat, null, later(0, 2));
  assert.equal(j1.status, 'waitlisted');
  assert.equal(j1.waitlist_place, 1);
  assert.equal(j2.waitlist_place, 2);
  assert.equal((await catView(cat)).waitlist_count, 2);

  const cancelled = await cancel(a, ra.id, later(1));
  assert.equal(cancelled.status, 'cancelled');
  assert.equal(await statusOf(j1.id), 'offered');
  assert.equal(await statusOf(j2.id), 'waitlisted');
  const view = await catView(cat);
  assert.equal(view.filled, 2);
  assert.equal(view.waitlist_count, 1);

  const offers = await notesOf(w1, 'tournament_spot_offered');
  assert.equal(offers.length, 1);
  assert.equal(offers[0].category, 'tournaments');
  assert.equal(offers[0].payload.registration_id, j1.id);
  assert.equal(offers[0].payload.offer_expires_local, '2026-11-23T21:00:00');

  // The offer holds the spot: a newcomer cannot register past it.
  const newcomer = await player('Newcomer');
  assert.equal(await errorOf(register(newcomer, cat, null, later(1, 30))), 'full');

  // The offer is the player's own: nobody else claims it, they do.
  assert.equal(await errorOf(claim(w2, j1.id, later(2))), 'not_found');
  const claimed = await claim(w1, j1.id, later(2));
  assert.equal(claimed.status, 'registered');
  assert.equal((await catView(cat)).filled, 2);
  assert.equal(await errorOf(claim(w1, j1.id, later(2))), 'not_found');
});

test('an unclaimed offer lapses after 24 hours and passes to the next player', async () => {
  const t = await tournament();
  const cat = await category(t, { cap: 1 });
  const [a, w1, w2] = [await player('A'), await player('W1'), await player('W2')];
  const ra = await register(a, cat);
  const j1 = await joinWaitlist(w1, cat, null, later(0, 1));
  const j2 = await joinWaitlist(w2, cat, null, later(0, 2));
  await cancel(a, ra.id, later(1));
  assert.equal(await statusOf(j1.id), 'offered');

  // Not yet: one minute before the end of the window nothing changes.
  await expire(later(24, 59));
  assert.equal(await statusOf(j1.id), 'offered');
  // Past the window, the claim is refused even before the job runs.
  assert.equal(await errorOf(claim(w1, j1.id, later(25, 1))), 'not_found');

  assert.equal(await expire(later(25, 1)), 1);
  assert.equal(await statusOf(j1.id), 'lapsed');
  assert.equal(await statusOf(j2.id), 'offered');
  assert.equal((await notesOf(w2, 'tournament_spot_offered')).length, 1);
  assert.equal((await catView(cat)).filled, 1);
});

test('join_waitlist: only when full and enabled, same checks as register', async () => {
  const t = await tournament();
  const cat = await category(t, { cap: 1 });
  const closed = await category(t, { cap: 1, waitlist: false, name: 'Closed' });
  const [a, b, c] = [await player('A'), await player('B'), await player('C')];
  assert.equal(await errorOf(joinWaitlist(a, cat)), 'not_full');
  await register(a, cat);
  await register(a, closed);
  assert.equal(await errorOf(joinWaitlist(a, cat)), 'already_registered');
  assert.equal(await errorOf(joinWaitlist(b, closed)), 'waitlist_closed');
  await joinWaitlist(b, cat);
  assert.equal(await errorOf(joinWaitlist(b, cat)), 'already_registered');
  assert.equal(await errorOf(joinWaitlist(c, cat, null, tashkent('2026-12-10', 0))), 'deadline_passed');
});

test('a waitlisted pair is offered only once the partner confirms', async () => {
  const t = await tournament();
  const cat = await category(t, { kind: 'pairs', cap: 1 });
  const [a, ap, b, bp, c, cp] = await Promise.all(['A', 'AP', 'B', 'BP', 'C', 'CP'].map((n) => player(n)));
  const ra = await register(a, cat, ap);
  await respond(ap, ra.id, true);
  const wb = await joinWaitlist(b, cat, bp, later(0, 1));
  const wc = await joinWaitlist(c, cat, cp, later(0, 2));
  assert.equal(wb.status, 'waitlisted');
  assert.equal(wb.partner_confirmed, false);
  assert.equal((await notesOf(bp, 'tournament_partner_invite')).length, 1);
  await respond(cp, wc.id, true, later(0, 3));
  assert.equal(await statusOf(wc.id), 'waitlisted');

  // B's partner has not confirmed: the spot goes to C, B keeps their place.
  await cancel(ap, ra.id, later(1));
  assert.equal(await statusOf(wb.id), 'waitlisted');
  assert.equal(await statusOf(wc.id), 'offered');
  assert.equal((await notesOf(c, 'tournament_spot_offered')).length, 1);
  assert.equal((await notesOf(cp, 'tournament_spot_offered')).length, 1);

  // The partner claims for both.
  assert.equal((await claim(cp, wc.id, later(2))).status, 'registered');

  // B's partner declines: the entry ends.
  assert.equal((await respond(bp, wb.id, false, later(3))).status, 'declined');
  assert.equal((await notesOf(b, 'tournament_partner_declined')).length, 1);
});

test('a confirmation that arrives while a spot is free takes the offer at once', async () => {
  const t = await tournament();
  const cat = await category(t, { kind: 'pairs', cap: 1 });
  const [a, ap, b, bp] = await Promise.all(['A', 'AP', 'B', 'BP'].map((n) => player(n)));
  const ra = await register(a, cat, ap);
  await respond(ap, ra.id, true);
  const wb = await joinWaitlist(b, cat, bp, later(0, 1));
  await cancel(a, ra.id, later(1));
  assert.equal(await statusOf(wb.id), 'waitlisted');
  await respond(bp, wb.id, true, later(2));
  assert.equal(await statusOf(wb.id), 'offered');
});

test('after the deadline the job lapses offers but offers nothing new', async () => {
  const t = await tournament({ deadline: tashkent('2026-11-23', 12) });
  const cat = await category(t, { cap: 1 });
  const [a, w1, w2] = [await player('A'), await player('W1'), await player('W2')];
  const ra = await register(a, cat);
  const j1 = await joinWaitlist(w1, cat, null, later(0, 1));
  const j2 = await joinWaitlist(w2, cat, null, later(0, 2));
  await cancel(a, ra.id, later(1));
  assert.equal(await statusOf(j1.id), 'offered');
  // The window ends at the deadline, not 24 hours later.
  assert.equal((await notesOf(w1, 'tournament_spot_offered'))[0].payload.offer_expires_local, '2026-11-23T12:00:00');

  await expire(tashkent('2026-11-23', 12, 1));
  assert.equal(await statusOf(j1.id), 'lapsed');
  assert.equal(await statusOf(j2.id), 'waitlisted');
  assert.equal((await notesOf(w2, 'tournament_spot_offered')).length, 0);
  assert.equal((await one(`select app.offer_next($1, $2) as n`, [cat, tashkent('2026-11-23', 13)])).n, 0);
  assert.equal(await statusOf(j2.id), 'waitlisted');
});

// --- pairs -------------------------------------------------------------------

test('pairs: a pending pair is not counted; only the partner answers; accept registers both', async () => {
  const t = await tournament();
  const cat = await category(t, { kind: 'pairs', cap: 2 });
  const [a, p, other] = [await player('A'), await player('P'), await player('Other')];
  const r = await register(a, cat, p);
  assert.equal(r.status, 'pending_partner');
  assert.deepEqual(r.partner, { id: p, name: 'P' });
  assert.equal(r.partner_expires_local, '2026-11-24T20:00:00');
  assert.equal((await catView(cat)).filled, 0);

  const invites = await notesOf(p, 'tournament_partner_invite');
  assert.equal(invites.length, 1);
  assert.equal(invites[0].category, 'invites');
  assert.equal(invites[0].payload.actor_name, 'A');
  assert.equal(invites[0].payload.registration_id, r.id);

  assert.equal(await errorOf(respond(other, r.id, true)), 'not_found');
  assert.equal(await errorOf(respond(a, r.id, true)), 'not_found');
  assert.equal(await statusOf(r.id), 'pending_partner');

  const accepted = await respond(p, r.id, true, later(1));
  assert.equal(accepted.status, 'registered');
  assert.equal((await catView(cat)).filled, 1);
  const forA = await tView(t, a);
  const forP = await tView(t, p);
  assert.equal(forA.my_registrations[0].status, 'registered');
  assert.equal(forP.my_registrations[0].status, 'registered');

  const acc = await notesOf(a, 'tournament_partner_accepted');
  assert.equal(acc.length, 1);
  assert.equal(acc[0].payload.actor_name, 'P');
  assert.equal((await notesOf(a, 'tournament_registered')).length, 1);
  assert.equal((await notesOf(p, 'tournament_registered')).length, 1);
  assert.equal(await errorOf(respond(p, r.id, true)), 'not_found');
});

test('pairs: partner required, not self, not already in; accept when full gets full', async () => {
  const t = await tournament();
  const cat = await category(t, { kind: 'pairs', cap: 1 });
  const [a, ap, b, bp] = [await player('A'), await player('AP'), await player('B'), await player('BP')];
  assert.equal(await errorOf(register(a, cat)), 'invalid_argument');
  assert.equal(await errorOf(register(a, cat, a)), 'invalid_argument');
  assert.equal(await errorOf(register(a, cat, randomUUID())), 'not_found');
  const ra = await register(a, cat, ap);
  const rb = await register(b, cat, bp);
  await respond(ap, ra.id, true);
  assert.equal(await errorOf(respond(bp, rb.id, true)), 'full');
  assert.equal(await statusOf(rb.id), 'pending_partner');
  // The pair can move to the waitlist: the pending entry must go first.
  assert.equal(await errorOf(joinWaitlist(b, cat, bp)), 'already_registered');
  await cancel(b, rb.id);
  assert.equal((await joinWaitlist(b, cat, bp)).status, 'waitlisted');
  // A confirmed partner is in the category: nobody else can name them.
  const c = await player('C');
  assert.equal(await errorOf(register(c, cat, ap)), 'partner_unavailable');
});

test('a pending invite does not stop the named partner from registering on their own', async () => {
  const t = await tournament();
  const cat = await category(t, { kind: 'pairs', cap: 4 });
  const [a, p, q] = [await player('A'), await player('P'), await player('Q')];
  const ra = await register(a, cat, p);
  const rp = await register(p, cat, q);
  assert.equal(rp.status, 'pending_partner');
  await respond(q, rp.id, true);
  // P is now in the category with Q, so accepting A's invite is refused.
  assert.equal(await errorOf(respond(p, ra.id, true)), 'partner_unavailable');
  assert.equal(await statusOf(ra.id), 'pending_partner');
});

test('a confirmed partner cannot register separately in that category', async () => {
  const t = await tournament();
  const cat = await category(t, { kind: 'pairs', cap: 4 });
  const singles = await category(t, { cap: 4, name: 'Singles' });
  const [a, p, q] = [await player('A'), await player('P'), await player('Q')];
  const ra = await register(a, cat, p);
  await respond(p, ra.id, true);
  assert.equal(await errorOf(register(p, cat, q)), 'already_registered');
  // Another category is fine.
  assert.equal((await register(p, singles)).status, 'registered');
});

test('a pending pair expires after 48 hours; the registrant is told', async () => {
  const t = await tournament();
  const cat = await category(t, { kind: 'pairs', cap: 2 });
  const [a, p] = [await player('A'), await player('P')];
  const r = await register(a, cat, p);
  assert.equal(await expire(later(47, 59)), 0);
  assert.equal(await statusOf(r.id), 'pending_partner');
  // Past the expiry the partner cannot accept, even before the job runs.
  assert.equal(await errorOf(respond(p, r.id, true, later(48, 1))), 'not_found');
  assert.equal(await expire(later(48, 1)), 1);
  assert.equal(await statusOf(r.id), 'expired');
  const notes = await notesOf(a, 'tournament_partner_expired');
  assert.equal(notes.length, 1);
  assert.equal(notes[0].payload.registration_id, r.id);
  // The registrant can start again.
  assert.equal((await register(a, cat, p, later(49))).status, 'pending_partner');
});

test('a pending pair close to the deadline is reminded once', async () => {
  const t = await tournament({ deadline: tashkent('2026-11-23', 12) });
  const cat = await category(t, { kind: 'pairs', cap: 2 });
  const [a, p, b, q] = [await player('A'), await player('P'), await player('B'), await player('Q')];
  const early = await register(a, cat, p, tashkent('2026-11-22', 8));
  // Invited inside the last 24 hours: already close, no separate reminder.
  await register(b, cat, q, tashkent('2026-11-22', 13));
  assert.equal(early.partner_expires_local, '2026-11-23T12:00:00');
  await expire(tashkent('2026-11-22', 11));
  assert.equal((await notesOf(a, 'tournament_deadline_reminder')).length, 0);
  await expire(tashkent('2026-11-22', 13));
  await expire(tashkent('2026-11-22', 14));
  const notes = await notesOf(a, 'tournament_deadline_reminder');
  assert.equal(notes.length, 1);
  assert.equal(notes[0].payload.registration_id, early.id);
  assert.equal((await notesOf(b, 'tournament_deadline_reminder')).length, 0);
});

// --- cancellation and the deadline ----------------------------------------------

test('cancel: registrant or confirmed partner only, live entries only', async () => {
  const t = await tournament();
  const cat = await category(t, { kind: 'pairs', cap: 2 });
  const [a, p, other] = [await player('A'), await player('P'), await player('Other')];
  const r = await register(a, cat, p);
  assert.equal(await errorOf(cancel(other, r.id)), 'not_found');
  // An invited partner declines instead.
  assert.equal(await errorOf(cancel(p, r.id)), 'not_found');
  await respond(p, r.id, true);
  assert.equal((await cancel(p, r.id)).status, 'cancelled');
  assert.equal(await errorOf(cancel(a, r.id)), 'not_found');

  // A singles entry has no partner: still nobody else's to cancel.
  const singles = await category(t, { cap: 2, name: 'Singles' });
  const rs = await register(a, singles);
  assert.equal(await errorOf(cancel(other, rs.id)), 'not_found');
  assert.equal(await statusOf(rs.id), 'registered');
});

test('cancelling a pair tells the other player: partner_cancelled with the canceller\'s name', async () => {
  const t = await tournament();
  const [a, p] = [await player('A'), await player('P')];
  const check = async (to, reg, actor) => {
    const notes = await notesOf(to, 'tournament_partner_cancelled');
    assert.equal(notes.length, 1);
    assert.equal(notes[0].category, 'tournaments');
    assert.equal(notes[0].payload.registration_id, reg.id);
    assert.equal(notes[0].payload.tournament_id, t);
    assert.equal(notes[0].payload.category_id, reg.category_id);
    assert.equal(notes[0].payload.actor_name, actor);
    assert.equal(notes[0].payload.title.en, 'Cup');
    assert.equal(notes[0].payload.category_name.en, reg.category_name.en);
    await pool.query('delete from notifications');
  };

  // A registered pair: the partner cancels, the registrant is told.
  const registered = await category(t, { kind: 'pairs', cap: 2, name: 'Registered' });
  const r1 = await register(a, registered, p);
  await respond(p, r1.id, true);
  await pool.query('delete from notifications');
  await cancel(p, r1.id, later(1));
  await check(a, r1, 'P');
  assert.equal((await notesOf(p, 'tournament_partner_cancelled')).length, 0);

  // A pending pair: the registrant cancels, the invited partner is told.
  const pending = await category(t, { kind: 'pairs', cap: 2, name: 'Pending' });
  const r2 = await register(a, pending, p);
  await pool.query('delete from notifications');
  await cancel(a, r2.id, later(1));
  await check(p, r2, 'A');

  // A waitlisted pair (confirmed) and an offered pair: either side cancels.
  const full = await category(t, { kind: 'pairs', cap: 1, name: 'Full' });
  const [x, xp] = [await player('X'), await player('XP')];
  const rx = await register(x, full, xp);
  await respond(xp, rx.id, true);
  const w = await joinWaitlist(a, full, p, later(0, 1));
  await respond(p, w.id, true, later(0, 2));
  await pool.query('delete from notifications');
  await cancel(a, w.id, later(1));
  await check(p, w, 'A');

  const w2 = await joinWaitlist(a, full, p, later(2));
  await respond(p, w2.id, true, later(2, 1));
  await cancel(x, rx.id, later(3));
  assert.equal(await statusOf(w2.id), 'offered');
  await pool.query('delete from notifications');
  await cancel(p, w2.id, later(4));
  await check(a, w2, 'P');

  // Singles: nobody else to tell.
  const singles = await category(t, { cap: 2, name: 'Singles' });
  const rs = await register(a, singles);
  await cancel(a, rs.id, later(5));
  assert.equal((await pool.query(`select count(*)::int as n from notifications where kind = 'tournament_partner_cancelled'`)).rows[0].n, 0);
});

test('after the deadline: register, cancel and respond are refused', async () => {
  const t = await tournament({ deadline: tashkent('2026-11-23', 12) });
  const singles = await category(t, { cap: 4 });
  const pairs = await category(t, { kind: 'pairs', cap: 4, name: 'Pairs' });
  const [a, b, p] = [await player('A'), await player('B'), await player('P')];
  const ra = await register(a, singles);
  const rp = await register(b, pairs, p);
  const late = tashkent('2026-11-23', 12);
  const c = await player('C');
  assert.equal(await errorOf(register(c, singles, null, late)), 'deadline_passed');
  assert.equal(await errorOf(cancel(a, ra.id, late)), 'deadline_passed');
  assert.equal(await errorOf(respond(p, rp.id, true, late)), 'deadline_passed');
  assert.equal(await statusOf(ra.id), 'registered');
});

// --- the tournament summary --------------------------------------------------------

test('slots_filled on the tournament follows register, accept, cancel and claim', async () => {
  const t = await tournament();
  const singles = await category(t, { cap: 1, fee: 50000 });
  const pairs = await category(t, { kind: 'pairs', cap: 3, fee: 80000, name: 'Pairs' });
  assert.deepEqual(await summary(t), { min_fee: 50000, max_fee: 80000, slots_total: 4, slots_filled: 0 });
  const [a, b, p] = [await player('A'), await player('B'), await player('P')];
  const ra = await register(a, singles);
  assert.equal((await summary(t)).slots_filled, 1);
  const rp = await register(b, pairs, p);
  assert.equal((await summary(t)).slots_filled, 1);
  await respond(p, rp.id, true);
  assert.equal((await summary(t)).slots_filled, 2);
  const w = await player('W');
  const jw = await joinWaitlist(w, singles);
  await cancel(a, ra.id, later(1));
  // The offer holds the spot.
  assert.equal((await summary(t)).slots_filled, 2);
  await claim(w, jw.id, later(2));
  assert.equal((await summary(t)).slots_filled, 2);
  await cancel(p, rp.id, later(3));
  assert.equal((await summary(t)).slots_filled, 1);
});

// --- views ----------------------------------------------------------------------

test('get_tournament shows the categories and only my own registrations', async () => {
  const t = await tournament({ title: 'Open Cup' });
  const singles = await category(t, { cap: 2, fee: 50000 });
  await category(t, { kind: 'pairs', cap: 4, fee: 70000, name: 'Pairs' });
  const [a, b] = [await player('A'), await player('B')];
  await register(a, singles);
  await register(b, singles);
  const view = await tView(t, a);
  assert.equal(view.title_en, 'Open Cup');
  assert.equal(view.starts_on, '2026-12-10');
  assert.equal(view.currency, 'UZS');
  assert.equal(view.fee_min, 50000);
  assert.equal(view.fee_max, 70000);
  assert.equal(view.categories.length, 2);
  assert.equal(view.categories[0].filled, 2);
  assert.equal(view.categories[0].full, true);
  assert.equal(view.my_registrations.length, 1);
  assert.deepEqual(view.my_registrations[0].registrant, { id: a, name: 'A' });
  assert.equal(JSON.stringify(view).includes(b), false);
});

test('get_tournament settles expired offers and invites first, so none shows as claimable', async () => {
  const t = await tournament();
  const singles = await category(t, { cap: 1, name: 'Singles' });
  const pairs = await category(t, { kind: 'pairs', cap: 2, name: 'Pairs' });
  const [a, w1, w2, b, bp] = await Promise.all(['A', 'W1', 'W2', 'B', 'BP'].map((n) => player(n)));
  const ra = await register(a, singles);
  const j1 = await joinWaitlist(w1, singles, null, later(0, 1));
  const j2 = await joinWaitlist(w2, singles, null, later(0, 2));
  await cancel(a, ra.id, later(1));
  assert.equal(await statusOf(j1.id), 'offered');
  const pending = await register(b, pairs, bp, later(1));

  const get = (user, when) => one(`select app.get_tournament($1, $2, $3) as t`, [user, t, when]).then((r) => r.t);
  // Before anything runs out, a read changes nothing.
  const early = await get(w1, later(2));
  assert.equal(early.my_registrations[0].status, 'offered');

  // 50 hours on: W1's offer and B's invite have run out; the job has not run.
  const view = await get(w1, later(51));
  assert.equal(await statusOf(j1.id), 'lapsed');
  assert.deepEqual(view.my_registrations, []);
  assert.equal(view.categories[0].my_status, null);
  assert.equal(await statusOf(j2.id), 'offered');
  assert.equal((await notesOf(w2, 'tournament_spot_offered')).length, 1);
  assert.equal(await statusOf(pending.id), 'expired');
  assert.equal((await notesOf(b, 'tournament_partner_expired')).length, 1);
  assert.equal((await get(w2, later(51))).my_registrations[0].status, 'offered');

  // An inactive tournament: null, and nothing is touched.
  await pool.query(`update tournaments set active = false where id = $1`, [t]);
  assert.equal(await get(w2, later(80)), null);
  assert.equal(await statusOf(j2.id), 'offered');
});

test('my_registrations: active tournaments only, each saying whether registration is open', async () => {
  const open = await tournament({ title: 'Open Cup' });
  const closed = await tournament({ title: 'Closed Cup', deadline: tashkent('2026-11-23', 12) });
  const hidden = await tournament({ title: 'Hidden Cup' });
  const p = await player('P');
  for (const t of [open, closed, hidden]) await register(p, await category(t, { cap: 2 }));
  await pool.query(`update tournaments set active = false where id = $1`, [hidden]);

  const mine = async (when) =>
    (await pool.query(`select app.my_registrations($1, $2) as r`, [p, when])).rows
      .map((r) => [r.r.tournament.title_en, r.r.tournament.registration_open])
      .sort();
  assert.deepEqual(await mine(later(1)), [
    ['Closed Cup', true],
    ['Open Cup', true],
  ]);
  assert.deepEqual(await mine(tashkent('2026-11-23', 12)), [
    ['Closed Cup', false],
    ['Open Cup', true],
  ]);
});

test('muting tournaments silences tournament notifications; invites follow the invites switch', async () => {
  const t = await tournament();
  const cat = await category(t, { kind: 'pairs', cap: 2 });
  const [a, p] = [await player('A'), await player('P')];
  await pool.query(`update profiles set muted_categories = array['tournaments'] where id = $1`, [a]);
  await pool.query(`update profiles set muted_categories = array['invites'] where id = $1`, [p]);
  const r = await register(a, cat, p);
  assert.equal((await notesOf(p, 'tournament_partner_invite')).length, 0);
  await respond(p, r.id, true);
  assert.equal((await notesOf(a)).length, 0);
  assert.equal((await notesOf(p, 'tournament_registered')).length, 1);
});

// --- finding a partner by phone, last seen ------------------------------------------

test('find_player_by_phone returns id and name only; at most 20 lookups an hour', async () => {
  const [me, them] = [await player('Me'), await player('Them')];
  await addPhone(pool, them, '+998901234567');
  const find = (phone, when = now) => one(`select app.find_player_by_phone($1, $2, $3) as r`, [me, phone, when]).then((r) => r.r);
  assert.deepEqual(await find('+998 (90) 123-45-67'), { id: them, name: 'Them' });
  assert.equal(await find('+998900000000'), null);
  assert.equal(await find('not a phone'), null);
  for (let i = 0; i < 17; i++) await find('+998900000000', later(0, 1));
  assert.equal(await errorOf(find('+998901234567', later(0, 30))), 'rate_limited');
  // An hour after the first lookups, room again.
  assert.deepEqual(await find('+998901234567', later(1, 0)), { id: them, name: 'Them' });
});

test('find_player_by_phone matches a number typed without its +, and does not block rows that reference the caller', async () => {
  const [me, them] = [await player('Me'), await player('Them')];
  await addPhone(pool, them, '+998905554433');
  const find = (phone) => one(`select app.find_player_by_phone($1, $2, $3) as r`, [me, phone, now]).then((r) => r.r);
  assert.deepEqual(await find('998905554433'), { id: them, name: 'Them' });
  assert.deepEqual(await find('998 90 555-44-33'), { id: them, name: 'Them' });
  assert.equal(await find('998900000000'), null);
  assert.equal(await find('12'), null);

  // Another transaction is writing a row that references my profile (a
  // registration): its key share lock must not make the lookup wait.
  const t = await tournament();
  const cat = await category(t, { cap: 4 });
  const other = await db.connect();
  try {
    await other.query('begin');
    await other.query(
      `insert into tournament_registrations (category_id, user_id, partner_confirmed, status, fee, currency)
       values ($1, $2, true, 'registered', 0, 'UZS')`,
      [cat, me],
    );
    const lookup = await db.connect();
    try {
      await lookup.query('begin');
      await lookup.query(`set local lock_timeout = '2s'`);
      const { rows } = await lookup.query(`select app.find_player_by_phone($1, '998905554433', $2) as r`, [me, now]);
      assert.deepEqual(rows[0].r, { id: them, name: 'Them' });
      await lookup.query('commit');
    } finally {
      lookup.release();
    }
    await other.query('rollback');
  } finally {
    other.release();
  }
});

test('touch_last_seen writes at most once an hour', async () => {
  const p = await player('P');
  const seen = () => one(`select last_seen_at from profiles where id = $1`, [p]).then((r) => r.last_seen_at?.toISOString() ?? null);
  await pool.query(`select app.touch_last_seen($1, $2)`, [p, now]);
  assert.equal(await seen(), new Date(now).toISOString());
  await pool.query(`select app.touch_last_seen($1, $2)`, [p, later(0, 30)]);
  assert.equal(await seen(), new Date(now).toISOString());
  await pool.query(`select app.touch_last_seen($1, $2)`, [p, later(1, 1)]);
  assert.equal(await seen(), later(1, 1));
  // Other players cannot read it.
  const other = await player('Other');
  await expectError(asUser(pool, other, (c) => c.query(`select last_seen_at from profiles`)), '42501');
});

// --- the API -----------------------------------------------------------------------

test('anon cannot execute any new public function; set_settings accepts tournaments', async () => {
  const id = randomUUID();
  const calls = [
    ['list_tournaments', ['tashkent']],
    ['get_tournament', [id]],
    ['register_tournament', [id, null]],
    ['respond_partner', [id, true]],
    ['cancel_registration', [id]],
    ['join_waitlist', [id, null]],
    ['claim_offer', [id]],
    ['my_registrations', []],
    ['find_player_by_phone', ['+998901234567']],
    ['touch_last_seen', []],
  ];
  const sql = (fn, args) => `select public.${fn}(${args.map((_, i) => `$${i + 1}`).join(', ')})`;
  for (const [fn, args] of calls) {
    await expectError(asAnon(pool, (c) => c.query(sql(fn, args), args)), '42501');
  }
  const p = await player('Api');
  await asUser(pool, p, (c) => c.query(`select public.set_settings(array['tournaments'], null)`));
  assert.deepEqual((await one(`select muted_categories from profiles where id = $1`, [p])).muted_categories, ['tournaments']);
  // No direct table access.
  for (const table of ['tournament_categories', 'tournament_registrations', 'phone_lookups']) {
    await expectError(asUser(pool, p, (c) => c.query(`select * from ${table}`)), '42501');
  }
});

test('through the API: list, get, register, my registrations, find by phone, last seen', async () => {
  // Real clock here: the wrappers pass now().
  const today = new Date(Date.now() + 5 * 3600 * 1000).toISOString().slice(0, 10);
  const inDays = (n) => new Date(Date.parse(today) + n * 86400000).toISOString().slice(0, 10);
  const soon = await tournament({ starts: inDays(10), ends: inDays(11), title: 'Zeta Cup' });
  const sooner = await tournament({ starts: inDays(5), ends: inDays(5), title: 'Alpha Cup' });
  const running = await tournament({ starts: inDays(-1), ends: today, title: 'Mid Cup' });
  const past = await tournament({ starts: inDays(-5), ends: inDays(-3), title: 'Old Cup' });
  const football = await tournament({ starts: inDays(7), sport: 'football', title: 'Ball Cup' });
  for (const t of [soon, sooner, running, past, football]) await category(t, { cap: 4 });
  const cat = (await one(`select id from tournament_categories where tournament_id = $1`, [soon])).id;

  const p = await player('Api player');
  const q = await player('Api partner');
  await addPhone(pool, q, '+998907777777');
  const rpc = (user, text, args = []) => asUser(pool, user, async (c) => (await c.query(text, args)).rows.map((r) => r.r));

  const byDate = await rpc(p, `select public.list_tournaments('tashkent') as r`);
  assert.deepEqual(byDate.map((t) => t.title_en), ['Mid Cup', 'Alpha Cup', 'Ball Cup', 'Zeta Cup']);
  const az = await rpc(p, `select public.list_tournaments('tashkent', null, null, 'az') as r`);
  assert.deepEqual(az.map((t) => t.title_en), ['Alpha Cup', 'Ball Cup', 'Mid Cup', 'Zeta Cup']);
  const padel = await rpc(p, `select public.list_tournaments('tashkent', 'padel', $1::date) as r`, [inDays(6)]);
  assert.deepEqual(padel.map((t) => t.title_en), ['Zeta Cup']);
  await expectError(rpc(p, `select public.list_tournaments('tashkent', null, null, 'price') as r`), 'invalid_argument');

  const [registered] = await rpc(p, `select public.register_tournament($1) as r`, [cat]);
  assert.equal(registered.status, 'registered');
  const [view] = await rpc(p, `select public.get_tournament($1) as r`, [soon]);
  assert.equal(view.my_registrations.length, 1);
  assert.equal(view.categories[0].filled, 1);
  const mine = await rpc(p, `select public.my_registrations() as r`);
  assert.equal(mine.length, 1);
  assert.equal(mine[0].tournament.id, soon);
  assert.equal(mine[0].tournament.title_en, 'Zeta Cup');
  assert.equal((await rpc(q, `select public.my_registrations() as r`)).length, 0);

  const [found] = await rpc(p, `select public.find_player_by_phone('+998907777777') as r`);
  assert.deepEqual(found, { id: q, name: 'Api partner' });
  await rpc(p, `select public.touch_last_seen() as r`);
  assert.ok((await one(`select last_seen_at from profiles where id = $1`, [p])).last_seen_at);

  const [cancelled] = await rpc(p, `select public.cancel_registration($1) as r`, [registered.id]);
  assert.equal(cancelled.status, 'cancelled');
  const [missing] = await rpc(p, `select public.get_tournament($1) as r`, [randomUUID()]);
  assert.equal(missing, null);
});
