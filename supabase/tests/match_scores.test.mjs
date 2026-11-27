// Milestone 8a, Task 3: scores, advancement, group standings and
// withdrawals. The `app` functions are called with the acting user and a
// fixed clock; the last test goes through the `public` wrappers.

import assert from 'node:assert/strict';
import { after, before, beforeEach, test } from 'node:test';
import { asUser, createUser, expectError, freshDb } from './helpers/db.mjs';
import { addAdmin, addCategory, addCourt, addEntries, addOwner, addRatedSports, addTournament, addVenue, at, tashkent } from './helpers/fixtures.mjs';

let db;
let pool;
let admin;
let organizer;
let owner;

// Sunday evening in Tashkent; the tournament runs Monday 30 November to
// Tuesday 1 December.
const now = tashkent('2026-11-22', 20);
const day = '2026-11-30';
const day2 = '2026-12-01';

before(async () => {
  db = await freshDb('match_scores');
  pool = db.pool;
  // Padel is a rated sport (M7 sets); football is not (one score per side).
  await addRatedSports(pool);
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

const score = (user, match, outcome, winner = null, sets = null, when = now) =>
  pool.query(`select app.enter_match_score($1, $2, $3, $4, $5::jsonb, $6)`, [
    user,
    match,
    outcome,
    winner,
    sets === null ? null : JSON.stringify(sets),
    when,
  ]);
const withdraw = (user, reg, when = now) => pool.query(`select app.withdraw_entry($1, $2, $3)`, [user, reg, when]);
const drawJson = (cat, user = admin) => scalar(`select app.draw_json($1, $2) as r`, [cat, user]);
const matchJson = (id) => scalar(`select app.match_json(m) as r from tournament_matches m where m.id = $1`, [id]);
const matchRow = (id) => one(`select * from tournament_matches where id = $1`, [id]);
const knockout = async (cat, round) =>
  (await pool.query(`select * from tournament_matches where category_id = $1 and stage = 'knockout' and round = $2 order by position`, [cat, round])).rows;
const allMatches = async (cat) => (await pool.query(`select * from tournament_matches where category_id = $1`, [cat])).rows;
const playersOf = async (reg) => (await one(`select app.entry_players($1) as p`, [reg])).p;
const notesOf = (user, kind) =>
  pool.query(`select * from notifications where user_id = $1 and kind = $2 order by created_at, id`, [user, kind]).then((r) => r.rows);
const statusOf = async (reg) => (await one(`select status from tournament_registrations where id = $1`, [reg])).status;
const blocksOf = async (match) => (await pool.query(`select * from bookings where tournament_match_id = $1`, [match])).rows;
const schedule = (match, court, startsAt) =>
  pool.query(`select app.schedule_match($1, $2, $3, $4::timestamp, null, $5)`, [organizer, match, court, startsAt, now]);

/** A player with a padel level and rating hint (higher seeds stronger). */
async function player(name) {
  return createUser(pool, name);
}

async function venue(courts = 2) {
  const venueId = await addVenue(pool, { open: 7 * 60, close: 23 * 60 });
  await addOwner(pool, venueId, owner);
  const ids = [];
  for (let i = 0; i < courts; i++) ids.push(await addCourt(pool, venueId));
  return { venueId, courts: ids };
}

async function tournament({ venueId = null, sport = 'padel' } = {}) {
  const t = await addTournament(pool, { venueId, startsOn: day, endsOn: day2, sportId: sport });
  await pool.query(`insert into tournament_organizers (tournament_id, user_id) values ($1, $2)`, [t, organizer]);
  return t;
}

/** A category with the given players (or n new ones) and a published draw. */
async function published(t, { users, n = 4, format = 'knockout', size = null, advance = null, kind = 'singles', partners } = {}) {
  const cat = await addCategory(pool, t, { kind });
  await pool.query(`update tournament_categories set sort_order = (select count(*) from tournament_categories where tournament_id = $2) where id = $1`, [cat, t]);
  const entrants = users ?? (await Promise.all(Array.from({ length: n }, (_, i) => player(`P${i + 1}`))));
  const regs = await addEntries(pool, cat, entrants, { partners });
  await pool.query(`select app.make_draw($1, $2, $3, $4, $5, $6)`, [admin, cat, format, size, advance, now]);
  await pool.query(`select app.publish_draw($1, $2, $3)`, [admin, cat, now]);
  return { cat, users: entrants, regs };
}

/** The group match between x and y. */
const between = (cat, x, y) =>
  one(
    `select * from tournament_matches where category_id = $1 and stage = 'group'
       and ((side_a = $2 and side_b = $3) or (side_a = $3 and side_b = $2))`,
    [cat, x, y],
  );
const flip = (sets) => sets.map(([a, b]) => [b, a]);
/** A played result between x and y, the sets written from x's side. */
async function result(cat, x, y, sets, user = organizer) {
  const m = await between(cat, x, y);
  await score(user, m.id, 'played', null, m.side_a === x ? sets : flip(sets));
  return m;
}
async function walkover(cat, winner, loser) {
  const m = await between(cat, winner, loser);
  await score(organizer, m.id, 'walkover', m.side_a === winner ? 'a' : 'b');
  return m;
}
/** The group's members in seed order. */
async function members(cat, label) {
  const draw = await drawJson(cat);
  const g = draw.groups.find((x) => x.label === label);
  return draw.entries.filter((e) => e.group_id === g.id).map((e) => e.registration_id);
}
const winnerOf = (m) => (m.winner === 'a' ? m.side_a : m.winner === 'b' ? m.side_b : null);

// --- knockout ------------------------------------------------------------------------

test('knockout to a winner', async () => {
  const t = await tournament();
  const { cat } = await published(t, { n: 4 });
  const [s1, s2] = await knockout(cat, 1);

  await score(organizer, s1.id, 'played', null, [[6, 4], [6, 3]]);
  const draw = await one(`select first_score_at from tournament_draws where category_id = $1`, [cat]);
  assert.ok(draw.first_score_at);
  await score(organizer, s2.id, 'played', null, [[3, 6], [4, 6]]);

  const [final] = await knockout(cat, 2);
  assert.equal(final.side_a, s1.side_a);
  assert.equal(final.side_b, s2.side_b);
  assert.equal(final.status, 'ready');
  assert.equal((await drawJson(cat)).finished, false);

  await score(organizer, final.id, 'played', null, [[6, 1], [6, 2]]);
  const j = await drawJson(cat);
  assert.equal(j.winner, s1.side_a);
  assert.equal(j.runner_up, s2.side_b);
  assert.equal(j.finished, true);

  const done = await matchRow(s1.id);
  assert.equal(done.status, 'done');
  assert.equal(done.outcome, 'played');
  assert.equal(done.winner, 'a');
  assert.deepEqual(done.sets, [[6, 4], [6, 3]]);
  assert.equal(done.scored_by, organizer);

  for (const p of await playersOf(s1.side_a)) {
    const won = await notesOf(p, 'category_won');
    assert.equal(won.length, 1);
    assert.equal(won[0].category, 'tournaments');
    assert.equal(won[0].payload.category_id, cat);
    assert.equal(won[0].payload.tournament_id, t);
    assert.equal(won[0].payload.title.kk, null);
    // Two matches, two results.
    assert.equal((await notesOf(p, 'match_result')).length, 2);
  }
  for (const p of await playersOf(s2.side_b)) assert.equal((await notesOf(p, 'category_won')).length, 0);
  const [loser] = await playersOf(s1.side_b);
  const notes = await notesOf(loser, 'match_result');
  assert.equal(notes.length, 1);
  assert.equal(notes[0].payload.match_id, s1.id);
  assert.equal(notes[0].payload.category_id, cat);
  assert.ok((await pool.query(`select 1 from audit_log where action = 'enter_match_score' and entity_id = $1`, [s1.id])).rowCount > 0);

  // A waiting match (sides not known) or a strange outcome is refused.
  await expectError(score(organizer, s1.id, 'forfeit', 'a'), 'invalid_argument');
  await expectError(score(organizer, final.id, 'walkover', null), 'invalid_argument');
  await expectError(score(await player('Stranger'), final.id, 'walkover', 'a'), 'not_allowed');
  await expectError(score(organizer, '00000000-0000-0000-0000-000000000000', 'walkover', 'a'), 'not_found');
});

test('draw refused in knockout', async () => {
  const t = await tournament();
  const { cat } = await published(t, { n: 2 });
  const [final] = await knockout(cat, 1);
  await expectError(score(organizer, final.id, 'played', null, [[6, 4], [4, 6]]), 'draw_not_allowed');
  await expectError(score(organizer, final.id, 'played', null, [[0, 0]]), 'invalid_argument');
  // A decider is for sports without sets.
  await expectError(score(organizer, final.id, 'decider', 'a', [[2, 2]]), 'invalid_argument');
  // Retired: the score so far, unfinished.
  await score(organizer, final.id, 'retired', 'b', [[6, 4], [2, 1]]);
  assert.equal((await matchRow(final.id)).winner, 'b');

  const ft = await tournament({ sport: 'football' });
  const { cat: fc } = await published(ft, { n: 2 });
  const [ff] = await knockout(fc, 1);
  await expectError(score(organizer, ff.id, 'played', null, [[2, 2]]), 'draw_not_allowed');
  await expectError(score(organizer, ff.id, 'played', null, [[2, 1], [1, 0]]), 'invalid_argument');
  await expectError(score(organizer, ff.id, 'played', null, [[100, 1]]), 'invalid_argument');
  await expectError(score(organizer, ff.id, 'decider', 'a', [[2, 1]]), 'invalid_argument');
  await expectError(score(organizer, ff.id, 'decider', null, [[2, 2]]), 'invalid_argument');
  await score(organizer, ff.id, 'decider', 'a', [[2, 2]]);
  const m = await matchRow(ff.id);
  assert.equal(m.status, 'done');
  assert.equal(m.outcome, 'decider');
  assert.equal(m.winner, 'a');
  assert.deepEqual(m.sets, [[2, 2]]);
  assert.equal((await drawJson(fc)).winner, m.side_a);
});

test('football group allows a draw', async () => {
  const t = await tournament({ sport: 'football' });
  const { cat, regs } = await published(t, { n: 3, format: 'groups', size: 3, advance: 1 });
  const [x, y] = await members(cat, 'A');
  const m = await result(cat, x, y, [[1, 1]]);
  assert.equal((await matchRow(m.id)).winner, 'draw');
  const draw = await drawJson(cat);
  const standings = draw.groups[0].standings;
  assert.equal(standings.length, regs.length);
  for (const reg of [x, y]) {
    const row = standings.find((s) => s.registration_id === reg);
    assert.equal(row.played, 1);
    assert.equal(row.drawn, 1);
    assert.equal(row.points, 1);
    assert.equal(row.games_for, 1);
    assert.equal(row.games_against, 1);
  }
  assert.deepEqual(Object.keys(standings[0]).sort(), [
    'advancing', 'drawn', 'games_against', 'games_for', 'lost', 'place', 'played', 'points', 'registration_id', 'sets_against',
    'sets_for', 'withdrawn', 'won',
  ]);
  assert.deepEqual(standings.map((s) => s.place), [1, 2, 3]);
  // A decider is for knockout matches only.
  const [, , z] = await members(cat, 'A');
  const other = await between(cat, x, z);
  await expectError(score(organizer, other.id, 'decider', 'a', [[0, 0]]), 'invalid_argument');
});

test('correction moves the new winner on', async () => {
  const { venueId, courts } = await venue();
  const t = await tournament({ venueId });
  const { cat } = await published(t, { n: 8 });
  const [q1, q2] = await knockout(cat, 1);
  await score(organizer, q1.id, 'played', null, [[6, 4], [6, 4]]);
  let [semi] = await knockout(cat, 2);
  assert.equal(semi.side_a, q1.side_a);
  await schedule(semi.id, courts[0], at(day, 11, 30));

  await score(organizer, q1.id, 'played', null, [[4, 6], [3, 6]]);
  [semi] = await knockout(cat, 2);
  assert.equal(semi.side_a, q1.side_b);
  assert.equal(semi.status, 'waiting');
  assert.equal((await matchJson(semi.id)).starts_at, at(day, 11, 30));
  assert.equal((await blocksOf(semi.id)).length, 1);
  // Both sides heard about the entry and the correction.
  for (const reg of [q1.side_a, q1.side_b]) {
    for (const p of await playersOf(reg)) assert.equal((await notesOf(p, 'match_result')).length, 2);
  }
  // The same winner again: nothing moves.
  await score(organizer, q1.id, 'played', null, [[4, 6], [4, 6]]);
  assert.equal((await knockout(cat, 2))[0].side_a, q1.side_b);

  await score(organizer, q2.id, 'played', null, [[6, 0], [6, 0]]);
  [semi] = await knockout(cat, 2);
  assert.equal(semi.status, 'ready');
  // The other side of the semi-final hears when its opponent changes.
  await score(organizer, q2.id, 'played', null, [[0, 6], [0, 6]]);
  [semi] = await knockout(cat, 2);
  assert.equal(semi.side_b, q2.side_b);
  const [semiPlayer] = await playersOf(q1.side_b);
  const heard = (await notesOf(semiPlayer, 'match_result')).map((n) => n.payload.match_id);
  assert.ok(heard.includes(q2.id), 'the semi-final opponent is told');

  await score(organizer, semi.id, 'played', null, [[6, 2], [6, 2]]);
  await expectError(score(organizer, q1.id, 'played', null, [[6, 4], [6, 4]]), 'next_match_played');
  await expectError(score(organizer, q2.id, 'walkover', 'a'), 'next_match_played');
  // The semi itself can still be corrected while the final is unplayed.
  await score(organizer, semi.id, 'played', null, [[2, 6], [2, 6]]);
  assert.equal((await knockout(cat, 3))[0].side_a, q2.side_b);
});

// --- groups --------------------------------------------------------------------------

test('standings tie-breaks', async () => {
  // Three on 4 points, beating each other in a circle: set difference
  // decides; the walkover win counts its points but no sets.
  const t = await tournament();
  const { cat } = await published(t, { n: 4, format: 'groups', size: 4, advance: 2 });
  const [a, b, c, d] = await members(cat, 'A');
  await result(cat, a, b, [[6, 0], [6, 0]]);
  await result(cat, b, c, [[6, 4], [4, 6], [6, 4]]);
  await result(cat, c, a, [[6, 4], [4, 6], [6, 4]]);
  await result(cat, a, d, [[6, 0], [6, 0]]);
  await result(cat, b, d, [[6, 0], [6, 0]]);
  await walkover(cat, c, d);

  const standings = (await drawJson(cat)).groups[0].standings;
  assert.deepEqual(standings.map((s) => s.registration_id), [a, b, c, d]);
  assert.deepEqual(standings.map((s) => s.points), [4, 4, 4, 0]);
  assert.deepEqual(standings.map((s) => s.advancing), [true, true, false, false]);
  const rowC = standings[2];
  assert.equal(rowC.played, 3);
  assert.equal(rowC.won, 2);
  assert.equal(rowC.lost, 1);
  assert.equal(rowC.sets_for, 3);
  assert.equal(rowC.sets_against, 3);
  assert.equal(rowC.games_for, 16 + 14);
  assert.equal(rowC.withdrawn, false);
  const groupId = (await drawJson(cat)).groups[0].id;
  assert.deepEqual(await scalar(`select app.group_standings($1) as r`, [groupId]), standings);

  // Two level on points: head-to-head beats a better goal difference.
  const ft = await tournament({ sport: 'football' });
  const { cat: fc } = await published(ft, { n: 4, format: 'groups', size: 4, advance: 2 });
  const [fa, fb, fcc, fd] = await members(fc, 'A');
  await result(fc, fb, fcc, [[1, 0]]);
  await result(fc, fcc, fd, [[5, 0]]);
  await result(fc, fb, fd, [[1, 0]]);
  await result(fc, fa, fb, [[1, 0]]);
  await result(fc, fcc, fa, [[1, 0]]);
  await result(fc, fa, fd, [[0, 0]]);
  const table = (await drawJson(fc)).groups[0].standings;
  assert.deepEqual(table.map((s) => s.registration_id), [fb, fcc, fa, fd]);
  assert.deepEqual(table.map((s) => s.points), [4, 4, 3, 1]);
});

/** Plays a group of three: x1 beats both, x2 beats x3, with the given scores. */
async function playGroup(cat, [x1, x2, x3], { top = [[6, 0], [6, 0]], second = [[6, 0], [6, 0]], third = [[6, 0], [6, 0]] } = {}) {
  await result(cat, x1, x2, top);
  await result(cat, x1, x3, second);
  await result(cat, x2, x3, third);
}

test('groups fill the knockout', async () => {
  // Two groups of three, two advance. A1 is the best winner and A2 the
  // worst runner-up, so the seeded order would put them in one semi-final.
  const t = await tournament();
  const { cat } = await published(t, { n: 6, format: 'groups', size: 3, advance: 2 });
  const groupA = await members(cat, 'A');
  const groupB = await members(cat, 'B');
  await playGroup(cat, groupA, { top: [[6, 0], [6, 0]], second: [[6, 0], [6, 0]], third: [[6, 4], [6, 4]] });
  // Before the last match nothing is placed.
  await result(cat, groupB[0], groupB[1], [[6, 4], [7, 5]]);
  await result(cat, groupB[0], groupB[2], [[6, 4], [6, 4]]);
  for (const m of await knockout(cat, 1)) assert.equal(m.side_a, null);
  await result(cat, groupB[1], groupB[2], [[6, 0], [6, 0]]);

  const [s1, s2] = await knockout(cat, 1);
  assert.deepEqual([s1.side_a, s1.side_b], [groupA[0], groupB[1]]);
  assert.deepEqual([s2.side_a, s2.side_b], [groupB[0], groupA[1]]);
  assert.equal(s1.status, 'ready');
  assert.equal(s2.status, 'ready');

  // Three groups, one advances: four slots, the best winner gets the bye.
  const t2 = await tournament();
  const { cat: c3 } = await published(t2, { n: 9, format: 'groups', size: 3, advance: 1 });
  const [ga, gb, gc] = [await members(c3, 'A'), await members(c3, 'B'), await members(c3, 'C')];
  await playGroup(c3, ga, { top: [[6, 2], [6, 2]], second: [[6, 2], [6, 2]] });
  await playGroup(c3, gb, { top: [[6, 3], [6, 3]], second: [[6, 3], [6, 3]] });
  await playGroup(c3, gc, { top: [[6, 0], [6, 0]], second: [[6, 0], [6, 0]] });
  let [b1, b2] = await knockout(c3, 1);
  let [f] = await knockout(c3, 2);
  assert.deepEqual([b1.side_a, b1.b_empty, b1.status, b1.outcome, b1.winner], [gc[0], true, 'done', 'bye', 'a']);
  assert.deepEqual([b2.side_a, b2.side_b, b2.status], [ga[0], gb[0], 'ready']);
  assert.equal(f.side_a, gc[0]);

  // A group correction is still allowed (only a bye in the knockout); it
  // drops C1 below A1, so the bye moves.
  await result(c3, gc[0], gc[1], [[7, 6], [7, 6]]);
  [b1, b2] = await knockout(c3, 1);
  [f] = await knockout(c3, 2);
  assert.deepEqual([b1.side_a, b1.outcome], [ga[0], 'bye']);
  assert.deepEqual([b2.side_a, b2.side_b], [gc[0], gb[0]]);
  assert.equal(f.side_a, ga[0]);

  // Once a knockout match is played, the groups are final.
  await score(organizer, b2.id, 'played', null, [[6, 1], [6, 1]]);
  await expectError(result(c3, gc[0], gc[1], [[6, 0], [6, 0]]), 'next_match_played');
  await score(organizer, f.id, 'played', null, [[6, 1], [6, 1]]);
  const j = await drawJson(c3);
  assert.equal(j.finished, true);
  assert.equal(j.winner, ga[0]);
  assert.equal(j.runner_up, gc[0]);
});

test('single group', async () => {
  const t = await tournament();
  const { cat } = await published(t, { n: 3, format: 'groups', size: 3, advance: 1 });
  const group = await members(cat, 'A');
  assert.equal((await knockout(cat, 1)).length, 0);
  await result(cat, group[0], group[1], [[6, 0], [6, 0]]);
  await result(cat, group[0], group[2], [[6, 0], [6, 0]]);
  assert.equal((await drawJson(cat)).finished, false);
  await result(cat, group[1], group[2], [[6, 0], [6, 0]]);
  const j = await drawJson(cat);
  assert.equal(j.finished, true);
  assert.equal(j.winner, group[0]);
  assert.equal(j.runner_up, group[1]);
  for (const p of await playersOf(group[0])) assert.equal((await notesOf(p, 'category_won')).length, 1);

  // The champion deletes their account: the deletion succeeds, the result stays.
  const [champion] = await playersOf(group[0]);
  await pool.query(`select app.delete_account($1, $2)`, [champion, now]);
  assert.equal(await statusOf(group[0]), 'removed');
  const after = await drawJson(cat);
  assert.equal(after.winner, group[0]);
  assert.equal(after.runner_up, group[1]);
  for (const p of await playersOf(group[1])) assert.equal((await notesOf(p, 'category_won')).length, 0);
});

// --- withdrawals ---------------------------------------------------------------------

test('bracket with withdrawals completes', async () => {
  const t = await tournament();
  const { cat } = await published(t, { n: 8 });
  const [q1, q2, q3, q4] = await knockout(cat, 1);

  await withdraw(organizer, q1.side_a);
  let m = await matchRow(q1.id);
  assert.deepEqual([m.status, m.outcome, m.winner], ['done', 'walkover', 'b']);
  assert.equal(await statusOf(q1.side_a), 'removed');
  const reg = await one(`select admin_override from tournament_registrations where id = $1`, [q1.side_a]);
  assert.equal(reg.admin_override, true);
  for (const p of await playersOf(q1.side_a)) assert.equal((await notesOf(p, 'entry_withdrawn')).length, 1);
  assert.equal((await drawJson(cat)).entries.find((e) => e.registration_id === q1.side_a).withdrawn, true);

  await withdraw(organizer, q1.side_b);
  m = await matchRow(q1.id);
  assert.deepEqual([m.status, m.outcome, m.winner], ['done', 'none', null]);
  let [semi1, semi2] = await knockout(cat, 2);
  assert.deepEqual([semi1.side_a, semi1.a_empty, semi1.status], [null, true, 'waiting']);

  // Semi-final 1 is a walkover for whoever wins quarter-final 2.
  await score(organizer, q2.id, 'played', null, [[6, 3], [6, 3]]);
  [semi1] = await knockout(cat, 2);
  assert.deepEqual([semi1.side_b, semi1.status, semi1.outcome, semi1.winner], [q2.side_a, 'done', 'walkover', 'b']);
  let [final] = await knockout(cat, 3);
  assert.equal(final.side_a, q2.side_a);

  // A semi-finalist withdraws before their opponent is known.
  await score(organizer, q3.id, 'played', null, [[6, 3], [6, 3]]);
  await withdraw(organizer, q3.side_a);
  assert.equal((await matchRow(q3.id)).outcome, 'played');
  [, semi2] = await knockout(cat, 2);
  assert.deepEqual([semi2.side_a, semi2.a_empty, semi2.status], [null, true, 'waiting']);
  await score(organizer, q4.id, 'played', null, [[2, 6], [2, 6]]);
  [, semi2] = await knockout(cat, 2);
  assert.deepEqual([semi2.status, semi2.outcome, semi2.winner], ['done', 'walkover', 'b']);
  [final] = await knockout(cat, 3);
  assert.equal(final.side_b, q4.side_b);
  assert.equal(final.status, 'ready');

  await score(organizer, final.id, 'played', null, [[6, 1], [6, 1]]);
  const j = await drawJson(cat);
  assert.equal(j.finished, true);
  assert.equal(j.winner, q2.side_a);
  for (const x of await allMatches(cat)) assert.notEqual(x.status, 'waiting');

  // Withdrawn twice, or by someone who is not an organiser: refused.
  await expectError(withdraw(organizer, q1.side_a), 'not_found');
  await expectError(withdraw(await player('Stranger'), q2.side_b), 'not_allowed');
  assert.ok((await pool.query(`select 1 from audit_log where action = 'withdraw_entry'`)).rowCount >= 3);
});

test('group withdrawal', async () => {
  const t = await tournament();
  const { cat } = await published(t, { n: 4, format: 'groups', size: 4, advance: 2 });
  const [a, b, c, d] = await members(cat, 'A');
  const played = await result(cat, a, b, [[6, 2], [6, 2]]);
  await withdraw(organizer, a);

  const kept = await matchRow(played.id);
  assert.equal(kept.outcome, 'played');
  assert.equal(winnerOf(kept), a);
  for (const other of [c, d]) {
    const m = await between(cat, a, other);
    assert.deepEqual([m.status, m.outcome, winnerOf(m)], ['done', 'walkover', other]);
  }
  const standings = (await drawJson(cat)).groups[0].standings;
  const last = standings.at(-1);
  assert.equal(last.registration_id, a);
  assert.equal(last.withdrawn, true);
  assert.equal(last.advancing, false);
  assert.equal(last.points, 2);
  const rowB = standings.find((s) => s.registration_id === b);
  assert.equal(rowB.lost, 1);
  assert.equal(rowB.sets_against, 2);

  // The rest finish the group; the withdrawn entry never advances.
  await result(cat, b, c, [[6, 0], [6, 0]]);
  await result(cat, b, d, [[6, 0], [6, 0]]);
  await result(cat, c, d, [[6, 0], [6, 0]]);
  const [finalMatch] = await knockout(cat, 1);
  assert.deepEqual([finalMatch.side_a, finalMatch.side_b].sort(), [b, c].sort());
});

test('deleted account is withdrawn', async () => {
  const t = await tournament();
  const { cat } = await published(t, { n: 4 });
  const [s1, s2] = await knockout(cat, 1);
  await score(organizer, s2.id, 'played', null, [[6, 1], [6, 1]]);
  const [gone] = await playersOf(s1.side_a);
  await pool.query(`select app.delete_account($1, $2)`, [gone, now]);
  const m = await matchRow(s1.id);
  assert.deepEqual([m.status, m.outcome, m.winner], ['done', 'walkover', 'b']);
  assert.equal(await statusOf(s1.side_a), 'removed');
  assert.deepEqual((await matchRow(s2.id)).sets, [[6, 1], [6, 1]]);

  // A confirmed partner: the pair is withdrawn the same way.
  const pt = await tournament();
  const partners = [await player('Q1'), await player('Q2'), await player('Q3'), await player('Q4')];
  const { cat: pairs } = await published(pt, { n: 4, kind: 'pairs', partners });
  const [p1] = await knockout(pairs, 1);
  const [, partner] = await playersOf(p1.side_b);
  await pool.query(`select app.delete_account($1, $2)`, [partner, now]);
  const pm = await matchRow(p1.id);
  assert.deepEqual([pm.status, pm.outcome, pm.winner], ['done', 'walkover', 'a']);
  assert.equal(await statusOf(p1.side_b), 'removed');
});

test('withdraw from a redone draft', async () => {
  const t = await tournament();
  const { cat, regs, users } = await published(t, { n: 4 });
  await pool.query(`select app.redo_draw($1, $2, $3)`, [admin, cat, now]);
  await withdraw(organizer, regs[0]);
  assert.equal(await statusOf(regs[0]), 'removed');
  const draw = await one(`select * from tournament_draws where category_id = $1`, [cat]);
  assert.equal(draw.outdated, true);
  assert.equal(draw.status, 'draft');

  await pool.query(`select app.delete_account($1, $2)`, [users[1], now]);
  assert.equal(await statusOf(regs[1]), 'removed');

  // Not locked yet (a first draft): there is nothing to withdraw from.
  const { cat: open } = await (async () => {
    const c = await addCategory(pool, t);
    const r = await addEntries(pool, c, [await player('O1'), await player('O2')]);
    await pool.query(`select app.make_draw($1, $2, 'knockout', null, null, $3)`, [admin, c, now]);
    return { cat: c, regs: r };
  })();
  const openReg = (await one(`select id from tournament_registrations where category_id = $1 limit 1`, [open])).id;
  await expectError(withdraw(organizer, openReg), 'not_found');
});

// --- the schedule --------------------------------------------------------------------

test('advancing into a clash is flagged', async () => {
  const { venueId, courts } = await venue();
  const t = await tournament({ venueId });
  const shared = await player('Shared');
  const { cat: first, regs } = await published(t, { users: [shared, await player('A2'), await player('A3'), await player('A4')] });
  const { cat: second } = await published(t, { users: [shared, await player('B2')] });
  const semi = (await knockout(first, 1)).find((m) => m.side_a === regs[0] || m.side_b === regs[0]);
  const [final] = await knockout(first, 2);
  const [other] = await knockout(second, 1);
  await schedule(other.id, courts[0], at(day, 11, 30));
  await schedule(final.id, courts[1], at(day, 11, 30));
  assert.equal((await matchJson(final.id)).clash, false);

  await score(organizer, semi.id, 'walkover', semi.side_a === regs[0] ? 'a' : 'b');
  assert.equal((await matchJson(final.id)).clash, true);
  assert.equal((await matchJson(other.id)).clash, true);
});

test('walkover releases a future block', async () => {
  const { venueId, courts } = await venue();
  const t = await tournament({ venueId });
  const { cat } = await published(t, { n: 8 });
  const [s1, s2, s3] = await knockout(cat, 1);
  await schedule(s1.id, courts[0], at(day, 10));
  await schedule(s2.id, courts[1], at(day, 10));

  await score(organizer, s1.id, 'walkover', 'a');
  assert.equal((await blocksOf(s1.id)).length, 0);
  const j = await matchJson(s1.id);
  assert.equal(j.starts_at, null);
  assert.equal(j.court_id, null);

  // After the start the court was used: the block and time stay.
  await score(organizer, s2.id, 'walkover', 'b', null, tashkent(day, 10, 30));
  assert.equal((await blocksOf(s2.id)).length, 1);
  assert.equal((await matchJson(s2.id)).starts_at, at(day, 10));

  // A withdrawal's walkover before the start releases the block as well.
  await schedule(s3.id, courts[0], at(day, 13));
  await withdraw(organizer, s3.side_a);
  assert.equal((await blocksOf(s3.id)).length, 0);
  const w = await matchJson(s3.id);
  assert.deepEqual([w.outcome, w.starts_at, w.court_id], ['walkover', null, null]);
});

test('my next match', async () => {
  const t = await tournament();
  const { cat, users, regs } = await published(t, { n: 4 });
  const me = users[0];
  const mine = (await knockout(cat, 1)).find((m) => m.side_a === regs[0] || m.side_b === regs[0]);
  const bracket = (user) => scalar(`select app.tournament_bracket($1, $2) as r`, [user, t]);

  let b = await bracket(me);
  assert.equal(b.my_next_match.id, mine.id);
  assert.equal(b.my_next_match.category_id, cat);
  assert.equal(b.finished, false);
  assert.equal((await bracket(await player('Stranger'))).my_next_match, null);

  await score(organizer, mine.id, 'walkover', mine.side_a === regs[0] ? 'a' : 'b');
  const [final] = await knockout(cat, 2);
  b = await bracket(me);
  assert.equal(b.my_next_match.id, final.id);

  const list = await scalar(`select app.my_tournament_matches($1) as r`, [me]);
  assert.deepEqual(list.map((x) => x.id), [final.id, mine.id]);
  assert.equal(list[0].tournament_id, t);
  assert.equal(list[0].category_id, cat);
  assert.equal(list[0].title_en, 'Cup');
  assert.equal(list[0].title_uz, 'Kubok');
  assert.equal(list[0].title_ru, 'Кубок');

  const [other] = (await knockout(cat, 1)).filter((m) => m.id !== mine.id);
  await score(organizer, other.id, 'walkover', 'a');
  await score(organizer, final.id, 'walkover', 'a');
  b = await bracket(me);
  assert.equal(b.my_next_match, null);
  assert.equal(b.finished, true);
  // A category with entries but no draw yet: the tournament is not finished.
  const extra = await addCategory(pool, t);
  await addEntries(pool, extra, [await player('X1'), await player('X2')]);
  assert.equal((await bracket(me)).finished, false);
});

test('organiser plays', async () => {
  const t = await tournament();
  const { cat } = await published(t, { users: [organizer, await player('Rival')] });
  const [final] = await knockout(cat, 1);
  await score(organizer, final.id, 'played', null, [[6, 0], [6, 0]]);
  assert.equal((await matchRow(final.id)).status, 'done');
});

// --- the API -------------------------------------------------------------------------

test('the public calls', async () => {
  const t = await tournament();
  const { cat, users } = await published(t, { n: 4 });
  const [s1, s2] = await knockout(cat, 1);

  const draw = await asUser(pool, organizer, async (c) =>
    (await c.query(`select public.enter_match_score($1, 'played', null, $2::jsonb) as r`, [s1.id, JSON.stringify([[6, 2], [6, 2]])])).rows[0].r,
  );
  assert.equal(draw.category_id, cat);
  assert.equal(draw.matches.find((m) => m.id === s1.id).status, 'done');
  assert.equal(draw.finished, false);
  assert.equal(draw.winner, null);

  const after = await asUser(pool, organizer, async (c) => (await c.query(`select public.withdraw_entry($1) as r`, [s2.side_a])).rows[0].r);
  assert.equal(after.matches.find((m) => m.id === s2.id).outcome, 'walkover');

  const [me] = await playersOf(s1.side_a);
  const list = await asUser(pool, me, async (c) => (await c.query(`select public.my_tournament_matches() as r`)).rows[0].r);
  assert.equal(list.length, 2);
  await expectError(
    asUser(pool, users[1], (c) => c.query(`select public.enter_match_score($1, 'walkover', 'a')`, [s1.id])),
    'not_allowed',
  );
  await expectError(
    asUser(pool, organizer, (c) => c.query(`select public.withdraw_entry_service($1, now())`, [s1.side_a])),
    '42883',
  );
});
