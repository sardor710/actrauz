// Port of app/test/domain/booking_engine_test.dart: the same cases, fixture
// and expected values, run against the database functions in the `app`
// schema (which take the acting player and the current time as arguments).

import assert from 'node:assert/strict';
import { after, before, beforeEach, test } from 'node:test';
import { createUser, errorOf, freshDb } from './helpers/db.mjs';
import { addCourt, addVenue, at, monday, tashkent } from './helpers/fixtures.mjs';

let db;
let pool;
let ali;
let vali;
let venueId;
let court;

// Sunday evening in Tashkent: every Monday slot is in the future.
const now = tashkent('2026-11-22', 20);

before(async () => {
  db = await freshDb('booking');
  pool = db.pool;
  ali = await createUser(pool, 'Ali');
  vali = await createUser(pool, 'Vali');
  venueId = await addVenue(pool);
});
after(() => db.end());

// A fresh court for every test, like the Dart setUp.
beforeEach(async () => {
  await pool.query('delete from bookings');
  court = await addCourt(pool, venueId, {
    rules: [{ weekdays: [1, 2, 3, 4, 5], from: 1080, to: 1380, price: 250000 }],
  });
});

const one = async (sql, params) => (await pool.query(sql, params)).rows[0];

const hold = (user, starts, { at: when = now, courtId = court } = {}) =>
  one(
    `select b.*, app.booking_json(b) as json from app.hold_slots($1, $2, $3::timestamp[], $4) b`,
    [user, courtId, starts, when],
  ).then((row) => ({ ...row.json, raw: row }));

const confirm = (user, id, { at: when = now, players = null, note = null } = {}) =>
  one(`select app.booking_json(b) as json from app.confirm_booking($1, $2, $3, $4, $5) b`, [user, id, players, note, when]).then(
    (row) => row.json,
  );

const cancel = (user, id, { at: when = now } = {}) =>
  one(`select app.booking_json(b) as json from app.cancel_booking($1, $2, $3) b`, [user, id, when]).then((row) => row.json);

const release = (user, id) => pool.query(`select app.release_hold($1, $2)`, [user, id]);

const stateOf = async (start, { user = null, at: when = now, courtId = court } = {}) => {
  const { rows } = await pool.query(`select * from app.court_availability($1, $2, $3::date, $4)`, [
    user,
    courtId,
    start.slice(0, 10),
    when,
  ]);
  const slot = rows.find((r) => r.starts_local === start);
  assert.ok(slot, `no slot at ${start}`);
  return slot.state;
};

const bookingsOf = async (user) =>
  (
    await pool.query(
      `select id from bookings where user_id = $1 and status not in ('held', 'released') order by lower(during) desc`,
      [user],
    )
  ).rows;

test('hold then confirm locks the summed price', async () => {
  // 17:30 is base price, 19:00 falls under the evening rule.
  const held = await hold(ali, [at(monday, 17, 30), at(monday, 19)]);
  assert.equal(held.status, 'held');
  assert.equal(held.total_price, 180000 + 250000);
  assert.equal(held.hold_expires_local, '2026-11-22T20:05:00');
  assert.equal(held.currency, 'UZS');

  const confirmed = await confirm(ali, held.id, { at: tashkent('2026-11-22', 20, 2), players: 4 });
  assert.equal(confirmed.status, 'confirmed');
  assert.equal(confirmed.payment_method, 'pay_at_venue');
  assert.equal(confirmed.payment_status, 'unpaid');
  assert.equal(confirmed.slot_count, 2);
  assert.equal(confirmed.players, 4);
  assert.equal(confirmed.starts_local, '2026-11-23T17:30:00');
  assert.equal(confirmed.ends_local, '2026-11-23T20:30:00');
  assert.equal(confirmed.hold_expires_local, null);
});

test('a second player cannot hold a held slot', async () => {
  const slot = at(monday, 7);
  await hold(ali, [slot]);
  assert.equal(await errorOf(hold(vali, [slot])), 'slot_taken');
  assert.equal(await stateOf(slot, { user: vali }), 'taken');
  assert.equal(await stateOf(slot, { user: ali }), 'mine');
});

test('overlap is caught when only part of the selection is taken', async () => {
  await hold(ali, [at(monday, 8, 30)]);
  assert.equal(await errorOf(hold(vali, [at(monday, 7), at(monday, 8, 30)])), 'slot_taken');
});

test('a confirmed slot stays taken for everyone', async () => {
  const slot = at(monday, 7);
  await confirm(ali, (await hold(ali, [slot])).id);
  assert.equal(await stateOf(slot, { user: ali }), 'taken');
  assert.equal(await errorOf(hold(vali, [slot])), 'slot_taken');
});

