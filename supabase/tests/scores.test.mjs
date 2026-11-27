// Milestone 7, Task 2: match scores, confirmation, disputes, the rating maths
// and admin resolution (design 2026-11-27-actra-m7-competitive §5.4-§5.6).
// The `app` functions are called with a fixed clock.

import assert from 'node:assert/strict';
import { after, before, beforeEach, test } from 'node:test';
import { asAnon, asUser, createUser, expectError, freshDb } from './helpers/db.mjs';
import { addAdmin, addRatedSports, addVenue, tashkent } from './helpers/fixtures.mjs';

let db;
let pool;
let venueId;

const now = tashkent('2026-11-22', 20);
const HOUR = 3600 * 1000;
/** The instant `hours` after `now`, as ISO text. */
const plus = (hours, from = now) => new Date(Date.parse(from) + hours * HOUR).toISOString();

before(async () => {
  db = await freshDb('scores');
  pool = db.pool;
  await addRatedSports(pool);
  venueId = await addVenue(pool, { name: 'Score venue' });
});
after(() => db.end());

// auto_confirm_scores looks at every pending result: start each test clean.
beforeEach(async () => {
  await pool.query('delete from match_results');
  await pool.query('delete from notifications');
  await pool.query('delete from audit_log');
});

const one = async (sql, params) => (await pool.query(sql, params)).rows[0];

async function player(name) {
  const id = await createUser(pool, name);
  await pool.query(`update profiles set city_id = 'tashkent' where id = $1`, [id]);
  return id;
}

/** A player with a rating (and its derived level) set directly. */
async function rated(name, rating, ratedGames = 0, sportId = 'padel') {
  const id = await player(name);
  await pool.query(
    `insert into player_ratings (user_id, sport_id, rating, rated_games, source) values ($1, $2, $3, $4, 'questionnaire')`,
    [id, sportId, rating, ratedGames],
  );
  await pool.query(`select app.sync_level($1, $2)`, [id, sportId]);
  return id;
}

const four = (rating, ratedGames = 0) =>
  Promise.all(['A', 'B', 'C', 'D'].map((n) => rated(`${n} ${rating}`, rating, ratedGames)));

/**
 * A 90-minute game that ended at `end` (default: one hour before `now`) with
 * those participants; the first is the host.
 */
async function finishedGame(sportId, playerIds, end = plus(-1)) {
  const start = new Date(Date.parse(end) - 1.5 * HOUR).toISOString();
  const g = await one(
    `insert into games (sport_id, city_id, venue_id, host_id, during, utc_offset_minutes, spots)
     values ($1, 'tashkent', $2, $3, tstzrange($4, $5), 300, $6) returning id`,
    [sportId, venueId, playerIds[0], start, end, Math.max(2, playerIds.length)],
  );
  for (const [i, id] of playerIds.entries()) {
    await pool.query(`insert into game_participants (game_id, user_id, joined_at) values ($1, $2, $3)`, [
      g.id,
      id,
      plus(-48 + i / 60),
    ]);
  }
  return g.id;
}

const enter = (user, gameId, a, b, sets, at = now) =>
  one(`select r.* from app.enter_score($1, $2, $3::uuid[], $4::uuid[], $5::jsonb, $6) r`, [
    user,
    gameId,
    a,
    b,
    JSON.stringify(sets),
    at,
  ]);
const confirm = (user, resultId, at = now) => one(`select r.* from app.confirm_score($1, $2, $3) r`, [user, resultId, at]);
const dispute = (user, resultId, reason, at = now) =>
  one(`select r.* from app.dispute_score($1, $2, $3, $4) r`, [user, resultId, reason, at]);
const autoConfirm = (at) => one(`select app.auto_confirm_scores($1) as n`, [at]).then((r) => r.n);
const resolve = (user, resultId, action, sets = null, at = now) =>
  pool.query(`select app.admin_resolve_score($1, $2, $3, $4::jsonb, $5)`, [
    user,
    resultId,
    action,
    sets === null ? null : JSON.stringify(sets),
    at,
  ]);

const ratingOf = (user, sportId = 'padel') =>
  one(`select rating::text from player_ratings where user_id = $1 and sport_id = $2`, [user, sportId]).then((r) => r?.rating ?? null);
