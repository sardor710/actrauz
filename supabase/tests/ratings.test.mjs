// Milestone 7, Task 1: ratings for padel and tennis, the questionnaire,
// "My sports", the derived 1-5 level and rating ranges on games and Game
// Requests. The `app` functions are called with a fixed clock.

import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { after, before, test } from 'node:test';
import { asUser, createUser, errorOf, expectError, freshDb } from './helpers/db.mjs';
import { addAdmin, addCities, addCourt, addRatedSports, addVenue, tashkent } from './helpers/fixtures.mjs';

let db;
let pool;
let venueId;

// Sunday evening in Tashkent: every Monday slot is in the future.
const now = tashkent('2026-11-22', 20);
const ten = '2026-11-23T10:00:00';
const saturday = '2026-11-28';
const window = { starts_local: `${saturday}T18:00:00`, ends_local: `${saturday}T21:00:00` };

before(async () => {
  db = await freshDb('ratings');
  pool = db.pool;
  await addCities(pool);
  await addRatedSports(pool);
  venueId = await addVenue(pool, { name: 'Test venue' });
});
after(() => db.end());

const one = async (sql, params) => (await pool.query(sql, params)).rows[0];

async function player(name, levels = {}) {
  const id = await createUser(pool, name);
  await pool.query(`update profiles set city_id = 'tashkent' where id = $1`, [id]);
  for (const [sportId, level] of Object.entries(levels)) {
    await pool.query(`insert into player_levels (user_id, sport_id, level) values ($1, $2, $3)`, [id, sportId, level]);
  }
  return id;
}

/** A player with a padel rating (and its derived level), as the server keeps them. */
async function rated(name, rating, ratedGames = 0) {
  const id = await player(name);
  await pool.query(
    `insert into player_ratings (user_id, sport_id, rating, rated_games, source) values ($1, 'padel', $2, $3, 'questionnaire')`,
    [id, rating, ratedGames],
  );
  await pool.query(`select app.sync_level($1, 'padel')`, [id]);
  return id;
}

const questionnaire = (answers) => one(`select app.questionnaire_rating($1::integer[])::text as r`, [answers]).then((r) => r.r);
const setSport = (user, sportId, level, answers) =>
  pool.query(`select app.set_my_sport($1, $2, $3, $4::integer[], $5)`, [user, sportId, level, answers, now]);
const mySports = (user) => one(`select app.my_sports($1) as s`, [user]).then((r) => r.s);
const ratingRow = (user, sportId = 'padel') =>
  one(`select rating::text, rated_games, source from player_ratings where user_id = $1 and sport_id = $2`, [user, sportId]);
const levelOf = (user, sportId = 'padel') =>
  one(`select level from player_levels where user_id = $1 and sport_id = $2`, [user, sportId]).then((r) => r?.level ?? null);

/** A confirmed app booking on a new padel court (so slots never clash). */
async function booking(user, start = ten) {
  const courtId = await addCourt(pool, venueId, { basePrice: 400000 });
  const held = await one(`select (app.hold_slots($1, $2, $3::timestamp[], $4)).id`, [user, courtId, [start], now]);
  await pool.query(`select app.confirm_booking($1, $2, null, null, $3)`, [user, held.id, now]);
  return held.id;
}

const create = (user, game) =>
  one(`select app.game_json(app.create_game($1, $2::jsonb, $3), $1) as g`, [user, JSON.stringify(game), now]).then((r) => r.g);
const join = (user, gameId) => one(`select app.game_json(app.join_game($1, $2, $3), $1) as g`, [user, gameId, now]).then((r) => r.g);

async function padelGame(range) {
  const host = await player('Host');
  const g = await create(host, { sport_id: 'padel', booking_id: await booking(host), spots: 4, ...range });
  return { host, id: g.id, game: g };
}

async function footballGame() {
  const host = await player('Football host');
  const courtId = await addCourt(pool, venueId, { basePrice: 400000, sportId: 'football' });
  const held = await one(`select (app.hold_slots($1, $2, $3::timestamp[], $4)).id`, [host, courtId, [ten], now]);
  await pool.query(`select app.confirm_booking($1, $2, null, null, $3)`, [host, held.id, now]);
  return create(host, { sport_id: 'football', booking_id: held.id, spots: 10, min_level: 2, max_level: 4 });
}

