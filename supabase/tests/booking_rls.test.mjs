// What a signed-in player can and cannot do through the API: only the
// public functions write bookings, and players see only their own.

import assert from 'node:assert/strict';
import { after, before, test } from 'node:test';
import { asAnon, asUser, createUser, errorOf, expectError, freshDb } from './helpers/db.mjs';
import { addCourt, addVenue } from './helpers/fixtures.mjs';

let db;
let pool;
let ali;
let vali;
let owner;
let venueId;
let otherVenueId;
let court;
let otherCourt;
let slot;
let nextSlot;
let bookingId;

// The public functions use the real clock, so pick slots relative to today:
// a 24-hour venue, a slot three days ahead at 10:00 venue time.
before(async () => {
  db = await freshDb('rls');
  pool = db.pool;
  ali = await createUser(pool, 'Ali');
  vali = await createUser(pool, 'Vali');
  owner = await createUser(pool, 'Owner');
  venueId = await addVenue(pool, { open: 0, close: 24 * 60 });
  otherVenueId = await addVenue(pool, { open: 0, close: 24 * 60, name: 'Other' });
  court = await addCourt(pool, venueId, { slot: 60 });
  otherCourt = await addCourt(pool, otherVenueId, { slot: 60 });
  await pool.query(`insert into venue_owners (venue_id, user_id) values ($1, $2)`, [venueId, owner]);
  await pool.query(`insert into profile_contacts (user_id, phone) values ($1, '+998901111111')`, [ali]);

  const { rows } = await pool.query(
    `select to_char(d, 'YYYY-MM-DD"T"10:00:00') as a, to_char(d, 'YYYY-MM-DD"T"11:00:00') as b
     from (select (app.to_local(now(), 300))::date + 3 as d) x`,
  );
  slot = rows[0].a;
  nextSlot = rows[0].b;
});
after(() => db.end());

const rpc = (client, name, args) => client.query(`select public.${name}(${args.map((_, i) => `$${i + 1}`).join(', ')}) as r`, args);

test('a signed-in player holds and confirms through the public functions', async () => {
  const held = await asUser(pool, ali, async (c) => (await rpc(c, 'hold_slots', [court, [slot]])).rows[0].r);
  assert.equal(held.status, 'held');
  assert.equal(held.user_id, ali);
  assert.equal(held.starts_local, slot);

  const confirmed = await asUser(pool, ali, async (c) => (await rpc(c, 'confirm_booking', [held.id, 4, 'Bring balls'])).rows[0].r);
  assert.equal(confirmed.status, 'confirmed');
  assert.equal(confirmed.players, 4);
  assert.equal(confirmed.note, 'Bring balls');
  bookingId = confirmed.id;

  const mine = await asUser(pool, ali, async (c) => (await c.query('select public.my_bookings() as r')).rows.map((r) => r.r));
  assert.deepEqual(
    mine.map((b) => b.id),
    [bookingId],
  );
});

test('another player sees none of it, only that the slot is taken', async () => {
  await asUser(pool, vali, async (c) => {
    assert.equal((await c.query('select * from bookings')).rows.length, 0);
    assert.equal((await c.query('select public.my_bookings() as r')).rows.length, 0);
    const day = await c.query('select * from public.court_availability($1, $2::date)', [court, slot.slice(0, 10)]);
    assert.equal(day.rows.find((r) => r.starts_local === slot).state, 'taken');
    assert.equal(day.rows.find((r) => r.starts_local === nextSlot).state, 'free');
  });
  assert.equal(await errorOf(asUser(pool, vali, (c) => rpc(c, 'hold_slots', [court, [slot]]))), 'slot_taken');
});

test("a player's own row is visible to them", async () => {
  const rows = await asUser(pool, ali, async (c) => (await c.query('select id, status from bookings')).rows);
  assert.deepEqual(rows, [{ id: bookingId, status: 'confirmed' }]);
});

