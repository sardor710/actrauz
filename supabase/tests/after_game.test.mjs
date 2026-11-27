// Milestone 7, Task 8: after a game — thumbs up/down, "didn't show up"
// reports and their majority rule, abuse reports, the sportsmanship summary
// and the admin review (design 2026-11-27-actra-m7-competitive §6).
// The `app` functions are called with a fixed clock; the client calls at the
// end use games built from the real clock, because public.* passes now().

import assert from 'node:assert/strict';
import { after, before, beforeEach, test } from 'node:test';
import { asAnon, asUser, createUser, expectError, freshDb } from './helpers/db.mjs';
import { addAdmin, addCourt, addRatedSports, addVenue, tashkent } from './helpers/fixtures.mjs';

let db;
let pool;
let venueId;
let courtId;

const now = tashkent('2026-11-22', 20);
const HOUR = 3600 * 1000;
/** The instant `hours` after `from` (default `now`), as ISO text. */
const plus = (hours, from = now) => new Date(Date.parse(from) + hours * HOUR).toISOString();

before(async () => {
  db = await freshDb('after_game');
  pool = db.pool;
  await addRatedSports(pool);
  venueId = await addVenue(pool, { name: 'After venue' });
  courtId = await addCourt(pool, venueId);
});
after(() => db.end());

// The admin review lists every dispute and open report: start each test clean.
beforeEach(async () => {
  await pool.query('delete from match_results');
  await pool.query('delete from abuse_reports');
  await pool.query('delete from notifications');
  await pool.query('delete from audit_log');
});

const one = async (sql, params) => (await pool.query(sql, params)).rows[0];

async function player(name) {
  const id = await createUser(pool, name);
  await pool.query(`update profiles set city_id = 'tashkent' where id = $1`, [id]);
  return id;
}
const players = (...names) => Promise.all(names.map((n) => player(n)));

/**
 * A 90-minute padel game that ended at `end` (default: one hour before `now`)
 * with those participants, the first one hosting. Everyone joined two days
 * before the start, except the players in `late`, who joined ten minutes
 * after it.
 */
async function finishedGame(playerIds, { end = plus(-1), late = [], bookingId = null } = {}) {
  const start = new Date(Date.parse(end) - 1.5 * HOUR).toISOString();
  const g = await one(
    `insert into games (sport_id, city_id, venue_id, host_id, during, utc_offset_minutes, spots, booking_id)
     values ('padel', 'tashkent', $1, $2, tstzrange($3, $4), 300, $5, $6) returning id`,
    [venueId, playerIds[0], start, end, Math.max(2, playerIds.length), bookingId],
  );
  for (const [i, id] of playerIds.entries()) {
    const joined = late.includes(id) ? plus(1 / 6, start) : plus(-48 + i / 60, start);
    await pool.query(`insert into game_participants (game_id, user_id, joined_at) values ($1, $2, $3)`, [g.id, id, joined]);
  }
  return g.id;
}

/** The finished-game job, as it runs every ten minutes. */
const completeGames = (at = now) => pool.query(`select app.complete_games($1)`, [at]);

const vote = (user, gameId, target, up, at = now) =>
  pool.query(`select app.vote_player($1, $2, $3, $4, $5)`, [user, gameId, target, up, at]);
const noShow = (user, gameId, target, reported = true, at = now) =>
  pool.query(`select app.report_no_show($1, $2, $3, $4, $5)`, [user, gameId, target, reported, at]);
const report = (user, target, gameId, reason = 'language', details = null, at = now) =>
  one(`select app.report_player($1, $2, $3, $4, $5, $6) as id`, [user, target, gameId, reason, details, at]).then((r) => r.id);
const sportsmanship = (user) => one(`select app.sportsmanship($1) as s`, [user]).then((r) => r.s);
const review = (user) => one(`select app.admin_review($1) as r`, [user]).then((r) => r.r);
const closeReport = (user, id, note, at = now) => pool.query(`select app.admin_close_report($1, $2, $3, $4)`, [user, id, note, at]);

const votesBy = (voter, gameId) =>
  pool
    .query(`select target_id, up, updated_at from game_votes where voter_id = $1 and game_id = $2 order by target_id`, [voter, gameId])
    .then((r) => r.rows);
/** The reliability events about this game a player has, as "kind delta". */
const gameEvents = (user, gameId) =>
  pool
    .query(`select kind || ' ' || delta as e from reliability_events where user_id = $1 and ref = $2 order by kind`, [user, gameId])
    .then((r) => r.rows.map((x) => x.e));
const notices = (kind, gameId) =>
  pool
    .query(`select user_id, category, payload from notifications where kind = $1 and payload->>'game_id' = $2 order by user_id`, [
      kind,
      gameId,
    ])
    .then((r) => r.rows);
const resultRow = (id) => one(`select * from match_results where id = $1`, [id]);
const sorted = (ids) => [...ids].sort();

// --- votes -------------------------------------------------------------------

