// Venue owners run their calendar (Milestone 3a): walk-ins, blocks,
// cancelling and marking bookings, the audit log, and the scheduled job that
// moves finished bookings along. Like booking.test.mjs, most cases call the
// `app` functions directly with the acting user and a fixed clock; the last
// tests go through the `public` wrappers as the API would.

import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { after, before, beforeEach, test } from 'node:test';
import { asAnon, asUser, createUser, errorOf, expectError, freshDb } from './helpers/db.mjs';
import { addAdmin, addCourt, addOwner, addPhone, addVenue, at, monday, tashkent } from './helpers/fixtures.mjs';

let db;
let pool;
let owner; // owns venueId
let otherOwner; // owns otherVenueId only
let admin;
let ali; // a player with an account phone
let vali; // a player with no role
let venueId;
let otherVenueId;
let inactiveVenueId;
let court;
let otherCourt;

// Sunday evening in Tashkent: every Monday slot is in the future.
const now = tashkent('2026-11-22', 20);
const aliPhone = '+998901111111';

before(async () => {
  db = await freshDb('owner');
  pool = db.pool;
  venueId = await addVenue(pool);
  otherVenueId = await addVenue(pool, { name: 'Other venue' });
  inactiveVenueId = await addVenue(pool, { name: 'Closed venue' });
  await pool.query('update venues set active = false where id = $1', [inactiveVenueId]);
  owner = await addOwner(pool, venueId, await createUser(pool, 'Owner'));
  otherOwner = await addOwner(pool, otherVenueId, await createUser(pool, 'Other owner'));
  admin = await addAdmin(pool, await createUser(pool, 'Admin'));
  ali = await addPhone(pool, await createUser(pool, 'Ali'), aliPhone);
  vali = await createUser(pool, 'Vali');
});
after(() => db.end());

// A fresh court for every test, with the evening rule from booking.test.mjs:
// 17:30 is base price (180 000), 19:00 and 20:30 are 250 000.
beforeEach(async () => {
  await pool.query('delete from audit_log');
  await pool.query('delete from bookings');
  court = await addCourt(pool, venueId, {
    rules: [{ weekdays: [1, 2, 3, 4, 5], from: 1080, to: 1380, price: 250000 }],
  });
  otherCourt = await addCourt(pool, otherVenueId);
});

const one = async (sql, params) => (await pool.query(sql, params)).rows[0];

const ownerJson = (call, params) =>
  one(`select app.owner_booking_json(b) as json from ${call} b`, params).then((row) => row.json);

const walkIn = (
  user,
  starts,
  { name = 'Guest', phone = null, players = null, payment = 'cash', at: when = now, courtId = court } = {},
) =>
  ownerJson(`app.owner_create_walk_in($1, $2, $3::timestamp[], $4, $5, $6, $7, $8)`, [
    user,
    courtId,
    starts,
    name,
    phone,
    players,
    payment,
    when,
  ]);

const block = (user, starts, { reason = null, at: when = now, courtId = court } = {}) =>
  ownerJson(`app.owner_block_slots($1, $2, $3::timestamp[], $4, $5)`, [user, courtId, starts, reason, when]);

const cancelByVenue = (user, id, { at: when = now } = {}) => ownerJson(`app.owner_cancel_booking($1, $2, $3)`, [user, id, when]);

const mark = (user, id, outcome, { at: when = now } = {}) =>
  ownerJson(`app.owner_mark_booking($1, $2, $3, $4)`, [user, id, outcome, when]);

const calendar = (user, courtId, from, days, { at: when = now } = {}) =>
  one(`select app.owner_calendar($1, $2, $3::date, $4, $5) as c`, [user, courtId, from, days, when]).then((row) => row.c);

const myVenues = (user) => one(`select to_jsonb(app.my_venue_ids($1)) as ids`, [user]).then((row) => row.ids);

// A player's app booking: hold, then confirm.
const book = async (user, starts, { courtId = court, at: when = now } = {}) => {
  const held = await one(`select (app.hold_slots($1, $2, $3::timestamp[], $4)).id`, [user, courtId, starts, when]);
  await pool.query(`select app.confirm_booking($1, $2, null, null, $3)`, [user, held.id, when]);
  return held.id;
};

const playerHold = (user, starts, { courtId = court, at: when = now } = {}) =>
  one(`select (app.hold_slots($1, $2, $3::timestamp[], $4)).id`, [user, courtId, starts, when]).then((r) => r.id);

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

const linkedUser = async (id) => (await one(`select user_id from bookings where id = $1`, [id])).user_id;

const statusOf = async (id) => (await one(`select status, payment_status from bookings where id = $1`, [id]));

const auditRows = async () =>
  (await pool.query(`select actor_id, action, entity, entity_id, before, after, created_at from audit_log order by id`)).rows;

// Everything an owner function could change.
const snapshot = async () => ({
  bookings: (await pool.query(`select * from bookings order by id`)).rows,
  audit: (await pool.query(`select count(*)::int as n from audit_log`)).rows[0].n,
});

// ---------------------------------------------------------------------------
// Who manages what
// ---------------------------------------------------------------------------

test('my_venue_ids: an owner gets their venues, an admin every active venue, a player none', async () => {
  assert.deepEqual(await myVenues(owner), [venueId]);
  assert.deepEqual(await myVenues(otherOwner), [otherVenueId]);
  const all = await myVenues(admin);
  assert.ok(all.includes(venueId) && all.includes(otherVenueId));
  assert.ok(!all.includes(inactiveVenueId));
  assert.deepEqual(await myVenues(vali), []);
  assert.deepEqual(await myVenues(null), []);
});

