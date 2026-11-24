// Milestone 4a: notifications, reliability, settings, and the booking hooks
// that feed them. The `app` functions are called directly with a fixed clock;
// the last tests go through the `public` wrappers as the API would.

import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { after, before, beforeEach, test } from 'node:test';
import { asAnon, asUser, createUser, errorOf, expectError, freshDb } from './helpers/db.mjs';
import { addCourt, addOwner, addVenue, monday, tashkent } from './helpers/fixtures.mjs';

let db;
let pool;
let venueId;
let ownerA;
let ownerB;
let court;
let ali;
let vali;

// Sunday evening in Tashkent: every Monday slot is in the future.
const now = tashkent('2026-11-22', 20);
// Monday slots of the default court: 07:00, 08:30, 10:00, 11:30, ...
const ten = '2026-11-23T10:00:00';
const eleven30 = '2026-11-23T11:30:00';

before(async () => {
  db = await freshDb('community');
  pool = db.pool;
  venueId = await addVenue(pool, { name: 'Test venue' });
  await pool.query(`update venues set name_uz = 'Sinov', name_ru = 'Test-ru' where id = $1`, [venueId]);
  ownerA = await addOwner(pool, venueId, await createUser(pool, 'Owner A'));
  ownerB = await addOwner(pool, venueId, await createUser(pool, 'Owner B'));
});
after(() => db.end());

beforeEach(async () => {
  await pool.query('delete from notifications');
  await pool.query('delete from reliability_events');
  await pool.query('delete from bookings');
  await pool.query(`update profiles set muted_categories = '{}', hidden_from_search = false`);
  court = await addCourt(pool, venueId);
  ali = await createUser(pool, 'Ali');
  vali = await createUser(pool, 'Vali');
});

const one = async (sql, params) => (await pool.query(sql, params)).rows[0];
const rpc = (client, fn, args = []) =>
  client.query(`select public.${fn}(${args.map((_, i) => `$${i + 1}`).join(', ')}) as r`, args).then((r) => r.rows);

const book = async (user, start, { at: when = now } = {}) => {
  const held = await one(`select (app.hold_slots($1, $2, $3::timestamp[], $4)).id`, [user, court, [start], when]);
  await pool.query(`select app.confirm_booking($1, $2, null, null, $3)`, [user, held.id, when]);
  return held.id;
};

const reliability = (user, when = now) => one(`select app.reliability($1, $2) as r`, [user, when]).then((r) => r.r);

const event = (user, kind, ref = randomUUID(), when = now) =>
  pool.query(`select app.reliability_event($1, $2, $3, $4)`, [user, kind, ref, when]);

const notesOf = (user, kind) =>
  pool
    .query(`select * from notifications where user_id = $1 ${kind ? 'and kind = $2' : ''} order by created_at`, kind ? [user, kind] : [user])
    .then((r) => r.rows);

const mark = (owner, id, outcome, when) => pool.query(`select app.owner_mark_booking($1, $2, $3, $4)`, [owner, id, outcome, when]);

const walkIn = async () =>
  (
    await pool.query(`select (app.owner_create_walk_in($1, $2, $3::timestamp[], 'Guest', null, null, 'cash', $4)).id`, [
      ownerA,
      court,
      [ten],
      now,
    ])
  ).rows[0].id;

// --- notify ---------------------------------------------------------------

test('notify inserts a row; a muted category inserts nothing', async () => {
  await pool.query(`select app.notify($1, 'game_joined', 'games', '{"game_id":"x"}', $2)`, [ali, now]);
  const rows = await notesOf(ali);
  assert.equal(rows.length, 1);
  assert.equal(rows[0].kind, 'game_joined');
  assert.equal(rows[0].category, 'games');
  assert.deepEqual(rows[0].payload, { game_id: 'x' });
  assert.equal(rows[0].read_at, null);

  await pool.query(`update profiles set muted_categories = array['games'] where id = $1`, [ali]);
  await pool.query(`select app.notify($1, 'game_left', 'games', '{}', $2)`, [ali, now]);
  assert.equal((await notesOf(ali)).length, 1);
  await pool.query(`select app.notify($1, 'booking_confirmed', 'bookings', '{}', $2)`, [ali, now]);
  assert.equal((await notesOf(ali)).length, 2);
});

