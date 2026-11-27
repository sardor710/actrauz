// Milestone 8a, Task 1: organisers, draws and seeding. The `app` functions
// are called with the acting user and a fixed clock; the last tests go
// through the `public` wrappers as the API would.

import assert from 'node:assert/strict';
import { after, before, beforeEach, test } from 'node:test';
import { asUser, createUser, errorOf, expectError, freshDb } from './helpers/db.mjs';
import { addAdmin, addCategory, addEntries, addPhone, addRatedSports, addTournament, tashkent } from './helpers/fixtures.mjs';

let db;
let pool;
let admin;

// Sunday evening in Tashkent; tournaments start on 10 December.
const now = tashkent('2026-11-22', 20);
const later = (hours) => new Date(Date.parse(now) + hours * 3600000).toISOString();

before(async () => {
  db = await freshDb('draws');
  pool = db.pool;
  await addRatedSports(pool);
  admin = await addAdmin(pool, await createUser(pool, 'Admin'));
});
after(() => db.end());

beforeEach(async () => {
  await pool.query('delete from audit_log');
  await pool.query('delete from notifications');
  await pool.query('delete from tournament_registrations');
  await pool.query('delete from tournaments');
});

const one = async (sql, params) => (await pool.query(sql, params)).rows[0];
const scalar = async (sql, params) => (await one(sql, params))?.r;

const makeDraw = (user, cat, format = 'knockout', size = null, advance = null) =>
  pool.query(`select app.make_draw($1, $2, $3, $4, $5, $6)`, [user, cat, format, size, advance, now]);
const swap = (user, cat, a, b) => pool.query(`select app.swap_draw_entries($1, $2, $3, $4, $5)`, [user, cat, a, b, now]);
const publish = (user, cat, when = now) => pool.query(`select app.publish_draw($1, $2, $3)`, [user, cat, when]);
const redo = (user, cat) => pool.query(`select app.redo_draw($1, $2, $3)`, [user, cat, now]);
const drawJson = (cat, user = admin) => scalar(`select app.draw_json($1, $2) as r`, [cat, user]);
const setOrganizer = (user, t, target, add) => pool.query(`select app.admin_set_organizer($1, $2, $3, $4, $5)`, [user, t, target, add, now]);

const statusOf = (id) => one(`select status from tournament_registrations where id = $1`, [id]).then((r) => r.status);
const notesOf = (user, kind) =>
  pool.query(`select * from notifications where user_id = $1 and kind = $2 order by created_at, id`, [user, kind]).then((r) => r.rows);

/** A player with a padel rating (rated sport), or none. */
async function player(name, rating = null) {
  const id = await createUser(pool, name);
  if (rating !== null) {
    await pool.query(`insert into player_ratings (user_id, sport_id, rating, source) values ($1, 'padel', $2, 'questionnaire')`, [id, rating]);
  }
  return id;
}

/** n players with distinct ratings, strongest first. */
async function players(n) {
  const out = [];
  for (let i = 0; i < n; i++) out.push(await player(`P${i + 1}`, (7 - i * 0.5).toFixed(2)));
  return out;
}

/** A singles category of a new tournament with n rated entries, strongest first. */
async function category(n, { tournament } = {}) {
  const t = tournament ?? (await addTournament(pool));
  const cat = await addCategory(pool, t);
  const users = await players(n);
  const regs = await addEntries(pool, cat, users);
  return { t, cat, users, regs };
}

const seedMap = (draw) => Object.fromEntries(draw.entries.map((e) => [e.registration_id, e.seed]));
const knockoutRound = (draw, round) =>
  draw.matches.filter((m) => m.stage === 'knockout' && m.round === round).sort((a, b) => a.position - b.position);

// --- seeding and the bracket ----------------------------------------------------------

test('seed order: 8 entries pair seeds (1,8), (4,5), (2,7), (3,6)', async () => {
  const { cat, regs } = await category(8);
  await makeDraw(admin, cat);
  const draw = await drawJson(cat);
  const seed = seedMap(draw);
  assert.deepEqual(
    regs.map((r) => seed[r]),
    [1, 2, 3, 4, 5, 6, 7, 8],
  );
  const r1 = knockoutRound(draw, 1);
  assert.deepEqual(
    r1.map((m) => [seed[m.side_a], seed[m.side_b]]),
    [
      [1, 8],
      [4, 5],
      [2, 7],
      [3, 6],
    ],
  );
  assert.ok(r1.every((m) => m.status === 'ready'));
  assert.equal(knockoutRound(draw, 2).length, 2);
  assert.equal(knockoutRound(draw, 3).length, 1);
  assert.ok([...knockoutRound(draw, 2), ...knockoutRound(draw, 3)].every((m) => m.status === 'waiting'));
  assert.equal(draw.format, 'knockout');
  assert.equal(draw.status, 'draft');
  assert.equal(draw.outdated, false);
});

