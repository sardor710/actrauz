// Milestone 4c: Game Requests ("looking for players"). The `app` functions
// are called with a fixed clock.

import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { after, before, beforeEach, test } from 'node:test';
import { asAnon, asUser, createUser, errorOf, expectError, freshDb } from './helpers/db.mjs';
import { addCourt, addVenue, tashkent } from './helpers/fixtures.mjs';

let db;
let pool;
let venueId;

// Sunday evening in Tashkent; the request is for the coming Saturday.
const now = tashkent('2026-11-22', 20);
const saturday = '2026-11-28';
const window = { starts_local: `${saturday}T18:00:00`, ends_local: `${saturday}T21:00:00` };

before(async () => {
  db = await freshDb('game_requests');
  pool = db.pool;
  venueId = await addVenue(pool, { name: 'Test venue' });
});
after(() => db.end());

beforeEach(async () => {
  await pool.query('delete from notifications');
  await pool.query('delete from game_requests');
  await pool.query('delete from games');
});

// Distinct clocks, so the order people tapped is unambiguous.
const tap = (n) => tashkent('2026-11-22', 20, n);

const one = async (sql, params) => (await pool.query(sql, params)).rows[0];

async function player(name, levels = {}) {
  const id = await createUser(pool, name);
  await pool.query(`update profiles set city_id = 'tashkent' where id = $1`, [id]);
  for (const [sportId, level] of Object.entries(levels)) {
    await pool.query(`insert into player_levels (user_id, sport_id, level) values ($1, $2, $3)`, [id, sportId, level]);
  }
  return id;
}

const create = (user, request, when = now) =>
  one(`select app.game_request_json(app.create_game_request($1, $2::jsonb, $3), $1) as r`, [user, JSON.stringify(request), when]).then((r) => r.r);
const view = (id, user) => one(`select app.game_request_json(r, $2) as r from game_requests r where r.id = $1`, [id, user]).then((r) => r.r);
const interest = (user, id, when = now) =>
  one(`select app.game_request_json(app.request_interest($1, $2, $3), $1) as r`, [user, id, when]).then((r) => r.r);
const convert = (user, id, place, when = now) =>
  one(`select app.game_json(app.convert_game_request($1, $2, $3::jsonb, $4), $1) as g`, [user, id, JSON.stringify(place), when]).then((r) => r.g);
const notesOf = (user, kind) =>
  pool
    .query(`select * from notifications where user_id = $1 ${kind ? 'and kind = $2' : ''} order by created_at, id`, kind ? [user, kind] : [user])
    .then((r) => r.rows);

async function footballRequest(overrides = {}) {
  const poster = await player('Poster', { football: 3 });
  const r = await create(poster, { sport_id: 'football', ...window, area: 'Chilonzor', players_needed: 9, ...overrides });
  return { poster, id: r.id, request: r };
}

test('a request lists its window, area and interested players; each I am in notifies the poster', async () => {
  const { poster, id, request } = await footballRequest({ note: 'Friendly', min_level: 2, max_level: 4 });
  assert.equal(request.sport_id, 'football');
  assert.equal(request.city_id, 'tashkent');
  assert.equal(request.starts_local, `${saturday}T18:00:00`);
  assert.equal(request.ends_local, `${saturday}T21:00:00`);
  assert.equal(request.area, 'Chilonzor');
  assert.equal(request.players_needed, 9);
  assert.equal(request.status, 'open');
  assert.equal(request.my_status, 'host');
  assert.equal(request.interested_count, 0);

  const [a, b, c] = [await player('A', { football: 2 }), await player('B'), await player('C')];
  await interest(a, id, tap(1));
  await interest(b, id, tap(2));
  const after3 = await interest(c, id, tap(3));
  assert.equal(after3.interested_count, 3);
  assert.equal(after3.my_status, 'interested');
  assert.deepEqual(after3.interested.map((x) => x.id), [a, b, c]);
  assert.equal(after3.interested[0].name, 'A');
  assert.equal(after3.interested[0].level, 2);
  assert.equal(after3.interested[0].reliability.badge, 'new');
  assert.equal((await view(id, poster)).interested_count, 3);
  assert.equal((await view(id, randomUUID())).my_status, null);

  const notes = await notesOf(poster, 'request_interest');
  assert.equal(notes.length, 3);
  assert.equal(notes[0].category, 'requests');
  assert.equal(notes[0].payload.request_id, id);
  assert.equal(notes[0].payload.actor_name, 'A');
  assert.equal(notes[0].payload.sport_id, 'football');
  assert.equal(notes[0].payload.starts_local, `${saturday}T18:00:00`);
});

