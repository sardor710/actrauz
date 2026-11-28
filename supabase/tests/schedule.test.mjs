// Milestone 8a, Task 2: the match schedule and its calendar blocks. The
// `app` functions are called with the acting user and a fixed clock; the
// last test goes through the `public` wrappers as the API would.

import assert from 'node:assert/strict';
import { after, before, beforeEach, test } from 'node:test';
import { asUser, createUser, expectError, freshDb } from './helpers/db.mjs';
import { addAdmin, addCategory, addCourt, addEntries, addOwner, addTournament, addVenue, at, tashkent } from './helpers/fixtures.mjs';

let db;
let pool;
let admin;
let organizer;
let owner;

// Sunday evening in Tashkent; the tournament runs Monday 30 November to
// Tuesday 1 December (close enough for app bookings, at most 14 days ahead).
const now = tashkent('2026-11-22', 20);
const day = '2026-11-30';
const day2 = '2026-12-01';

before(async () => {
  db = await freshDb('schedule');
  pool = db.pool;
  admin = await addAdmin(pool, await createUser(pool, 'Admin'));
  organizer = await createUser(pool, 'Organiser');
  owner = await createUser(pool, 'Owner');
});
after(() => db.end());

beforeEach(async () => {
  await pool.query('delete from notifications');
  await pool.query('delete from bookings');
  await pool.query('delete from tournament_registrations');
  await pool.query('delete from tournaments');
});

const one = async (sql, params) => (await pool.query(sql, params)).rows[0];
const scalar = async (sql, params) => (await one(sql, params))?.r;
const json = (v) => JSON.stringify(v);

const schedule = (user, match, court, startsAt, note = null, when = now) =>
  pool.query(`select app.schedule_match($1, $2, $3, $4::timestamp, $5, $6)`, [user, match, court, startsAt, note, when]);
const fill = (user, t, onDay, courts, from, categories = null, when = now) =>
  scalar(`select app.fill_day($1, $2, $3::date, $4::uuid[], $5::time, $6::uuid[], $7) as r`, [
    user,
    t,
    onDay,
    courts,
    from,
    categories,
    when,
  ]);
const matchJson = (id) => scalar(`select app.match_json(m) as r from tournament_matches m where m.id = $1`, [id]);
const blocksOf = async (match) =>
  (
    await pool.query(
      `select b.*, lower(b.during) as starts, (lower(b.during) at time zone 'UTC')::text || '/' || (upper(b.during) at time zone 'UTC')::text as range from bookings b where b.tournament_match_id = $1`,
      [match],
    )
  ).rows;
const knockout = async (cat, round) =>
  (
    await pool.query(
      `select * from tournament_matches where category_id = $1 and stage = 'knockout' and round = $2 order by position`,
      [cat, round],
    )
  ).rows;
const allMatches = async (cats) =>
  (await pool.query(`select m.*, app.match_json(m) as j from tournament_matches m where m.category_id = any ($1::uuid[])`, [cats])).rows;
const playersOf = async (reg) => (await one(`select app.entry_players($1) as p`, [reg])).p;
const notesOf = (user, kind) =>
  pool.query(`select * from notifications where user_id = $1 and kind = $2 order by created_at, id`, [user, kind]).then((r) => r.rows);

/** A player with a padel level (sets the seeding: higher is stronger). */
async function player(name, level = null) {
  const id = await createUser(pool, name);
  if (level) await pool.query(`insert into player_levels (user_id, sport_id, level) values ($1, 'padel', $2)`, [id, level]);
  return id;
}

/** A venue with n 90-minute padel courts, owned by `owner`. */
async function venue({ open = 7 * 60, close = 23 * 60, courts = 2 } = {}) {
  const venueId = await addVenue(pool, { open, close });
  await addOwner(pool, venueId, owner);
  const ids = [];
  for (let i = 0; i < courts; i++) ids.push(await addCourt(pool, venueId));
  return { venueId, courts: ids };
}