const ratingRow = (user, sportId = 'padel') =>
  one(`select rating::text, rated_games, source from player_ratings where user_id = $1 and sport_id = $2`, [user, sportId]);
const levelOf = (user, sportId = 'padel') =>
  one(`select level from player_levels where user_id = $1 and sport_id = $2`, [user, sportId]).then((r) => r?.level ?? null);
const resultRow = (id) => one(`select * from match_results where id = $1`, [id]);
const events = (resultId) =>
  pool
    .query(
      `select user_id, old_rating::text as old, new_rating::text as new, delta::text as delta
       from rating_events where result_id = $1 order by user_id`,
      [resultId],
    )
    .then((r) => r.rows);
const eventOf = (resultId, user) =>
  one(`select old_rating::text as old, new_rating::text as new, delta::text as delta from rating_events where result_id = $1 and user_id = $2`, [
    resultId,
    user,
  ]);
const notices = (kind, resultId) =>
  pool
    .query(`select user_id, payload from notifications where kind = $1 and payload->>'result_id' = $2 order by user_id`, [
      kind,
      resultId,
    ])
    .then((r) => r.rows);
const gameJson = (gameId, user) => one(`select app.game_json(g, $2) as g from games g where g.id = $1`, [gameId, user]).then((r) => r.g);
const sorted = (ids) => [...ids].sort();

/** A doubles game between [a, b] and [c, d] with the score entered by a. */
async function doubles(players, sets, sportId = 'padel') {
  const [a, b, c, d] = players;
  const gameId = await finishedGame(sportId, players);
  const r = await enter(a, gameId, [a, b], [c, d], sets);
  return { gameId, resultId: r.id };
}

// --- confirming and the maths ----------------------------------------------

test('host enters and an opponent confirms', async () => {
  const [h, p, o1, o2] = await four('3.50');
  const gameId = await finishedGame('padel', [h, p, o1, o2]);
  const r = await enter(h, gameId, [h, p], [o1, o2], [[6, 4], [6, 4]]);
  assert.equal(r.status, 'pending');
  assert.equal(r.winner, 'a');
  assert.equal(r.entered_by, h);
  assert.equal(new Date(r.confirm_deadline).toISOString(), plus(24));
  assert.deepEqual((await notices('score_entered', r.id)).map((n) => n.user_id), sorted([p, o1, o2]));

  const confirmed = await confirm(o1, r.id);
  assert.equal(confirmed.status, 'confirmed');

  for (const u of [h, p]) assert.deepEqual(await ratingRow(u), { rating: '3.63', rated_games: 1, source: 'questionnaire' });
  for (const u of [o1, o2]) assert.deepEqual(await ratingRow(u), { rating: '3.37', rated_games: 1, source: 'questionnaire' });
  const ev = await events(r.id);
  assert.equal(ev.length, 4);
  assert.deepEqual(await eventOf(r.id, h), { old: '3.50', new: '3.63', delta: '0.13' });
  assert.deepEqual(await eventOf(r.id, o2), { old: '3.50', new: '3.37', delta: '-0.13' });

  const g = await gameJson(gameId, h);
  assert.equal(g.result.status, 'confirmed');
  assert.deepEqual(g.result.sets, [[6, 4], [6, 4]]);
  assert.deepEqual(sorted(g.result.side_a), sorted([h, p]));
  assert.deepEqual(sorted(g.result.side_b), sorted([o1, o2]));
  assert.deepEqual(g.result.confirmed_by, [o1]);
  assert.deepEqual(g.result.changes[h], { old: 3.5, new: 3.63 });
  assert.deepEqual(g.result.changes[o1], { old: 3.5, new: 3.37 });
  assert.equal(Object.keys(g.result.changes).length, 4);

  const updated = await notices('rating_updated', r.id);
  assert.deepEqual(updated.map((n) => n.user_id), sorted([h, p, o1, o2]));
  const mine = updated.find((n) => n.user_id === h).payload;
  assert.equal(mine.game_id, gameId);
  assert.equal(mine.old, 3.5);
  assert.equal(mine.new, 3.63);
  assert.equal(
    (await one(`select category from notifications where kind = 'rating_updated' and user_id = $1`, [h])).category,
    'ratings',
  );
});

