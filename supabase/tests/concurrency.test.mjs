// The rule that must never break: a slot belongs to at most one active hold
// or booking, whatever arrives at the same moment (product spec §14 rule 1).

import assert from 'node:assert/strict';
import { after, before, test } from 'node:test';
import { createUser, errorOf, expectError, freshDb } from './helpers/db.mjs';
import { addCourt, addVenue, at, monday, tashkent } from './helpers/fixtures.mjs';

let db;
let pool;
let ali;
let vali;
let venueId;

const now = tashkent('2026-11-22', 20);

before(async () => {
  db = await freshDb('concurrency');
  pool = db.pool;
  ali = await createUser(pool, 'Ali');
  vali = await createUser(pool, 'Vali');
  venueId = await addVenue(pool, { open: 0, close: 24 * 60 });
});
after(() => db.end());

// Each call takes its own connection from the pool, so two calls started
// together really do run in two sessions at once.
const hold = (user, courtId, starts) =>
  pool.query(`select (app.hold_slots($1, $2, $3::timestamp[], $4)).id`, [user, courtId, starts, now]);

const activeOn = async (courtId) =>
  (
    await pool.query(
      `select user_id, lower(during) as start from bookings
       where court_id = $1 and status in ('held', 'confirmed') order by lower(during)`,
      [courtId],
    )
  ).rows;

test('two players holding the same slot at the same moment: exactly one succeeds', async () => {
  // 20 rounds on 20 separate courts, all fired together.
  const courts = [];
  for (let i = 0; i < 20; i++) courts.push(await addCourt(pool, venueId, { slot: 60 }));
  const players = [];
  for (let i = 0; i < 40; i++) players.push(await createUser(pool, `P${i}`));

  const results = await Promise.all(
    courts.flatMap((courtId, i) => [
      errorOf(hold(players[2 * i], courtId, [at(monday, 10)])),
      errorOf(hold(players[2 * i + 1], courtId, [at(monday, 10)])),
    ]),
  );

  for (let i = 0; i < courts.length; i++) {
    const pair = [results[2 * i], results[2 * i + 1]].sort();
    assert.deepEqual(pair, [null, 'slot_taken'].sort(), `court ${i}: ${JSON.stringify(pair)}`);
    assert.equal((await activeOn(courts[i])).length, 1);
  }
});

test('ten players racing for one slot: one winner, nine refused', async () => {
  const courtId = await addCourt(pool, venueId, { slot: 60 });
  const players = [];
  for (let i = 0; i < 10; i++) players.push(await createUser(pool, `R${i}`));
  const results = await Promise.all(players.map((p) => errorOf(hold(p, courtId, [at(monday, 12)]))));
  assert.equal(results.filter((r) => r === null).length, 1);
  assert.equal(results.filter((r) => r === 'slot_taken').length, 9);
  assert.equal((await activeOn(courtId)).length, 1);
});

test('overlapping selections racing: one wins, the other is refused whole', async () => {
  const courtId = await addCourt(pool, venueId, { slot: 60 });
  const [a, b] = await Promise.all([
    errorOf(hold(ali, courtId, [at(monday, 9), at(monday, 10)])),
    errorOf(hold(vali, courtId, [at(monday, 10), at(monday, 11)])),
  ]);
  assert.deepEqual([a, b].sort(), [null, 'slot_taken'].sort());
  assert.equal((await activeOn(courtId)).length, 1);
});

