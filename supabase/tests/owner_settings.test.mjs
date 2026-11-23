// Owner settings and dashboard (Milestone 3b): working hours, court
// overrides, slot length and price rules, and the venue dashboard. As in
// owner.test.mjs, the `app` functions are called with the acting user and a
// fixed clock; the last tests go through the `public` wrappers.

import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { after, before, beforeEach, test } from 'node:test';
import { asAnon, asUser, createUser, errorOf, expectError, freshDb } from './helpers/db.mjs';
import { addAdmin, addCourt, addOwner, addVenue, at, monday, saturday, tashkent } from './helpers/fixtures.mjs';

let db;
let pool;
let owner; // owns every venueId made in beforeEach
let otherOwner; // owns otherVenueId only
let admin;
let ali;
let vali; // no role
let venueId;
let otherVenueId;
let court;
let otherCourt;

const now = tashkent('2026-11-22', 20);
const tuesday = '2026-11-24';
const sunday = '2026-11-29';

before(async () => {
  db = await freshDb('owner_settings');
  pool = db.pool;
  owner = await createUser(pool, 'Owner');
  otherOwner = await createUser(pool, 'Other owner');
  admin = await addAdmin(pool, await createUser(pool, 'Admin'));
  ali = await createUser(pool, 'Ali');
  vali = await createUser(pool, 'Vali');
  otherVenueId = await addVenue(pool, { name: 'Other venue' });
  await addOwner(pool, otherVenueId, otherOwner);
  otherCourt = await addCourt(pool, otherVenueId);
});
after(() => db.end());

// A fresh venue (07:00-23:00 every day) and court for every test, with the
// evening rule from booking.test.mjs: weekdays 18:00-23:00 at 250 000.
beforeEach(async () => {
  await pool.query('delete from audit_log');
  await pool.query('delete from bookings');
  venueId = await addVenue(pool);
  await addOwner(pool, venueId, owner);
  court = await addCourt(pool, venueId, {
    rules: [{ weekdays: [1, 2, 3, 4, 5], from: 1080, to: 1380, price: 250000 }],
  });
});

const one = async (sql, params) => (await pool.query(sql, params)).rows[0];
const json = (value) => (value === null || typeof value === 'string' ? value : JSON.stringify(value));

/** Seven days, 07:00-23:00 unless `days` says otherwise: { 1: [540, 1260], 7: null }. */
const week = (days = {}) =>
  [1, 2, 3, 4, 5, 6, 7].map((weekday) => {
    const day = weekday in days ? days[weekday] : [420, 1380];
    return { weekday, open_minute: day?.[0] ?? null, close_minute: day?.[1] ?? null };
  });

const setVenueHours = (user, venue, hours, { at: when = now } = {}) =>
  one(`select app.owner_set_venue_hours($1, $2, $3::jsonb, $4) as r`, [user, venue, json(hours), when]).then((r) => r.r);

const setCourtHours = (user, courtId, hours, { at: when = now } = {}) =>
  one(`select app.owner_set_court_hours($1, $2, $3::jsonb, $4) as r`, [user, courtId, json(hours), when]).then((r) => r.r);

const setPricing = (user, courtId, slot, base, rules, { at: when = now } = {}) =>
  one(`select app.owner_set_court_pricing($1, $2, $3, $4, $5::jsonb, $6) as r`, [user, courtId, slot, base, json(rules), when]).then(
    (r) => r.r,
  );

const dashboard = (user, venue, courtId, from, to) =>
  one(`select app.owner_dashboard($1, $2, $3, $4::date, $5::date) as d`, [user, venue, courtId, from, to]).then((r) => r.d);

const slots = async (courtId, day) =>
  (await pool.query(`select * from app.court_slots($1, $2::date) order by starts_local`, [courtId, day])).rows;

const stateOf = async (courtId, start) => {
  const { rows } = await pool.query(`select * from app.court_availability(null, $1, $2::date, $3)`, [courtId, start.slice(0, 10), now]);
  const slot = rows.find((r) => r.starts_local === start);
  assert.ok(slot, `no slot at ${start}`);
  return slot.state;
};