test('a user who does not manage the venue is refused everywhere; nothing changes, nothing is logged', async () => {
  const booking = await walkIn(owner, [at(monday, 7)]);
  const ended = tashkent(monday, 9);
  await pool.query('delete from audit_log');
  for (const user of [vali, otherOwner, null]) {
    const before = await snapshot();
    assert.equal(await errorOf(calendar(user, court, monday, 7)), 'not_allowed');
    assert.equal(await errorOf(walkIn(user, [at(monday, 10)])), 'not_allowed');
    assert.equal(await errorOf(block(user, [at(monday, 10)])), 'not_allowed');
    assert.equal(await errorOf(cancelByVenue(user, booking.id)), 'not_allowed');
    assert.equal(await errorOf(mark(user, booking.id, 'paid', { at: ended })), 'not_allowed');
    assert.equal(await errorOf(mark(user, booking.id, 'no_show', { at: ended })), 'not_allowed');
    // The role check comes before every other check.
    assert.equal(await errorOf(walkIn(user, [], { name: ' ' })), 'not_allowed');
    assert.equal(await errorOf(walkIn(user, [at(monday, 7, 15)], { payment: 'bitcoin' })), 'not_allowed');
    assert.equal(await errorOf(block(user, [at('2026-12-25', 7)])), 'not_allowed');
    assert.equal(await errorOf(calendar(user, court, monday, 0)), 'not_allowed');
    assert.equal(await errorOf(mark(user, booking.id, 'paid')), 'not_allowed');
    assert.equal(await errorOf(mark(user, booking.id, 'whatever')), 'not_allowed');
    // Unknown ids do not reveal whether they exist.
    assert.equal(await errorOf(walkIn(user, [at(monday, 10)], { courtId: randomUUID() })), 'not_allowed');
    assert.equal(await errorOf(calendar(user, randomUUID(), monday, 7)), 'not_allowed');
    assert.equal(await errorOf(cancelByVenue(user, randomUUID())), 'not_allowed');
    assert.deepEqual(await snapshot(), before);
  }
  assert.equal((await auditRows()).length, 0);
});

test('an owner of one venue cannot touch another venue they do not own', async () => {
  const theirs = await walkIn(otherOwner, [at(monday, 7)], { courtId: otherCourt });
  assert.equal(await errorOf(cancelByVenue(owner, theirs.id)), 'not_allowed');
  assert.equal(await errorOf(walkIn(owner, [at(monday, 10)], { courtId: otherCourt })), 'not_allowed');
  assert.equal((await statusOf(theirs.id)).status, 'confirmed');
});

test('an admin acts on any venue', async () => {
  const w = await walkIn(admin, [at(monday, 7)], { courtId: otherCourt, name: 'Admin guest' });
  assert.equal(w.venue_id, otherVenueId);
  const b = await block(admin, [at(monday, 10)], { courtId: otherCourt });
  assert.equal(b.source, 'block');
  const cal = await calendar(admin, otherCourt, monday, 1);
  assert.equal(cal.slots.find((s) => s.starts_local === at(monday, 7)).state, 'booked');
  assert.equal((await mark(admin, w.id, 'paid', { at: tashkent(monday, 8) })).status, 'paid');
  assert.equal((await cancelByVenue(admin, b.id)).status, 'cancelled_by_venue');
  // An admin is told when something really is missing.
  assert.equal(await errorOf(walkIn(admin, [at(monday, 10)], { courtId: randomUUID() })), 'not_found');
  assert.equal(await errorOf(calendar(admin, randomUUID(), monday, 7)), 'not_found');
  assert.equal(await errorOf(cancelByVenue(admin, randomUUID())), 'not_found');
  assert.equal(await errorOf(mark(admin, randomUUID(), 'paid')), 'not_found');
});

// ---------------------------------------------------------------------------
// Walk-ins and blocks
// ---------------------------------------------------------------------------

test('a walk-in is confirmed at once with the summed price and the guest details', async () => {
  const w = await walkIn(owner, [at(monday, 19), at(monday, 17, 30)], {
    name: '  Bek  ',
    phone: '+998907777777',
    players: 4,
    payment: 'transfer',
  });
  assert.equal(w.status, 'confirmed');
  assert.equal(w.source, 'walk_in');
  assert.equal(w.total_price, 180000 + 250000);
  assert.equal(w.slot_count, 2);
  assert.equal(w.starts_local, '2026-11-23T17:30:00');
  assert.equal(w.ends_local, '2026-11-23T20:30:00');
  assert.equal(w.currency, 'UZS');
  assert.equal(w.user_id, null);
  assert.equal(w.venue_id, venueId);
  assert.equal(w.court_id, court);
  assert.equal(w.customer_name, 'Bek');
  assert.equal(w.customer_phone, '+998907777777');
  assert.equal(w.players, 4);
  assert.equal(w.walk_in_payment, 'transfer');
  assert.equal(w.payment_method, 'pay_at_venue');
  assert.equal(w.payment_status, 'unpaid');
  assert.equal(w.reason, null);
  assert.equal(w.hold_expires_local, null);
  assert.equal(w.late_cancellation, false);
  for (const payment of ['cash', 'card']) {
    assert.equal((await walkIn(owner, [at(monday, payment === 'cash' ? 7 : 10)], { payment })).walk_in_payment, payment);
  }
});