test('established players move less', async () => {
  const players = await four('3.50', 10);
  const { resultId } = await doubles(players, [[6, 4], [6, 4]]);
  await confirm(players[2], resultId);
  assert.equal(await ratingOf(players[0]), '3.55');
  assert.equal(await ratingOf(players[1]), '3.55');
  assert.equal(await ratingOf(players[2]), '3.45');
  assert.equal(await ratingOf(players[3]), '3.45');
});

test('favourite wins small, underdog wins big', async () => {
  const fav = await rated('Favourite', '4.50');
  const dog = await rated('Underdog', '3.50');
  let gameId = await finishedGame('padel', [fav, dog]);
  let r = await enter(fav, gameId, [fav], [dog], [[6, 0], [6, 0]]);
  await confirm(dog, r.id);
  assert.equal(await ratingOf(fav), '4.53');
  assert.equal(await ratingOf(dog), '3.47');

  const fav2 = await rated('Favourite 2', '4.50');
  const dog2 = await rated('Underdog 2', '3.50');
  gameId = await finishedGame('padel', [fav2, dog2]);
  r = await enter(fav2, gameId, [fav2], [dog2], [[0, 6], [0, 6]]);
  assert.equal(r.winner, 'b');
  await confirm(dog2, r.id);
  assert.equal(await ratingOf(dog2), '3.84');
  assert.equal(await ratingOf(fav2), '4.16');
});

test('draw', async () => {
  const players = await four('3.50');
  const { resultId } = await doubles(players, [[6, 4], [4, 6]]);
  assert.equal((await resultRow(resultId)).winner, 'draw');
  await confirm(players[3], resultId);
  for (const u of players) assert.equal(await ratingOf(u), '3.50');
  const ev = await events(resultId);
  assert.equal(ev.length, 4);
  for (const e of ev) assert.equal(e.delta, '0.00');
});

test('winner: more sets, then more games', async () => {
  const players = await four('3.50');
  const gameId = await finishedGame('padel', players);
  const [a, b, c, d] = players;
  // Two sets to one for side b, though side a won more games.
  let r = await enter(a, gameId, [a, b], [c, d], [[6, 0], [4, 6], [5, 7]]);
  assert.equal(r.winner, 'b');
  // One set each, side a ahead on games.
  r = await enter(a, gameId, [a, b], [c, d], [[6, 0], [4, 6]]);
  assert.equal(r.winner, 'a');
});

test('partner confirming is not enough', async () => {
  const players = await four('3.50');
  const { gameId, resultId } = await doubles(players, [[6, 4], [6, 4]]);
  const r = await confirm(players[1], resultId);
  assert.equal(r.status, 'pending');
  assert.equal((await events(resultId)).length, 0);
  assert.deepEqual((await gameJson(gameId, players[0])).result.confirmed_by, [players[1]]);
  assert.equal('changes' in (await gameJson(gameId, players[0])).result, false);
  // The enterer cannot confirm their own score.
  await expectError(confirm(players[0], resultId), 'not_found');
});

test('confirm twice changes ratings once', async () => {
  const players = await four('3.50');
  const { resultId } = await doubles(players, [[6, 4], [6, 4]]);
  await confirm(players[2], resultId);
  await expectError(confirm(players[3], resultId), 'not_found');
  await expectError(confirm(players[2], resultId), 'not_found');
  assert.equal((await events(resultId)).length, 4);
  assert.equal(await ratingOf(players[0]), '3.63');
});

test('auto-confirm after 24 hours', async () => {
  const players = await four('3.50');
  const { resultId } = await doubles(players, [[6, 4], [6, 4]]);
  assert.equal(await autoConfirm(plus(23)), 0);
  assert.equal((await resultRow(resultId)).status, 'pending');
  assert.equal(await autoConfirm(plus(24)), 1);
  assert.equal((await resultRow(resultId)).status, 'confirmed');
  assert.equal(await ratingOf(players[0]), '3.63');
  assert.equal(await ratingOf(players[2]), '3.37');
  assert.equal(await autoConfirm(plus(25)), 0);
});

