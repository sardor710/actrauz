// End-to-end check of Kazakhstan against the hosted project (run it after
// `deploy.mjs migrations`):
//
//   1. A throw-away Almaty venue with one court priced 12 000 is made as the
//      service role. It has no owners, so no real owner is notified.
//   2. A throw-away player signs in, holds and confirms tomorrow 18:00
//      Almaty time (UTC+5) through the same RPCs the app calls.
//   3. The booking is KZT, 12 000, and reads 18:00 on the venue's wall clock.
//   4. The player's language is set to Kazakh (kk).
//   5. The booking, venue, court and player are deleted again, even when an
//      assertion fails.
//
//   node scripts/e2e-kz.mjs

import assert from 'node:assert/strict';
import { randomInt, randomUUID } from 'node:crypto';
import { call, env, removeAccounts, rpc, signIn } from './e2e-lib.mjs';
import { sql, step } from './env.mjs';

const addDays = (date, days) => {
  const d = new Date(`${date}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + days);
  return d.toISOString().slice(0, 10);
};

// Made up front so cleanup knows them even if the insert fails half way.
const venueId = randomUUID();
const courtId = randomUUID();
let failed = false;
try {
  step('A throw-away Almaty venue with one court priced 12 000');
  const tag = `E2E KZ ${Date.now()}`;
  const cities = await sql(env, `select currency, utc_offset_minutes from public.cities where id = 'almaty'`);
  assert.deepEqual(cities, [{ currency: 'KZT', utc_offset_minutes: 300 }], 'Almaty is a KZT city at UTC+5');
  await sql(
    env,
    `insert into public.venues (id, city_id, name_en, address_en, phone)
       values ('${venueId}', 'almaty', '${tag}', 'Nowhere 1', '');
     insert into public.courts (id, venue_id, sport_id, name_en, slot_minutes, base_price, indoor)
       values ('${courtId}', '${venueId}', 'padel', 'Court 1', 60, 12000, true);
     insert into public.working_hours (venue_id, weekday, open_minute, close_minute)
       select '${venueId}', d, 480, 1320 from generate_series(1, 7) d;`,
    { write: true },
  );
  const owners = await sql(env, `select count(*)::int as n from public.venue_owners where venue_id = '${venueId}'`);
  assert.equal(owners[0].n, 0, 'the throw-away venue has no owners, so nobody real is notified');
  console.log(`  ${tag}: venue ${venueId}, court ${courtId}`);

  step('A throw-away player signs in');
  const suffix = String(randomInt(10_000_000)).padStart(7, '0');
  const player = await signIn('player', `+99805${suffix}`);

  step('The player holds and confirms tomorrow 18:00 Almaty time');
  const today = (await sql(env, `select app.to_local(now(), 300)::date::text as d`))[0].d;
  const tomorrow = addDays(today, 1);
  const day = await rpc(player, 'court_availability', { p_court_id: courtId, p_date: tomorrow });
  assert.equal(day.status, 200, JSON.stringify(day.data));
  const slot = day.data.find((s) => s.starts_local.replace('T', ' ').slice(0, 16) === `${tomorrow} 18:00`);
  assert.ok(slot, `no 18:00 slot on ${tomorrow}: ${day.data.map((s) => s.starts_local).join(', ')}`);
  assert.equal(slot.state, 'free');
  assert.equal(slot.price, 12000);
  const held = await rpc(player, 'hold_slots', { p_court_id: courtId, p_starts: [slot.starts_local] });
  assert.equal(held.status, 200, JSON.stringify(held.data));
  assert.equal(held.data.status, 'held');
  const confirmed = await rpc(player, 'confirm_booking', { p_booking_id: held.data.id, p_players: 4, p_note: 'e2e kz' });
  assert.equal(confirmed.data?.status, 'confirmed', JSON.stringify(confirmed.data));
  const bookingId = confirmed.data.id;
  assert.equal(confirmed.data.currency, 'KZT');
  assert.equal(confirmed.data.total_price, 12000);
  console.log(`  booking ${bookingId}: ${confirmed.data.currency} ${confirmed.data.total_price}, ${confirmed.data.starts_local}`);

  step('The booking row: KZT, 12 000, 18:00 on the venue wall clock');
  const rows = await sql(
    env,
    `select status, currency, total_price, utc_offset_minutes, user_id::text,
            app.to_local(lower(during), utc_offset_minutes)::text as starts_local,
            to_char(lower(during) at time zone 'UTC', 'HH24:MI') as starts_utc
     from public.bookings where id = '${bookingId}'`,
  );
  assert.equal(rows.length, 1);
  assert.equal(rows[0].status, 'confirmed');
  assert.equal(rows[0].user_id, player.userId);
  assert.equal(rows[0].currency, 'KZT');
  assert.equal(Number(rows[0].total_price), 12000);
  assert.equal(Number(rows[0].utc_offset_minutes), 300);
  assert.match(rows[0].starts_local, new RegExp(`^${tomorrow} 18:00(:00)?$`), `wall clock reads ${rows[0].starts_local}`);
  assert.equal(rows[0].starts_utc, '13:00', 'UTC+5: 18:00 in Almaty is 13:00 UTC');
  console.log(`  ${rows[0].currency} ${rows[0].total_price}, ${rows[0].starts_local} local, ${rows[0].starts_utc} UTC`);

  step('The player can use Kazakh');
  const profile = await call(`/rest/v1/profiles?id=eq.${player.userId}&select=id,language`, {
    method: 'PATCH',
    token: player.jwt,
    headers: { Prefer: 'return=representation' },
    body: { language: 'kk' },
  });
  assert.equal(profile.status, 200, JSON.stringify(profile.data));
  assert.equal(profile.data[0].language, 'kk');
  const stored = await sql(env, `select language from public.profiles where id = '${player.userId}'`);
  assert.equal(stored[0].language, 'kk');
  console.log('  profiles.language = kk');

  console.log('\nKAZAKHSTAN END TO END: PASSED');
} catch (e) {
  failed = true;
  console.error(`\nKAZAKHSTAN END TO END: FAILED\n${e.stack ?? e}`);
} finally {
  step('Cleaning up the throw-away venue and player');
  await removeAccounts({
    before: [
      `delete from public.bookings where venue_id = '${venueId}'`,
      `delete from public.venues where id = '${venueId}'`,
    ],
  });
  try {
    const left = await sql(
      env,
      `select (select count(*) from public.venues where id = '${venueId}' or name_en like 'E2E KZ %') as venues,
              (select count(*) from public.courts where id = '${courtId}') as courts`,
    );
    console.log(`  left behind: ${left[0].venues} test venues, ${left[0].courts} test courts`);
  } catch (e) {
    console.error(`  could not check what is left: ${e.message}`);
  }
}
process.exit(failed ? 1 : 0);
