// Milestone 7, Task 11: teams — creating and editing, joining (open or by
// approval), invites, leaving, removing members, handing over the captain
// role, deleting, admin removal, the team JSON and lists, and deleting an
// account (design 2026-11-27-actra-m7-competitive §7).
// The `app` functions are called with a fixed clock; the client calls at the
// end go through the public wrappers, which pass now().

import assert from 'node:assert/strict';
import { after, before, beforeEach, test } from 'node:test';
import { asUser, createUser, expectError, freshDb } from './helpers/db.mjs';
import { addAdmin, addRatedSports, tashkent } from './helpers/fixtures.mjs';

let db;
let pool;

const now = tashkent('2026-11-22', 20);

before(async () => {
  db = await freshDb('teams');
  pool = db.pool;
  await addRatedSports(pool);
});
after(() => db.end());

// Lists and notices look at every team: start each test clean.
beforeEach(async () => {
  await pool.query('delete from teams');
  await pool.query('delete from notifications');
  await pool.query('delete from audit_log');
});

const one = async (sql, params) => (await pool.query(sql, params)).rows[0];

async function player(name, { city = 'tashkent' } = {}) {
  const id = await createUser(pool, name);
  await pool.query(`update profiles set city_id = $2 where id = $1`, [id, city]);
  return id;
}
const players = (...names) => Promise.all(names.map((n) => player(n)));

const spec = (name, extra = {}) => ({ name, sport_id: 'football', city_id: 'tashkent', join_policy: 'open', ...extra });

const create = (user, team, at = now) => one(`select * from app.create_team($1, $2, $3)`, [user, team, at]);
const update = (user, teamId, team, at = now) => one(`select * from app.update_team($1, $2, $3, $4)`, [user, teamId, team, at]);
const deleteTeam = (user, teamId, at = now) => pool.query(`select app.delete_team($1, $2, $3)`, [user, teamId, at]);
const join = (user, teamId, at = now) => one(`select * from app.join_team($1, $2, $3)`, [user, teamId, at]);
const leave = (user, teamId, at = now) => pool.query(`select app.leave_team($1, $2, $3)`, [user, teamId, at]);
const withdraw = (user, requestId) => pool.query(`select app.withdraw_team_request($1, $2)`, [user, requestId]);
const decide = (user, requestId, approve, at = now) =>
  one(`select * from app.decide_team_request($1, $2, $3, $4)`, [user, requestId, approve, at]);
const remove = (user, teamId, member, at = now) => one(`select * from app.remove_team_member($1, $2, $3, $4)`, [user, teamId, member, at]);
const invite = (user, teamId, invitee, at = now) => pool.query(`select app.invite_to_team($1, $2, $3, $4)`, [user, teamId, invitee, at]);
const respond = (user, teamId, accept, at = now) => one(`select * from app.respond_team_invite($1, $2, $3, $4)`, [user, teamId, accept, at]);
const transfer = (user, teamId, member, at = now) => one(`select * from app.transfer_captain($1, $2, $3, $4)`, [user, teamId, member, at]);
const adminDelete = (user, teamId, at = now) => pool.query(`select app.admin_delete_team($1, $2, $3)`, [user, teamId, at]);

const summary = (teamId, user) => one(`select app.team_summary_json(t, $2) as j from teams t where t.id = $1`, [teamId, user]).then((r) => r.j);
const teamJson = (teamId, user) => one(`select app.team_json(t, $2) as j from teams t where t.id = $1`, [teamId, user]).then((r) => r.j);
const listTeams = (user, city) =>
  pool.query(`select t from app.list_teams($1, $2) t`, [user, city]).then((r) => r.rows.map((x) => x.t));
const memberIds = (teamId) =>
  pool.query(`select user_id from team_members where team_id = $1 order by user_id`, [teamId]).then((r) => r.rows.map((x) => x.user_id));
const notices = (kind) =>
  pool
    .query(`select user_id, category, payload from notifications where kind = $1 order by user_id`, [kind])
    .then((r) => r.rows);
const pendingRequest = (teamId, user) =>
  one(`select id from team_join_requests where team_id = $1 and user_id = $2 and status = 'pending'`, [teamId, user]).then((r) => r?.id);
const sorted = (ids) => [...ids].sort();

/** A team captained by `captain` with those other members, joined in order. */
async function teamWith(captain, members = [], extra = {}) {
  const team = await create(captain, spec(extra.name ?? `Team ${Math.random().toString(36).slice(2, 8)}`, extra));
  for (const [i, m] of members.entries()) await join(m, team.id, new Date(Date.parse(now) + (i + 1) * 60000).toISOString());
  return team;
}