const hold = (user, courtId, starts) =>
  one(`select b.* from app.hold_slots($1, $2, $3::timestamp[], $4) b`, [user, courtId, starts, now]);

const book = async (user, courtId, starts) => {
  const held = await hold(user, courtId, starts);
  await pool.query(`select app.confirm_booking($1, $2, null, null, $3)`, [user, held.id, now]);
  return held.id;
};

const walkIn = async (courtId, starts) =>
  (
    await one(`select (app.owner_create_walk_in($1, $2, $3::timestamp[], 'Guest', null, null, 'cash', $4)).id`, [
      owner,
      courtId,
      starts,
      now,
    ])
  ).id;

const blockSlots = async (courtId, starts) =>
  (await one(`select (app.owner_block_slots($1, $2, $3::timestamp[], null, $4)).id`, [owner, courtId, starts, now])).id;

const setStatus = (id, status, paymentStatus = 'unpaid') =>
  pool.query(`update bookings set status = $2, payment_status = $3 where id = $1`, [id, status, paymentStatus]);

const auditRows = async () =>
  (await pool.query(`select actor_id, action, entity, entity_id, before, after from audit_log order by id`)).rows;

const hoursOf = async (column, id) =>
  (
    await pool.query(
      `select weekday, closed, open_minute, close_minute from working_hours where ${column} = $1 order by weekday`,
      [id],
    )
  ).rows;

const pricingOf = async (courtId) => ({
  court: await one(`select slot_minutes, base_price from courts where id = $1`, [courtId]),
  rules: (
    await pool.query(
      `select weekdays, from_minute, to_minute, price, sort_order from price_rules where court_id = $1 order by sort_order`,
      [courtId],
    )
  ).rows,
});

// Everything a settings function could change.
const snapshot = async () => ({
  hours: (await pool.query(`select venue_id, court_id, weekday, closed, open_minute, close_minute from working_hours order by 1, 2, 3`))
    .rows,
  courts: (await pool.query(`select id, slot_minutes, base_price from courts order by id`)).rows,
  rules: (await pool.query(`select court_id, weekdays, from_minute, to_minute, price, sort_order from price_rules order by 1, 6`))
    .rows,
  audit: (await pool.query(`select count(*)::int as n from audit_log`)).rows[0].n,
});

const goodRules = [
  { weekdays: [1, 2, 3, 4, 5], from_minute: 1080, to_minute: 1380, price: 150000 },
  { weekdays: [6, 7], from_minute: 0, to_minute: 1440, price: 200000 },
];

// ---------------------------------------------------------------------------
// Venue hours
// ---------------------------------------------------------------------------

test('venue hours: saved as the slots read them, closed days have no row, one audit row', async () => {
  const result = await setVenueHours(owner, venueId, week({ 1: [540, 1260], 7: null }));
  // void: node-postgres reads it as an empty string.
  assert.equal(result, '');

  const mon = await slots(court, monday);
  assert.equal(mon.length, 8);
  assert.equal(mon[0].starts_local, '2026-11-23T09:00:00');
  assert.equal(mon.at(-1).ends_local, '2026-11-23T21:00:00');
  assert.equal((await slots(court, sunday)).length, 0);
  assert.equal((await slots(court, tuesday)).length, 10);

  const rows = await hoursOf('venue_id', venueId);
  assert.deepEqual(
    rows.map((r) => [r.weekday, r.closed, r.open_minute, r.close_minute]),
    [
      [1, false, 540, 1260],
      [2, false, 420, 1380],
      [3, false, 420, 1380],
      [4, false, 420, 1380],
      [5, false, 420, 1380],
      [6, false, 420, 1380],
    ],
  );

  const log = await auditRows();
  assert.equal(log.length, 1);
  assert.deepEqual([log[0].actor_id, log[0].action, log[0].entity, log[0].entity_id], [owner, 'set_venue_hours', 'venue', venueId]);
  assert.equal(log[0].before.length, 7);
  assert.equal(log[0].after.length, 6);
  assert.deepEqual(log[0].after[0], { weekday: 1, closed: false, open_minute: 540, close_minute: 1260 });

  // Order of the objects does not matter; reopening Sunday adds its row back.
  await setVenueHours(owner, venueId, week().reverse());
  assert.equal((await hoursOf('venue_id', venueId)).length, 7);
  assert.equal((await slots(court, sunday)).length, 10);
});

