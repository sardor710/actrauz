// Admin functions (Milestone 3c): venues, courts, owners, sports, banners and
// the audit log reader. As elsewhere, the `app` functions are called with the
// acting user and a fixed clock; the last tests go through the `public`
// wrappers as the API would.

import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { after, before, beforeEach, test } from 'node:test';
import { asAnon, asUser, createUser, errorOf, expectError, freshDb } from './helpers/db.mjs';
import { addAdmin, addCourt, addOwner, addPhone, addVenue, at, monday, tashkent } from './helpers/fixtures.mjs';

let db;
let pool;
let admin;
let owner; // owns ownedVenue
let ali; // player with a phone
let vali; // player, no role
let ownedVenue;

const now = tashkent('2026-11-22', 20);
const aliPhone = '+998901111111';

// Every write gets its own instant, so the audit log has a clear order.
let clock = 0;
const tick = () => new Date(Date.UTC(2026, 10, 22, 6, 0, clock++)).toISOString();

before(async () => {
  db = await freshDb('admin');
  pool = db.pool;
  admin = await addAdmin(pool, await createUser(pool, 'Admin'));
  ownedVenue = await addVenue(pool, { name: 'Owned venue' });
  owner = await addOwner(pool, ownedVenue, await createUser(pool, 'Owner'));
  ali = await addPhone(pool, await createUser(pool, 'Ali Valiyev'), aliPhone);
  vali = await createUser(pool, 'Vali');
});
after(() => db.end());

beforeEach(async () => {
  await pool.query('delete from audit_log');
});

const json = (value) => (value === null || typeof value === 'string' ? value : JSON.stringify(value));
const one = async (sql, params) => (await pool.query(sql, params)).rows[0];
const scalar = async (sql, params) => (await one(sql, params))?.r;
const list = async (sql, params) => (await pool.query(sql, params)).rows.map((row) => row.r);

const listVenues = (user) => list(`select app.admin_list_venues($1) as r`, [user]);
const saveVenue = (user, venue, when = tick()) => scalar(`select app.admin_save_venue($1, $2::jsonb, $3) as r`, [user, json(venue), when]);
const saveCourt = (user, court, when = tick()) => scalar(`select app.admin_save_court($1, $2::jsonb, $3) as r`, [user, json(court), when]);
const duplicateCourt = (user, id, when = tick()) => scalar(`select app.admin_duplicate_court($1, $2, $3) as r`, [user, id, when]);
const deleteCourt = (user, id, when = tick()) => scalar(`select app.admin_delete_court($1, $2, $3) as r`, [user, id, when]);
const deleteVenue = (user, id, when = tick()) => scalar(`select app.admin_delete_venue($1, $2, $3) as r`, [user, id, when]);
const searchUsers = (user, query) => list(`select app.admin_search_users($1, $2) as r`, [user, query]);
const setOwner = (user, venue, target, assigned, when = tick()) =>
  scalar(`select app.admin_set_owner($1, $2, $3, $4, $5) as r`, [user, venue, target, assigned, when]);
const listSports = (user) => list(`select app.admin_list_sports($1) as r`, [user]);
const saveSport = (user, sport, create, when = tick()) =>
  scalar(`select app.admin_save_sport($1, $2::jsonb, $3, $4) as r`, [user, json(sport), create, when]);
const listBanners = (user) => list(`select app.admin_list_banners($1) as r`, [user]);
const saveBanner = (user, banner, when = tick()) => scalar(`select app.admin_save_banner($1, $2::jsonb, $3) as r`, [user, json(banner), when]);
const deleteBanner = (user, id, when = tick()) => scalar(`select app.admin_delete_banner($1, $2, $3) as r`, [user, id, when]);
const auditLog = (user, limit, beforeAt = null) => list(`select app.admin_audit_log($1, $2, $3) as r`, [user, limit, beforeAt]);

const auditRows = async () =>
  (await pool.query(`select actor_id, action, entity, entity_id, before, after from audit_log order by id`)).rows;

const venueOf = async (id) => (await listVenues(admin)).find((v) => v.id === id);

const fullVenue = {
  city_id: 'tashkent',
  name_uz: 'Yangi maydon',
  name_ru: 'Новая площадка',
  name_en: 'New venue',
  description_uz: null,
  description_ru: 'Описание',
  description_en: 'Description',
  address_uz: null,
  address_ru: 'ул. Навои, 1',
  address_en: '1 Navoi St',
  district_uz: null,
  district_ru: 'Юнусабад',
  district_en: 'Yunusabad',
  phone: '+998712000000',
  amenities: ['showers', 'parking'],
  active: true,
};

const newVenue = async (overrides = {}) => saveVenue(admin, { ...fullVenue, ...overrides });
const newCourt = async (venueId, overrides = {}) =>
  saveCourt(admin, {
    venue_id: venueId,
    sport_id: 'padel',
    name_uz: 'Kort 1',
    name_ru: 'Корт 1',
    name_en: 'Court 1',
    slot_minutes: 60,
    base_price: 150000,
    indoor: true,
    active: true,
    ...overrides,
  });