test('interest rules: poster, twice, ended, cancelled and unknown requests', async () => {
  const { poster, id } = await footballRequest();
  const p = await player('P');
  assert.equal(await errorOf(interest(poster, id)), 'invalid_argument');
  await interest(p, id);
  assert.equal(await errorOf(interest(p, id)), 'already_joined');
  const q = await player('Q');
  assert.equal(await errorOf(interest(q, id, tashkent(saturday, 21, 1))), 'not_found');
  assert.equal(await errorOf(interest(q, randomUUID())), 'not_found');

  await pool.query(`select app.cancel_game_request($1, $2)`, [poster, id]);
  assert.equal(await errorOf(interest(q, id)), 'not_found');
});

test('withdrawing interest removes the player; the poster can remove one', async () => {
  const { poster, id } = await footballRequest();
  const [a, b] = [await player('A'), await player('B')];
  await interest(a, id);
  await interest(b, id);
  await pool.query(`select app.withdraw_interest($1, $2)`, [a, id]);
  assert.equal((await view(id, poster)).interested_count, 1);
  assert.equal(await errorOf(pool.query(`select app.withdraw_interest($1, $2)`, [a, id])), 'not_found');

  // Only the poster removes someone.
  assert.equal(await errorOf(pool.query(`select app.remove_interested($1, $2, $3)`, [a, id, b])), 'not_found');
  assert.equal((await view(id, poster)).interested_count, 1);
  await pool.query(`select app.remove_interested($1, $2, $3)`, [poster, id, b]);
  assert.equal((await view(id, poster)).interested_count, 0);
  assert.equal(await errorOf(pool.query(`select app.remove_interested($1, $2, $3)`, [poster, id, b])), 'not_found');
});

test('another player cannot convert, remove or cancel a request', async () => {
  const { poster, id } = await footballRequest();
  const a = await player('A');
  const other = await player('Other');
  await interest(a, id);
  assert.equal(await errorOf(convert(other, id, { meeting_point: 'Park', spots: 3 })), 'not_found');
  assert.equal(await errorOf(pool.query(`select app.remove_interested($1, $2, $3)`, [other, id, a])), 'not_found');
  assert.equal(await errorOf(pool.query(`select app.cancel_game_request($1, $2)`, [other, id])), 'not_found');
  const r = await view(id, poster);
  assert.equal(r.status, 'open');
  assert.equal(r.interested_count, 1);
  assert.equal((await one(`select count(*)::int as n from games`)).n, 0);
});

test('cancelling is for the poster and for open requests only', async () => {
  const { poster, id } = await footballRequest();
  const r = await one(`select app.game_request_json(app.cancel_game_request($1, $2), $1) as r`, [poster, id]).then((x) => x.r);
  assert.equal(r.status, 'cancelled');
  assert.equal(await errorOf(pool.query(`select app.cancel_game_request($1, $2)`, [poster, id])), 'not_found');
});