/** A tournament (organised by `organizer`) at the venue, or without one. */
async function tournament(venueId = null) {
  const t = await addTournament(pool, { venueId, startsOn: day, endsOn: day2 });
  await pool.query(`insert into tournament_organizers (tournament_id, user_id) values ($1, $2)`, [t, organizer]);
  return t;
}

/** A category with the given players (or n new ones) and a published draw. */
async function published(t, { users, n = 8, format = 'knockout', size = null, advance = null, kind = 'singles', partners } = {}) {
  const cat = await addCategory(pool, t, { kind });
  // Categories in the order they are made.
  await pool.query(`update tournament_categories set sort_order = (select count(*) from tournament_categories where tournament_id = $2) where id = $1`, [cat, t]);
  const entrants = users ?? (await Promise.all(Array.from({ length: n }, (_, i) => player(`P${i + 1}`))));
  const regs = await addEntries(pool, cat, entrants, { partners });
  await pool.query(`select app.make_draw($1, $2, $3, $4, $5, $6)`, [admin, cat, format, size, advance, now]);
  await pool.query(`select app.publish_draw($1, $2, $3)`, [admin, cat, now]);
  return { cat, users: entrants, regs };
}

/** An app booking of one slot, held and confirmed by a new player. */
async function appBooking(court, startsAt) {
  const user = await createUser(pool, 'Booker');
  const { rows } = await pool.query(`select (app.hold_slots($1, $2, $3::timestamp[], $4)).id`, [user, court, [startsAt], now]);
  await pool.query(`select app.confirm_booking($1, $2, null, null, $3)`, [user, rows[0].id, now]);
  return rows[0].id;
}

const overlap = (a, b) => a.start < b.end && b.start < a.end;
const span = (j) => ({ start: j.starts_at, end: j.ends_at });

// --- scheduling a match ----------------------------------------------------------------

test('schedule blocks the court', async () => {
  const { venueId, courts } = await venue();
  const t = await tournament(venueId);
  const { cat } = await published(t);
  const [m] = await knockout(cat, 1);

  await schedule(organizer, m.id, courts[0], at(day, 10));

  const blocks = await blocksOf(m.id);
  assert.equal(blocks.length, 1);
  assert.equal(blocks[0].source, 'block');
  assert.equal(blocks[0].status, 'confirmed');
  assert.equal(blocks[0].court_id, courts[0]);
  assert.equal(blocks[0].user_id, null);
  assert.equal(blocks[0].block_reason, 'Tournament: Kubok');
  assert.equal(blocks[0].range, '2026-11-30 05:00:00/2026-11-30 06:30:00');

  const free = await createUser(pool, 'Someone');
  const { rows: slots } = await pool.query(`select * from app.court_availability($1, $2, $3::date, $4)`, [free, courts[0], day, now]);
  assert.equal(slots.find((s) => s.starts_local === at(day, 10)).state, 'taken');

  const calendar = await scalar(`select app.owner_calendar($1, $2, $3::date, 1, $4) as r`, [owner, courts[0], day, now]);
  const slot = calendar.slots.find((s) => s.starts_local === at(day, 10));
  assert.equal(slot.state, 'blocked');
  assert.equal(slot.booking_id, blocks[0].id);
  assert.deepEqual(slot.tournament, { title: { uz: 'Kubok', ru: 'Кубок', kk: null, en: 'Cup' }, match_id: m.id });
  assert.equal(calendar.slots.find((s) => s.starts_local === at(day, 11, 30)).tournament, undefined);

  const j = await matchJson(m.id);
  assert.equal(j.court_id, courts[0]);
  assert.deepEqual(j.court_name, { uz: null, ru: null, kk: null, en: 'Court' });
  assert.equal(j.starts_at, at(day, 10));
  assert.equal(j.ends_at, at(day, 11, 30));
  assert.equal(j.clash, false);

  // Both players hear about it.
  for (const reg of [m.side_a, m.side_b]) {
    for (const p of await playersOf(reg)) {
      const notes = await notesOf(p, 'match_scheduled');
      assert.equal(notes.length, 1);
      assert.equal(notes[0].category, 'tournaments');
      assert.equal(notes[0].payload.tournament_id, t);
      assert.equal(notes[0].payload.category_id, cat);
      assert.equal(notes[0].payload.match_id, m.id);
      assert.equal(notes[0].payload.starts_at, at(day, 10));
    }
  }

  // Organisers only; a draft draw cannot be scheduled.
  await expectError(schedule(await createUser(pool, 'Stranger'), m.id, courts[0], at(day, 13)), 'not_allowed');
  const draft = await addCategory(pool, t);
  await addEntries(pool, draft, [await player('D1'), await player('D2')]);
  await pool.query(`select app.make_draw($1, $2, 'knockout', null, null, $3)`, [admin, draft, now]);
  const [d] = await knockout(draft, 1);
  await expectError(schedule(organizer, d.id, courts[1], at(day, 13)), 'not_found');
  await expectError(schedule(organizer, '00000000-0000-0000-0000-000000000000', courts[1], at(day, 13)), 'not_found');
  // A match that is done (a bye) cannot be scheduled.
  const { cat: odd } = await published(t, { n: 3 });
  const bye = (await knockout(odd, 1)).find((x) => x.status === 'done');
  await expectError(schedule(organizer, bye.id, courts[1], at(day, 13)), 'invalid_argument');
});