test('an expired hold cannot be confirmed and frees the slot', async () => {
  const slot = at(monday, 7);
  const held = await hold(ali, [slot]);
  const later = tashkent('2026-11-22', 20, 5);
  assert.equal(await stateOf(slot, { user: vali, at: later }), 'free');
  assert.equal(await errorOf(confirm(ali, held.id, { at: later })), 'hold_expired');
  assert.equal((await hold(vali, [slot], { at: later })).status, 'held');
  // Once someone else has taken the slot it is still "expired", not "unknown".
  assert.equal(await errorOf(confirm(ali, held.id, { at: later })), 'hold_expired');
});

test('release frees a held slot', async () => {
  const slot = at(monday, 7);
  await release(ali, (await hold(ali, [slot])).id);
  assert.equal(await stateOf(slot, { user: vali }), 'free');
});

test("a new hold replaces the same player's previous hold", async () => {
  const first = at(monday, 7);
  await hold(ali, [first]);
  await hold(ali, [at(monday, 10)]);
  assert.equal(await stateOf(first, { user: vali }), 'free');
});

test('non-adjacent slots are refused', async () => {
  assert.equal(await errorOf(hold(ali, [at(monday, 7), at(monday, 10)])), 'not_contiguous');
});

test('slots may be passed in any order', async () => {
  const held = await hold(ali, [at(monday, 8, 30), at(monday, 7)]);
  assert.equal(held.starts_local, '2026-11-23T07:00:00');
  assert.equal(held.slot_count, 2);
});

test('an empty selection is refused', async () => {
  assert.equal(await errorOf(hold(ali, [])), 'empty_selection');
});

test("a time that is not one of the court's slots is refused", async () => {
  assert.equal(await errorOf(hold(ali, [at(monday, 7, 15)])), 'not_found');
});

test('past slots cannot be held and show as past', async () => {
  const midday = tashkent(monday, 12);
  const slot = at(monday, 7);
  assert.equal(await errorOf(hold(ali, [slot], { at: midday })), 'in_past');
  assert.equal(await stateOf(slot, { at: midday }), 'past');
  // A slot that has already started is past too.
  assert.equal(await stateOf(at(monday, 11, 30), { at: midday }), 'past');
});

test('more than 14 days ahead is refused, 14 is allowed', async () => {
  assert.equal((await hold(ali, [at('2026-12-06', 8, 30)])).status, 'held');
  assert.equal(await errorOf(hold(ali, [at('2026-12-07', 7)])), 'too_far_ahead');
});

test('a fourth upcoming booking is refused', async () => {
  for (const hour of [7, 10, 13]) {
    await confirm(ali, (await hold(ali, [at(monday, hour)])).id);
  }
  assert.equal(await errorOf(hold(ali, [at(monday, 16)])), 'too_many_bookings');
  // Another player is unaffected.
  assert.equal((await hold(vali, [at(monday, 16)])).status, 'held');
});

test('cancelling early is free and reopens the slot', async () => {
  const slot = at(monday, 7);
  const booking = await confirm(ali, (await hold(ali, [slot])).id);
  const cancelled = await cancel(ali, booking.id, { at: tashkent(monday, 0) });
  assert.equal(cancelled.status, 'cancelled_by_player');
  assert.equal(cancelled.late_cancellation, false);
  assert.equal(await stateOf(slot, { user: vali }), 'free');
});

test('cancelling inside 6 hours is flagged late', async () => {
  const booking = await confirm(ali, (await hold(ali, [at(monday, 7)])).id);
  const cancelled = await cancel(ali, booking.id, { at: tashkent(monday, 5) });
  assert.equal(cancelled.late_cancellation, true);
});

test('cancelling exactly 6 hours before is still free', async () => {
  const booking = await confirm(ali, (await hold(ali, [at(monday, 7)])).id);
  assert.equal((await cancel(ali, booking.id, { at: tashkent(monday, 1) })).late_cancellation, false);
});

test('a started or already cancelled booking cannot be cancelled', async () => {
  const booking = await confirm(ali, (await hold(ali, [at(monday, 7)])).id);
  assert.equal(await errorOf(cancel(ali, booking.id, { at: tashkent(monday, 7) })), 'not_cancellable');
  await cancel(ali, booking.id);
  assert.equal(await errorOf(cancel(ali, booking.id)), 'not_cancellable');
  assert.equal(await errorOf(cancel(ali, '00000000-0000-0000-0000-000000000000')), 'not_found');
});