test('a walk-in whose phone matches an account is linked to it', async () => {
  const w = await walkIn(owner, [at(monday, 7)], { name: 'Ali at the desk', phone: ' +998 (90) 111-11-11 ' });
  assert.equal(await linkedUser(w.id), ali);
  // The owner is not told whether the phone has an account.
  assert.equal(w.user_id, null);
  assert.equal(w.customer_phone, aliPhone);
  // The guest's name as the owner typed it.
  assert.equal(w.customer_name, 'Ali at the desk');
  const unknown = await walkIn(owner, [at(monday, 10)], { phone: '+998905555555' });
  assert.equal(await linkedUser(unknown.id), null);
  const none = await walkIn(owner, [at(monday, 13)], { phone: '  ' });
  assert.equal(await linkedUser(none.id), null);
  assert.equal(none.customer_phone, null);
});

test("linked walk-ins do not count toward the player's three upcoming app bookings", async () => {
  // Vali has no phone: three app bookings, the fourth is refused as before.
  for (const hour of [7, 10, 13]) await book(vali, [at(monday, hour)]);
  assert.equal(await errorOf(playerHold(vali, [at(monday, 16)])), 'too_many_bookings');

  // Ali: two app bookings plus two walk-ins linked by phone, then a third app booking.
  const aliCourt = await addCourt(pool, venueId);
  for (const hour of [7, 10]) await book(ali, [at(monday, hour)], { courtId: aliCourt });
  for (const hour of [13, 16]) {
    assert.equal(await linkedUser((await walkIn(owner, [at(monday, hour)], { courtId: aliCourt, phone: aliPhone })).id), ali);
  }
  const third = await book(ali, [at(monday, 19)], { courtId: aliCourt });
  assert.equal((await statusOf(third)).status, 'confirmed');
  // That third app booking reaches the cap.
  assert.equal(await errorOf(playerHold(ali, [at('2026-11-24', 7)], { courtId: aliCourt })), 'too_many_bookings');
});

test('a player sees a linked walk-in among their bookings but cannot cancel it', async () => {
  const w = await walkIn(owner, [at(monday, 7)], { phone: aliPhone });
  const mine = await asUser(pool, ali, async (c) => (await c.query('select public.my_bookings() as r')).rows.map((r) => r.r));
  assert.deepEqual(
    mine.map((b) => b.id),
    [w.id],
  );
  assert.equal(
    await errorOf(one(`select app.cancel_booking($1, $2, $3)`, [ali, w.id, now])),
    'not_cancellable',
  );
  assert.equal((await statusOf(w.id)).status, 'confirmed');
  // Their own app bookings cancel as before.
  const own = await book(ali, [at(monday, 10)]);
  assert.equal((await one(`select (app.cancel_booking($1, $2, $3)).status`, [ali, own, now])).status, 'cancelled_by_player');
});

test('owner input limits are refused with invalid_argument', async () => {
  const ok = await walkIn(owner, [at(monday, 7)], { name: 'N'.repeat(80), players: 100, phone: '(998) 90-111 2233' });
  assert.equal(ok.customer_phone, '998901112233');
  assert.equal(await errorOf(walkIn(owner, [at(monday, 10)], { name: 'N'.repeat(81) })), 'invalid_argument');
  assert.equal(await errorOf(walkIn(owner, [at(monday, 10)], { players: 101 })), 'invalid_argument');
  for (const phone of ['12345', '+1234567890123456', '+99890abc1111', '++998901111111', '+998.90.111.11.11']) {
    assert.equal(await errorOf(walkIn(owner, [at(monday, 10)], { phone })), 'invalid_argument', phone);
  }
  assert.equal((await block(owner, [at(monday, 10)], { reason: 'R'.repeat(200) })).reason.length, 200);
  assert.equal(await errorOf(block(owner, [at(monday, 13)], { reason: 'R'.repeat(201) })), 'invalid_argument');

  const allDay = await addCourt(pool, venueId, { slot: 60, override: { 1: [0, 24 * 60] } });
  const day = Array.from({ length: 24 }, (_, h) => at(monday, h));
  // Sunday 20:00 Tashkent: all 24 Monday slots are ahead.
  assert.equal((await block(owner, day, { courtId: allDay })).slot_count, 24);
  const tooMany = Array.from({ length: 25 }, () => at(monday, 7));
  assert.equal(await errorOf(block(owner, tooMany, { courtId: allDay })), 'invalid_argument');
  assert.equal(await errorOf(walkIn(owner, tooMany, { courtId: allDay })), 'invalid_argument');
});

test('a walk-in needs a name', async () => {
  for (const name of [null, '', '   ']) {
    assert.equal(await errorOf(walkIn(owner, [at(monday, 7)], { name })), 'name_required');
  }
  assert.equal((await snapshot()).bookings.length, 0);
});

test('a walk-in needs a payment method of cash, card or transfer', async () => {
  for (const payment of [null, '', 'bitcoin', 'pay_at_venue']) {
    assert.equal(await errorOf(walkIn(owner, [at(monday, 7)], { payment })), 'invalid_argument');
  }
  assert.equal(await errorOf(walkIn(owner, [at(monday, 7)], { players: 0 })), 'invalid_argument');
});

test('a block is confirmed, free, and carries its reason', async () => {
  const b = await block(owner, [at(monday, 10), at(monday, 11, 30)], { reason: ' Repair ' });
  assert.equal(b.status, 'confirmed');
  assert.equal(b.source, 'block');
  assert.equal(b.total_price, 0);
  assert.equal(b.slot_count, 2);
  assert.equal(b.user_id, null);
  assert.equal(b.reason, 'Repair');
  assert.equal(b.customer_name, null);
  assert.equal(b.customer_phone, null);
  assert.equal(b.walk_in_payment, null);
  assert.equal((await block(owner, [at(monday, 13)])).reason, null);
});

