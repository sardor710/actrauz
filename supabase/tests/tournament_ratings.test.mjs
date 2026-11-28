// Milestone 8a, Task 4: tournament matches move ratings (design §8, §9). A
// played match in a rated sport writes an M7 result that is applied at once;
// a correction reverses it exactly once. The `app` functions are called with
// the acting user and a fixed clock.

import assert from 'node:assert/strict';
import { after, before, beforeEach, test } from 'node:test';
import { createUser, expectError, freshDb } from './helpers/db.mjs';
import { addAdmin, addCategory, addEntries, addRatedSports, addTournament, addVenue, tashkent } from './helpers/fixtures.mjs';

let db;
let pool;
let admin;
let organizer;
let venueId;

const now = tashkent('2026-11-22', 20);
const later = tashkent('2026-11-30', 12);
const HOUR = 3600 * 1000;
const plus = (hours, from = now) => new Date(Date.parse(from) + hours * HOUR).toISOString();

before(async () => {
  db = await freshDb('tournament_ratings');
  pool = db.pool;
  await addRatedSports(pool);
  admin = await addAdmin(pool, await createUser(pool, 'Admin'));
  organizer = await createUser(pool, 'Organiser');
  venueId = await addVenue(pool, { name: 'Rating venue' });
});
after(() => db.end());

beforeEach(async () => {
  await pool.query('delete from notifications');
  await pool.query('delete from tournament_registrations');
  await pool.query('delete from tournaments');
});

const one = async (sql, params) => (await pool.query(sql, params)).rows[0];
const scalar = async (sql, params) => (await one(sql, params))?.r;

/** A player in Tashkent with a padel rating (provisional unless games given). */
async function rated(name, rating = '2.50', ratedGames = 0, sportId = 'padel') {
  const id = await createUser(pool, name);
  await pool.query(`update profiles set city_id = 'tashkent' where id = $1`, [id]);
  await pool.query(
    `insert into player_ratings (user_id, sport_id, rating, rated_games, source) values ($1, $2, $3, $4, 'questionnaire')`,
    [id, sportId, rating, ratedGames],
  );
  await pool.query(`select app.sync_level($1, $2)`, [id, sportId]);
  return id;
}

const score = (user, match, outcome, winner = null, sets = null, when = now) =>
  pool.query(`select app.enter_match_score($1, $2, $3, $4, $5::jsonb, $6)`, [
    user,
    match,
    outcome,
    winner,
    sets === null ? null : JSON.stringify(sets),
    when,
  ]);

async function tournament(sport = 'padel') {
  const t = await addTournament(pool, { startsOn: '2026-11-30', endsOn: '2026-12-01', sportId: sport });
  await pool.query(`insert into tournament_organizers (tournament_id, user_id) values ($1, $2)`, [t, organizer]);
  return t;
}

/** A published knockout category with those entrants. */
async function published(t, users, { kind = 'singles', partners } = {}) {
  const cat = await addCategory(pool, t, { kind });
  const regs = await addEntries(pool, cat, users, { partners });
  await pool.query(`select app.make_draw($1, $2, 'knockout', null, null, $3)`, [admin, cat, now]);
  await pool.query(`select app.publish_draw($1, $2, $3)`, [admin, cat, now]);
  return { cat, regs };
}

const knockout = async (cat, round) =>
  (await pool.query(`select * from tournament_matches where category_id = $1 and stage = 'knockout' and round = $2 order by position`, [cat, round]))
    .rows;
const playersOf = async (reg) => (await one(`select app.entry_players($1) as p`, [reg])).p;
const ratingRow = (user, sportId = 'padel') =>
  one(`select rating::text, rated_games from player_ratings where user_id = $1 and sport_id = $2`, [user, sportId]);
const ratingOf = async (user, sportId = 'padel') => (await ratingRow(user, sportId))?.rating ?? null;
const resultsOf = async (match) =>
  (await pool.query(`select * from match_results where tournament_match_id = $1 order by entered_at, id`, [match])).rows;
const liveResult = async (match) => (await resultsOf(match)).filter((r) => r.status !== 'void');
const eventsOf = async (user) =>
  (await pool.query(`select * from rating_events where user_id = $1 order by created_at, id`, [user])).rows;
const resultsInCategory = async (cat) =>
  (
    await pool.query(
      `select r.* from match_results r join tournament_matches m on m.id = r.tournament_match_id where m.category_id = $1`,
      [cat],
    )
  ).rows;

/** A singles final between two new 2.50 players: [match, a's user, b's user]. */
async function singlesFinal(names = ['A', 'B']) {
  const t = await tournament();
  const users = [await rated(names[0]), await rated(names[1])];
  const { cat } = await published(t, users);
  const [final] = await knockout(cat, 1);
  const [a] = await playersOf(final.side_a);
  const [b] = await playersOf(final.side_b);
  return { t, cat, final, a, b };
}

