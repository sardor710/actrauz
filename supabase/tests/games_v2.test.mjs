// Milestone 4b: games for every sport type, requests to join, invites, host
// tools and visibility. The `app` functions are called with a fixed clock;
// the API tests go through the `public` wrappers, which use now(), so their
// games are placed relative to the real clock.

import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { after, before, beforeEach, test } from 'node:test';
import { asAnon, asUser, createUser, errorOf, expectError, freshDb } from './helpers/db.mjs';
import { addCourt, addOwner, addVenue, tashkent } from './helpers/fixtures.mjs';

let db;
let pool;
let venueId;
let owner;

// Sunday evening in Tashkent: every Monday slot is in the future.
const now = tashkent('2026-11-22', 20);
const ten = '2026-11-23T10:00:00';

before(async () => {
  db = await freshDb('games_v2');
  pool = db.pool;
  venueId = await addVenue(pool, { name: 'Test venue' });
  owner = await addOwner(pool, venueId, await createUser(pool, 'Owner'));
});
after(() => db.end());

beforeEach(async () => {
  await pool.query('delete from notifications');
  await pool.query('delete from reliability_events');
});

const one = async (sql, params) => (await pool.query(sql, params)).rows[0];

async function player(name, levels = {}) {
  const id = await createUser(pool, name);
  await pool.query(`update profiles set city_id = 'tashkent' where id = $1`, [id]);
  for (const [sportId, level] of Object.entries(levels)) {
    await pool.query(`insert into player_levels (user_id, sport_id, level) values ($1, $2, $3)`, [id, sportId, level]);
  }
  return id;
}

/** A confirmed app booking on a new 400 000 padel court (so slots never clash). */
async function booking(user, start = ten, courtId = null) {
  courtId ??= await addCourt(pool, venueId, { basePrice: 400000 });
  const held = await one(`select (app.hold_slots($1, $2, $3::timestamp[], $4)).id`, [user, courtId, [start], now]);
  await pool.query(`select app.confirm_booking($1, $2, null, null, $3)`, [user, held.id, now]);
  return held.id;
}

const create = (user, game, when = now) =>
  one(`select app.game_json(app.create_game($1, $2::jsonb, $3), $1) as g`, [user, JSON.stringify(game), when]).then((r) => r.g);

const json = (gameId, user) => one(`select app.game_json(g, $2) as g from games g where g.id = $1`, [gameId, user]).then((r) => r.g);

const join = (user, gameId, when = now) =>
  one(`select app.game_json(app.join_game($1, $2, $3), $1) as g`, [user, gameId, when]).then((r) => r.g);
const leave = (user, gameId, when = now) =>
  one(`select app.game_json(app.leave_game($1, $2, $3), $1) as g`, [user, gameId, when]).then((r) => r.g);
const requestToJoin = (user, gameId, when = now) =>
  one(`select r.* from app.request_to_join($1, $2, $3) r`, [user, gameId, when]);
const decide = (user, requestId, approve, when = now) =>
  one(`select app.game_json(app.decide_join_request($1, $2, $3, $4), $1) as g`, [user, requestId, approve, when]).then((r) => r.g);
const invite = (user, gameId, invitee, when = now) =>
  pool.query(`select app.invite_to_game($1, $2, $3, $4)`, [user, gameId, invitee, when]);

const notesOf = (user, kind) =>
  pool
    .query(`select * from notifications where user_id = $1 ${kind ? 'and kind = $2' : ''} order by created_at`, kind ? [user, kind] : [user])
    .then((r) => r.rows);
const eventsOf = (user) => pool.query(`select kind, ref from reliability_events where user_id = $1`, [user]).then((r) => r.rows);
const count = (gameId) => one(`select count(*)::int as n from game_participants where game_id = $1`, [gameId]).then((r) => r.n);

/** A booked padel game on a fresh host's Monday 10:00 booking. */
async function bookedGame({ spots = 4, minLevel = 1, maxLevel = 5, visibility = 'public' } = {}) {
  const host = await player('Host');
  const bookingId = await booking(host);
  const g = await create(host, { sport_id: 'padel', booking_id: bookingId, spots, min_level: minLevel, max_level: maxLevel, visibility });
  return { host, bookingId, id: g.id, game: g };
}