test('a player sees only their own notifications; clients cannot write', async () => {
  await pool.query(`select app.notify($1, 'game_joined', 'games', '{}', $2)`, [ali, now]);
  await pool.query(`select app.notify($1, 'game_left', 'games', '{}', $2)`, [vali, now]);
  const valiRow = (await notesOf(vali))[0];

  const table = await asUser(pool, ali, (c) => c.query('select * from notifications'));
  assert.deepEqual(
    table.rows.map((r) => r.kind),
    ['game_joined'],
  );

  const fn = await asUser(pool, ali, (c) => rpc(c, 'my_notifications'));
  assert.equal(fn.length, 1);
  assert.equal(fn[0].r.kind, 'game_joined');
  assert.equal(fn[0].r.read, false);
  assert.ok(fn[0].r.id && fn[0].r.created_at);

  await expectError(
    asUser(pool, ali, (c) => c.query(`insert into notifications (user_id, kind, category) values ($1, 'x', 'games')`, [ali])),
    '42501',
  );

  await asUser(pool, ali, (c) => rpc(c, 'mark_notifications_read', [[valiRow.id]]));
  assert.equal((await notesOf(vali))[0].read_at, null);
});

test('unread count drops to 0 after marking all read', async () => {
  await pool.query(`select app.notify($1, 'game_joined', 'games', '{}', $2)`, [ali, now]);
  await pool.query(`select app.notify($1, 'game_left', 'games', '{}', $2)`, [ali, now]);
  assert.equal((await asUser(pool, ali, (c) => rpc(c, 'unread_notification_count')))[0].r, 2);
  await asUser(pool, ali, (c) => rpc(c, 'mark_notifications_read', [null]));
  assert.equal((await asUser(pool, ali, (c) => rpc(c, 'unread_notification_count')))[0].r, 0);
});

test('my_notifications pages by p_before and respects the limit', async () => {
  for (let i = 0; i < 3; i++) {
    await pool.query(`select app.notify($1, 'game_joined', 'games', '{}', $2::timestamptz + $3 * interval '1 minute')`, [ali, now, i]);
  }
  const page = await asUser(pool, ali, (c) => rpc(c, 'my_notifications', [2, null]));
  assert.equal(page.length, 2);
  const older = await asUser(pool, ali, (c) => rpc(c, 'my_notifications', [50, page[1].r.created_at]));
  assert.equal(older.length, 1);
});

// --- reliability ----------------------------------------------------------

test('a new user scores 80 and is new', async () => {
  assert.deepEqual(await reliability(ali), { score: 80, badge: 'new' });
});

test('three paid events make a player reliable at 86', async () => {
  for (let i = 0; i < 3; i++) await event(ali, 'booking_paid');
  assert.deepEqual(await reliability(ali), { score: 86, badge: 'reliable' });
});

test('one no-show is limited at 60, two are blocked at 40', async () => {
  await event(ali, 'no_show');
  assert.deepEqual(await reliability(ali), { score: 60, badge: 'limited' });
  await event(ali, 'no_show');
  assert.deepEqual(await reliability(ali), { score: 40, badge: 'blocked' });
});

test('an event 91 days old does not count; 89 days does', async () => {
  await event(ali, 'no_show', randomUUID(), new Date(Date.parse(now) - 91 * 86400000).toISOString());
  assert.equal((await reliability(ali)).score, 80);
  await event(ali, 'no_show', randomUUID(), new Date(Date.parse(now) - 89 * 86400000).toISOString());
  assert.equal((await reliability(ali)).score, 60);
});

test('events are unique per user, kind and ref', async () => {
  const ref = randomUUID();
  await event(ali, 'no_show', ref);
  await event(ali, 'no_show', ref);
  assert.equal((await reliability(ali)).score, 60);
});