test('venue hours: invalid_hours and invalid_argument, and nothing changes', async () => {
  const before = await snapshot();
  const hoursErrors = [
    week().slice(0, 6),
    [...week(), { weekday: 1, open_minute: 420, close_minute: 1380 }],
    [...week().slice(0, 6), { weekday: 1, open_minute: 420, close_minute: 1380 }],
    [...week().slice(1), { weekday: 0, open_minute: 420, close_minute: 1380 }],
    [...week().slice(0, 6), { weekday: 8, open_minute: 420, close_minute: 1380 }],
    week({ 1: [1380, 420] }),
    week({ 1: [600, 600] }),
    week({ 1: [-10, 600] }),
    week({ 1: [600, 1500] }),
    week({ 1: [600, null] }),
    week({ 1: [null, 600] }),
    [],
  ];
  for (const hours of hoursErrors) {
    assert.equal(await errorOf(setVenueHours(owner, venueId, hours)), 'invalid_hours', JSON.stringify(hours));
  }
  const argumentErrors = [
    null,
    '{}',
    '"week"',
    '[1, 2, 3, 4, 5, 6, 7]',
    [...week().slice(0, 6), { weekday: '7', open_minute: 420, close_minute: 1380 }],
    [...week().slice(0, 6), { weekday: 7, open_minute: 420.5, close_minute: 1380 }],
    [...week().slice(0, 6), { weekday: 7, open_minute: '420', close_minute: 1380 }],
    [...week().slice(0, 6), { open_minute: 420, close_minute: 1380 }],
  ];
  for (const hours of argumentErrors) {
    assert.equal(await errorOf(setVenueHours(owner, venueId, hours)), 'invalid_argument', JSON.stringify(hours));
  }
  assert.deepEqual(await snapshot(), before);
});

// ---------------------------------------------------------------------------
// Court hours
// ---------------------------------------------------------------------------

test('court hours: overridden days replace the venue, an empty array follows the venue again', async () => {
  const sibling = await addCourt(pool, venueId);
  await setCourtHours(owner, court, [
    { weekday: 1, open_minute: null, close_minute: null },
    { weekday: 2, open_minute: 600, close_minute: 840 },
  ]);
  assert.equal((await slots(court, monday)).length, 0);
  assert.deepEqual(
    (await slots(court, tuesday)).map((s) => s.starts_local),
    ['2026-11-24T10:00:00', '2026-11-24T11:30:00'],
  );
  assert.equal((await slots(court, '2026-11-25')).length, 10);
  assert.equal((await slots(sibling, monday)).length, 10);
  assert.deepEqual(
    (await hoursOf('court_id', court)).map((r) => [r.weekday, r.closed]),
    [
      [1, true],
      [2, false],
    ],
  );

  await setCourtHours(owner, court, []);
  assert.equal((await slots(court, monday)).length, 10);
  assert.equal((await hoursOf('court_id', court)).length, 0);

  const log = await auditRows();
  assert.deepEqual(
    log.map((r) => [r.actor_id, r.action, r.entity, r.entity_id]),
    [
      [owner, 'set_court_hours', 'court', court],
      [owner, 'set_court_hours', 'court', court],
    ],
  );
  assert.deepEqual(log[1].before.length, 2);
  assert.deepEqual(log[1].after, []);
});

test('court hours: validation', async () => {
  const before = await snapshot();
  const day = (weekday, open = 600, close = 840) => ({ weekday, open_minute: open, close_minute: close });
  for (const hours of [
    [day(1), day(1)],
    [...week(), day(1)],
    [day(1, 840, 600)],
    [day(1, 0, 1441)],
    [day(9)],
    [{ weekday: 1, open_minute: 600, close_minute: null }],
  ]) {
    assert.equal(await errorOf(setCourtHours(owner, court, hours)), 'invalid_hours', JSON.stringify(hours));
  }
  for (const hours of [null, '{}', '[1]', [{ open_minute: 600, close_minute: 840 }]]) {
    assert.equal(await errorOf(setCourtHours(owner, court, hours)), 'invalid_argument', JSON.stringify(hours));
  }
  assert.deepEqual(await snapshot(), before);
});