test('vote up, change, remove', async () => {
  const [h, a, b] = await players('Vote host', 'Vote A', 'Vote B');
  const gameId = await finishedGame([h, a, b]);

  await vote(a, gameId, h, true);
  await vote(a, gameId, b, true, plus(1));
  assert.deepEqual(
    (await votesBy(a, gameId)).map((v) => [v.target_id, v.up]),
    sorted([h, b]).map((id) => [id, true]),
  );

  await vote(a, gameId, b, false, plus(2));
  const changed = (await votesBy(a, gameId)).find((v) => v.target_id === b);
  assert.equal(changed.up, false);
  assert.equal(new Date(changed.updated_at).toISOString(), plus(2));
  assert.equal((await votesBy(a, gameId)).length, 2);

  await vote(a, gameId, b, null, plus(3));
  assert.deepEqual((await votesBy(a, gameId)).map((v) => v.target_id), [h]);
  // Removing a vote that is not there does nothing.
  await vote(a, gameId, b, null, plus(3));
  assert.deepEqual((await votesBy(a, gameId)).map((v) => v.target_id), [h]);
});

test('votes need a finished shared game', async () => {
  const [h, a, outsider, gone] = await players('Need host', 'Need A', 'Outsider', 'Gone');
  const gameId = await finishedGame([h, a, gone]);

  const upcoming = await finishedGame([h, a], { end: plus(2) });
  await expectError(vote(a, upcoming, h, true), 'not_found');
  await expectError(vote(outsider, gameId, h, true), 'not_found');
  await expectError(vote(a, gameId, outsider, true), 'not_found');
  await expectError(vote(a, gameId, a, true), 'not_found');
  await expectError(vote(a, gameId, h, true, plus(-1 + 8 * 24)), 'score_closed');
  // Open until exactly 7 days after the end.
  await vote(a, gameId, h, true, plus(-1 + 7 * 24 - 1 / 60));
  await expectError(vote(a, gameId, h, false, plus(-1 + 7 * 24)), 'score_closed');

  await pool.query(`update profiles set deleted_at = $2 where id = $1`, [gone, now]);
  await expectError(vote(a, gameId, gone, true), 'not_found');
  await expectError(vote(gone, gameId, a, true), 'not_authenticated');
  await expectError(vote(null, gameId, a, true), 'not_authenticated');

  const cancelled = await finishedGame([h, a]);
  await pool.query(`update games set status = 'cancelled' where id = $1`, [cancelled]);
  await expectError(vote(a, cancelled, h, true), 'not_found');
});

test('sportsmanship hides small samples', async () => {
  const [t, v1, v2, v3, v4, v5] = await players('Sport T', 'V1', 'V2', 'V3', 'V4', 'V5');
  const gameId = await finishedGame([t, v1, v2, v3, v4, v5]);
  assert.deepEqual(await sportsmanship(t), { votes: 0, percent: null });

  await vote(v1, gameId, t, true);
  await vote(v2, gameId, t, true);
  await vote(v3, gameId, t, true);
  await vote(v4, gameId, t, false);
  // Votes given do not count, only votes received.
  await vote(t, gameId, v1, true);
  assert.deepEqual(await sportsmanship(t), { votes: 4, percent: null });

  await vote(v5, gameId, t, true);
  assert.deepEqual(await sportsmanship(t), { votes: 5, percent: 80 });
  const profile = await one(`select app.player_json(p) as j from profiles p where p.id = $1`, [t]).then((r) => r.j);
  assert.deepEqual(profile.sportsmanship, { votes: 5, percent: 80 });
});

// --- no-shows ------------------------------------------------------------------

test('majority no-show', async () => {
  const [h, a, b, t] = await players('Maj host', 'Maj A', 'Maj B', 'Maj T');
  const gameId = await finishedGame([h, a, b, t]);
  await completeGames();
  assert.deepEqual(await gameEvents(t, gameId), ['game_completed 2']);

  await noShow(a, gameId, t);
  assert.deepEqual(await gameEvents(t, gameId), ['game_completed 2']);
  assert.deepEqual(await notices('no_show_recorded', gameId), []);

  await noShow(b, gameId, t, true, plus(1));
  assert.deepEqual(await gameEvents(t, gameId), ['no_show -20']);
  const recorded = await notices('no_show_recorded', gameId);
  assert.deepEqual(recorded.map((n) => n.user_id), [t]);
  assert.equal(recorded[0].category, 'games');
  assert.equal(recorded[0].payload.sport_id, 'padel');
  assert.ok(recorded[0].payload.starts_local);
  assert.equal(
    new Date((await one(`select created_at from reliability_events where user_id = $1 and ref = $2`, [t, gameId])).created_at).toISOString(),
    plus(1),
  );

  await noShow(h, gameId, t, true, plus(2));
  assert.deepEqual(await gameEvents(t, gameId), ['no_show -20']);
  assert.equal((await notices('no_show_recorded', gameId)).length, 1);
  // The reporters keep their own credit.
  for (const u of [h, a, b]) assert.deepEqual(await gameEvents(u, gameId), ['game_completed 2']);
  // Reporting twice is one report.
  await noShow(a, gameId, t, true, plus(3));
  assert.equal((await one(`select count(*)::int as n from game_no_show_reports where game_id = $1`, [gameId])).n, 3);
});