test('byes go to top seeds', async () => {
  const { cat } = await category(5);
  await makeDraw(admin, cat);
  const draw = await drawJson(cat);
  const seed = seedMap(draw);
  const r1 = knockoutRound(draw, 1);
  assert.deepEqual(
    r1.map((m) => [seed[m.side_a] ?? null, seed[m.side_b] ?? null, m.status, m.outcome, m.winner, m.a_empty, m.b_empty]),
    [
      [1, null, 'done', 'bye', 'a', false, true],
      [4, 5, 'ready', null, null, false, false],
      [2, null, 'done', 'bye', 'a', false, true],
      [3, null, 'done', 'bye', 'a', false, true],
    ],
  );
  const r2 = knockoutRound(draw, 2);
  assert.deepEqual(
    r2.map((m) => [seed[m.side_a] ?? null, seed[m.side_b] ?? null, m.status]),
    [
      [1, null, 'waiting'],
      [2, 3, 'ready'],
    ],
  );
});

test('two entries make a final; one entry is too few', async () => {
  const { cat } = await category(2);
  await makeDraw(admin, cat);
  const draw = await drawJson(cat);
  assert.equal(draw.matches.length, 1);
  assert.equal(draw.matches[0].status, 'ready');
  assert.equal(draw.matches[0].round, 1);

  const { cat: lone } = await category(1);
  await expectError(makeDraw(admin, lone), 'too_few_entries');
});

test('pairs strength is the average of the two ratings', async () => {
  const t = await addTournament(pool);
  const cat = await addCategory(pool, t, { kind: 'pairs' });
  const y1 = await player('Y1', '3.50');
  const y2 = await player('Y2', '3.50');
  const x1 = await player('X1', '3.00');
  const x2 = await player('X2', '5.00');
  // The weaker pair registers first, so order of entry cannot explain the result.
  const [y, x] = await addEntries(pool, cat, [y1, x1], { partners: [y2, x2] });
  await makeDraw(admin, cat);
  const draw = await drawJson(cat);
  const byReg = Object.fromEntries(draw.entries.map((e) => [e.registration_id, e]));
  assert.equal(byReg[x].seed, 1);
  assert.equal(Number(byReg[x].strength), 4);
  assert.equal(byReg[y].seed, 2);
  assert.equal(Number(byReg[y].strength), 3.5);
  assert.deepEqual(byReg[x].players.map((p) => p.id).sort(), [x1, x2].sort());
});

test('group sizes differ by at most one; groups need three entries', async () => {
  const sizes = async (n, size, advance = 1) => {
    const { cat } = await category(n);
    await makeDraw(admin, cat, 'groups', size, advance);
    const draw = await drawJson(cat);
    const count = {};
    for (const e of draw.entries) count[e.group_id] = (count[e.group_id] ?? 0) + 1;
    assert.equal(draw.groups.length, Object.keys(count).length);
    return Object.values(count).sort((a, b) => b - a);
  };
  assert.deepEqual(await sizes(10, 3), [4, 3, 3]);
  assert.deepEqual(await sizes(10, 4), [4, 3, 3]);
  assert.deepEqual(await sizes(5, 4), [5]);
  assert.deepEqual(await sizes(7, 4), [4, 3]);

  const { cat } = await category(2);
  await expectError(makeDraw(admin, cat, 'groups', 4, 1), 'too_few_entries');
  const { cat: other } = await category(6);
  await expectError(makeDraw(admin, other, 'groups', 5, 1), 'invalid_argument');
  await expectError(makeDraw(admin, other, 'groups', 3, 3), 'invalid_argument');
  await expectError(makeDraw(admin, other, 'league'), 'invalid_argument');
});