test('slot taken', async () => {
  const { venueId, courts } = await venue();
  const { courts: elsewhere } = await venue();
  const t = await tournament(venueId);
  const { cat } = await published(t);
  const [m] = await knockout(cat, 1);

  await appBooking(courts[0], at(day, 10));
  await expectError(schedule(organizer, m.id, courts[0], at(day, 10)), 'slot_taken');
  assert.equal((await blocksOf(m.id)).length, 0);

  await expectError(schedule(organizer, m.id, courts[1], at(day, 10, 15)), 'invalid_argument');
  await expectError(schedule(organizer, m.id, courts[1], at('2026-12-02', 10)), 'invalid_argument');
  await expectError(schedule(organizer, m.id, courts[1], at('2026-11-29', 10)), 'invalid_argument');
  await expectError(schedule(organizer, m.id, elsewhere[0], at(day, 10)), 'invalid_argument');
  await expectError(schedule(organizer, m.id, null, at(day, 10)), 'invalid_argument');
  await pool.query(`update courts set active = false where id = $1`, [courts[1]]);
  await expectError(schedule(organizer, m.id, courts[1], at(day, 10)), 'invalid_argument');
  assert.equal((await matchJson(m.id)).starts_at, null);
});

test('move and clear release', async () => {
  const { venueId, courts } = await venue();
  const t = await tournament(venueId);
  const { cat } = await published(t);
  const [m] = await knockout(cat, 1);

  await schedule(organizer, m.id, courts[0], at(day, 10));
  await schedule(organizer, m.id, courts[1], at(day, 11, 30));
  let blocks = await blocksOf(m.id);
  assert.equal(blocks.length, 1);
  assert.equal(blocks[0].court_id, courts[1]);
  assert.equal(blocks[0].range, '2026-11-30 06:30:00/2026-11-30 08:00:00');
  assert.equal((await pool.query(`select count(*)::int as n from bookings where source = 'block'`)).rows[0].n, 1);
  // The old slot is free again.
  await appBooking(courts[0], at(day, 10));

  // The same slot again: nothing changes, nobody is told twice.
  await schedule(organizer, m.id, courts[1], at(day, 11, 30));
  const [player1] = await playersOf(m.side_a);
  assert.equal((await notesOf(player1, 'match_scheduled')).length, 2);

  await schedule(organizer, m.id, null, null);
  blocks = await blocksOf(m.id);
  assert.equal(blocks.length, 0);
  const j = await matchJson(m.id);
  assert.equal(j.starts_at, null);
  assert.equal(j.court_id, null);
  assert.equal(j.ends_at, null);
  assert.equal((await notesOf(player1, 'match_scheduled')).length, 2);
});