test('two reports at once still make a majority', async () => {
  const [h, a, b, t] = await players('Race host', 'Race A', 'Race B', 'Race T');
  const gameId = await finishedGame([h, a, b, t]);
  const first = await db.connect();
  const second = await db.connect();
  try {
    await first.query('begin');
    await second.query('begin');
    await first.query(`select app.report_no_show($1, $2, $3, true, $4)`, [a, gameId, t, now]);
    // Waits for the first transaction's lock on the game row.
    const waiting = second.query(`select app.report_no_show($1, $2, $3, true, $4)`, [b, gameId, t, now]);
    await new Promise((resolve) => setTimeout(resolve, 200));
    await first.query('commit');
    await waiting;
    await second.query('commit');
  } finally {
    first.release();
    second.release();
  }
  assert.deepEqual(await gameEvents(t, gameId), ['no_show -20']);
});

test('three-player game needs both others', async () => {
  const [h, a, t] = await players('Three host', 'Three A', 'Three T');
  const gameId = await finishedGame([h, a, t]);
  await noShow(a, gameId, t);
  assert.deepEqual(await gameEvents(t, gameId), []);
  await noShow(h, gameId, t);
  assert.deepEqual(await gameEvents(t, gameId), ['no_show -20']);
});

test('two-player game never reaches a majority', async () => {
  const [h, t] = await players('Two host', 'Two T');
  const gameId = await finishedGame([h, t]);
  await noShow(h, gameId, t);
  assert.deepEqual(await gameEvents(t, gameId), []);
  assert.deepEqual(await notices('no_show_recorded', gameId), []);
});

test('withdrawing undoes the penalty', async () => {
  const [h, a, b, t] = await players('Undo host', 'Undo A', 'Undo B', 'Undo T');
  const gameId = await finishedGame([h, a, b, t]);
  await completeGames();
  await noShow(a, gameId, t);
  await noShow(b, gameId, t);
  assert.deepEqual(await gameEvents(t, gameId), ['no_show -20']);

  await noShow(a, gameId, t, false, plus(10));
  assert.deepEqual(await gameEvents(t, gameId), ['game_completed 2']);
  assert.equal((await one(`select count(*)::int as n from game_no_show_reports where game_id = $1`, [gameId])).n, 1);

  // Back to a majority: the penalty again, and the player hears again.
  await noShow(h, gameId, t, true, plus(11));
  assert.deepEqual(await gameEvents(t, gameId), ['no_show -20']);
  assert.equal((await notices('no_show_recorded', gameId)).length, 2);

  // Withdrawing a report that never made a majority gives no credit.
  const [h2, a2, t2] = await players('Lone host', 'Lone A', 'Lone T');
  const lone = await finishedGame([h2, a2, t2]);
  await noShow(a2, lone, t2);
  await noShow(a2, lone, t2, false);
  assert.deepEqual(await gameEvents(t2, lone), []);
});

test('late joiners get neither the penalty nor the credit', async () => {
  const [h, a, b, t] = await players('Late host', 'Late A', 'Late B', 'Late T');
  const gameId = await finishedGame([h, a, b, t], { late: [t] });
  await completeGames();
  assert.deepEqual(await gameEvents(t, gameId), []);
  await noShow(a, gameId, t);
  await noShow(b, gameId, t);
  assert.deepEqual(await gameEvents(t, gameId), []);
  assert.deepEqual(await notices('no_show_recorded', gameId), []);
  await noShow(a, gameId, t, false);
  assert.deepEqual(await gameEvents(t, gameId), []);
});

test('the finished-game job gives no credit to a recorded no-show', async () => {
  const [h, a, b, t] = await players('Early host', 'Early A', 'Early B', 'Early T');
  const gameId = await finishedGame([h, a, b, t]);
  // A majority before the job has run: nothing to take away yet.
  await noShow(a, gameId, t);
  await noShow(b, gameId, t);
  assert.deepEqual(await gameEvents(t, gameId), ['no_show -20']);
  await completeGames();
  assert.deepEqual(await gameEvents(t, gameId), ['no_show -20']);
  for (const u of [h, a, b]) assert.deepEqual(await gameEvents(u, gameId), ['game_completed 2']);
});

test('venue no-show is not doubled', async () => {
  const [h, a, b, c] = await players('Venue host', 'Venue A', 'Venue B', 'Venue C');
  const end = plus(-1);
  const booking = await one(
    `insert into bookings (user_id, venue_id, court_id, during, utc_offset_minutes, slot_count, total_price, currency, status)
     values ($1, $2, $3, tstzrange($4, $5), 300, 1, 180000, 'UZS', 'no_show') returning id`,
    [h, venueId, courtId, plus(-1.5, end), end],
  );
  await pool.query(`select app.reliability_event($1, 'no_show', $2, $3)`, [h, booking.id, now]);
  const gameId = await finishedGame([h, a, b, c], { end, bookingId: booking.id });
  await completeGames();

  await noShow(a, gameId, h);
  await noShow(b, gameId, h);
  await noShow(c, gameId, h);
  // The venue's mark stands alone: no second penalty, no notice.
  assert.deepEqual(await gameEvents(h, gameId), ['game_completed 2']);
  assert.deepEqual(await gameEvents(h, booking.id), ['no_show -20']);
  assert.deepEqual(await notices('no_show_recorded', gameId), []);

  // Another player in the same game is penalised as usual.
  await noShow(h, gameId, c);
  await noShow(a, gameId, c);
  assert.deepEqual(await gameEvents(c, gameId), ['no_show -20']);
});

