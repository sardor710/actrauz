// End-to-end check of the owner and admin functions against the hosted
// project, with real sessions:
//
//   1. Three throw-away accounts sign in: an admin, an owner, a player.
//   2. The admin (made one by a row in app_admins) creates a throw-away
//      venue with one court and assigns the owner, found by name search.
//   3. The owner reads the calendar, adds a walk-in and a block, changes the
//      price, reads the dashboard, and cancels both.
//   4. The player is refused every owner and admin call, and sees the
//      walk-in's slot as taken.
//   5. The audit log lists what was done; everything made here is deleted.
//
//   node scripts/e2e-owner.mjs

import assert from 'node:assert/strict';
import { randomInt } from 'node:crypto';
import { call, createdUsersSql, env, removeAccounts, rpc, saveProfile, signIn } from './e2e-lib.mjs';
import { sql, step } from './env.mjs';

/** A call that must be refused with the given error name. */
async function refused(session, name, params, error) {
  const res = await rpc(session, name, params);
  assert.equal(res.status, 400, `${name}: expected ${error}, got ${res.status} ${JSON.stringify(res.data)}`);
  assert.equal(res.data.message, error, `${name}: ${JSON.stringify(res.data)}`);
}

/** A call that must succeed; returns its data. */
async function ok(session, name, params = {}) {
  const res = await rpc(session, name, params);
  assert.ok(res.status === 200 || res.status === 204, `${name} failed: ${res.status} ${JSON.stringify(res.data)}`);
  return res.data;
}