test('player busy across categories', async () => {
  const { venueId, courts } = await venue();
  const t = await tournament(venueId);
  const shared = await player('Shared');
  const { cat: singles } = await published(t, { users: [shared, await player('S2')] });
  // In the pairs category the shared player is the partner, not the registrant.
  const { cat: pairs } = await published(t, {
    kind: 'pairs',
    users: [await player('R1'), await player('R2')],
    partners: [shared, await player('R2 partner')],
  });
  const [a] = await knockout(singles, 1);
  const [b] = await knockout(pairs, 1);

  await schedule(organizer, a.id, courts[0], at(day, 10));
  await expectError(schedule(organizer, b.id, courts[1], at(day, 10)), 'player_busy');
  assert.equal((await blocksOf(b.id)).length, 0);
  // Touching slots do not overlap.
  await schedule(organizer, b.id, courts[1], at(day, 11, 30));
  assert.equal((await matchJson(a.id)).clash, false);
  assert.equal((await matchJson(b.id)).clash, false);

  // A clash made behind the schedule's back (as advancing can) is flagged.
  await pool.query(`update tournament_matches set starts_at = $2 where id = $1`, [b.id, tashkent(day, 10)]);
  assert.equal((await matchJson(a.id)).clash, true);
  assert.equal((await matchJson(b.id)).clash, true);
});

test('owner cannot cancel', async () => {
  const { venueId, courts } = await venue();
  const t = await tournament(venueId);
  const { cat } = await published(t);
  const [m] = await knockout(cat, 1);
  await schedule(organizer, m.id, courts[0], at(day, 10));
  const [block] = await blocksOf(m.id);
  await expectError(pool.query(`select app.owner_cancel_booking($1, $2, $3)`, [owner, block.id, now]), 'tournament_block');
  assert.equal((await blocksOf(m.id))[0].status, 'confirmed');

  // The owner's own blocks still cancel.
  const own = await one(`select (app.owner_block_slots($1, $2, $3::timestamp[], 'Repairs', $4)).id`, [owner, courts[1], [at(day, 10)], now]);
  await pool.query(`select app.owner_cancel_booking($1, $2, $3)`, [owner, own.id, now]);
});

// --- fill the day ------------------------------------------------------------------------

test('fill the day', async () => {
  // Open 09:00-13:30: slots at 09:00, 10:30 and 12:00 on each court.
  const { venueId, courts } = await venue({ open: 9 * 60, close: 13 * 60 + 30 });
  const t = await tournament(venueId);
  const { cat } = await published(t);

  const result = await fill(organizer, t, day, courts, '09:00');
  const [final] = await knockout(cat, 3);
  assert.equal(result.scheduled, 6);
  assert.deepEqual(result.unscheduled, [final.id]);

  const r1 = await knockout(cat, 1);
  const j1 = await Promise.all(r1.map((m) => matchJson(m.id)));
  assert.deepEqual(
    j1.map((j) => [j.starts_at, j.court_id]),
    [
      [at(day, 9), courts[0]],
      [at(day, 9), courts[1]],
      [at(day, 10, 30), courts[0]],
      [at(day, 10, 30), courts[1]],
    ],
  );
  for (const semi of await knockout(cat, 2)) {
    const j = await matchJson(semi.id);
    assert.ok(j.starts_at >= at(day, 12), j.starts_at);
    assert.equal((await blocksOf(semi.id)).length, 1);
  }
  assert.equal((await matchJson(final.id)).starts_at, null);
  assert.equal((await pool.query(`select count(*)::int as n from bookings where source = 'block'`)).rows[0].n, 6);
  const [p] = await playersOf(r1[0].side_a);
  assert.equal((await notesOf(p, 'match_scheduled')).length, 1);

  // Nothing left that fits: a second run places nothing.
  const again = await fill(organizer, t, day, courts, '09:00');
  assert.equal(again.scheduled, 0);
  assert.deepEqual(again.unscheduled, [final.id]);

  // Not the organiser's: refused. A court elsewhere or a day outside: refused.
  await expectError(fill(await createUser(pool, 'Stranger'), t, day, courts, '09:00'), 'not_allowed');
  const { courts: elsewhere } = await venue();
  await expectError(fill(organizer, t, day, elsewhere, '09:00'), 'invalid_argument');
  await expectError(fill(organizer, t, '2026-12-02', courts, '09:00'), 'invalid_argument');
  await expectError(fill(organizer, t, day, [], '09:00'), 'invalid_argument');
});