test('a blocked player cannot hold slots', async () => {
  await event(ali, 'no_show');
  await event(ali, 'no_show');
  assert.equal(
    await errorOf(pool.query(`select app.hold_slots($1, $2, $3::timestamp[], $4)`, [ali, court, [ten], now])),
    'reliability_too_low',
  );
});

test('a limited player may hold one upcoming booking, not two', async () => {
  assert.ok(await book(ali, ten));
  await event(ali, 'no_show');
  assert.equal(
    await errorOf(pool.query(`select app.hold_slots($1, $2, $3::timestamp[], $4)`, [ali, court, [eleven30], now])),
    'too_many_bookings',
  );
});

test('a limited player with no upcoming booking can still book one', async () => {
  await event(ali, 'no_show');
  assert.ok(await book(ali, ten));
});

test('a late cancellation records one late_cancel event; an early one none', async () => {
  const late = await book(ali, ten);
  await pool.query(`select app.cancel_booking($1, $2, $3)`, [ali, late, tashkent(monday, 7)]);
  const events = await pool.query(`select kind, delta, ref from reliability_events where user_id = $1`, [ali]);
  assert.equal(events.rows.length, 1);
  assert.equal(events.rows[0].kind, 'late_cancel');
  assert.equal(events.rows[0].delta, -5);
  assert.equal(events.rows[0].ref, late);
  assert.equal((await reliability(ali, tashkent(monday, 7))).score, 75);

  const early = await book(vali, eleven30);
  await pool.query(`select app.cancel_booking($1, $2, $3)`, [vali, early, tashkent(monday, 1)]);
  assert.equal((await pool.query(`select 1 from reliability_events where user_id = $1`, [vali])).rows.length, 0);
});

test('owner marks no-show, paid, no-show: events swap, never stack', async () => {
  const id = await book(ali, ten);
  const later = tashkent(monday, 13);
  await mark(ownerA, id, 'no_show', later);
  assert.equal((await reliability(ali, later)).score, 60);
  await mark(ownerA, id, 'paid', later);
  assert.equal((await reliability(ali, later)).score, 82);
  await mark(ownerA, id, 'no_show', later);
  assert.equal((await reliability(ali, later)).score, 60);
  await mark(ownerA, id, 'paid', later);
  await mark(ownerA, id, 'paid', later);
  assert.equal((await reliability(ali, later)).score, 82);
  assert.equal((await pool.query(`select 1 from reliability_events where user_id = $1`, [ali])).rows.length, 1);
});

test('a walk-in marked no-show creates no event', async () => {
  await mark(ownerA, await walkIn(), 'no_show', tashkent(monday, 13));
  assert.equal((await pool.query('select 1 from reliability_events')).rows.length, 0);
});

// --- booking hooks --------------------------------------------------------

test('owner cancelling an app booking notifies the player, with no reliability event', async () => {
  const id = await book(ali, ten);
  await pool.query(`select app.owner_cancel_booking($1, $2, $3)`, [ownerA, id, now]);
  const [note] = await notesOf(ali, 'booking_cancelled_by_venue');
  assert.ok(note);
  assert.equal(note.category, 'bookings');
  assert.equal(note.payload.booking_id, id);
  assert.deepEqual(note.payload.venue_name, { uz: 'Sinov', ru: 'Test-ru', en: 'Test venue' });
  assert.equal(note.payload.sport_id, 'padel');
  assert.equal(note.payload.starts_local, ten);
  assert.equal((await pool.query('select 1 from reliability_events')).rows.length, 0);
});

test('owner cancelling a walk-in notifies nobody', async () => {
  await pool.query(`select app.owner_cancel_booking($1, $2, $3)`, [ownerA, await walkIn(), now]);
  assert.equal((await pool.query('select 1 from notifications')).rows.length, 0);
});