test('a later price change does not touch an existing booking', async () => {
  const booking = await confirm(ali, (await hold(ali, [at(monday, 7)])).id);
  await pool.query('update courts set base_price = 999000 where id = $1', [court]);
  assert.equal((await one('select total_price from bookings where id = $1', [booking.id])).total_price, 180000);
  assert.equal((await hold(vali, [at(monday, 10)])).total_price, 999000);
});

test('bookingsOf lists confirmed and cancelled bookings, not holds', async () => {
  await confirm(ali, (await hold(ali, [at(monday, 7)])).id);
  await hold(ali, [at(monday, 10)]);
  assert.equal((await bookingsOf(ali)).length, 1);
  assert.equal((await bookingsOf(vali)).length, 0);
});

// ---- Beyond the Dart cases: things only the database version can get wrong ----

test('a court closed on Mondays has no Monday slots and cannot be held', async () => {
  const closed = await addCourt(pool, venueId, { slot: 60, basePrice: 200000, override: { 1: null } });
  const { rows } = await pool.query(`select * from app.court_slots($1, $2::date)`, [closed, monday]);
  assert.equal(rows.length, 0);
  assert.equal(await errorOf(hold(ali, [at(monday, 7)], { courtId: closed })), 'not_found');
  // Tuesday follows the venue's hours: 07:00-23:00 in 60-minute slots.
  const tuesday = await pool.query(`select * from app.court_slots($1, '2026-11-24'::date)`, [closed]);
  assert.equal(tuesday.rows.length, 16);
});

test('07:00-23:00 with 90-minute slots gives 07:00 ... 20:30, back to back', async () => {
  const { rows } = await pool.query(`select * from app.court_slots($1, $2::date)`, [court, monday]);
  assert.equal(rows.length, 10);
  assert.equal(rows[0].starts_local, '2026-11-23T07:00:00');
  assert.equal(rows.at(-1).starts_local, '2026-11-23T20:30:00');
  assert.equal(rows.at(-1).ends_local, '2026-11-23T22:00:00');
  for (let i = 1; i < rows.length; i++) assert.equal(rows[i].starts_local, rows[i - 1].ends_local);
  // Rule start is inclusive, end exclusive: 17:30 is base price, 19:00 and 20:30 are evening.
  assert.deepEqual(
    rows.slice(-3).map((r) => r.price),
    [180000, 250000, 250000],
  );
});

test('hours shorter than a slot, or closing before opening, give no slots', async () => {
  const short = await addCourt(pool, venueId, { override: { 1: [7 * 60, 8 * 60] } });
  const backwards = await addCourt(pool, venueId, { override: { 1: [20 * 60, 8 * 60] } });
  for (const id of [short, backwards]) {
    assert.equal((await pool.query(`select * from app.court_slots($1, $2::date)`, [id, monday])).rows.length, 0);
  }
});

test('wall-clock times survive a city with a different UTC offset', async () => {
  const farVenue = await addVenue(pool, { cityId: 'farcity', name: 'Far' });
  const farCourt = await addCourt(pool, farVenue);
  // 20:00 in Tashkent (UTC+5) is 21:00 in a UTC+6 city.
  const held = await hold(ali, [at(monday, 7)], { courtId: farCourt });
  assert.equal(held.starts_local, '2026-11-23T07:00:00');
  assert.equal(held.ends_local, '2026-11-23T08:30:00');
  assert.equal(held.hold_expires_local, '2026-11-22T21:05:00');
  assert.equal(held.currency, 'KZT');
  const stored = await one(`select lower(during) at time zone 'UTC' as utc from bookings where id = $1`, [held.id]);
  assert.equal(stored.utc, '2026-11-23T01:00:00');
});

test('the same slot twice in one selection is refused', async () => {
  assert.equal(await errorOf(hold(ali, [at(monday, 7), at(monday, 7)])), 'not_contiguous');
});

test("a player cannot confirm, cancel or release someone else's booking", async () => {
  const held = await hold(ali, [at(monday, 7)]);
  assert.equal(await errorOf(confirm(vali, held.id)), 'not_found');
  await release(vali, held.id);
  assert.equal(await stateOf(at(monday, 7), { user: ali }), 'mine');
  const booking = await confirm(ali, held.id);
  assert.equal(await errorOf(cancel(vali, booking.id)), 'not_found');
});

test('the scheduled job releases only expired holds', async () => {
  await hold(ali, [at(monday, 7)]);
  await hold(vali, [at(monday, 10)], { at: tashkent('2026-11-22', 20, 3) });
  const released = await one(`select app.release_expired_holds($1) as n`, [tashkent('2026-11-22', 20, 6)]);
  assert.equal(released.n, 1);
  const { rows } = await pool.query(`select user_id, status from bookings order by created_at`);
  assert.deepEqual(
    rows.map((r) => r.status),
    ['released', 'held'],
  );
});
