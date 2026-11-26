// Milestone 5b: the admin tournament manager and the admin dashboard. As
// elsewhere, the `app` functions are called with the acting user and a fixed
// clock; the last tests go through the `public` wrappers as the API would.

import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { after, before, beforeEach, test } from 'node:test';
import { asAnon, asUser, createUser, errorOf, freshDb } from './helpers/db.mjs';
import { addAdmin, addCourt, addPhone, addVenue, tashkent } from './helpers/fixtures.mjs';

let db;
let pool;
let admin;
let venueId; // Tashkent
let almatyVenue;
let courtId; // at venueId
let almatyCourt;

// Sunday evening in Tashkent. Tournaments start on 10 December; registration
// closes at 00:00 that day unless a test sets its own deadline.
const now = tashkent('2026-11-22', 20);
const later = (hours) => new Date(Date.parse(now) + hours * 3600000).toISOString();

before(async () => {
  db = await freshDb('admin_tournaments');
  pool = db.pool;
  admin = await addAdmin(pool, await createUser(pool, 'Admin'));
  venueId = await addVenue(pool, { name: 'Tashkent venue' });
  almatyVenue = await addVenue(pool, { cityId: 'almaty', name: 'Almaty venue' });
  courtId = await addCourt(pool, venueId);
  almatyCourt = await addCourt(pool, almatyVenue);
});
after(() => db.end());

beforeEach(async () => {
  await pool.query('delete from audit_log');
  await pool.query('delete from notifications');
  await pool.query('delete from tournament_registrations');
  await pool.query('delete from tournament_categories');
  await pool.query('delete from tournaments');
  await pool.query('delete from games');
  await pool.query('delete from bookings');
});

const json = (value) => (value === null || typeof value === 'string' ? value : JSON.stringify(value));
const one = async (sql, params) => (await pool.query(sql, params)).rows[0];
const scalar = async (sql, params) => (await one(sql, params))?.r;
const list = async (sql, params) => (await pool.query(sql, params)).rows.map((row) => row.r);

const saveTournament = (user, t, when = now) => scalar(`select app.admin_save_tournament($1, $2::jsonb, $3) as r`, [user, json(t), when]);
const saveCategory = (user, c, when = now) => scalar(`select app.admin_save_category($1, $2::jsonb, $3) as r`, [user, json(c), when]);
const deleteCategory = (user, id, when = now) => scalar(`select app.admin_delete_category($1, $2, $3) as r`, [user, id, when]);
const listTournaments = (user, when = now) => list(`select app.admin_list_tournaments($1, $2) as r`, [user, when]);
const listRegistrations = (user, id) => list(`select app.admin_list_registrations($1, $2) as r`, [user, id]);
const aj = (sql, params) => scalar(`select app.admin_registration_json(${sql}) as r`, params);
const setPaid = (user, id, paid, when = now) => aj(`app.admin_set_paid($1, $2, $3, $4)`, [user, id, paid, when]);
const removeReg = (user, id, when = now) => aj(`app.admin_remove_registration($1, $2, $3)`, [user, id, when]);
const moveReg = (user, id, cat, when = now) => aj(`app.admin_move_registration($1, $2, $3, $4)`, [user, id, cat, when]);
const addReg = (user, cat, target, partner = null, when = now) =>
  aj(`app.admin_add_registration($1, $2, $3, $4, $5)`, [user, cat, target, partner, when]);
const offerNext = (user, cat, when = now) => scalar(`select app.admin_offer_next($1, $2, $3) as r`, [user, cat, when]);
const dashboard = (user, city, from, to, when = now) =>
  scalar(`select app.admin_dashboard($1, $2, $3, $4, $5) as r`, [user, city, from, to, when]);

// Task 1's player calls.
const rj = (sql, params) => scalar(`select app.registration_json(${sql}) as r`, params);
const register = (user, cat, partner = null, when = now) => rj(`app.register($1, $2, $3, $4)`, [user, cat, partner, when]);
const respond = (user, id, accept, when = now) => rj(`app.respond_partner($1, $2, $3, $4)`, [user, id, accept, when]);
const cancel = (user, id, when = now) => rj(`app.cancel_registration($1, $2, $3)`, [user, id, when]);
const joinWaitlist = (user, cat, partner = null, when = now) => rj(`app.join_waitlist($1, $2, $3, $4)`, [user, cat, partner, when]);
const claim = (user, id, when = now) => rj(`app.claim_offer($1, $2, $3)`, [user, id, when]);

const statusOf = (id) => one(`select status from tournament_registrations where id = $1`, [id]).then((r) => r.status);
const summary = (id) => one(`select min_fee, max_fee, slots_total, slots_filled from tournaments where id = $1`, [id]);
const auditRows = async () => (await pool.query(`select actor_id, action, entity, entity_id, before, after from audit_log order by id`)).rows;
const auditCount = async () => Number((await one(`select count(*) as n from audit_log`)).n);
const notesOf = (user, kind) =>
  pool.query(`select * from notifications where user_id = $1 and kind = $2 order by created_at, id`, [user, kind]).then((r) => r.rows);

async function player(name, { levels = {}, phone = null, city = 'tashkent' } = {}) {
  const id = await createUser(pool, name);
  await pool.query(`update profiles set city_id = $2 where id = $1`, [id, city]);
  for (const [sportId, level] of Object.entries(levels)) {
    await pool.query(`insert into player_levels (user_id, sport_id, level) values ($1, $2, $3)`, [id, sportId, level]);
  }
  if (phone) await addPhone(pool, id, phone);
  return id;
}

const cat = (fields = {}) => ({ name_en: 'Open', name_ru: 'Открытая', name_uz: 'Ochiq', kind: 'singles', cap: 2, fee: 100000, ...fields });

/** A tournament made by the admin with the given categories; returns { t, cats }. */
async function adminTournament({ city = 'tashkent', venue = venueId, deadline, categories = [cat()], starts = '2026-12-10', ends = starts } = {}) {
  const payload = {
    city_id: city,
    sport_id: 'padel',
    venue_id: venue,
    title_en: 'Cup',
    title_ru: 'Кубок',
    starts_on: starts,
    ends_on: ends,
    categories,
  };
  if (deadline !== undefined) payload.registration_deadline_local = deadline;
  const t = await saveTournament(admin, payload);
  const cats = (await pool.query(`select id from tournament_categories where tournament_id = $1 order by sort_order, created_at, id`, [t])).rows.map(
    (r) => r.id,
  );
  return { t, cats };
}