// Everything an admin function could change.
const snapshot = async () => {
  const counts = {};
  for (const t of ['venues', 'courts', 'working_hours', 'price_rules', 'venue_owners', 'sports', 'banners', 'audit_log']) {
    counts[t] = (await one(`select count(*)::int as n, md5(coalesce(string_agg(x::text, '|' order by x::text), '')) as h from ${t} x`));
  }
  return counts;
};

// ---------------------------------------------------------------------------
// Who is an admin
// ---------------------------------------------------------------------------

test('am_i_admin is true for admins only; visitors cannot ask', async () => {
  const ask = (user) => asUser(pool, user, async (c) => (await c.query('select public.am_i_admin() as r')).rows[0].r);
  assert.equal(await ask(admin), true);
  assert.equal(await ask(owner), false);
  assert.equal(await ask(vali), false);
  await expectError(
    asAnon(pool, (c) => c.query('select public.am_i_admin()')),
    '42501',
  );
});

test('owners, players and nobody are refused by every admin function; nothing changes, nothing is logged', async () => {
  const courtId = await addCourt(pool, ownedVenue);
  const bannerId = await saveBanner(admin, { url: 'https://example.com', title_en: 'Hello' });
  await pool.query('delete from audit_log');
  const before = await snapshot();
  for (const user of [owner, vali, null]) {
    const refused = async (promise) => assert.equal(await errorOf(promise), 'not_allowed');
    await refused(listVenues(user));
    await refused(saveVenue(user, fullVenue));
    await refused(saveVenue(user, { id: ownedVenue, name_en: 'Mine now' }));
    await refused(saveCourt(user, { id: courtId, base_price: 1 }));
    await refused(duplicateCourt(user, courtId));
    await refused(deleteCourt(user, courtId));
    await refused(deleteVenue(user, ownedVenue));
    await refused(searchUsers(user, 'Ali'));
    await refused(searchUsers(user, '1111'));
    await refused(setOwner(user, ownedVenue, vali, true));
    await refused(listSports(user));
    await refused(saveSport(user, { id: 'squash', name_en: 'Squash', icon_key: 'squash' }, true));
    await refused(listBanners(user));
    await refused(saveBanner(user, { id: bannerId, active: false }));
    await refused(deleteBanner(user, bannerId));
    await refused(auditLog(user, 10));
    // The role check comes before anything else.
    await refused(saveVenue(user, '"not an object"'));
    await refused(saveVenue(user, { typo: 1 }));
    await refused(deleteCourt(user, randomUUID()));
    await refused(auditLog(user, 0));
    await refused(saveSport(user, { id: 'Bad Id' }, null));
  }
  assert.deepEqual(await snapshot(), before);
});

// ---------------------------------------------------------------------------
// Venues
// ---------------------------------------------------------------------------

test('a venue is created with 08:00-22:00 hours, listed newest first, and updated key by key', async () => {
  // Created "later" than every fixture venue, so it must come first.
  const id = await saveVenue(admin, fullVenue, '2030-01-01T00:00:00Z');
  const listed = await listVenues(admin);
  assert.equal(listed[0].id, id);
  const created = listed.map((x) => Date.parse(x.created_at));
  assert.deepEqual(created, [...created].sort((a, b) => b - a));
  const v = listed[0];
  for (const [key, value] of Object.entries(fullVenue)) {
    if (key === 'amenities') continue;
    assert.deepEqual(v[key], value, key);
  }
  assert.deepEqual(v.amenities, ['parking', 'showers']);
  assert.deepEqual(v.courts, []);
  assert.deepEqual(v.owners, []);
  assert.deepEqual(
    v.hours,
    [1, 2, 3, 4, 5, 6, 7].map((weekday) => ({ weekday, closed: false, open_minute: 480, close_minute: 1320 })),
  );
  assert.ok('color_seed' in v && 'created_at' in v);

  assert.equal(await saveVenue(admin, { id, name_ru: '  Другое имя ', amenities: [], description_en: '', active: false }), id);
  const updated = await venueOf(id);
  assert.equal(updated.name_ru, 'Другое имя');
  assert.equal(updated.name_en, 'New venue');
  assert.equal(updated.description_en, null);
  assert.deepEqual(updated.amenities, []);
  assert.equal(updated.active, false);
  assert.equal(updated.phone, '+998712000000');

  const log = await auditRows();
  assert.deepEqual(
    log.map((r) => [r.actor_id, r.action, r.entity, r.entity_id]),
    [
      [admin, 'create_venue', 'venue', id],
      [admin, 'update_venue', 'venue', id],
    ],
  );
  assert.equal(log[0].before, null);
  assert.equal(log[0].after.name_en, 'New venue');
  assert.deepEqual([log[1].before.active, log[1].after.active], [true, false]);
});

test('a venue closed on a weekday lists that day as closed; every venue lists seven days', async () => {
  const id = await newVenue();
  await pool.query(`delete from working_hours where venue_id = $1 and weekday = 7`, [id]);
  const v = await venueOf(id);
  assert.equal(v.hours.length, 7);
  assert.deepEqual(v.hours[6], { weekday: 7, closed: true, open_minute: 0, close_minute: 0 });
});

