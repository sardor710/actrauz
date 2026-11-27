// End-to-end check of teams and team games (Milestone 7) against the hosted
// project, with real sessions:
//
//   0. Read-only first: the M7 team tables exist. Otherwise it stops before
//      creating anything.
//   1. Five throw-away accounts sign in: an admin, a captain, a requester, an
//      invitee and an outsider. The admin (a row in app_admins) creates a
//      throw-away venue "E2E M7 teams <timestamp>" with one padel court, so
//      no real venue owner is ever notified.
//   2. The captain creates a padel team in Tashkent that needs approval; the
//      requester asks to join and the captain approves.
//   3. The captain invites the invitee, who accepts.
//   4. The captain books the throw-away court and posts a team game on it
//      (it never opens to everyone). The members are told; the requester
//      sees it, finds it in the list and joins; the outsider cannot see it
//      (get_game is null, not listed, not on the team page) or join it.
//   5. The captain cannot leave while captain; hands the role to the
//      requester, is no longer captain, and leaves. The new captain deletes
//      the team.
//   6. Everything made here (the team and its members, requests and
//      invites, the game, the booking, the court, the venue, the admin's
//      audit rows, the app_admins row, the accounts) is deleted, whatever
//      happened; what is left is printed, and anything left fails the run.
//
//   node scripts/e2e-teams.mjs
//
// It writes to the hosted project: run it only when asked to.

import assert from 'node:assert/strict';
import { randomInt } from 'node:crypto';
import { createdUsersSql, env, removeAccounts, rpc, saveProfile, signIn } from './e2e-lib.mjs';
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

const kinds = async (session) => (await ok(session, 'my_notifications', { p_limit: 50 })).map((n) => n.kind);
const memberIds = (team) => team.members.map((m) => m.id);

// -- 0. Preconditions (read-only, before anything is created) ---------------
step('Checking the live database is ready for M7 teams');
const ready = (await sql(env, `select to_regclass('public.teams')::text as teams,
                                      exists (select 1 from information_schema.columns
                                              where table_schema = 'public' and table_name = 'games'
                                                and column_name = 'team_id') as team_games`))[0];
if (!ready.teams || ready.team_games !== true) {
  console.error('  The M7 team tables are missing: run `node scripts/deploy.mjs migrations` first. Nothing was created.');
  process.exit(1);
}
console.log('  teams and games.team_id present');