test('no-show reports close after 48 hours', async () => {
  const [h, a, b, t] = await players('Window host', 'Window A', 'Window B', 'Window T');
  const gameId = await finishedGame([h, a, b, t]); // ended at plus(-1)
  await expectError(noShow(a, await finishedGame([h, a, t], { end: plus(1) }), t), 'not_found');
  await noShow(a, gameId, t, true, plus(47 - 1 / 60));
  await expectError(noShow(b, gameId, t, true, plus(47)), 'score_closed');
  await expectError(noShow(a, gameId, t, false, plus(48)), 'score_closed');
  assert.equal((await one(`select count(*)::int as n from game_no_show_reports where game_id = $1`, [gameId])).n, 1);

  const [outsider] = await players('Window outsider');
  await expectError(noShow(outsider, gameId, t), 'not_found');
  await expectError(noShow(a, gameId, outsider), 'not_found');
  await expectError(noShow(a, gameId, a), 'not_found');
  await expectError(noShow(null, gameId, t), 'not_authenticated');
  await expectError(noShow(a, gameId, t, null), 'invalid_argument');
});

test('no-show against a player in a result', async () => {
  const enter = (user, gameId, a, b) =>
    one(`select r.* from app.enter_score($1, $2, $3::uuid[], $4::uuid[], '[[6, 4], [6, 4]]', $5) r`, [user, gameId, a, b, now]);
  const ratings = (ids) =>
    pool
      .query(`select user_id, rating::text, rated_games from player_ratings where user_id = any ($1) order by user_id`, [ids])
      .then((r) => r.rows);

  // Pending -> disputed, for the admin.
  const [h, a, b, t] = await players('Res host', 'Res A', 'Res B', 'Res T');
  const pendingGame = await finishedGame([h, a, b, t]);
  const pending = await enter(h, pendingGame, [h, a], [b, t]);
  await pool.query('delete from notifications');
  await noShow(a, pendingGame, t);
  assert.equal((await resultRow(pending.id)).status, 'pending');
  await noShow(b, pendingGame, t);
  const disputed = await resultRow(pending.id);
  assert.equal(disputed.status, 'disputed');
  assert.equal(disputed.dispute_reason, 'no_show');
  assert.equal(disputed.dispute_by, null);
  assert.equal(disputed.flagged_no_show, false);
  const told = await notices('score_disputed', pendingGame);
  assert.deepEqual(told.map((n) => n.user_id), sorted([h, a, b, t]));
  assert.equal(told[0].category, 'ratings');
  assert.equal(told[0].payload.result_id, pending.id);
  // A third report changes nothing more.
  await noShow(h, pendingGame, t);
  assert.equal((await notices('score_disputed', pendingGame)).length, 4);

  // Confirmed -> flagged, ratings untouched.
  const [h2, a2, b2, t2] = await players('Conf host', 'Conf A', 'Conf B', 'Conf T');
  const confirmedGame = await finishedGame([h2, a2, b2, t2]);
  const confirmed = await enter(h2, confirmedGame, [h2, a2], [b2, t2]);
  await pool.query(`select app.confirm_score($1, $2, $3)`, [b2, confirmed.id, now]);
  const before = await ratings([h2, a2, b2, t2]);
  const eventsBefore = (await one(`select count(*)::int as n from rating_events where result_id = $1`, [confirmed.id])).n;
  await pool.query('delete from notifications');
  await noShow(h2, confirmedGame, t2);
  await noShow(a2, confirmedGame, t2);
  const flagged = await resultRow(confirmed.id);
  assert.equal(flagged.status, 'confirmed');
  assert.equal(flagged.flagged_no_show, true);
  assert.equal(flagged.dispute_reason, null);
  assert.deepEqual(await ratings([h2, a2, b2, t2]), before);
  assert.equal((await one(`select count(*)::int as n from rating_events where result_id = $1`, [confirmed.id])).n, eventsBefore);
  assert.deepEqual(await notices('score_disputed', confirmedGame), []);

  // A result the reported player is not in stays as it is.
  const [h3, a3, b3, t3] = await players('Out host', 'Out A', 'Out B', 'Out T');
  const otherGame = await finishedGame([h3, a3, b3, t3]);
  const singles = await enter(h3, otherGame, [h3], [a3]);
  await noShow(a3, otherGame, t3);
  await noShow(b3, otherGame, t3);
  await noShow(h3, otherGame, t3);
  assert.deepEqual(await gameEvents(t3, otherGame), ['no_show -20']);
  assert.equal((await resultRow(singles.id)).status, 'pending');
});