const createRequest = (user, request) =>
  one(`select app.game_request_json(app.create_game_request($1, $2::jsonb, $3), $1) as r`, [user, JSON.stringify(request), now]).then(
    (r) => r.r,
  );

// --- questionnaire and My sports -------------------------------------------

test('questionnaire scoring', async () => {
  assert.equal(await questionnaire([0, 0, 0, 0, 0]), '1.00');
  assert.equal(await questionnaire([3, 3, 3, 3, 3]), '5.00');
  assert.equal(await questionnaire([1, 2, 1, 0, 2]), '2.70');
  await expectError(questionnaire([1, 2, 1, 0]), 'invalid_argument');
  await expectError(questionnaire([1, 2, 4, 0, 2]), 'invalid_argument');
  await expectError(questionnaire([1, 2, null, 0, 2]), 'invalid_argument');
  await expectError(questionnaire(null), 'invalid_argument');
});

test('answering sets rating and level', async () => {
  const u = await player('Answerer');
  await setSport(u, 'padel', null, [1, 2, 1, 0, 2]);
  assert.deepEqual(await ratingRow(u), { rating: '2.70', rated_games: 0, source: 'questionnaire' });
  assert.equal(await levelOf(u), 2);
  assert.deepEqual(await mySports(u), [
    { sport_id: 'padel', level: 2, rating: 2.7, provisional: true, rated_games: 0, can_retake: true },
  ]);

  // Retaking before the first rated game replaces the rating.
  await setSport(u, 'padel', null, [3, 3, 3, 3, 3]);
  assert.equal((await ratingRow(u)).rating, '5.00');
  assert.equal(await levelOf(u), 5);
});

test('simple sport takes a level', async () => {
  const u = await player('Simple');
  await setSport(u, 'football', 4, null);
  assert.equal(await levelOf(u, 'football'), 4);
  assert.deepEqual(await mySports(u), [
    { sport_id: 'football', level: 4, rating: null, provisional: null, rated_games: null, can_retake: false },
  ]);
  await expectError(setSport(u, 'football', null, [1, 1, 1, 1, 1]), 'invalid_argument');
  await expectError(setSport(u, 'football', 6, null), 'invalid_argument');
  await expectError(setSport(u, 'padel', 3, null), 'invalid_argument');
  await expectError(setSport(u, 'nonsense', 3, null), 'invalid_argument');
  assert.equal(await levelOf(u), null);

  // Removing a sport removes its level only; a rating stays.
  await setSport(u, 'padel', null, [1, 1, 1, 1, 1]);
  await pool.query(`select app.remove_my_sport($1, 'padel')`, [u]);
  await pool.query(`select app.remove_my_sport($1, 'football')`, [u]);
  assert.equal(await levelOf(u), null);
  assert.equal(await levelOf(u, 'football'), null);
  assert.equal((await ratingRow(u)).rating, '2.50');
  assert.deepEqual(await mySports(u), []);
});

test('rating is locked after a rated game', async () => {
  const u = await player('Locked');
  await setSport(u, 'padel', null, [1, 2, 1, 0, 2]);
  await pool.query(`update player_ratings set rated_games = 1 where user_id = $1`, [u]);
  await pool.query(`select app.remove_my_sport($1, 'padel')`, [u]);

  // Adding it again needs no answers, and answers do not change the rating.
  await setSport(u, 'padel', null, [3, 3, 3, 3, 3]);
  assert.equal((await ratingRow(u)).rating, '2.70');
  assert.equal(await levelOf(u), 2);
  assert.equal((await mySports(u))[0].can_retake, false);
  assert.equal((await mySports(u))[0].rated_games, 1);
});

test('the public wrappers return my sports', async () => {
  const u = await player('Wrapped');
  const rpc = (sql, params) => asUser(pool, u, (c) => c.query(sql, params).then((r) => r.rows[0].r));
  assert.deepEqual(await rpc(`select public.my_sports() as r`), []);
  const after = await rpc(`select public.set_my_sport('padel', p_answers => '{0,0,0,0,0}') as r`);
  assert.equal(after[0].rating, 1);
  const both = await rpc(`select public.set_my_sport('football', 3) as r`);
  assert.deepEqual(both.map((s) => s.sport_id).sort(), ['football', 'padel']);
  assert.deepEqual(await rpc(`select public.remove_my_sport('football') as r`).then((s) => s.map((x) => x.sport_id)), ['padel']);
});