// ---------------------------------------------------------------------------
// Slot length and prices
// ---------------------------------------------------------------------------

test('pricing: new slots and prices for new bookings; an existing booking keeps its time and price', async () => {
  const existing = await book(vali, court, [at(monday, 7)]);

  await setPricing(owner, court, 60, 100000, goodRules);

  const mon = await slots(court, monday);
  assert.equal(mon.length, 16);
  const price = (list, start) => list.find((s) => s.starts_local === start).price;
  assert.equal(price(mon, at(monday, 7)), 100000);
  assert.equal(price(mon, at(monday, 17)), 100000);
  assert.equal(price(mon, at(monday, 18)), 150000);
  assert.equal(price(mon, at(monday, 22)), 150000);
  assert.equal(price(await slots(court, saturday), at(saturday, 7)), 200000);

  assert.deepEqual(await pricingOf(court), {
    court: { slot_minutes: 60, base_price: 100000 },
    rules: [
      { weekdays: [1, 2, 3, 4, 5], from_minute: 1080, to_minute: 1380, price: 150000, sort_order: 0 },
      { weekdays: [6, 7], from_minute: 0, to_minute: 1440, price: 200000, sort_order: 1 },
    ],
  });

  // The booking made under the old settings is untouched.
  const kept = await one(
    `select total_price, slot_count, app.to_local(lower(during), utc_offset_minutes) as starts,
            app.to_local(upper(during), utc_offset_minutes) as ends, status from bookings where id = $1`,
    [existing],
  );
  assert.deepEqual(kept, {
    total_price: 180000,
    slot_count: 1,
    starts: '2026-11-23T07:00:00',
    ends: '2026-11-23T08:30:00',
    status: 'confirmed',
  });
  // It still holds its time against the new 60-minute grid.
  assert.equal(await stateOf(court, at(monday, 7)), 'taken');
  assert.equal(await stateOf(court, at(monday, 8)), 'taken');
  assert.equal(await stateOf(court, at(monday, 9)), 'free');
  assert.equal((await hold(ali, court, [at(monday, 9)])).total_price, 100000);
  assert.equal((await hold(ali, court, [at(monday, 18), at(monday, 19)])).total_price, 300000);

  const log = await auditRows();
  assert.equal(log.length, 1);
  assert.deepEqual([log[0].actor_id, log[0].action, log[0].entity, log[0].entity_id], [owner, 'set_court_pricing', 'court', court]);
  assert.deepEqual([log[0].before.slot_minutes, log[0].before.base_price, log[0].before.rules.length], [90, 180000, 1]);
  assert.deepEqual([log[0].after.slot_minutes, log[0].after.base_price, log[0].after.rules.length], [60, 100000, 2]);
});

test('pricing: an empty rule list leaves only the base price; touching and other-day rules do not overlap', async () => {
  await setPricing(owner, court, 120, 90000, []);
  assert.deepEqual((await pricingOf(court)).rules, []);
  assert.ok((await slots(court, monday)).every((s) => s.price === 90000));

  await setPricing(owner, court, 90, 100000, [
    { weekdays: [1], from_minute: 1080, to_minute: 1200, price: 1 },
    { weekdays: [1], from_minute: 1200, to_minute: 1380, price: 2 },
    { weekdays: [2], from_minute: 1080, to_minute: 1380, price: 3 },
    { weekdays: [3, 3], from_minute: 0, to_minute: 1440, price: 0 },
  ]);
  const { rules } = await pricingOf(court);
  assert.equal(rules.length, 4);
  assert.deepEqual(rules[3].weekdays, [3]);
});