test('converting with the poster booking: poster plus the first interested, the rest told they are not in', async () => {
  const poster = await player('Poster', { football: 3 });
  const courtId = await addCourt(pool, venueId, { sportId: 'football', basePrice: 300000 });
  const held = await one(`select (app.hold_slots($1, $2, $3::timestamp[], $4)).id`, [poster, courtId, [`${saturday}T19:00:00`], now]);
  await pool.query(`select app.confirm_booking($1, $2, null, null, $3)`, [poster, held.id, now]);
  const r = await create(poster, { sport_id: 'football', ...window, area: 'Chilonzor', players_needed: 9, min_level: 1, max_level: 4, note: 'Friendly' });

  const [a, b, c] = [await player('A'), await player('B'), await player('C')];
  await interest(a, r.id, tap(1));
  await interest(b, r.id, tap(2));
  await interest(c, r.id, tap(3));
  await pool.query('delete from notifications');

  const game = await convert(poster, r.id, { booking_id: held.id, spots: 3 });
  assert.equal(game.kind, 'booked');
  assert.equal(game.sport_id, 'football');
  assert.equal(game.spots, 3);
  assert.equal(game.min_level, 1);
  assert.equal(game.max_level, 4);
  assert.equal(game.note, 'Friendly');
  assert.equal(game.participant_ids[0], poster);
  assert.deepEqual(game.participant_ids.slice(1).sort(), [a, b].sort());

  const done = await view(r.id, poster);
  assert.equal(done.status, 'converted');
  assert.equal(done.game_id, game.id);

  for (const [user, added] of [[a, true], [b, true], [c, false]]) {
    const notes = await notesOf(user, 'request_converted');
    assert.equal(notes.length, 1);
    assert.equal(notes[0].category, 'requests');
    assert.equal(notes[0].payload.added, added);
    assert.equal(notes[0].payload.game_id, game.id);
    assert.equal(notes[0].payload.request_id, r.id);
    assert.equal(notes[0].payload.sport_id, 'football');
  }
  assert.equal((await notesOf(poster, 'request_converted')).length, 0);

  assert.equal(await errorOf(convert(poster, r.id, { booking_id: held.id, spots: 3 })), 'not_found');
  assert.equal((await one(`select count(*)::int as n from games`)).n, 1);
});

test('converting a running request with a meeting point makes a map_point game with everyone interested', async () => {
  const poster = await player('Runner');
  const r = await create(poster, { sport_id: 'running', ...window, area: 'Anhor park', players_needed: 5 });
  const [a, b] = [await player('A'), await player('B')];
  await interest(a, r.id);
  await interest(b, r.id);
  const game = await convert(poster, r.id, { meeting_point: 'Anhor park gate', meeting_lat: 41.3, meeting_lng: 69.3 });
  assert.equal(game.kind, 'map_point');
  assert.equal(game.spots, 6);
  assert.equal(game.starts_local, `${saturday}T18:00:00`);
  assert.equal(game.ends_local, `${saturday}T21:00:00`);
  assert.equal(game.participant_ids[0], poster);
  assert.deepEqual(game.participant_ids.slice(1).sort(), [a, b].sort());
  assert.equal((await notesOf(a, 'request_converted'))[0].payload.added, true);
});

test('a place-only request can convert to a venue game with its own times', async () => {
  const poster = await player('Gym rat');
  const r = await create(poster, { sport_id: 'gym', ...window, venue_id: venueId, players_needed: 2 });
  assert.equal(r.venue_id, venueId);
  const game = await convert(poster, r.id, { venue_id: venueId, starts_local: `${saturday}T19:00:00`, ends_local: `${saturday}T20:00:00` });
  assert.equal(game.kind, 'place');
  assert.equal(game.starts_local, `${saturday}T19:00:00`);
  assert.equal(game.spots, 3);
});

test('the spots are never exceeded when converting', async () => {
  const poster = await player('Poster');
  const r = await create(poster, { sport_id: 'running', ...window, players_needed: 1 });
  const [a, b] = [await player('A'), await player('B')];
  await interest(a, r.id, tap(1));
  await interest(b, r.id, tap(2));
  const game = await convert(poster, r.id, { meeting_point: 'Gate', spots: 2 });
  assert.deepEqual(game.participant_ids, [poster, a]);
  assert.equal((await notesOf(b, 'request_converted'))[0].payload.added, false);
});