test('clients cannot write a rated level', async () => {
  const u = await player('Client');
  await setSport(u, 'padel', null, [1, 2, 1, 0, 2]);
  await setSport(u, 'football', 2, null);
  const changed = (sql) => asUser(pool, u, (c) => c.query(sql, [u]).then((r) => r.rowCount));

  await expectError(changed(`insert into player_levels (user_id, sport_id, level) values ($1, 'tennis', 5)`), '42501');
  assert.equal(await changed(`update player_levels set level = 5 where user_id = $1 and sport_id = 'padel'`), 0);
  assert.equal(await changed(`delete from player_levels where user_id = $1 and sport_id = 'padel'`), 0);
  // Moving a football row onto padel is refused as well.
  await expectError(changed(`update player_levels set sport_id = 'padel' where user_id = $1 and sport_id = 'football'`), '42501');
  assert.equal(await levelOf(u), 2);

  assert.equal(await changed(`update player_levels set level = 5 where user_id = $1 and sport_id = 'football'`), 1);
  assert.equal(await changed(`delete from player_levels where user_id = $1 and sport_id = 'football'`), 1);
  assert.equal(await changed(`insert into player_levels (user_id, sport_id, level) values ($1, 'football', 3)`), 1);
  assert.equal(await levelOf(u, 'football'), 3);
});

test('tournament level follows the rating, ticked or not', async () => {
  const levelFor = (user, sportId) => one(`select app.player_level($1, $2) as l`, [user, sportId]).then((r) => r.l);
  const u = await rated('Unticked', '4.60');
  await pool.query(`select app.remove_my_sport($1, 'padel')`, [u]);
  assert.equal(await levelOf(u), null);
  assert.equal(await levelFor(u, 'padel'), 4);
  // Top of the scale is level 5; no rating counts as the minimum.
  assert.equal(await levelFor(await rated('Top', '6.40'), 'padel'), 5);
  assert.equal(await levelFor(await player('Unrated'), 'padel'), 1);
  // A simple sport keeps its stored level.
  assert.equal(await levelFor(await player('Footballer', { football: 3 }), 'football'), 3);
  assert.equal(await levelFor(await player('No football'), 'football'), 1);
});

test('clients cannot touch ratings', async () => {
  const u = await player('Rating client');
  await expectError(asUser(pool, u, (c) => c.query(`select * from player_ratings`)), '42501');
  await expectError(
    asUser(pool, u, (c) => c.query(`insert into player_ratings (user_id, sport_id, rating, source) values ($1, 'padel', 7, 'level')`, [u])),
    '42501',
  );
});

// --- backfill ----------------------------------------------------------------