test('snake seeding: A gets 1,4,5,8 and B gets 2,3,6,7; the knockout rows wait', async () => {
  const { cat } = await category(8);
  await makeDraw(admin, cat, 'groups', 4, 2);
  const draw = await drawJson(cat);
  assert.deepEqual(
    draw.groups.map((g) => g.label),
    ['A', 'B'],
  );
  const label = Object.fromEntries(draw.groups.map((g) => [g.id, g.label]));
  const seedsOf = (l) =>
    draw.entries
      .filter((e) => label[e.group_id] === l)
      .map((e) => e.seed)
      .sort((a, b) => a - b);
  assert.deepEqual(seedsOf('A'), [1, 4, 5, 8]);
  assert.deepEqual(seedsOf('B'), [2, 3, 6, 7]);
  // 2 groups x 2 advancing = 4 qualifiers: two semi-finals and a final, all waiting.
  const ko = draw.matches.filter((m) => m.stage === 'knockout');
  assert.equal(ko.length, 3);
  assert.ok(ko.every((m) => m.status === 'waiting' && m.side_a === null && m.side_b === null && !m.a_empty && !m.b_empty));
  assert.equal(draw.group_size, 4);
  assert.equal(draw.advance, 2);
});

test('knockout after groups marks the empty qualifier slots', async () => {
  // 3 groups x 2 = 6 qualifiers in a bracket of 8: qualifier seeds 7 and 8 are empty.
  const { cat } = await category(9);
  await makeDraw(admin, cat, 'groups', 3, 2);
  const draw = await drawJson(cat);
  const r1 = knockoutRound(draw, 1);
  assert.deepEqual(
    r1.map((m) => [m.a_empty, m.b_empty, m.status]),
    [
      [false, true, 'waiting'],
      [false, false, 'waiting'],
      [false, true, 'waiting'],
      [false, false, 'waiting'],
    ],
  );
  // One group, one advancing: no knockout at all.
  const { cat: single } = await category(4);
  await makeDraw(admin, single, 'groups', 4, 1);
  assert.equal((await drawJson(single)).matches.filter((m) => m.stage === 'knockout').length, 0);
});

test('round robin: a group of 4 plays 6 matches in 3 rounds, a group of 3 plays 3', async () => {
  const { cat } = await category(7);
  await makeDraw(admin, cat, 'groups', 4, 1);
  const draw = await drawJson(cat);
  const members = {};
  for (const e of draw.entries) (members[e.group_id] ??= []).push(e.registration_id);
  for (const [groupId, regs] of Object.entries(members)) {
    const ms = draw.matches.filter((m) => m.stage === 'group' && m.group_id === groupId);
    if (regs.length === 4) {
      assert.equal(ms.length, 6);
      assert.deepEqual([...new Set(ms.map((m) => m.round))].sort(), [1, 2, 3]);
    } else {
      assert.equal(regs.length, 3);
      assert.equal(ms.length, 3);
    }
    for (const round of new Set(ms.map((m) => m.round))) {
      const sides = ms.filter((m) => m.round === round).flatMap((m) => [m.side_a, m.side_b]);
      assert.equal(new Set(sides).size, sides.length, 'nobody plays twice in one round');
    }
    const pairs = new Set(ms.map((m) => [m.side_a, m.side_b].sort().join()));
    assert.equal(pairs.size, (regs.length * (regs.length - 1)) / 2, 'every pair meets once');
    assert.ok(ms.every((m) => m.status === 'ready' && regs.includes(m.side_a) && regs.includes(m.side_b)));
  }
});

// --- who may draw, who may see ------------------------------------------------------

test('organiser scope: only admins and the tournament organisers make draws', async () => {
  const { t, cat } = await category(4);
  const otherT = await addTournament(pool);
  const organizer = await player('Org');
  const otherOrganizer = await player('Other org');
  const stranger = await player('Stranger');
  await setOrganizer(admin, t, organizer, true);
  await setOrganizer(admin, otherT, otherOrganizer, true);

  await makeDraw(organizer, cat);
  await expectError(makeDraw(otherOrganizer, cat), 'not_allowed');
  await expectError(makeDraw(stranger, cat), 'not_allowed');
  await makeDraw(admin, cat);

  const audit = (await pool.query(`select actor_id, action from audit_log where action = 'make_draw' order by id`)).rows;
  assert.deepEqual(
    audit.map((a) => a.actor_id),
    [organizer, admin],
  );
});

test('draft is hidden from players until published', async () => {
  const { cat, users } = await category(4);
  await makeDraw(admin, cat);
  assert.equal(await drawJson(cat, users[0]), null);
  assert.ok(await drawJson(cat, admin));
  await publish(admin, cat);
  const seen = await drawJson(cat, users[0]);
  assert.equal(seen.status, 'published');
  assert.equal(seen.entries.length, 4);
});