test('a score cannot name a recorded no-show', async () => {
  const [h, a, b, t] = await players('Late score host', 'Late score A', 'Late score B', 'Late score T');
  const gameId = await finishedGame([h, a, b, t]);
  await noShow(a, gameId, t);
  await noShow(b, gameId, t);
  const enter = (sideA, sideB) =>
    pool.query(`select app.enter_score($1, $2, $3::uuid[], $4::uuid[], '[[6, 4]]', $5)`, [h, gameId, sideA, sideB, now]);
  await expectError(enter([h, a], [b, t]), 'invalid_argument');
  await expectError(enter([h, t], [a, b]), 'invalid_argument');
  // Without them the score goes in as usual.
  await enter([h], [a]);
  assert.equal((await one(`select status from match_results where game_id = $1`, [gameId])).status, 'pending');
});

test('venue mark after a peer majority leaves one penalty', async () => {
  const admin = await addAdmin(pool, await player('Mark admin'));
  const [h, a, b, c] = await players('Mark host', 'Mark A', 'Mark B', 'Mark C');
  const end = plus(-30);
  const booking = await one(
    `insert into bookings (user_id, venue_id, court_id, during, utc_offset_minutes, slot_count, total_price, currency, status)
     values ($1, $2, $3, tstzrange($4, $5), 300, 1, 180000, 'UZS', 'confirmed') returning id`,
    [h, venueId, courtId, plus(-1.5, end), end],
  );
  const gameId = await finishedGame([h, a, b, c], { end, bookingId: booking.id });
  await noShow(a, gameId, h);
  await noShow(b, gameId, h);
  assert.deepEqual(await gameEvents(h, gameId), ['no_show -20']);

  const mark = (outcome) => pool.query(`select app.owner_mark_booking($1, $2, $3, $4)`, [admin, booking.id, outcome, now]);
  const noShows = () =>
    pool
      .query(`select ref from reliability_events where user_id = $1 and kind = 'no_show'`, [h])
      .then((r) => r.rows.map((x) => x.ref));
  await mark('no_show');
  assert.deepEqual(await noShows(), [booking.id]);
  // A later report finds the venue's mark and adds nothing.
  await noShow(c, gameId, h);
  assert.deepEqual(await noShows(), [booking.id]);
  // Changed to paid: the venue's penalty goes, the peer one does not come back.
  await mark('paid');
  assert.deepEqual(await noShows(), []);
  assert.deepEqual(await gameEvents(h, booking.id), ['booking_paid 2']);
});

// --- abuse reports -------------------------------------------------------------

test('abuse report', async () => {
  const [r, t, other, gone] = await players('Reporter', 'Reported', 'Other', 'Gone');
  const gameId = await finishedGame([r, t]);

  const id = await report(r, t, null, 'language', '  Swore at everyone.  ');
  const row = await one(`select * from abuse_reports where id = $1`, [id]);
  assert.equal(row.reporter_id, r);
  assert.equal(row.target_id, t);
  assert.equal(row.game_id, null);
  assert.equal(row.reason, 'language');
  assert.equal(row.details, 'Swore at everyone.');
  assert.equal(row.status, 'open');
  assert.equal(new Date(row.created_at).toISOString(), new Date(now).toISOString());
  await expectError(report(r, t, null, 'other'), 'already_exists');

  // The same pair about a game is another report, once.
  const withGame = await report(r, t, gameId, 'false_score', '   ');
  assert.equal((await one(`select details from abuse_reports where id = $1`, [withGame])).details, null);
  await expectError(report(r, t, gameId, 'aggression'), 'already_exists');

  await report(r, other, null, 'other', 'x'.repeat(500));
  await expectError(report(t, other, null, 'other', 'x'.repeat(501)), 'invalid_argument');
  await expectError(report(r, r, null, 'other'), 'invalid_argument');
  await expectError(report(t, r, null, 'spam'), 'invalid_argument');
  await expectError(report(t, r, null, null), 'invalid_argument');
  // With a game, both must have played in it.
  await expectError(report(r, other, gameId, 'other'), 'not_found');
  await expectError(report(other, r, gameId, 'other'), 'not_found');
  await pool.query(`update profiles set deleted_at = $2 where id = $1`, [gone, now]);
  await expectError(report(r, gone, null, 'other'), 'not_found');
  await expectError(report(gone, r, null, 'other'), 'not_authenticated');

  assert.equal((await one(`select count(*)::int as n from notifications where user_id = $1`, [t])).n, 0);
});

// --- admin review --------------------------------------------------------------

