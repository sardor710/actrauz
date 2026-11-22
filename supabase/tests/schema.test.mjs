import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { after, before, test } from 'node:test';
import { asAnon, asUser, createUser, expectError, freshDb } from './helpers/db.mjs';
import { addCourt, addVenue } from './helpers/fixtures.mjs';

let db;
let ali;
let vali;
let venueId;

before(async () => {
  db = await freshDb('schema');
  ali = await createUser(db.pool, 'Ali');
  vali = await createUser(db.pool, 'Vali');
  venueId = await addVenue(db.pool);
  await db.pool.query(`insert into profile_contacts (user_id, phone) values ($1, '+998901111111'), ($2, '+998902222222')`, [
    ali,
    vali,
  ]);
  await db.pool.query(`insert into sports (id, name_en, icon_key) values ('padel', 'Padel', 'padel') on conflict do nothing`);
});
after(() => db.end());

const catalog = ['cities', 'sports', 'venues', 'courts', 'working_hours', 'price_rules', 'banners', 'tournaments'];

test('a visitor can read every catalog table', async () => {
  await asAnon(db.pool, async (c) => {
    for (const table of catalog) await c.query(`select * from ${table} limit 1`);
    assert.equal((await c.query('select count(*)::int as n from venues')).rows[0].n, 1);
  });
});

test('nobody can write the catalog through the API', async () => {
  const insert = (c) => c.query(`insert into venues (city_id, name_en) values ('tashkent', 'Mine')`);
  await expectError(asAnon(db.pool, insert), '42501');
  await expectError(asUser(db.pool, ali, insert), '42501');
  await expectError(
    asUser(db.pool, ali, (c) => c.query(`update courts set base_price = 1`)),
    '42501',
  );
});

test('an inactive venue is hidden', async () => {
  const hidden = await addVenue(db.pool, { name: 'Hidden' });
  await db.pool.query('update venues set active = false where id = $1', [hidden]);
  const ids = await asAnon(db.pool, async (c) => (await c.query('select id from venues')).rows.map((r) => r.id));
  assert.ok(!ids.includes(hidden));
  assert.ok(ids.includes(venueId));
});

test('a player edits their own profile and nobody else\'s', async () => {
  await asUser(db.pool, ali, async (c) => {
    assert.equal((await c.query(`update profiles set full_name = 'Hacked' where id = $1`, [vali])).rowCount, 0);
    assert.equal((await c.query(`update profiles set full_name = 'Ali B' where id = $1`, [ali])).rowCount, 1);
    // Other players' names are visible (games show who is playing).
    assert.equal((await c.query('select count(*)::int as n from profiles')).rows[0].n, 2);
  });
  const { rows } = await db.pool.query('select full_name from profiles where id = $1', [vali]);
  assert.equal(rows[0].full_name, 'Vali');
});

test('a player cannot create a profile for another id', async () => {
  await expectError(
    asUser(db.pool, ali, (c) => c.query(`insert into profiles (id, full_name) values ($1, 'Ghost')`, [randomUUID()])),
    '42501',
  );
});

test('a player sees only their own phone number', async () => {
  const phones = await asUser(db.pool, ali, async (c) => (await c.query('select phone from profile_contacts')).rows);
  assert.deepEqual(phones, [{ phone: '+998901111111' }]);
  await expectError(
    asUser(db.pool, ali, (c) => c.query(`update profile_contacts set phone = '+998903333333'`)),
    '42501',
  );
  await expectError(
    asAnon(db.pool, (c) => c.query('select * from profile_contacts')),
    '42501',
  );
});

test('levels are set by their owner only', async () => {
  await asUser(db.pool, ali, (c) =>
    c.query(`insert into player_levels (user_id, sport_id, level) values ($1, 'padel', 3)`, [ali]),
  );
  await expectError(
    asUser(db.pool, ali, (c) => c.query(`insert into player_levels (user_id, sport_id, level) values ($1, 'padel', 5)`, [vali])),
    '42501',
  );
  const seen = await asUser(db.pool, vali, async (c) => (await c.query('select level from player_levels')).rows);
  assert.deepEqual(seen, [{ level: 3 }]);
});

test('login tokens are invisible to the app', async () => {
  await db.pool.query(
    `insert into login_tokens (token, poll_secret_hash, expires_at) values ('t1', 'h', now() + interval '10 minutes')`,
  );
  await expectError(
    asUser(db.pool, ali, (c) => c.query('select * from login_tokens')),
    '42501',
  );
  await expectError(
    asAnon(db.pool, (c) => c.query('select * from login_tokens')),
    '42501',
  );
});

test('hours belong to a venue or a court, never both or neither', async () => {
  const courtId = await addCourt(db.pool, venueId);
  await expectError(
    db.pool.query(`insert into working_hours (venue_id, court_id, weekday) values ($1, $2, 1)`, [venueId, courtId]),
    '23514',
  );
  await expectError(db.pool.query(`insert into working_hours (weekday) values (1)`), '23514');
});

test('slot length is 60, 90 or 120 minutes', async () => {
  await expectError(
    db.pool.query(
      `insert into courts (venue_id, sport_id, name_en, slot_minutes, base_price) values ($1, 'padel', 'Odd', 45, 1000)`,
      [venueId],
    ),
    '23514',
  );
});

test('a phone number belongs to one account', async () => {
  const third = await createUser(db.pool, 'Third');
  await expectError(
    db.pool.query(`insert into profile_contacts (user_id, phone) values ($1, '+998901111111')`, [third]),
    '23505',
  );
});