test('backfill', async () => {
  // The template database is migrated empty, so run the migration's
  // backfill block on rows seeded here, in a database of its own.
  const source = await readFile(path.join(process.env.ACTRA_ROOT, 'migrations', '20261127100000_ratings.sql'), 'utf8');
  const block = source.match(/-- backfill:start\r?\n([\s\S]*?)-- backfill:end/)?.[1];
  assert.ok(block && block.includes('player_ratings'), 'the backfill block is marked in the migration');

  const fresh = await freshDb('ratings_backfill');
  try {
    const p = fresh.pool;
    const q = async (sql, params) => (await p.query(sql, params)).rows[0];
    await addRatedSports(p);
    const venue = await addVenue(p, { name: 'Backfill venue' });
    const host = await createUser(p, 'Host');
    const keeper = await createUser(p, 'Keeper');
    await p.query(`insert into player_levels (user_id, sport_id, level) values ($1, 'padel', 3), ($1, 'football', 4), ($2, 'padel', 5)`, [
      host,
      keeper,
    ]);
    // A rating that already exists is left alone.
    await p.query(`insert into player_ratings (user_id, sport_id, rating, source) values ($1, 'padel', 4.20, 'questionnaire')`, [keeper]);
    const game = async (sportId, min, max) =>
      (
        await q(
          `insert into games (sport_id, city_id, venue_id, host_id, kind, during, utc_offset_minutes, spots, min_level, max_level)
           values ($1, 'tashkent', $2, $3, 'place', tstzrange(now() + interval '1 day', now() + interval '25 hours'), 300, 4, $4, $5)
           returning id`,
          [sportId, venue, host, min, max],
        )
      ).id;
    const padel = await game('padel', 2, 4);
    const padelTop = await game('padel', 3, 5);
    const football = await game('football', 2, 4);
    const { id: request } = await q(
      `insert into game_requests (sport_id, city_id, host_id, during, utc_offset_minutes, players_needed, min_level, max_level)
       values ('padel', 'tashkent', $1, tstzrange(now() + interval '1 day', now() + interval '25 hours'), 300, 3, 1, 3)
       returning id`,
      [host],
    );

    await p.query(block);
    await p.query(block);

    const rating = (user, sport) => q(`select rating::text, source, rated_games from player_ratings where user_id = $1 and sport_id = $2`, [user, sport]);
    assert.deepEqual(await rating(host, 'padel'), { rating: '3.50', source: 'level', rated_games: 0 });
    assert.equal(await rating(host, 'football'), undefined);
    assert.deepEqual(await rating(keeper, 'padel'), { rating: '4.20', source: 'questionnaire', rated_games: 0 });
    assert.equal((await q(`select level from player_levels where user_id = $1 and sport_id = 'padel'`, [host])).level, 3);

    const range = (table, id) => q(`select min_rating::text, max_rating::text from ${table} where id = $1`, [id]);
    assert.deepEqual(await range('games', padel), { min_rating: '2.00', max_rating: '4.99' });
    assert.deepEqual(await range('games', padelTop), { min_rating: '3.00', max_rating: '7.00' });
    assert.deepEqual(await range('games', football), { min_rating: null, max_rating: null });
    assert.deepEqual(await range('game_requests', request), { min_rating: '1.00', max_rating: '3.99' });
  } finally {
    await fresh.end();
  }
});

test('the migration rates padel and tennis', async () => {
  // A live database whose padel row is not flagged yet: the migration's flag
  // statement makes it rated before the backfill runs (design §5.1).
  const source = await readFile(path.join(process.env.ACTRA_ROOT, 'migrations', '20261127100000_ratings.sql'), 'utf8');
  const flag = source.match(/-- rated-sports:start\r?\n([\s\S]*?)-- rated-sports:end/)?.[1];
  const block = source.match(/-- backfill:start\r?\n([\s\S]*?)-- backfill:end/)?.[1];
  assert.ok(flag && flag.includes('competitive_rating'), 'the flag statement is marked in the migration');
  assert.ok(source.indexOf('-- rated-sports:start') < source.indexOf('-- backfill:start'), 'the flag comes before the backfill');

  const fresh = await freshDb('ratings_flag');
  try {
    const p = fresh.pool;
    await addCities(p);
    assert.equal((await p.query(`select competitive_rating from sports where id = 'padel'`)).rows[0].competitive_rating, false);
    const u = await createUser(p, 'Level three');
    await p.query(`insert into player_levels (user_id, sport_id, level) values ($1, 'padel', 3)`, [u]);

    await p.query(flag);
    await p.query(flag);
    await p.query(block);

    assert.equal((await p.query(`select competitive_rating from sports where id = 'padel'`)).rows[0].competitive_rating, true);
    // Where tennis does not exist, nothing is created.
    assert.equal((await p.query(`select count(*)::int as n from sports where id = 'tennis'`)).rows[0].n, 0);
    const r = (await p.query(`select rating::text from player_ratings where user_id = $1 and sport_id = 'padel'`, [u])).rows[0];
    assert.equal(r?.rating, '3.50');
  } finally {
    await fresh.end();
  }
});

// --- rating ranges on games ---------------------------------------------------

