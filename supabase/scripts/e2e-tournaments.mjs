// End-to-end check of tournament registration (Milestone 5) against the
// hosted project, with real sessions:
//
//   0. Read-only first: the tournament tables exist. Otherwise it stops
//      before creating anything.
//   1. Five throw-away accounts sign in: an admin (a row in app_admins) and
//      four players (pair A: p1 and p2; pair B: p3 and p4).
//   2. The admin creates a throw-away tournament "E2E M8 tournaments
//      <timestamp>" in Tashkent, a week out, with no venue (so no venue
//      owner exists to be told) and one pairs category with a cap of one
//      pair and the waitlist on.
//   3. p3 cannot join the waitlist while there is room (not_full). p1
//      registers with p2 as partner: pending until p2 accepts; p2 is invited,
//      accepts, both are registered and told, and the category is full.
//   4. p3 joins the waitlist with p4; p4 accepts the invite. The pair waits
//      first in line and is offered nothing while the category is full.
//   5. p1 cancels: p2 is told, the spot is offered to pair B (both told), and
//      p3 claims it; pair B is registered.
//   6. A plain player cannot mark an entry paid; the admin cannot mark the
//      cancelled entry paid (not_markable); the admin marks pair B paid and
//      the participants list shows it.
//   7. Everything made here (registrations, the category, the tournament,
//      the admin's audit rows, the app_admins row, the accounts) is deleted,
//      whatever happened; what is left is printed, and anything left fails
//      the run.
//
// The tournament is listed in Tashkent's tournament list for the minute the
// script runs; its only category is full from step 3 on.
//
//   node scripts/e2e-tournaments.mjs
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

const notifications = async (session) => ok(session, 'my_notifications', { p_limit: 50 });

/** The player has a notification of this kind about this registration. */
async function told(session, kind, registrationId, who) {
  const note = (await notifications(session)).find((n) => n.kind === kind && n.payload.registration_id === registrationId);
  assert.ok(note, `${who} has no ${kind} about ${registrationId}`);
  return note;
}

// -- 0. Preconditions (read-only, before anything is created) ---------------
step('Checking the live database has the tournament tables');
const ready = (await sql(env, `select to_regclass('public.tournament_categories')::text as categories,
                                      to_regclass('public.tournament_registrations')::text as registrations`))[0];
if (!ready.categories || !ready.registrations) {
  console.error('  The tournament tables are missing: run `node scripts/deploy.mjs migrations` first. Nothing was created.');
  process.exit(1);
}
console.log('  tournament_categories and tournament_registrations present');