// --- draft changes ------------------------------------------------------------------

test('swap in draft changes round 1; after publish it is refused', async () => {
  const { cat, regs } = await category(8);
  await makeDraw(admin, cat);
  await swap(admin, cat, regs[0], regs[7]);
  const draw = await drawJson(cat);
  const seed = seedMap(draw);
  assert.equal(seed[regs[7]], 1);
  assert.equal(seed[regs[0]], 8);
  const first = knockoutRound(draw, 1)[0];
  assert.equal(first.side_a, regs[7]);
  assert.equal(first.side_b, regs[0]);
  assert.equal(draw.matches.length, 7);

  await publish(admin, cat);
  await expectError(swap(admin, cat, regs[0], regs[7]), 'draw_published');
  await expectError(makeDraw(admin, cat), 'draw_published');
});

test('swap between groups moves the two entries', async () => {
  const { cat, regs } = await category(8);
  await makeDraw(admin, cat, 'groups', 4, 1);
  const before = await drawJson(cat);
  const groupOf = (d, r) => d.entries.find((e) => e.registration_id === r).group_id;
  // Seeds 1 and 2 are in different groups.
  assert.notEqual(groupOf(before, regs[0]), groupOf(before, regs[1]));
  await swap(admin, cat, regs[0], regs[1]);
  const afterSwap = await drawJson(cat);
  assert.equal(groupOf(afterSwap, regs[0]), groupOf(before, regs[1]));
  assert.equal(groupOf(afterSwap, regs[1]), groupOf(before, regs[0]));
  const inGroup = (d, g) => d.matches.filter((m) => m.group_id === g).flatMap((m) => [m.side_a, m.side_b]);
  assert.ok(inGroup(afterSwap, groupOf(before, regs[1])).includes(regs[0]));
  assert.ok(!inGroup(afterSwap, groupOf(before, regs[0])).includes(regs[0]));
});

test('outdated draft cannot be published until it is made again', async () => {
  const { cat } = await category(4);
  await makeDraw(admin, cat);
  const late = await player('Late', '2.00');
  await pool.query(`select app.register($1, $2, null, $3)`, [late, cat, now]);
  assert.equal((await drawJson(cat)).outdated, true);
  await expectError(publish(admin, cat), 'draw_outdated');
  await makeDraw(admin, cat);
  const draw = await drawJson(cat);
  assert.equal(draw.outdated, false);
  assert.equal(draw.entries.length, 5);
  await publish(admin, cat);
});

// --- publishing locks the entries ----------------------------------------------------

test('publish locks entries, closes the waitlist and tells every player', async () => {
  const t = await addTournament(pool);
  const cat = await addCategory(pool, t, { kind: 'pairs', cap: 3 });
  const ps = await players(6);
  const regs = await addEntries(pool, cat, [ps[0], ps[2], ps[4]], { partners: [ps[1], ps[3], ps[5]] });
  const offeredUser = await player('Offered');
  const offeredPartner = await player('Offered partner');
  const { id: offered } = await one(
    `insert into tournament_registrations (category_id, user_id, partner_id, partner_confirmed, status, fee, currency, offer_expires_at, waitlist_position)
     values ($1, $2, $3, true, 'offered', 0, 'UZS', $4, 1) returning id`,
    [cat, offeredUser, offeredPartner, later(24)],
  );
  const waitingUser = await player('Waiting');
  const { id: waiting } = await one(
    `insert into tournament_registrations (category_id, user_id, partner_id, partner_confirmed, status, fee, currency, waitlist_position)
     values ($1, $2, null, false, 'waitlisted', 0, 'UZS', 2) returning id`,
    [cat, waitingUser],
  );
  await makeDraw(admin, cat);
  await publish(admin, cat);

  assert.equal(await statusOf(offered), 'lapsed');
  assert.equal(await statusOf(waiting), 'lapsed');
  assert.equal((await notesOf(offeredUser, 'waitlist_closed')).length, 1);
  assert.equal((await notesOf(offeredPartner, 'waitlist_closed')).length, 1);
  assert.equal((await notesOf(waitingUser, 'waitlist_closed')).length, 1);
  const note = (await notesOf(offeredUser, 'waitlist_closed'))[0];
  assert.equal(note.category, 'tournaments');
  assert.equal(note.payload.tournament_id, t);
  assert.equal(note.payload.category_id, cat);
  assert.deepEqual(Object.keys(note.payload.title).sort(), ['en', 'kk', 'ru', 'uz']);
  assert.deepEqual(Object.keys(note.payload.category_name).sort(), ['en', 'kk', 'ru', 'uz']);
  for (const p of ps) {
    const n = await notesOf(p, 'draw_published');
    assert.equal(n.length, 1, 'each player of each entry is told once');
    assert.equal(n[0].payload.category_id, cat);
  }
  // The offered pair no longer counts toward the summary.
  assert.equal((await one(`select slots_filled from tournaments where id = $1`, [t])).slots_filled, 3);

  const newcomer = await player('New');
  const newPartner = await player('New partner');
  await expectError(pool.query(`select app.register($1, $2, $3, $4)`, [newcomer, cat, newPartner, now]), 'draw_published');
  await expectError(pool.query(`select app.cancel_registration($1, $2, $3)`, [ps[0], regs[0], now]), 'draw_published');
  await pool.query(`select app.admin_set_paid($1, $2, true, $3)`, [admin, regs[0], now]);
  assert.ok((await one(`select paid_at from tournament_registrations where id = $1`, [regs[0]])).paid_at);
  await expectError(pool.query(`select app.admin_remove_registration($1, $2, $3)`, [admin, regs[1], now]), 'draw_published');
});