test('venue validation', async () => {
  const id = await newVenue();
  await pool.query('delete from audit_log');
  const before = await snapshot();
  const bad = [
    null,
    '[]',
    '"x"',
    { name_en: 'No city' },
    { ...fullVenue, city_id: 'atlantis' },
    { ...fullVenue, amenities: ['pool'] },
    { ...fullVenue, amenities: 'parking' },
    { ...fullVenue, typo: true },
    { ...fullVenue, color_seed: 3 },
    { ...fullVenue, name_uz: null, name_ru: ' ', name_en: '' },
    { city_id: 'tashkent' },
    { ...fullVenue, name_en: 'x'.repeat(201) },
    { ...fullVenue, address_en: 'x'.repeat(201) },
    { ...fullVenue, description_en: 'x'.repeat(2001) },
    { ...fullVenue, phone: 998712000000 },
    { ...fullVenue, active: 'yes' },
    { ...fullVenue, active: null },
    { ...fullVenue, city_id: null },
    { id: 'not-a-uuid', name_en: 'x' },
    { id, name_uz: null, name_ru: null, name_en: null },
    { id, city_id: 'atlantis' },
  ];
  for (const venue of bad) {
    assert.equal(await errorOf(saveVenue(admin, venue)), 'invalid_argument', JSON.stringify(venue)?.slice(0, 80));
  }
  assert.equal(await errorOf(saveVenue(admin, { id: randomUUID(), name_en: 'Ghost' })), 'not_found');
  assert.deepEqual(await snapshot(), before);
  // The limits themselves are allowed.
  assert.equal(await saveVenue(admin, { id, name_en: 'x'.repeat(200), description_en: 'y'.repeat(2000) }), id);
});

test('deleting a venue: refused with any booking, allowed without; deactivating is always allowed', async () => {
  const busy = await newVenue();
  const busyCourt = await newCourt(busy);
  const held = await one(`select (app.hold_slots($1, $2, $3::timestamp[], $4)).id`, [vali, busyCourt, [at(monday, 8)], now]);
  await pool.query(`update bookings set status = 'released' where id = $1`, [held.id]);
  assert.equal(await errorOf(deleteVenue(admin, busy)), 'has_bookings');
  assert.equal(await saveVenue(admin, { id: busy, active: false }), busy);
  assert.ok(await venueOf(busy));

  const empty = await newVenue();
  const emptyCourt = await newCourt(empty);
  await setOwner(admin, empty, vali, true);
  await pool.query('delete from audit_log');
  assert.equal(await deleteVenue(admin, empty), '');
  assert.equal(await venueOf(empty), undefined);
  assert.equal((await one(`select count(*)::int as n from courts where id = $1`, [emptyCourt])).n, 0);
  assert.equal((await one(`select count(*)::int as n from working_hours where venue_id = $1`, [empty])).n, 0);
  assert.equal((await one(`select count(*)::int as n from venue_owners where venue_id = $1`, [empty])).n, 0);
  const log = await auditRows();
  assert.deepEqual(
    log.map((r) => [r.action, r.entity, r.entity_id, r.after]),
    [['delete_venue', 'venue', empty, null]],
  );
  assert.equal(log[0].before.id, empty);
  assert.equal(await errorOf(deleteVenue(admin, empty)), 'not_found');
});

// ---------------------------------------------------------------------------
// Courts
// ---------------------------------------------------------------------------

test('a court created by an admin is listed and bookable by a player through the existing functions', async () => {
  const venueId = await newVenue();
  const courtId = await newCourt(venueId);
  const v = await venueOf(venueId);
  assert.equal(v.courts.length, 1);
  const c = v.courts[0];
  assert.deepEqual(
    [c.id, c.venue_id, c.sport_id, c.name_en, c.slot_minutes, c.base_price, c.indoor, c.active, c.hours, c.price_rules],
    [courtId, venueId, 'padel', 'Court 1', 60, 150000, true, true, [], []],
  );

  // 08:00-22:00 in 60-minute slots.
  const { rows } = await pool.query(`select * from app.court_availability($1, $2, $3::date, $4)`, [vali, courtId, monday, now]);
  assert.equal(rows.length, 14);
  assert.equal(rows[0].starts_local, at(monday, 8));
  const held = await one(`select b.* from app.hold_slots($1, $2, $3::timestamp[], $4) b`, [vali, courtId, [at(monday, 8)], now]);
  assert.equal(held.total_price, 150000);
  const confirmed = await one(`select (app.confirm_booking($1, $2, null, null, $3)).status`, [vali, held.id, now]);
  assert.equal(confirmed.status, 'confirmed');
  await pool.query(`update bookings set status = 'cancelled_by_player' where id = $1`, [held.id]);

  // Update key by key.
  assert.equal(await saveCourt(admin, { id: courtId, base_price: 170000, name_ru: null }), courtId);
  const updated = (await venueOf(venueId)).courts[0];
  assert.deepEqual([updated.base_price, updated.name_ru, updated.name_en, updated.slot_minutes], [170000, null, 'Court 1', 60]);
  assert.deepEqual(
    (await auditRows()).map((r) => [r.action, r.entity, r.entity_id]),
    [
      ['create_venue', 'venue', venueId],
      ['create_court', 'court', courtId],
      ['update_court', 'court', courtId],
    ],
  );
});

