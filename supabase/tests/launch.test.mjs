// Milestone 6: launch changes. Games and requests at a hidden venue stay out
// of the public lists.

import assert from 'node:assert/strict';
import { after, before, beforeEach, test } from 'node:test';
import { createUser, freshDb } from './helpers/db.mjs';
import { addVenue, tashkent } from './helpers/fixtures.mjs';

let db;
let pool;
let venueId;

const now = tashkent('2026-11-22', 20);

before(async () => {
  db = await freshDb('launch');
  pool = db.pool;
  venueId = await addVenue(pool, { cityId: 'almaty', name: 'Sample venue' });
});
after(() => db.end());

beforeEach(async () => {
  await pool.query('delete from game_requests');
  await pool.query('delete from games');
  await pool.query(`update venues set active = true`);
});

const one = async (sql, params) => (await pool.query(sql, params)).rows[0];

async function player(name) {
  const id = await createUser(pool, name);
  await pool.query(`update profiles set city_id = 'almaty' where id = $1`, [id]);
  return id;
}

async function openGame(host, venue) {
  const { id } = await one(
    `insert into games (sport_id, city_id, venue_id, host_id, kind, meeting_point, visibility, during, utc_offset_minutes, spots)
     values ('football', 'almaty', $1, $2, case when $1::uuid is null then 'map_point' else 'place' end, case when $1::uuid is null then 'Park gate' end, 'public',
             tstzrange($3::timestamptz + interval '1 day', $3::timestamptz + interval '1 day 1 hour'), 300, 10)
     returning id`,
    [venue, host, now],
  );
  await pool.query(`insert into game_participants (game_id, user_id) values ($1, $2)`, [id, host]);
  return id;
}

const games = (user) =>
  pool.query(`select app.list_games($1, 'almaty', $2) as g`, [user, now]).then((r) => r.rows.map((x) => x.g.id));
const requests = (user) =>
  pool.query(`select app.list_game_requests($1, 'almaty', $2) as r`, [user, now]).then((r) => r.rows.map((x) => x.r.id));

test('games at inactive venue are hidden', async () => {
  const host = await player('Host');
  const other = await player('Other');
  const id = await openGame(host, venueId);
  assert.ok((await games(other)).includes(id), 'listed while the venue is active');

  await pool.query(`update venues set active = false where id = $1`, [venueId]);
  assert.ok(!(await games(other)).includes(id), 'hidden from another player');
  assert.ok((await games(host)).includes(id), 'the host still sees their own game');

  const joiner = await player('Joiner');
  await pool.query(`insert into game_participants (game_id, user_id) values ($1, $2)`, [id, joiner]);
  assert.ok((await games(joiner)).includes(id), 'a participant still sees it');
});

test('requests at inactive venue are hidden', async () => {
  const host = await player('Poster');
  const other = await player('Other');
  const { r } = await one(
    `select app.game_request_json(app.create_game_request($1, $2::jsonb, $3), $1) as r`,
    [host, JSON.stringify({ sport_id: 'football', venue_id: venueId, starts_local: '2026-11-28T18:00:00', ends_local: '2026-11-28T21:00:00', players_needed: 6 }), now],
  );
  assert.ok((await requests(other)).includes(r.id));

  await pool.query(`update venues set active = false where id = $1`, [venueId]);
  assert.ok(!(await requests(other)).includes(r.id), 'hidden from another player');
  assert.ok((await requests(host)).includes(r.id), 'the poster still sees their own request');
});

test('place games stay listed', async () => {
  const host = await player('Host');
  const other = await player('Other');
  const id = await openGame(host, null);
  await pool.query(`update venues set active = false`);
  assert.ok((await games(other)).includes(id));
});