test('old build creates a padel game', async () => {
  const { game } = await padelGame({ min_level: 2, max_level: 4 });
  assert.equal(game.min_rating, 2);
  assert.equal(game.max_rating, 4.99);
  assert.ok(Number.isInteger(game.min_level) && Number.isInteger(game.max_level));
  assert.deepEqual([game.min_level, game.max_level], [2, 4]);

  const { game: top } = await padelGame({ min_level: 3, max_level: 5 });
  assert.equal(top.max_rating, 7);

  const { game: plain } = await padelGame({});
  assert.deepEqual([plain.min_rating, plain.max_rating, plain.min_level, plain.max_level], [1, 7, 1, 5]);
});

test('rating range sets the level range', async () => {
  const { game } = await padelGame({ min_rating: 3.0, max_rating: 4.5, min_level: 1, max_level: 1 });
  assert.deepEqual([game.min_rating, game.max_rating], [3, 4.5]);
  assert.deepEqual([game.min_level, game.max_level], [3, 4]);

  const { game: top } = await padelGame({ min_rating: 5.5, max_rating: 7 });
  assert.deepEqual([top.min_level, top.max_level], [5, 5]);

  const bad = async (range) => {
    const host = await player('Bad host');
    return errorOf(create(host, { sport_id: 'padel', booking_id: await booking(host), spots: 4, ...range }));
  };
  assert.equal(await bad({ min_rating: 5, max_rating: 4 }), 'invalid_argument');
  assert.equal(await bad({ min_rating: 0.5, max_rating: 4 }), 'invalid_argument');
  assert.equal(await bad({ min_rating: 3, max_rating: 7.5 }), 'invalid_argument');
  assert.equal(await bad({ min_rating: '3', max_rating: 4 }), 'invalid_argument');
  // Both ends or neither.
  assert.equal(await bad({ min_rating: 3 }), 'invalid_argument');

  const football = await footballGame();
  assert.deepEqual([football.min_rating, football.max_rating], [null, null]);
  assert.deepEqual([football.min_level, football.max_level], [2, 4]);
  assert.equal(football.participants[0].rating, null);
  assert.equal(football.participants[0].provisional, null);
});

test('join checks the rating', async () => {
  const { id, host } = await padelGame({ min_rating: 3.0, max_rating: 4.5 });
  const high = await rated('High', 4.7);
  const edge = await rated('Edge', 4.5, 12);
  const unrated = await player('Unrated');

  await expectError(join(high, id), 'level_out_of_range');
  const joined = await join(edge, id);
  const e = joined.participants.find((p) => p.id === edge);
  assert.equal(e.rating, 4.5);
  assert.equal(e.provisional, false);
  assert.equal(e.level, 4);
  await expectError(join(unrated, id), 'level_out_of_range');

  const low = await padelGame({ min_rating: 1.0, max_rating: 2.5 });
  await join(unrated, low.id);

  await pool.query(`select app.invite_to_game($1, $2, $3, $4)`, [host, id, high, now]);
  const invited = await join(high, id);
  assert.equal(invited.participants.find((p) => p.id === high).rating, 4.7);
  assert.equal(invited.participants.find((p) => p.id === high).provisional, true);

  // The host sees ratings on join requests too.
  const asker = await rated('Asker', 2.2);
  await pool.query(`select app.request_to_join($1, $2, $3)`, [asker, id, now]);
  const hostView = await one(`select app.game_json(g, $2) as g from games g where g.id = $1`, [id, host]).then((r) => r.g);
  assert.equal(hostView.join_requests[0].rating, 2.2);
  assert.equal(hostView.join_requests[0].provisional, true);
});