/** A place-only game inserted directly, starting `hoursAhead` after the real clock (for the API wrappers). */
async function liveGame({ visibility = 'public', spots = 4, minLevel = 1, maxLevel = 5, hoursAhead = 48 } = {}) {
  const host = await player('Live host');
  const { id } = await one(
    `insert into games (sport_id, city_id, venue_id, host_id, kind, visibility, during, utc_offset_minutes, spots, min_level, max_level)
     values ('gym', 'tashkent', $1, $2, 'place', $3,
             tstzrange(now() + make_interval(hours => $4), now() + make_interval(hours => $4 + 1)), 300, $5, $6, $7)
     returning id`,
    [venueId, host, visibility, hoursAhead, spots, minLevel, maxLevel],
  );
  await pool.query(`insert into game_participants (game_id, user_id) values ($1, $2)`, [id, host]);
  return { host, id };
}

async function block(user) {
  for (let i = 0; i < 2; i++) {
    await pool.query(`select app.reliability_event($1, 'no_show', $2, $3)`, [user, randomUUID(), now]);
  }
}

// --- creating ---------------------------------------------------------------

test('a game on my own confirmed padel booking: price split, host alone, kind booked', async () => {
  const { host, bookingId, game } = await bookedGame({ spots: 4 });
  assert.equal(game.kind, 'booked');
  assert.equal(game.price_per_player, 100000);
  assert.equal(game.booking_id, bookingId);
  assert.equal(game.venue_id, venueId);
  assert.equal(game.city_id, 'tashkent');
  assert.equal(game.starts_local, ten);
  assert.equal(game.ends_local, '2026-11-23T11:30:00');
  assert.equal(game.visibility, 'public');
  assert.equal(game.status, 'open');
  assert.equal(game.my_status, 'host');
  assert.deepEqual(game.participant_ids, [host]);
  assert.equal(game.participants.length, 1);
  assert.equal(game.participants[0].id, host);
  assert.equal(game.participants[0].name, 'Host');
  assert.deepEqual(game.participants[0].reliability, { score: 80, badge: 'new' });
  assert.deepEqual(game.join_requests, []);
});

test('the price per player rounds up', async () => {
  const host = await player('Thirds');
  const g = await create(host, { sport_id: 'padel', booking_id: await booking(host), spots: 3 });
  assert.equal(g.price_per_player, 133334);
});

test('a booking that is not mine, not confirmed, already used or for another sport is refused', async () => {
  const host = await player('Owner of booking');
  const other = await player('Someone else');
  const bookingId = await booking(host);
  assert.equal(await errorOf(create(other, { sport_id: 'padel', booking_id: bookingId, spots: 4 })), 'booking_not_usable');
  assert.equal(await errorOf(create(host, { sport_id: 'football', booking_id: bookingId, spots: 4 })), 'booking_not_usable');

  await create(host, { sport_id: 'padel', booking_id: bookingId, spots: 4 });
  assert.equal(await errorOf(create(host, { sport_id: 'padel', booking_id: bookingId, spots: 4 })), 'game_exists');

  const cancelled = await booking(host, '2026-11-23T13:00:00');
  await pool.query(`select app.cancel_booking($1, $2, $3)`, [host, cancelled, now]);
  assert.equal(await errorOf(create(host, { sport_id: 'padel', booking_id: cancelled, spots: 4 })), 'booking_not_usable');

  // A booking that has started cannot carry a new game.
  const later = await booking(host, '2026-11-23T16:00:00');
  assert.equal(
    await errorOf(create(host, { sport_id: 'padel', booking_id: later, spots: 4 }, tashkent('2026-11-23', 16, 30))),
    'booking_not_usable',
  );
});

test('a bookable sport needs a booking', async () => {
  const p = await player('No booking');
  assert.equal(
    await errorOf(create(p, { sport_id: 'football', venue_id: venueId, starts_local: '2026-11-23T10:00:00', ends_local: '2026-11-23T11:00:00', spots: 10 })),
    'booking_not_usable',
  );
});

test('spots and levels are checked', async () => {
  const host = await player('Checks');
  const bookingId = await booking(host);
  for (const bad of [{ spots: 1 }, { spots: 31 }, { spots: 4, min_level: 0 }, { spots: 4, max_level: 6 }, { spots: 4, min_level: 4, max_level: 2 }]) {
    assert.equal(await errorOf(create(host, { sport_id: 'padel', booking_id: bookingId, ...bad })), 'invalid_argument', JSON.stringify(bad));
  }
  assert.equal(
    await errorOf(create(host, { sport_id: 'padel', booking_id: bookingId, spots: 4, visibility: 'secret' })),
    'invalid_argument',
  );
});