test('a new court goes after the venue\'s existing courts', async () => {
  const venueId = await newVenue();
  const first = await newCourt(venueId);
  const second = await newCourt(venueId, { name_en: 'Court 2' });
  const { rows } = await pool.query(`select id, sort_order from courts where venue_id = $1 order by sort_order`, [venueId]);
  assert.deepEqual(
    rows.map((r) => r.id),
    [first, second],
  );
  assert.ok(rows[1].sort_order > rows[0].sort_order);
});

test('court validation', async () => {
  const venueId = await newVenue();
  const courtId = await newCourt(venueId);
  const otherVenue = await newVenue();
  await pool.query('delete from audit_log');
  const before = await snapshot();
  const base = { venue_id: venueId, sport_id: 'padel', name_en: 'C', slot_minutes: 90, base_price: 1000, indoor: false, active: true };
  const bad = [
    null,
    { ...base, venue_id: undefined },
    { ...base, venue_id: randomUUID() },
    { ...base, venue_id: 'nope' },
    { ...base, sport_id: 'curling' },
    { ...base, sport_id: undefined },
    { ...base, slot_minutes: 45 },
    { ...base, slot_minutes: undefined },
    { ...base, base_price: -1 },
    { ...base, base_price: 10.5 },
    { ...base, base_price: 50000001 },
    { ...base, base_price: 2147483647 },
    { id: courtId, base_price: 50000001 },
    { ...base, base_price: undefined },
    { ...base, name_en: ' ' },
    { ...base, name_en: 'x'.repeat(201) },
    { ...base, indoor: 1 },
    { ...base, sort_order: 3 },
    { ...base, typo: 'x' },
    { id: courtId, venue_id: otherVenue },
    { id: courtId, name_uz: null, name_ru: null, name_en: null },
  ];
  for (const court of bad) {
    assert.equal(await errorOf(saveCourt(admin, court)), 'invalid_argument', JSON.stringify(court));
  }
  assert.equal(await errorOf(saveCourt(admin, { id: randomUUID(), base_price: 1 })), 'not_found');
  assert.deepEqual(await snapshot(), before);
  // Naming the court's own venue on update is fine.
  assert.equal(await saveCourt(admin, { id: courtId, venue_id: venueId, base_price: 2000 }), courtId);
  // The price cap itself is allowed.
  assert.equal(await saveCourt(admin, { id: courtId, base_price: 50000000 }), courtId);
});

test('a deactivated court disappears from the player reads; its bookings are untouched', async () => {
  const venueId = await newVenue();
  const courtId = await newCourt(venueId);
  const bookingId = (
    await one(`select app.confirm_booking($1, (app.hold_slots($1, $2, $3::timestamp[], $4)).id, 2, null, $4) as b`, [
      ali,
      courtId,
      [at(monday, 10)],
      now,
    ])
  ).b;
  const before = await one(`select * from bookings where court_id = $1`, [courtId]);
  assert.ok(bookingId);

  await saveCourt(admin, { id: courtId, active: false });

  const seen = await asAnon(pool, async (c) => (await c.query('select id from courts where id = $1', [courtId])).rows);
  assert.deepEqual(seen, []);
  const seenSignedIn = await asUser(pool, vali, async (c) => (await c.query('select id from courts where id = $1', [courtId])).rows);
  assert.deepEqual(seenSignedIn, []);
  const day = await asAnon(pool, async (c) =>
    (await c.query('select * from public.court_availability($1, $2::date)', [courtId, monday])).rows,
  );
  assert.deepEqual(day, []);
  assert.equal(await errorOf(one(`select app.hold_slots($1, $2, $3::timestamp[], $4)`, [vali, courtId, [at(monday, 12)], now])), 'not_found');

  assert.deepEqual(await one(`select * from bookings where court_id = $1`, [courtId]), before);
  const mine = await asUser(pool, ali, async (c) => (await c.query('select public.my_bookings() as r')).rows.map((r) => r.r.court_id));
  assert.ok(mine.includes(courtId));
  // Still there for the admin, marked inactive.
  assert.equal((await venueOf(venueId)).courts.find((c) => c.id === courtId).active, false);

  // The same for a venue.
  await saveVenue(admin, { id: venueId, active: false });
  assert.deepEqual(await asAnon(pool, async (c) => (await c.query('select id from venues where id = $1', [venueId])).rows), []);
});