// --- tournaments --------------------------------------------------------------------

test('admin creates a tournament with two categories; the list and the summary columns follow them', async () => {
  const { t, cats } = await adminTournament({
    deadline: '2026-12-09T18:00:00',
    categories: [cat({ fee: 80000, cap: 8 }), cat({ name_en: 'Pairs', kind: 'pairs', fee: 150000, cap: 4, min_level: 2, max_level: 4 })],
  });
  assert.equal(cats.length, 2);
  assert.deepEqual(await summary(t), { min_fee: 80000, max_fee: 150000, slots_total: 12, slots_filled: 0 });

  const row = (await listTournaments(admin)).find((x) => x.id === t);
  assert.equal(row.fee_min, 80000);
  assert.equal(row.fee_max, 150000);
  assert.equal(row.slots_total, 12);
  assert.equal(row.slots_filled, 0);
  assert.equal(row.category_count, 2);
  assert.equal(row.registration_deadline_local, '2026-12-09T18:00:00');
  assert.equal(row.currency, 'UZS');
  assert.equal(row.active, true);
  assert.deepEqual(
    row.categories.map((c) => [c.name_en, c.kind, c.fee, c.cap, c.min_level, c.max_level]),
    [
      ['Open', 'singles', 80000, 8, 1, 5],
      ['Pairs', 'pairs', 150000, 4, 2, 4],
    ],
  );

  // One audit row for the whole create.
  const audit = await auditRows();
  assert.equal(audit.length, 1);
  assert.deepEqual([audit[0].actor_id, audit[0].action, audit[0].entity, audit[0].entity_id], [admin, 'create_tournament', 'tournament', t]);
  assert.equal(audit[0].before, null);
  assert.equal(audit[0].after.title_en, 'Cup');
  assert.equal(audit[0].after.categories.length, 2);

  // Inactive tournaments are listed too, newest (latest start) first.
  const { t: t2 } = await adminTournament({ starts: '2027-01-10' });
  await saveTournament(admin, { id: t2, active: false });
  const ids = (await listTournaments(admin)).map((x) => x.id);
  assert.deepEqual(ids, [t2, t]);
});

test('a tournament created without categories gets one open singles category', async () => {
  const t = await saveTournament(admin, { city_id: 'tashkent', sport_id: 'padel', title_en: 'Plain', starts_on: '2026-12-10', ends_on: '2026-12-10' });
  const cats = (await pool.query(`select * from tournament_categories where tournament_id = $1`, [t])).rows;
  assert.equal(cats.length, 1);
  assert.deepEqual(
    [cats[0].name_en, cats[0].name_ru, cats[0].name_uz, cats[0].name_kk, cats[0].kind, cats[0].gender, cats[0].fee, cats[0].cap, cats[0].min_level, cats[0].max_level],
    ['Open', 'Открытая', 'Ochiq', 'Ашық', 'singles', 'open', 0, 16, 1, 5],
  );
  assert.deepEqual(await summary(t), { min_fee: 0, max_fee: 0, slots_total: 16, slots_filled: 0 });
  const row = await one(`select * from tournaments where id = $1`, [t]);
  // No deadline given: 00:00 venue time on the first day.
  assert.equal(row.registration_deadline.toISOString(), new Date('2026-12-10T00:00:00+05:00').toISOString());
  assert.equal(row.venue_id, null);
  assert.equal(row.active, true);
  assert.equal(await auditCount(), 1);
  // Players can register in it right away.
  const p = await player('P');
  assert.equal((await register(p, cats[0].id)).status, 'registered');
});

test('saving a tournament checks the city, venue, dates, deadline and keys', async () => {
  const base = { city_id: 'tashkent', sport_id: 'padel', title_en: 'Cup', starts_on: '2026-12-10', ends_on: '2026-12-11' };
  const bad = [
    { ...base, venue_id: almatyVenue }, // venue in another city
    { ...base, venue_id: randomUUID() },
    { ...base, city_id: 'nowhere' },
    { ...base, sport_id: 'chess' },
    { ...base, ends_on: '2026-12-09' },
    { ...base, starts_on: '2026-13-01' },
    { ...base, title_en: null },
    { ...base, registration_deadline_local: '2026-12-12T00:00:01' }, // after the end of ends_on
    { ...base, registration_deadline_local: 'tomorrow' },
    { ...base, slots_total: 10 }, // computed, never written
    { ...base, unknown: 1 },
    { ...base, categories: [] },
    { ...base, categories: [{ name_en: 'X', kind: 'triples', cap: 2 }] },
    { ...base, categories: [{ name_en: 'X', kind: 'singles', cap: 0 }] },
    { ...base, cover_url: 'http://insecure.example/x.png' },
    { city_id: 'tashkent', sport_id: 'padel', title_en: 'No dates' },
  ];
  for (const t of bad) assert.equal(await errorOf(saveTournament(admin, t)), 'invalid_argument', JSON.stringify(t));
  assert.equal(await auditCount(), 0);

  // The last moment of ends_on is fine.
  const t = await saveTournament(admin, { ...base, registration_deadline_local: '2026-12-12T00:00:00', cover_url: 'https://img.example/c.png', color_seed: 7 });
  const row = await one(`select * from tournaments where id = $1`, [t]);
  assert.equal(row.cover_url, 'https://img.example/c.png');
  assert.equal(row.color_seed, 7);

  // Update: only the keys given; categories cannot be sent on update.
  assert.equal(await errorOf(saveTournament(admin, { id: t, categories: [cat()] })), 'invalid_argument');
  assert.equal(await errorOf(saveTournament(admin, { id: randomUUID(), title_en: 'X' })), 'not_found');
  await saveTournament(admin, { id: t, title_en: 'Renamed', description_en: 'About' });
  const updated = await one(`select * from tournaments where id = $1`, [t]);
  assert.equal(updated.title_en, 'Renamed');
  assert.equal(updated.description_en, 'About');
  assert.equal(updated.registration_deadline.toISOString(), row.registration_deadline.toISOString());
  const audit = (await auditRows()).at(-1);
  assert.equal(audit.action, 'update_tournament');
  assert.equal(audit.before.title_en, 'Cup');
  assert.equal(audit.after.title_en, 'Renamed');

  // A city with registrations cannot change (fees are locked in its currency).
  const p = await player('P');
  const catId = (await one(`select id from tournament_categories where tournament_id = $1`, [t])).id;
  await register(p, catId);
  assert.equal(await errorOf(saveTournament(admin, { id: t, city_id: 'almaty' })), 'has_registrations');
});