test('nobody can write the bookings table directly', async () => {
  const insert = (c) =>
    c.query(
      `insert into bookings (user_id, venue_id, court_id, during, utc_offset_minutes, slot_count, total_price, currency, status)
       values ($1, $2, $3, tstzrange(now() + interval '5 days', now() + interval '5 days 1 hour'), 300, 1, 0, 'UZS', 'confirmed')`,
      [ali, venueId, court],
    );
  await expectError(asUser(pool, ali, insert), '42501');
  await expectError(
    asUser(pool, ali, (c) => c.query(`update bookings set total_price = 1 where id = $1`, [bookingId])),
    '42501',
  );
  await expectError(
    asUser(pool, ali, (c) => c.query(`update bookings set status = 'paid' where id = $1`, [bookingId])),
    '42501',
  );
  await expectError(
    asUser(pool, ali, (c) => c.query(`delete from bookings where id = $1`, [bookingId])),
    '42501',
  );
  const { rows } = await pool.query('select total_price, status from bookings where id = $1', [bookingId]);
  assert.deepEqual(rows[0], { total_price: 180000, status: 'confirmed' });
});

test('the rule functions in the app schema are not callable through the API', async () => {
  await expectError(
    asUser(pool, vali, (c) => c.query(`select app.cancel_booking($1, $2, now())`, [ali, bookingId])),
    '42501',
  );
  await expectError(
    asUser(pool, vali, (c) => c.query(`select app.hold_slots($1, $2, $3::timestamp[], now())`, [ali, court, [nextSlot]])),
    '42501',
  );
});

test('a visitor who is not signed in cannot book', async () => {
  await expectError(
    asAnon(pool, (c) => rpc(c, 'hold_slots', [court, [nextSlot]])),
    '42501',
  );
  await expectError(
    asAnon(pool, (c) => c.query('select public.my_bookings()')),
    '42501',
  );
  await expectError(
    asAnon(pool, (c) => c.query('select * from bookings')),
    '42501',
  );
  // Browsing free times is allowed without an account.
  const day = await asAnon(pool, async (c) =>
    (await c.query('select * from public.court_availability($1, $2::date)', [court, slot.slice(0, 10)])).rows,
  );
  assert.equal(day.find((r) => r.starts_local === slot).state, 'taken');
});

test("a player cannot confirm, cancel or release another player's booking", async () => {
  const held = await asUser(pool, vali, async (c) => (await rpc(c, 'hold_slots', [court, [nextSlot]])).rows[0].r);
  assert.equal(await errorOf(asUser(pool, ali, (c) => rpc(c, 'confirm_booking', [held.id, null, null]))), 'not_found');
  await asUser(pool, ali, (c) => rpc(c, 'release_hold', [held.id]));
  assert.equal((await pool.query('select status from bookings where id = $1', [held.id])).rows[0].status, 'held');
  assert.equal(await errorOf(asUser(pool, vali, (c) => rpc(c, 'cancel_booking', [bookingId]))), 'not_found');
  await asUser(pool, vali, (c) => rpc(c, 'release_hold', [held.id]));
});

test('a venue owner sees bookings at their venue only, and no phone numbers', async () => {
  const elsewhere = await asUser(pool, vali, async (c) => (await rpc(c, 'hold_slots', [otherCourt, [slot]])).rows[0].r);
  await asUser(pool, vali, (c) => rpc(c, 'confirm_booking', [elsewhere.id, null, null]));

  await asUser(pool, owner, async (c) => {
    const rows = (await c.query('select id, venue_id, status from bookings')).rows;
    assert.ok(rows.length > 0);
    assert.ok(rows.every((r) => r.venue_id === venueId));
    assert.deepEqual(
      rows.filter((r) => r.status === 'confirmed').map((r) => r.id),
      [bookingId],
    );
    assert.equal((await c.query('select * from profile_contacts')).rows.length, 0);
  });
});

test('the player cancels through the public function', async () => {
  const cancelled = await asUser(pool, ali, async (c) => (await rpc(c, 'cancel_booking', [bookingId])).rows[0].r);
  assert.equal(cancelled.status, 'cancelled_by_player');
  assert.equal(cancelled.late_cancellation, false);
  const day = await asUser(pool, vali, async (c) =>
    (await c.query('select * from public.court_availability($1, $2::date)', [court, slot.slice(0, 10)])).rows,
  );
  assert.equal(day.find((r) => r.starts_local === slot).state, 'free');
});