test('duplicating a court copies sport, slot length, prices, rules and hour overrides, right after the original', async () => {
  const venueId = await newVenue();
  const first = await newCourt(venueId, { name_ru: null, slot_minutes: 90, indoor: false });
  const last = await newCourt(venueId, { name_en: 'Court 9' });
  await pool.query(
    `insert into price_rules (court_id, weekdays, from_minute, to_minute, price, sort_order) values
       ($1, '{1,2,3,4,5}', 1080, 1320, 200000, 0), ($1, '{6,7}', 480, 1320, 220000, 1)`,
    [first],
  );
  await pool.query(
    `insert into working_hours (court_id, weekday, closed, open_minute, close_minute) values ($1, 1, true, 0, 0), ($1, 6, false, 600, 1200)`,
    [first],
  );
  await pool.query('delete from audit_log');

  const copy = await duplicateCourt(admin, first);
  assert.notEqual(copy, first);
  const v = await venueOf(venueId);
  assert.deepEqual(
    v.courts.map((c) => c.id),
    [first, copy, last],
  );
  const original = v.courts[0];
  const dup = v.courts[1];
  assert.deepEqual([dup.name_uz, dup.name_ru, dup.name_en], ['Kort 1 2', null, 'Court 1 2']);
  for (const key of ['venue_id', 'sport_id', 'slot_minutes', 'base_price', 'indoor', 'active', 'hours', 'price_rules']) {
    assert.deepEqual(dup[key], original[key], key);
  }
  assert.equal(dup.price_rules.length, 2);
  assert.deepEqual(dup.price_rules[0], { weekdays: [1, 2, 3, 4, 5], from_minute: 1080, to_minute: 1320, price: 200000 });
  assert.equal(dup.hours.length, 2);
  // The copy really offers what the original does.
  const slotsOf = async (id, day) => (await pool.query(`select * from app.court_slots($1, $2::date)`, [id, day])).rows;
  assert.deepEqual(await slotsOf(copy, monday), []);
  assert.deepEqual(await slotsOf(copy, '2026-11-28'), await slotsOf(first, '2026-11-28'));

  assert.deepEqual(
    (await auditRows()).map((r) => [r.actor_id, r.action, r.entity, r.entity_id]),
    [[admin, 'duplicate_court', 'court', copy]],
  );
  assert.equal(await errorOf(duplicateCourt(admin, randomUUID())), 'not_found');
});

test('deleting a court: refused with any booking, allowed without', async () => {
  const venueId = await newVenue();
  const busy = await newCourt(venueId);
  const held = await one(`select (app.hold_slots($1, $2, $3::timestamp[], $4)).id`, [vali, busy, [at(monday, 9)], now]);
  await pool.query(`update bookings set status = 'released' where id = $1`, [held.id]);
  assert.equal(await errorOf(deleteCourt(admin, busy)), 'has_bookings');
  assert.equal(await saveCourt(admin, { id: busy, active: false }), busy);

  const free = await newCourt(venueId);
  await pool.query(`insert into price_rules (court_id, weekdays, from_minute, to_minute, price) values ($1, '{1}', 0, 60, 1)`, [free]);
  await pool.query(`insert into working_hours (court_id, weekday, closed) values ($1, 2, true)`, [free]);
  await pool.query('delete from audit_log');
  assert.equal(await deleteCourt(admin, free), '');
  for (const t of ['courts where id', 'price_rules where court_id', 'working_hours where court_id']) {
    assert.equal((await one(`select count(*)::int as n from ${t} = $1`, [free])).n, 0, t);
  }
  const log = await auditRows();
  assert.deepEqual(
    log.map((r) => [r.action, r.entity, r.entity_id, r.before.id, r.after]),
    [['delete_court', 'court', free, free, null]],
  );
  assert.equal(await errorOf(deleteCourt(admin, free)), 'not_found');
});

// ---------------------------------------------------------------------------
// Owners and user search
// ---------------------------------------------------------------------------

test('user search by name and by phone, at most 20, nothing under 2 characters', async () => {
  const byName = await searchUsers(admin, 'ALI');
  assert.ok(byName.some((u) => u.user_id === ali && u.full_name === 'Ali Valiyev' && u.phone === aliPhone));
  assert.ok(byName.every((u) => u.full_name.toLowerCase().includes('ali')));
  const byPhone = await searchUsers(admin, '90 111');
  assert.deepEqual(
    byPhone.map((u) => u.user_id),
    [ali],
  );
  assert.deepEqual(await searchUsers(admin, '+998 90 111-11-11'), byPhone);
  assert.deepEqual(await searchUsers(admin, 'a'), []);
  assert.deepEqual(await searchUsers(admin, ' a '), []);
  assert.deepEqual(await searchUsers(admin, ''), []);
  assert.deepEqual(await searchUsers(admin, null), []);
  // Wildcards are text, not patterns.
  assert.deepEqual(await searchUsers(admin, '%%'), []);
  assert.deepEqual(await searchUsers(admin, '__'), []);
  const noPhone = (await searchUsers(admin, 'Vali')).find((u) => u.user_id === vali);
  assert.deepEqual(noPhone, { user_id: vali, full_name: 'Vali', phone: null });

  for (let i = 0; i < 25; i++) await createUser(pool, `Manyfold ${String(i).padStart(2, '0')}`);
  assert.equal((await searchUsers(admin, 'manyfold')).length, 20);
});