for (const [label, create] of [
  ['walk-in', walkIn],
  ['block', block],
]) {
  test(`${label}: same slot checks as a player hold`, async () => {
    assert.equal(await errorOf(create(owner, [])), 'empty_selection');
    assert.equal(await errorOf(create(owner, [at(monday, 7, 15)])), 'not_found');
    assert.equal(await errorOf(create(owner, [at(monday, 7), at(monday, 10)])), 'not_contiguous');
    assert.equal(await errorOf(create(owner, [at(monday, 7), at(monday, 7)])), 'not_contiguous');
    assert.equal(await errorOf(create(owner, [at('2026-12-07', 7)])), 'too_far_ahead');
    assert.equal((await create(owner, [at('2026-12-06', 8, 30)])).status, 'confirmed');
    // A closed court has no slots.
    const closed = await addCourt(pool, venueId, { override: { 1: null } });
    assert.equal(await errorOf(create(owner, [at(monday, 7)], { courtId: closed })), 'not_found');
  });

  test(`${label}: allowed while the first selected slot has not ended`, async () => {
    // At 09:00 the 07:00 slot has ended, 08:30 is under way.
    const nine = tashkent(monday, 9);
    assert.equal(await errorOf(create(owner, [at(monday, 7)], { at: nine })), 'in_past');
    assert.equal(await errorOf(create(owner, [at(monday, 7)], { at: tashkent(monday, 8, 30) })), 'in_past');
    // An ended slot cannot ride along with one that is still open.
    assert.equal(await errorOf(create(owner, [at(monday, 7), at(monday, 8, 30)], { at: nine })), 'in_past');
    assert.equal((await create(owner, [at(monday, 8, 30), at(monday, 10)], { at: nine })).slot_count, 2);
    assert.equal((await create(owner, [at(monday, 7)], { at: tashkent(monday, 8, 29) })).status, 'confirmed');
  });

  test(`${label}: no limit on upcoming bookings`, async () => {
    for (const hour of [7, 10, 13, 16, 19]) {
      assert.equal((await create(owner, [at(monday, hour)])).status, 'confirmed');
    }
  });

  test(`${label}: a taken slot is refused with slot_taken, and a player cannot take it either`, async () => {
    const held = await playerHold(ali, [at(monday, 7)]);
    assert.equal(await errorOf(create(owner, [at(monday, 7)])), 'slot_taken');
    // Once the hold has expired the slot is the owner's to give.
    const later = tashkent('2026-11-22', 20, 6);
    assert.equal((await create(owner, [at(monday, 7)], { at: later })).status, 'confirmed');
    assert.equal((await statusOf(held)).status, 'released');

    await book(vali, [at(monday, 10)]);
    assert.equal(await errorOf(create(owner, [at(monday, 8, 30), at(monday, 10)])), 'slot_taken');

    await create(owner, [at(monday, 13)]);
    assert.equal(await errorOf(playerHold(vali, [at(monday, 13)])), 'slot_taken');
    assert.equal(await errorOf(walkIn(owner, [at(monday, 13)])), 'slot_taken');
    assert.equal(await errorOf(block(owner, [at(monday, 13)])), 'slot_taken');
  });
}

test('the player-side availability shows walk-ins and blocks as taken', async () => {
  await walkIn(owner, [at(monday, 7)]);
  await block(owner, [at(monday, 10)]);
  for (const user of [null, vali]) {
    assert.equal(await stateOf(at(monday, 7), { user }), 'taken');
    assert.equal(await stateOf(at(monday, 10), { user }), 'taken');
    assert.equal(await stateOf(at(monday, 8, 30), { user }), 'free');
  }
  // Even for the player a walk-in was linked to.
  await walkIn(owner, [at(monday, 13)], { phone: aliPhone });
  assert.equal(await stateOf(at(monday, 13), { user: ali }), 'taken');
});

// ---------------------------------------------------------------------------
// Calendar
// ---------------------------------------------------------------------------

test('the calendar shows every slot with its price, state and booking', async () => {
  const w = await walkIn(owner, [at(monday, 8, 30)], { name: 'Bek', phone: '+998907777777', payment: 'card' });
  const b = await block(owner, [at(monday, 10)], { reason: 'Repair' });
  const appBooking = await book(ali, [at(monday, 13)]);

  // Monday at noon: 07:00 has ended; 11:30 is under way but not over.
  const cal = await calendar(owner, court, monday, 2, { at: tashkent(monday, 12) });
  assert.equal(cal.slots.length, 20);
  assert.equal(cal.slots[0].starts_local, '2026-11-23T07:00:00');
  assert.equal(cal.slots[0].ends_local, '2026-11-23T08:30:00');
  assert.equal(cal.slots.at(-1).starts_local, '2026-11-24T20:30:00');
  const slot = (start) => cal.slots.find((s) => s.starts_local === start);
  assert.deepEqual(slot(at(monday, 7)), {
    starts_local: '2026-11-23T07:00:00',
    ends_local: '2026-11-23T08:30:00',
    price: 180000,
    state: 'past',
    booking_id: null,
  });
  assert.deepEqual([slot(at(monday, 8, 30)).state, slot(at(monday, 8, 30)).booking_id], ['booked', w.id]);
  assert.deepEqual([slot(at(monday, 10)).state, slot(at(monday, 10)).booking_id], ['blocked', b.id]);
  assert.deepEqual([slot(at(monday, 11, 30)).state, slot(at(monday, 11, 30)).booking_id], ['free', null]);
  assert.deepEqual([slot(at(monday, 13)).state, slot(at(monday, 13)).booking_id], ['booked', appBooking]);
  assert.equal(slot(at(monday, 19)).price, 250000);
  assert.equal(slot(at(monday, 19)).state, 'free');
  assert.ok(cal.slots.filter((s) => s.starts_local.startsWith('2026-11-24')).every((s) => s.state === 'free'));

  assert.deepEqual(
    cal.bookings.map((x) => x.id),
    [w.id, b.id, appBooking],
  );
  const byId = Object.fromEntries(cal.bookings.map((x) => [x.id, x]));
  assert.equal(byId[w.id].customer_name, 'Bek');
  assert.equal(byId[w.id].customer_phone, '+998907777777');
  assert.equal(byId[w.id].walk_in_payment, 'card');
  assert.equal(byId[b.id].reason, 'Repair');
  assert.equal(byId[b.id].customer_name, null);
  // An app booking shows the player's profile name and phone.
  assert.equal(byId[appBooking].source, 'app');
  assert.equal(byId[appBooking].customer_name, 'Ali');
  assert.equal(byId[appBooking].customer_phone, aliPhone);
  assert.equal(byId[appBooking].walk_in_payment, null);
  assert.equal(byId[appBooking].reason, null);

  // Booked and blocked stay so after the slot is over.
  const late = await calendar(owner, court, monday, 1, { at: tashkent(monday, 23) });
  assert.deepEqual(
    late.slots.map((s) => s.state).slice(0, 5),
    ['past', 'booked', 'blocked', 'past', 'booked'],
  );
});