test('a distance that rounds past the column limit is invalid, not an overflow', async () => {
  const p = await player('Ultra');
  const run = { sport_id: 'running', meeting_point: 'Park', spots: 4, starts_local: '2026-11-23T07:00:00', ends_local: '2026-11-23T08:00:00' };
  assert.equal(await errorOf(create(p, { ...run, distance_km: 9999.95 })), 'invalid_argument');
  assert.equal((await create(p, { ...run, distance_km: 9999.94 })).distance_km, 9999.9);
});

test('running from a meeting point is a map_point game with no price; gym at a venue is a place game', async () => {
  const runner = await player('Runner');
  const run = await create(runner, {
    sport_id: 'running',
    meeting_point: 'Amir Temur square, north gate',
    meeting_lat: 41.3111,
    meeting_lng: 69.2797,
    starts_local: '2026-11-23T07:00:00',
    ends_local: '2026-11-23T08:00:00',
    spots: 6,
    distance_km: 8.5,
    pace: '5:30',
    note: 'Easy pace',
  });
  assert.equal(run.kind, 'map_point');
  assert.equal(run.price_per_player, null);
  assert.equal(run.venue_id, null);
  assert.equal(run.city_id, 'tashkent');
  assert.equal(run.meeting_point, 'Amir Temur square, north gate');
  assert.equal(run.meeting_lat, 41.3111);
  assert.equal(run.distance_km, 8.5);
  assert.equal(run.pace, '5:30');
  assert.equal(run.starts_local, '2026-11-23T07:00:00');
  assert.equal(run.ends_local, '2026-11-23T08:00:00');
  assert.deepEqual(run.participant_ids, [runner]);

  const gym = await create(runner, {
    sport_id: 'gym',
    venue_id: venueId,
    starts_local: '2026-11-24T18:00:00',
    ends_local: '2026-11-24T19:30:00',
    spots: 2,
  });
  assert.equal(gym.kind, 'place');
  assert.equal(gym.venue_id, venueId);
  assert.equal(gym.price_per_player, null);
});

test('place-only games: past, too far ahead, bad duration and missing place are refused', async () => {
  const p = await player('Timing');
  const base = { sport_id: 'running', meeting_point: 'Park', spots: 4 };
  assert.equal(await errorOf(create(p, { ...base, starts_local: '2026-11-22T19:00:00', ends_local: '2026-11-22T20:00:00' })), 'in_past');
  assert.equal(await errorOf(create(p, { ...base, starts_local: '2026-12-08T07:00:00', ends_local: '2026-12-08T08:00:00' })), 'too_far_ahead');
  assert.equal(await errorOf(create(p, { ...base, starts_local: '2026-11-23T07:00:00', ends_local: '2026-11-23T07:00:00' })), 'invalid_argument');
  assert.equal(await errorOf(create(p, { ...base, starts_local: '2026-11-23T07:00:00', ends_local: '2026-11-23T19:30:00' })), 'invalid_argument');
  assert.equal(
    await errorOf(create(p, { sport_id: 'running', spots: 4, starts_local: '2026-11-23T07:00:00', ends_local: '2026-11-23T08:00:00' })),
    'invalid_argument',
  );
});

// --- invite-only and visibility -------------------------------------------

test('an invite-only game is invisible to strangers until they are invited', async () => {
  const { host, id } = await liveGame({ visibility: 'invite_only', minLevel: 4, maxLevel: 5 });
  const stranger = await player('Stranger', { gym: 1 });

  const listed = await asUser(pool, stranger, async (c) => (await c.query(`select public.list_games('tashkent') as g`)).rows.map((r) => r.g.id));
  assert.ok(!listed.includes(id));
  const fetched = await asUser(pool, stranger, async (c) => (await c.query('select public.get_game($1) as g', [id])).rows[0].g);
  assert.equal(fetched, null);
  await expectError(asUser(pool, stranger, (c) => c.query('select public.join_game($1)', [id])), 'not_found');
  await expectError(asUser(pool, stranger, (c) => c.query('select * from games')), '42501');
  await expectError(asUser(pool, stranger, (c) => c.query('select * from game_participants')), '42501');
  await expectError(asUser(pool, stranger, (c) => c.query('select * from game_join_requests')), '42501');
  await expectError(asUser(pool, stranger, (c) => c.query('select * from game_invites')), '42501');

  const invited = await asUser(pool, host, async (c) => (await c.query('select public.invite_to_game($1, $2) as g', [id, stranger])).rows[0].g);
  assert.equal(invited.id, id);
  const note = await notesOf(stranger, 'game_invite');
  assert.equal(note.length, 1);
  assert.equal(note[0].category, 'invites');
  assert.equal(note[0].payload.game_id, id);
  assert.equal(note[0].payload.actor_name, 'Live host');
  assert.equal(note[0].payload.sport_id, 'gym');
  assert.ok(note[0].payload.starts_local);

  const seen = await asUser(pool, stranger, async (c) => (await c.query('select public.get_game($1) as g', [id])).rows[0].g);
  assert.equal(seen.my_status, 'invited');
  assert.equal(seen.join_requests, undefined);
  const listedNow = await asUser(pool, stranger, async (c) => (await c.query(`select public.list_games('almaty') as g`)).rows.map((r) => r.g.id));
  assert.ok(listedNow.includes(id), 'invited games are listed whatever the city');

  // Level 1 against a 4-5 game: the invite skips the level check.
  const joined = await asUser(pool, stranger, async (c) => (await c.query('select public.join_game($1) as g', [id])).rows[0].g);
  assert.equal(joined.my_status, 'participant');
  assert.deepEqual(joined.participant_ids, [host, stranger]);
  assert.equal((await one(`select status from game_invites where game_id = $1 and user_id = $2`, [id, stranger])).status, 'accepted');
  assert.equal((await notesOf(host, 'game_joined')).length, 1);
});