// --- creating ----------------------------------------------------------------

test('create a team', async () => {
  const cap = await player('Create cap');
  const team = await create(cap, spec('  Tashkent Tigers  ', { description: '  Sunday games  ', join_policy: 'approval' }));
  assert.equal(team.name, 'Tashkent Tigers');
  assert.equal(team.description, 'Sunday games');
  assert.equal(team.join_policy, 'approval');
  assert.equal(team.captain_id, cap);
  assert.ok(team.color_seed >= 0 && team.color_seed <= 7);
  assert.deepEqual(await memberIds(team.id), [cap]);

  const s = await summary(team.id, cap);
  assert.deepEqual(Object.keys(s).sort(), [
    'captain_id', 'city_id', 'color_seed', 'description', 'id', 'join_policy', 'member_count', 'my_request_id', 'my_status',
    'name', 'sport_id', 'upcoming_games',
  ]);
  assert.equal(s.member_count, 1);
  assert.equal(s.my_status, 'captain');
  assert.equal(s.upcoming_games, 0);
  assert.equal(s.my_request_id, null);
  assert.equal((await summary(team.id, await player('Stranger'))).my_status, null);

  for (const bad of [
    spec('ab'),
    spec('x'.repeat(41)),
    spec('   '),
    spec('Bad sport', { sport_id: 'curling' }),
    spec('Bad city', { city_id: 'atlantis' }),
    spec('Bad policy', { join_policy: 'secret' }),
    spec('No policy', { join_policy: null }),
    spec('Long text', { description: 'x'.repeat(501) }),
  ]) {
    await expectError(create(cap, bad), 'invalid_argument');
  }
  await pool.query(`update sports set active = false where id = 'tennis'`);
  await expectError(create(cap, spec('Inactive', { sport_id: 'tennis' })), 'invalid_argument');
  await pool.query(`update sports set active = true where id = 'tennis'`);
  await expectError(create(null, spec('Nobody')), 'not_authenticated');
});

test('team names are unique per city and sport', async () => {
  const [a, b] = await players('Unique A', 'Unique B');
  await create(a, spec('Lions'));
  await expectError(create(b, spec('  LIONS ')), 'already_exists');
  await create(b, spec('Lions', { sport_id: 'padel' }));
  await create(b, spec('Lions', { city_id: 'almaty' }));

  const other = await create(a, spec('Tigers'));
  await expectError(update(a, other.id, { name: 'lions' }), 'already_exists');
  const renamed = await update(a, other.id, { name: 'Tigers FC', description: 'New', join_policy: 'approval' });
  assert.equal(renamed.name, 'Tigers FC');
  assert.equal(renamed.description, 'New');
  assert.equal(renamed.join_policy, 'approval');
  // Absent keys stay as they were.
  const kept = await update(a, other.id, { description: null });
  assert.equal(kept.name, 'Tigers FC');
  assert.equal(kept.description, null);
  assert.equal(kept.join_policy, 'approval');
  await expectError(update(a, other.id, { name: 'ab' }), 'invalid_argument');
  await expectError(update(a, other.id, { join_policy: 'secret' }), 'invalid_argument');
});

test('six teams is too many', async () => {
  const cap = await player('Busy cap');
  for (let i = 1; i <= 5; i++) await create(cap, spec(`Busy ${i}`));
  await expectError(create(cap, spec('Busy 6')), 'team_limit');
  // Joining another team as a member is still fine; handing one over frees a place.
  const other = await player('Other cap');
  const t = await create(other, spec('Elsewhere'));
  await join(cap, t.id);
  const busy1 = await one(`select id from teams where name = 'Busy 1'`);
  await join(other, busy1.id);
  await transfer(cap, busy1.id, other);
  await create(cap, spec('Busy 6'));
});

// --- joining -----------------------------------------------------------------

test('open team joins at once', async () => {
  const [cap, m] = await players('Open cap', 'Open member');
  const team = await create(cap, spec('Open team'));
  const after = await join(m, team.id);
  assert.equal(after.id, team.id);
  assert.deepEqual(await memberIds(team.id), sorted([cap, m]));
  assert.equal((await summary(team.id, m)).my_status, 'member');
  assert.equal((await summary(team.id, m)).member_count, 2);
  await expectError(join(m, team.id), 'already_joined');
  await expectError(join(cap, team.id), 'already_joined');
  assert.equal((await notices('team_join_request')).length, 0);

  // Members can leave.
  await leave(m, team.id);
  assert.deepEqual(await memberIds(team.id), [cap]);
  await expectError(leave(m, team.id), 'not_found');
});