test("the calendar shows a player's live hold as booked, and an expired one as free", async () => {
  const held = await playerHold(vali, [at(monday, 14, 30)]);
  const live = await calendar(owner, court, monday, 1);
  const slot = live.slots.find((s) => s.starts_local === at(monday, 14, 30));
  assert.deepEqual([slot.state, slot.booking_id], ['booked', held]);
  assert.equal(live.bookings.find((x) => x.id === held).status, 'held');
  const expired = await calendar(owner, court, monday, 1, { at: tashkent('2026-11-22', 20, 5) });
  assert.equal(expired.slots.find((s) => s.starts_local === at(monday, 14, 30)).state, 'free');
  assert.equal(expired.bookings.length, 0);
});

test('the calendar covers 1 to 14 days', async () => {
  assert.equal((await calendar(owner, court, monday, 1)).slots.length, 10);
  assert.equal((await calendar(owner, court, monday, 14)).slots.length, 140);
  for (const days of [0, 15, -1, null]) {
    assert.equal(await errorOf(calendar(owner, court, monday, days)), 'invalid_argument');
  }
  assert.equal(await errorOf(calendar(owner, court, null, 7)), 'invalid_argument');
});

// ---------------------------------------------------------------------------
// Cancelling
// ---------------------------------------------------------------------------

test('the venue cancels a booking: the slot is free at once, and the second cancel is refused', async () => {
  const w = await walkIn(owner, [at(monday, 7)]);
  const cancelled = await cancelByVenue(owner, w.id);
  assert.equal(cancelled.status, 'cancelled_by_venue');
  assert.equal(await stateOf(at(monday, 7), { user: vali }), 'free');
  const cal = await calendar(owner, court, monday, 1);
  assert.equal(cal.slots[0].state, 'free');
  assert.equal(cal.bookings.length, 0);
  assert.equal(await errorOf(cancelByVenue(owner, w.id)), 'not_cancellable');
  const { cancelled_at } = await one(`select cancelled_at from bookings where id = $1`, [w.id]);
  assert.ok(cancelled_at);
});

test("cancelling a player's booking late never sets their late-cancellation flag", async () => {
  const id = await book(ali, [at(monday, 7)]);
  const cancelled = await cancelByVenue(owner, id, { at: tashkent(monday, 6) });
  assert.equal(cancelled.status, 'cancelled_by_venue');
  assert.equal(cancelled.late_cancellation, false);
  assert.equal(cancelled.customer_name, 'Ali');
});

test('a cancelled block frees its slots; cancelling it again is refused', async () => {
  const b = await block(owner, [at(monday, 10), at(monday, 11, 30)]);
  assert.equal((await cancelByVenue(owner, b.id)).status, 'cancelled_by_venue');
  assert.equal(await errorOf(cancelByVenue(owner, b.id)), 'not_cancellable');
  assert.equal(await stateOf(at(monday, 10), { user: vali }), 'free');
  assert.equal(await stateOf(at(monday, 11, 30), { user: vali }), 'free');
  assert.equal((await playerHold(vali, [at(monday, 11, 30)])).length, 36);
});

test('a booking can be cancelled until it ends, not after', async () => {
  const w = await walkIn(owner, [at(monday, 7)]);
  assert.equal(await errorOf(cancelByVenue(owner, w.id, { at: tashkent(monday, 8, 30) })), 'not_cancellable');
  assert.equal((await cancelByVenue(owner, w.id, { at: tashkent(monday, 8) })).status, 'cancelled_by_venue');
  // Only confirmed rows: not a hold, not a booking already marked.
  const held = await playerHold(vali, [at(monday, 13)]);
  assert.equal(await errorOf(cancelByVenue(owner, held)), 'not_cancellable');
  const paid = await walkIn(owner, [at(monday, 10)]);
  await mark(owner, paid.id, 'paid', { at: tashkent(monday, 10) });
  assert.equal(await errorOf(cancelByVenue(owner, paid.id, { at: tashkent(monday, 10, 30) })), 'not_cancellable');
});

// ---------------------------------------------------------------------------
// Paid and no-show
// ---------------------------------------------------------------------------

test('marking before the start is refused with not_markable', async () => {
  const w = await walkIn(owner, [at(monday, 7)]);
  assert.equal(await errorOf(mark(owner, w.id, 'paid')), 'not_markable');
  assert.equal(await errorOf(mark(owner, w.id, 'paid', { at: tashkent(monday, 6, 59) })), 'not_markable');
  assert.equal(await errorOf(mark(owner, w.id, 'no_show', { at: tashkent(monday, 6, 59) })), 'not_markable');
  assert.deepEqual(await statusOf(w.id), { status: 'confirmed', payment_status: 'unpaid' });
});