test('fill the day skips taken slots and waits for feeders', async () => {
  const { venueId, courts } = await venue({ open: 9 * 60, close: 23 * 60 });
  const t = await tournament(venueId);
  const { cat } = await published(t, { n: 4 });
  await appBooking(courts[0], at(day, 9));

  const result = await fill(organizer, t, day, courts, '09:00');
  assert.equal(result.scheduled, 3);
  assert.deepEqual(result.unscheduled, []);
  const [s1, s2] = await knockout(cat, 1);
  const [f] = await knockout(cat, 2);
  assert.deepEqual([(await matchJson(s1.id)).starts_at, (await matchJson(s1.id)).court_id], [at(day, 9), courts[1]]);
  assert.deepEqual([(await matchJson(s2.id)).starts_at, (await matchJson(s2.id)).court_id], [at(day, 10, 30), courts[0]]);
  // The final starts once both semi-finals are over.
  assert.equal((await matchJson(f.id)).starts_at, at(day, 12));
});

test('fill the day respects players', async () => {
  const { venueId, courts } = await venue({ open: 9 * 60, close: 23 * 60, courts: 3 });
  const t = await tournament(venueId);
  // The shared player is the top seed of both: semi-final 1 of each.
  const shared = await player('Shared', 5);
  const one4 = [shared, await player('A2', 3), await player('A3', 2), await player('A4', 1)];
  const two4 = [shared, await player('B2', 3), await player('B3', 2), await player('B4', 1)];
  const { cat: first, regs: firstRegs } = await published(t, { users: one4 });
  const { cat: second, regs: secondRegs } = await published(t, { users: two4 });

  const result = await fill(organizer, t, day, courts, '09:00');
  assert.equal(result.scheduled, 6);

  const [firstSemi] = await knockout(first, 1);
  const [secondSemi] = await knockout(second, 1);
  assert.ok([firstSemi.side_a, firstSemi.side_b].includes(firstRegs[0]));
  assert.ok([secondSemi.side_a, secondSemi.side_b].includes(secondRegs[0]));
  assert.equal((await matchJson(firstSemi.id)).starts_at, at(day, 9));
  // A third court is free at 09:00, but the shared player is busy then.
  assert.equal((await matchJson(secondSemi.id)).starts_at, at(day, 10, 30));
  assert.equal((await matchJson((await knockout(second, 1))[1].id)).starts_at, at(day, 9));

  const mine = [];
  for (const m of await allMatches([first, second])) {
    const players = [...(m.side_a ? await playersOf(m.side_a) : []), ...(m.side_b ? await playersOf(m.side_b) : [])];
    if (players.includes(shared) && m.j.starts_at) mine.push(span(m.j));
  }
  assert.equal(mine.length, 2);
  assert.ok(!overlap(mine[0], mine[1]));
  for (const m of await allMatches([first, second])) assert.equal(m.j.clash, false);
});

test('fill the day gap', async () => {
  // A group of four on two courts: three rounds of two matches.
  const { venueId, courts } = await venue({ open: 9 * 60, close: 23 * 60 });
  const t = await tournament(venueId);
  const { cat, regs } = await published(t, { n: 4, format: 'groups', size: 4, advance: 1 });

  const result = await fill(organizer, t, day, courts, '09:00');
  assert.equal(result.scheduled, 6);
  const matches = await allMatches([cat]);
  assert.equal(matches.length, 6);
  for (const reg of regs) {
    const starts = matches
      .filter((m) => m.side_a === reg || m.side_b === reg)
      .map((m) => m.j.starts_at)
      .sort();
    assert.deepEqual(starts, [at(day, 9), at(day, 12), at(day, 15)]);
  }

  // Only three slots: no schedule keeps the gap, so the rest go back to back.
  const { venueId: small, courts: smallCourts } = await venue({ open: 9 * 60, close: 13 * 60 + 30 });
  const t2 = await tournament(small);
  const { cat: cat2 } = await published(t2, { n: 4, format: 'groups', size: 4, advance: 1 });
  const second = await fill(organizer, t2, day, smallCourts, '09:00');
  assert.equal(second.scheduled, 6);
  const starts = (await allMatches([cat2])).map((m) => m.j.starts_at).sort();
  assert.deepEqual(starts, [at(day, 9), at(day, 9), at(day, 10, 30), at(day, 10, 30), at(day, 12), at(day, 12)]);
});

