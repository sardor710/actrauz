// supabase/seed.sql must give a new database the same content as the app's
// sample data (app/lib/data/sample/sample_data.dart).

import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { after, before, test } from 'node:test';
import { freshDb } from './helpers/db.mjs';

let db;
let pool;
let seed;

const count = async (sql, params) => (await pool.query(`select count(*)::int as n from ${sql}`, params)).rows[0].n;

before(async () => {
  db = await freshDb('seed');
  pool = db.pool;
  seed = await readFile(path.join(process.env.ACTRA_ROOT, 'seed.sql'), 'utf8');
  await pool.query(seed);
});
after(() => db.end());

test('three cities, five sports plus running and gym, six venues (3 / 2 / 1), fourteen courts', async () => {
  assert.equal(await count('cities'), 3);
  assert.equal(await count('sports'), 7);
  assert.equal(await count('courts'), 14);
  const { rows } = await pool.query(`select city_id, count(*)::int as n from venues group by city_id order by city_id`);
  assert.deepEqual(rows, [
    { city_id: 'almaty', n: 2 },
    { city_id: 'astana', n: 1 },
    { city_id: 'tashkent', n: 3 },
  ]);
  const cities = await pool.query(`select id, currency, utc_offset_minutes from cities order by id`);
  assert.deepEqual(cities.rows, [
    { id: 'almaty', currency: 'KZT', utc_offset_minutes: 300 },
    { id: 'astana', currency: 'KZT', utc_offset_minutes: 300 },
    { id: 'tashkent', currency: 'UZS', utc_offset_minutes: 300 },
  ]);
});

test('every text shown for a venue exists in all three languages', async () => {
  const fields = ['name', 'description', 'address', 'district'].flatMap((f) => [`${f}_uz`, `${f}_ru`, `${f}_en`]);
  const blank = fields.map((f) => `coalesce(${f}, '') = ''`).join(' or ');
  assert.equal(await count(`venues where ${blank}`), 0);
  const noName = `coalesce(name_uz, '') = '' or coalesce(name_ru, '') = '' or coalesce(name_en, '') = ''`;
  assert.equal(await count(`courts where ${noName}`), 0);
  assert.equal(await count(`sports where ${noName}`), 0);
  const { rows } = await pool.query(`select description_uz, address_ru from venues where name_en = 'Bunyod Football Park'`);
  assert.equal(rows[0].description_uz, 'Sunʼiy qoplamali ikki maydon: 5×5 va 7×7. Kechki oʻyinlar uchun yoritish bor.');
  assert.equal(rows[0].address_ru, 'улица Катартал, 48');
});

test('prices and slots match the sample: Lochin court 1 on a Monday and a Saturday', async () => {
  const court = `md5('actra:v1c1')::uuid`;
  const mondaySlots = (await pool.query(`select * from app.court_slots(${court}, '2026-11-23')`)).rows;
  assert.equal(mondaySlots.length, 10);
  assert.equal(mondaySlots[0].starts_local, '2026-11-23T07:00:00');
  assert.equal(mondaySlots[0].price, 180000);
  // 17:30 starts before the evening rule, 19:00 is inside it.
  assert.equal(mondaySlots.find((s) => s.starts_local === '2026-11-23T17:30:00').price, 180000);
  assert.equal(mondaySlots.find((s) => s.starts_local === '2026-11-23T19:00:00').price, 250000);
  const saturday = (await pool.query(`select distinct price from app.court_slots(${court}, '2026-11-28')`)).rows;
  assert.deepEqual(saturday, [{ price: 300000 }]);
});

test('hours match the sample: late closing, a closed Sunday, a court closed on Mondays', async () => {
  const slots = async (courtSampleId, date) =>
    (await pool.query(`select * from app.court_slots(md5('actra:' || $1)::uuid, $2::date)`, [courtSampleId, date])).rows;
  // Bunyod: weekdays 08:00-24:00, 60-minute slots -> the last one ends at midnight.
  const bunyod = await slots('v2c1', '2026-11-23');
  assert.equal(bunyod.length, 16);
  assert.equal(bunyod.at(-1).ends_local, '2026-11-24T00:00:00');
  // Zhetisu Arena is closed on Sundays; Saturday is 09:00-20:00.
  assert.equal((await slots('v5c1', '2026-11-29')).length, 0);
  assert.equal((await slots('v5c1', '2026-11-28')).length, 11);
  // Semurg's basketball court is closed on Mondays although the venue is open.
  assert.equal((await slots('v3c3', '2026-11-23')).length, 0);
  assert.equal((await slots('v3c1', '2026-11-23')).length, 16);
  assert.equal((await slots('v3c3', '2026-11-24')).length, 16);
});

test('every court plays a known sport and has slots this week', async () => {
  const { rows } = await pool.query(`
    select c.id,
           (select count(*)::int from generate_series(0, 6) d, app.court_slots(c.id, current_date + d)) as slots
    from courts c join sports s on s.id = c.sport_id`);
  assert.equal(rows.length, 14);
  for (const row of rows) assert.ok(row.slots > 0, row.id);
});

test('banners, tournaments and players are there', async () => {
  assert.equal(await count('banners'), 2);
  assert.equal(await count('tournaments'), 3);
  assert.equal(await count('tournaments where ends_on < starts_on or starts_on <= current_date'), 0);
  assert.equal(await count('profiles'), 8);
  assert.equal(await count('player_levels'), 12);
  const { rows } = await pool.query(
    `select t.ends_on - t.starts_on as days, v.name_en
     from tournaments t join venues v on v.id = t.venue_id where t.title_en = 'Almaty Open Tennis'`,
  );
  assert.deepEqual(rows, [{ days: 2, name_en: 'Alatau Padel & Tennis' }]);
});