test('the database itself refuses an overlapping row, whoever writes it', async () => {
  const courtId = await addCourt(pool, venueId, { slot: 60 });
  await pool.query(`select app.confirm_booking($1, (app.hold_slots($1, $2, $3::timestamp[], $4)).id, null, null, $4)`, [
    ali,
    courtId,
    [at(monday, 14)],
    now,
  ]);
  const insert = (status, range) =>
    pool.query(
      `insert into bookings (user_id, venue_id, court_id, during, utc_offset_minutes, slot_count, total_price, currency, status)
       values ($1, $2, $3, $4::tstzrange, 300, 1, 1, 'UZS', $5)`,
      [vali, venueId, courtId, range, status],
    );
  // 14:30-15:30 Tashkent overlaps the confirmed 14:00-15:00.
  await expectError(insert('confirmed', '[2026-11-23 09:30+00,2026-11-23 10:30+00)'), '23P01');
  await expectError(insert('held', '[2026-11-23 09:30+00,2026-11-23 10:30+00)'), '23P01');
  // Touching ranges do not overlap: 15:00-16:00 is fine.
  await insert('confirmed', '[2026-11-23 10:00+00,2026-11-23 11:00+00)');
  // Inactive rows never block.
  await insert('cancelled_by_player', '[2026-11-23 09:30+00,2026-11-23 10:30+00)');
  await insert('released', '[2026-11-23 09:30+00,2026-11-23 10:30+00)');
});

test('one player sending two holds at once ends with exactly one hold', async () => {
  const first = await addCourt(pool, venueId, { slot: 60 });
  const second = await addCourt(pool, venueId, { slot: 60 });
  const player = await createUser(pool, 'Double tap');
  const results = await Promise.all([
    errorOf(hold(player, first, [at(monday, 16)])),
    errorOf(hold(player, second, [at(monday, 16)])),
    errorOf(hold(player, first, [at(monday, 18)])),
  ]);
  assert.deepEqual(results, [null, null, null]);
  const { rows } = await pool.query(`select count(*)::int as n from bookings where user_id = $1 and status = 'held'`, [player]);
  assert.equal(rows[0].n, 1);
});

test('the three-booking limit holds under simultaneous requests', async () => {
  const courtId = await addCourt(pool, venueId, { slot: 60 });
  const player = await createUser(pool, 'Greedy');
  // Hold-and-confirm five different slots at once; the cap is three.
  const results = await Promise.all(
    [1, 2, 3, 4, 5].map((hour) =>
      errorOf(
        pool.query(`select app.confirm_booking($1, (app.hold_slots($1, $2, $3::timestamp[], $4)).id, null, null, $4)`, [
          player,
          courtId,
          [at(monday, hour)],
          now,
        ]),
      ),
    ),
  );
  assert.equal(results.filter((r) => r === null).length, 3, JSON.stringify(results));
  assert.equal(results.filter((r) => r === 'too_many_bookings').length, 2);
});

test('the last spot of a game: a join and an approval racing, exactly one gets in', async () => {
  // 10 rounds on 10 games, each with one spot left, all fired together.
  const rounds = [];
  for (let i = 0; i < 10; i++) {
    const host = await createUser(pool, `Host ${i}`);
    const { rows } = await pool.query(
      `insert into games (sport_id, city_id, venue_id, host_id, during, utc_offset_minutes, spots)
       values ('padel', 'tashkent', $1, $2, tstzrange('2026-11-23 19:00+05', '2026-11-23 20:30+05'), 300, 2) returning id`,
      [venueId, host],
    );
    const gameId = rows[0].id;
    await pool.query(`insert into game_participants (game_id, user_id) values ($1, $2)`, [gameId, host]);
    const x = await createUser(pool, `X ${i}`);
    const y = await createUser(pool, `Y ${i}`);
    const request = (await pool.query(`select (app.request_to_join($1, $2, $3)).id`, [y, gameId, now])).rows[0].id;
    rounds.push({ host, gameId, x, request });
  }

  const results = await Promise.all(
    rounds.flatMap(({ host, gameId, x, request }) => [
      errorOf(pool.query(`select app.join_game($1, $2, $3)`, [x, gameId, now])),
      errorOf(pool.query(`select app.decide_join_request($1, $2, true, $3)`, [host, request, now])),
    ]),
  );

  for (let i = 0; i < rounds.length; i++) {
    const pair = [results[2 * i], results[2 * i + 1]].sort();
    assert.deepEqual(pair, [null, 'full'].sort(), `game ${i}: ${JSON.stringify(pair)}`);
    const { rows } = await pool.query(`select count(*)::int as n from game_participants where game_id = $1`, [rounds[i].gameId]);
    assert.equal(rows[0].n, 2);
  }
});

// Integrity rule 2: a tournament category never counts more than its cap.