test('pricing: validation', async () => {
  const before = await snapshot();
  const rule = (overrides) => ({ weekdays: [1], from_minute: 1080, to_minute: 1380, price: 1000, ...overrides });
  const argumentCases = [
    [45, 1000, []],
    [null, 1000, []],
    [90, -1, []],
    [90, null, []],
    [90, 1000, null],
    [90, 1000, '{}'],
    [90, 1000, '[1]'],
    [90, 1000, [rule({ price: -1 })]],
    [90, 1000, [rule({ price: null })]],
    [90, 1000, [rule({ price: 10.5 })]],
    [90, 1000, [rule({ weekdays: [] })]],
    [90, 1000, [rule({ weekdays: [0] })]],
    [90, 1000, [rule({ weekdays: [8] })]],
    [90, 1000, [rule({ weekdays: ['1'] })]],
    [90, 1000, [rule({ weekdays: 1 })]],
    [90, 1000, [rule({ from_minute: null })]],
  ];
  for (const [slot, base, rules] of argumentCases) {
    assert.equal(await errorOf(setPricing(owner, court, slot, base, rules)), 'invalid_argument', JSON.stringify([slot, base, rules]));
  }
  for (const rules of [
    [rule({ from_minute: 1380, to_minute: 1080 })],
    [rule({ from_minute: 1080, to_minute: 1080 })],
    [rule({ to_minute: 1441 })],
    [rule({ from_minute: -1 })],
  ]) {
    assert.equal(await errorOf(setPricing(owner, court, 90, 1000, rules)), 'invalid_hours', JSON.stringify(rules));
  }
  for (const rules of [
    [rule({ weekdays: [1, 2] }), rule({ weekdays: [2, 3], from_minute: 1200, to_minute: 1300 })],
    [rule({}), rule({})],
    [rule({ from_minute: 0, to_minute: 1440 }), rule({ weekdays: [5, 1], from_minute: 600, to_minute: 660 })],
  ]) {
    assert.equal(await errorOf(setPricing(owner, court, 90, 1000, rules)), 'rules_overlap', JSON.stringify(rules));
  }
  assert.deepEqual(await snapshot(), before);
});

test('pricing: prices above 50 000 000 and weekday lists over 7 entries are refused', async () => {
  const before = await snapshot();
  const rule = (overrides) => ({ weekdays: [1], from_minute: 1080, to_minute: 1380, price: 1000, ...overrides });
  assert.equal(await errorOf(setPricing(owner, court, 90, 50000001, [])), 'invalid_argument');
  assert.equal(await errorOf(setPricing(owner, court, 90, 2147483647, [])), 'invalid_argument');
  assert.equal(await errorOf(setPricing(owner, court, 90, 1000, [rule({ price: 50000001 })])), 'invalid_argument');
  assert.equal(await errorOf(setPricing(owner, court, 90, 1000, [rule({ weekdays: [1, 1, 2, 3, 4, 5, 6, 7] })])), 'invalid_argument');
  assert.deepEqual(await snapshot(), before);
  // The limits themselves are allowed, and a booking at the cap still sums.
  await setPricing(owner, court, 90, 50000000, [rule({ weekdays: [1, 1, 2, 3, 4, 5, 7], price: 50000000 })]);
  assert.deepEqual((await pricingOf(court)).rules[0].weekdays, [1, 2, 3, 4, 5, 7]);
  assert.equal((await hold(vali, court, [at(monday, 7), at(monday, 8, 30)])).total_price, 100000000);
});

test('dashboard: bookings in another currency are left out', async () => {
  const kept = await walkIn(court, [at(monday, 7)]);
  const moved = await walkIn(court, [at(monday, 10)]);
  await setStatus(kept, 'paid', 'paid');
  await setStatus(moved, 'paid', 'paid');
  // As if the venue had been in a KZT city when this one was made.
  await pool.query(`update bookings set currency = 'KZT' where id = $1`, [moved]);
  const d = await dashboard(owner, venueId, null, monday, monday);
  assert.deepEqual(
    [d.currency, d.bookings_walk_in, d.revenue_paid, d.slots_booked, d.heatmap],
    ['UZS', 1, 180000, 1, [{ weekday: 1, hour: 7, count: 1 }]],
  );
});