test('dispute freezes the result', async () => {
  const players = await four('3.50');
  const [a, b, c, d] = players;
  const { gameId, resultId } = await doubles(players, [[6, 4], [6, 4]]);
  const r = await dispute(c, resultId, `  ${'x'.repeat(400)}  `);
  assert.equal(r.status, 'disputed');
  assert.equal(r.dispute_by, c);
  assert.equal(r.dispute_reason, 'x'.repeat(300));
  assert.equal((await events(resultId)).length, 0);
  assert.equal(await autoConfirm(plus(48)), 0);
  assert.equal((await resultRow(resultId)).status, 'disputed');
  for (const u of players) assert.equal(await ratingOf(u), '3.50');
  assert.deepEqual((await notices('score_disputed', resultId)).map((n) => n.user_id), sorted([a, b, d]));
  assert.equal((await gameJson(gameId, a)).result.dispute_reason, 'x'.repeat(300));
  // Frozen: neither confirm nor another dispute.
  await expectError(confirm(d, resultId), 'not_found');
  await expectError(dispute(d, resultId, null), 'not_found');
});

test('host can correct a pending score', async () => {
  const players = await four('3.50');
  const [h, p, o1, o2] = players;
  const { gameId, resultId } = await doubles(players, [[6, 4], [6, 4]]);
  await confirm(p, resultId);
  const r = await enter(h, gameId, [h, o1], [p, o2], [[7, 5]], plus(1));
  assert.equal(r.id, resultId);
  assert.equal(r.status, 'pending');
  assert.equal(new Date(r.confirm_deadline).toISOString(), plus(25));
  const g = (await gameJson(gameId, h)).result;
  assert.deepEqual(g.confirmed_by, []);
  assert.deepEqual(g.sets, [[7, 5]]);
  assert.deepEqual(sorted(g.side_a), sorted([h, o1]));
  // Another participant may not overwrite it, even after the host's 24 hours.
  await expectError(enter(p, gameId, [p, h], [o1, o2], [[6, 0]], plus(24)), 'not_allowed');
  // Once confirmed, nobody can enter again.
  await confirm(p, resultId, plus(2));
  await expectError(enter(h, gameId, [h, o1], [p, o2], [[6, 0]], plus(3)), 'already_exists');
});

test('who may enter and when', async () => {
  const players = await four('3.50');
  const [h, p, o1, o2] = players;
  const gameId = await finishedGame('padel', players);
  const sides = [[h, p], [o1, o2]];
  // The game ended one hour before `now`.
  await expectError(enter(h, gameId, ...sides, [[6, 4]], plus(-1.5)), 'score_closed');
  await expectError(enter(h, gameId, ...sides, [[6, 4]], plus(-1 + 8 * 24)), 'score_closed');
  await expectError(enter(o1, gameId, [o1, o2], [h, p], [[6, 4]], now), 'not_allowed');
  const r = await enter(o1, gameId, [o1, o2], [h, p], [[6, 4]], plus(24));
  assert.equal(r.entered_by, o1);
  // Only the other side's word confirms it: here the host's.
  assert.equal((await confirm(h, r.id, plus(25))).status, 'confirmed');

  await expectError(enter(null, gameId, ...sides, [[6, 4]]), 'not_authenticated');
  const outsider = await player('Outsider');
  await expectError(enter(outsider, gameId, ...sides, [[6, 4]]), 'not_found');

  const football = await finishedGame('football', players);
  await expectError(enter(h, football, ...sides, [[6, 4]]), 'not_found');
  const cancelled = await finishedGame('padel', players);
  await pool.query(`update games set status = 'cancelled' where id = $1`, [cancelled]);
  await expectError(enter(h, cancelled, ...sides, [[6, 4]]), 'not_found');
});

