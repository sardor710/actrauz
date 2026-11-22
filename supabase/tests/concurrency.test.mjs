// The rule that must never break: a slot belongs to at most one active hold
// or booking, whatever arrives at the same moment (product spec §14 rule 1).

import assert from 'node:assert/strict';
import { after, before, test } from 'node:test';
import { createUser, errorOf, expectError, freshDb } from './helpers/db.mjs';
import { addCourt, addVenue, at, monday, tashkent } from './helpers/fixtures.mjs';

let db;
let pool;
let ali;
let vali;
let venueId;

const now = tashkent('2026-11-22', 20);

before(async () => {
  db = await freshDb('concurrency');
  pool = db.pool;
  ali = await createUser(pool, 'Ali');
  vali = await createUser(pool, 'Vali');
  venueId = await addVenue(pool, { open: 0, close: 24 * 60 });
});
after(() => db.end());

// Each call takes its own connection from the pool, so two calls started
// together really do run in two sessions at once.
const hold = (user, courtId, starts) =>
  pool.query(`select (app.hold_slots($1, $2, $3::timestamp[], $4)).id`, [user, courtId, starts, now]);

const activeOn = async (courtId) =>
  (
    await pool.query(
      `select user_id, lower(during) as start from bookings
       where court_id = $1 and status in ('held', 'confirmed') order by lower(during)`,
      [courtId],
    )
  ).rows;

test('two players holding the same slot at the same moment: exactly one succeeds', async () => {
  // 20 rounds on 20 separate courts, all fired together.
  const courts = [];
  for (let i = 0; i < 20; i++) courts.push(await addCourt(pool, venueId, { slot: 60 }));
  const players = [];
  for (let i = 0; i < 40; i++) players.push(await createUser(pool, `P${i}`));

  const results = await Promise.all(
    courts.flatMap((courtId, i) => [
      errorOf(hold(players[2 * i], courtId, [at(monday, 10)])),
      errorOf(hold(players[2 * i + 1], courtId, [at(monday, 10)])),
    ]),
  );

  for (let i = 0; i < courts.length; i++) {
    const pair = [results[2 * i], results[2 * i + 1]].sort();
    assert.deepEqual(pair, [null, 'slot_taken'].sort(), `court ${i}: ${JSON.stringify(pair)}`);
    assert.equal((await activeOn(courts[i])).length, 1);
  }
});

test('ten players racing for one slot: one winner, nine refused', async () => {
  const courtId = await addCourt(pool, venueId, { slot: 60 });
  const players = [];
  for (let i = 0; i < 10; i++) players.push(await createUser(pool, `R${i}`));
  const results = await Promise.all(players.map((p) => errorOf(hold(p, courtId, [at(monday, 12)]))));
  assert.equal(results.filter((r) => r === null).length, 1);
  assert.equal(results.filter((r) => r === 'slot_taken').length, 9);
  assert.equal((await activeOn(courtId)).length, 1);
});

test('overlapping selections racing: one wins, the other is refused whole', async () => {
  const courtId = await addCourt(pool, venueId, { slot: 60 });
  const [a, b] = await Promise.all([
    errorOf(hold(ali, courtId, [at(monday, 9), at(monday, 10)])),
    errorOf(hold(vali, courtId, [at(monday, 10), at(monday, 11)])),
  ]);
  assert.deepEqual([a, b].sort(), [null, 'slot_taken'].sort());
  assert.equal((await activeOn(courtId)).length, 1);
});

test('the database itself refuses an overlapping row, whoever writes it', async () => {
  const courtId = await addCourt(pool, venueId, { slot: 60 });
  await pool.query(`select app.confirm_booking($1, (app.hold_slots($1, $2, $3::timestamp[], $4)).id, null, null, $4)`, [
    ali,
    courtId,
    [at(monday, 14)],
    now,
  ]);
  const insert = (status, range) =>
    pool.query(
      `insert into bookings (user_id, venue_id, court_id, during, utc_offset_minutes, slot_count, total_price, currency, status)
       values ($1, $2, $3, $4::tstzrange, 300, 1, 1, 'UZS', $5)`,
      [vali, venueId, courtId, range, status],
    );
  // 14:30-15:30 Tashkent overlaps the confirmed 14:00-15:00.
  await expectError(insert('confirmed', '[2026-11-23 09:30+00,2026-11-23 10:30+00)'), '23P01');
  await expectError(insert('held', '[2026-11-23 09:30+00,2026-11-23 10:30+00)'), '23P01');
  // Touching ranges do not overlap: 15:00-16:00 is fine.
  await insert('confirmed', '[2026-11-23 10:00+00,2026-11-23 11:00+00)');
  // Inactive rows never block.
  await insert('cancelled_by_player', '[2026-11-23 09:30+00,2026-11-23 10:30+00)');
  await insert('released', '[2026-11-23 09:30+00,2026-11-23 10:30+00)');
});

test('one player sending two holds at once ends with exactly one hold', async () => {
  const first = await addCourt(pool, venueId, { slot: 60 });
  const second = await addCourt(pool, venueId, { slot: 60 });
  const player = await createUser(pool, 'Double tap');
  const results = await Promise.all([
    errorOf(hold(player, first, [at(monday, 16)])),
    errorOf(hold(player, second, [at(monday, 16)])),
    errorOf(hold(player, first, [at(monday, 18)])),
  ]);
  assert.deepEqual(results, [null, null, null]);
  const { rows } = await pool.query(`select count(*)::int as n from bookings where user_id = $1 and status = 'held'`, [player]);
  assert.equal(rows[0].n, 1);
});

test('the three-booking limit holds under simultaneous requests', async () => {
  const courtId = await addCourt(pool, venueId, { slot: 60 });
  const player = await createUser(pool, 'Greedy');
  // Hold-and-confirm five different slots at once; the cap is three.
  const results = await Promise.all(
    [1, 2, 3, 4, 5].map((hour) =>
      errorOf(
        pool.query(`select app.confirm_booking($1, (app.hold_slots($1, $2, $3::timestamp[], $4)).id, null, null, $4)`, [
          player,
          courtId,
          [at(monday, hour)],
          now,
        ]),
      ),
    ),
  );
  assert.equal(results.filter((r) => r === null).length, 3, JSON.stringify(results));
  assert.equal(results.filter((r) => r === 'too_many_bookings').length, 2);
});