test('dashboard: dates more than 10 years from today are refused', async () => {
  const { rows } = await pool.query(
    `select to_char(current_date + interval '10 years', 'YYYY-MM-DD') as hi, to_char(current_date - interval '10 years', 'YYYY-MM-DD') as lo,
            to_char(current_date + interval '10 years 1 day', 'YYYY-MM-DD') as over, to_char(current_date - interval '10 years 1 day', 'YYYY-MM-DD') as under`,
  );
  const { hi, lo, over, under } = rows[0];
  assert.equal((await dashboard(owner, venueId, null, hi, hi)).days, 1);
  assert.equal((await dashboard(owner, venueId, null, lo, lo)).days, 1);
  for (const [from, to] of [
    [over, over],
    [under, under],
    ['9999-12-30', '9999-12-31'],
    ['0001-01-01', '0001-01-02'],
  ]) {
    assert.equal(await errorOf(dashboard(owner, venueId, null, from, to)), 'invalid_argument', `${from}..${to}`);
  }
});

test('dashboard: a venue\'s bookings are indexed by time range', async () => {
  const { rows } = await pool.query(`select indexdef from pg_indexes where indexname = 'bookings_venue_during_idx'`);
  assert.equal(rows.length, 1);
  assert.match(rows[0].indexdef, /USING gist \(venue_id, during\)/);
});

// ---------------------------------------------------------------------------
// Who may change what
// ---------------------------------------------------------------------------

test('a user who does not manage the venue is refused by every function; nothing changes, nothing is logged', async () => {
  const before = await snapshot();
  for (const user of [vali, otherOwner, null]) {
    assert.equal(await errorOf(setVenueHours(user, venueId, week())), 'not_allowed');
    assert.equal(await errorOf(setCourtHours(user, court, [])), 'not_allowed');
    assert.equal(await errorOf(setPricing(user, court, 60, 1000, [])), 'not_allowed');
    assert.equal(await errorOf(dashboard(user, venueId, null, monday, sunday)), 'not_allowed');
    assert.equal(await errorOf(dashboard(user, venueId, court, monday, sunday)), 'not_allowed');
    // The role check comes before every other check.
    assert.equal(await errorOf(setVenueHours(user, venueId, '{}')), 'not_allowed');
    assert.equal(await errorOf(setCourtHours(user, court, [{ weekday: 1, open_minute: 900, close_minute: 600 }])), 'not_allowed');
    assert.equal(await errorOf(setPricing(user, court, 45, -1, null)), 'not_allowed');
    assert.equal(await errorOf(dashboard(user, venueId, null, monday, '2027-12-31')), 'not_allowed');
    // Unknown ids look the same as someone else's.
    assert.equal(await errorOf(setVenueHours(user, randomUUID(), week())), 'not_allowed');
    assert.equal(await errorOf(setCourtHours(user, randomUUID(), [])), 'not_allowed');
    assert.equal(await errorOf(setPricing(user, randomUUID(), 60, 1000, [])), 'not_allowed');
    assert.equal(await errorOf(dashboard(user, randomUUID(), null, monday, sunday)), 'not_allowed');
  }
  // An owner cannot reach another venue's court through their own venue.
  assert.equal(await errorOf(setCourtHours(owner, otherCourt, [])), 'not_allowed');
  assert.equal(await errorOf(setPricing(owner, otherCourt, 60, 1000, [])), 'not_allowed');
  assert.equal(await errorOf(dashboard(owner, venueId, otherCourt, monday, sunday)), 'not_found');
  assert.deepEqual(await snapshot(), before);
});

test('an admin changes any venue', async () => {
  await setVenueHours(admin, otherVenueId, week({ 7: null }));
  await setCourtHours(admin, otherCourt, [{ weekday: 1, open_minute: 600, close_minute: 900 }]);
  await setPricing(admin, otherCourt, 60, 50000, []);
  assert.equal((await slots(otherCourt, monday)).length, 5);
  assert.equal((await slots(otherCourt, sunday)).length, 0);
  assert.equal((await dashboard(admin, otherVenueId, null, monday, monday)).slots_available, 5);
  assert.deepEqual(
    (await auditRows()).map((r) => [r.actor_id, r.action]),
    [
      [admin, 'set_venue_hours'],
      [admin, 'set_court_hours'],
      [admin, 'set_court_pricing'],
    ],
  );
  assert.equal(await errorOf(setVenueHours(admin, randomUUID(), week())), 'not_found');
  assert.equal(await errorOf(setCourtHours(admin, randomUUID(), [])), 'not_found');
  assert.equal(await errorOf(setPricing(admin, randomUUID(), 60, 1000, [])), 'not_found');
  assert.equal(await errorOf(dashboard(admin, randomUUID(), null, monday, sunday)), 'not_found');
  // Put the shared venue back for the other tests.
  await setVenueHours(admin, otherVenueId, week());
  await setCourtHours(admin, otherCourt, []);
  await setPricing(admin, otherCourt, 90, 180000, []);
});