test('assigning an owner gives them the venue; twice or removing an absent owner is fine', async () => {
  const venueId = await newVenue();
  await pool.query('delete from audit_log');
  const ids = async (user) => (await one(`select to_jsonb(app.my_venue_ids($1)) as ids`, [user])).ids;
  assert.ok(!(await ids(ali)).includes(venueId));

  assert.equal(await setOwner(admin, venueId, ali, true), '');
  await setOwner(admin, venueId, ali, true);
  assert.ok((await ids(ali)).includes(venueId));
  assert.deepEqual((await venueOf(venueId)).owners, [{ user_id: ali, full_name: 'Ali Valiyev', phone: aliPhone }]);
  // Ali can now run the calendar as an owner.
  assert.equal((await one(`select app.owner_calendar($1, $2, $3::date, 1, $4) as c`, [ali, await newCourt(venueId), monday, now])).c.slots.length, 14);

  await setOwner(admin, venueId, ali, false);
  await setOwner(admin, venueId, ali, false);
  assert.ok(!(await ids(ali)).includes(venueId));
  assert.deepEqual((await venueOf(venueId)).owners, []);

  const log = await auditRows();
  assert.deepEqual(
    log.filter((r) => r.entity === 'venue').map((r) => [r.action, r.entity_id, r.after.user_id]),
    [
      ['assign_owner', venueId, ali],
      ['assign_owner', venueId, ali],
      ['remove_owner', venueId, ali],
      ['remove_owner', venueId, ali],
    ],
  );
  assert.equal(await errorOf(setOwner(admin, randomUUID(), ali, true)), 'not_found');
  assert.equal(await errorOf(setOwner(admin, venueId, randomUUID(), true)), 'not_found');
  assert.equal(await errorOf(setOwner(admin, venueId, ali, null)), 'invalid_argument');
});

// ---------------------------------------------------------------------------
// Sports
// ---------------------------------------------------------------------------

test('sports: create, list by sort order, update; inactive ones are hidden from players', async () => {
  const squash = {
    id: 'squash_2',
    name_uz: 'Skvosh',
    name_ru: 'Сквош',
    name_en: 'Squash',
    icon_key: 'squash',
    bookable: true,
    competitive_rating: false,
    default_players: 2,
    sort_order: -5,
    active: true,
  };
  assert.equal(await saveSport(admin, squash, true), 'squash_2');
  const sports = await listSports(admin);
  assert.deepEqual(sports[0], { ...squash, name_kk: null });
  const orders = sports.map((s) => s.sort_order);
  assert.deepEqual(orders, [...orders].sort((a, b) => a - b));

  assert.equal(await errorOf(saveSport(admin, squash, true)), 'already_exists');
  assert.equal(await saveSport(admin, { id: 'squash_2', name_ru: null, active: false, default_players: 4 }, false), 'squash_2');
  const updated = (await listSports(admin)).find((s) => s.id === 'squash_2');
  assert.deepEqual([updated.name_ru, updated.name_en, updated.active, updated.default_players], [null, 'Squash', false, 4]);
  assert.deepEqual(await asAnon(pool, async (c) => (await c.query(`select id from sports where id = 'squash_2'`)).rows), []);

  // Minimal create gets the defaults.
  assert.equal(await saveSport(admin, { id: 'yoga', name_en: 'Yoga', icon_key: 'yoga' }, true), 'yoga');
  const yoga = (await listSports(admin)).find((s) => s.id === 'yoga');
  assert.deepEqual(
    [yoga.bookable, yoga.competitive_rating, yoga.default_players, yoga.sort_order, yoga.active],
    [true, false, 2, 0, true],
  );
  assert.deepEqual(
    (await auditRows()).map((r) => [r.action, r.entity, r.entity_id]),
    [
      ['create_sport', 'sport', 'squash_2'],
      ['update_sport', 'sport', 'squash_2'],
      ['create_sport', 'sport', 'yoga'],
    ],
  );
});

test('sport validation', async () => {
  await pool.query('delete from audit_log');
  const before = await snapshot();
  const ok = { id: 'tennis_x', name_en: 'Tennis', icon_key: 'tennis' };
  for (const [sport, create] of [
    [{ ...ok, id: 'Tennis' }, true],
    [{ ...ok, id: 't' }, true],
    [{ ...ok, id: '1tennis' }, true],
    [{ ...ok, id: 'a'.repeat(31) }, true],
    [{ ...ok, id: undefined }, true],
    [{ ...ok, id: undefined }, false],
    [{ ...ok, icon_key: undefined }, true],
    [{ ...ok, name_en: null }, true],
    [{ ...ok, default_players: 0 }, true],
    [{ ...ok, bookable: 'true' }, true],
    [{ ...ok, color: 'red' }, true],
    [ok, null],
    ['[]', true],
  ]) {
    assert.equal(await errorOf(saveSport(admin, sport, create)), 'invalid_argument', JSON.stringify([sport, create]));
  }
  assert.equal(await errorOf(saveSport(admin, { id: 'no_such_sport', name_en: 'X' }, false)), 'not_found');
  assert.equal(await errorOf(saveSport(admin, { id: 'padel', name_en: 'Padel', icon_key: 'padel' }, true)), 'already_exists');
  assert.deepEqual(await snapshot(), before);
});

