// The rule that must never break: a slot belongs to at most one active hold
// or booking, whatever arrives at the same moment (product spec §14 rule 1).

import assert from 'node:assert/strict';
import { after, before, test } from 'node:test';
import { createUser, errorOf, expectError, freshDb } from './helpers/db.mjs';
import { addAdmin, addCategory, addCourt, addEntries, addTournament, addVenue, at, monday, tashkent } from './helpers/fixtures.mjs';

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

/** A doubles tennis game that ended an hour before `now`, its score entered by the first player at `at`. */
async function enteredResult([a, b, c, d], at = now) {
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
    at,
  ]);
  return r.rows[0].id;
}

const later = (seconds) => new Date(Date.parse(now) + seconds * 1000).toISOString();

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

test('auto-confirm and a confirm on another result do not deadlock', async () => {
  // Low and high are two players with low < high in uuid order. The auto run
  // applies result 1 (with high) first, then fillers, then result 2 (with
  // low); result 3 (low and high, not yet due) is confirmed meanwhile on a
  // second connection, locking low then high. An auto run that locked per
  // result would hold high and wait for low while the confirm holds low and
  // waits for high. (That code never deadlocked here in practice: the
  // confirm's insert of missing ratings already waits for the auto run once
  // it has updated high, so the window is microseconds wide. This guards
  // the lock order against regressions.)
  for (let attempt = 0; attempt < 20; attempt++) {
    const pair = [await ratedPlayer(`Pair ${attempt}.1`), await ratedPlayer(`Pair ${attempt}.2`)].sort();
    const [low, high] = pair;
    const fresh = async (n) => {
      const out = [];
      for (let i = 0; i < n; i++) out.push(await ratedPlayer(`Fresh ${attempt}.${Math.random()}`));
      return out;
    };
    const [a1, b1, c1] = await fresh(3);
    const first = await enteredResult([a1, high, b1, c1], now);
    // The fillers widen the window between the two; they share four players.
    const fillerPlayers = await fresh(4);
    const fillers = [];
    for (let i = 0; i < 25; i++) fillers.push(await enteredResult(fillerPlayers, later(1 + i)));
    const [a2, b2, c2] = await fresh(3);
    const second = await enteredResult([a2, low, b2, c2], later(60));
    const [host3, opp3] = await fresh(2);
    // Entered an hour later: not due for the auto run below.
    const third = await enteredResult([host3, low, high, opp3], later(3600));

    const delay = (attempt * 3) % 40;
    const [auto, confirmed] = await Promise.all([
      errorOf(pool.query(`select app.auto_confirm_scores($1)`, [later(24 * 3600 + 120)])),
      new Promise((resolve) => setTimeout(resolve, delay)).then(() =>
        errorOf(pool.query(`select app.confirm_score($1, $2, $3)`, [high, third, later(3600)])),
      ),
    ]);
    assert.equal(auto, null, `attempt ${attempt}: auto ${auto}`);
    assert.equal(confirmed, null, `attempt ${attempt}: confirm ${confirmed}`);

    for (const resultId of [first, ...fillers, second, third]) {
      const { rows } = await pool.query(`select status from match_results where id = $1`, [resultId]);
      assert.equal(rows[0].status, 'confirmed', `attempt ${attempt}`);
      const per = await pool.query(
        `select count(*)::int as n, count(distinct user_id)::int as players from rating_events where result_id = $1`,
        [resultId],
      );
      assert.deepEqual(per.rows[0], { n: 4, players: 4 });
    }
  }
});