test('only the host invites; a player already in cannot be invited; an invite can be declined', async () => {
  const { host, id } = await bookedGame();
  const p = await player('Invitee');
  const other = await player('Other');
  assert.equal(await errorOf(invite(other, id, p)), 'not_found');
  assert.equal(await errorOf(invite(host, id, host)), 'already_joined');
  await invite(host, id, p);
  await invite(host, id, p);
  assert.equal((await one(`select count(*)::int as n from game_invites where game_id = $1`, [id])).n, 1);
  assert.equal((await json(id, p)).my_status, 'invited');
  await pool.query(`select app.decline_invite($1, $2)`, [p, id]);
  assert.equal((await one(`select status from game_invites where game_id = $1 and user_id = $2`, [id, p])).status, 'declined');
  assert.equal((await json(id, p)).my_status, null);
  assert.equal(await errorOf(pool.query(`select app.decline_invite($1, $2)`, [p, id])), 'not_found');
});

test('a stranger cannot ask to join an invite-only game', async () => {
  const { id } = await liveGame({ visibility: 'invite_only' });
  const stranger = await player('Stranger');
  assert.equal(await errorOf(requestToJoin(stranger, id, new Date().toISOString())), 'not_found');
});

test('a pending invite does not get past a full game', async () => {
  const { host, id } = await bookedGame({ spots: 2 });
  const invited = await player('Invited');
  await invite(host, id, invited);
  await join(await player('Faster'), id);
  assert.equal(await errorOf(join(invited, id)), 'full');
});

test('a game that has started takes nobody new, invited or not', async () => {
  const { host, id } = await bookedGame();
  const invited = await player('Invited late');
  await invite(host, id, invited);
  const started = tashkent('2026-11-23', 10, 15);
  assert.equal(await errorOf(join(await player('Walk-up'), id, started)), 'not_found');
  assert.equal(await errorOf(join(invited, id, started)), 'not_found');
  assert.equal(await count(id), 1);
});

// --- requests to join -------------------------------------------------------

test('a player outside the level range asks to join; only the host decides', async () => {
  const { host, id } = await bookedGame({ minLevel: 4, maxLevel: 5 });
  const low = await player('Low', { padel: 2 });
  assert.equal(await errorOf(join(low, id)), 'level_out_of_range');

  const request = await requestToJoin(low, id);
  assert.equal(request.status, 'pending');
  assert.equal(await errorOf(requestToJoin(low, id)), 'already_requested');
  const asked = await notesOf(host, 'join_request');
  assert.equal(asked.length, 1);
  assert.equal(asked[0].payload.request_id, request.id);
  assert.equal(asked[0].payload.actor_name, 'Low');
  assert.equal(asked[0].payload.game_id, id);

  const hostView = await json(id, host);
  assert.equal(hostView.join_requests.length, 1);
  assert.equal(hostView.join_requests[0].id, request.id);
  assert.equal(hostView.join_requests[0].user_id, low);
  assert.equal(hostView.join_requests[0].name, 'Low');
  assert.equal(hostView.join_requests[0].level, 2);
  assert.deepEqual(hostView.join_requests[0].reliability, { score: 80, badge: 'new' });
  assert.equal((await json(id, low)).my_status, 'requested');
  assert.equal((await json(id, low)).join_requests, undefined);

  const stranger = await player('Stranger');
  assert.equal(await errorOf(decide(stranger, request.id, true)), 'not_found');
  assert.equal(await errorOf(decide(low, request.id, true)), 'not_found');
  assert.equal(await count(id), 1);

  const approved = await decide(host, request.id, true);
  assert.equal(approved.participant_ids.length, 2);
  assert.deepEqual(approved.join_requests, []);
  assert.equal((await json(id, low)).my_status, 'participant');
  assert.equal((await notesOf(low, 'join_approved')).length, 1);
  assert.equal(await errorOf(decide(host, request.id, true)), 'not_found');
  assert.equal(await errorOf(requestToJoin(low, id)), 'already_joined');
});