async function tournamentCategory(kind, cap) {
  const { rows } = await pool.query(
    `insert into tournaments (city_id, sport_id, venue_id, title_en, starts_on, ends_on)
     values ('tashkent', 'padel', $1, 'Race Cup', '2026-12-10', '2026-12-10') returning id`,
    [venueId],
  );
  const cat = await pool.query(
    `insert into tournament_categories (tournament_id, name_en, kind, cap, fee) values ($1, 'Open', $2, $3, 0) returning id`,
    [rows[0].id, kind, cap],
  );
  return { tournamentId: rows[0].id, categoryId: cat.rows[0].id };
}

const counted = async (categoryId) =>
  (
    await pool.query(
      `select count(*)::int as n from tournament_registrations where category_id = $1 and status in ('registered', 'offered')`,
      [categoryId],
    )
  ).rows[0].n;

test('the last spot of a singles category: two registrations racing, exactly one gets in', async () => {
  // 10 rounds on 10 categories, each with one spot left, all fired together.
  const rounds = [];
  for (let i = 0; i < 10; i++) {
    const { tournamentId, categoryId } = await tournamentCategory('singles', 2);
    const first = await createUser(pool, `First ${i}`);
    await pool.query(`select app.register($1, $2, null, $3)`, [first, categoryId, now]);
    rounds.push({ tournamentId, categoryId, x: await createUser(pool, `SX ${i}`), y: await createUser(pool, `SY ${i}`) });
  }

  const register = (user, categoryId) => errorOf(pool.query(`select app.register($1, $2, null, $3)`, [user, categoryId, now]));
  const results = await Promise.all(rounds.flatMap(({ categoryId, x, y }) => [register(x, categoryId), register(y, categoryId)]));

  for (let i = 0; i < rounds.length; i++) {
    const pair = [results[2 * i], results[2 * i + 1]].sort();
    assert.deepEqual(pair, [null, 'full'].sort(), `category ${i}: ${JSON.stringify(pair)}`);
    assert.equal(await counted(rounds[i].categoryId), 2);
    const { rows } = await pool.query(`select slots_filled from tournaments where id = $1`, [rounds[i].tournamentId]);
    assert.equal(rows[0].slots_filled, 2);
  }
});

test('the last spot of a pairs category: two partners accepting at once, exactly one pair gets in', async () => {
  const rounds = [];
  for (let i = 0; i < 10; i++) {
    const { categoryId } = await tournamentCategory('pairs', 2);
    const users = [];
    for (const n of ['A', 'AP', 'B', 'BP', 'C', 'CP']) users.push(await createUser(pool, `${n} ${i}`));
    const [a, ap, b, bp, c, cp] = users;
    const reg = async (user, partner) =>
      (await pool.query(`select (app.register($1, $2, $3, $4)).id`, [user, categoryId, partner, now])).rows[0].id;
    await pool.query(`select app.respond_partner($1, $2, true, $3)`, [ap, await reg(a, ap), now]);
    rounds.push({ categoryId, b: [bp, await reg(b, bp)], c: [cp, await reg(c, cp)] });
  }

  const accept = ([partner, id]) => errorOf(pool.query(`select app.respond_partner($1, $2, true, $3)`, [partner, id, now]));
  const results = await Promise.all(rounds.flatMap(({ b, c }) => [accept(b), accept(c)]));

  for (let i = 0; i < rounds.length; i++) {
    const pair = [results[2 * i], results[2 * i + 1]].sort();
    assert.deepEqual(pair, [null, 'full'].sort(), `category ${i}: ${JSON.stringify(pair)}`);
    assert.equal(await counted(rounds[i].categoryId), 2);
  }
});

// Ratings (M7): a result changes ratings exactly once, and two results that
// share a player never lose one of the two changes. Tennis is rated here;
// padel stays a simple sport for the tests above.

async function ratedPlayer(name, rating = '3.50') {
  await pool.query(
    `insert into sports (id, name_en, icon_key, default_players, competitive_rating)
     values ('tennis', 'Tennis', 'tennis', 2, true) on conflict (id) do update set competitive_rating = true`,
  );
  const id = await createUser(pool, name);
  await pool.query(
    `insert into player_ratings (user_id, sport_id, rating, rated_games, source) values ($1, 'tennis', $2, 0, 'questionnaire')`,
    [id, rating],
  );
  return id;
}