// ---------------------------------------------------------------------------
// Dashboard
// ---------------------------------------------------------------------------

test('dashboard: counts, revenue, slots and heatmap for a prepared week', async () => {
  const courtB = await addCourt(pool, venueId);
  const appPaid = await book(ali, court, [at(monday, 7)]);
  await setStatus(appPaid, 'paid', 'paid');
  await walkIn(court, [at(monday, 10)]); // confirmed
  const unverified = await walkIn(court, [at(tuesday, 17, 30)]);
  await setStatus(unverified, 'unverified');
  const noShow = await book(vali, court, [at('2026-11-25', 7)]);
  await setStatus(noShow, 'no_show');
  const cancelled = await walkIn(court, [at('2026-11-26', 7)]);
  await setStatus(cancelled, 'cancelled_by_venue');
  await blockSlots(court, [at('2026-11-27', 7), at('2026-11-27', 8, 30)]);
  await hold(ali, court, [at(saturday, 7)]); // a live hold is not a booking
  const paidB = await walkIn(courtB, [at(monday, 7), at(monday, 8, 30)]);
  await setStatus(paidB, 'paid', 'paid');
  await walkIn(court, [at('2026-11-30', 7)]); // the next week

  assert.deepEqual(await dashboard(owner, venueId, null, monday, sunday), {
    currency: 'UZS',
    days: 7,
    bookings_app: 2,
    bookings_walk_in: 3,
    revenue_paid: 180000 + 360000,
    revenue_unconfirmed: 180000,
    no_shows: 1,
    slots_available: 2 * 7 * 10 - 2,
    slots_booked: 6,
    heatmap: [
      { weekday: 1, hour: 7, count: 2 },
      { weekday: 1, hour: 10, count: 1 },
      { weekday: 2, hour: 17, count: 1 },
      { weekday: 3, hour: 7, count: 1 },
    ],
  });

  assert.deepEqual(await dashboard(owner, venueId, court, monday, sunday), {
    currency: 'UZS',
    days: 7,
    bookings_app: 2,
    bookings_walk_in: 2,
    revenue_paid: 180000,
    revenue_unconfirmed: 180000,
    no_shows: 1,
    slots_available: 7 * 10 - 2,
    slots_booked: 4,
    heatmap: [
      { weekday: 1, hour: 7, count: 1 },
      { weekday: 1, hour: 10, count: 1 },
      { weekday: 2, hour: 17, count: 1 },
      { weekday: 3, hour: 7, count: 1 },
    ],
  });

  const b = await dashboard(owner, venueId, courtB, monday, sunday);
  assert.deepEqual(
    [b.bookings_app, b.bookings_walk_in, b.revenue_paid, b.slots_booked, b.slots_available, b.heatmap],
    [0, 1, 360000, 2, 70, [{ weekday: 1, hour: 7, count: 1 }]],
  );

  const mondayOnly = await dashboard(owner, venueId, null, monday, monday);
  assert.deepEqual(
    [mondayOnly.days, mondayOnly.bookings_app, mondayOnly.bookings_walk_in, mondayOnly.slots_booked, mondayOnly.slots_available],
    [1, 1, 2, 4, 20],
  );

  const empty = await dashboard(owner, venueId, null, '2026-12-14', '2026-12-14');
  assert.deepEqual([empty.bookings_app, empty.revenue_paid, empty.slots_booked, empty.heatmap], [0, 0, 0, []]);

  // Reading the dashboard writes nothing: only the bookings' own owner writes are logged.
  const actions = (await auditRows()).map((r) => r.action);
  assert.ok(!actions.some((a) => a.includes('dashboard')));
});