test('tournaments have their categories and a deadline; the summary columns are real counts', async () => {
  assert.equal(await count('tournament_categories'), 6);
  const { rows } = await pool.query(`
    select t.title_en, t.min_fee, t.max_fee, t.slots_total, t.slots_filled,
           (select min(c.fee) from tournament_categories c where c.tournament_id = t.id) as fee_min,
           (select max(c.fee) from tournament_categories c where c.tournament_id = t.id) as fee_max,
           (select sum(c.cap)::int from tournament_categories c where c.tournament_id = t.id) as cap_sum,
           (select count(*)::int from tournament_categories c where c.tournament_id = t.id) as categories,
           t.registration_deadline > now() as deadline_ahead,
           t.registration_deadline < app.to_instant(t.starts_on::timestamp, ci.utc_offset_minutes) as deadline_before_start
    from tournaments t join cities ci on ci.id = t.city_id order by t.title_en`);
  assert.deepEqual(
    rows.map((r) => [r.title_en, r.categories, r.slots_total, r.slots_filled]),
    [
      ['Almaty Open Tennis', 2, 24, 0],
      ['Amateur 5-a-side League', 1, 12, 0],
      ['Tashkent Padel Cup', 3, 32, 0],
    ],
  );
  for (const r of rows) {
    assert.equal(r.min_fee, r.fee_min, r.title_en);
    assert.equal(r.max_fee, r.fee_max, r.title_en);
    assert.equal(r.slots_total, r.cap_sum, r.title_en);
    assert.ok(r.deadline_ahead && r.deadline_before_start, r.title_en);
  }
});

test('the first category of each tournament has the id the tournaments migration gives its default one', async () => {
  const { rows } = await pool.query(`
    select t.title_en, c.id = md5('actra:default-category:' || t.id::text)::uuid as is_default
    from tournaments t join tournament_categories c on c.tournament_id = t.id and c.sort_order = 0`);
  assert.equal(rows.length, 3);
  for (const r of rows) assert.ok(r.is_default, r.title_en);
});

test('a seed run updates the default category the migration made instead of adding a second', async () => {
  const other = await freshDb('seed_backfill');
  try {
    await other.pool.query(seed);
    // A database whose tournaments predate categories: the migration's backfill
    // gives each one open singles category under the default id.
    await other.pool.query('delete from tournament_categories');
    await other.pool.query('select app.backfill_tournaments()');
    const backfilled = await other.pool.query(
      `select c.name_en, c.cap from tournament_categories c join tournaments t on t.id = c.tournament_id
       where t.title_en = 'Tashkent Padel Cup'`,
    );
    assert.deepEqual(backfilled.rows.map((r) => r.name_en), ['Open']);

    await other.pool.query(seed);
    const { rows } = await other.pool.query(
      `select t.title_en, count(*)::int as n, bool_or(c.name_en = 'Open pairs') as updated
       from tournaments t join tournament_categories c on c.tournament_id = t.id group by t.title_en order by t.title_en`,
    );
    assert.deepEqual(rows, [
      { title_en: 'Almaty Open Tennis', n: 2, updated: false },
      { title_en: 'Amateur 5-a-side League', n: 1, updated: false },
      { title_en: 'Tashkent Padel Cup', n: 3, updated: true },
    ]);
  } finally {
    await other.end();
  }
});

test('sample games sit on real bookings and are not over capacity', async () => {
  const { rows } = await pool.query(`
    select g.id, g.spots, g.price_per_player, b.status, b.total_price, b.court_id, b.user_id, g.host_id,
           app.to_local(lower(g.during), g.utc_offset_minutes) as starts_local,
           (select count(*)::int from game_participants p where p.game_id = g.id) as players
    from games g join bookings b on b.id = g.booking_id`);
  assert.ok(rows.length >= 4, `only ${rows.length} games`);
  for (const game of rows) {
    assert.ok(game.players <= game.spots);
    assert.equal(game.status, 'confirmed');
    assert.equal(game.user_id, game.host_id);
    assert.equal(game.price_per_player, Math.round(game.total_price / game.spots));
    const day = await pool.query(`select * from app.court_availability(null, $1, $2::date, now())`, [
      game.court_id,
      game.starts_local.slice(0, 10),
    ]);
    assert.equal(day.rows.find((s) => s.starts_local === game.starts_local).state, 'taken');
  }
});

test('the full sample game is hidden from discovery, as in the app', async () => {
  const { rows } = await pool.query(`select app.list_games(null, 'tashkent', now()) as g`);
  const ids = rows.map((r) => r.g.id);
  const full = (await pool.query(`select md5('actra:g4')::uuid as id`)).rows[0].id;
  assert.ok(!ids.includes(full));
  assert.ok(ids.length >= 1);
});

test('running the seed again changes nothing', async () => {
  const tables = [
    'cities', 'sports', 'venues', 'courts', 'working_hours', 'price_rules', 'banners',
    'tournaments', 'tournament_categories', 'profiles', 'player_levels', 'games', 'game_participants', 'bookings',
  ];
  const snapshot = async () => {
    const counts = {};
    for (const t of tables) counts[t] = await count(t);
    return counts;
  };
  const first = await snapshot();
  await pool.query(seed);
  assert.deepEqual(await snapshot(), first);
  assert.equal(await count(`bookings where status = 'confirmed'`), first.games);
});
