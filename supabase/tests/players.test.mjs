// Milestone 4c: finding players and the player profile.

import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { after, before, test } from 'node:test';
import { asUser, createUser, freshDb } from './helpers/db.mjs';
import { addPhone, addVenue } from './helpers/fixtures.mjs';

let db;
let pool;
let phoneSeq = 1000000;

before(async () => {
  db = await freshDb('players');
  pool = db.pool;
  await addVenue(pool);
});
after(() => db.end());

async function player(name, { city = 'tashkent', levels = {}, hidden = false } = {}) {
  const id = await createUser(pool, name);
  await pool.query(`update profiles set city_id = $2, hidden_from_search = $3 where id = $1`, [id, city, hidden]);
  for (const [sportId, level] of Object.entries(levels)) {
    await pool.query(`insert into player_levels (user_id, sport_id, level) values ($1, $2, $3)`, [id, sportId, level]);
  }
  await addPhone(pool, id, `+99890${phoneSeq++}`);
  return id;
}

const list = (user, city, sport = null, min = 1, max = 5, query = null, limit = 50) =>
  pool
    .query(`select p from app.list_players($1, $2, $3, $4, $5, $6, $7) p`, [user, city, sport, min, max, query, limit])
    .then((r) => r.rows.map((x) => x.p));

test('list_players: city, hidden, caller, name query and the sport/level filter', async () => {
  const me = await player('Me');
  const anna = await player('Anna Karimova', { levels: { football: 3, padel: 2 } });
  const ali = await player('Ali Valiev', { levels: { football: 5 } });
  const bobur = await player('Bobur'); // no level rows: counts as 1
  await player('Hidden Hana', { hidden: true, levels: { football: 3 } });
  await player('Far Away', { city: 'almaty' });

  const all = await list(me, 'tashkent');
  assert.deepEqual(all.map((p) => p.id).sort(), [anna, ali, bobur].sort());
  assert.ok(!all.some((p) => p.id === me));
  assert.ok(!all.some((p) => p.name === 'Hidden Hana' || p.name === 'Far Away'));

  const a = all.find((p) => p.id === anna);
  assert.deepEqual(Object.keys(a).sort(), ['city_id', 'games_played', 'id', 'levels', 'name', 'ratings', 'reliability']);
  assert.deepEqual(a.levels, { football: 3, padel: 2 });
  assert.equal(a.city_id, 'tashkent');
  assert.equal(a.games_played, 0);
  assert.equal(a.reliability.badge, 'new');
  assert.deepEqual(all.map((p) => p.name), ['Ali Valiev', 'Anna Karimova', 'Bobur']);

  assert.deepEqual((await list(me, 'tashkent', 'football', 3, 5)).map((p) => p.id).sort(), [anna, ali].sort());
  assert.deepEqual((await list(me, 'tashkent', 'football', 4, 5)).map((p) => p.id), [ali]);
  assert.deepEqual((await list(me, 'tashkent', 'football', 1, 1)).map((p) => p.id), [bobur]);
  assert.equal((await list(me, 'tashkent', null, 4, 5)).length, 3);
  assert.deepEqual((await list(me, 'tashkent', null, 1, 5, 'ANNA')).map((p) => p.id), [anna]);
  assert.equal((await list(me, 'tashkent', null, 1, 5, 'a%')).length, 0);
  assert.equal((await list(me, 'tashkent', null, 1, 5, null, 2)).length, 2);

  assert.ok(!JSON.stringify(all).includes('phone'));
  assert.ok(!JSON.stringify(all).includes('+998'));
});

test('player_profile works for hidden players, counts completed games and never has a phone', async () => {
  const hidden = await player('Hidden Hana', { hidden: true, levels: { football: 4 } });
  const mate = await player('Mate');
  const insert = (hours, completed) =>
    pool
      .query(
        `insert into games (sport_id, city_id, host_id, kind, meeting_point, during, utc_offset_minutes, spots, completed_at)
         values ('gym', 'tashkent', $1, 'map_point', 'x',
                 tstzrange(now() + make_interval(hours => $2), now() + make_interval(hours => $2 + 1)), 300, 4,
                 case when $3 then now() end)
         returning id`,
        [mate, hours, completed],
      )
      .then((r) => r.rows[0].id);
  const done = await insert(-3, true);
  const upcoming = await insert(2, false);
  await pool.query(`insert into game_participants (game_id, user_id) values ($1, $2), ($1, $3), ($4, $3)`, [done, mate, hidden, upcoming]);

  const viewer = await player('Viewer');
  const p = (await pool.query(`select app.player_profile($1, $2) as p`, [viewer, hidden])).rows[0].p;
  assert.equal(p.name, 'Hidden Hana');
  assert.deepEqual(p.levels, { football: 4 });
  assert.equal(p.games_played, 1);
  assert.ok(!JSON.stringify(p).includes('phone'));
  assert.equal((await pool.query(`select app.player_profile($1, $2) as p`, [viewer, randomUUID()])).rows[0].p, null);
});

test('through the API: signed-in players list and view players', async () => {
  const me = await player('Api me');
  const other = await player('Api other', { levels: { padel: 2 } });
  const rows = await asUser(pool, me, (c) =>
    c.query(`select public.list_players('tashkent', 'padel', 2, 3, 'api oth') as p`).then((r) => r.rows.map((x) => x.p)),
  );
  assert.deepEqual(rows.map((p) => p.id), [other]);
  const defaults = await asUser(pool, me, (c) => c.query(`select public.list_players('tashkent') as p`).then((r) => r.rows));
  assert.ok(defaults.length >= 1);
  const profile = await asUser(pool, me, (c) => c.query(`select public.player_profile($1) as p`, [other]).then((r) => r.rows[0].p));
  assert.equal(profile.id, other);
});