test('bad scores are refused', async () => {
  const players = await four('3.50');
  const [h, p, o1, o2] = players;
  const x = await rated('Fifth', '3.50');
  const y = await rated('Not in the game', '3.50');
  const gameId = await finishedGame('padel', [h, p, o1, o2, x]);
  const bad = (a, b, sets) => expectError(enter(h, gameId, a, b, sets), 'invalid_argument');
  const ok = [[6, 4]];
  await bad([h, p], [o1], ok);
  await bad([h, p], [p, o1], ok);
  await bad([h, p], [o1, y], ok);
  await bad([p, o1], [o2, x], ok);
  await bad([h, p], [o1, o2], [[6, 4], [6, 4], [6, 4], [6, 4], [6, 4], [6, 4]]);
  await bad([h, p], [o1, o2], [[0, 0]]);
  await bad([h, p], [o1, o2], [[6]]);
  await bad([h, p], [o1, o2], [[31, 0]]);
  // Malformed input is refused the same way, never with a cast error.
  await bad([h, p], [o1, o2], []);
  await bad([h, p], [o1, o2], { a: 1 });
  await bad([h, p], [o1, o2], [[6.5, 4]]);
  await bad([h, p], [o1, o2], [['6', 4]]);
  await bad([h, p], [o1, o2], [[-1, 4]]);
  await bad([h, p], [o1, o2], [[1e20, 4]]);
  await bad([h, p], [o1, o2], [[6, null]]);
  await bad([h, p], [o1, o2], null);
  await bad([h, null], [o1, o2], ok);
  await bad([], [], ok);
  await bad(null, [o1], ok);
  assert.equal(await one(`select count(*)::int as n from match_results`).then((r) => r.n), 0);
});

// --- starting ratings and limits -------------------------------------------

test('unrated player starts at the others’ average', async () => {
  const a = await rated('Three', '3.00');
  const b = await rated('Four', '4.00');
  const c = await rated('Five', '5.00');
  const d = await player('New');
  const { resultId } = await doubles([a, b, c, d], [[6, 4], [6, 4]]);
  await confirm(c, resultId);
  assert.equal((await ratingRow(d)).source, 'first_result');
  assert.equal((await ratingRow(d)).rated_games, 1);
  assert.equal((await eventOf(resultId, d)).old, '4.00');
  assert.equal(await levelOf(d), 3);

  const strong = await Promise.all(['S1', 'S2', 'S3'].map((n) => rated(n, '6.00')));
  const e = await player('New 2');
  const second = await doubles([...strong, e], [[6, 4], [6, 4]]);
  await confirm(strong[2], second.resultId);
  assert.equal((await eventOf(second.resultId, e)).old, '5.00');
});

test('all unrated start at 2.50', async () => {
  const players = await Promise.all(['U1', 'U2', 'U3', 'U4'].map((n) => player(n)));
  const { resultId } = await doubles(players, [[6, 4], [6, 4]]);
  await confirm(players[2], resultId);
  for (const u of players) {
    assert.equal((await eventOf(resultId, u)).old, '2.50');
    assert.equal((await ratingRow(u)).source, 'first_result');
  }
  assert.equal(await ratingOf(players[0]), '2.63');
  assert.equal(await ratingOf(players[2]), '2.37');
});

test('auto-confirm gives unrated players their starting rating', async () => {
  const a = await rated('Auto three', '3.00');
  const b = await rated('Auto four', '4.00');
  const c = await rated('Auto five', '5.00');
  const d = await player('Auto new');
  const mixed = await doubles([a, b, c, d], [[6, 4], [6, 4]]);
  const fresh = await Promise.all(['N1', 'N2', 'N3', 'N4'].map((n) => player(n)));
  const unrated = await doubles(fresh, [[6, 4], [6, 4]]);
  assert.equal(await autoConfirm(plus(24)), 2);
  assert.equal((await eventOf(mixed.resultId, d)).old, '4.00');
  assert.equal((await ratingRow(d)).source, 'first_result');
  for (const u of fresh) assert.equal((await eventOf(unrated.resultId, u)).old, '2.50');
  assert.equal(await ratingOf(fresh[0]), '2.63');
});

test('rating stays within 1.00–7.00', async () => {
  const low = await rated('Lowest', '1.00');
  const other = await rated('Other', '1.00');
  let gameId = await finishedGame('padel', [other, low]);
  let r = await enter(other, gameId, [other], [low], [[6, 0], [6, 0]]);
  await confirm(low, r.id);
  assert.equal(await ratingOf(low), '1.00');
  assert.deepEqual(await eventOf(r.id, low), { old: '1.00', new: '1.00', delta: '0.00' });

  const top = await rated('Highest', '7.00');
  const rival = await rated('Rival', '7.00');
  gameId = await finishedGame('padel', [top, rival]);
  r = await enter(top, gameId, [top], [rival], [[6, 0], [6, 0]]);
  await confirm(rival, r.id);
  assert.equal(await ratingOf(top), '7.00');
});