// --- ratings move -------------------------------------------------------------------

test('played match moves ratings', async () => {
  const { t, cat, final, a, b } = await singlesFinal();
  await score(organizer, final.id, 'played', null, [[6, 2], [6, 3]]);

  assert.deepEqual(await ratingRow(a), { rating: '2.64', rated_games: 1 });
  assert.deepEqual(await ratingRow(b), { rating: '2.36', rated_games: 1 });
  for (const u of [a, b]) assert.equal((await eventsOf(u)).length, 1);

  const [r] = await resultsOf(final.id);
  assert.equal(r.status, 'confirmed');
  assert.equal(r.game_id, null);
  assert.equal(r.entered_by, organizer);
  assert.equal(r.winner, 'a');
  assert.deepEqual(r.sets, [[6, 2], [6, 3]]);
  assert.equal(await scalar(`select app.result_sport(r) as r from match_results r where r.id = $1`, [r.id]), 'padel');
  const j = await scalar(`select app.result_json(r) as r from match_results r where r.id = $1`, [r.id]);
  assert.equal(j.tournament_match_id, final.id);
  assert.deepEqual(j.side_a, [a]);
  assert.deepEqual(j.side_b, [b]);
  assert.deepEqual(j.changes[a], { old: 2.5, new: 2.64 });

  const note = await one(`select * from notifications where user_id = $1 and kind = 'rating_updated'`, [a]);
  assert.equal(note.category, 'ratings');
  assert.equal(note.payload.tournament_id, t);
  assert.equal(note.payload.category_id, cat);
  assert.equal(note.payload.match_id, final.id);
  assert.equal(note.payload.result_id, r.id);
  assert.equal(note.payload.title_uz, 'Kubok');
  assert.equal(note.payload.title_ru, 'Кубок');
  assert.equal(note.payload.title_en, 'Cup');
  assert.ok('title_kk' in note.payload);
  assert.equal(note.payload.old, 2.5);
  assert.equal(note.payload.new, 2.64);
  assert.equal((await one(`select count(*)::int as n from notifications where user_id = $1 and kind = 'rating_updated'`, [b])).n, 1);
});

test('pairs', async () => {
  const t = await tournament();
  const [p1, p2, q1, q2] = [await rated('P1'), await rated('P2'), await rated('Q1'), await rated('Q2')];
  const { cat } = await published(t, [p1, q1], { kind: 'pairs', partners: [p2, q2] });
  const [final] = await knockout(cat, 1);
  await score(organizer, final.id, 'played', null, [[6, 2], [6, 3]]);

  const winners = await playersOf(final.side_a);
  const losers = await playersOf(final.side_b);
  assert.equal(winners.length, 2);
  assert.equal(losers.length, 2);
  for (const u of winners) assert.deepEqual(await ratingRow(u), { rating: '2.64', rated_games: 1 });
  for (const u of losers) assert.deepEqual(await ratingRow(u), { rating: '2.36', rated_games: 1 });
  const [r] = await liveResult(final.id);
  assert.equal((await one(`select count(*)::int as n from rating_events where result_id = $1`, [r.id])).n, 4);
  const sides = (await pool.query(`select user_id, side from match_result_players where result_id = $1`, [r.id])).rows;
  assert.deepEqual(sides.filter((s) => s.side === 'a').map((s) => s.user_id).sort(), [...winners].sort());
  assert.deepEqual(sides.filter((s) => s.side === 'b').map((s) => s.user_id).sort(), [...losers].sort());
});

test('walkover, retired, bye do not move ratings', async () => {
  const t = await tournament();
  const users = [await rated('W1'), await rated('W2'), await rated('W3')];
  const { cat } = await published(t, users);
  const round1 = await knockout(cat, 1);
  // Three entries: one first-round match is a bye.
  assert.ok(round1.some((m) => m.outcome === 'bye'));
  const real = round1.find((m) => m.outcome !== 'bye');
  await score(organizer, real.id, 'retired', 'a', [[6, 4], [2, 1]]);
  const [final] = await knockout(cat, 2);
  assert.equal(final.status, 'ready');
  await score(organizer, final.id, 'walkover', 'b');

  assert.equal((await resultsInCategory(cat)).length, 0);
  for (const u of users) {
    assert.deepEqual(await ratingRow(u), { rating: '2.50', rated_games: 0 });
    assert.equal((await eventsOf(u)).length, 0);
  }
});