test('tournament scheduling: fill the day racing an app hold, two organisers racing for one player', async () => {
  const admin = await addAdmin(pool, await createUser(pool, 'Admin'));
  const organizers = [await createUser(pool, 'Organiser 1'), await createUser(pool, 'Organiser 2')];
  // A tournament on Monday at the venue, organised by both, with one
  // published knockout per list of players.
  const tournamentWith = async (entrants) => {
    const t = await addTournament(pool, { venueId, startsOn: monday });
    for (const o of organizers) {
      await pool.query(`insert into tournament_organizers (tournament_id, user_id) values ($1, $2)`, [t, o]);
    }
    const cats = [];
    for (const users of entrants) {
      const cat = await addCategory(pool, t);
      await addEntries(pool, cat, users);
      await pool.query(`select app.make_draw($1, $2, 'knockout', null, null, $3)`, [admin, cat, now]);
      await pool.query(`select app.publish_draw($1, $2, $3)`, [admin, cat, now]);
      cats.push(cat);
    }
    return { t, cats };
  };
  const firstMatch = async (cat) =>
    (await pool.query(`select * from tournament_matches where category_id = $1 order by round, position limit 1`, [cat])).rows[0];

  for (let attempt = 0; attempt < 10; attempt++) {
    // Fill the day and a player's hold on the same 10:00 slot of one court.
    const courtId = await addCourt(pool, venueId, { slot: 60 });
    const { t, cats } = await tournamentWith([[await createUser(pool, 'A'), await createUser(pool, 'B')]]);
    const booker = await createUser(pool, `Booker ${attempt}`);
    // Staggered both ways, so each side gets to win some rounds.
    const fillDelay = attempt % 2 === 0 ? 0 : attempt % 4;
    const holdDelay = attempt % 2 === 0 ? attempt % 3 : 0;
    const wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
    const [filled, held] = await Promise.all([
      wait(fillDelay).then(() =>
        pool
          .query(`select app.fill_day($1, $2, $3::date, $4::uuid[], '10:00'::time, null, $5) as r`, [organizers[0], t, monday, [courtId], now])
          .then((r) => r.rows[0].r),
      ),
      wait(holdDelay).then(() => errorOf(hold(booker, courtId, [at(monday, 10)]))),
    ]);
    assert.equal(filled.scheduled, 1, `attempt ${attempt}`);
    const { rows } = await pool.query(
      `select source, lower(during) as start from bookings
       where court_id = $1 and status in ('held', 'confirmed') order by lower(during)`,
      [courtId],
    );
    const at10 = rows.filter((r) => r.start.toISOString() === '2026-11-23T05:00:00.000Z');
    assert.equal(at10.length, 1, `attempt ${attempt}: ${JSON.stringify(rows)}`);
    const match = await firstMatch(cats[0]);
    if (held === null) {
      // The hold came first: fill the day skipped 10:00 and took 11:00.
      assert.equal(at10[0].source, 'app');
      assert.equal(match.starts_at.toISOString(), '2026-11-23T06:00:00.000Z');
    } else {
      assert.equal(held, 'slot_taken', `attempt ${attempt}`);
      assert.equal(at10[0].source, 'block');
      assert.equal(match.starts_at.toISOString(), '2026-11-23T05:00:00.000Z');
    }

    // Two organisers putting one player on two courts at 10:00 at once.
    const shared = await createUser(pool, `Shared ${attempt}`);
    const courts = [await addCourt(pool, venueId, { slot: 60 }), await addCourt(pool, venueId, { slot: 60 })];
    const race = await tournamentWith([
      [shared, await createUser(pool, 'C')],
      [shared, await createUser(pool, 'D')],
    ]);
    const matches = [await firstMatch(race.cats[0]), await firstMatch(race.cats[1])];
    const results = await Promise.all(
      [0, 1].map((i) =>
        errorOf(
          pool.query(`select app.schedule_match($1, $2, $3, $4::timestamp, null, $5)`, [
            organizers[i],
            matches[i].id,
            courts[i],
            at(monday, 10),
            now,
          ]),
        ),
      ),
    );
    assert.deepEqual([...results].sort(), [null, 'player_busy'].sort(), `attempt ${attempt}`);
    const scheduled = await pool.query(
      `select count(*)::int as n from tournament_matches where id = any ($1::uuid[]) and starts_at is not null`,
      [matches.map((m) => m.id)],
    );
    assert.equal(scheduled.rows[0].n, 1);
  }
});

test('tournament scores: two organisers entering one match at once leave one winner in the next match', async () => {
  const admin = await addAdmin(pool, await createUser(pool, 'Score admin'));
  const organizers = [await createUser(pool, 'Scorer 1'), await createUser(pool, 'Scorer 2')];
  for (let attempt = 0; attempt < 10; attempt++) {
    const t = await addTournament(pool, { startsOn: monday });
    for (const o of organizers) {
      await pool.query(`insert into tournament_organizers (tournament_id, user_id) values ($1, $2)`, [t, o]);
    }
    const cat = await addCategory(pool, t);
    const users = [];
    for (let i = 0; i < 4; i++) users.push(await createUser(pool, `E${attempt}-${i}`));
    await addEntries(pool, cat, users);
    await pool.query(`select app.make_draw($1, $2, 'knockout', null, null, $3)`, [admin, cat, now]);
    await pool.query(`select app.publish_draw($1, $2, $3)`, [admin, cat, now]);
    const semi = (
      await pool.query(`select * from tournament_matches where category_id = $1 and round = 1 order by position limit 1`, [cat])
    ).rows[0];

    // Each names a different winner (a walkover: no score rules in play).
    const results = await Promise.all(
      ['a', 'b'].map((side, i) =>
        errorOf(pool.query(`select app.enter_match_score($1, $2, 'walkover', $3, null, $4)`, [organizers[i], semi.id, side, now])),
      ),
    );
    for (const r of results) assert.ok(r === null || r === 'next_match_played', `attempt ${attempt}: ${r}`);
    assert.ok(results.includes(null), `attempt ${attempt}`);

    const done = (await pool.query(`select * from tournament_matches where id = $1`, [semi.id])).rows[0];
    const final = (await pool.query(`select * from tournament_matches where category_id = $1 and round = 2`, [cat])).rows[0];
    assert.equal(done.status, 'done');
    assert.equal(final.side_a, done.winner === 'a' ? semi.side_a : semi.side_b, `attempt ${attempt}`);
    assert.equal(final.side_b, null);
    assert.equal(final.status, 'waiting');
  }
});