test('fill the day: groups before the knockout, ticked categories only', async () => {
  const { venueId, courts } = await venue({ open: 9 * 60, close: 23 * 60 });
  const t = await tournament(venueId);
  // Two groups of three, two advance: a knockout of four after them.
  const { cat } = await published(t, { n: 6, format: 'groups', size: 3, advance: 2 });
  const { cat: other } = await published(t, { n: 2 });

  const result = await fill(organizer, t, day, courts, '09:00', [cat]);
  const matches = await allMatches([cat]);
  const groupEnds = matches.filter((m) => m.stage === 'group').map((m) => m.j.ends_at);
  assert.ok(groupEnds.every((e) => e !== null));
  const lastGroupEnd = groupEnds.sort().at(-1);
  for (const m of matches.filter((x) => x.stage === 'knockout' && x.round === 1)) {
    assert.ok(m.j.starts_at >= lastGroupEnd, `${m.j.starts_at} < ${lastGroupEnd}`);
  }
  assert.equal(result.scheduled, matches.length);
  const [untouched] = await knockout(other, 1);
  assert.equal((await matchJson(untouched.id)).starts_at, null);
});

// --- without a venue ---------------------------------------------------------------------

test('no venue', async () => {
  const { courts } = await venue();
  const t = await tournament(null);
  const { cat } = await published(t, { n: 2 });
  const [m] = await knockout(cat, 1);

  await schedule(organizer, m.id, null, at(day, 10), '  Central park, court 3  ');
  const j = await matchJson(m.id);
  assert.equal(j.starts_at, at(day, 10));
  assert.equal(j.place_note, 'Central park, court 3');
  assert.equal(j.court_id, null);
  assert.equal(j.ends_at, null);
  assert.equal((await blocksOf(m.id)).length, 0);
  assert.equal((await pool.query(`select count(*)::int as n from bookings`)).rows[0].n, 0);
  const [p] = await playersOf(m.side_a);
  assert.equal((await notesOf(p, 'match_scheduled')).length, 1);

  await expectError(schedule(organizer, m.id, courts[0], at(day, 10)), 'invalid_argument');
  await expectError(schedule(organizer, m.id, null, at(day, 10), 'x'.repeat(101)), 'invalid_argument');
  await expectError(schedule(organizer, m.id, null, at('2026-12-02', 10)), 'invalid_argument');
  await expectError(fill(organizer, t, day, courts, '09:00'), 'invalid_argument');

  // The same player twice at one time is still refused.
  const shared = (await playersOf(m.side_a))[0];
  const { cat: other } = await published(t, { users: [shared, await player('Q2')] });
  const [o] = await knockout(other, 1);
  await expectError(schedule(organizer, o.id, null, at(day, 10)), 'player_busy');
  await schedule(organizer, o.id, null, at(day, 12));
});

// --- the tournament and its categories after a draw ---------------------------------------