test('admin review lists and closes', async () => {
  const admin = await addAdmin(pool, await player('Review admin'));
  const enter = (user, gameId, a, b) =>
    one(`select r.* from app.enter_score($1, $2, $3::uuid[], $4::uuid[], '[[6, 4]]', $5) r`, [user, gameId, a, b, now]);

  // A player's dispute.
  const [h, o] = await players('Disp host', 'Disp opp');
  const disputedGame = await finishedGame([h, o]);
  const disputed = await enter(h, disputedGame, [h], [o]);
  await pool.query(`select app.dispute_score($1, $2, 'Wrong', $3)`, [o, disputed.id, now]);
  // A confirmed result flagged by a no-show majority.
  const [fh, fa, fb, ft] = await players('Flag host', 'Flag A', 'Flag B', 'Flag T');
  const flaggedGame = await finishedGame([fh, fa, fb, ft]);
  const flagged = await enter(fh, flaggedGame, [fh, fa], [fb, ft]);
  await pool.query(`select app.confirm_score($1, $2, $3)`, [fb, flagged.id, now]);
  await noShow(fh, flaggedGame, ft);
  await noShow(fa, flaggedGame, ft);
  // A false-score report about the flagged game, and one without a game.
  const reportId = await report(fb, fh, flaggedGame, 'false_score', 'They made it up', plus(1));
  const plainId = await report(o, h, null, 'other', null, plus(2));
  // Not listed: a pending result and a closed report.
  const [ph, po] = await players('Pend host', 'Pend opp');
  await enter(ph, await finishedGame([ph, po]), [ph], [po]);

  const r = await review(admin);
  assert.deepEqual(r.counts, { disputes: 2, reports: 2 });
  const byResult = Object.fromEntries(r.disputes.map((d) => [d.result.id, d]));
  assert.deepEqual(Object.keys(byResult).sort(), sorted([disputed.id, flagged.id]));
  const d = byResult[disputed.id];
  assert.deepEqual(Object.keys(d).sort(), ['disputed_by_name', 'game', 'players', 'result']);
  assert.equal(d.result.status, 'disputed');
  assert.equal(d.result.dispute_reason, 'Wrong');
  assert.equal(d.game.game_id, disputedGame);
  assert.deepEqual(d.players, [
    { id: h, name: 'Disp host', side: 'a' },
    { id: o, name: 'Disp opp', side: 'b' },
  ]);
  assert.equal(d.disputed_by_name, 'Disp opp');
  const f = byResult[flagged.id];
  assert.equal(f.result.status, 'confirmed');
  assert.equal(f.result.flagged_no_show, true);
  assert.equal(f.disputed_by_name, null);
  assert.equal(f.players.length, 4);

  assert.deepEqual(r.reports.map((x) => x.id), [reportId, plainId]);
  const rep = r.reports[0];
  assert.deepEqual(Object.keys(rep).sort(), [
    'created_at', 'details', 'game', 'game_id', 'id', 'reason', 'reporter_id', 'reporter_name', 'result', 'target_id', 'target_name',
  ]);
  assert.equal(rep.reporter_id, fb);
  assert.equal(rep.reporter_name, 'Flag B');
  assert.equal(rep.target_id, fh);
  assert.equal(rep.target_name, 'Flag host');
  assert.equal(rep.game_id, flaggedGame);
  assert.equal(rep.game.game_id, flaggedGame);
  assert.equal(rep.result.id, flagged.id);
  assert.equal(rep.reason, 'false_score');
  assert.equal(rep.details, 'They made it up');
  assert.equal(new Date(rep.created_at).toISOString(), plus(1));
  assert.equal(r.reports[1].game, null);
  assert.equal(r.reports[1].result, null);

  await expectError(review(h), 'not_allowed');
  await expectError(closeReport(h, reportId, null), 'not_allowed');

  await closeReport(admin, reportId, '  Spoke to both.  ', plus(3));
  const closed = await one(`select * from abuse_reports where id = $1`, [reportId]);
  assert.equal(closed.status, 'closed');
  assert.equal(closed.admin_note, 'Spoke to both.');
  assert.equal(closed.closed_by, admin);
  assert.equal(new Date(closed.closed_at).toISOString(), plus(3));
  const audit = await one(`select actor_id, action, entity, entity_id, before, after from audit_log where entity_id = $1`, [reportId]);
  assert.equal(audit.actor_id, admin);
  assert.equal(audit.action, 'report_closed');
  assert.equal(audit.entity, 'abuse_report');
  assert.equal(audit.before.status, 'open');
  assert.equal(audit.after.status, 'closed');
  await expectError(closeReport(admin, reportId, null), 'not_found');
  // Once closed, the same pair and game can be reported again.
  await report(fb, fh, flaggedGame, 'other', null, plus(4));

  await pool.query(`select app.admin_resolve_score($1, $2, 'void', null, $3)`, [admin, flagged.id, now]);
  await pool.query(`select app.admin_resolve_score($1, $2, 'confirm', null, $3)`, [admin, disputed.id, now]);
  await closeReport(admin, plainId, null);
  const after = await review(admin);
  assert.deepEqual(after.counts, { disputes: 0, reports: 1 });
  assert.deepEqual(after.disputes, []);
  // A dispute that came from a no-show majority is listed like any other.
  const [nh, na, nb, nt] = await players('NS host', 'NS A', 'NS B', 'NS T');
  const nsGame = await finishedGame([nh, na, nb, nt]);
  const ns = await enter(nh, nsGame, [nh, na], [nb, nt]);
  await noShow(na, nsGame, nt);
  await noShow(nb, nsGame, nt);
  const listed = (await review(admin)).disputes;
  assert.deepEqual(listed.map((x) => x.result.id), [ns.id]);
  assert.equal(listed[0].result.dispute_reason, 'no_show');
  assert.equal(listed[0].disputed_by_name, null);
});

