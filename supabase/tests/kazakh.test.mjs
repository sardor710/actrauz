// Milestone 6: Kazakh (kk) as a fourth language: content columns, the
// language checks, and every localized object the database builds.

import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { after, before, test } from 'node:test';
import { createUser, errorOf, freshDb } from './helpers/db.mjs';
import { addAdmin, addCourt, addOwner, addVenue, tashkent } from './helpers/fixtures.mjs';

let db;
let pool;
let admin;
let venueId;

const now = tashkent('2026-11-22', 20);

before(async () => {
  db = await freshDb('kazakh');
  pool = db.pool;
  admin = await addAdmin(pool, await createUser(pool, 'Admin'));
  venueId = await addVenue(pool, { name: 'Test venue' });
});
after(() => db.end());

const one = async (sql, params) => (await pool.query(sql, params)).rows[0];
const scalar = async (sql, params) => (await one(sql, params))?.r;
const keys = (o) => Object.keys(o).sort();

test('kk columns exist: nullable text', async () => {
  const expected = {
    cities: ['name_kk'],
    sports: ['name_kk'],
    venues: ['name_kk', 'description_kk', 'address_kk', 'district_kk'],
    courts: ['name_kk'],
    banners: ['title_kk', 'subtitle_kk'],
    tournaments: ['title_kk', 'description_kk'],
    tournament_categories: ['name_kk'],
  };
  for (const [table, columns] of Object.entries(expected)) {
    for (const column of columns) {
      const row = await one(
        `select data_type, is_nullable from information_schema.columns
         where table_schema = 'public' and table_name = $1 and column_name = $2`,
        [table, column],
      );
      assert.deepEqual(row, { data_type: 'text', is_nullable: 'YES' }, `${table}.${column}`);
    }
  }
});

test('profile and login token accept kk, and reject anything else', async () => {
  const user = await createUser(pool, 'Aigerim');
  await pool.query(`update profiles set language = 'kk' where id = $1`, [user]);
  assert.equal((await one(`select language from profiles where id = $1`, [user])).language, 'kk');
  assert.equal(await errorOf(pool.query(`update profiles set language = 'kz' where id = $1`, [user])), '23514');

  const insert = (token, language) =>
    pool.query(
      `insert into login_tokens (token, poll_secret_hash, language, expires_at)
       values ($1, 'h', $2, now() + interval '10 minutes')`,
      [token, language],
    );
  await insert('kk-token', 'kk');
  assert.equal((await one(`select language from login_tokens where token = 'kk-token'`)).language, 'kk');
  assert.equal(await errorOf(insert('kz-token', 'kz')), '23514');
});

test('a venue, court or category named only in Kazakh satisfies the named checks', async () => {
  const { rows } = await pool.query(`insert into venues (city_id, name_kk) values ('tashkent', 'Алатау') returning id`);
  const venue = rows[0].id;
  await pool.query(`insert into courts (venue_id, sport_id, name_kk, slot_minutes, base_price) values ($1, 'padel', 'Корт', 90, 1)`, [venue]);
  await pool.query(`delete from courts where venue_id = $1`, [venue]);
  await pool.query(`delete from venues where id = $1`, [venue]);
});