test('approving a requester who has been blocked since asking is refused', async () => {
  const { host, id } = await bookedGame();
  const p = await player('Soon blocked');
  const request = await requestToJoin(p, id);
  await block(p);
  assert.equal(await errorOf(decide(host, request.id, true)), 'reliability_too_low');
  assert.equal(await count(id), 1);
});

test('a declined or withdrawn request', async () => {
  const { host, id } = await bookedGame();
  const a = await player('A');
  const b = await player('B');
  const ra = await requestToJoin(a, id);
  await decide(host, ra.id, false);
  assert.equal((await notesOf(a, 'join_declined')).length, 1);
  assert.equal(await count(id), 1);

  const rb = await requestToJoin(b, id);
  assert.equal(await errorOf(pool.query(`select app.withdraw_join_request($1, $2)`, [a, rb.id])), 'not_found');
  await pool.query(`select app.withdraw_join_request($1, $2)`, [b, rb.id]);
  assert.equal((await one(`select status from game_join_requests where id = $1`, [rb.id])).status, 'withdrawn');
  assert.equal(await errorOf(decide(host, rb.id, true)), 'not_found');
  // A new request after a withdrawn one is fine.
  assert.equal((await requestToJoin(b, id)).status, 'pending');
});

test('approving when the game is full is refused; the filler is told apart from the others', async () => {
  const { host, id } = await bookedGame({ spots: 3 });
  const first = await player('First');
  const second = await player('Second');
  const third = await player('Third');
  const r2 = await requestToJoin(second, id);
  const r3 = await requestToJoin(third, id);
  await join(first, id);
  assert.equal((await notesOf(first, 'game_full')).length, 0);

  await decide(host, r2.id, true);
  // Second filled it: the host and First hear game_full, Second hears join_approved only.
  assert.equal((await notesOf(host, 'game_full')).length, 1);
  assert.equal((await notesOf(first, 'game_full')).length, 1);
  assert.equal((await notesOf(second, 'game_full')).length, 0);
  assert.equal((await notesOf(second, 'join_approved')).length, 1);

  assert.equal(await errorOf(decide(host, r3.id, true)), 'full');
  assert.equal(await count(id), 3);
  assert.equal(await errorOf(requestToJoin(await player('Late'), id)), 'full');
});

test('joining the last spot tells the others the game is full', async () => {
  const { host, id } = await bookedGame({ spots: 2 });
  const p = await player('Filler');
  await join(p, id);
  const joined = await notesOf(host, 'game_joined');
  assert.equal(joined.length, 1);
  assert.equal(joined[0].payload.actor_name, 'Filler');
  assert.equal(joined[0].payload.sport_id, 'padel');
  assert.equal(joined[0].payload.starts_local, ten);
  assert.equal((await notesOf(host, 'game_full')).length, 1);
  assert.equal((await notesOf(p, 'game_full')).length, 0);
});

// --- leaving ----------------------------------------------------------------

test('leaving inside six hours of the start is a late cancellation; earlier is free', async () => {
  const { host, id } = await bookedGame();
  const late = await player('Late leaver');
  const early = await player('Early leaver');
  await join(late, id);
  await join(early, id);

  await leave(early, id, tashkent('2026-11-23', 0));
  assert.deepEqual(await eventsOf(early), []);
  await leave(late, id, tashkent('2026-11-23', 7));
  assert.deepEqual(await eventsOf(late), [{ kind: 'late_cancel', ref: id }]);

  const left = await notesOf(host, 'game_left');
  assert.equal(left.length, 2);
  assert.deepEqual(left.map((n) => n.payload.actor_name).sort(), ['Early leaver', 'Late leaver']);
});

// --- host tools -------------------------------------------------------------