let venueId = null;
let failed = false;
try {
  step('Signing in an admin, a captain, a requester, an invitee and an outsider');
  const suffix = String(randomInt(10_000_000)).padStart(7, '0');
  const stamp = new Date().toISOString().replace(/\D/g, '').slice(0, 14);
  const admin = await signIn('admin', `+99809${suffix}`);
  const captain = await signIn('captain', `+99805${suffix}`);
  const requester = await signIn('requester', `+99806${suffix}`);
  const invitee = await signIn('invitee', `+99807${suffix}`);
  const outsider = await signIn('outsider', `+99808${suffix}`);
  const tag = [...suffix].map((d) => 'abcdefghij'[d]).join('');
  await saveProfile(admin, `E2E M7 Admin ${tag}`);
  await saveProfile(captain, `E2E M7 Captain ${tag}`);
  await saveProfile(requester, `E2E M7 Requester ${tag}`);
  await saveProfile(invitee, `E2E M7 Invitee ${tag}`);
  await saveProfile(outsider, `E2E M7 Outsider ${tag}`);
  const today = (await sql(env, `select (app.to_local(now(), 300))::date::text as d`))[0].d;

  step('The admin creates a throw-away venue with one padel court');
  await sql(env, `insert into public.app_admins (user_id) values ('${admin.userId}')`, { write: true });
  venueId = await ok(admin, 'admin_save_venue', {
    p_venue: { city_id: 'tashkent', name_en: `E2E M7 teams ${stamp}`, address_en: 'Nowhere 1', district_en: 'Test', phone: '+998710000000' },
  });
  const court = await ok(admin, 'admin_save_court', {
    p_court: { venue_id: venueId, sport_id: 'padel', name_en: 'Court 1', slot_minutes: 60, base_price: 100000, indoor: true },
  });
  console.log(`  venue ${venueId}, court ${court}`);

  step('The captain creates an approval team; the requester asks and is approved');
  // Names are unique per city and sport on the live project: the tag keeps it free.
  const team = await ok(captain, 'create_team', {
    p_team: { name: `E2E M7 ${tag}`, sport_id: 'padel', city_id: 'tashkent', join_policy: 'approval', description: 'E2E check' },
  });
  assert.equal(team.my_status, 'captain');
  assert.equal(team.captain_id, captain.userId);
  assert.equal(team.member_count, 1);
  const asked = await ok(requester, 'join_team', { p_team_id: team.id });
  assert.equal(asked.my_status, 'requested');
  assert.ok(asked.my_request_id);
  await refused(requester, 'join_team', { p_team_id: team.id }, 'already_requested');
  await refused(outsider, 'decide_team_request', { p_request_id: asked.my_request_id, p_approve: true }, 'not_allowed');
  assert.ok((await kinds(captain)).includes('team_join_request'));
  const captainView = await ok(captain, 'get_team', { p_team_id: team.id });
  assert.deepEqual(captainView.requests.map((r) => r.user_id), [requester.userId]);
  const approved = await ok(captain, 'decide_team_request', { p_request_id: asked.my_request_id, p_approve: true });
  assert.deepEqual(memberIds(approved), [captain.userId, requester.userId]);
  assert.ok((await kinds(requester)).includes('team_join_approved'));
  assert.equal((await ok(requester, 'get_team', { p_team_id: team.id })).my_status, 'member');
  console.log(`  team ${team.id}: requested, refused to a stranger, approved`);

  step('The captain invites the invitee, who accepts');
  await ok(captain, 'invite_to_team', { p_team_id: team.id, p_invitee: invitee.userId });
  assert.ok((await kinds(invitee)).includes('team_invite'));
  assert.equal((await ok(invitee, 'get_team', { p_team_id: team.id })).my_status, 'invited');
  const accepted = await ok(invitee, 'respond_team_invite', { p_team_id: team.id, p_accept: true });
  assert.equal(accepted.my_status, 'member');
  assert.equal(accepted.member_count, 3);
  const listedTeams = await ok(outsider, 'list_teams', { p_city_id: 'tashkent' });
  assert.equal(listedTeams.find((t) => t.id === team.id)?.my_status, null, 'the outsider sees the team as a stranger');
  console.log('  invited, accepted; three members');

  step('The captain posts a team game on the throw-away court');
  let slot = null;
  for (let ahead = 3; ahead <= 10 && !slot; ahead++) {
    const day = await ok(captain, 'court_availability', { p_court_id: court, p_date: addDays(today, ahead) });
    slot = day.find((s) => s.state === 'free') ?? null;
  }
  assert.ok(slot, 'no free slot found on the throw-away court');
  const held = await ok(captain, 'hold_slots', { p_court_id: court, p_starts: [slot.starts_local] });
  const booking = await ok(captain, 'confirm_booking', { p_booking_id: held.id, p_players: 4, p_note: 'e2e m7 teams' });
  assert.equal(booking.status, 'confirmed');
  // No open_hours_before: the game never opens to everyone.
  const game = await ok(captain, 'create_game', {
    p_game: { sport_id: 'padel', booking_id: booking.id, spots: 4, team_id: team.id },
  });
  assert.equal(game.visibility, 'invite_only');
  assert.equal(game.team?.id, team.id);
  assert.equal(game.public_from_local, null);
  for (const s of [requester, invitee]) assert.ok((await kinds(s)).includes('team_game_posted'));
  console.log(`  game ${game.id} on booking ${booking.id} (${slot.starts_local})`);

  step('The member sees and joins the game; the outsider cannot see it');
  const memberView = await ok(requester, 'get_game', { p_game_id: game.id });
  assert.equal(memberView?.id, game.id, 'the member cannot see the team game');
  assert.ok((await ok(requester, 'list_games', { p_city_id: 'tashkent' })).some((g) => g.id === game.id));
  assert.ok((await ok(requester, 'get_team', { p_team_id: team.id })).games.some((g) => g.id === game.id));
  assert.equal((await ok(requester, 'join_game', { p_game_id: game.id })).my_status, 'participant');
  assert.equal(await ok(outsider, 'get_game', { p_game_id: game.id }), null);
  assert.ok(!(await ok(outsider, 'list_games', { p_city_id: 'tashkent' })).some((g) => g.id === game.id));
  const outsiderTeam = await ok(outsider, 'get_team', { p_team_id: team.id });
  assert.ok(!outsiderTeam.games.some((g) => g.id === game.id), 'the team page shows the game to the outsider');
  assert.equal(outsiderTeam.upcoming_games, 1);
  await refused(outsider, 'join_game', { p_game_id: game.id }, 'not_found');
  await refused(outsider, 'request_to_join', { p_game_id: game.id }, 'not_found');
  console.log('  member: visible, listed, joined; outsider: null, not listed, refused');

  step('The captain hands the role over and leaves; the new captain deletes the team');
  await refused(captain, 'leave_team', { p_team_id: team.id }, 'captain_cannot_leave');
  const handed = await ok(captain, 'transfer_captain', { p_team_id: team.id, p_member: requester.userId });
  assert.equal(handed.captain_id, requester.userId);
  assert.equal(handed.my_status, 'member', 'the old captain is a plain member now');
  assert.ok((await kinds(requester)).includes('team_captain'));
  await refused(captain, 'transfer_captain', { p_team_id: team.id, p_member: invitee.userId }, 'not_allowed');
  await ok(captain, 'leave_team', { p_team_id: team.id });
  const after = await ok(requester, 'get_team', { p_team_id: team.id });
  assert.equal(after.my_status, 'captain');
  assert.deepEqual(memberIds(after).sort(), [requester.userId, invitee.userId].sort());
  await ok(requester, 'delete_team', { p_team_id: team.id });
  assert.equal(await ok(invitee, 'get_team', { p_team_id: team.id }), null);
  assert.ok((await kinds(invitee)).includes('team_deleted'));
  console.log('  transferred, left, deleted');

  console.log('\nTEAMS END TO END: PASSED');
} catch (e) {
  failed = true;
  console.error(`\nTEAMS END TO END: FAILED\n${e.stack ?? e}`);
} finally {
  step('Cleaning up the throw-away team, venue, game and accounts');
  const users = createdUsersSql();
  await removeAccounts({
    before: [
      ...(users
        ? [
            // Members, requests and invites go with their team.
            `delete from public.teams where captain_id in (${users})`,
            `delete from public.team_members where user_id in (${users})`,
            `delete from public.team_join_requests where user_id in (${users})`,
            `delete from public.team_invites where user_id in (${users})`,
            // Neither games nor bookings cascade from the accounts.
            `delete from public.games where host_id in (${users})`,
          ]
        : []),
      ...(venueId
        ? [
            `delete from public.bookings where venue_id = '${venueId}'`,
            `delete from public.courts where venue_id = '${venueId}'`,
            `delete from public.venues where id = '${venueId}'`,
          ]
        : []),
      ...(users
        ? [`delete from public.audit_log where actor_id in (${users})`, `delete from public.app_admins where user_id in (${users})`]
        : []),
    ],
  });

  const counts = {
    'test venues': `select count(*) from public.venues where name_en like 'E2E M7%'`,
    ...(venueId ? { 'venue bookings': `select count(*) from public.bookings where venue_id = '${venueId}'` } : {}),
    ...(users
      ? {
          teams: `select count(*) from public.teams where captain_id in (${users})`,
          'team members': `select count(*) from public.team_members where user_id in (${users})`,
          'team requests': `select count(*) from public.team_join_requests where user_id in (${users})`,
          'team invites': `select count(*) from public.team_invites where user_id in (${users})`,
          games: `select count(*) from public.games where host_id in (${users})`,
          'audit rows': `select count(*) from public.audit_log where actor_id in (${users})`,
          admins: `select count(*) from public.app_admins where user_id in (${users})`,
          profiles: `select count(*) from public.profiles where id in (${users})`,
        }
      : {}),
  };
  try {
    const row = (await sql(env, `select ${Object.entries(counts).map(([k, q]) => `(${q})::int as "${k}"`).join(', ')}`))[0];
    const left = Object.entries(row).filter(([, n]) => n > 0);
    console.log(`  left behind: ${left.length ? left.map(([k, n]) => `${n} ${k}`).join(', ') : 'nothing'}`);
    if (left.length) failed = true;
  } catch (e) {
    failed = true;
    console.error(`  could not count what is left: ${e.message}`);
  }
}
process.exit(failed ? 1 : 0);