test('tournament edits', async () => {
  const { venueId, courts } = await venue();
  const { venueId: otherVenue } = await venue();
  const t = await tournament(venueId);
  const { cat } = await published(t);
  const [m1, m2] = await knockout(cat, 1);
  await schedule(organizer, m1.id, courts[0], at(day2, 10));
  await schedule(organizer, m2.id, courts[1], at(day, 10));

  const save = (patch) => pool.query(`select app.admin_save_tournament($1, $2::jsonb, $3)`, [admin, json({ id: t, ...patch }), now]);
  await expectError(save({ venue_id: otherVenue }), 'draw_exists');
  await expectError(save({ venue_id: null }), 'draw_exists');
  await expectError(save({ sport_id: 'football' }), 'draw_exists');
  await expectError(save({ ends_on: day }), 'matches_outside_dates');
  await expectError(save({ starts_on: day2 }), 'matches_outside_dates');
  // Dates that still hold every match are fine, as is the title.
  await save({ ends_on: '2026-12-02', title_en: 'Big cup' });

  // Hidden: every block of an unplayed match is released.
  await pool.query(`update tournament_matches set status = 'done', outcome = 'walkover', winner = 'a' where id = $1`, [m2.id]);
  await save({ active: false });
  assert.equal((await blocksOf(m1.id)).length, 0);
  assert.equal((await blocksOf(m2.id)).length, 1);

  const saveCategory = (patch) => pool.query(`select app.admin_save_category($1, $2::jsonb, $3)`, [admin, json({ id: cat, ...patch }), now]);
  await expectError(saveCategory({ kind: 'pairs' }), 'draw_exists');
  await saveCategory({ name_en: 'Open singles' });
  await expectError(pool.query(`select app.admin_delete_category($1, $2, $3)`, [admin, cat, now]), 'draw_exists');

  // A draft counts as a draw too.
  const t2 = await tournament(venueId);
  const draft = await addCategory(pool, t2);
  await addEntries(pool, draft, [await player('D1'), await player('D2')]);
  await pool.query(`select app.make_draw($1, $2, 'knockout', null, null, $3)`, [admin, draft, now]);
  await expectError(
    pool.query(`select app.admin_save_tournament($1, $2::jsonb, $3)`, [admin, json({ id: t2, venue_id: otherVenue }), now]),
    'draw_exists',
  );
});

test('redo releases blocks', async () => {
  const { venueId, courts } = await venue();
  const t = await tournament(venueId);
  const { cat } = await published(t);
  const [m1, m2] = await knockout(cat, 1);
  await schedule(organizer, m1.id, courts[0], at(day, 10));
  await schedule(organizer, m2.id, courts[1], at(day, 10));
  assert.equal((await pool.query(`select count(*)::int as n from bookings where venue_id = $1`, [venueId])).rows[0].n, 2);

  await pool.query(`select app.redo_draw($1, $2, $3)`, [admin, cat, now]);
  assert.equal((await pool.query(`select count(*)::int as n from bookings where venue_id = $1`, [venueId])).rows[0].n, 0);
});

// --- the API -----------------------------------------------------------------------------

test('the public calls', async () => {
  const { venueId, courts } = await venue({ open: 9 * 60, close: 23 * 60 });
  const t = await tournament(venueId);
  const { cat } = await published(t, { n: 4 });
  const [m] = await knockout(cat, 1);

  const j = await asUser(pool, organizer, async (c) =>
    (await c.query(`select public.schedule_match($1, $2, $3::timestamp) as r`, [m.id, courts[0], at(day, 9)])).rows[0].r,
  );
  assert.equal(j.id, m.id);
  assert.equal(j.starts_at, at(day, 9));

  const result = await asUser(pool, organizer, async (c) =>
    (await c.query(`select public.fill_day($1, $2::date, $3::uuid[], '09:00'::time) as r`, [t, day, courts])).rows[0].r,
  );
  assert.equal(result.scheduled, 2);

  const cleared = await asUser(pool, organizer, async (c) => (await c.query(`select public.schedule_match($1) as r`, [m.id])).rows[0].r);
  assert.equal(cleared.starts_at, null);

  // Courts for the schedule: organisers only.
  const bracket = await asUser(pool, organizer, async (c) => (await c.query(`select public.tournament_bracket($1) as r`, [t])).rows[0].r);
  assert.deepEqual(
    bracket.courts.map((x) => [x.id, x.slot_minutes, x.name.en]).sort(),
    courts.map((id) => [id, 90, 'Court']).sort(),
  );
  const someone = await createUser(pool, 'Someone');
  const seen = await asUser(pool, someone, async (c) => (await c.query(`select public.tournament_bracket($1) as r`, [t])).rows[0].r);
  assert.deepEqual(seen.courts, []);
  await expectError(
    asUser(pool, someone, (c) => c.query(`select public.schedule_match($1, $2, $3::timestamp)`, [m.id, courts[0], at(day, 9)])),
    'not_allowed',
  );
});