test('host_update_game: spots below the players are refused; a note change tells the others', async () => {
  const { host, id } = await bookedGame({ spots: 4 });
  const a = await player('A');
  const b = await player('B');
  await join(a, id);
  await join(b, id);
  const update = (user, note, spots) => one(`select app.game_json(app.host_update_game($1, $2, $3, $4, $5), $1) as g`, [user, id, note, spots, now]).then((r) => r.g);

  assert.equal(await errorOf(update(host, null, 2)), 'invalid_argument');
  assert.equal(await errorOf(update(host, null, 1)), 'invalid_argument');
  assert.equal(await errorOf(update(a, 'Mine now', null)), 'not_found');

  await pool.query('delete from notifications');
  const changed = await update(host, 'Bring water', null);
  assert.equal(changed.note, 'Bring water');
  assert.equal(changed.spots, 4);
  assert.equal((await notesOf(a, 'game_changed')).length, 1);
  assert.equal((await notesOf(b, 'game_changed')).length, 1);
  assert.equal((await notesOf(host, 'game_changed')).length, 0);

  const resized = await update(host, null, 5);
  assert.equal(resized.spots, 5);
  assert.equal(resized.note, 'Bring water');
  assert.equal(resized.price_per_player, 80000);
});

test('host_remove_participant removes a player without a reliability event', async () => {
  const { host, id } = await bookedGame();
  const p = await player('Removed');
  await join(p, id);
  const remove = (user, member) => pool.query(`select app.host_remove_participant($1, $2, $3, $4)`, [user, id, member, now]);
  assert.equal(await errorOf(remove(p, host)), 'not_found');
  assert.equal(await errorOf(remove(host, host)), 'host_cannot_leave');
  await remove(host, p);
  assert.equal(await count(id), 1);
  assert.equal((await notesOf(p, 'game_removed')).length, 1);
  assert.deepEqual(await eventsOf(p), []);
  assert.equal(await errorOf(remove(host, p)), 'not_participant');
});

test('the host cancels the game and the booking: participants hear, the host does not', async () => {
  const { host, bookingId, id } = await bookedGame();
  const p = await player('Player');
  await join(p, id);
  const stranger = await player('Stranger');
  assert.equal(await errorOf(pool.query(`select app.host_cancel_game($1, $2, true, $3)`, [stranger, id, now])), 'not_found');

  await pool.query(`select app.host_cancel_game($1, $2, true, $3)`, [host, id, now]);
  assert.equal((await one(`select status from games where id = $1`, [id])).status, 'cancelled');
  assert.equal((await one(`select status from bookings where id = $1`, [bookingId])).status, 'cancelled_by_player');
  assert.equal((await notesOf(p, 'game_cancelled')).length, 1);
  assert.equal((await notesOf(host, 'game_cancelled')).length, 0);
});

test('the host cancelling with the booking inside six hours is a late cancellation for the host', async () => {
  const { host, bookingId, id } = await bookedGame();
  await pool.query(`select app.host_cancel_game($1, $2, true, $3)`, [host, id, tashkent('2026-11-23', 6)]);
  assert.equal((await one(`select status from bookings where id = $1`, [bookingId])).status, 'cancelled_by_player');
  assert.deepEqual(await eventsOf(host), [{ kind: 'late_cancel', ref: bookingId }]);
});

test('host tools stop once the game has started', async () => {
  const { host, id } = await bookedGame();
  const p = await player('Stays');
  await join(p, id);
  const started = tashkent('2026-11-23', 10, 15);
  assert.equal(
    await errorOf(pool.query(`select app.host_remove_participant($1, $2, $3, $4)`, [host, id, p, started])),
    'not_found',
  );
  assert.equal(await errorOf(pool.query(`select app.host_cancel_game($1, $2, false, $3)`, [host, id, started])), 'not_cancellable');
  assert.equal(await count(id), 2);
  assert.equal((await one(`select status from games where id = $1`, [id])).status, 'open');
});

test('the host cancels the game but keeps the booking', async () => {
  const { host, bookingId, id } = await bookedGame();
  await pool.query(`select app.host_cancel_game($1, $2, false, $3)`, [host, id, now]);
  assert.equal((await one(`select status from games where id = $1`, [id])).status, 'cancelled');
  assert.equal((await one(`select status from bookings where id = $1`, [bookingId])).status, 'confirmed');
});