// ---------------------------------------------------------------------------
// Banners
// ---------------------------------------------------------------------------

test('banners: create, list, update, delete; inactive ones are hidden from players', async () => {
  const banner = {
    city_id: 'tashkent',
    title_uz: 'Sarlavha',
    title_ru: 'Заголовок',
    title_en: 'Title',
    subtitle_uz: null,
    subtitle_ru: 'Подзаголовок',
    subtitle_en: 'Subtitle',
    url: 'https://actra.uz/promo',
    sort_order: -10,
    active: true,
  };
  const id = await saveBanner(admin, banner);
  const listed = await listBanners(admin);
  assert.equal(listed[0].id, id);
  for (const [key, value] of Object.entries(banner)) assert.deepEqual(listed[0][key], value, key);

  assert.equal(await saveBanner(admin, { id, city_id: null, active: false }), id);
  const updated = (await listBanners(admin)).find((b) => b.id === id);
  assert.deepEqual([updated.city_id, updated.active, updated.title_en], [null, false, 'Title']);
  assert.deepEqual(await asAnon(pool, async (c) => (await c.query('select id from banners where id = $1', [id])).rows), []);

  assert.equal(await deleteBanner(admin, id), '');
  assert.equal((await listBanners(admin)).find((b) => b.id === id), undefined);
  assert.equal(await errorOf(deleteBanner(admin, id)), 'not_found');
  assert.deepEqual(
    (await auditRows()).map((r) => [r.action, r.entity, r.entity_id]),
    [
      ['create_banner', 'banner', id],
      ['update_banner', 'banner', id],
      ['delete_banner', 'banner', id],
    ],
  );
});

test('banner validation', async () => {
  const id = await saveBanner(admin, { url: 'https://example.com', title_en: 'T' });
  await pool.query('delete from audit_log');
  const before = await snapshot();
  const ok = { url: 'https://example.com/x', title_en: 'T' };
  for (const banner of [
    { ...ok, url: 'http://example.com' },
    { ...ok, url: 'https://' },
    { ...ok, url: 'https://exa mple.com' },
    { ...ok, url: 'javascript:alert(1)' },
    { ...ok, url: `https://example.com/${'x'.repeat(200)}` },
    { title_en: 'No url' },
    { ...ok, title_en: null },
    { ...ok, city_id: 'atlantis' },
    { ...ok, sort_order: '1' },
    { ...ok, image: 'x.png' },
    { id, url: 'ftp://x' },
    { id, title_uz: null, title_ru: null, title_en: null },
  ]) {
    assert.equal(await errorOf(saveBanner(admin, banner)), 'invalid_argument', JSON.stringify(banner).slice(0, 80));
  }
  assert.equal(await errorOf(saveBanner(admin, { id: randomUUID(), title_en: 'X' })), 'not_found');
  assert.deepEqual(await snapshot(), before);
});

// ---------------------------------------------------------------------------
// Audit log reader
// ---------------------------------------------------------------------------

test('the audit log reads newest first and pages with p_before', async () => {
  const ids = [];
  for (let i = 0; i < 5; i++) ids.push(await saveBanner(admin, { url: `https://example.com/${i}`, title_en: `B${i}` }));
  const page1 = await auditLog(admin, 2);
  assert.equal(page1.length, 2);
  assert.deepEqual(
    page1.map((e) => e.entity_id),
    [ids[4], ids[3]],
  );
  const e = page1[0];
  assert.deepEqual(Object.keys(e).sort(), ['action', 'actor_name', 'after', 'before', 'created_at', 'entity', 'entity_id', 'id'].sort());
  assert.deepEqual([e.actor_name, e.action, e.entity, e.before], ['Admin', 'create_banner', 'banner', null]);
  assert.equal(typeof e.id, 'string');
  assert.equal(e.after.title_en, 'B4');

  const page2 = await auditLog(admin, 2, page1.at(-1).created_at);
  assert.deepEqual(
    page2.map((x) => x.entity_id),
    [ids[2], ids[1]],
  );
  const page3 = await auditLog(admin, 100, page2.at(-1).created_at);
  assert.deepEqual(
    page3.map((x) => x.entity_id),
    [ids[0]],
  );
  for (const limit of [0, 101, -1, null]) {
    assert.equal(await errorOf(auditLog(admin, limit)), 'invalid_argument');
  }
  // Owner writes show up too, with the owner's name.
  const courtId = await addCourt(pool, ownedVenue);
  await one(`select app.owner_block_slots($1, $2, $3::timestamp[], null, $4)`, [owner, courtId, [at(monday, 7)], tick()]);
  assert.deepEqual(
    (await auditLog(admin, 1)).map((x) => [x.actor_name, x.action]),
    [['Owner', 'block_slots']],
  );
});