test('approval team needs the captain', async () => {
  const [cap, a, b] = await players('Approval cap', 'Approval A', 'Approval B');
  const team = await create(cap, spec('Approval team', { join_policy: 'approval' }));

  await join(a, team.id);
  assert.deepEqual(await memberIds(team.id), [cap]);
  const requestId = await pendingRequest(team.id, a);
  assert.ok(requestId);
  assert.deepEqual(await notices('team_join_request'), [
    { user_id: cap, category: 'teams', payload: { team_id: team.id, team_name: 'Approval team', actor_name: 'Approval A' } },
  ]);
  const s = await summary(team.id, a);
  assert.equal(s.my_status, 'requested');
  assert.equal(s.my_request_id, requestId);
  await expectError(join(a, team.id), 'already_requested');

  const capView = await teamJson(team.id, cap);
  assert.deepEqual(capView.requests.map((r) => [r.id, r.user_id, r.name]), [[requestId, a, 'Approval A']]);
  assert.deepEqual(Object.keys(capView.requests[0]).sort(), ['created_at', 'id', 'level', 'name', 'rating', 'reliability', 'user_id']);

  const approved = await decide(cap, requestId, true);
  assert.equal(approved.id, team.id);
  assert.deepEqual(await memberIds(team.id), sorted([cap, a]));
  assert.deepEqual(await notices('team_join_approved'), [
    { user_id: a, category: 'teams', payload: { team_id: team.id, team_name: 'Approval team', actor_name: 'Approval cap' } },
  ]);
  await expectError(decide(cap, requestId, true), 'not_found');
  assert.deepEqual((await teamJson(team.id, cap)).requests, []);

  await join(b, team.id);
  await decide(cap, await pendingRequest(team.id, b), false);
  assert.deepEqual(await memberIds(team.id), sorted([cap, a]));
  assert.deepEqual((await notices('team_join_declined')).map((n) => n.user_id), [b]);

  // Asking again after a decline, then withdrawing.
  await join(b, team.id);
  const again = await pendingRequest(team.id, b);
  await expectError(withdraw(a, again), 'not_found');
  await withdraw(b, again);
  assert.equal(await pendingRequest(team.id, b), undefined);
  assert.equal((await summary(team.id, b)).my_status, null);
  await expectError(withdraw(b, again), 'not_found');
});

test('invite and accept', async () => {
  const [cap, a, b] = await players('Invite cap', 'Invite A', 'Invite B');
  const team = await create(cap, spec('Invite team', { join_policy: 'approval' }));

  await invite(cap, team.id, a);
  assert.deepEqual(await notices('team_invite'), [
    { user_id: a, category: 'teams', payload: { team_id: team.id, team_name: 'Invite team', actor_name: 'Invite cap' } },
  ]);
  assert.equal((await summary(team.id, a)).my_status, 'invited');
  // Inviting again while open sends nothing new.
  await invite(cap, team.id, a);
  assert.equal((await notices('team_invite')).length, 1);

  const joined = await respond(a, team.id, true);
  assert.equal(joined.id, team.id);
  assert.deepEqual(await memberIds(team.id), sorted([cap, a]));
  assert.equal((await one(`select status from team_invites where team_id = $1 and user_id = $2`, [team.id, a])).status, 'accepted');
  await expectError(respond(a, team.id, true), 'not_found');
  await expectError(invite(cap, team.id, a), 'already_joined');

  await invite(cap, team.id, b);
  await respond(b, team.id, false);
  assert.deepEqual(await memberIds(team.id), sorted([cap, a]));
  assert.equal((await one(`select status from team_invites where team_id = $1 and user_id = $2`, [team.id, b])).status, 'declined');

  // Re-inviting a declined player opens the invite again.
  await invite(cap, team.id, b);
  assert.equal((await one(`select status from team_invites where team_id = $1 and user_id = $2`, [team.id, b])).status, 'pending');
  assert.equal((await notices('team_invite')).filter((n) => n.user_id === b).length, 2);

  // With a pending invite, joining an approval team needs no request.
  await join(b, team.id);
  assert.deepEqual(await memberIds(team.id), sorted([cap, a, b]));
  assert.equal(await pendingRequest(team.id, b), undefined);

  // A pending request is settled when an invite is accepted.
  const d = await player('Invite D');
  await join(d, team.id);
  assert.ok(await pendingRequest(team.id, d));
  await invite(cap, team.id, d);
  assert.equal((await summary(team.id, d)).my_status, 'invited');
  await respond(d, team.id, true);
  assert.equal(await pendingRequest(team.id, d), undefined);
  assert.deepEqual((await teamJson(team.id, cap)).requests, []);

  await expectError(invite(cap, team.id, cap), 'invalid_argument');
  await expectError(invite(cap, team.id, '00000000-0000-0000-0000-000000000001'), 'not_found');
  const gone = await player('Invite gone');
  await pool.query(`update profiles set deleted_at = $2 where id = $1`, [gone, now]);
  await expectError(invite(cap, team.id, gone), 'not_found');

  // An open team: joining accepts a pending invite.
  const open = await create(cap, spec('Invite open'));
  const c = await player('Invite C');
  await invite(cap, open.id, c);
  await join(c, open.id);
  assert.equal((await one(`select status from team_invites where team_id = $1 and user_id = $2`, [open.id, c])).status, 'accepted');
});