// --- categories ----------------------------------------------------------------------

test('categories: create, cap never below the count, a raised cap offers the waitlist, kind locked once used', async () => {
  const { t, cats } = await adminTournament({ categories: [cat({ cap: 2 })] });
  const [c1] = cats;

  const c2 = await saveCategory(admin, { tournament_id: t, name_en: 'Women', gender: 'women', kind: 'singles', cap: 4, fee: 50000 });
  assert.deepEqual(await summary(t), { min_fee: 50000, max_fee: 100000, slots_total: 6, slots_filled: 0 });
  const created = await one(`select * from tournament_categories where id = $1`, [c2]);
  assert.deepEqual([created.gender, created.min_level, created.max_level, created.waitlist_enabled, created.sort_order], ['women', 1, 5, true, 1]);

  const [a, b, w1, w2] = [await player('A'), await player('B'), await player('W1'), await player('W2')];
  await register(a, c1);
  await register(b, c1);
  const wl1 = await joinWaitlist(w1, c1);
  const wl2 = await joinWaitlist(w2, c1);

  await pool.query('delete from audit_log');
  assert.equal(await errorOf(saveCategory(admin, { id: c1, cap: 1 })), 'invalid_argument');
  assert.equal(await errorOf(saveCategory(admin, { id: c1, kind: 'pairs' })), 'has_registrations');
  assert.equal(await errorOf(saveCategory(admin, { id: c1, tournament_id: randomUUID() })), 'invalid_argument');
  assert.equal(await errorOf(saveCategory(admin, { id: c1, min_level: 4, max_level: 2 })), 'invalid_argument');
  assert.equal(await errorOf(saveCategory(admin, { tournament_id: randomUUID(), name_en: 'X', kind: 'singles', cap: 2 })), 'invalid_argument');
  assert.equal(await errorOf(saveCategory(admin, { tournament_id: t, name_en: 'X', cap: 2 })), 'invalid_argument'); // no kind
  assert.equal(await auditCount(), 0);

  // Raising the cap by one offers the first waitlisted entry; one audit row.
  await saveCategory(admin, { id: c1, cap: 3, fee: 120000 });
  assert.equal(await statusOf(wl1.id), 'offered');
  assert.equal(await statusOf(wl2.id), 'waitlisted');
  assert.equal((await notesOf(w1, 'tournament_spot_offered')).length, 1);
  assert.deepEqual(await summary(t), { min_fee: 50000, max_fee: 120000, slots_total: 7, slots_filled: 3 });
  const audit = await auditRows();
  assert.equal(audit.length, 1);
  assert.deepEqual([audit[0].action, audit[0].entity, audit[0].entity_id, audit[0].before.cap, audit[0].after.cap], ['update_category', 'tournament_category', c1, 2, 3]);
  // Fees already locked stay.
  assert.equal((await one(`select fee from tournament_registrations where user_id = $1`, [a])).fee, 100000);

  // The cap can equal the count (the offer holds a spot).
  await saveCategory(admin, { id: c1, cap: 3 });
  assert.equal(await errorOf(saveCategory(admin, { id: c1, cap: 2 })), 'invalid_argument');

  // An empty category may change kind.
  await saveCategory(admin, { id: c2, kind: 'pairs' });
  assert.equal((await one(`select kind from tournament_categories where id = $1`, [c2])).kind, 'pairs');
});

test('creating categories concurrently in one tournament never deadlocks; each gets its own place', async () => {
  const { t } = await adminTournament();
  // The interleaving that deadlocked: another create has inserted its
  // category (holding the foreign key's share lock on the tournament) but
  // not yet recomputed the summary when this create starts.
  const other = await db.connect();
  try {
    await other.query('begin');
    await other.query(
      `insert into tournament_categories (tournament_id, name_en, kind, cap, sort_order) values ($1, 'Other', 'singles', 2, 1)`,
      [t],
    );
    const mine = saveCategory(admin, { tournament_id: t, name_en: 'Mine', kind: 'singles', cap: 2 });
    // Let it reach its wait on the tournament row before the other one goes on.
    await new Promise((resolve) => setTimeout(resolve, 300));
    await other.query(`select app.sync_tournament_summary($1)`, [t]);
    await other.query('commit');
    const id = await mine;
    assert.equal((await one(`select sort_order from tournament_categories where id = $1`, [id])).sort_order, 2);
  } catch (e) {
    await other.query('rollback').catch(() => {});
    throw e;
  } finally {
    other.release();
  }

  const ids = await Promise.all(
    [1, 2, 3, 4, 5, 6].map((i) => saveCategory(admin, { tournament_id: t, name_en: `Parallel ${i}`, kind: 'singles', cap: 2 })),
  );
  const orders = (await pool.query(`select sort_order from tournament_categories where id = any ($1)`, [ids])).rows.map((r) => r.sort_order);
  assert.equal(new Set(orders).size, 6);
  assert.deepEqual(await summary(t), { min_fee: 0, max_fee: 100000, slots_total: 18, slots_filled: 0 });
});

test('after the deadline a raised cap offers nobody (only admin_offer_next does)', async () => {
  const { cats } = await adminTournament({ categories: [cat({ cap: 1 })] });
  const [a, w] = [await player('A'), await player('W')];
  await register(a, cats[0]);
  const wl = await joinWaitlist(w, cats[0]);
  const afterDeadline = tashkent('2026-12-10', 9);
  await saveCategory(admin, { id: cats[0], cap: 2 }, afterDeadline);
  assert.equal(await statusOf(wl.id), 'waitlisted');

  assert.equal(await offerNext(admin, cats[0], afterDeadline), 1);
  assert.equal(await statusOf(wl.id), 'offered');
  const row = await one(`select offer_expires_at from tournament_registrations where id = $1`, [wl.id]);
  assert.equal(row.offer_expires_at.toISOString(), new Date(Date.parse(afterDeadline) + 24 * 3600000).toISOString());
  // The player can take it after the deadline.
  assert.equal((await claim(w, wl.id, tashkent('2026-12-10', 10))).status, 'registered');
  // The category is full now.
  assert.equal(await errorOf(offerNext(admin, cats[0], afterDeadline)), 'full');
});