test('job can still expire invites in a locked category', async () => {
  const { cat } = await category(4);
  const inviter = await player('Inviter');
  const invitee = await player('Invitee');
  const { id: pending } = await one(
    `insert into tournament_registrations (category_id, user_id, partner_id, partner_confirmed, status, fee, currency, partner_expires_at)
     values ($1, $2, $3, false, 'pending_partner', 0, 'UZS', $4) returning id`,
    [cat, inviter, invitee, later(1)],
  );
  await makeDraw(admin, cat);
  await publish(admin, cat);
  await pool.query(`select app.expire_tournament_entries($1)`, [later(2)]);
  assert.equal(await statusOf(pending), 'expired');
});

test('the override lets a withdrawal through a locked category', async () => {
  const { cat, regs } = await category(4);
  await makeDraw(admin, cat);
  await publish(admin, cat);
  const client = await pool.connect();
  try {
    await client.query('begin');
    await client.query(`select set_config('actra.draw_override', 'on', true)`);
    await client.query(`update tournament_registrations set status = 'removed' where id = $1`, [regs[3]]);
    await client.query('commit');
  } finally {
    client.release();
  }
  assert.equal(await statusOf(regs[3]), 'removed');
});

// --- redo ---------------------------------------------------------------------------

test('redo before any score makes a new draft; after a score it is final', async () => {
  const { cat, users } = await category(4);
  await expectError(redo(admin, cat), 'not_found');
  await makeDraw(admin, cat, 'groups', 4, 1);
  await expectError(redo(admin, cat), 'invalid_argument');
  await publish(admin, cat);
  await redo(admin, cat);
  const draw = await drawJson(cat);
  assert.equal(draw.status, 'draft');
  assert.equal(draw.format, 'groups');
  assert.equal(draw.group_size, 4);
  assert.equal(draw.entries.length, 4);
  assert.equal(await drawJson(cat, users[0]), null, 'a redone draw is a draft again');
  for (const u of users) assert.equal((await notesOf(u, 'draw_redone')).length, 1);

  // Still locked after a redo, and after making the draft again.
  await makeDraw(admin, cat, 'knockout');
  const late = await player('Late');
  await expectError(pool.query(`select app.register($1, $2, null, $3)`, [late, cat, now]), 'draw_published');

  await publish(admin, cat);
  await pool.query(`update tournament_draws set first_score_at = $2 where category_id = $1`, [cat, now]);
  await expectError(redo(admin, cat), 'draw_final');
});

// --- organisers ---------------------------------------------------------------------