test('correction reverses once', async () => {
  const { final, a, b } = await singlesFinal(['C1', 'C2']);
  await score(organizer, final.id, 'played', null, [[6, 2], [6, 3]]);
  assert.equal(await ratingOf(a), '2.64');

  // The other winner: each rating is the start plus the new change only.
  await score(organizer, final.id, 'played', null, [[2, 6], [3, 6]], plus(1));
  assert.deepEqual(await ratingRow(a), { rating: '2.36', rated_games: 1 });
  assert.deepEqual(await ratingRow(b), { rating: '2.64', rated_games: 1 });
  const live = await liveResult(final.id);
  assert.equal(live.length, 1);
  assert.equal(live[0].winner, 'b');
  assert.equal((await resultsOf(final.id)).length, 2);
  for (const u of [a, b]) {
    const ev = await eventsOf(u);
    assert.equal(ev.length, 1);
    assert.equal(ev[0].result_id, live[0].id);
  }

  // A walkover: back to the start.
  await score(organizer, final.id, 'walkover', 'a', null, plus(2));
  for (const u of [a, b]) {
    assert.deepEqual(await ratingRow(u), { rating: '2.50', rated_games: 0 });
    assert.equal((await eventsOf(u)).length, 0);
  }
  assert.equal((await liveResult(final.id)).length, 0);
  assert.ok((await resultsOf(final.id)).every((r) => r.status === 'void'));

  // Played again after the walkover: one new result.
  await score(organizer, final.id, 'played', null, [[6, 2], [6, 3]], plus(3));
  assert.equal(await ratingOf(a), '2.64');
  assert.equal((await liveResult(final.id)).length, 1);
});

test('the same result entered again changes nothing', async () => {
  const { final, a, b } = await singlesFinal(['I1', 'I2']);
  await score(organizer, final.id, 'played', null, [[6, 2], [6, 3]]);
  const before = await one(`select * from tournament_matches where id = $1`, [final.id]);
  const [result] = await resultsOf(final.id);
  const notes = async () => Number((await one(`select count(*) as n from notifications`)).n);
  const audits = async () => Number((await one(`select count(*) as n from audit_log where action = 'enter_match_score'`)).n);
  const noteCount = await notes();
  const auditCount = await audits();

  await score(organizer, final.id, 'played', null, [[6, 2], [6, 3]], plus(1));
  assert.equal(await notes(), noteCount, 'no notices');
  assert.equal(await audits(), auditCount);
  const afterRow = await one(`select * from tournament_matches where id = $1`, [final.id]);
  assert.equal(afterRow.scored_at.toISOString(), before.scored_at.toISOString());
  const results = await resultsOf(final.id);
  assert.equal(results.length, 1);
  assert.equal(results[0].id, result.id);
  assert.equal(results[0].status, 'confirmed');
  assert.deepEqual(await ratingRow(a), { rating: '2.64', rated_games: 1 });
  assert.deepEqual(await ratingRow(b), { rating: '2.36', rated_games: 1 });
  for (const u of [a, b]) assert.equal((await eventsOf(u)).length, 1);

  // The same winner with another score is a real correction.
  await score(organizer, final.id, 'played', null, [[6, 2], [6, 4]], plus(2));
  assert.equal((await resultsOf(final.id)).length, 2);
});

test('football moves nothing', async () => {
  const t = await tournament('football');
  const users = [await createUser(pool, 'F1'), await createUser(pool, 'F2')];
  const { cat } = await published(t, users);
  const [final] = await knockout(cat, 1);
  await score(organizer, final.id, 'played', null, [[2, 1]]);
  assert.equal((await resultsInCategory(cat)).length, 0);
  for (const u of users) {
    assert.equal(await ratingOf(u, 'football'), null);
    assert.equal((await eventsOf(u)).length, 0);
  }
});

// --- M7 readers --------------------------------------------------------------------

