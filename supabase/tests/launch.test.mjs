// Milestone 6: launch changes. Games and requests at a hidden venue stay out
// of the public lists; account deletion scrubs and closes an account.

import assert from 'node:assert/strict';
import { after, before, beforeEach, test } from 'node:test';
import { asUser, createUser, errorOf, expectError, freshDb } from './helpers/db.mjs';
import { addAdmin, addCourt, addOwner, addPhone, addVenue, tashkent } from './helpers/fixtures.mjs';

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
  await pool.query('delete from bookings');
  await pool.query('delete from tournament_registrations');
  await pool.query('delete from tournament_categories');
  await pool.query('delete from tournaments');
  await pool.query('delete from notifications');
  await pool.query('delete from venue_owners');
  await pool.query('delete from audit_log');
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

// --- account deletion --------------------------------------------------------

const later = (hours) => new Date(Date.parse(now) + hours * 3600000).toISOString();
const deleteAccount = (user, when = now) => pool.query(`select app.delete_account($1, $2)`, [user, when]);
const statusOf = (table, id) => one(`select status from ${table} where id = $1`, [id]).then((r) => r.status);
const notesOf = (user, kind) =>
  pool.query(`select * from notifications where user_id = $1 and kind = $2`, [user, kind]).then((r) => r.rows);
const rowsFor = (table, user) =>
  one(`select count(*)::int as n from ${table} where user_id = $1`, [user]).then((r) => r.n);
const isParticipant = (gameId, user) =>
  one(`select exists (select 1 from game_participants where game_id = $1 and user_id = $2) as x`, [gameId, user]).then((r) => r.x);

/** An app booking (confirmed unless `confirm` is false) on a new one-hour court, at `start` venue time. */
async function booking(user, start, { confirm = true } = {}) {
  const courtId = await addCourt(pool, venueId, { slot: 60 });
  const held = await one(`select (app.hold_slots($1, $2, $3::timestamp[], $4)).id`, [user, courtId, [start], now]);
  if (confirm) await pool.query(`select app.confirm_booking($1, $2, null, null, $3)`, [user, held.id, now]);
  return held.id;
}

async function tournament({ starts = '2026-12-10', ends = starts, deadline = null } = {}) {
  const { id } = await one(
    `insert into tournaments (city_id, sport_id, venue_id, title_en, starts_on, ends_on, registration_deadline)
     values ('almaty', 'padel', $1, 'Cup', $2, $3, $4) returning id`,
    [venueId, starts, ends, deadline],
  );
  return id;
}

async function category(tournamentId, kind = 'pairs') {
  const { id } = await one(
    `insert into tournament_categories (tournament_id, name_en, kind, cap) values ($1, 'Open', $2, 8) returning id`,
    [tournamentId, kind],
  );
  return id;
}

const register = (user, cat, partner = null, when = now) =>
  one(`select (app.register($1, $2, $3, $4)).id`, [user, cat, partner, when]).then((r) => r.id);
const acceptPartner = (user, registrationId, when = now) =>
  pool.query(`select app.respond_partner($1, $2, true, $3)`, [user, registrationId, when]);