test('admin_offer_next before the deadline fills free spots from the waitlist; nobody waiting gives 0', async () => {
  const { cats } = await adminTournament({ categories: [cat({ cap: 1 })] });
  const [a, w] = [await player('A'), await player('W')];
  const ra = await register(a, cats[0]);
  const wl = await joinWaitlist(w, cats[0]);
  // A spot freed without an offer (as if offer_next had not run).
  await pool.query(`update tournament_registrations set status = 'cancelled' where id = $1`, [ra.id]);
  await pool.query('delete from audit_log');
  assert.equal(await offerNext(admin, cats[0]), 1);
  assert.equal(await statusOf(wl.id), 'offered');
  const row = await one(`select offer_expires_at from tournament_registrations where id = $1`, [wl.id]);
  assert.equal(row.offer_expires_at.toISOString(), later(24));
  assert.equal(await auditCount(), 1);
  // An expired offer is swept first: it lapses, nobody is left, the spot is free.
  assert.equal(await offerNext(admin, cats[0], later(25)), 0);
  assert.equal(await statusOf(wl.id), 'lapsed');
});

test('deleting a category: refused with any entry, finished ones included; never the last one; history kept', async () => {
  const { t, cats } = await adminTournament({
    categories: [cat(), cat({ name_en: 'Second', fee: 70000 }), cat({ name_en: 'Empty', fee: 50000 })],
  });
  const [, c2, c3] = cats;
  const p = await player('P');
  const r = await register(p, c2);
  assert.equal(await errorOf(deleteCategory(admin, c2)), 'has_registrations');
  // Finished entries are history: still refused, and the row stays.
  await cancel(p, r.id);
  await pool.query('delete from audit_log');
  assert.equal(await errorOf(deleteCategory(admin, c2)), 'has_registrations');
  assert.equal(await statusOf(r.id), 'cancelled');
  assert.equal(await auditCount(), 0);

  // An empty category goes; the summary follows.
  await deleteCategory(admin, c3);
  assert.equal((await one(`select count(*)::int as n from tournament_categories where id = $1`, [c3])).n, 0);
  assert.deepEqual(await summary(t), { min_fee: 70000, max_fee: 100000, slots_total: 4, slots_filled: 0 });
  const audit = await auditRows();
  assert.equal(audit.length, 1);
  assert.deepEqual([audit[0].action, audit[0].entity_id, audit[0].before.name_en, audit[0].after], ['delete_category', c3, 'Empty', null]);

  assert.equal(await errorOf(deleteCategory(admin, randomUUID())), 'not_found');
  // The last category never goes, even when empty.
  const { cats: lone } = await adminTournament({ starts: '2026-12-20' });
  assert.equal(await errorOf(deleteCategory(admin, lone[0])), 'invalid_argument');
});

// --- registrations -------------------------------------------------------------------

test('admin_list_registrations shows every entry with phones, to admins only', async () => {
  const { t, cats } = await adminTournament({ categories: [cat({ cap: 1 }), cat({ name_en: 'Pairs', kind: 'pairs', cap: 2 })] });
  const a = await player('A', { phone: '+998901111111' });
  const b = await player('B', { phone: '+998902222222' });
  const c = await player('C');
  const ra = await register(a, cats[0]);
  const rc = await joinWaitlist(c, cats[0]);
  const pair = await register(a, cats[1], b);
  await respond(b, pair.id, true);

  const rows = await listRegistrations(admin, t);
  assert.equal(rows.length, 3);
  const byId = Object.fromEntries(rows.map((r) => [r.id, r]));
  assert.deepEqual(byId[ra.id].registrant, { id: a, name: 'A', phone: '+998901111111' });
  assert.equal(byId[ra.id].partner, null);
  assert.equal(byId[ra.id].status, 'registered');
  assert.equal(byId[ra.id].fee, 100000);
  assert.equal(byId[ra.id].currency, 'UZS');
  assert.equal(byId[ra.id].paid, false);
  assert.equal(byId[ra.id].admin_override, false);
  assert.ok(byId[ra.id].created_at);
  assert.deepEqual(byId[pair.id].partner, { id: b, name: 'B', phone: '+998902222222' });
  assert.equal(byId[rc.id].status, 'waitlisted');
  assert.ok(byId[rc.id].waitlist_position > 0);
  assert.deepEqual(byId[rc.id].registrant, { id: c, name: 'C', phone: null });

  assert.equal(await errorOf(listRegistrations(a, t)), 'not_allowed');
  assert.equal(await errorOf(listRegistrations(null, t)), 'not_allowed');
  assert.equal(await errorOf(listRegistrations(admin, randomUUID())), 'not_found');
});