test('confirming notifies the player and every owner', async () => {
  const id = await book(ali, ten);
  const [mine] = await notesOf(ali, 'booking_confirmed');
  assert.ok(mine);
  assert.equal(mine.payload.booking_id, id);
  assert.equal(mine.payload.venue_name.en, 'Test venue');
  for (const owner of [ownerA, ownerB]) {
    const [note] = await notesOf(owner, 'venue_new_booking');
    assert.ok(note, 'owner notified');
    assert.equal(note.category, 'venue');
    assert.equal(note.payload.venue_id, venueId);
    assert.equal(note.payload.booking_id, id);
    assert.equal(note.payload.actor_name, 'Ali');
    assert.deepEqual(note.payload.court_name, { uz: null, ru: null, en: 'Court' });
  }
});

test('player cancelling notifies the owners', async () => {
  const id = await book(ali, ten);
  await pool.query(`select app.cancel_booking($1, $2, $3)`, [ali, id, now]);
  for (const owner of [ownerA, ownerB]) {
    const [note] = await notesOf(owner, 'venue_booking_cancelled');
    assert.ok(note);
    assert.equal(note.payload.actor_name, 'Ali');
  }
});

test('send_reminders sends one reminder 1 h 50 m before, then none', async () => {
  const id = await book(ali, ten);
  assert.equal((await one(`select app.send_reminders($1) as n`, [tashkent(monday, 6)])).n, 0);
  const when = tashkent(monday, 8, 10);
  assert.equal((await one(`select app.send_reminders($1) as n`, [when])).n, 1);
  const notes = await notesOf(ali, 'booking_reminder');
  assert.equal(notes.length, 1);
  assert.equal(notes[0].payload.booking_id, id);
  assert.equal((await one(`select app.send_reminders($1) as n`, [when])).n, 0);
  assert.equal((await notesOf(ali, 'booking_reminder')).length, 1);
});

// --- settings and API surface --------------------------------------------

test('set_settings validates categories and my_settings reads them back', async () => {
  await expectError(asUser(pool, ali, (c) => rpc(c, 'set_settings', [['spam'], false])), 'invalid_argument');
  await asUser(pool, ali, (c) => rpc(c, 'set_settings', [['games', 'invites'], true]));
  const [row] = await asUser(pool, ali, (c) => rpc(c, 'my_settings'));
  assert.deepEqual(row.r.muted_categories.sort(), ['games', 'invites']);
  assert.equal(row.r.hidden_from_search, true);
  assert.deepEqual(row.r.reliability, { score: 80, badge: 'new' });
  const [rel] = await asUser(pool, ali, (c) => rpc(c, 'my_reliability'));
  assert.deepEqual(rel.r, { score: 80, badge: 'new' });
});

test('set_settings with an empty list unmutes everything; null leaves it', async () => {
  await asUser(pool, ali, (c) => rpc(c, 'set_settings', [['games'], null]));
  await asUser(pool, ali, (c) => rpc(c, 'set_settings', [null, null]));
  assert.deepEqual((await asUser(pool, ali, (c) => rpc(c, 'my_settings')))[0].r.muted_categories, ['games']);
  await asUser(pool, ali, (c) => rpc(c, 'set_settings', [[], null]));
  assert.deepEqual((await asUser(pool, ali, (c) => rpc(c, 'my_settings')))[0].r.muted_categories, []);
});

test('anon cannot execute the public functions; a player cannot call the app ones', async () => {
  const calls = [
    ['my_notifications', []],
    ['unread_notification_count', []],
    ['mark_notifications_read', [null]],
    ['my_settings', []],
    ['set_settings', [[], false]],
    ['my_reliability', []],
  ];
  for (const [fn, args] of calls) {
    await expectError(asAnon(pool, (c) => rpc(c, fn, args)), '42501');
  }
  await expectError(asUser(pool, ali, (c) => c.query(`select app.notify($1, 'x', 'games', '{}', now())`, [ali])), '42501');
  await expectError(asUser(pool, ali, (c) => c.query('select * from reliability_events')), '42501');
});

test('running and gym are seeded as non-bookable sports', async () => {
  const { rows } = await pool.query(`select id, bookable, name_uz, name_ru, name_en from sports where id in ('running','gym') order by id`);
  assert.equal(rows.length, 2);
  for (const r of rows) {
    assert.equal(r.bookable, false);
    assert.ok(r.name_uz && r.name_ru && r.name_en);
  }
});