test('paid and no-show set status and payment status once the start has passed', async () => {
  const w = await walkIn(owner, [at(monday, 7)]);
  const paid = await mark(owner, w.id, 'paid', { at: tashkent(monday, 7) });
  assert.equal(paid.status, 'paid');
  assert.equal(paid.payment_status, 'paid');
  assert.equal(paid.source, 'walk_in');
  // A mistake can be corrected either way.
  const noShow = await mark(owner, w.id, 'no_show', { at: tashkent(monday, 9) });
  assert.equal(noShow.status, 'no_show');
  assert.equal(noShow.payment_status, 'unpaid');
  assert.equal((await mark(owner, w.id, 'paid', { at: tashkent(monday, 9) })).status, 'paid');

  const appBooking = await book(ali, [at(monday, 10)]);
  assert.equal((await mark(owner, appBooking, 'no_show', { at: tashkent(monday, 12) })).status, 'no_show');
});

test('completed and unverified bookings can be marked; blocks, holds and cancelled rows cannot', async () => {
  const done = await walkIn(owner, [at(monday, 7)]);
  const stale = await walkIn(owner, [at(monday, 8, 30)]);
  await pool.query(`update bookings set status = 'completed' where id = $1`, [done.id]);
  await pool.query(`update bookings set status = 'unverified' where id = $1`, [stale.id]);
  const later = tashkent('2026-11-26', 12);
  assert.equal((await mark(owner, done.id, 'paid', { at: later })).status, 'paid');
  assert.equal((await mark(owner, stale.id, 'no_show', { at: later })).status, 'no_show');

  const b = await block(owner, [at(monday, 10)]);
  assert.equal(await errorOf(mark(owner, b.id, 'paid', { at: later })), 'not_markable');
  const held = await playerHold(vali, [at(monday, 13)]);
  assert.equal(await errorOf(mark(owner, held, 'paid', { at: tashkent(monday, 14) })), 'not_markable');
  const gone = await walkIn(owner, [at(monday, 16)]);
  await cancelByVenue(owner, gone.id);
  assert.equal(await errorOf(mark(owner, gone.id, 'paid', { at: later })), 'not_markable');
});

test('an unknown outcome is refused', async () => {
  const w = await walkIn(owner, [at(monday, 7)]);
  for (const outcome of [null, '', 'completed', 'PAID!']) {
    assert.equal(await errorOf(mark(owner, w.id, outcome, { at: tashkent(monday, 9) })), 'invalid_argument');
  }
});

// ---------------------------------------------------------------------------
// Audit log
// ---------------------------------------------------------------------------

test('every successful owner write adds one audit row with actor, action, booking, before and after', async () => {
  const w = await walkIn(owner, [at(monday, 7)], { name: 'Bek' });
  let log = await auditRows();
  assert.equal(log.length, 1);
  assert.equal(log[0].actor_id, owner);
  assert.equal(log[0].action, 'create_walk_in');
  assert.equal(log[0].entity, 'booking');
  assert.equal(log[0].entity_id, w.id);
  assert.equal(log[0].before, null);
  assert.equal(log[0].after.status, 'confirmed');
  assert.equal(log[0].after.guest_name, 'Bek');
  assert.equal(new Date(log[0].created_at).toISOString(), new Date(now).toISOString());

  const b = await block(admin, [at(monday, 10)], { reason: 'Repair' });
  await mark(owner, w.id, 'paid', { at: tashkent(monday, 8) });
  await cancelByVenue(owner, b.id, { at: tashkent(monday, 9) });
  log = await auditRows();
  assert.deepEqual(
    log.map((r) => [r.actor_id, r.action, r.entity_id]),
    [
      [owner, 'create_walk_in', w.id],
      [admin, 'block_slots', b.id],
      [owner, 'mark_booking', w.id],
      [owner, 'cancel_booking', b.id],
    ],
  );
  assert.equal(log[1].before, null);
  assert.equal(log[1].after.block_reason, 'Repair');
  assert.deepEqual([log[2].before.status, log[2].after.status], ['confirmed', 'paid']);
  assert.deepEqual([log[2].before.payment_status, log[2].after.payment_status], ['unpaid', 'paid']);
  assert.deepEqual([log[3].before.status, log[3].after.status], ['confirmed', 'cancelled_by_venue']);

  // Refused writes leave no trace.
  await errorOf(cancelByVenue(owner, b.id));
  await errorOf(mark(owner, b.id, 'paid', { at: tashkent(monday, 12) }));
  await errorOf(walkIn(owner, [at(monday, 7)]));
  await errorOf(walkIn(owner, [at(monday, 13)], { name: '' }));
  await errorOf(calendar(owner, court, monday, 7));
  assert.equal((await auditRows()).length, 4);
});

// ---------------------------------------------------------------------------
// Scheduled job
// ---------------------------------------------------------------------------

