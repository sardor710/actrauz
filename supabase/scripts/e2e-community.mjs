// End-to-end check of the community functions (Milestone 4) against the
// hosted project, with real sessions:
//
//   1. Four throw-away accounts sign in: an admin, a host, a joiner and a
//      guest. The admin (a row in app_admins) creates a throw-away venue
//      with one padel court, so no real venue owner is ever notified.
//   2. The host books that court and puts a game on the booking; the
//      joiner asks to join and the host approves.
//   3. The inbox: the host reads the join request, pages, marks it read; the
//      joiner has the approval.
//   4. An invite-only run is invisible to the guest until the host invites
//      them; then the guest joins.
//   5. The guest posts a Game Request, the joiner taps "I'm in", and the
//      guest converts it into a game with the joiner in it.
//   6. Finding players lists the three accounts with no phone number; a
//      hidden player drops out of the list. Settings and reliability read
//      back, and the private profile columns cannot be read directly.
//   7. The host cancels the game and the booking; everything made here
//      (venue, games, requests, bookings, accounts) is deleted. Existing
//      accounts are only ever read, never changed or notified.
//
//   node scripts/e2e-community.mjs
//
// It writes to the hosted project: run it only when asked to.

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

/** No key anywhere in the value is a phone number. */
function assertNoPhone(value, what) {
  const text = JSON.stringify(value);
  assert.ok(!/"phone"/.test(text) && !/\+998\d{9}/.test(text), `${what} carries a phone number: ${text}`);
}

const kinds = async (session) => (await ok(session, 'my_notifications', { p_limit: 50 })).map((n) => n.kind);

