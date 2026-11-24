// Port of app/test/domain/games_test.dart against the database, plus the
// cases only a shared database can get wrong.

import assert from 'node:assert/strict';
import { after, before, test } from 'node:test';
import { asAnon, asUser, createUser, errorOf, expectError, freshDb } from './helpers/db.mjs';
import { addVenue, tashkent } from './helpers/fixtures.mjs';

let db;
let pool;
let venueId;
let host;

const now = tashkent('2026-11-22', 20);

before(async () => {
  db = await freshDb('games');
  pool = db.pool;
  venueId = await addVenue(pool);
  host = await createUser(pool, 'Host');
});
after(() => db.end());

async function player(name, levels = {}) {
  const id = await createUser(pool, name);
  for (const [sportId, level] of Object.entries(levels)) {
    await pool.query(`insert into player_levels (user_id, sport_id, level) values ($1, $2, $3)`, [id, sportId, level]);
  }
  return id;
}

/** A padel game on Monday 19:00-20:30 Tashkent time with the host already in. */
async function game({ spots = 4, minLevel = 1, maxLevel = 5, others = [], cityId = 'tashkent' } = {}) {
  const { rows } = await pool.query(
    `insert into games (sport_id, city_id, venue_id, host_id, during, utc_offset_minutes, spots, min_level, max_level)
     values ('padel', $1, $2, $3, tstzrange('2026-11-23 19:00+05', '2026-11-23 20:30+05'), 300, $4, $5, $6) returning id`,
    [cityId, venueId, host, spots, minLevel, maxLevel],
  );
  const id = rows[0].id;
  await pool.query(`insert into game_participants (game_id, user_id, joined_at) values ($1, $2, '2026-11-20')`, [id, host]);
  for (const [i, other] of others.entries()) {
    await pool.query(`insert into game_participants (game_id, user_id, joined_at) values ($1, $2, $3)`, [
      id,
      other,
      `2026-11-21T00:00:0${i}Z`,
    ]);
  }
  return id;
}

const join = (user, gameId) =>
  pool.query(`select app.game_json(app.join_game($1, $2, $3), $1) as g`, [user, gameId, now]).then((r) => r.rows[0].g);
const leave = (user, gameId) =>
  pool.query(`select app.game_json(app.leave_game($1, $2, $3), $1) as g`, [user, gameId, now]).then((r) => r.rows[0].g);
const list = (user, cityId = 'tashkent') =>
  pool.query(`select app.list_games($1, $2, $3) as g`, [user, cityId, now]).then((r) => r.rows.map((x) => x.g));

test('joining adds the player and lowers the spots left', async () => {
  const id = await game();
  const dilnoza = await player('Dilnoza', { padel: 3 });
  const joined = await join(dilnoza, id);
  assert.deepEqual(joined.participant_ids, [host, dilnoza]);
  assert.equal(joined.spots - joined.participant_ids.length, 2);
  assert.equal(joined.starts_local, '2026-11-23T19:00:00');
  assert.equal(joined.ends_local, '2026-11-23T20:30:00');
});

test('a full game refuses new players and never exceeds its spots', async () => {
  const id = await game({ spots: 2, others: [await player('Second')] });
  assert.equal(await errorOf(join(await player('Third'), id)), 'full');
  const { rows } = await pool.query(`select count(*)::int as n from game_participants where game_id = $1`, [id]);
  assert.equal(rows[0].n, 2);
});

test('joining twice is refused', async () => {
  const id = await game();
  const p = await player('Twice');
  await join(p, id);
  assert.equal(await errorOf(join(p, id)), 'already_joined');
  assert.equal(await errorOf(join(host, id)), 'already_joined');
});

test('a player outside the level range is refused', async () => {
  const id = await game({ minLevel: 3, maxLevel: 5 });
  assert.equal(await errorOf(join(await player('Low', { padel: 2 }), id)), 'level_out_of_range');
  assert.equal((await join(await player('Fits', { padel: 3 }), id)).participant_ids.length, 2);
});