const enterScore = (user, gameId, a, b) =>
  one(`select r.* from app.enter_score($1, $2, $3::uuid[], $4::uuid[], '[[6, 4]]', $5) r`, [user, gameId, a, b, now]);
const resolve = (user, resultId, action) =>
  pool.query(`select app.admin_resolve_score($1, $2, $3, null, $4)`, [user, resultId, action, now]);

/** A confirmed doubles result in a fresh game, then flagged by a no-show majority against its last player. */
async function flaggedResult(prefix) {
  const [h, a, b, t] = await players(`${prefix} host`, `${prefix} A`, `${prefix} B`, `${prefix} T`);
  const gameId = await finishedGame([h, a, b, t]);
  const r = await enterScore(h, gameId, [h, a], [b, t]);
  await pool.query(`select app.confirm_score($1, $2, $3)`, [b, r.id, now]);
  await noShow(h, gameId, t);
  await noShow(a, gameId, t);
  return { resultId: r.id, gameId, players: [h, a, b, t] };
}

test('admin keeps a flagged result', async () => {
  const admin = await addAdmin(pool, await player('Keep admin'));
  const { resultId, players: ids } = await flaggedResult('Keep');
  const ratings = () =>
    pool
      .query(`select user_id, rating::text, rated_games from player_ratings where user_id = any ($1) order by user_id`, [ids])
      .then((r) => r.rows);
  const before = await ratings();
  assert.equal((await review(admin)).counts.disputes, 1);
  await pool.query('delete from notifications');

  await resolve(admin, resultId, 'keep');
  const kept = await resultRow(resultId);
  assert.equal(kept.status, 'confirmed');
  assert.equal(kept.flagged_no_show, false);
  assert.equal(kept.resolved_by, admin);
  assert.equal(new Date(kept.resolved_at).toISOString(), new Date(now).toISOString());
  assert.deepEqual(await ratings(), before);
  assert.equal((await one(`select count(*)::int as n from rating_events where result_id = $1`, [resultId])).n, 4);
  assert.deepEqual(
    (await pool.query(`select actor_id, action from audit_log where entity_id = $1`, [resultId])).rows,
    [{ actor_id: admin, action: 'score_keep' }],
  );
  assert.equal((await one(`select count(*)::int as n from notifications`)).n, 0);
  const after = await review(admin);
  assert.deepEqual(after.disputes, []);
  assert.equal(after.counts.disputes, 0);
  // Kept once: a second keep finds nothing to keep.
  await expectError(resolve(admin, resultId, 'keep'), 'not_found');

  // Void still works on a flagged result, and takes it off the list too.
  const other = await flaggedResult('Void');
  await resolve(admin, other.resultId, 'void');
  assert.equal((await resultRow(other.resultId)).status, 'void');
  assert.equal((await review(admin)).counts.disputes, 0);
});

test('keep needs a flagged confirmed result', async () => {
  const admin = await addAdmin(pool, await player('Keep check admin'));
  const [h, o, h2, o2, h3, o3] = await players('KP host', 'KP opp', 'KD host', 'KD opp', 'KC host', 'KC opp');
  const pending = await enterScore(h, await finishedGame([h, o]), [h], [o]);
  const disputed = await enterScore(h2, await finishedGame([h2, o2]), [h2], [o2]);
  await pool.query(`select app.dispute_score($1, $2, null, $3)`, [o2, disputed.id, now]);
  const confirmed = await enterScore(h3, await finishedGame([h3, o3]), [h3], [o3]);
  await pool.query(`select app.confirm_score($1, $2, $3)`, [o3, confirmed.id, now]);
  for (const r of [pending, disputed, confirmed]) await expectError(resolve(admin, r.id, 'keep'), 'not_found');
  await expectError(resolve(h, confirmed.id, 'keep'), 'not_allowed');
  assert.equal((await resultRow(pending.id)).status, 'pending');
  assert.equal((await resultRow(disputed.id)).status, 'disputed');
  assert.equal((await one(`select count(*)::int as n from audit_log`)).n, 0);
});

// --- what the app calls ----------------------------------------------------------