let venueId = null;
let failed = false;
try {
  step('Signing in an admin, a host, a joiner and a guest');
  const suffix = String(randomInt(10_000_000)).padStart(7, '0');
  const admin = await signIn('admin', `+99808${suffix}`);
  const host = await signIn('host', `+99805${suffix}`);
  const joiner = await signIn('joiner', `+99806${suffix}`);
  const guest = await signIn('guest', `+99807${suffix}`);
  // Letters only: the player search matches names.
  const tag = [...suffix].map((d) => 'abcdefghij'[d]).join('');
  await saveProfile(admin, `E2E Admin ${tag}`);
  await saveProfile(host, `E2E Host ${tag}`);
  await saveProfile(joiner, `E2E Joiner ${tag}`);
  await saveProfile(guest, `E2E Guest ${tag}`);
  const today = (await sql(env, `select (app.to_local(now(), 300))::date::text as d`))[0].d;

  step('Reliability starts at 80, new');
  for (const s of [host, joiner, guest]) {
    assert.deepEqual(await ok(s, 'my_reliability'), { score: 80, badge: 'new' });
  }

  step('The admin creates a throw-away venue with one padel court');
  await sql(env, `insert into public.app_admins (user_id) values ('${admin.userId}')`, { write: true });
  venueId = await ok(admin, 'admin_save_venue', {
    p_venue: { city_id: 'tashkent', name_en: `E2E test venue ${tag}`, address_en: 'Nowhere 1', district_en: 'Test', phone: '+998710000000' },
  });
  const court = await ok(admin, 'admin_save_court', {
    p_court: { venue_id: venueId, sport_id: 'padel', name_en: 'Court 1', slot_minutes: 60, base_price: 100000, indoor: true },
  });
  console.log(`  venue ${venueId}, court ${court}`);

  step('The host books that court and makes a public game on it');
  let slot = null;
  for (let ahead = 3; ahead <= 10 && !slot; ahead++) {
    const day = await ok(host, 'court_availability', { p_court_id: court, p_date: addDays(today, ahead) });
    slot = day.find((s) => s.state === 'free') ?? null;
  }
  assert.ok(slot, 'no free slot found on the throw-away court');
  const held = await ok(host, 'hold_slots', { p_court_id: court, p_starts: [slot.starts_local] });
  const booking = await ok(host, 'confirm_booking', { p_booking_id: held.id, p_players: 4, p_note: 'e2e community' });
  assert.equal(booking.status, 'confirmed');
  const game = await ok(host, 'create_game', { p_game: { sport_id: 'padel', booking_id: booking.id, spots: 4, visibility: 'public' } });
  assert.equal(game.kind, 'booked');
  assert.equal(game.my_status, 'host');
  assert.equal(game.price_per_player, Math.ceil(slot.price / 4));
  await refused(host, 'create_game', { p_game: { sport_id: 'padel', booking_id: booking.id, spots: 4 } }, 'game_exists');
  assertNoPhone(game, 'create_game');
  console.log(`  game ${game.id} on booking ${booking.id} (${slot.starts_local})`);

  step('The joiner asks to join; the host approves');
  const listed = (await ok(joiner, 'list_games', { p_city_id: 'tashkent' })).map((g) => g.id);
  assert.ok(listed.includes(game.id), 'the public game is listed in the city');
  const requested = await ok(joiner, 'request_to_join', { p_game_id: game.id });
  assert.equal(requested.my_status, 'requested');
  assert.ok(requested.my_request_id);
  await refused(joiner, 'request_to_join', { p_game_id: game.id }, 'already_requested');
  await refused(guest, 'decide_join_request', { p_request_id: requested.my_request_id, p_approve: true }, 'not_found');
  const hostView = await ok(host, 'get_game', { p_game_id: game.id });
  assert.deepEqual(hostView.join_requests.map((r) => r.user_id), [joiner.userId]);
  assert.equal(hostView.join_requests[0].reliability.badge, 'new');
  assertNoPhone(hostView, 'get_game (host)');
  const approved = await ok(host, 'decide_join_request', { p_request_id: requested.my_request_id, p_approve: true });
  assert.deepEqual(approved.participant_ids, [host.userId, joiner.userId]);
  assert.equal((await ok(joiner, 'get_game', { p_game_id: game.id })).my_status, 'participant');
  console.log('  requested, refused to a stranger, approved by the host');

  step('The inbox: read, page, mark read');
  const hostKinds = await kinds(host);
  assert.ok(hostKinds.includes('join_request'), `host inbox: ${hostKinds.join(', ')}`);
  assert.ok(hostKinds.includes('booking_confirmed'), `host inbox: ${hostKinds.join(', ')}`);
  assert.ok((await kinds(joiner)).includes('join_approved'));
  const [newest] = await ok(host, 'my_notifications', { p_limit: 1 });
  const older = await ok(host, 'my_notifications', { p_limit: 50, p_before: newest.created_at, p_before_id: newest.id });
  assert.ok(older.length >= 1 && !older.some((n) => n.id === newest.id), 'the next page starts after the last entry');
  assert.ok((await ok(host, 'unread_notification_count')) >= 2);
  await ok(host, 'mark_notifications_read', { p_ids: null });
  assert.equal(await ok(host, 'unread_notification_count'), 0);
  const table = await call('/rest/v1/notifications?select=user_id', { method: 'GET', token: joiner.jwt });
  assert.ok(table.status === 200 && table.data.every((n) => n.user_id === joiner.userId), 'a player reads only their own notifications');
  console.log(`  host had ${hostKinds.length} entries; paging and mark-all work; the table shows only your own`);

  step('An invite-only run is invisible to the guest until invited');
  const runDay = addDays(today, 3);
  const run = await ok(host, 'create_game', {
    p_game: {
      sport_id: 'running', meeting_point: 'E2E park gate', meeting_lat: 41.31, meeting_lng: 69.28,
      starts_local: `${runDay}T07:00:00`, ends_local: `${runDay}T08:00:00`, spots: 4, visibility: 'invite_only',
    },
  });
  assert.equal(run.kind, 'map_point');
  assert.ok(!(await ok(guest, 'list_games', { p_city_id: 'tashkent' })).some((g) => g.id === run.id));
  assert.equal(await ok(guest, 'get_game', { p_game_id: run.id }), null);
  await refused(guest, 'join_game', { p_game_id: run.id }, 'not_found');
  await refused(guest, 'request_to_join', { p_game_id: run.id }, 'not_found');
  for (const t of ['games', 'game_participants', 'game_invites', 'game_join_requests']) {
    const direct = await call(`/rest/v1/${t}?select=*`, { method: 'GET', token: guest.jwt });
    assert.ok(direct.status !== 200 || direct.data.length === 0, `${t} is readable by a player`);
  }
  await ok(host, 'invite_to_game', { p_game_id: run.id, p_user_id: guest.userId });
  assert.ok((await kinds(guest)).includes('game_invite'));
  assert.equal((await ok(guest, 'get_game', { p_game_id: run.id })).my_status, 'invited');
  const joinedRun = await ok(guest, 'join_game', { p_game_id: run.id });
  assert.equal(joinedRun.my_status, 'participant');
  console.log('  not listed, null, not_found; after the invite: invited, then joined');

  step('A Game Request: the guest posts, the joiner is in, the guest converts');
  const reqDay = addDays(today, 4);
  const request = await ok(guest, 'create_game_request', {
    p_request: { sport_id: 'running', starts_local: `${reqDay}T18:00:00`, ends_local: `${reqDay}T20:00:00`, area: 'E2E area', players_needed: 2 },
  });
  assert.equal(request.my_status, 'host');
  assert.ok((await ok(joiner, 'list_game_requests', { p_city_id: 'tashkent' })).some((r) => r.id === request.id));
  const interested = await ok(joiner, 'request_interest', { p_request_id: request.id });
  assert.equal(interested.my_status, 'interested');
  await refused(joiner, 'request_interest', { p_request_id: request.id }, 'already_joined');
  await refused(host, 'convert_game_request', { p_request_id: request.id, p_place: { meeting_point: 'x' } }, 'not_found');
  assert.ok((await kinds(guest)).includes('request_interest'));
  assertNoPhone(await ok(guest, 'get_game_request', { p_request_id: request.id }), 'get_game_request');
  const converted = await ok(guest, 'convert_game_request', {
    p_request_id: request.id, p_place: { meeting_point: 'E2E track', meeting_lat: 41.3, meeting_lng: 69.3 },
  });
  assert.deepEqual(converted.participant_ids, [guest.userId, joiner.userId]);
  const note = (await ok(joiner, 'my_notifications', { p_limit: 50 })).find((n) => n.kind === 'request_converted');
  assert.equal(note?.payload.added, true);
  assert.equal((await ok(guest, 'get_game_request', { p_request_id: request.id })).status, 'converted');
  console.log(`  request ${request.id} became game ${converted.id} with the joiner in it`);

  step('Finding players: no phone numbers; hidden players drop out of the list');
  const found = await ok(joiner, 'list_players', { p_city_id: 'tashkent', p_query: tag });
  assert.deepEqual(found.map((p) => p.id).sort(), [admin.userId, host.userId, guest.userId].sort(), 'the others, not the caller');
  assertNoPhone(found, 'list_players');
  const profile = await ok(joiner, 'player_profile', { p_user_id: host.userId });
  assert.equal(profile.name, `E2E Host ${tag}`);
  assert.deepEqual(profile.reliability, { score: 80, badge: 'new' });
  assertNoPhone(profile, 'player_profile');
  await ok(guest, 'set_settings', { p_muted: ['invites'], p_hidden: true });
  const settings = await ok(guest, 'my_settings');
  assert.deepEqual(settings.muted_categories, ['invites']);
  assert.equal(settings.hidden_from_search, true);
  const again = await ok(joiner, 'list_players', { p_city_id: 'tashkent', p_query: tag });
  assert.deepEqual(again.map((p) => p.id).sort(), [admin.userId, host.userId].sort());
  assert.equal((await ok(joiner, 'player_profile', { p_user_id: guest.userId })).id, guest.userId, 'the profile still opens');
  for (const column of ['muted_categories', 'hidden_from_search']) {
    const direct = await call(`/rest/v1/profiles?select=${column}&id=eq.${guest.userId}`, { method: 'GET', token: joiner.jwt });
    assert.notEqual(direct.status, 200, `profiles.${column} is readable by another player`);
  }
  const names = await call(`/rest/v1/profiles?select=full_name&id=eq.${guest.userId}`, { method: 'GET', token: joiner.jwt });
  assert.deepEqual(names.data, [{ full_name: `E2E Guest ${tag}` }]);
  console.log('  three found, no phones; hidden after set_settings; private columns refused, names readable');

  step('The host cancels the game and the booking; the joiner is told');
  const cancelled = await ok(host, 'host_cancel_game', { p_game_id: game.id, p_cancel_booking: true });
  assert.equal(cancelled.status, 'cancelled');
  assert.ok((await kinds(joiner)).includes('game_cancelled'));
  assert.equal((await ok(host, 'my_bookings')).find((b) => b.id === booking.id)?.status, 'cancelled_by_player');
  assert.deepEqual(await ok(host, 'my_reliability'), { score: 80, badge: 'new' }, 'cancelling days ahead costs nothing');

  console.log('\nCOMMUNITY END TO END: PASSED');
} catch (e) {
  failed = true;
  console.error(`\nCOMMUNITY END TO END: FAILED\n${e.stack ?? e}`);
} finally {
  step('Cleaning up the throw-away venue, games, requests and accounts');
  const users = createdUsersSql();
  await removeAccounts({
    before: [
      // Neither reference cascades from the accounts or their bookings.
      ...(users
        ? [`delete from public.game_requests where host_id in (${users})`, `delete from public.games where host_id in (${users})`]
        : []),
      ...(venueId
        ? [`delete from public.bookings where venue_id = '${venueId}'`, `delete from public.venues where id = '${venueId}'`]
        : []),
      ...(users ? [`delete from public.audit_log where actor_id in (${users})`] : []),
    ],
  });
  if (users) {
    const left = await sql(
      env,
      `select (select count(*) from public.games where host_id in (${users})) as games,
              (select count(*) from public.game_requests where host_id in (${users})) as requests,
              (select count(*) from public.profiles where id in (${users})) as profiles,
              (select count(*) from public.venues where name_en like 'E2E test venue%') as venues`,
    );
    console.log(
      `  left behind: ${left[0].games} games, ${left[0].requests} requests, ${left[0].profiles} profiles, ${left[0].venues} test venues`,
    );
  }
}
process.exit(failed ? 1 : 0);