test('the venue cancels the booking under a game: game cancelled, everyone told, nobody loses reliability', async () => {
  const { host, bookingId, id } = await bookedGame();
  const p = await player('Player');
  await join(p, id);
  await pool.query(`select app.owner_cancel_booking($1, $2, $3)`, [owner, bookingId, now]);
  assert.equal((await one(`select status from games where id = $1`, [id])).status, 'cancelled');
  assert.equal((await notesOf(host, 'game_cancelled')).length, 1);
  assert.equal((await notesOf(p, 'game_cancelled')).length, 1);
  assert.equal((await one('select count(*)::int as n from reliability_events')).n, 0);
});

test('the host cancelling the booking itself cancels the game too', async () => {
  const { host, bookingId, id } = await bookedGame();
  const p = await player('Player');
  await join(p, id);
  await pool.query(`select app.cancel_booking($1, $2, $3)`, [host, bookingId, now]);
  assert.equal((await one(`select status from games where id = $1`, [id])).status, 'cancelled');
  assert.equal((await notesOf(p, 'game_cancelled')).length, 1);
  assert.equal((await notesOf(host, 'game_cancelled')).length, 0);
});

// --- jobs -------------------------------------------------------------------

test('game reminders go to participants once, two hours before', async () => {
  const { host, id } = await bookedGame();
  const p = await player('Reminded');
  await join(p, id);
  await pool.query(`select app.send_reminders($1)`, [tashkent('2026-11-23', 7)]);
  assert.equal((await notesOf(p, 'game_reminder')).length, 0);
  await pool.query(`select app.send_reminders($1)`, [tashkent('2026-11-23', 8, 30)]);
  await pool.query(`select app.send_reminders($1)`, [tashkent('2026-11-23', 8, 40)]);
  assert.equal((await notesOf(p, 'game_reminder')).length, 1);
  assert.equal((await notesOf(host, 'game_reminder')).length, 1);
  assert.equal((await notesOf(p, 'game_reminder'))[0].payload.game_id, id);
});

test('complete_games gives each participant one game_completed, once', async () => {
  const { host, id } = await bookedGame();
  const p = await player('Finisher');
  await join(p, id);
  const after = tashkent('2026-11-23', 12);
  // Not over yet at 11:00 (it ends at 11:30).
  await pool.query(`select app.complete_games($1)`, [tashkent('2026-11-23', 11)]);
  assert.deepEqual(await eventsOf(host), []);
  assert.ok((await one(`select app.complete_games($1) as n`, [after])).n >= 1);
  assert.equal((await one(`select app.complete_games($1) as n`, [after])).n, 0);
  assert.deepEqual(await eventsOf(host), [{ kind: 'game_completed', ref: id }]);
  assert.deepEqual(await eventsOf(p), [{ kind: 'game_completed', ref: id }]);
  assert.ok((await one(`select completed_at from games where id = $1`, [id])).completed_at);
});

test('a solo game and a player who joined after the start earn no game_completed', async () => {
  const solo = await bookedGame();
  const { host, id } = await bookedGame();
  const early = await player('Early');
  await join(early, id);
  // Only a direct write can add someone after the start; the rule still holds.
  const late = await player('Late');
  await pool.query(`insert into game_participants (game_id, user_id, joined_at) values ($1, $2, $3)`, [id, late, tashkent('2026-11-23', 10, 30)]);
  await pool.query(`select app.complete_games($1)`, [tashkent('2026-11-23', 12)]);
  assert.deepEqual(await eventsOf(solo.host), []);
  assert.deepEqual(await eventsOf(host), [{ kind: 'game_completed', ref: id }]);
  assert.deepEqual(await eventsOf(early), [{ kind: 'game_completed', ref: id }]);
  assert.deepEqual(await eventsOf(late), []);
});

test('a cancelled game is not completed', async () => {
  const { host, id } = await bookedGame();
  await pool.query(`select app.host_cancel_game($1, $2, false, $3)`, [host, id, now]);
  await pool.query(`select app.complete_games($1)`, [tashkent('2026-11-23', 12)]);
  assert.deepEqual(await eventsOf(host), []);
});

// --- reliability and access ---------------------------------------------------

test('a blocked player cannot join, ask to join or create a game', async () => {
  const { id } = await bookedGame();
  const blocked = await player('Blocked');
  const bookingId = await booking(blocked, '2026-11-23T19:00:00');
  await block(blocked);
  assert.equal(await errorOf(join(blocked, id)), 'reliability_too_low');
  assert.equal(await errorOf(requestToJoin(blocked, id)), 'reliability_too_low');
  assert.equal(await errorOf(create(blocked, { sport_id: 'padel', booking_id: bookingId, spots: 4 })), 'reliability_too_low');
});