test('game json shows only my own votes', async () => {
  const [h, a, b, outsider] = await players('Json host', 'Json A', 'Json B', 'Json outsider');
  // public.* runs on the real clock.
  const gameId = await finishedGame([h, a, b], { end: new Date(Date.now() - HOUR).toISOString() });
  const rpc = (user, sql, params) => asUser(pool, user, (c) => c.query(sql, params).then((r) => r.rows[0]?.g));

  let g = await rpc(a, `select public.vote_player($1, $2, true) as g`, [gameId, h]);
  assert.equal(g.id, gameId);
  g = await rpc(a, `select public.vote_player($1, $2, false) as g`, [gameId, b]);
  assert.deepEqual(g.after_game, { votes: { [h]: true, [b]: false }, no_shows: [] });
  g = await rpc(a, `select public.report_no_show($1, $2, true) as g`, [gameId, b]);
  assert.deepEqual(g.after_game, { votes: { [h]: true, [b]: false }, no_shows: [b] });
  g = await rpc(a, `select public.vote_player($1, $2, null) as g`, [gameId, h]);
  assert.deepEqual(g.after_game.votes, { [b]: false });

  await rpc(h, `select public.vote_player($1, $2, true) as g`, [gameId, a]);
  const gameAs = (user) => one(`select app.game_json(g, $2) as g from games g where g.id = $1`, [gameId, user]).then((r) => r.g);
  assert.deepEqual((await gameAs(h)).after_game, { votes: { [a]: true }, no_shows: [] });
  assert.deepEqual((await gameAs(b)).after_game, { votes: {}, no_shows: [] });
  assert.equal('after_game' in (await gameAs(outsider)), false);
  assert.equal('after_game' in (await gameAs(null)), false);
  const upcoming = await finishedGame([h, a], { end: new Date(Date.now() + HOUR).toISOString() });
  assert.equal(
    'after_game' in (await one(`select app.game_json(g, $2) as g from games g where g.id = $1`, [upcoming, h])).g,
    false,
  );

  // Reports and the admin calls.
  await asUser(pool, a, (c) => c.query(`select public.report_player($1)`, [b]));
  assert.equal((await one(`select reason from abuse_reports where reporter_id = $1`, [a])).reason, 'other');
  await asUser(pool, a, (c) => c.query(`select public.report_player($1, $2, 'aggression', 'Shouted')`, [b, gameId]));
  await expectError(asUser(pool, a, (c) => c.query(`select public.admin_review()`)), 'not_allowed');
  const admin = await addAdmin(pool, await player('Json admin'));
  const r = await asUser(pool, admin, (c) => c.query(`select public.admin_review() as r`).then((x) => x.rows[0].r));
  assert.equal(r.counts.reports, 2);
  await asUser(pool, admin, (c) => c.query(`select public.admin_close_report($1)`, [r.reports[0].id]));
  await asUser(pool, admin, (c) => c.query(`select public.admin_close_report($1, 'Done')`, [r.reports[1].id]));
  assert.equal((await one(`select count(*)::int as n from abuse_reports where status = 'open'`)).n, 0);

  await expectError(asAnon(pool, (c) => c.query(`select public.vote_player($1, $2, true)`, [gameId, h])), '42501');
  await expectError(asAnon(pool, (c) => c.query(`select public.report_no_show($1, $2, true)`, [gameId, h])), '42501');
  await expectError(asAnon(pool, (c) => c.query(`select public.report_player($1)`, [h])), '42501');
  await expectError(asAnon(pool, (c) => c.query(`select public.admin_review()`)), '42501');
  await expectError(asAnon(pool, (c) => c.query(`select public.admin_close_report($1)`, [r.reports[0].id])), '42501');
  await expectError(asUser(pool, a, (c) => c.query(`select app.sportsmanship($1)`, [a])), '42501');
  for (const table of ['game_votes', 'game_no_show_reports', 'abuse_reports']) {
    await expectError(asUser(pool, a, (c) => c.query(`select * from ${table}`)), '42501');
  }
});

// --- deleting an account ---------------------------------------------------------

test('deleting an account with votes and reports', async () => {
  const [h, d, a, t, x] = await players('Del host', 'Del D', 'Del A', 'Del T', 'Del X');
  const gameId = await finishedGame([h, d, a, t]);
  await completeGames();
  // d's report is needed for the majority against t (2 of 3 others).
  await noShow(d, gameId, t);
  await noShow(a, gameId, t);
  assert.deepEqual(await gameEvents(t, gameId), ['no_show -20']);
  await vote(d, gameId, t, false);
  await vote(a, gameId, t, true);
  const mine = await report(d, x, null, 'other', 'About X');
  const aboutMe = await report(x, d, null, 'aggression');

  await pool.query(`select app.delete_account($1, $2)`, [d, plus(2)]);

  assert.deepEqual(await gameEvents(t, gameId), ['game_completed 2']);
  assert.equal((await one(`select count(*)::int as n from game_no_show_reports where reporter_id = $1`, [d])).n, 0);
  assert.equal((await one(`select count(*)::int as n from game_no_show_reports where game_id = $1`, [gameId])).n, 1);
  assert.deepEqual(await votesBy(d, gameId), []);
  assert.deepEqual(await sportsmanship(t), { votes: 1, percent: null });
  const closed = await one(`select status, details, closed_at, closed_by from abuse_reports where id = $1`, [mine]);
  assert.equal(closed.status, 'closed');
  assert.equal(closed.details, null);
  assert.equal(new Date(closed.closed_at).toISOString(), plus(2));
  assert.equal(closed.closed_by, null);
  assert.equal((await one(`select status from abuse_reports where id = $1`, [aboutMe])).status, 'open');
  // A second call does nothing.
  await pool.query(`select app.delete_account($1, $2)`, [d, plus(3)]);
});