test('levels follow ratings', async () => {
  // Established 2.95 beats 3.25 6-0 6-0: +0.10.
  const up = await rated('Climber', '2.95', 10);
  const down = await rated('Faller', '3.25', 10);
  assert.equal(await levelOf(up), 2);
  const gameId = await finishedGame('padel', [up, down]);
  const r = await enter(up, gameId, [up], [down], [[6, 0], [6, 0]]);
  await confirm(down, r.id);
  assert.equal(await ratingOf(up), '3.05');
  assert.equal(await levelOf(up), 3);
  assert.equal(await ratingOf(down), '3.15');
  assert.equal(await levelOf(down), 3);
});

// --- admin -----------------------------------------------------------------

test('admin confirms, corrects and voids a dispute', async () => {
  const admin = await addAdmin(pool, await player('Admin'));
  const audits = (resultId) =>
    pool.query(`select action from audit_log where entity = 'match_result' and entity_id = $1`, [resultId]).then((r) => r.rows);

  // Confirm as entered.
  let players = await four('3.50');
  let { resultId } = await doubles(players, [[6, 4], [6, 4]]);
  await dispute(players[2], resultId, 'wrong');
  await expectError(resolve(players[0], resultId, 'confirm'), 'not_allowed');
  await resolve(admin, resultId, 'confirm');
  assert.equal((await resultRow(resultId)).status, 'confirmed');
  assert.equal((await resultRow(resultId)).resolved_by, admin);
  assert.equal(await ratingOf(players[0]), '3.63');
  assert.equal((await events(resultId)).length, 4);
  assert.deepEqual((await audits(resultId)).map((a) => a.action), ['score_confirm']);
  const resolved = await notices('score_resolved', resultId);
  assert.deepEqual(resolved.map((n) => n.user_id), sorted(players));
  assert.equal(resolved[0].payload.action, 'confirm');
  // Only a disputed result can be confirmed by an admin.
  await expectError(resolve(admin, resultId, 'confirm'), 'not_found');

  // Correct: side b had been entered as the winner; side a won 6-0 6-0.
  players = await four('3.50');
  ({ resultId } = await doubles(players, [[4, 6], [4, 6]]));
  await dispute(players[2], resultId, null);
  await expectError(resolve(admin, resultId, 'correct', [[6, 0], [6, 0], [6, 0], [6, 0], [6, 0], [6, 0]]), 'invalid_argument');
  await expectError(resolve(admin, resultId, 'correct', null), 'invalid_argument');
  await resolve(admin, resultId, 'correct', [[6, 0], [6, 0]]);
  const corrected = await resultRow(resultId);
  assert.equal(corrected.status, 'confirmed');
  assert.deepEqual(corrected.sets, [[6, 0], [6, 0]]);
  assert.equal(corrected.winner, 'a');
  assert.equal(await ratingOf(players[0]), '3.69');
  assert.equal(await ratingOf(players[2]), '3.31');
  const correctAudit = await audits(resultId);
  assert.deepEqual(correctAudit.map((a) => a.action), ['score_correct']);
  const before = await one(`select before, after from audit_log where entity_id = $1`, [resultId]);
  assert.deepEqual(before.before.sets, [[4, 6], [4, 6]]);
  assert.deepEqual(before.after.sets, [[6, 0], [6, 0]]);
  assert.equal(before.after.status, 'confirmed');

  // Void a dispute: ratings stay as they were.
  players = await four('3.50');
  ({ resultId } = await doubles(players, [[6, 4], [6, 4]]));
  await dispute(players[2], resultId, null);
  await resolve(admin, resultId, 'void');
  assert.equal((await resultRow(resultId)).status, 'void');
  for (const u of players) assert.deepEqual(await ratingRow(u), { rating: '3.50', rated_games: 0, source: 'questionnaire' });
  assert.equal((await events(resultId)).length, 0);
  assert.deepEqual((await audits(resultId)).map((a) => a.action), ['score_void']);
  assert.equal((await notices('score_resolved', resultId))[0].payload.action, 'void');
  // A void result is final.
  await expectError(resolve(admin, resultId, 'void'), 'not_found');
  await expectError(resolve(admin, resultId, 'confirm'), 'not_found');
  await expectError(resolve(admin, resultId, 'reopen'), 'invalid_argument');
  const gameId = (await resultRow(resultId)).game_id;
  await expectError(enter(players[0], gameId, [players[0], players[1]], [players[2], players[3]], [[6, 0]]), 'already_exists');

  // A pending result can be voided too.
  players = await four('3.50');
  ({ resultId } = await doubles(players, [[6, 4], [6, 4]]));
  await resolve(admin, resultId, 'void');
  assert.equal((await resultRow(resultId)).status, 'void');
  assert.equal(await autoConfirm(plus(48)), 0);
});