let tournamentId = null;
let failed = false;
try {
  step('Signing in an admin and four players');
  const suffix = String(randomInt(10_000_000)).padStart(7, '0');
  const stamp = new Date().toISOString().replace(/\D/g, '').slice(0, 14);
  const admin = await signIn('admin', `+99809${suffix}`);
  const p1 = await signIn('player 1', `+99805${suffix}`);
  const p2 = await signIn('player 2', `+99806${suffix}`);
  const p3 = await signIn('player 3', `+99807${suffix}`);
  const p4 = await signIn('player 4', `+99808${suffix}`);
  const tag = [...suffix].map((d) => 'abcdefghij'[d]).join('');
  await saveProfile(admin, `E2E M8 Admin ${tag}`);
  await saveProfile(p1, `E2E M8 Anna ${tag}`);
  await saveProfile(p2, `E2E M8 Bobur ${tag}`);
  await saveProfile(p3, `E2E M8 Dilya ${tag}`);
  await saveProfile(p4, `E2E M8 Erkin ${tag}`);
  const today = (await sql(env, `select (app.to_local(now(), 300))::date::text as d`))[0].d;

  step('The admin creates a throw-away tournament with one pairs category (cap 1)');
  await sql(env, `insert into public.app_admins (user_id) values ('${admin.userId}')`, { write: true });
  // Registration closes at 00:00 on the first day: a week out leaves room.
  tournamentId = await ok(admin, 'admin_save_tournament', {
    p_tournament: {
      city_id: 'tashkent', sport_id: 'padel', title_en: `E2E M8 tournaments ${stamp}`,
      starts_on: addDays(today, 7), ends_on: addDays(today, 7),
      categories: [{ name_en: 'Pairs', kind: 'pairs', cap: 1, fee: 50000, waitlist_enabled: true }],
    },
  });
  const created = await ok(p1, 'get_tournament', { p_tournament_id: tournamentId });
  assert.equal(created.categories.length, 1, JSON.stringify(created.categories));
  const category = created.categories[0];
  assert.equal(category.kind, 'pairs');
  assert.equal(category.cap, 1);
  assert.equal(category.filled, 0);
  assert.equal(created.registration_open, true);
  console.log(`  tournament ${tournamentId}, category ${category.id}`);

  step('No waitlist while there is room; p1 registers with p2, who accepts');
  await refused(p3, 'join_waitlist', { p_category_id: category.id, p_partner_id: p4.userId }, 'not_full');
  const pairA = await ok(p1, 'register_tournament', { p_category_id: category.id, p_partner_id: p2.userId });
  assert.equal(pairA.status, 'pending_partner', JSON.stringify(pairA));
  assert.equal(pairA.partner_confirmed, false);
  assert.equal(pairA.fee, 50000);
  // Pending pairs hold no spot.
  assert.equal((await ok(p1, 'get_tournament', { p_tournament_id: tournamentId })).categories[0].filled, 0);
  await told(p2, 'tournament_partner_invite', pairA.id, 'p2');
  await refused(p3, 'respond_partner', { p_registration_id: pairA.id, p_accept: true }, 'not_found');
  const acceptedA = await ok(p2, 'respond_partner', { p_registration_id: pairA.id, p_accept: true });
  assert.equal(acceptedA.status, 'registered', JSON.stringify(acceptedA));
  assert.equal(acceptedA.partner_confirmed, true);
  await told(p1, 'tournament_partner_accepted', pairA.id, 'p1');
  await told(p1, 'tournament_registered', pairA.id, 'p1');
  await told(p2, 'tournament_registered', pairA.id, 'p2');
  const full = (await ok(p3, 'get_tournament', { p_tournament_id: tournamentId })).categories[0];
  assert.equal(full.filled, 1);
  assert.equal(full.full, true);
  console.log(`  pair A ${pairA.id}: invited, accepted, registered; the category is full`);

  step('p3 joins the waitlist with p4, who accepts');
  const pairB = await ok(p3, 'join_waitlist', { p_category_id: category.id, p_partner_id: p4.userId });
  assert.equal(pairB.status, 'waitlisted', JSON.stringify(pairB));
  assert.equal(pairB.partner_confirmed, false);
  assert.equal(pairB.waitlist_place, null, 'an unconfirmed pair has no place yet');
  await told(p4, 'tournament_partner_invite', pairB.id, 'p4');
  const confirmedB = await ok(p4, 'respond_partner', { p_registration_id: pairB.id, p_accept: true });
  assert.equal(confirmedB.status, 'waitlisted', 'still full: confirmed but not offered');
  assert.equal(confirmedB.partner_confirmed, true);
  assert.equal(Number(confirmedB.waitlist_place), 1);
  const waiting = (await ok(p3, 'get_tournament', { p_tournament_id: tournamentId })).categories[0];
  assert.equal(waiting.waitlist_count, 1);
  assert.equal(waiting.my_status, 'waitlisted');
  console.log(`  pair B ${pairB.id}: waitlisted, first in line`);

  step('p1 cancels; the spot is offered to pair B and p3 claims it');
  const cancelled = await ok(p1, 'cancel_registration', { p_registration_id: pairA.id });
  assert.equal(cancelled.status, 'cancelled', JSON.stringify(cancelled));
  await told(p2, 'tournament_partner_cancelled', pairA.id, 'p2');
  const offered = (await ok(p3, 'my_registrations')).find((r) => r.id === pairB.id);
  assert.equal(offered?.status, 'offered', JSON.stringify(offered));
  assert.ok(offered.offer_expires_local, 'the offer has an expiry');
  await told(p3, 'tournament_spot_offered', pairB.id, 'p3');
  await told(p4, 'tournament_spot_offered', pairB.id, 'p4');
  await refused(p1, 'claim_offer', { p_registration_id: pairB.id }, 'not_found');
  const claimed = await ok(p3, 'claim_offer', { p_registration_id: pairB.id });
  assert.equal(claimed.status, 'registered', JSON.stringify(claimed));
  await told(p4, 'tournament_registered', pairB.id, 'p4');
  const after = (await ok(p4, 'get_tournament', { p_tournament_id: tournamentId })).categories[0];
  assert.equal(after.filled, 1);
  assert.equal(after.waitlist_count, 0);
  assert.equal(after.my_status, 'registered');
  console.log('  cancelled, offered, claimed');

  step('The admin marks pair B paid');
  await refused(p3, 'admin_set_paid', { p_registration_id: pairB.id, p_paid: true }, 'not_allowed');
  await refused(admin, 'admin_set_paid', { p_registration_id: pairA.id, p_paid: true }, 'not_markable');
  const paid = await ok(admin, 'admin_set_paid', { p_registration_id: pairB.id, p_paid: true });
  assert.equal(paid.paid, true, JSON.stringify(paid));
  assert.ok(paid.paid_at);
  const list = await ok(admin, 'admin_list_registrations', { p_tournament_id: tournamentId });
  assert.deepEqual(
    list.map((r) => [r.id, r.status, r.paid]),
    [[pairB.id, 'registered', true], [pairA.id, 'cancelled', false]],
    JSON.stringify(list.map((r) => [r.id, r.status, r.paid])),
  );
  assert.equal((await ok(p3, 'my_registrations')).find((r) => r.id === pairB.id)?.paid, true);
  console.log('  refused to a player and for the cancelled entry; pair B paid');

  console.log('\nTOURNAMENTS END TO END: PASSED');
} catch (e) {
  failed = true;
  console.error(`\nTOURNAMENTS END TO END: FAILED\n${e.stack ?? e}`);
} finally {
  step('Cleaning up the throw-away tournament and accounts');
  const users = createdUsersSql();
  const categories = tournamentId ? `select c.id from public.tournament_categories c where c.tournament_id = '${tournamentId}'` : null;
  await removeAccounts({
    before: [
      ...(tournamentId
        ? [
            // Registrations block their category (on delete restrict); the
            // categories go with the tournament.
            `delete from public.tournament_registrations where category_id in (${categories})`,
            `delete from public.tournaments where id = '${tournamentId}'`,
          ]
        : []),
      ...(users
        ? [`delete from public.audit_log where actor_id in (${users})`, `delete from public.app_admins where user_id in (${users})`]
        : []),
    ],
  });

  const counts = {
    'test tournaments': `select count(*) from public.tournaments where title_en like 'E2E M8 tournaments%'`,
    ...(tournamentId
      ? { categories: `select count(*) from public.tournament_categories where tournament_id = '${tournamentId}'` }
      : {}),
    ...(users
      ? {
          registrations: `select count(*) from public.tournament_registrations where user_id in (${users}) or partner_id in (${users})`,
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