/** A doubles tennis game that ended an hour before `now`, its score entered by the first player. */
async function enteredResult([a, b, c, d]) {
  const { rows } = await pool.query(
    `insert into games (sport_id, city_id, venue_id, host_id, during, utc_offset_minutes, spots)
     values ('tennis', 'tashkent', $1, $2, tstzrange('2026-11-22 17:30+05', '2026-11-22 19:00+05'), 300, 4) returning id`,
    [venueId, a],
  );
  const gameId = rows[0].id;
  for (const u of [a, b, c, d]) await pool.query(`insert into game_participants (game_id, user_id) values ($1, $2)`, [gameId, u]);
  const r = await pool.query(`select (app.enter_score($1, $2, $3::uuid[], $4::uuid[], '[[6,4],[6,4]]'::jsonb, $5)).id`, [
    a,
    gameId,
    [a, b],
    [c, d],
    now,
  ]);
  return r.rows[0].id;
}

const plus24 = new Date(Date.parse(now) + 24 * 3600 * 1000).toISOString();
const eventCount = async (resultId) =>
  (await pool.query(`select count(*)::int as n from rating_events where result_id = $1`, [resultId])).rows[0].n;

test('concurrent confirm and auto-confirm', async () => {
  const rounds = [];
  for (let i = 0; i < 5; i++) {
    const players = [];
    for (const n of ['A', 'B', 'C', 'D']) players.push(await ratedPlayer(`Race ${n} ${i}`));
    rounds.push({ players, resultId: await enteredResult(players) });
  }

  // One auto-confirm run racing five opponents' confirmations: either may
  // apply a result, never both.
  const results = await Promise.all([
    errorOf(pool.query(`select app.auto_confirm_scores($1)`, [plus24])),
    ...rounds.map(({ players, resultId }) =>
      errorOf(pool.query(`select app.confirm_score($1, $2, $3)`, [players[2], resultId, now])),
    ),
  ]);
  assert.equal(results[0], null);
  for (const r of results.slice(1)) assert.ok(r === null || r === 'not_found', r);

  for (const { players, resultId } of rounds) {
    assert.equal(await eventCount(resultId), 4);
    const { rows } = await pool.query(`select status from match_results where id = $1`, [resultId]);
    assert.equal(rows[0].status, 'confirmed');
    const a = await pool.query(`select rating::text, rated_games from player_ratings where user_id = $1 and sport_id = 'tennis'`, [
      players[0],
    ]);
    assert.deepEqual(a.rows[0], { rating: '3.63', rated_games: 1 });
  }
});

test('two results sharing a player', async () => {
  for (let i = 0; i < 5; i++) {
    const a = await ratedPlayer(`Shared ${i}`, '3.00');
    const others = [];
    for (let j = 0; j < 6; j++) others.push(await ratedPlayer(`Other ${i}.${j}`, (3 + j * 0.25).toFixed(2)));
    const first = await enteredResult([a, others[0], others[1], others[2]]);
    const second = await enteredResult([a, others[3], others[4], others[5]]);

    const results = await Promise.all([
      errorOf(pool.query(`select app.confirm_score($1, $2, $3)`, [others[1], first, now])),
      errorOf(pool.query(`select app.confirm_score($1, $2, $3)`, [others[4], second, now])),
    ]);
    assert.deepEqual(results, [null, null]);

    const { rows } = await pool.query(
      `select (select rating from player_ratings where user_id = $1 and sport_id = 'tennis')::text as rating,
              (select rated_games from player_ratings where user_id = $1 and sport_id = 'tennis') as games,
              (3.00 + (select sum(delta) from rating_events where user_id = $1))::text as expected,
              (select count(*)::int from rating_events where user_id = $1) as events`,
      [a],
    );
    assert.equal(rows[0].events, 2);
    assert.equal(rows[0].games, 2);
    assert.equal(rows[0].rating, rows[0].expected);
  }
});
