// End-to-end check against the hosted project, through the same doors the
// app and Telegram use:
//
//   1. Two throw-away accounts sign in: telegram-login "start", then
//      Telegram-shaped updates posted to the webhook (with the secret
//      header), then "claim", then the one-time hash exchanged for a session.
//   2. Account A holds and confirms a seeded slot.
//   3. The row is read back from the bookings table.
//   4. Account B sees the slot as taken and is refused it.
//   5. A cancels; everything created here is deleted again.
//
// What it cannot check: a real person tapping "Share my phone number" in
// Telegram. The bot's replies to the fake chat ids used here fail by design.
//
//   node scripts/e2e.mjs

import assert from 'node:assert/strict';
import { randomInt } from 'node:crypto';
import { call, env, login, removeAccounts, rpc, sampleId, saveProfile, signIn, webhook } from './e2e-lib.mjs';
import { sql, step } from './env.mjs';

let failed = false;
try {
  step('The webhook refuses calls that are not from Telegram');
  assert.equal((await webhook({ message: { text: '/start x' } }, null)).status, 401);
  assert.equal((await webhook({ message: { text: '/start x' } }, 'wrong')).status, 401);
  console.log('  401 without the secret header, 401 with a wrong one');

  step('Signing in two accounts through the login function and the webhook');
  const suffix = String(randomInt(10_000_000)).padStart(7, '0');
  const a = await signIn('A', `+99800${suffix}`);
  const b = await signIn('B', `+99801${suffix}`);
  assert.notEqual(a.userId, b.userId);

  step('A login token is single-use');
  assert.deepEqual((await login({ action: 'claim', token: a.token, poll_secret: a.poll_secret })).data, { status: 'expired' });
  console.log('  second claim: expired');

  step('The same phone number signs in to the same account');
  const again = await signIn('A again', `+99800${suffix}`);
  assert.equal(again.userId, a.userId);
  assert.equal(again.isNew, false);

  step('First sign-in details');
  await saveProfile(a, 'E2E Player A');
  const phones = await call('/rest/v1/profile_contacts?select=phone', { method: 'GET', token: a.jwt });
  assert.deepEqual(phones.data, [{ phone: `+99800${suffix}` }], 'a player sees exactly their own phone');
  console.log('  profile saved; own phone visible, nobody else\'s');

  step('The catalog is seeded');
  const venues = await call('/rest/v1/venues?select=id,city_id', { method: 'GET', token: a.jwt });
  assert.equal(venues.data.length, 6, 'six seeded venues');
  const court = sampleId('v1c2');

  // A free slot a few days ahead on Lochin Padel Club, court 2.
  const today = (await sql(env, `select (app.to_local(now(), 300))::date::text as d`))[0].d;
  let slot = null;
  for (let ahead = 3; ahead <= 10 && !slot; ahead++) {
    const date = new Date(`${today}T00:00:00Z`);
    date.setUTCDate(date.getUTCDate() + ahead);
    const day = await rpc(a, 'court_availability', { p_court_id: court, p_date: date.toISOString().slice(0, 10) });
    assert.equal(day.status, 200, JSON.stringify(day.data));
    slot = day.data.find((s) => s.state === 'free') ?? null;
  }
  assert.ok(slot, 'no free slot found on the seeded court');
  console.log(`  slot: ${slot.starts_local}, ${slot.price} UZS`);

  step('A holds and confirms the slot');
  const held = await rpc(a, 'hold_slots', { p_court_id: court, p_starts: [slot.starts_local] });
  assert.equal(held.status, 200, JSON.stringify(held.data));
  assert.equal(held.data.status, 'held');
  assert.equal(held.data.total_price, slot.price);
  const confirmed = await rpc(a, 'confirm_booking', { p_booking_id: held.data.id, p_players: 4, p_note: 'e2e' });
  assert.equal(confirmed.data?.status, 'confirmed', JSON.stringify(confirmed.data));
  const bookingId = confirmed.data.id;

  step('The booking is in the database');
  const rows = await sql(
    env,
    `select status, total_price, user_id::text, court_id::text,
            app.to_local(lower(during), utc_offset_minutes)::text as starts_local
     from public.bookings where id = '${bookingId}'`,
  );
  assert.equal(rows.length, 1);
  assert.equal(rows[0].status, 'confirmed');
  assert.equal(rows[0].user_id, a.userId);
  assert.equal(rows[0].court_id, court);
  assert.equal(Number(rows[0].total_price), slot.price);
  console.log(`  bookings row ${bookingId}: ${rows[0].status}, ${rows[0].starts_local}`);

  step('The second account is blocked from the same slot');
  const seenByB = await rpc(b, 'court_availability', { p_court_id: court, p_date: slot.starts_local.slice(0, 10) });
  assert.equal(seenByB.data.find((s) => s.starts_local === slot.starts_local).state, 'taken');
  const refused = await rpc(b, 'hold_slots', { p_court_id: court, p_starts: [slot.starts_local] });
  assert.equal(refused.status, 400);
  assert.equal(refused.data.message, 'slot_taken');
  const bRows = await call('/rest/v1/bookings?select=id', { method: 'GET', token: b.jwt });
  assert.deepEqual(bRows.data, [], "B cannot see A's booking");
  const mine = await rpc(a, 'my_bookings');
  assert.deepEqual(mine.data.map((x) => x.id), [bookingId]);
  console.log('  B sees "taken", is refused with slot_taken, and cannot read A\'s row');

  step('Writing the table directly is refused');
  const direct = await call(`/rest/v1/bookings?id=eq.${bookingId}`, { method: 'PATCH', token: a.jwt, body: { total_price: 1 } });
  assert.ok(direct.status === 401 || direct.status === 403, `expected a refusal, got ${direct.status}`);
  console.log(`  PATCH bookings as the owner: ${direct.status}`);

  step('A cancels and the slot is free again');
  const cancelled = await rpc(a, 'cancel_booking', { p_booking_id: bookingId });
  assert.equal(cancelled.data?.status, 'cancelled_by_player', JSON.stringify(cancelled.data));
  const after = await rpc(b, 'court_availability', { p_court_id: court, p_date: slot.starts_local.slice(0, 10) });
  assert.equal(after.data.find((s) => s.starts_local === slot.starts_local).state, 'free');

  console.log('\nEND TO END: PASSED');
} catch (e) {
  failed = true;
  console.error(`\nEND TO END: FAILED\n${e.stack ?? e}`);
} finally {
  step('Cleaning up the throw-away accounts');
  await removeAccounts();
}
process.exit(failed ? 1 : 0);