test('a player with no level for the sport counts as level 1', async () => {
  const beginnerGame = await game({ minLevel: 1, maxLevel: 2 });
  const advancedGame = await game({ minLevel: 2, maxLevel: 5 });
  // A level in another sport does not carry over.
  const p = await player('New', { football: 5 });
  assert.equal((await join(p, beginnerGame)).participant_ids.length, 2);
  assert.equal(await errorOf(join(p, advancedGame)), 'level_out_of_range');
});

test('leaving removes the player', async () => {
  const p = await player('Leaver');
  const id = await game({ others: [p] });
  assert.deepEqual((await leave(p, id)).participant_ids, [host]);
});

test('the host cannot leave', async () => {
  assert.equal(await errorOf(leave(host, await game())), 'host_cannot_leave');
});

test('a player who is not in the game cannot leave it', async () => {
  assert.equal(await errorOf(leave(await player('Outsider'), await game())), 'not_participant');
});

test('an unknown or cancelled game cannot be joined', async () => {
  const p = await player('Late');
  assert.equal(await errorOf(join(p, '00000000-0000-0000-0000-000000000000')), 'not_found');
  const id = await game();
  await pool.query(`update games set status = 'cancelled' where id = $1`, [id]);
  assert.equal(await errorOf(join(p, id)), 'not_found');
});

test('five players racing for the last spot: exactly one gets it', async () => {
  const id = await game({ spots: 2 });
  const racers = [];
  for (let i = 0; i < 5; i++) racers.push(await player(`Racer ${i}`));
  const results = await Promise.all(racers.map((p) => errorOf(join(p, id))));
  assert.equal(results.filter((r) => r === null).length, 1, JSON.stringify(results));
  assert.equal(results.filter((r) => r === 'full').length, 4);
  const { rows } = await pool.query(`select count(*)::int as n from game_participants where game_id = $1`, [id]);
  assert.equal(rows[0].n, 2);
});

test('discovery hides full games from outsiders and shows them to participants', async () => {
  await pool.query('delete from games');
  const inside = await player('Inside');
  const outside = await player('Outside');
  const open = await game();
  const full = await game({ spots: 2, others: [inside] });
  const elsewhere = await game({ cityId: 'almaty' });

  assert.deepEqual(
    (await list(outside)).map((g) => g.id),
    [open],
  );
  assert.deepEqual((await list(inside)).map((g) => g.id).sort(), [open, full].sort());
  assert.deepEqual(
    (await list(outside, 'almaty')).map((g) => g.id),
    [elsewhere],
  );
});

test('games that have started are not listed', async () => {
  const p = await player('Browser');
  const { rows } = await pool.query(`select app.list_games($1, 'tashkent', $2) as g`, [p, tashkent('2026-11-23', 19)]);
  assert.equal(rows.length, 0);
});

test('through the API: players join as themselves, visitors cannot, tables are read-only', async () => {
  const id = await game();
  // public.join_game uses the real clock, and a started game takes nobody new.
  await pool.query(`update games set during = tstzrange(now() + interval '1 day', now() + interval '1 day 90 minutes') where id = $1`, [id]);
  const p = await player('Api');
  const joined = await asUser(pool, p, async (c) => (await c.query('select public.join_game($1) as g', [id])).rows[0].g);
  assert.deepEqual(joined.participant_ids, [host, p]);
  const fetched = await asUser(pool, p, async (c) => (await c.query('select public.get_game($1) as g', [id])).rows[0].g);
  assert.equal(fetched.host_id, host);

  await expectError(
    asAnon(pool, (c) => c.query('select public.join_game($1)', [id])),
    '42501',
  );
  await expectError(
    asUser(pool, p, (c) => c.query(`insert into game_participants (game_id, user_id) values ($1, $2)`, [id, host])),
    '42501',
  );
  await expectError(
    asUser(pool, p, (c) => c.query(`update games set spots = 100 where id = $1`, [id])),
    '42501',
  );
  const left = await asUser(pool, p, async (c) => (await c.query('select public.leave_game($1) as g', [id])).rows[0].g);
  assert.deepEqual(left.participant_ids, [host]);
});