test('set paid: registered entries only; revenue drops a paid entry that is removed or cancelled', async () => {
  const { t, cats } = await adminTournament({ categories: [cat({ cap: 3 })] });
  const [a, b, w] = [await player('A'), await player('B'), await player('W')];
  const ra = await register(a, cats[0]);
  const rb = await register(b, cats[0]);

  await pool.query('delete from audit_log');
  const paid = await setPaid(admin, ra.id, true);
  assert.equal(paid.paid, true);
  assert.equal(paid.registrant.phone, null);
  const row = await one(`select paid_at from tournament_registrations where id = $1`, [ra.id]);
  assert.equal(row.paid_at.toISOString(), new Date(now).toISOString());
  const audit = await auditRows();
  assert.equal(audit.length, 1);
  assert.deepEqual([audit[0].action, audit[0].entity, audit[0].entity_id, audit[0].before.paid_at, audit[0].after.paid_at !== null], [
    'set_registration_paid',
    'tournament_registration',
    ra.id,
    null,
    true,
  ]);

  assert.equal((await setPaid(admin, ra.id, false)).paid, false);
  await setPaid(admin, ra.id, true);
  await setPaid(admin, rb.id, true);

  const revenue = async () => (await dashboard(admin, 'tashkent', '2026-11-01', '2026-11-30')).revenue;
  assert.deepEqual(await revenue(), [{ currency: 'UZS', venues: 0, tournaments: 200000 }]);
  await cancel(b, rb.id);
  assert.deepEqual(await revenue(), [{ currency: 'UZS', venues: 0, tournaments: 100000 }]);
  await removeReg(admin, ra.id);
  assert.deepEqual(await revenue(), []);
  assert.equal((await one(`select status from tournament_registrations where id = $1`, [ra.id])).status, 'removed');

  // Only registered entries: not waitlisted, cancelled or removed ones.
  const rw = await register(w, cats[0]);
  await pool.query(`update tournament_registrations set status = 'waitlisted' where id = $1`, [rw.id]);
  assert.equal(await errorOf(setPaid(admin, rw.id, true)), 'not_markable');
  assert.equal(await errorOf(setPaid(admin, rb.id, true)), 'not_markable');
  assert.equal(await errorOf(setPaid(admin, ra.id, false)), 'not_markable');
  assert.equal(await errorOf(setPaid(admin, rw.id, null)), 'invalid_argument');
  assert.equal(await errorOf(setPaid(admin, randomUUID(), true)), 'not_found');
  assert.equal(await errorOf(setPaid(a, rw.id, true)), 'not_allowed');
  assert.equal((await summary(t)).slots_filled, 1);
});

test('remove: any live entry becomes removed, both players are told, a counted spot goes to the waitlist', async () => {
  const { t, cats } = await adminTournament({ categories: [cat({ name_en: 'Pairs', kind: 'pairs', cap: 1 })] });
  const [a, b, c, d] = [await player('A'), await player('B'), await player('C'), await player('D')];
  const pair = await register(a, cats[0], b);
  await respond(b, pair.id, true);
  const waiting = await joinWaitlist(c, cats[0], d);
  await respond(d, waiting.id, true);
  assert.deepEqual(await summary(t), { min_fee: 100000, max_fee: 100000, slots_total: 1, slots_filled: 1 });

  await pool.query('delete from audit_log');
  const removed = await removeReg(admin, pair.id);
  assert.equal(removed.status, 'removed');
  assert.equal((await notesOf(a, 'tournament_removed')).length, 1);
  assert.equal((await notesOf(b, 'tournament_removed')).length, 1);
  const note = (await notesOf(a, 'tournament_removed'))[0];
  assert.equal(note.category, 'tournaments');
  assert.equal(note.payload.registration_id, pair.id);
  assert.equal(note.payload.tournament_id, t);
  assert.equal(await statusOf(waiting.id), 'offered');
  assert.deepEqual(await summary(t), { min_fee: 100000, max_fee: 100000, slots_total: 1, slots_filled: 1 });
  const audit = await auditRows();
  assert.equal(audit.length, 1);
  assert.deepEqual([audit[0].action, audit[0].before.status, audit[0].after.status], ['remove_registration', 'registered', 'removed']);

  // A waitlisted entry (admin_remove_waitlisted is the same call).
  const [e] = [await player('E')];
  const { cats: singles } = await adminTournament({ categories: [cat({ cap: 1 })] });
  await register(e, singles[0]);
  const w = await joinWaitlist(c, singles[0]);
  assert.equal((await removeReg(admin, w.id)).status, 'removed');
  // Finished entries cannot be removed again.
  assert.equal(await errorOf(removeReg(admin, w.id)), 'not_found');
  assert.equal(await errorOf(removeReg(c, pair.id)), 'not_allowed');
});

test('remove: a pending invitee is told; expired offers are settled before the freed spot is offered', async () => {
  const { cats } = await adminTournament({ categories: [cat({ name_en: 'Pairs', kind: 'pairs', cap: 2 }), cat({ cap: 2 })] });
  const [cp, cs] = cats;
  const [a, b] = [await player('A'), await player('B')];
  const pending = await register(a, cp, b);
  assert.equal((await removeReg(admin, pending.id)).status, 'removed');
  assert.equal((await notesOf(a, 'tournament_removed')).length, 1);
  assert.equal((await notesOf(b, 'tournament_removed')).length, 1);

  // cap 2: x and y in, w1..w3 waiting; y cancels, so w1 holds an offer until later(24).
  const [x, y, w1, w2, w3] = [await player('X'), await player('Y'), await player('W1'), await player('W2'), await player('W3')];
  const rx = await register(x, cs);
  const ry = await register(y, cs);
  const [q1, q2, q3] = [await joinWaitlist(w1, cs), await joinWaitlist(w2, cs), await joinWaitlist(w3, cs)];
  await cancel(y, ry.id);
  assert.equal(await statusOf(q1.id), 'offered');
  // After w1's offer ran out, x is removed: w1 lapses, both free spots go to w2 and w3.
  await removeReg(admin, rx.id, later(25));
  assert.deepEqual([await statusOf(q1.id), await statusOf(q2.id), await statusOf(q3.id)], ['lapsed', 'offered', 'offered']);
});