test('M7 paths ignore tournament results', async () => {
  const { final, a, b } = await singlesFinal(['M1', 'M2']);
  await score(organizer, final.id, 'played', null, [[6, 2], [6, 3]]);
  const [r] = await liveResult(final.id);

  // Never pending: auto-confirm finds nothing to do.
  assert.equal((await one(`select app.auto_confirm_scores($1) as n`, [plus(24 * 30)])).n, 0);
  // Never disputed: not in the admin's review.
  const review = await scalar(`select app.admin_review($1) as r`, [admin]);
  assert.ok(!review.disputes.some((d) => d.result.id === r.id));
  // Past games list games only.
  assert.equal((await pool.query(`select * from app.my_past_games($1, $2)`, [a, later])).rowCount, 0);
  // Players cannot confirm or dispute it.
  await expectError(pool.query(`select app.confirm_score($1, $2, $3)`, [b, r.id, now]), 'not_found');
  await expectError(pool.query(`select app.dispute_score($1, $2, 'no', $3)`, [b, r.id, now]), 'not_found');
  await expectError(pool.query(`select app.dispute_score($1, $2, 'no', $3)`, [a, r.id, now]), 'not_found');
  assert.equal((await one(`select status from match_results where id = $1`, [r.id])).status, 'confirmed');
  assert.equal(await ratingOf(a), '2.64');
  assert.equal(await ratingOf(b), '2.36');

  // The leaderboard shows the new rating.
  const board = await scalar(`select app.leaderboard($1, 'padel', 'tashkent', 100) as r`, [a]);
  assert.equal(board.rows.find((x) => x.id === a).rating, 2.64);
  assert.equal(board.me.rating, 2.64);
  assert.equal(board.me.rated_games, 1);

  // An admin void still finds the tournament's sport and takes the change off.
  await pool.query(`select app.admin_resolve_score($1, $2, 'void', null, $3)`, [admin, r.id, now]);
  assert.deepEqual(await ratingRow(a), { rating: '2.50', rated_games: 0 });
  assert.deepEqual(await ratingRow(b), { rating: '2.50', rated_games: 0 });
  assert.equal((await one(`select status from match_results where id = $1`, [r.id])).status, 'void');
  const resolved = await one(`select * from notifications where user_id = $1 and kind = 'score_resolved'`, [b]);
  assert.equal(resolved.payload.match_id, final.id);
  assert.equal(resolved.payload.action, 'void');
});

test("deleted account keeps others' rating changes", async () => {
  const t = await tournament();
  const users = [await rated('D1'), await rated('D2'), await rated('D3'), await rated('D4')];
  const { cat } = await published(t, users);
  const [semi] = await knockout(cat, 1);
  await score(organizer, semi.id, 'played', null, [[6, 2], [6, 3]]);
  const [winner] = await playersOf(semi.side_a);
  const [loser] = await playersOf(semi.side_b);
  const [r] = await liveResult(semi.id);
  assert.equal(r.status, 'confirmed');

  // The winner deletes their account before the final.
  await pool.query(`select app.delete_account($1, $2)`, [winner, now]);
  assert.deepEqual(await ratingRow(loser), { rating: '2.36', rated_games: 1 });
  assert.equal((await eventsOf(loser)).length, 1);
  assert.equal((await one(`select status from match_results where id = $1`, [r.id])).status, 'confirmed');
  assert.equal(await ratingRow(winner), undefined);
  // Their final became a walkover: nothing more moves.
  const [final] = await knockout(cat, 2);
  assert.equal(final.side_a, null);
  assert.equal((await resultsInCategory(cat)).length, 1);
});

test('game results unchanged', async () => {
  const players = [await rated('G1', '3.50'), await rated('G2', '3.50'), await rated('G3', '3.50'), await rated('G4', '3.50')];
  const [h, p, o1, o2] = players;
  const end = plus(-1);
  const g = await one(
    `insert into games (sport_id, city_id, venue_id, host_id, during, utc_offset_minutes, spots)
     values ('padel', 'tashkent', $1, $2, tstzrange($3, $4), 300, 4) returning id`,
    [venueId, h, plus(-2.5), end],
  );
  for (const [i, id] of players.entries()) {
    await pool.query(`insert into game_participants (game_id, user_id, joined_at) values ($1, $2, $3)`, [g.id, id, plus(-48 + i / 60)]);
  }
  const r = await one(`select r.* from app.enter_score($1, $2, $3::uuid[], $4::uuid[], $5::jsonb, $6) r`, [
    h,
    g.id,
    [h, p],
    [o1, o2],
    JSON.stringify([[6, 4], [6, 4]]),
    now,
  ]);
  assert.equal(r.status, 'pending');
  assert.equal(r.tournament_match_id, null);
  await pool.query(`select app.confirm_score($1, $2, $3)`, [o1, r.id, now]);
  for (const u of [h, p]) assert.deepEqual(await ratingRow(u), { rating: '3.63', rated_games: 1 });
  for (const u of [o1, o2]) assert.deepEqual(await ratingRow(u), { rating: '3.37', rated_games: 1 });
  const note = await one(`select payload from notifications where user_id = $1 and kind = 'rating_updated'`, [h]);
  assert.equal(note.payload.game_id, g.id);
  assert.equal(note.payload.result_id, r.id);
  const gj = await scalar(`select app.game_json(g, $2) as r from games g where g.id = $1`, [g.id, h]);
  assert.equal(gj.result.status, 'confirmed');
  assert.equal(gj.result.tournament_match_id, null);
  assert.equal(await scalar(`select app.result_sport(r) as r from match_results r where r.id = $1`, [r.id]), 'padel');
});