test('only the captain manages', async () => {
  const [cap, m, other, outsider] = await players('Manage cap', 'Manage member', 'Manage other', 'Manage outsider');
  const team = await teamWith(cap, [m, other], { join_policy: 'open' });
  await update(cap, team.id, { join_policy: 'approval' });
  await join(outsider, team.id);
  const requestId = await pendingRequest(team.id, outsider);

  await expectError(update(m, team.id, { name: 'Taken over' }), 'not_allowed');
  await expectError(deleteTeam(m, team.id), 'not_allowed');
  await expectError(decide(m, requestId, true), 'not_allowed');
  await expectError(remove(m, team.id, other), 'not_allowed');
  await expectError(invite(m, team.id, outsider), 'not_allowed');
  await expectError(transfer(m, team.id, other), 'not_allowed');
  assert.equal((await one(`select captain_id from teams where id = $1`, [team.id])).captain_id, cap);
  assert.deepEqual(await memberIds(team.id), sorted([cap, m, other]));
});

test('captain cannot leave until they hand over', async () => {
  const [cap, m, stranger] = await players('Leave cap', 'Leave member', 'Leave stranger');
  const team = await teamWith(cap, [m]);
  await expectError(leave(cap, team.id), 'captain_cannot_leave');
  await expectError(transfer(cap, team.id, stranger), 'not_found');

  const handed = await transfer(cap, team.id, m);
  assert.equal(handed.captain_id, m);
  assert.deepEqual(await notices('team_captain'), [
    { user_id: m, category: 'teams', payload: { team_id: team.id, team_name: handed.name, actor_name: 'Leave cap' } },
  ]);
  assert.equal((await summary(team.id, m)).my_status, 'captain');
  assert.equal((await summary(team.id, cap)).my_status, 'member');

  await leave(cap, team.id);
  assert.deepEqual(await memberIds(team.id), [m]);
});

test('remove a member', async () => {
  const [cap, m] = await players('Remove cap', 'Remove member');
  const team = await teamWith(cap, [m]);
  await expectError(remove(cap, team.id, cap), 'invalid_argument');
  const after = await remove(cap, team.id, m);
  assert.equal(after.id, team.id);
  assert.deepEqual(await memberIds(team.id), [cap]);
  assert.deepEqual(await notices('team_removed'), [
    { user_id: m, category: 'teams', payload: { team_id: team.id, team_name: team.name, actor_name: 'Remove cap' } },
  ]);
  await expectError(remove(cap, team.id, m), 'not_found');
});

test('delete a team notifies members', async () => {
  const [cap, a, b] = await players('Delete cap', 'Delete A', 'Delete B');
  const team = await teamWith(cap, [a, b]);
  await deleteTeam(cap, team.id);
  assert.equal((await one(`select count(*)::int as n from teams where id = $1`, [team.id])).n, 0);
  assert.equal((await one(`select count(*)::int as n from team_members where team_id = $1`, [team.id])).n, 0);
  const sent = await notices('team_deleted');
  assert.deepEqual(sent.map((n) => n.user_id), sorted([a, b]));
  assert.deepEqual(sent[0].payload, { team_id: team.id, team_name: team.name, actor_name: 'Delete cap' });
  await expectError(deleteTeam(cap, team.id), 'not_found');
});