test('admin saves kk text for venue, court, sport, banner, tournament and category', async () => {
  const saved = await scalar(
    `select app.admin_save_venue($1, $2::jsonb, $3) as r`,
    [
      admin,
      JSON.stringify({
        city_id: 'almaty',
        name_kk: 'Алатау',
        description_kk: 'Сипаттама',
        address_kk: 'Мекенжай',
        district_kk: 'Ауданы',
      }),
      now,
    ],
  );
  const venue = await one(`select * from venues where id = $1`, [saved]);
  assert.equal(venue.name_kk, 'Алатау');
  assert.equal(venue.description_kk, 'Сипаттама');
  assert.equal(venue.address_kk, 'Мекенжай');
  assert.equal(venue.district_kk, 'Ауданы');
  assert.equal(venue.name_en, null);
  await scalar(`select app.admin_save_venue($1, $2::jsonb, $3) as r`, [admin, JSON.stringify({ id: saved, name_kk: 'Алатау 2' }), now]);
  assert.equal((await one(`select name_kk from venues where id = $1`, [saved])).name_kk, 'Алатау 2');

  const courtId = await scalar(
    `select app.admin_save_court($1, $2::jsonb, $3) as r`,
    [admin, JSON.stringify({ venue_id: saved, sport_id: 'padel', name_kk: 'Бірінші корт', slot_minutes: 90, base_price: 100000 }), now],
  );
  assert.equal((await one(`select name_kk from courts where id = $1`, [courtId])).name_kk, 'Бірінші корт');
  await scalar(`select app.admin_save_court($1, $2::jsonb, $3) as r`, [admin, JSON.stringify({ id: courtId, name_kk: 'Корт А' }), now]);
  assert.equal((await one(`select name_kk from courts where id = $1`, [courtId])).name_kk, 'Корт А');

  const copy = await scalar(`select app.admin_duplicate_court($1, $2, $3) as r`, [admin, courtId, now]);
  assert.equal((await one(`select name_kk from courts where id = $1`, [copy])).name_kk, 'Корт А 2');

  await scalar(`select app.admin_save_sport($1, $2::jsonb, true, $3) as r`, [admin, JSON.stringify({ id: 'archery', name_kk: 'Садақ ату', icon_key: 'archery' }), now]);
  assert.equal((await one(`select name_kk from sports where id = 'archery'`)).name_kk, 'Садақ ату');
  await scalar(`select app.admin_save_sport($1, $2::jsonb, false, $3) as r`, [admin, JSON.stringify({ id: 'archery', name_kk: 'Жебе' }), now]);
  assert.equal((await one(`select name_kk from sports where id = 'archery'`)).name_kk, 'Жебе');

  const banner = await scalar(
    `select app.admin_save_banner($1, $2::jsonb, $3) as r`,
    [admin, JSON.stringify({ title_kk: 'Жаңалық', subtitle_kk: 'Қосымша', url: 'https://example.com' }), now],
  );
  const bannerRow = await one(`select title_kk, subtitle_kk from banners where id = $1`, [banner]);
  assert.deepEqual(bannerRow, { title_kk: 'Жаңалық', subtitle_kk: 'Қосымша' });
  await scalar(`select app.admin_save_banner($1, $2::jsonb, $3) as r`, [admin, JSON.stringify({ id: banner, title_kk: 'Жаңа' }), now]);
  assert.equal((await one(`select title_kk from banners where id = $1`, [banner])).title_kk, 'Жаңа');

  const tournament = await scalar(
    `select app.admin_save_tournament($1, $2::jsonb, $3) as r`,
    [
      admin,
      JSON.stringify({
        city_id: 'almaty',
        sport_id: 'padel',
        title_kk: 'Кубок',
        description_kk: 'Жарыс сипаттамасы',
        starts_on: '2026-12-10',
        ends_on: '2026-12-10',
        categories: [{ name_kk: 'Ашық', kind: 'singles', cap: 8 }],
      }),
      now,
    ],
  );
  const t = await one(`select title_kk, description_kk from tournaments where id = $1`, [tournament]);
  assert.deepEqual(t, { title_kk: 'Кубок', description_kk: 'Жарыс сипаттамасы' });
  assert.equal((await one(`select name_kk from tournament_categories where tournament_id = $1`, [tournament])).name_kk, 'Ашық');
  await scalar(`select app.admin_save_tournament($1, $2::jsonb, $3) as r`, [admin, JSON.stringify({ id: tournament, title_kk: 'Кубок 2' }), now]);
  assert.equal((await one(`select title_kk from tournaments where id = $1`, [tournament])).title_kk, 'Кубок 2');

  const category = await scalar(
    `select app.admin_save_category($1, $2::jsonb, $3) as r`,
    [admin, JSON.stringify({ tournament_id: tournament, name_kk: 'Жұптар', kind: 'pairs', cap: 4 }), now],
  );
  assert.equal((await one(`select name_kk from tournament_categories where id = $1`, [category])).name_kk, 'Жұптар');
  await scalar(`select app.admin_save_category($1, $2::jsonb, $3) as r`, [admin, JSON.stringify({ id: category, name_kk: 'Жұп' }), now]);
  assert.equal((await one(`select name_kk from tournament_categories where id = $1`, [category])).name_kk, 'Жұп');
});

test('an admin save with no name in any language, Kazakh included, is invalid', async () => {
  const error = await errorOf(
    pool.query(`select app.admin_save_venue($1, $2::jsonb, $3)`, [admin, JSON.stringify({ city_id: 'almaty', phone: '+7 700 000 00 00' }), now]),
  );
  assert.equal(error, 'invalid_argument');
});