test('anon cannot execute any new public function; players can', async () => {
  const id = randomUUID();
  const calls = [
    ['create_game', [JSON.stringify({ sport_id: 'padel' })]],
    ['request_to_join', [id]],
    ['withdraw_join_request', [id]],
    ['decide_join_request', [id, true]],
    ['invite_to_game', [id, id]],
    ['decline_invite', [id]],
    ['host_remove_participant', [id, id]],
    ['host_update_game', [id, null, null]],
    ['host_cancel_game', [id, false]],
    ['list_games', ['tashkent']],
    ['get_game', [id]],
    ['join_game', [id]],
    ['leave_game', [id]],
  ];
  const sql = (fn, args) => `select public.${fn}(${args.map((_, i) => `$${i + 1}`).join(', ')})`;
  for (const [fn, args] of calls) {
    await expectError(asAnon(pool, (c) => c.query(sql(fn, args), args)), '42501');
  }
  const p = await player('Api');
  await expectError(asUser(pool, p, (c) => c.query(sql('request_to_join', [id]), [id])), 'not_found');
});

test('through the API: request, approve, update, remove and cancel as the signed-in host', async () => {
  const { host, id } = await liveGame({ minLevel: 5, maxLevel: 5 });
  const p = await player('Api player', { gym: 1 });
  const rpc = (user, sql, args) => asUser(pool, user, async (c) => (await c.query(sql, args)).rows[0].g);

  const requested = await rpc(p, 'select public.request_to_join($1) as g', [id]);
  assert.equal(requested.my_status, 'requested');
  const mine = await one(`select id from game_join_requests where game_id = $1 and user_id = $2`, [id, p]);
  assert.equal(requested.my_request_id, mine.id);
  assert.equal((await rpc(p, 'select public.get_game($1) as g', [id])).my_request_id, mine.id);
  const hostView = await rpc(host, 'select public.get_game($1) as g', [id]);
  const requestId = hostView.join_requests[0].id;
  const approved = await rpc(host, 'select public.decide_join_request($1, true) as g', [requestId]);
  assert.deepEqual(approved.participant_ids, [host, p]);
  assert.equal((await rpc(p, 'select public.get_game($1) as g', [id])).my_request_id, null);
  assert.equal(hostView.my_request_id, null);
  assert.deepEqual(
    approved.participants.map((x) => x.id),
    [host, p],
  );

  const updated = await rpc(host, `select public.host_update_game($1, 'See you', null) as g`, [id]);
  assert.equal(updated.note, 'See you');
  const removed = await rpc(host, 'select public.host_remove_participant($1, $2) as g', [id, p]);
  assert.deepEqual(removed.participant_ids, [host]);
  const cancelled = await rpc(host, 'select public.host_cancel_game($1, false) as g', [id]);
  assert.equal(cancelled.status, 'cancelled');

  const other = await liveGame();
  const again = await rpc(p, 'select public.request_to_join($1) as g', [other.id]);
  assert.equal(again.my_status, 'requested');
  const { id: pending } = await one(`select id from game_join_requests where game_id = $1 and user_id = $2`, [other.id, p]);
  const withdrawn = await rpc(p, 'select public.withdraw_join_request($1) as g', [pending]);
  assert.equal(withdrawn.my_status, null);
  assert.equal(withdrawn.my_request_id, null);
  assert.equal(again.my_request_id, pending);

  await rpc(other.host, 'select public.invite_to_game($1, $2) as g', [other.id, p]);
  const declined = await rpc(p, 'select public.decline_invite($1) as g', [other.id]);
  assert.equal(declined.my_status, null);
});

test('through the API: create a place game', async () => {
  const p = await player('Creator');
  const start = new Date(Date.now() + 26 * 3600 * 1000);
  const local = (d) => new Date(d.getTime() + 5 * 3600 * 1000).toISOString().slice(0, 13) + ':00:00';
  const g = await asUser(pool, p, async (c) =>
    (
      await c.query('select public.create_game($1::jsonb) as g', [
        JSON.stringify({
          sport_id: 'gym',
          venue_id: venueId,
          starts_local: local(start),
          ends_local: local(new Date(start.getTime() + 3600 * 1000)),
          spots: 3,
          visibility: 'invite_only',
        }),
      ])
    ).rows[0].g,
  );
  assert.equal(g.kind, 'place');
  assert.equal(g.visibility, 'invite_only');
  assert.equal(g.my_status, 'host');
});