test('team lists', async () => {
  const [me, x, y, z] = await players('List me', 'List X', 'List Y', 'List Z');
  const far = await player('List far', { city: 'almaty' });
  const mine = await create(far, spec('Almaty Eagles', { city_id: 'almaty' }));
  await join(me, mine.id);
  const small = await create(x, spec('Alpha small'));
  const big = await teamWith(y, [z], { name: 'Zeta big' });
  await create(far, spec('Almaty other', { city_id: 'almaty' }));

  const list = await listTeams(me, 'tashkent');
  assert.deepEqual(list.map((t) => t.id), [mine.id, big.id, small.id]);
  assert.equal(list[0].my_status, 'member');
  assert.equal(list[1].member_count, 2);

  // Members carry level, rating and reliability; captain first.
  await pool.query(`insert into player_levels (user_id, sport_id, level) values ($1, 'football', 3)`, [z]);
  const view = await teamJson(big.id, z);
  assert.deepEqual(view.members.map((m) => [m.id, m.captain]), [[y, true], [z, false]]);
  assert.equal(view.members[1].level, 3);
  assert.equal(view.members[0].level, null);
  assert.ok(view.members[1].reliability.badge);
  assert.deepEqual(Object.keys(view.members[1]).sort(), ['captain', 'id', 'level', 'name', 'provisional', 'rating', 'reliability']);
  assert.deepEqual(view.games, []);
  assert.ok(!('requests' in view));
  assert.ok('requests' in (await teamJson(big.id, y)));

  // A rated sport shows the rating.
  const padel = await create(x, spec('Padel pals', { sport_id: 'padel' }));
  await pool.query(
    `insert into player_ratings (user_id, sport_id, rating, rated_games, source, updated_at) values ($1, 'padel', 3.25, 2, 'questionnaire', $2)`,
    [x, now],
  );
  const padelView = await teamJson(padel.id, me);
  assert.equal(Number(padelView.members[0].rating), 3.25);
  assert.equal(padelView.members[0].provisional, true);

  // A deleted member (partial data) shows the marker.
  await pool.query(`update profiles set deleted_at = $2, full_name = null where id = $1`, [z, now]);
  const withDeleted = await teamJson(big.id, y);
  assert.equal(withDeleted.members.find((m) => m.id === z).deleted, true);
  assert.ok(!('deleted' in withDeleted.members.find((m) => m.id === y)));
});

test('player json lists teams', async () => {
  const [cap, m] = await players('Json cap', 'Json member');
  const a = await create(cap, spec('B team'));
  const b = await create(cap, spec('A team', { sport_id: 'padel' }));
  await join(m, a.id);
  const p = await one(`select app.player_json(pr) as p from profiles pr where pr.id = $1`, [cap]).then((r) => r.p);
  assert.deepEqual(p.teams, [
    { id: b.id, name: 'A team', sport_id: 'padel' },
    { id: a.id, name: 'B team', sport_id: 'football' },
  ]);
  const q = await one(`select app.player_json(pr) as p from profiles pr where pr.id = $1`, [m]).then((r) => r.p);
  assert.deepEqual(q.teams, [{ id: a.id, name: 'B team', sport_id: 'football' }]);
});

test('admin deletes a team', async () => {
  const [cap, m, admin, nobody] = await players('Admin cap', 'Admin member', 'Admin', 'Admin nobody');
  await addAdmin(pool, admin);
  const team = await teamWith(cap, [m]);
  await expectError(adminDelete(nobody, team.id), 'not_allowed');
  await adminDelete(admin, team.id);
  assert.equal((await one(`select count(*)::int as n from teams where id = $1`, [team.id])).n, 0);
  const audit = await one(`select actor_id, action, entity, entity_id, before, after from audit_log where entity_id = $1`, [team.id]);
  assert.equal(audit.actor_id, admin);
  assert.equal(audit.action, 'team_deleted');
  assert.equal(audit.entity, 'team');
  assert.equal(audit.before.name, team.name);
  assert.equal(audit.before.captain_id, cap);
  assert.equal(audit.after, null);
  assert.deepEqual((await notices('team_deleted')).map((n) => n.user_id), sorted([cap, m]));
  await expectError(adminDelete(admin, team.id), 'not_found');
});