test('request validation', async () => {
  const poster = await player('Poster');
  const ok = { sport_id: 'football', ...window, players_needed: 3 };
  assert.equal(await errorOf(create(poster, { ...ok, players_needed: 0 })), 'invalid_argument');
  assert.equal(await errorOf(create(poster, { ...ok, players_needed: 30 })), 'invalid_argument');
  assert.equal(await errorOf(create(poster, { ...ok, min_level: 4, max_level: 2 })), 'invalid_argument');
  assert.equal(await errorOf(create(poster, { ...ok, ends_local: window.starts_local })), 'invalid_argument');
  assert.equal(await errorOf(create(poster, { ...ok, starts_local: `${saturday}T08:00:00`, ends_local: `${saturday}T20:00:01` })), 'invalid_argument');
  assert.equal(await errorOf(create(poster, { ...ok, sport_id: 'curling' })), 'not_found');
  assert.equal(
    await errorOf(create(poster, { ...ok, starts_local: '2026-11-22T20:30:00', ends_local: '2026-11-22T21:30:00' }, tashkent('2026-11-22', 21))),
    'in_past',
  );
  assert.equal(await errorOf(create(poster, { ...ok, starts_local: '2026-12-20T18:00:00', ends_local: '2026-12-20T19:00:00' })), 'too_far_ahead');
  assert.equal(await errorOf(create(poster, { ...ok, venue_id: randomUUID() })), 'not_found');

  const nowhere = await createUser(pool, 'No city');
  assert.equal(await errorOf(create(nowhere, ok)), 'invalid_argument');
  const viaVenue = await create(nowhere, { ...ok, venue_id: venueId });
  assert.equal(viaVenue.city_id, 'tashkent');
});

test('a blocked player cannot post or say I am in', async () => {
  const { id } = await footballRequest();
  const blocked = await player('Blocked');
  for (let i = 0; i < 3; i++) {
    await pool.query(`select app.reliability_event($1, 'no_show', $2, $3)`, [blocked, `b${i}`, now]);
  }
  assert.equal(await errorOf(interest(blocked, id)), 'reliability_too_low');
  assert.equal(await errorOf(create(blocked, { sport_id: 'football', ...window, players_needed: 3 })), 'reliability_too_low');
});

test('expire_game_requests expires ended open requests and notifies the poster and interested once', async () => {
  const { poster, id } = await footballRequest();
  const other = await footballRequest();
  const [a, b] = [await player('A'), await player('B')];
  await interest(a, id);
  await interest(b, id);
  await pool.query('delete from notifications');

  const early = (await one(`select app.expire_game_requests($1) as n`, [tashkent(saturday, 20)])).n;
  assert.equal(early, 0);
  const late = tashkent(saturday, 21, 1);
  assert.equal((await one(`select app.expire_game_requests($1) as n`, [late])).n, 2);
  assert.equal((await one(`select app.expire_game_requests($1) as n`, [late])).n, 0);

  assert.equal((await view(id, poster)).status, 'expired');
  assert.equal((await view(other.id, other.poster)).status, 'expired');
  for (const user of [poster, a, b]) {
    const notes = await notesOf(user, 'request_expired');
    assert.equal(notes.length, 1);
    assert.equal(notes[0].category, 'requests');
    assert.equal(notes[0].payload.request_id, id);
  }
  // A converted request is not expired later.
  const conv = await player('Converter');
  const runner = await create(conv, { sport_id: 'running', ...window, players_needed: 2 });
  await convert(conv, runner.id, { meeting_point: 'Gate' });
  await pool.query(`select app.expire_game_requests($1)`, [tashkent('2026-11-29', 10)]);
  assert.equal((await view(runner.id, conv)).status, 'converted');
});