test('deletes a busy account', async () => {
  const me = await player('Leaving');
  await addPhone(pool, me, '+77010000001');
  await pool.query(`insert into player_levels (user_id, sport_id, level) values ($1, 'padel', 3)`, [me]);
  await addOwner(pool, venueId, me);
  const host = await player('Host');

  // (a) A confirmed booking starting in one hour: inside the late window.
  const bookingId = await booking(me, '2026-11-22T21:00:00');
  // (b) An open game I host, with one other player.
  const hosted = await openGame(me, venueId);
  const guest = await player('Guest');
  await pool.query(`insert into game_participants (game_id, user_id) values ($1, $2)`, [hosted, guest]);
  // (c) A game someone else hosts that I joined.
  const joined = await openGame(host, venueId);
  await pool.query(`select app.join_game($1, $2, $3)`, [me, joined, now]);
  // (d) A pending request to join, and an open invite.
  const asked = await openGame(host, venueId);
  const { id: joinRequest } = await one(`select (app.request_to_join($1, $2, $3)).id`, [me, asked, now]);
  const invitedTo = await openGame(host, venueId);
  await pool.query(`select app.invite_to_game($1, $2, $3, $4)`, [host, invitedTo, me, now]);
  // (e) An open Game Request I posted, and one I tapped "I'm in" on.
  const window = { sport_id: 'football', venue_id: venueId, starts_local: '2026-11-28T18:00:00', ends_local: '2026-11-28T21:00:00', players_needed: 6 };
  const { id: myRequest } = await one(`select (app.create_game_request($1, $2::jsonb, $3)).id`, [me, JSON.stringify(window), now]);
  const { id: theirRequest } = await one(`select (app.create_game_request($1, $2::jsonb, $3)).id`, [host, JSON.stringify(window), now]);
  await pool.query(`select app.request_interest($1, $2, $3)`, [me, theirRequest, now]);
  // (f) A pair I lead (partner confirmed) and a pair waiting on me as partner.
  const cup = await tournament();
  const partner = await player('Partner');
  const led = await register(me, await category(cup), partner);
  await acceptPartner(partner, led);
  const registrant = await player('Registrant');
  const waiting = await register(registrant, await category(cup), me);
  assert.ok((await rowsFor('notifications', me)) > 0, 'I had notifications');

  await deleteAccount(me);

  // (a)
  const b = await one(`select status, late_cancellation from bookings where id = $1`, [bookingId]);
  assert.deepEqual(b, { status: 'cancelled_by_player', late_cancellation: true });
  // (b)
  assert.equal(await statusOf('games', hosted), 'cancelled');
  assert.equal((await notesOf(guest, 'game_cancelled')).length, 1);
  // (c)
  assert.equal(await isParticipant(joined, me), false);
  assert.equal((await notesOf(host, 'game_left')).length, 1);
  // (d)
  assert.equal(await statusOf('game_join_requests', joinRequest), 'withdrawn');
  assert.equal((await one(`select status from game_invites where game_id = $1 and user_id = $2`, [invitedTo, me])).status, 'declined');
  // (e)
  assert.equal(await statusOf('game_requests', myRequest), 'cancelled');
  assert.equal((await one(`select count(*)::int as n from game_request_interest where request_id = $1`, [theirRequest])).n, 0);
  // (f): both entries cancelled; the other player of each hears it.
  assert.equal(await statusOf('tournament_registrations', led), 'cancelled');
  assert.equal(await statusOf('tournament_registrations', waiting), 'cancelled');
  assert.equal((await notesOf(partner, 'tournament_partner_cancelled')).length, 1);
  assert.equal((await notesOf(registrant, 'tournament_partner_cancelled')).length, 1);

  // Personal rows are gone, the profile is scrubbed.
  for (const table of ['profile_contacts', 'player_levels', 'venue_owners', 'notifications']) {
    assert.equal(await rowsFor(table, me), 0, table);
  }
  const profile = await one(`select full_name, city_id, deleted_at from profiles where id = $1`, [me]);
  assert.equal(profile.full_name, null);
  assert.equal(profile.city_id, null);
  assert.equal(profile.deleted_at.toISOString(), new Date(now).toISOString());
});

test('deletion: held bookings, booked games, history and late deadlines', async () => {
  const me = await player('Leaving');
  // A hold I never confirmed is given back.
  const held = await booking(me, '2026-11-23T10:00:00', { confirm: false });
  // A game on my booking: cancelled with the booking, its players told once.
  const courtBooking = await booking(me, '2026-11-23T12:00:00');
  const { g } = await one(`select app.game_json(app.create_game($1, $2::jsonb, $3), $1) as g`, [
    me,
    JSON.stringify({ sport_id: 'padel', booking_id: courtBooking, spots: 4 }),
    now,
  ]);
  const guest = await player('Guest');
  await pool.query(`select app.join_game($1, $2, $3)`, [guest, g.id, now]);
  // A game I played in that is over stays in its history.
  const host = await player('Host');
  const { id: past } = await one(
    `insert into games (sport_id, city_id, venue_id, host_id, kind, visibility, during, utc_offset_minutes, spots, completed_at)
     values ('football', 'almaty', $1, $2, 'place', 'public',
             tstzrange($3::timestamptz - interval '2 days', $3::timestamptz - interval '47 hours'), 300, 10,
             $3::timestamptz - interval '47 hours')
     returning id`,
    [venueId, host, now],
  );
  await pool.query(`insert into game_participants (game_id, user_id) values ($1, $2), ($1, $3)`, [past, host, me]);
  // A pair whose registration closed an hour ago: cancel_registration would refuse.
  const cup = await tournament({ starts: '2026-11-24', deadline: later(-1) });
  const partner = await player('Partner');
  const late = await register(me, await category(cup), partner, later(-48));
  await acceptPartner(partner, late, later(-47));

  await deleteAccount(me);

  assert.equal(await statusOf('bookings', held), 'released');
  assert.equal(await statusOf('bookings', courtBooking), 'cancelled_by_player');
  assert.equal(await statusOf('games', g.id), 'cancelled');
  assert.equal((await notesOf(guest, 'game_cancelled')).length, 1);
  assert.equal(await isParticipant(past, me), true);
  assert.equal(await statusOf('tournament_registrations', late), 'cancelled');
  assert.equal((await notesOf(partner, 'tournament_partner_cancelled')).length, 1);
});