test('notification payloads carry kk', async () => {
  const owner = await addOwner(pool, venueId, await createUser(pool, 'Owner'));
  const court = await addCourt(pool, venueId);
  await pool.query(`update courts set name_kk = 'Корт' where id = $1`, [court]);
  await pool.query(`update venues set name_kk = 'Алаңы' where id = $1`, [venueId]);
  const player = await createUser(pool, 'Ali');
  const held = await one(`select (app.hold_slots($1, $2, $3::timestamp[], $4)).id`, [player, court, ['2026-11-23T10:00:00'], now]);
  await pool.query(`select app.confirm_booking($1, $2, null, null, $3)`, [player, held.id, now]);
  const { rows } = await pool.query(`select payload from notifications where user_id = $1 and kind = 'venue_new_booking'`, [owner]);
  assert.equal(rows.length, 1);
  assert.deepEqual(keys(rows[0].payload.court_name), ['en', 'kk', 'ru', 'uz']);
  assert.equal(rows[0].payload.court_name.kk, 'Корт');
  const mine = await one(`select payload from notifications where user_id = $1 and kind = 'booking_confirmed'`, [player]);
  assert.deepEqual(keys(mine.payload.venue_name), ['en', 'kk', 'ru', 'uz']);
  assert.equal(mine.payload.venue_name.kk, 'Алаңы');

  const t = await scalar(
    `select app.admin_save_tournament($1, $2::jsonb, $3) as r`,
    [admin, JSON.stringify({ city_id: 'tashkent', sport_id: 'padel', title_kk: 'Кубок', starts_on: '2026-12-10', ends_on: '2026-12-10',
      categories: [{ name_kk: 'Ашық', kind: 'singles', cap: 8 }] }), now],
  );
  const category = (await one(`select id from tournament_categories where tournament_id = $1`, [t])).id;
  await pool.query(`select app.register($1, $2, null, $3)`, [player, category, now]);
  const reg = await one(`select payload from notifications where user_id = $1 and kind = 'tournament_registered'`, [player]);
  assert.deepEqual(keys(reg.payload.title), ['en', 'kk', 'ru', 'uz']);
  assert.deepEqual(keys(reg.payload.category_name), ['en', 'kk', 'ru', 'uz']);
  assert.equal(reg.payload.title.kk, 'Кубок');
  assert.equal(reg.payload.category_name.kk, 'Ашық');
});

test('tournament json carries kk', async () => {
  const t = await scalar(
    `select app.admin_save_tournament($1, $2::jsonb, $3) as r`,
    [admin, JSON.stringify({ city_id: 'tashkent', sport_id: 'padel', title_kk: 'Кубок', description_kk: 'Сипаттама', starts_on: '2026-12-11', ends_on: '2026-12-11',
      categories: [{ name_kk: 'Ашық', kind: 'singles', cap: 8 }] }), now],
  );
  const json = await scalar(`select app.tournament_json(t, null, $2) as r from tournaments t where t.id = $1`, [t, now]);
  assert.equal(json.title_kk, 'Кубок');
  assert.equal(json.description_kk, 'Сипаттама');
  assert.equal(json.categories.length, 1);
  assert.equal(json.categories[0].name_kk, 'Ашық');
  assert.equal(json.title_ru, null);
});

test('list_tournaments sorts a Kazakh reader by Kazakh title', async () => {
  const reader = await createUser(pool, 'Reader');
  await pool.query(`update profiles set language = 'kk', city_id = 'tashkent' where id = $1`, [reader]);
  const make = (title_kk, title_ru) =>
    scalar(
      `select app.admin_save_tournament($1, $2::jsonb, $3) as r`,
      [admin, JSON.stringify({ city_id: 'tashkent', sport_id: 'padel', title_kk, title_ru, starts_on: '2026-12-20', ends_on: '2026-12-20' }), now],
    );
  const first = await make('Алтын', 'Яблоко');
  const second = await make('Ұлы', 'Арбуз');
  const { rows } = await pool.query(`select app.list_tournaments($1, 'tashkent', 'padel', '2026-12-20', 'az', $2) as r`, [reader, now]);
  const ids = rows.map((r) => r.r.id).filter((id) => [first, second].includes(id));
  assert.deepEqual(ids, [first, second]);
});

test('seeded cities and sports have Kazakh names', async () => {
  const seeded = await freshDb('kazakh_seed');
  try {
    await seeded.pool.query(await readFile(path.join(process.env.ACTRA_ROOT, 'seed.sql'), 'utf8'));
    const cities = await seeded.pool.query(`select id, name_kk from cities order by id`);
    assert.deepEqual(cities.rows, [
      { id: 'almaty', name_kk: 'Алматы' },
      { id: 'astana', name_kk: 'Астана' },
      { id: 'tashkent', name_kk: 'Ташкент' },
    ]);
    const sports = await seeded.pool.query(`select id, name_kk from sports order by sort_order`);
    assert.deepEqual(
      sports.rows.map((s) => s.name_kk),
      ['Футбол', 'Падел', 'Теннис', 'Баскетбол', 'Волейбол', 'Жүгіру', 'Жаттығу залы'],
    );
  } finally {
    await seeded.end();
  }
});