// ---------------------------------------------------------------------------
// Through the API
// ---------------------------------------------------------------------------

const rpc = (client, name, args) => client.query(`select public.${name}(${args.map((_, i) => `$${i + 1}`).join(', ')}) as r`, args);
const rows = async (user, name, args) => asUser(pool, user, async (c) => (await rpc(c, name, args)).rows.map((r) => r.r));

test('the public functions act as the signed-in admin; others are refused', async () => {
  const venueId = (await rows(admin, 'admin_save_venue', [JSON.stringify(fullVenue)]))[0];
  const courtId = (
    await rows(admin, 'admin_save_court', [
      JSON.stringify({ venue_id: venueId, sport_id: 'padel', name_en: 'API court', slot_minutes: 90, base_price: 1000, indoor: false, active: true }),
    ])
  )[0];
  const copy = (await rows(admin, 'admin_duplicate_court', [courtId]))[0];
  await rows(admin, 'admin_delete_court', [copy]);
  await rows(admin, 'admin_set_owner', [venueId, vali, true]);
  const venues = await rows(admin, 'admin_list_venues', []);
  const v = venues.find((x) => x.id === venueId);
  assert.deepEqual(
    v.courts.map((c) => c.id),
    [courtId],
  );
  assert.deepEqual(v.owners, [{ user_id: vali, full_name: 'Vali', phone: null }]);
  assert.ok((await rows(admin, 'admin_search_users', ['Ali'])).some((u) => u.phone === aliPhone));
  assert.equal((await rows(admin, 'admin_save_sport', [JSON.stringify({ id: 'api_sport', name_en: 'API', icon_key: 'x' }), true]))[0], 'api_sport');
  assert.ok((await rows(admin, 'admin_list_sports', [])).some((s) => s.id === 'api_sport'));
  const bannerId = (await rows(admin, 'admin_save_banner', [JSON.stringify({ url: 'https://x.uz', title_en: 'API' })]))[0];
  assert.ok((await rows(admin, 'admin_list_banners', [])).some((b) => b.id === bannerId));
  await rows(admin, 'admin_delete_banner', [bannerId]);
  await rows(admin, 'admin_delete_venue', [venueId]).catch((e) => assert.equal(e.message, 'not_found'));
  const log = await rows(admin, 'admin_audit_log', [100, null]);
  assert.deepEqual(
    log.map((e) => e.action).reverse(),
    ['create_venue', 'create_court', 'duplicate_court', 'delete_court', 'assign_owner', 'create_sport', 'create_banner', 'delete_banner', 'delete_venue'],
  );
  assert.ok(log.every((e) => e.actor_name === 'Admin'));

  // Phone numbers and everything else stay with admins.
  for (const user of [owner, vali]) {
    for (const [name, args] of [
      ['admin_list_venues', []],
      ['admin_search_users', ['Ali']],
      ['admin_audit_log', [10, null]],
      ['admin_set_owner', [ownedVenue, user, true]],
      ['admin_save_venue', [JSON.stringify(fullVenue)]],
    ]) {
      assert.equal(await errorOf(rows(user, name, args)), 'not_allowed', `${name} as ${user}`);
    }
  }
});

test('visitors cannot call the admin functions; only signed-in users and the service role may', async () => {
  const signatures = [
    ['am_i_admin', []],
    ['admin_list_venues', []],
    ['admin_save_venue', ['jsonb']],
    ['admin_save_court', ['jsonb']],
    ['admin_duplicate_court', ['uuid']],
    ['admin_delete_court', ['uuid']],
    ['admin_delete_venue', ['uuid']],
    ['admin_search_users', ['text']],
    ['admin_set_owner', ['uuid', 'uuid', 'boolean']],
    ['admin_list_sports', []],
    ['admin_save_sport', ['jsonb', 'boolean']],
    ['admin_list_banners', []],
    ['admin_save_banner', ['jsonb']],
    ['admin_delete_banner', ['uuid']],
    ['admin_audit_log', ['integer', 'timestamptz']],
  ];
  for (const [name, types] of signatures) {
    const fn = `public.${name}(${types.join(', ')})`;
    const { rows: r } = await pool.query(
      `select has_function_privilege('anon', $1, 'execute') as anon,
              has_function_privilege('authenticated', $1, 'execute') as authed,
              has_function_privilege('service_role', $1, 'execute') as service,
              p.prosecdef as definer, p.proconfig as config
       from pg_proc p where p.oid = $1::regprocedure`,
      [fn],
    );
    assert.deepEqual(r[0], { anon: false, authed: true, service: true, definer: true, config: ['search_path=""'] }, fn);
  }
  await expectError(
    asAnon(pool, (c) => c.query('select public.admin_list_venues()')),
    '42501',
  );
  await expectError(
    asUser(pool, admin, (c) => c.query('select app.admin_list_venues($1)', [admin])),
    '42501',
  );
});