test('move: same tournament and kind, keeps the fee, refuses a full target, tells the players, offers the source spot', async () => {
  const { t, cats } = await adminTournament({
    categories: [
      cat({ name_en: 'A', fee: 100000, cap: 1 }),
      cat({ name_en: 'B', fee: 200000, cap: 2, min_level: 4, max_level: 5 }),
      cat({ name_en: 'Pairs', kind: 'pairs', cap: 2 }),
    ],
  });
  const [ca, cb, cp] = cats;
  const [a, b, w] = [await player('A'), await player('B'), await player('W')];
  const ra = await register(a, ca);
  const wl = await joinWaitlist(w, ca);
  const { cats: other } = await adminTournament({ starts: '2026-12-20' });

  assert.equal(await errorOf(moveReg(admin, ra.id, other[0])), 'invalid_argument');
  assert.equal(await errorOf(moveReg(admin, ra.id, cp)), 'invalid_argument');
  assert.equal(await errorOf(moveReg(admin, ra.id, ca)), 'invalid_argument');
  assert.equal(await errorOf(moveReg(admin, wl.id, cb)), 'invalid_argument'); // only registered entries move
  assert.equal(await errorOf(moveReg(admin, ra.id, randomUUID())), 'not_found');
  assert.equal(await errorOf(moveReg(a, ra.id, cb)), 'not_allowed');

  await pool.query('delete from audit_log');
  // Level 1 player into a 4-5 category: the admin's move bypasses the range.
  const moved = await moveReg(admin, ra.id, cb);
  assert.equal(moved.category_id, cb);
  assert.equal(moved.status, 'registered');
  assert.equal(moved.fee, 100000);
  const note = (await notesOf(a, 'tournament_moved'))[0];
  assert.equal(note.category, 'tournaments');
  assert.equal(note.payload.category_id, cb);
  assert.equal(note.payload.category_name.en, 'B');
  assert.equal(note.payload.from_category_name.en, 'A');
  assert.equal(await statusOf(wl.id), 'offered');
  assert.deepEqual(await summary(t), { min_fee: 100000, max_fee: 200000, slots_total: 5, slots_filled: 2 });
  const audit = await auditRows();
  assert.equal(audit.length, 1);
  assert.deepEqual([audit[0].action, audit[0].before.category_id, audit[0].after.category_id], ['move_registration', ca, cb]);

  // A player already in the target, and a full target.
  assert.equal((await claim(w, wl.id)).status, 'registered');
  await addReg(admin, cb, w); // w is now in A and in B; B is full (a, w)
  assert.equal(await errorOf(moveReg(admin, wl.id, cb)), 'already_registered');
  await saveCategory(admin, { id: ca, cap: 2 });
  const rb = await register(b, ca);
  assert.equal(await errorOf(moveReg(admin, rb.id, cb)), 'full');
  assert.equal(await statusOf(rb.id), 'registered');
});

test('admin add: bypasses the level range and the deadline, never the cap; pairs are registered at once', async () => {
  const { t, cats } = await adminTournament({
    categories: [cat({ cap: 1, min_level: 4, max_level: 5 }), cat({ name_en: 'Pairs', kind: 'pairs', cap: 1 })],
  });
  const [cs, cp] = cats;
  const [a, b, c, d] = [await player('A'), await player('B'), await player('C'), await player('D')];
  const afterDeadline = tashkent('2026-12-10', 8);

  await pool.query('delete from audit_log');
  const ra = await addReg(admin, cs, a, null, afterDeadline);
  assert.equal(ra.status, 'registered');
  assert.equal(ra.admin_override, true);
  assert.equal(ra.fee, 100000);
  assert.equal(ra.currency, 'UZS');
  assert.equal((await notesOf(a, 'tournament_registered')).length, 1);
  assert.equal(await auditCount(), 1);
  assert.equal((await auditRows())[0].action, 'add_registration');

  assert.equal(await errorOf(addReg(admin, cs, b, null, afterDeadline)), 'full');
  assert.equal(await errorOf(addReg(admin, cs, a)), 'already_registered');
  assert.equal(await errorOf(addReg(admin, cs, b, c)), 'invalid_argument'); // singles with a partner
  assert.equal(await errorOf(addReg(admin, cp, b)), 'invalid_argument'); // pairs without one
  assert.equal(await errorOf(addReg(admin, cp, b, b)), 'invalid_argument');
  assert.equal(await errorOf(addReg(admin, cp, b, randomUUID())), 'not_found');
  assert.equal(await errorOf(addReg(admin, cp, randomUUID(), b)), 'not_found');
  assert.equal(await errorOf(addReg(admin, randomUUID(), b)), 'not_found');
  assert.equal(await errorOf(addReg(b, cp, b, c)), 'not_allowed');

  const pair = await addReg(admin, cp, b, c);
  assert.equal(pair.status, 'registered');
  assert.equal(pair.partner_confirmed, true);
  assert.equal(pair.partner.phone, null);
  assert.equal((await notesOf(c, 'tournament_registered')).length, 1);
  assert.deepEqual(await summary(t), { min_fee: 100000, max_fee: 100000, slots_total: 2, slots_filled: 2 });

  // A confirmed partner is "in" too.
  await saveCategory(admin, { id: cp, cap: 2 });
  assert.equal(await errorOf(addReg(admin, cp, c, d)), 'already_registered');
  assert.equal(await errorOf(addReg(admin, cp, d, c)), 'partner_unavailable');
});

// --- dashboard -----------------------------------------------------------------------

async function booking({ court = courtId, venue = venueId, start, minutes = 60, price, status = 'paid', source = 'app', user = null, offset = 300, currency = 'UZS', created = now }) {
  const end = new Date(Date.parse(start) + minutes * 60000).toISOString();
  await pool.query(
    `insert into bookings (user_id, venue_id, court_id, during, utc_offset_minutes, slot_count, total_price, currency, status, source,
                           guest_name, walk_in_payment, created_at)
     values ($1, $2, $3, tstzrange($4, $5), $6, 1, $7, $8, $9, $10, $11, $12, $13)`,
    [
      source === 'app' ? user : null,
      venue,
      court,
      start,
      end,
      offset,
      price,
      currency,
      status,
      source,
      source === 'walk_in' ? 'Guest' : null,
      source === 'walk_in' ? 'cash' : null,
      created,
    ],
  );
}