test('dashboard: the range is inclusive, at most 92 days', async () => {
  assert.equal((await dashboard(owner, venueId, null, monday, '2027-02-22')).days, 92);
  assert.equal(await errorOf(dashboard(owner, venueId, null, monday, '2027-02-23')), 'invalid_argument');
  assert.equal(await errorOf(dashboard(owner, venueId, null, sunday, monday)), 'invalid_argument');
  assert.equal(await errorOf(dashboard(owner, venueId, null, null, monday)), 'invalid_argument');
  assert.equal(await errorOf(dashboard(owner, venueId, null, monday, null)), 'invalid_argument');
});

// ---------------------------------------------------------------------------
// Through the API
// ---------------------------------------------------------------------------

const rpc = (client, name, args) => client.query(`select public.${name}(${args.map((_, i) => `$${i + 1}`).join(', ')}) as r`, args);

test('the public functions act as the signed-in user', async () => {
  await asUser(pool, owner, (c) => rpc(c, 'owner_set_venue_hours', [venueId, JSON.stringify(week({ 7: null }))]));
  await asUser(pool, owner, (c) =>
    rpc(c, 'owner_set_court_hours', [court, JSON.stringify([{ weekday: 1, open_minute: 600, close_minute: 900 }])]),
  );
  await asUser(pool, owner, (c) => rpc(c, 'owner_set_court_pricing', [court, 60, 70000, JSON.stringify(goodRules)]));
  assert.equal((await slots(court, monday)).length, 5);
  assert.equal((await slots(court, sunday)).length, 0);
  assert.equal((await pricingOf(court)).court.base_price, 70000);
  const d = (await asUser(pool, owner, (c) => rpc(c, 'owner_dashboard', [venueId, null, monday, monday]))).rows[0].r;
  assert.equal(d.slots_available, 5);
  assert.equal(d.currency, 'UZS');
  assert.deepEqual(
    (await auditRows()).map((r) => [r.actor_id, r.action]),
    [
      [owner, 'set_venue_hours'],
      [owner, 'set_court_hours'],
      [owner, 'set_court_pricing'],
    ],
  );
  assert.equal(
    await errorOf(asUser(pool, owner, (c) => rpc(c, 'owner_set_court_pricing', [court, 60, 70000, JSON.stringify([goodRules[0], goodRules[0]])]))),
    'rules_overlap',
  );
  assert.equal(
    await errorOf(asUser(pool, vali, (c) => rpc(c, 'owner_set_venue_hours', [venueId, JSON.stringify(week())]))),
    'not_allowed',
  );
  assert.equal(await errorOf(asUser(pool, vali, (c) => rpc(c, 'owner_set_court_hours', [court, '[]']))), 'not_allowed');
  assert.equal(
    await errorOf(asUser(pool, vali, (c) => rpc(c, 'owner_set_court_pricing', [court, 60, 1, '[]']))),
    'not_allowed',
  );
  assert.equal(await errorOf(asUser(pool, vali, (c) => rpc(c, 'owner_dashboard', [venueId, null, monday, monday]))), 'not_allowed');
});

test('visitors cannot call the settings functions', async () => {
  const calls = [
    ['owner_set_venue_hours', [venueId, JSON.stringify(week())]],
    ['owner_set_court_hours', [court, '[]']],
    ['owner_set_court_pricing', [court, 60, 1, '[]']],
    ['owner_dashboard', [venueId, null, monday, monday]],
  ];
  for (const [name, args] of calls) {
    await expectError(
      asAnon(pool, (c) => rpc(c, name, args)),
      '42501',
    );
  }
  for (const fn of [
    'public.owner_set_venue_hours(uuid, jsonb)',
    'public.owner_set_court_hours(uuid, jsonb)',
    'public.owner_set_court_pricing(uuid, integer, integer, jsonb)',
    'public.owner_dashboard(uuid, uuid, date, date)',
  ]) {
    const { rows } = await pool.query(
      `select has_function_privilege('anon', $1, 'execute') as anon,
              has_function_privilege('authenticated', $1, 'execute') as authed,
              has_function_privilege('service_role', $1, 'execute') as service`,
      [fn],
    );
    assert.deepEqual(rows[0], { anon: false, authed: true, service: true }, fn);
  }
  await expectError(
    asUser(pool, owner, (c) => c.query(`select app.owner_set_court_pricing($1, $2, 60, 1, '[]', now())`, [owner, court])),
    '42501',
  );
});