test('advance_bookings completes finished bookings, then marks them unverified after 48 hours; blocks are skipped', async () => {
  const early = await walkIn(owner, [at(monday, 7)]); // ends Mon 08:30
  const evening = await walkIn(owner, [at(monday, 20, 30)]); // ends Mon 22:00
  const b = await block(owner, [at(monday, 10)]);
  const gone = await walkIn(owner, [at(monday, 13)]);
  await cancelByVenue(owner, gone.id);
  const paid = await walkIn(owner, [at(monday, 16)]);
  await mark(owner, paid.id, 'paid', { at: tashkent(monday, 16) });
  const appBooking = await book(ali, [at(monday, 17, 30)]); // ends Mon 19:00
  const advance = async (when) => (await one(`select app.advance_bookings($1) as n`, [when])).n;
  const statuses = async () =>
    Object.fromEntries(
      await Promise.all(
        [
          ['early', early.id],
          ['evening', evening.id],
          ['block', b.id],
          ['gone', gone.id],
          ['paid', paid.id],
          ['app', appBooking],
        ].map(async ([k, id]) => [k, (await statusOf(id)).status]),
      ),
    );

  assert.equal(await advance(tashkent(monday, 21)), 2);
  assert.deepEqual(await statuses(), {
    early: 'completed',
    evening: 'confirmed',
    block: 'confirmed',
    gone: 'cancelled_by_venue',
    paid: 'paid',
    app: 'completed',
  });

  // Exactly 48 hours after the end is not yet "more than 48 hours".
  assert.equal(await advance(tashkent('2026-11-25', 8, 30)), 1);
  assert.equal((await statusOf(early.id)).status, 'completed');
  assert.equal((await statusOf(evening.id)).status, 'completed');
  assert.equal(await advance(tashkent('2026-11-25', 8, 31)), 1);
  assert.equal((await statusOf(early.id)).status, 'unverified');

  // A confirmed booking found long after its end goes straight to unverified.
  const tuesday = await walkIn(owner, [at('2026-11-24', 7)]);
  assert.equal(await advance(tashkent('2026-12-10', 12)), 3);
  assert.deepEqual(await statuses(), {
    early: 'unverified',
    evening: 'unverified',
    block: 'confirmed',
    gone: 'cancelled_by_venue',
    paid: 'paid',
    app: 'unverified',
  });
  assert.equal((await statusOf(tuesday.id)).status, 'unverified');
  assert.equal(await advance(tashkent('2026-12-10', 12)), 0);
});

// ---------------------------------------------------------------------------
// The guarantee: owner and player at the same moment
// ---------------------------------------------------------------------------

test('owner walk-in and player hold on the same slot at the same moment: exactly one succeeds', async () => {
  const courts = [];
  for (let i = 0; i < 20; i++) courts.push(await addCourt(pool, venueId, { slot: 60 }));
  const players = [];
  for (let i = 0; i < 20; i++) players.push(await createUser(pool, `Racer ${i}`));
  // Each call takes its own pool connection, so both really run at once.
  const ownerCall = (courtId, i) =>
    pool.query(
      i % 2
        ? `select (app.owner_create_walk_in($1, $2, $3::timestamp[], 'Guest', null, null, 'cash', $4)).id`
        : `select (app.owner_block_slots($1, $2, $3::timestamp[], null, $4)).id`,
      [owner, courtId, [at(monday, 10)], now],
    );
  const results = await Promise.all(
    courts.flatMap((courtId, i) => [
      errorOf(ownerCall(courtId, i)),
      errorOf(playerHold(players[i], [at(monday, 10)], { courtId })),
    ]),
  );
  for (let i = 0; i < courts.length; i++) {
    const pair = [results[2 * i], results[2 * i + 1]].sort();
    assert.deepEqual(pair, [null, 'slot_taken'].sort(), `court ${i}: ${JSON.stringify(pair)}`);
    const { rows } = await pool.query(
      `select count(*)::int as n from bookings where court_id = $1 and status in ('held', 'confirmed')`,
      [courts[i]],
    );
    assert.equal(rows[0].n, 1);
  }
});

// ---------------------------------------------------------------------------
// Through the API
// ---------------------------------------------------------------------------

const rpc = (client, name, args) => client.query(`select public.${name}(${args.map((_, i) => `$${i + 1}`).join(', ')}) as r`, args);

test('the public functions act as the signed-in user at the real time', async () => {
  const { rows } = await pool.query(`select to_char((app.to_local(now(), 300))::date + 3, 'YYYY-MM-DD') as d`);
  const day = rows[0].d;
  const slot = at(day, 10);
  const next = at(day, 11, 30);

  assert.deepEqual((await asUser(pool, owner, (c) => rpc(c, 'my_venue_ids', []))).rows[0].r, [venueId]);
  assert.deepEqual((await asUser(pool, vali, (c) => rpc(c, 'my_venue_ids', []))).rows[0].r, []);

  const w = (await asUser(pool, owner, (c) => rpc(c, 'owner_create_walk_in', [court, [slot], 'Bek', null, 2, 'card']))).rows[0].r;
  assert.equal(w.source, 'walk_in');
  assert.equal(w.customer_name, 'Bek');
  assert.equal(w.walk_in_payment, 'card');
  const b = (await asUser(pool, owner, (c) => rpc(c, 'owner_block_slots', [court, [next], 'Repair']))).rows[0].r;
  assert.equal(b.source, 'block');
  const cal = (await asUser(pool, owner, (c) => rpc(c, 'owner_calendar', [court, day, 1]))).rows[0].r;
  assert.equal(cal.slots.find((s) => s.starts_local === slot).state, 'booked');
  assert.equal(cal.slots.find((s) => s.starts_local === next).state, 'blocked');
  assert.equal(await errorOf(asUser(pool, owner, (c) => rpc(c, 'owner_mark_booking', [w.id, 'paid']))), 'not_markable');
  const cancelled = (await asUser(pool, owner, (c) => rpc(c, 'owner_cancel_booking', [b.id]))).rows[0].r;
  assert.equal(cancelled.status, 'cancelled_by_venue');

  const log = await auditRows();
  assert.deepEqual(
    log.map((r) => [r.actor_id, r.action]),
    [
      [owner, 'create_walk_in'],
      [owner, 'block_slots'],
      [owner, 'cancel_booking'],
    ],
  );

  // A signed-in player with no role is refused by name.
  assert.equal(await errorOf(asUser(pool, vali, (c) => rpc(c, 'owner_calendar', [court, day, 1]))), 'not_allowed');
  assert.equal(
    await errorOf(asUser(pool, vali, (c) => rpc(c, 'owner_create_walk_in', [court, [next], 'X', null, null, 'cash']))),
    'not_allowed',
  );
  assert.equal(await errorOf(asUser(pool, vali, (c) => rpc(c, 'owner_block_slots', [court, [next], null]))), 'not_allowed');
  assert.equal(await errorOf(asUser(pool, vali, (c) => rpc(c, 'owner_cancel_booking', [w.id]))), 'not_allowed');
  assert.equal(await errorOf(asUser(pool, vali, (c) => rpc(c, 'owner_mark_booking', [w.id, 'paid']))), 'not_allowed');
  // p_reason may be left out.
  const plain = (await asUser(pool, owner, (c) => c.query(`select public.owner_block_slots($1, $2::timestamp[]) as r`, [court, [next]])))
    .rows[0].r;
  assert.equal(plain.reason, null);
});