test('dashboard: revenue per currency, venues from paid bookings, tournaments from paid registered entries', async () => {
  const u = await player('Booker');
  // Tashkent, in November (venue time).
  await booking({ start: tashkent('2026-11-10', 10), price: 100000, user: u });
  await booking({ start: tashkent('2026-11-10', 12), price: 50000, source: 'walk_in' });
  await booking({ start: tashkent('2026-11-11', 10), price: 70000, status: 'confirmed', user: u }); // not paid
  await booking({ start: tashkent('2026-11-12', 10), price: 70000, status: 'unverified', user: u }); // not paid
  await booking({ start: tashkent('2026-11-13', 10), price: 0, status: 'confirmed', source: 'block' }); // never
  // 00:30 on 1 December venue time: outside November even though it is 30 November in UTC.
  await booking({ start: tashkent('2026-12-01', 0, 30), price: 900000, user: u });
  // Almaty, KZT.
  await booking({ court: almatyCourt, venue: almatyVenue, start: '2026-11-15T10:00:00+05:00', price: 8000, currency: 'KZT', user: u });

  // Tournaments: a UZS one and a KZT one.
  const { cats: uz } = await adminTournament({ categories: [cat({ cap: 4, fee: 120000 })] });
  const { cats: kz } = await adminTournament({ city: 'almaty', venue: almatyVenue, categories: [cat({ cap: 4, fee: 15000 })] });
  const [a, b, k] = [await player('A'), await player('B'), await player('K', { city: 'almaty' })];
  const ra = await register(a, uz[0]);
  await register(b, uz[0]); // unpaid
  const rk = await register(k, kz[0]);
  await setPaid(admin, ra.id, true);
  await setPaid(admin, rk.id, true);
  // Paid in December: outside the period.
  const { cats: dec } = await adminTournament({ starts: '2026-12-20', categories: [cat({ cap: 4, fee: 999 })] });
  const rd = await register(a, dec[0]);
  await setPaid(admin, rd.id, true, tashkent('2026-12-01', 1));

  const all = await dashboard(admin, null, '2026-11-01', '2026-11-30');
  assert.deepEqual(all.revenue, [
    { currency: 'KZT', venues: 8000, tournaments: 15000 },
    { currency: 'UZS', venues: 150000, tournaments: 120000 },
  ]);
  const tk = await dashboard(admin, 'tashkent', '2026-11-01', '2026-11-30');
  assert.deepEqual(tk.revenue, [{ currency: 'UZS', venues: 150000, tournaments: 120000 }]);
  const al = await dashboard(admin, 'almaty', '2026-11-01', '2026-11-30');
  assert.deepEqual(al.revenue, [{ currency: 'KZT', venues: 8000, tournaments: 15000 }]);
  const decOnly = await dashboard(admin, 'tashkent', '2026-12-01', '2026-12-31');
  assert.deepEqual(decOnly.revenue, [{ currency: 'UZS', venues: 900000, tournaments: 999 }]);

  // The venue total agrees with the owner dashboard for the same days.
  const owner = await scalar(`select app.owner_dashboard($1, $2, null, '2026-11-01', '2026-11-30') as r`, [admin, venueId]);
  assert.equal(owner.revenue_paid, tk.revenue[0].venues);

  for (const [from, to] of [
    [null, '2026-11-30'],
    ['2026-11-30', '2026-11-01'],
    ['2026-01-01', '2027-06-01'],
  ]) {
    assert.equal(await errorOf(dashboard(admin, null, from, to)), 'invalid_argument');
  }
  assert.equal(await errorOf(dashboard(admin, 'nowhere', '2026-11-01', '2026-11-30')), 'not_found');
  assert.equal(await errorOf(dashboard(a, null, '2026-11-01', '2026-11-30')), 'not_allowed');
});

test('dashboard: users (active from last_seen_at, else last sign-in) and counts per city', async () => {
  await pool.query(`delete from profiles where id not in (select user_id from app_admins)`);
  await pool.query(`update profiles set city_id = 'tashkent', created_at = '2026-01-01T00:00:00Z', last_seen_at = null`);
  const seen = async (id, lastSeen, signIn, created) => {
    await pool.query(`update profiles set last_seen_at = $2, created_at = $3 where id = $1`, [id, lastSeen, created]);
    await pool.query(`update auth.users set last_sign_in_at = $2 where id = $1`, [id, signIn]);
  };
  // now is 2026-11-22 20:00 Tashkent.
  const recentSignIn = await player('Signed in recently');
  await seen(recentSignIn, null, later(-24 * 3), tashkent('2026-11-22', 10)); // new today
  const staleSeen = await player('Seen long ago');
  await seen(staleSeen, later(-24 * 40), later(-24 * 2), tashkent('2026-11-17', 10)); // new in 7 days; last_seen_at wins: not active
  const old = await player('Old');
  await seen(old, later(-24 * 60), later(-24 * 60), tashkent('2026-11-03', 10)); // new this month
  const active = await player('Active', { city: 'almaty' });
  await seen(active, later(-1), null, tashkent('2026-10-31', 10)); // last month
  // Created 23:30 on 21 November Tashkent time: yesterday locally, though 18:30 UTC.
  const yesterday = await player('Yesterday');
  await seen(yesterday, null, null, tashkent('2026-11-21', 23, 30));

  const all = await dashboard(admin, null, '2026-11-01', '2026-11-30');
  // The admin (created 2026-01-01, never seen) counts in the total.
  assert.deepEqual(all.users, { total: 6, active_30d: 2, new_today: 1, new_7d: 3, new_month: 4 });
  const tk = await dashboard(admin, 'tashkent', '2026-11-01', '2026-11-30');
  assert.deepEqual(tk.users, { total: 5, active_30d: 1, new_today: 1, new_7d: 3, new_month: 4 });
  const al = await dashboard(admin, 'almaty', '2026-11-01', '2026-11-30');
  assert.deepEqual(al.users, { total: 1, active_30d: 1, new_today: 0, new_7d: 0, new_month: 0 });

  // Counts in the period: bookings (no blocks or holds), games, registrations.
  await booking({ start: tashkent('2026-12-05', 10), price: 1, status: 'confirmed', user: old, created: tashkent('2026-11-20', 9) });
  await booking({ start: tashkent('2026-12-05', 12), price: 1, status: 'confirmed', source: 'block', created: tashkent('2026-11-20', 9) });
  await booking({ start: tashkent('2026-12-05', 14), price: 1, status: 'released', user: old, created: tashkent('2026-11-20', 9) });
  await booking({ start: tashkent('2026-12-06', 10), price: 1, status: 'confirmed', user: old, created: tashkent('2026-12-01', 9) });
  // Cancelled later: still a booking made in the period.
  await booking({ start: tashkent('2026-12-08', 10), price: 1, status: 'cancelled_by_player', user: old, created: tashkent('2026-11-21', 9) });
  await booking({ court: almatyCourt, venue: almatyVenue, start: '2026-12-05T10:00:00+05:00', price: 1, status: 'confirmed', currency: 'KZT', user: old, created: tashkent('2026-11-20', 9) });
  await pool.query(
    `insert into games (sport_id, city_id, venue_id, host_id, during, utc_offset_minutes, spots, created_at) values
       ('padel', 'tashkent', $1, $2, tstzrange('2026-12-07 05:00+00', '2026-12-07 06:00+00'), 300, 4, $3),
       ('padel', 'almaty', $4, $2, tstzrange('2026-12-07 05:00+00', '2026-12-07 06:00+00'), 300, 4, $3)`,
    [venueId, old, tashkent('2026-11-20', 9), almatyVenue],
  );
  const { cats } = await adminTournament({ categories: [cat({ cap: 4 })] });
  await register(old, cats[0], null, tashkent('2026-11-20', 9));
  const r2 = await register(staleSeen, cats[0], null, tashkent('2026-11-20', 9));
  await cancel(staleSeen, r2.id, tashkent('2026-11-20', 10));

  assert.deepEqual((await dashboard(admin, null, '2026-11-01', '2026-11-30')).counts, { bookings: 3, games: 2, registrations: 2 });
  assert.deepEqual((await dashboard(admin, 'tashkent', '2026-11-01', '2026-11-30')).counts, { bookings: 2, games: 1, registrations: 2 });
  assert.deepEqual((await dashboard(admin, 'almaty', '2026-11-01', '2026-11-30')).counts, { bookings: 1, games: 1, registrations: 0 });
});