test('list_game_requests: open, not ended, earliest first, plus my own', async () => {
  await pool.query('delete from game_requests');
  const p1 = await player('P1');
  const p2 = await player('P2');
  const late = await create(p1, { sport_id: 'football', starts_local: `${saturday}T20:00:00`, ends_local: `${saturday}T21:00:00`, players_needed: 3 });
  const early = await create(p2, { sport_id: 'football', starts_local: `${saturday}T10:00:00`, ends_local: `${saturday}T11:00:00`, players_needed: 3 });
  const cancelled = await create(p2, { sport_id: 'football', ...window, players_needed: 3 });
  await pool.query(`select app.cancel_game_request($1, $2)`, [p2, cancelled.id]);
  const viewer = await player('Viewer');
  const list = (user, city, when = now) =>
    pool.query(`select r from app.list_game_requests($1, $2, $3) r`, [user, city, when]).then((x) => x.rows.map((y) => y.r));

  assert.deepEqual((await list(viewer, 'tashkent')).map((r) => r.id), [early.id, late.id]);
  assert.deepEqual(await list(viewer, 'almaty'), []);
  // My own open request shows in any city.
  assert.deepEqual((await list(p1, 'almaty')).map((r) => r.id), [late.id]);
  assert.deepEqual((await list(viewer, 'tashkent', tashkent(saturday, 11, 30))).map((r) => r.id), [late.id]);
});

test('anon cannot execute any new public function; players can', async () => {
  const id = randomUUID();
  const calls = [
    ['create_game_request', [JSON.stringify({ sport_id: 'football' })]],
    ['get_game_request', [id]],
    ['list_game_requests', ['tashkent']],
    ['request_interest', [id]],
    ['withdraw_interest', [id]],
    ['remove_interested', [id, id]],
    ['cancel_game_request', [id]],
    ['convert_game_request', [id, JSON.stringify({})]],
    ['list_players', ['tashkent']],
    ['player_profile', [id]],
  ];
  const sql = (fn, args) => `select public.${fn}(${args.map((_, i) => `$${i + 1}`).join(', ')})`;
  for (const [fn, args] of calls) {
    await expectError(asAnon(pool, (c) => c.query(sql(fn, args), args)), '42501');
  }
  const p = await player('Api');
  await expectError(asUser(pool, p, (c) => c.query(sql('request_interest', [id]), [id])), 'not_found');
});

test('through the API: post, say I am in, list, convert as the signed-in player', async () => {
  const poster = await player('Api poster');
  const p = await player('Api player');
  const rpc = (user, sql, args) => asUser(pool, user, async (c) => (await c.query(sql, args)).rows[0].r);
  const day = new Date(Date.now() + 2 * 24 * 3600 * 1000 + 5 * 3600 * 1000).toISOString().slice(0, 10);
  const body = { sport_id: 'running', starts_local: `${day}T19:00:00`, ends_local: `${day}T20:00:00`, players_needed: 4, area: 'Park' };
  const r = await rpc(poster, 'select public.create_game_request($1::jsonb) as r', [JSON.stringify(body)]);
  assert.equal(r.my_status, 'host');
  const liked = await rpc(p, 'select public.request_interest($1) as r', [r.id]);
  assert.equal(liked.my_status, 'interested');
  assert.equal((await rpc(p, 'select public.get_game_request($1) as r', [r.id])).interested_count, 1);
  assert.equal(await rpc(p, 'select public.get_game_request($1) as r', [randomUUID()]), null);
  const listed = await asUser(pool, p, (c) => c.query(`select public.list_game_requests('tashkent') as r`).then((x) => x.rows));
  assert.ok(listed.some((x) => x.r.id === r.id));
  const out = await rpc(p, 'select public.withdraw_interest($1) as r', [r.id]);
  assert.equal(out.interested_count, 0);
  await rpc(p, 'select public.request_interest($1) as r', [r.id]);
  const removed = await rpc(poster, 'select public.remove_interested($1, $2) as r', [r.id, p]);
  assert.equal(removed.interested_count, 0);
  await rpc(p, 'select public.request_interest($1) as r', [r.id]);
  const game = await rpc(poster, 'select public.convert_game_request($1, $2::jsonb) as r', [r.id, JSON.stringify({ meeting_point: 'Gate' })]);
  assert.equal(game.kind, 'map_point');
  assert.deepEqual(game.participant_ids, [poster, p]);
  const other = await player('Api cancel');
  const c = await rpc(other, 'select public.create_game_request($1::jsonb) as r', [JSON.stringify(body)]);
  assert.equal((await rpc(other, 'select public.cancel_game_request($1) as r', [c.id])).status, 'cancelled');
});