test('visitors cannot call the owner functions; the app schema is closed to the API', async () => {
  const w = await walkIn(owner, [at(monday, 7)]);
  const calls = [
    ['my_venue_ids', []],
    ['owner_calendar', [court, monday, 7]],
    ['owner_create_walk_in', [court, [at(monday, 10)], 'X', null, null, 'cash']],
    ['owner_block_slots', [court, [at(monday, 10)], null]],
    ['owner_cancel_booking', [w.id]],
    ['owner_mark_booking', [w.id, 'paid']],
  ];
  for (const [name, args] of calls) {
    await expectError(
      asAnon(pool, (c) => rpc(c, name, args)),
      '42501',
    );
  }
  const signatures = [
    'public.my_venue_ids()',
    'public.owner_calendar(uuid, date, integer)',
    'public.owner_create_walk_in(uuid, timestamp[], text, text, integer, text)',
    'public.owner_block_slots(uuid, timestamp[], text)',
    'public.owner_cancel_booking(uuid)',
    'public.owner_mark_booking(uuid, text)',
  ];
  for (const fn of signatures) {
    const { rows } = await pool.query(
      `select has_function_privilege('anon', $1, 'execute') as anon,
              has_function_privilege('authenticated', $1, 'execute') as authed,
              has_function_privilege('service_role', $1, 'execute') as service`,
      [fn],
    );
    assert.deepEqual(rows[0], { anon: false, authed: true, service: true }, fn);
  }
  await expectError(
    asUser(pool, owner, (c) =>
      c.query(`select app.owner_create_walk_in($1, $2, $3::timestamp[], 'X', null, null, 'cash', now())`, [
        owner,
        court,
        [at(monday, 10)],
      ]),
    ),
    '42501',
  );
  await expectError(
    asUser(pool, owner, (c) => c.query(`select app.advance_bookings(now())`)),
    '42501',
  );
});

test('app_admins and audit_log are closed to the API', async () => {
  const { rows: seq } = await pool.query(
    `select has_sequence_privilege('anon', 'public.audit_log_id_seq', 'usage,select,update') as anon,
            has_sequence_privilege('authenticated', 'public.audit_log_id_seq', 'usage,select,update') as authed`,
  );
  assert.deepEqual(seq[0], { anon: false, authed: false });
  for (const table of ['app_admins', 'audit_log']) {
    await expectError(
      asUser(pool, owner, (c) => c.query(`select * from ${table}`)),
      '42501',
    );
    await expectError(
      asAnon(pool, (c) => c.query(`select * from ${table}`)),
      '42501',
    );
  }
  // Nobody makes themselves an admin.
  await expectError(
    asUser(pool, vali, (c) => c.query(`insert into app_admins (user_id) values ($1)`, [vali])),
    '42501',
  );
  await expectError(
    asUser(pool, owner, (c) => c.query(`delete from audit_log`)),
    '42501',
  );
  const { rows } = await pool.query(
    `select relname, relrowsecurity from pg_class where relname in ('app_admins', 'audit_log') and relnamespace = 'public'::regnamespace order by relname`,
  );
  assert.deepEqual(rows, [
    { relname: 'app_admins', relrowsecurity: true },
    { relname: 'audit_log', relrowsecurity: true },
  ]);
});

test('the table refuses a walk-in without a name and a block with a player, whoever writes it', async () => {
  const insert = (fields) =>
    pool.query(
      `insert into bookings (user_id, venue_id, court_id, during, utc_offset_minutes, slot_count, total_price, currency, status,
                             source, guest_name, walk_in_payment)
       values ($1, $2, $3, '[2026-11-30 05:00+00,2026-11-30 06:30+00)', 300, 1, 0, 'UZS', 'confirmed', $4, $5, $6)`,
      [fields.user ?? null, venueId, court, fields.source, fields.name ?? null, fields.payment ?? null],
    );
  await expectError(insert({ source: 'walk_in', name: ' ', payment: 'cash' }), '23514');
  await expectError(insert({ source: 'walk_in', name: 'Bek', payment: 'crypto' }), '23514');
  await expectError(insert({ source: 'walk_in', name: 'Bek' }), '23514');
  await expectError(insert({ source: 'block', user: ali }), '23514');
  await expectError(insert({ source: 'app', payment: 'cash', user: ali }), '23514');
  await expectError(insert({ source: 'app' }), '23514');
  await expectError(insert({ source: 'other' }), '23514');
  await insert({ source: 'block' });
});