// --- access ----------------------------------------------------------------------------

test('a non-admin is refused by every admin tournament function', async () => {
  const p = await player('Nobody');
  const id = randomUUID();
  const calls = [
    [`select app.admin_save_tournament($1, '{}'::jsonb, $2)`, (u) => [u, now]],
    [`select app.admin_save_category($1, '{}'::jsonb, $2)`, (u) => [u, now]],
    [`select app.admin_delete_category($1, $2, $3)`, (u) => [u, id, now]],
    [`select app.admin_list_tournaments($1, $2)`, (u) => [u, now]],
    [`select app.admin_list_registrations($1, $2)`, (u) => [u, id]],
    [`select app.admin_set_paid($1, $2, true, $3)`, (u) => [u, id, now]],
    [`select app.admin_remove_registration($1, $2, $3)`, (u) => [u, id, now]],
    [`select app.admin_move_registration($1, $2, $3, $4)`, (u) => [u, id, id, now]],
    [`select app.admin_add_registration($1, $2, $3, null, $4)`, (u) => [u, id, id, now]],
    [`select app.admin_offer_next($1, $2, $3)`, (u) => [u, id, now]],
    [`select app.admin_dashboard($1, null, '2026-11-01', '2026-11-30', $2)`, (u) => [u, now]],
  ];
  for (const [sql, args] of calls) {
    for (const u of [p, null]) assert.equal(await errorOf(pool.query(sql, args(u))), 'not_allowed', `${sql} as ${u}`);
  }
  assert.equal(await auditCount(), 0);
});

test('the public wrappers: visitors refused, privileges as elsewhere, admins get phones through the API', async () => {
  const signatures = [
    ['admin_save_tournament', ['jsonb']],
    ['admin_save_category', ['jsonb']],
    ['admin_delete_category', ['uuid']],
    ['admin_list_tournaments', []],
    ['admin_list_registrations', ['uuid']],
    ['admin_set_paid', ['uuid', 'boolean']],
    ['admin_remove_registration', ['uuid']],
    ['admin_move_registration', ['uuid', 'uuid']],
    ['admin_add_registration', ['uuid', 'uuid', 'uuid']],
    ['admin_offer_next', ['uuid']],
    ['admin_dashboard', ['text', 'date', 'date']],
  ];
  const id = randomUUID();
  const sample = { jsonb: '{}', uuid: id, boolean: true, text: null, date: '2026-11-01' };
  for (const [name, types] of signatures) {
    const fn = `public.${name}(${types.join(', ')})`;
    const { rows: r } = await pool.query(
      `select has_function_privilege('anon', $1, 'execute') as anon,
              has_function_privilege('authenticated', $1, 'execute') as authed,
              has_function_privilege('service_role', $1, 'execute') as service,
              p.prosecdef as definer, p.proconfig as config
       from pg_proc p where p.oid = $1::regprocedure`,
      [fn],
    );
    assert.deepEqual(r[0], { anon: false, authed: true, service: true, definer: true, config: ['search_path=""'] }, fn);
    const args = types.map((t) => sample[t]);
    const sql = `select public.${name}(${types.map((t, i) => `$${i + 1}::${t}`).join(', ')})`;
    assert.equal(await errorOf(asAnon(pool, (c) => c.query(sql, args))), '42501', fn);
  }

  // Through the API as the admin and as a player.
  const p = await player('Api', { phone: '+998903333333' });
  const t = await asUser(pool, admin, async (c) =>
    (await c.query(`select public.admin_save_tournament($1::jsonb) as r`, [json({ city_id: 'tashkent', sport_id: 'padel', title_en: 'API', starts_on: '2026-12-10', ends_on: '2026-12-10' })])).rows[0].r,
  );
  const catId = (await one(`select id from tournament_categories where tournament_id = $1`, [t])).id;
  const added = await asUser(pool, admin, async (c) => (await c.query(`select public.admin_add_registration($1, $2) as r`, [catId, p])).rows[0].r);
  assert.equal(added.registrant.phone, '+998903333333');
  const listed = await asUser(pool, admin, async (c) => (await c.query(`select public.admin_list_registrations($1) as r`, [t])).rows.map((x) => x.r));
  assert.equal(listed[0].registrant.phone, '+998903333333');
  const tournaments = await asUser(pool, admin, async (c) => (await c.query(`select public.admin_list_tournaments() as r`)).rows.map((x) => x.r));
  assert.equal(tournaments.find((x) => x.id === t).registration_count, 1);
  const dash = await asUser(pool, admin, async (c) => (await c.query(`select public.admin_dashboard(null, '2026-11-01', '2026-11-30') as r`)).rows[0].r);
  assert.ok(dash.users.total >= 2);
  assert.equal(await errorOf(asUser(pool, p, (c) => c.query(`select public.admin_list_registrations($1)`, [t]))), 'not_allowed');
  // The rules themselves are not callable from the API.
  assert.equal(await errorOf(asUser(pool, admin, (c) => c.query(`select app.admin_list_registrations($1, $2)`, [admin, t]))), '42501');
});