const addDays = (date, days) => {
  const d = new Date(`${date}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + days);
  return d.toISOString().slice(0, 10);
};

let venueId = null;
let failed = false;
try {
  step('Signing in an admin, an owner and a player');
  const suffix = String(randomInt(10_000_000)).padStart(7, '0');
  const admin = await signIn('admin', `+99802${suffix}`);
  const owner = await signIn('owner', `+99803${suffix}`);
  const player = await signIn('player', `+99804${suffix}`);
  // Letters only: digits in a search are also matched against phone numbers.
  const tag = [...suffix].map((d) => 'abcdefghij'[d]).join('');
  const ownerName = `E2E Owner ${tag}`;
  await saveProfile(admin, `E2E Admin ${tag}`);
  await saveProfile(owner, ownerName);
  await saveProfile(player, `E2E Player ${tag}`);

  step('Nobody is an admin until a row says so');
  assert.equal(await ok(admin, 'am_i_admin'), false);
  await refused(admin, 'admin_list_venues', {}, 'not_allowed');
  await refused(admin, 'admin_save_venue', { p_venue: { city_id: 'tashkent', name_en: 'Nope' } }, 'not_allowed');
  await sql(env, `insert into public.app_admins (user_id) values ('${admin.userId}')`, { write: true });
  assert.equal(await ok(admin, 'am_i_admin'), true);
  assert.equal(await ok(player, 'am_i_admin'), false);
  console.log('  refused before the app_admins row, allowed after it');

  step('The admin creates a venue with one court');
  venueId = await ok(admin, 'admin_save_venue', {
    p_venue: {
      city_id: 'tashkent',
      name_en: `E2E test venue ${tag}`,
      address_en: 'Nowhere 1',
      district_en: 'Test',
      phone: '+998710000000',
      amenities: ['parking', 'lighting'],
    },
  });
  assert.match(venueId, /^[0-9a-f-]{36}$/);
  const courtId = await ok(admin, 'admin_save_court', {
    p_court: { venue_id: venueId, sport_id: 'padel', name_en: 'Court 1', slot_minutes: 60, base_price: 100000, indoor: true },
  });
  await refused(admin, 'admin_save_court', { p_court: { venue_id: venueId, sport_id: 'no_such_sport', name_en: 'X', slot_minutes: 60, base_price: 1 } }, 'invalid_argument');
  const listed = (await ok(admin, 'admin_list_venues')).find((v) => v.id === venueId);
  assert.ok(listed, 'the new venue is in the admin list');
  assert.equal(listed.courts.length, 1);
  assert.equal(listed.hours.length, 7, 'a new venue gets seven days of hours');
  assert.deepEqual(listed.owners, []);
  console.log(`  venue ${venueId}, court ${courtId}`);

  step('The admin finds the owner by name and by phone, and assigns them');
  const found = await ok(admin, 'admin_search_users', { p_query: ownerName.toLowerCase() });
  assert.deepEqual(found.map((u) => u.user_id), [owner.userId]);
  assert.equal(found[0].phone, `+99803${suffix}`);
  const byPhone = await ok(admin, 'admin_search_users', { p_query: `99803 ${suffix}` });
  assert.deepEqual(byPhone.map((u) => u.user_id), [owner.userId]);
  await refused(player, 'admin_search_users', { p_query: ownerName }, 'not_allowed');
  await refused(player, 'admin_set_owner', { p_venue_id: venueId, p_user_id: player.userId, p_assigned: true }, 'not_allowed');
  assert.deepEqual(await ok(owner, 'my_venue_ids'), []);
  await ok(admin, 'admin_set_owner', { p_venue_id: venueId, p_user_id: owner.userId, p_assigned: true });
  assert.deepEqual(await ok(owner, 'my_venue_ids'), [venueId]);
  assert.deepEqual(await ok(player, 'my_venue_ids'), []);
  console.log('  the owner now manages the venue; the player manages nothing');

  step('The owner reads the calendar; the player may not');
  const now = (await sql(env, `select app.to_local(now(), 300)::text as t`))[0].t;
  const today = now.slice(0, 10);
  const day = addDays(today, 2);
  const calendar = await ok(owner, 'owner_calendar', { p_court_id: courtId, p_from: day, p_days: 1 });
  assert.equal(calendar.slots.length, 14, 'a 08:00–22:00 day of one-hour slots');
  assert.ok(calendar.slots.every((s) => s.state === 'free' && s.price === 100000));
  assert.deepEqual(calendar.bookings, []);
  await refused(player, 'owner_calendar', { p_court_id: courtId, p_from: day, p_days: 1 }, 'not_allowed');
  const [first, second, third] = calendar.slots;

  step('The owner adds a walk-in and blocks a slot');
  await refused(owner, 'owner_create_walk_in', { p_court_id: courtId, p_starts: [first.starts_local], p_name: ' ', p_phone: null, p_players: 4, p_payment_method: 'cash' }, 'name_required');
  await refused(player, 'owner_create_walk_in', { p_court_id: courtId, p_starts: [first.starts_local], p_name: 'Guest', p_phone: null, p_players: 4, p_payment_method: 'cash' }, 'not_allowed');
  const walkIn = await ok(owner, 'owner_create_walk_in', {
    p_court_id: courtId, p_starts: [first.starts_local], p_name: 'E2E Guest', p_phone: null, p_players: 4, p_payment_method: 'cash',
  });
  assert.equal(walkIn.source, 'walk_in');
  assert.equal(walkIn.status, 'confirmed');
  assert.equal(walkIn.total_price, 100000);
  assert.equal(walkIn.customer_name, 'E2E Guest');
  assert.equal(walkIn.walk_in_payment, 'cash');
  await refused(owner, 'owner_create_walk_in', { p_court_id: courtId, p_starts: [first.starts_local], p_name: 'Second', p_phone: null, p_players: 2, p_payment_method: 'card' }, 'slot_taken');

  const block = await ok(owner, 'owner_block_slots', { p_court_id: courtId, p_starts: [second.starts_local], p_reason: 'Maintenance' });
  assert.equal(block.source, 'block');
  assert.equal(block.total_price, 0);
  assert.equal(block.reason, 'Maintenance');

  const filled = await ok(owner, 'owner_calendar', { p_court_id: courtId, p_from: day, p_days: 1 });
  assert.deepEqual(filled.slots.slice(0, 3).map((s) => s.state), ['booked', 'blocked', 'free']);
  assert.deepEqual(filled.bookings.map((b) => b.id).sort(), [walkIn.id, block.id].sort());
  console.log(`  walk-in ${first.starts_local}, block ${second.starts_local}`);

  step('The player sees both slots as taken and cannot read or change the rows');
  const seen = await ok(player, 'court_availability', { p_court_id: courtId, p_date: day });
  assert.deepEqual(seen.slice(0, 3).map((s) => s.state), ['taken', 'taken', 'free']);
  await refused(player, 'hold_slots', { p_court_id: courtId, p_starts: [first.starts_local] }, 'slot_taken');
  await refused(player, 'owner_cancel_booking', { p_booking_id: walkIn.id }, 'not_allowed');
  await refused(player, 'cancel_booking', { p_booking_id: walkIn.id }, 'not_found');
  const rows = await call(`/rest/v1/bookings?select=id&venue_id=eq.${venueId}`, { method: 'GET', token: player.jwt });
  assert.deepEqual(rows.data, [], 'a player cannot read the venue\'s bookings');
  for (const table of ['audit_log', 'app_admins']) {
    const direct = await call(`/rest/v1/${table}?select=*`, { method: 'GET', token: player.jwt });
    assert.ok(direct.status !== 200 || direct.data.length === 0, `${table} is readable by a player`);
  }
  console.log('  taken, slot_taken, not_allowed; no rows through the table API');

  step('A booking that has not started cannot be marked');
  await refused(owner, 'owner_mark_booking', { p_booking_id: walkIn.id, p_outcome: 'paid' }, 'not_markable');

  // Only when the venue is open right now: a walk-in in the running slot.
  const running = (await ok(owner, 'owner_calendar', { p_court_id: courtId, p_from: today, p_days: 1 })).slots.find(
    (s) => s.state === 'free' && s.starts_local.replace('T', ' ') <= now && now < s.ends_local.replace('T', ' '),
  );
  let paidToday = 0;
  if (running) {
    const current = await ok(owner, 'owner_create_walk_in', {
      p_court_id: courtId, p_starts: [running.starts_local], p_name: 'E2E Now', p_phone: null, p_players: 2, p_payment_method: 'card',
    });
    const paid = await ok(owner, 'owner_mark_booking', { p_booking_id: current.id, p_outcome: 'paid' });
    assert.equal(paid.status, 'paid');
    assert.equal(paid.payment_status, 'paid');
    paidToday = paid.total_price;
    console.log(`  a walk-in in the running slot (${running.starts_local}) was marked paid`);
  } else {
    console.log('  the venue is closed right now, so marking as paid was not exercised');
  }

  step('The owner changes the price and hours');
  await refused(owner, 'owner_set_court_pricing', { p_court_id: courtId, p_slot_minutes: 45, p_base_price: 150000, p_rules: [] }, 'invalid_argument');
  await refused(player, 'owner_set_court_pricing', { p_court_id: courtId, p_slot_minutes: 60, p_base_price: 1, p_rules: [] }, 'not_allowed');
  await ok(owner, 'owner_set_court_pricing', {
    p_court_id: courtId, p_slot_minutes: 60, p_base_price: 150000,
    p_rules: [{ weekdays: [1, 2, 3, 4, 5, 6, 7], from_minute: 1080, to_minute: 1320, price: 200000 }],
  });
  await refused(owner, 'owner_set_venue_hours', { p_venue_id: venueId, p_hours: [] }, 'invalid_hours');
  await ok(owner, 'owner_set_court_hours', { p_court_id: courtId, p_hours: [] });
  const repriced = await ok(owner, 'owner_calendar', { p_court_id: courtId, p_from: day, p_days: 1 });
  assert.equal(repriced.slots.find((s) => s.starts_local === third.starts_local).price, 150000);
  assert.equal(repriced.slots.at(-1).price, 200000, 'the evening rule applies');
  assert.equal(repriced.bookings.find((b) => b.id === walkIn.id).total_price, 100000, 'the walk-in keeps its price');
  console.log('  new slots cost the new price; the existing walk-in keeps its own');

  step('The dashboard counts the walk-in');
  const dashboard = await ok(owner, 'owner_dashboard', { p_venue_id: venueId, p_court_id: null, p_from: day, p_to: day });
  assert.equal(dashboard.currency, 'UZS');
  assert.equal(dashboard.bookings_walk_in, 1);
  assert.equal(dashboard.bookings_app, 0);
  assert.equal(dashboard.revenue_paid, 0);
  // Revenue counts once a booking is marked paid; "unconfirmed" is only for
  // bookings nobody marked within 48 hours of their end.
  assert.equal(dashboard.revenue_unconfirmed, 0);
  assert.equal(dashboard.slots_booked, 1);
  assert.equal(dashboard.slots_available, 13, 'fourteen slots less the blocked one');
  if (paidToday) {
    const todays = await ok(owner, 'owner_dashboard', { p_venue_id: venueId, p_court_id: courtId, p_from: today, p_to: today });
    assert.equal(todays.revenue_paid, paidToday);
    assert.equal(todays.bookings_walk_in, 1);
  }
  await refused(player, 'owner_dashboard', { p_venue_id: venueId, p_court_id: null, p_from: day, p_to: day }, 'not_allowed');
  console.log(`  walk-ins ${dashboard.bookings_walk_in}, slots ${dashboard.slots_booked}/${dashboard.slots_available}${paidToday ? `, paid today ${paidToday}` : ''}`);

  step('The owner cancels both and the slots are free again');
  assert.equal((await ok(owner, 'owner_cancel_booking', { p_booking_id: walkIn.id })).status, 'cancelled_by_venue');
  await ok(owner, 'owner_cancel_booking', { p_booking_id: block.id });
  const freed = await ok(player, 'court_availability', { p_court_id: courtId, p_date: day });
  assert.deepEqual(freed.slice(0, 2).map((s) => s.state), ['free', 'free']);

  step('A venue with booking rows cannot be deleted, and the audit log has the story');
  await refused(admin, 'admin_delete_venue', { p_venue_id: venueId }, 'has_bookings');
  await refused(owner, 'admin_audit_log', { p_limit: 50, p_before: null }, 'not_allowed');
  const audit = await ok(admin, 'admin_audit_log', { p_limit: 100, p_before: null });
  const mine = audit.filter((entry) => entry.actor_name?.endsWith(tag));
  const actions = [...new Set(mine.map((entry) => entry.action))];
  assert.ok(actions.includes('create_venue'), `create_venue missing from ${actions.join(', ')}`);
  assert.ok(mine.length >= 8, `expected at least 8 audit rows, found ${mine.length}`);
  console.log(`  ${mine.length} rows: ${actions.join(', ')}`);

  console.log('\nOWNER AND ADMIN END TO END: PASSED');
} catch (e) {
  failed = true;
  console.error(`\nOWNER AND ADMIN END TO END: FAILED\n${e.stack ?? e}`);
} finally {
  step('Cleaning up the throw-away venue and accounts');
  const users = createdUsersSql();
  await removeAccounts({
    before: [
      ...(venueId
        ? [`delete from public.bookings where venue_id = '${venueId}'`, `delete from public.venues where id = '${venueId}'`]
        : []),
      ...(users ? [`delete from public.audit_log where actor_id in (${users})`] : []),
    ],
  });
  const left = await sql(
    env,
    `select (select count(*) from public.venues where name_en like 'E2E test venue%') as venues,
            (select count(*) from public.app_admins) as admins,
            (select count(*) from public.profiles where full_name like 'E2E %') as profiles`,
  );
  console.log(`  left behind: ${left[0].venues} test venues, ${left[0].profiles} test profiles; admins in the project: ${left[0].admins}`);
}
process.exit(failed ? 1 : 0);