test('request keeps its rating range through conversion', async () => {
  const poster = await player('Poster');
  const interested = await rated('Keen', 3.3);
  const r = await createRequest(poster, { sport_id: 'padel', starts_local: ten, ends_local: '2026-11-23T13:00:00', players_needed: 3, min_rating: 3.0, max_rating: 4.5 });
  assert.deepEqual([r.min_rating, r.max_rating, r.min_level, r.max_level], [3, 4.5, 3, 4]);

  await pool.query(`select app.request_interest($1, $2, $3)`, [interested, r.id, now]);
  const view = await one(`select app.game_request_json(r, $2) as r from game_requests r where r.id = $1`, [r.id, poster]).then((x) => x.r);
  assert.equal(view.interested[0].rating, 3.3);
  assert.equal(view.interested[0].provisional, true);

  const bookingId = await booking(poster);
  const g = await one(`select app.game_json(app.convert_game_request($1, $2, $3::jsonb, $4), $1) as g`, [
    poster,
    r.id,
    JSON.stringify({ booking_id: bookingId }),
    now,
  ]).then((x) => x.g);
  assert.deepEqual([g.min_rating, g.max_rating, g.min_level, g.max_level], [3, 4.5, 3, 4]);

  // An old build's request gets a range from its levels; a simple sport none.
  const old = await createRequest(poster, { sport_id: 'padel', ...window, players_needed: 1, min_level: 2, max_level: 5 });
  assert.deepEqual([old.min_rating, old.max_rating], [2, 7]);
  await expectError(createRequest(poster, { sport_id: 'padel', ...window, players_needed: 1, min_rating: 4, max_rating: 3 }), 'invalid_argument');
  const football = await createRequest(poster, { sport_id: 'football', ...window, players_needed: 9, min_rating: 3, max_rating: 4 });
  assert.deepEqual([football.min_rating, football.max_rating, football.min_level, football.max_level], [null, null, 1, 5]);
});

// --- players, admin, settings -----------------------------------------------

test('players filter by rating', async () => {
  const me = await player('Viewer');
  const mid = await rated('Mid Rated', 3.5);
  const top = await rated('Top Rated', 4.7);
  const list = (min, max, sport = 'padel') =>
    pool
      .query(`select p from app.list_players_rated($1, 'tashkent', $2, $3, $4, null, 100) p`, [me, sport, min, max])
      .then((r) => r.rows.map((x) => x.p));

  const found = await list(3.0, 4.0);
  assert.ok(found.some((p) => p.id === mid));
  assert.ok(!found.some((p) => p.id === top));
  assert.ok(!found.some((p) => p.id === me));
  assert.ok((await list(4.5, 7)).some((p) => p.id === top));
  await expectError(list(1, 5, 'football'), 'invalid_argument');

  const m = found.find((p) => p.id === mid);
  assert.deepEqual(m.ratings.padel, { rating: 3.5, provisional: true, rated_games: 0 });
  assert.deepEqual(m.levels, { padel: 3 });

  const viaApi = await asUser(pool, me, (c) =>
    c.query(`select p from public.list_players_rated('tashkent', 'padel', 3.0, 4.0) p`).then((r) => r.rows.map((x) => x.p.id)),
  );
  assert.ok(viaApi.includes(mid) && !viaApi.includes(top));
});

test('sport rating switch is locked', async () => {
  const admin = await addAdmin(pool, await player('Admin'));
  const save = (sport, create) => pool.query(`select app.admin_save_sport($1, $2::jsonb, $3, $4)`, [admin, JSON.stringify(sport), create, now]);
  await save({ id: 'padel', competitive_rating: false, sort_order: 3 }, false);
  const padel = await one(`select competitive_rating, sort_order from sports where id = 'padel'`);
  assert.deepEqual(padel, { competitive_rating: true, sort_order: 3 });

  await save({ id: 'squash', name_en: 'Squash', icon_key: 'squash', competitive_rating: true }, true);
  assert.equal((await one(`select competitive_rating from sports where id = 'squash'`)).competitive_rating, false);
  await save({ id: 'squash', competitive_rating: true }, false);
  assert.equal((await one(`select competitive_rating from sports where id = 'squash'`)).competitive_rating, false);
});

test('new categories can be muted', async () => {
  const u = await player('Muter');
  await asUser(pool, u, (c) => c.query(`select public.set_settings('{ratings,teams}', false)`));
  assert.deepEqual((await one(`select muted_categories from profiles where id = $1`, [u])).muted_categories, ['ratings', 'teams']);
  await expectError(asUser(pool, u, (c) => c.query(`select public.set_settings('{nonsense}', false)`)), 'invalid_argument');
  await pool.query(`insert into notifications (user_id, kind, category, payload) values ($1, 'rating_changed', 'ratings', '{}')`, [u]);
  await pool.query(`insert into notifications (user_id, kind, category, payload) values ($1, 'team_invite', 'teams', '{}')`, [u]);
});