test('organizers: admins add and remove them; organisers see their own tournaments and entries', async () => {
  const { t, cat, users } = await category(2);
  const otherT = await addTournament(pool);
  const organizer = await player('Org');
  await addPhone(pool, users[0], '+998901111111');
  await pool.query(`update tournaments set title_kk = 'Kubok KK' where id = $1`, [t]);

  await expectError(setOrganizer(organizer, t, organizer, true), 'not_allowed');
  await setOrganizer(admin, t, organizer, true);
  const added = await notesOf(organizer, 'organizer_added');
  assert.equal(added.length, 1);
  assert.equal(added[0].payload.tournament_id, t);
  assert.equal(added[0].category, 'tournaments');
  assert.equal(added[0].payload.title.kk, 'Kubok KK');

  const mine = await scalar(`select app.my_organized_tournaments($1) as r`, [organizer]);
  assert.deepEqual(
    mine.map((x) => x.id),
    [t],
  );
  assert.equal(mine[0].title_en, 'Cup');
  assert.equal(mine[0].title_kk, 'Kubok KK');
  assert.ok(otherT);

  const entries = await scalar(`select app.organizer_entries($1, $2) as r`, [organizer, t]);
  assert.equal(entries.length, 2);
  assert.equal(entries.find((e) => e.registrant.id === users[0]).registrant.phone, '+998901111111');
  await expectError(pool.query(`select app.organizer_entries($1, $2)`, [users[0], t]), 'not_allowed');
  assert.ok(cat);

  await setOrganizer(admin, t, organizer, false);
  assert.equal((await notesOf(organizer, 'organizer_removed')).length, 1);
  assert.deepEqual(await scalar(`select app.my_organized_tournaments($1) as r`, [organizer]), []);
  await expectError(pool.query(`select app.organizer_entries($1, $2)`, [organizer, t]), 'not_allowed');
  const actions = (await pool.query(`select action from audit_log order by id`)).rows.map((r) => r.action);
  assert.deepEqual(actions, ['add_organizer', 'remove_organizer']);
});

test('the public calls: organiser list, draws and the bracket', async () => {
  const { t, cat, users } = await category(4);
  const organizer = await player('Org');

  const list = await asUser(pool, admin, async (c) =>
    (await c.query(`select public.admin_set_organizer($1, $2, true) as r`, [t, organizer])).rows[0].r,
  );
  assert.deepEqual(list, [{ id: organizer, name: 'Org' }]);
  assert.deepEqual(
    await asUser(pool, admin, async (c) => (await c.query(`select public.tournament_organizers($1) as r`, [t])).rows[0].r),
    [{ id: organizer, name: 'Org' }],
  );
  assert.equal(
    await errorOf(asUser(pool, organizer, (c) => c.query(`select public.tournament_organizers($1)`, [t]))),
    'not_allowed',
  );

  const made = await asUser(pool, organizer, async (c) =>
    (await c.query(`select public.make_draw($1, 'knockout') as r`, [cat])).rows[0].r,
  );
  assert.equal(made.status, 'draft');
  assert.equal(made.matches.length, 3);
  assert.deepEqual(Object.keys(made.matches[0]).sort(), [
    'a_empty', 'b_empty', 'court_id', 'group_id', 'id', 'outcome', 'place_note', 'position', 'round', 'sets', 'side_a', 'side_b',
    'stage', 'starts_at', 'status', 'winner',
  ]);

  const playerView = await asUser(pool, users[0], async (c) => (await c.query(`select public.tournament_bracket($1) as r`, [t])).rows[0].r);
  assert.deepEqual(playerView, { organizer: false, draws: [] });
  const orgView = await asUser(pool, organizer, async (c) => (await c.query(`select public.tournament_bracket($1) as r`, [t])).rows[0].r);
  assert.equal(orgView.organizer, true);
  assert.equal(orgView.draws.length, 1);

  const published = await asUser(pool, organizer, async (c) => (await c.query(`select public.publish_draw($1) as r`, [cat])).rows[0].r);
  assert.equal(published.status, 'published');
  const seen = await asUser(pool, users[0], async (c) => (await c.query(`select public.tournament_bracket($1) as r`, [t])).rows[0].r);
  assert.equal(seen.draws.length, 1);
  assert.equal(seen.draws[0].category_id, cat);

  const mine = await asUser(pool, organizer, async (c) => (await c.query(`select public.my_organized_tournaments() as r`)).rows[0].r);
  assert.deepEqual(
    mine.map((x) => x.id),
    [t],
  );
  const entries = await asUser(pool, organizer, async (c) => (await c.query(`select public.organizer_entries($1) as r`, [t])).rows[0].r);
  assert.equal(entries.length, 4);
  const redone = await asUser(pool, organizer, async (c) => (await c.query(`select public.redo_draw($1) as r`, [cat])).rows[0].r);
  assert.equal(redone.status, 'draft');
  const swapped = await asUser(pool, organizer, async (c) =>
    (await c.query(`select public.swap_draw_entries($1, $2, $3) as r`, [cat, redone.entries[0].registration_id, redone.entries[1].registration_id])).rows[0].r,
  );
  assert.equal(swapped.entries.length, 4);
});