test('void after a later result', async () => {
  const admin = await addAdmin(pool, await player('Admin 2'));
  const [a, b, c, d] = await four('3.50');
  const first = await doubles([a, b, c, d], [[6, 4], [6, 4]]);
  await confirm(c, first.resultId);
  assert.equal(await ratingOf(a), '3.63');

  const [e, f, g] = await Promise.all(['E', 'F', 'G'].map((n) => rated(n, '3.20')));
  const second = await doubles([a, e, f, g], [[6, 2], [6, 3]]);
  await confirm(f, second.resultId);
  const r2 = await ratingOf(a);
  assert.equal((await ratingRow(a)).rated_games, 2);
  const secondEvents = await events(second.resultId);

  await resolve(admin, first.resultId, 'void');
  const expected = (Number(r2) - 0.13).toFixed(2);
  assert.deepEqual(await ratingRow(a), { rating: expected, rated_games: 1, source: 'questionnaire' });
  assert.equal(await levelOf(a), Math.min(5, Math.floor(Number(expected))));
  assert.equal((await events(first.resultId)).length, 0);
  assert.deepEqual(await events(second.resultId), secondEvents);
  // The others in the voided result are back where they started.
  for (const u of [b, c, d]) assert.deepEqual(await ratingRow(u), { rating: '3.50', rated_games: 0, source: 'questionnaire' });
  assert.equal((await resultRow(first.resultId)).status, 'void');
  assert.equal('changes' in (await gameJson(first.gameId, a)).result, false);
});

// --- what the app calls ----------------------------------------------------

test('client calls', async () => {
  const players = await four('3.50');
  const [h, p, o1, o2] = players;
  // public.* runs on the real clock.
  const gameId = await finishedGame('padel', players, new Date(Date.now() - HOUR).toISOString());
  const g = await asUser(pool, h, (c) =>
    c
      .query(`select public.enter_score($1, $2::uuid[], $3::uuid[], $4::jsonb) as g`, [
        gameId,
        [h, p],
        [o1, o2],
        JSON.stringify([[6, 4], [6, 4]]),
      ])
      .then((r) => r.rows[0].g),
  );
  assert.equal(g.id, gameId);
  assert.equal(g.result.status, 'pending');
  const resultId = g.result.id;

  const disputed = await asUser(pool, o1, (c) =>
    c.query(`select public.dispute_score($1) as g`, [resultId]).then((r) => r.rows[0].g),
  );
  assert.equal(disputed.result.status, 'disputed');
  await pool.query(`update match_results set status = 'pending' where id = $1`, [resultId]);
  const confirmed = await asUser(pool, o2, (c) =>
    c.query(`select public.confirm_score($1) as g`, [resultId]).then((r) => r.rows[0].g),
  );
  assert.equal(confirmed.result.status, 'confirmed');
  assert.equal(confirmed.result.changes[h].new, 3.63);

  await expectError(
    asUser(pool, h, (c) => c.query(`select public.admin_resolve_score($1, 'void')`, [resultId])),
    'not_allowed',
  );
  await expectError(
    asAnon(pool, (c) =>
      c.query(`select public.enter_score($1, $2::uuid[], $3::uuid[], $4::jsonb)`, [gameId, [h, p], [o1, o2], '[[6,4]]']),
    ),
    '42501',
  );
  await expectError(asAnon(pool, (c) => c.query(`select public.confirm_score($1)`, [resultId])), '42501');
  await expectError(asUser(pool, h, (c) => c.query(`select app.auto_confirm_scores(now())`)), '42501');
  await expectError(asUser(pool, h, (c) => c.query(`select * from match_results`)), '42501');
  await expectError(asUser(pool, h, (c) => c.query(`select * from rating_events`)), '42501');
});