test('captain account deleted', async () => {
  const [cap, oldest, newer, joiner, invitee] = await players('Gone cap', 'Oldest', 'Newer', 'Joiner', 'Invitee');
  const team = await teamWith(cap, [oldest, newer]);
  const solo = await create(cap, spec('Solo team'));
  const elsewhere = await create(joiner, spec('Elsewhere team', { join_policy: 'approval' }));
  await join(cap, elsewhere.id);
  await invite(joiner, elsewhere.id, cap);
  const open = await create(invitee, spec('Member team'));
  await join(cap, open.id);

  await pool.query(`select app.delete_account($1, $2)`, [cap, now]);

  const t = await one(`select captain_id from teams where id = $1`, [team.id]);
  assert.equal(t.captain_id, oldest);
  assert.deepEqual(await memberIds(team.id), sorted([oldest, newer]));
  assert.deepEqual(await notices('team_captain'), [
    { user_id: oldest, category: 'teams', payload: { team_id: team.id, team_name: team.name, actor_name: 'Gone cap' } },
  ]);
  assert.equal((await one(`select count(*)::int as n from teams where id = $1`, [solo.id])).n, 0);
  assert.deepEqual(await memberIds(open.id), [invitee]);
  for (const table of ['team_members', 'team_join_requests', 'team_invites']) {
    assert.equal((await one(`select count(*)::int as n from ${table} where user_id = $1`, [cap])).n, 0, table);
  }
  // A second call does nothing; the deleted account can no longer be invited.
  await pool.query(`select app.delete_account($1, $2)`, [cap, now]);
  await expectError(invite(joiner, elsewhere.id, cap), 'not_found');
});

// --- through the API -----------------------------------------------------------

test('through the API: a team from creation to deletion', async () => {
  const [cap, m] = await players('Api cap', 'Api member');
  const call = (user, sql, params = []) => asUser(pool, user, (c) => c.query(sql, params).then((r) => r.rows));

  const [{ t: created }] = await call(cap, `select public.create_team($1) as t`, [spec('Api team', { join_policy: 'approval' })]);
  assert.equal(created.my_status, 'captain');
  assert.deepEqual(created.members.map((x) => x.id), [cap]);
  assert.deepEqual(created.requests, []);
  assert.deepEqual(created.games, []);

  const [{ t: requested }] = await call(m, `select public.join_team($1) as t`, [created.id]);
  assert.equal(requested.my_status, 'requested');
  assert.ok(!('requests' in requested));
  await call(m, `select public.withdraw_team_request($1)`, [requested.my_request_id]);
  await call(m, `select public.join_team($1)`, [created.id]);
  const requestId = await pendingRequest(created.id, m);
  const [{ t: decided }] = await call(cap, `select public.decide_team_request($1, true) as t`, [requestId]);
  assert.equal(decided.member_count, 2);

  const [{ t: updated }] = await call(cap, `select public.update_team($1, $2) as t`, [created.id, { description: 'Hello' }]);
  assert.equal(updated.description, 'Hello');
  const [{ t: listed }] = await call(m, `select public.list_teams('tashkent') as t`);
  assert.equal(listed.id, created.id);
  const [{ t: got }] = await call(m, `select public.get_team($1) as t`, [created.id]);
  assert.equal(got.my_status, 'member');
  assert.equal((await call(m, `select public.get_team($1) as t`, ['00000000-0000-0000-0000-000000000001']))[0].t, null);

  const [{ t: handed }] = await call(cap, `select public.transfer_captain($1, $2) as t`, [created.id, m]);
  assert.equal(handed.captain_id, m);
  await call(cap, `select public.leave_team($1)`, [created.id]);
  await call(m, `select public.invite_to_team($1, $2)`, [created.id, cap]);
  const [{ t: back }] = await call(cap, `select public.respond_team_invite($1, true) as t`, [created.id]);
  assert.equal(back.my_status, 'member');
  const [{ t: removed }] = await call(m, `select public.remove_team_member($1, $2) as t`, [created.id, cap]);
  assert.equal(removed.member_count, 1);

  const admin = await player('Api admin');
  await addAdmin(pool, admin);
  await expectError(call(m, `select public.admin_delete_team($1)`, [created.id]), 'not_allowed');
  await call(m, `select public.delete_team($1)`, [created.id]);
  const second = await call(admin, `select public.create_team($1) as t`, [spec('Api second')]);
  await call(admin, `select public.admin_delete_team($1)`, [second[0].t.id]);

  await expectError(call(m, `select app.create_team($1, $2, now())`, [m, spec('Direct')]), '42501');
  await expectError(call(m, `select * from teams`), '42501');
});