test('delete is idempotent', async () => {
  const me = await player('Leaving');
  await deleteAccount(me);
  await deleteAccount(me, later(5));
  const profile = await one(`select deleted_at from profiles where id = $1`, [me]);
  assert.equal(profile.deleted_at.toISOString(), new Date(now).toISOString(), 'the first deletion time stays');
});

test('admin cannot self-delete', async () => {
  const me = await player('Admin');
  await addPhone(pool, me, '+77010000002');
  await addAdmin(pool, me);
  await expectError(deleteAccount(me), 'admin_account');
  const profile = await one(`select full_name, city_id, deleted_at from profiles where id = $1`, [me]);
  assert.deepEqual(profile, { full_name: 'Admin', city_id: 'almaty', deleted_at: null });
  assert.equal(await rowsFor('profile_contacts', me), 1);
});

test('sole owner can delete', async () => {
  const me = await player('Owner');
  const owned = await addVenue(pool, { cityId: 'almaty', name: 'Owned venue' });
  await addOwner(pool, owned, me);
  const coOwner = await player('Co-owner');
  await addOwner(pool, venueId, me);
  await addOwner(pool, venueId, coOwner);

  await deleteAccount(me);

  assert.equal((await one(`select count(*)::int as n from venues where id = $1`, [owned])).n, 1, 'the venue stays');
  assert.equal(await rowsFor('venue_owners', me), 0);
  const log = (await pool.query(`select actor_id, entity, entity_id from audit_log where action = 'owner_account_deleted'`)).rows;
  assert.deepEqual(log, [{ actor_id: me, entity: 'venue', entity_id: owned }], 'only the venue left without an owner');
});

test('deleted players are invisible', async () => {
  const ghost = await player('Ghost');
  await addPhone(pool, ghost, '+77010000009');
  const seeker = await player('Seeker');
  const listed = async () =>
    (await pool.query(`select app.list_players($1, 'almaty', null, null, null, null, 100) as p`, [seeker])).rows.map((r) => r.p.id);
  assert.ok((await listed()).includes(ghost));

  await deleteAccount(ghost);
  assert.ok(!(await listed()).includes(ghost));
  // Even with a name and a city written back, a deleted player is never listed.
  await pool.query(`update profiles set full_name = 'Ghost', city_id = 'almaty' where id = $1`, [ghost]);
  assert.ok(!(await listed()).includes(ghost));
  assert.equal((await one(`select app.find_player_by_phone($1, '+77010000009', $2) as p`, [seeker, now])).p, null);

  const game = await openGame(seeker, venueId);
  assert.equal(await errorOf(pool.query(`select app.invite_to_game($1, $2, $3, $4)`, [seeker, game, ghost, now])), 'not_found');
  const pairs = await category(await tournament());
  assert.equal(await errorOf(register(seeker, pairs, ghost)), 'not_found');
});

test('service only', async () => {
  const me = await player('Leaving');
  await expectError(asUser(pool, me, (c) => c.query(`select public.delete_account_service($1)`, [me])), '42501');
  assert.equal((await one(`select deleted_at from profiles where id = $1`, [me])).deleted_at, null);

  const client = await pool.connect();
  try {
    await client.query('begin');
    await client.query('set local role service_role');
    await client.query(`select public.delete_account_service($1)`, [me]);
    await client.query('commit');
  } finally {
    client.release();
  }
  assert.ok((await one(`select deleted_at from profiles where id = $1`, [me])).deleted_at);
});

test('deleted_at is readable', async () => {
  const me = await player('Reader');
  const gone = await player('Gone');
  await deleteAccount(gone);
  const { rows } = await asUser(pool, me, (c) =>
    c.query(`select id, full_name, city_id, language, terms_accepted_at, created_at, deleted_at from profiles where id = $1`, [gone]),
  );
  assert.equal(rows.length, 1);
  assert.ok(rows[0].deleted_at);
  assert.equal(rows[0].full_name, null);
  // The private settings columns stay private, so `select *` is still refused
  // (community_core.test.mjs).
  await expectError(asUser(pool, me, (c) => c.query('select * from profiles')), '42501');
});