// --- hidden tournaments and past slots (review round 1) -----------------------------------

test('hiding a tournament clears the times of its unplayed matches', async () => {
  const { venueId, courts } = await venue();
  const t = await tournament(venueId);
  const { cat } = await published(t);
  const [m1, m2] = await knockout(cat, 1);
  await schedule(organizer, m1.id, courts[0], at(day, 10), 'Main hall');
  await schedule(organizer, m2.id, courts[1], at(day, 10));
  await pool.query(`update tournament_matches set status = 'done', outcome = 'walkover', winner = 'a' where id = $1`, [m2.id]);

  await pool.query(`select app.admin_save_tournament($1, $2::jsonb, $3)`, [admin, json({ id: t, active: false }), now]);
  const j1 = await matchJson(m1.id);
  assert.equal(j1.starts_at, null);
  assert.equal(j1.court_id, null);
  assert.equal(j1.place_note, 'Main hall');
  assert.equal((await blocksOf(m1.id)).length, 0);
  // The played match keeps its time and block.
  assert.equal((await matchJson(m2.id)).starts_at, at(day, 10));
  assert.equal((await blocksOf(m2.id)).length, 1);

  // Shown again: the match is simply unscheduled.
  await pool.query(`select app.admin_save_tournament($1, $2::jsonb, $3)`, [admin, json({ id: t, active: true }), now]);
  assert.equal((await matchJson(m1.id)).starts_at, null);
});

test('a hidden tournament cannot be scheduled', async () => {
  const { venueId, courts } = await venue({ open: 9 * 60, close: 23 * 60 });
  const t = await tournament(venueId);
  const { cat } = await published(t);
  const [m] = await knockout(cat, 1);
  await pool.query(`update tournaments set active = false where id = $1`, [t]);
  await expectError(schedule(organizer, m.id, courts[0], at(day, 10, 30)), 'not_found');
  await expectError(schedule(organizer, m.id, null, null), 'not_found');
  await expectError(fill(organizer, t, day, courts, '09:00'), 'not_found');
  assert.equal((await blocksOf(m.id)).length, 0);
});

test('past slots', async () => {
  const { venueId, courts } = await venue({ open: 9 * 60, close: 23 * 60 });
  const t = await tournament(venueId);
  const { cat } = await published(t);
  const [m] = await knockout(cat, 1);
  const eleven = tashkent(day, 11);

  // A slot that has ended (9:00-10:30) is refused.
  await expectError(schedule(organizer, m.id, courts[0], at(day, 9), null, eleven), 'in_past');
  // A slot under way (10:30-12:00) can still be set: the organiser records
  // when a match is really being played.
  await schedule(organizer, m.id, courts[0], at(day, 10, 30), null, eleven);
  assert.equal((await matchJson(m.id)).starts_at, at(day, 10, 30));
  await schedule(organizer, m.id, courts[0], at(day, 12), null, eleven);

  // "Fill the day" still skips every slot that has already started.
  const result = await fill(organizer, t, day, courts, '09:00', null, eleven);
  assert.ok(result.scheduled > 0);
  for (const x of await allMatches([cat])) {
    if (x.j.starts_at) assert.ok(x.j.starts_at >= at(day, 11), x.j.starts_at);
  }
  assert.equal((await pool.query(`select count(*)::int as n from bookings where lower(during) < $1`, [eleven])).rows[0].n, 0);
});

test('past times without a venue: up to two hours back', async () => {
  const t = await tournament();
  const { cat } = await published(t);
  const [m] = await knockout(cat, 1);
  const eleven = tashkent(day, 11);

  await schedule(organizer, m.id, null, at(day, 9), 'Field 2', eleven);
  assert.equal((await matchJson(m.id)).starts_at, at(day, 9));
  await expectError(schedule(organizer, m.id, null, at(day, 8, 59), 'Field 2', eleven), 'in_past');
});
