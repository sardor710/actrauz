// End-to-end check of tournament brackets (Milestone 8a) against the hosted
// project, with real sessions:
//
//   0. Read-only first: the M8 tables and columns exist and padel is rated.
//      Otherwise it stops before creating anything.
//   1. Six throw-away accounts sign in: an admin (a row in app_admins), an
//      organiser (a plain player, never an admin: admins pass every
//      organiser check) and four players. The admin creates a throw-away
//      venue "E2E M8 brackets <timestamp>" with two padel courts, so no real
//      venue owner is ever notified, and a throw-away tournament on it, two
//      and three days out, with two singles categories (cap 4 and cap 2, no
//      waitlist).
//   2. The four players answer the padel questionnaire (set_my_sport) with
//      the same answers: everyone starts at the same rating.
//   3. Nobody but an admin or a named organiser may make a draw; the admin
//      names the organiser, who is told and sees the tournament as theirs.
//   4. The four register in the main category (it fills); players 1 and 2
//      also enter the second one.
//   5. The organiser makes a knockout draw: a draft nobody else sees; then
//      publishes it, and every player is told.
//   6. "Fill the day" on the first day from 09:00 on both courts lays all
//      three matches (the semi-finals side by side, the final after them);
//      each match holds a calendar block on the throw-away venue, and the
//      semi-finalists are told when they play.
//   7. A player cannot enter a score. The organiser enters both semi-finals
//      and the final; the winners move on, a semi-final can no longer be
//      corrected once the final has a score, the category has its winner
//      and runner-up, and the winner is told. Every player is told each
//      result; three confirmed results moved the ratings (six rating
//      events): both semi-final losers fell, the champion rose, both
//      finalists have two rated games. The three blocks stay.
//   8. In the second category the organiser publishes a two-entry knockout
//      and withdraws player 2: a walkover for player 1, who wins the
//      category (told) while player 2 is told of the withdrawal; no rating
//      moves and no result is written for it. The tournament is finished.
//   9. Everything made here (results, rating events, ratings, matches,
//      blocks, draws, groups, entries, organisers, registrations, the
//      categories, the tournament, the courts, the venue, the audit rows,
//      the app_admins row, the accounts) is deleted, whatever happened; what
//      is left is printed, and anything left fails the run.
//
// The tournament is listed in Tashkent's tournament list for the minute the
// script runs; its main category is full from step 4 on and neither has a
// waitlist.
//
//   node scripts/e2e-brackets.mjs
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

const notifications = async (session) => ok(session, 'my_notifications', { p_limit: 100 });

/** The player's notifications of this kind whose payload has every given value. */
async function noticesOf(session, kind, payload = {}) {
  return (await notifications(session)).filter(
    (n) => n.kind === kind && Object.entries(payload).every(([k, v]) => n.payload[k] === v),
  );
}

/** The player's padel entry in my_sports (the list set_my_sport also returns). */
function padel(sports, who) {
  const entry = sports.find((s) => s.sport_id === 'padel');
  assert.ok(entry, `${who} has no padel entry: ${JSON.stringify(sports)}`);
  return { ...entry, rating: Number(entry.rating) };
}

/** The knockout match of a draw at (round, position). */
function knockout(draw, round, position) {
  const match = draw.matches.find((m) => m.stage === 'knockout' && m.round === round && m.position === position);
  assert.ok(match, `no knockout match ${round}/${position}: ${JSON.stringify(draw.matches)}`);
  return match;
}

// -- 0. Preconditions (read-only, before anything is created) ---------------
step('Checking the live database is ready for M8 brackets');
const ready = (await sql(env, `select to_regclass('public.tournament_matches')::text as matches,
                                      to_regclass('public.tournament_organizers')::text as organizers,
                                      exists (select 1 from information_schema.columns
                                              where table_schema = 'public' and table_name = 'bookings'
                                                and column_name = 'tournament_match_id') as blocks,
                                      exists (select 1 from information_schema.columns
                                              where table_schema = 'public' and table_name = 'match_results'
                                                and column_name = 'tournament_match_id') as results,
                                      (select competitive_rating from public.sports where id = 'padel') as rated`))[0];
if (!ready.matches || !ready.organizers || ready.blocks !== true || ready.results !== true) {
  console.error('  The M8 tables are missing: run `node scripts/deploy.mjs migrations` first (the four 20261128* files). Nothing was created.');
  process.exit(1);
}
if (ready.rated !== true) {
  console.error('  padel is not rated on this database: the M7 migrations have not been applied. Nothing was created.');
  process.exit(1);
}
console.log('  tournament_matches, organisers, calendar blocks and tournament results present; padel is rated');

let venueId = null;
let tournamentId = null;
let failed = false;
try {
  step('Signing in an admin, an organiser and four players');
  const suffix = String(randomInt(10_000_000)).padStart(7, '0');
  const stamp = new Date().toISOString().replace(/\D/g, '').slice(0, 14);
  const admin = await signIn('admin', `+99809${suffix}`);
  const organiser = await signIn('organiser', `+99804${suffix}`);
  const p1 = await signIn('player 1', `+99805${suffix}`);
  const p2 = await signIn('player 2', `+99806${suffix}`);
  const p3 = await signIn('player 3', `+99807${suffix}`);
  const p4 = await signIn('player 4', `+99808${suffix}`);
  const players = [p1, p2, p3, p4];
  const tag = [...suffix].map((d) => 'abcdefghij'[d]).join('');
  await saveProfile(admin, `E2E M8 Admin ${tag}`);
  await saveProfile(organiser, `E2E M8 Organiser ${tag}`);
  await saveProfile(p1, `E2E M8 Anna ${tag}`);
  await saveProfile(p2, `E2E M8 Bobur ${tag}`);
  await saveProfile(p3, `E2E M8 Dilya ${tag}`);
  await saveProfile(p4, `E2E M8 Erkin ${tag}`);
  const today = (await sql(env, `select (app.to_local(now(), 300))::date::text as d`))[0].d;
  // Registration closes at 00:00 on the first day: two days out leaves a
  // whole day, and every slot of the first day is in the future.
  const day = addDays(today, 2);

  step('The admin creates a throw-away venue with two padel courts and a tournament on it');
  await sql(env, `insert into public.app_admins (user_id) values ('${admin.userId}')`, { write: true });
  venueId = await ok(admin, 'admin_save_venue', {
    p_venue: { city_id: 'tashkent', name_en: `E2E M8 brackets ${stamp}`, address_en: 'Nowhere 1', district_en: 'Test', phone: '+998710000000' },
  });
  const courts = [];
  for (const name of ['Court 1', 'Court 2']) {
    courts.push(await ok(admin, 'admin_save_court', {
      p_court: { venue_id: venueId, sport_id: 'padel', name_en: name, slot_minutes: 60, base_price: 100000, indoor: true },
    }));
  }
  tournamentId = await ok(admin, 'admin_save_tournament', {
    p_tournament: {
      city_id: 'tashkent', sport_id: 'padel', venue_id: venueId, title_en: `E2E M8 brackets ${stamp}`,
      starts_on: day, ends_on: addDays(day, 1),
      categories: [
        { name_en: 'Singles', kind: 'singles', cap: 4, waitlist_enabled: false },
        { name_en: 'Singles B', kind: 'singles', cap: 2, waitlist_enabled: false },
      ],
    },
  });
  const created = await ok(p1, 'get_tournament', { p_tournament_id: tournamentId });
  assert.deepEqual(created.categories.map((c) => [c.name_en, c.cap]), [['Singles', 4], ['Singles B', 2]]);
  const [main, second] = created.categories.map((c) => c.id);
  console.log(`  venue ${venueId}, courts ${courts.join(', ')}, tournament ${tournamentId}`);

  step('The four players answer the padel questionnaire');
  const before = {};
  for (const p of players) {
    const entry = padel(await ok(p, 'set_my_sport', { p_sport_id: 'padel', p_answers: [1, 1, 1, 1, 1] }), p.userId);
    assert.equal(entry.rated_games, 0);
    before[p.userId] = entry.rating;
  }
  assert.equal(new Set(Object.values(before)).size, 1, `everyone starts level: ${JSON.stringify(before)}`);
  console.log(`  all four start at ${before[p1.userId].toFixed(2)}`);

  step('Only an admin or a named organiser may draw; the admin names the organiser');
  await refused(organiser, 'make_draw', { p_category_id: main, p_format: 'knockout' }, 'not_allowed');
  await refused(organiser, 'admin_set_organizer', { p_tournament_id: tournamentId, p_user_id: organiser.userId, p_add: true }, 'not_allowed');
  const organisers = await ok(admin, 'admin_set_organizer', { p_tournament_id: tournamentId, p_user_id: organiser.userId, p_add: true });
  assert.deepEqual(organisers.map((o) => o.id), [organiser.userId]);
  assert.equal((await noticesOf(organiser, 'organizer_added', { tournament_id: tournamentId })).length, 1);
  assert.ok((await ok(organiser, 'my_organized_tournaments')).some((t) => t.id === tournamentId));
  await refused(p1, 'make_draw', { p_category_id: main, p_format: 'knockout' }, 'not_allowed');
  console.log('  refused before; named, told, listed as theirs; a player is still refused');

  step('The four register in the main category; players 1 and 2 also in the second');
  const entry = {}; // user id -> registration id in the main category
  for (const p of players) {
    const reg = await ok(p, 'register_tournament', { p_category_id: main });
    assert.equal(reg.status, 'registered', JSON.stringify(reg));
    entry[p.userId] = reg.id;
  }
  const entry2 = {}; // user id -> registration id in the second category
  for (const p of [p1, p2]) {
    const reg = await ok(p, 'register_tournament', { p_category_id: second });
    assert.equal(reg.status, 'registered', JSON.stringify(reg));
    entry2[p.userId] = reg.id;
  }
  const filled = (await ok(p1, 'get_tournament', { p_tournament_id: tournamentId })).categories;
  assert.equal(filled[0].full, true);
  assert.equal(filled[1].full, true);
  const playerOf = (registrationId) =>
    players.find((p) => entry[p.userId] === registrationId || entry2[p.userId] === registrationId);
  console.log('  main category full (4), second category full (2)');

  step('The organiser makes a knockout draw, then publishes it');
  const draft = await ok(organiser, 'make_draw', { p_category_id: main, p_format: 'knockout' });
  assert.equal(draft.status, 'draft');
  assert.equal(draft.entries.length, 4);
  assert.deepEqual(draft.entries.map((e) => e.seed), [1, 2, 3, 4]);
  assert.equal((await ok(p1, 'tournament_bracket', { p_tournament_id: tournamentId })).draws.length, 0, 'a draft is hidden from players');
  const published = await ok(organiser, 'publish_draw', { p_category_id: main });
  assert.equal(published.status, 'published');
  assert.equal(published.matches.length, 3, JSON.stringify(published.matches));
  const semi1 = knockout(published, 1, 1);
  const semi2 = knockout(published, 1, 2);
  const final = knockout(published, 2, 1);
  for (const m of [semi1, semi2]) {
    assert.equal(m.status, 'ready');
    assert.ok(m.side_a && m.side_b);
  }
  assert.equal(final.status, 'waiting');
  const seen = await ok(p1, 'tournament_bracket', { p_tournament_id: tournamentId });
  assert.equal(seen.organizer, false);
  assert.deepEqual(seen.courts, [], 'players see no court list');
  assert.deepEqual(seen.draws.map((d) => d.category_id), [main]);
  for (const p of players) {
    assert.equal((await noticesOf(p, 'draw_published', { category_id: main })).length, 1, `${p.userId}: draw_published`);
  }
  await refused(organiser, 'make_draw', { p_category_id: main, p_format: 'knockout' }, 'draw_published');
  console.log(`  semi-finals ${semi1.id}, ${semi2.id}; final ${final.id}; all four told`);

  step('Fill the day: three matches on the two courts, each with a calendar block');
  const filledDay = await ok(organiser, 'fill_day', {
    p_tournament_id: tournamentId, p_day: day, p_court_ids: courts, p_from: '09:00', p_category_ids: [main],
  });
  assert.deepEqual(filledDay, { scheduled: 3, unscheduled: [] });
  const scheduled = (await ok(organiser, 'tournament_bracket', { p_tournament_id: tournamentId })).draws
    .find((d) => d.category_id === main);
  const [s1, s2, f] = [knockout(scheduled, 1, 1), knockout(scheduled, 1, 2), knockout(scheduled, 2, 1)];
  assert.ok(String(s1.starts_at).replace('T', ' ').startsWith(`${day} 09:00`), `semi-final 1 at ${s1.starts_at}`);
  assert.equal(s2.starts_at, s1.starts_at, 'the semi-finals side by side');
  assert.notEqual(s1.court_id, s2.court_id);
  assert.ok(String(f.starts_at) > String(s1.starts_at), `final at ${f.starts_at}, after ${s1.starts_at}`);
  for (const m of [s1, s2, f]) assert.ok(courts.includes(m.court_id), `${m.id} on ${m.court_id}`);
  const matchIds = [s1.id, s2.id, f.id];
  const matchList = matchIds.map((id) => `'${id}'`).join(', ');
  const blocksSql = `select count(*)::int as n from public.bookings
                     where tournament_match_id in (${matchList}) and venue_id = '${venueId}'
                       and source = 'block' and status = 'confirmed' and user_id is null`;
  assert.equal((await sql(env, blocksSql))[0].n, 3, 'three calendar blocks');
  for (const m of [s1, s2]) {
    for (const reg of [m.side_a, m.side_b]) {
      const p = playerOf(reg);
      assert.equal((await noticesOf(p, 'match_scheduled', { match_id: m.id })).length, 1, `${p.userId}: match_scheduled`);
    }
  }
  console.log(`  semi-finals ${s1.starts_at} on both courts, final ${f.starts_at}; 3 blocks; semi-finalists told`);

  step('The organiser enters the three scores');
  await refused(p1, 'enter_match_score', { p_match_id: s1.id, p_outcome: 'played', p_sets: [[6, 2], [6, 3]] }, 'not_allowed');
  let draw = await ok(organiser, 'enter_match_score', { p_match_id: s1.id, p_outcome: 'played', p_sets: [[6, 2], [6, 3]] });
  assert.equal(knockout(draw, 1, 1).winner, 'a');
  assert.equal(knockout(draw, 2, 1).side_a, s1.side_a, 'the semi-final 1 winner is on side a of the final');
  draw = await ok(organiser, 'enter_match_score', { p_match_id: s2.id, p_outcome: 'played', p_sets: [[3, 6], [4, 6]] });
  assert.equal(knockout(draw, 1, 2).winner, 'b');
  const ready2 = knockout(draw, 2, 1);
  assert.equal(ready2.side_b, s2.side_b, 'the semi-final 2 winner is on side b of the final');
  assert.equal(ready2.status, 'ready');
  draw = await ok(organiser, 'enter_match_score', { p_match_id: f.id, p_outcome: 'played', p_sets: [[6, 4], [7, 5]] });
  assert.equal(knockout(draw, 2, 1).winner, 'a');
  assert.equal(draw.finished, true);
  assert.equal(draw.winner, s1.side_a);
  assert.equal(draw.runner_up, s2.side_b);
  await refused(organiser, 'enter_match_score', { p_match_id: s1.id, p_outcome: 'played', p_sets: [[2, 6], [3, 6]] }, 'next_match_played');

  const champion = playerOf(s1.side_a);
  const runnerUp = playerOf(s2.side_b);
  const semiLosers = [playerOf(s1.side_b), playerOf(s2.side_a)];
  assert.equal((await noticesOf(champion, 'category_won', { category_id: main })).length, 1, 'the champion is told');
  for (const p of [runnerUp, ...semiLosers]) {
    assert.equal((await noticesOf(p, 'category_won', { category_id: main })).length, 0, `${p.userId} did not win`);
  }
  for (const [m, ps] of [[s1, [champion, semiLosers[0]]], [s2, [runnerUp, semiLosers[1]]], [f, [champion, runnerUp]]]) {
    for (const p of ps) {
      assert.equal((await noticesOf(p, 'match_result', { match_id: m.id })).length, 1, `${p.userId}: match_result for ${m.id}`);
    }
  }
  const theirs = await ok(champion, 'my_tournament_matches');
  for (const id of [s1.id, f.id]) assert.ok(theirs.some((m) => m.id === id), `${id} missing from my_tournament_matches`);
  console.log(`  winner ${champion.userId}, runner-up ${runnerUp.userId}; a correction after the final is refused`);

  step('Ratings moved for the three played matches; the blocks stay');
  const results = (await sql(env, `select count(*) filter (where r.status = 'confirmed')::int as confirmed,
                                          count(*)::int as total,
                                          (select count(*)::int from public.rating_events e
                                           join public.match_results x on x.id = e.result_id
                                           where x.tournament_match_id in (${matchList})) as events
                                   from public.match_results r where r.tournament_match_id in (${matchList})`))[0];
  assert.deepEqual(results, { confirmed: 3, total: 3, events: 6 }, JSON.stringify(results));
  const after = {};
  for (const p of players) after[p.userId] = padel(await ok(p, 'my_sports'), p.userId);
  for (const p of semiLosers) {
    assert.equal(after[p.userId].rated_games, 1, JSON.stringify(after[p.userId]));
    assert.ok(after[p.userId].rating < before[p.userId], `semi-final loser ${p.userId}: ${before[p.userId]} -> ${after[p.userId].rating}`);
  }
  for (const p of [champion, runnerUp]) assert.equal(after[p.userId].rated_games, 2, JSON.stringify(after[p.userId]));
  assert.ok(after[champion.userId].rating > before[champion.userId], `champion: ${before[champion.userId]} -> ${after[champion.userId].rating}`);
  for (const p of players) {
    const rated = await noticesOf(p, 'rating_updated');
    const played = matchIds.filter((id) => rated.some((n) => n.payload.match_id === id));
    assert.equal(played.length, after[p.userId].rated_games, `${p.userId}: rating_updated for ${played.length} matches`);
  }
  assert.equal((await sql(env, blocksSql))[0].n, 3, 'played matches keep their blocks');
  for (const p of players) console.log(`  ${p.userId}: ${before[p.userId].toFixed(2)} -> ${after[p.userId].rating.toFixed(2)} (${after[p.userId].rated_games} games)`);

  step('Second category: a withdrawal makes a walkover');
  const draft2 = await ok(organiser, 'make_draw', { p_category_id: second, p_format: 'knockout' });
  assert.equal(draft2.entries.length, 2);
  const published2 = await ok(organiser, 'publish_draw', { p_category_id: second });
  assert.equal(published2.matches.length, 1);
  const only = knockout(published2, 1, 1);
  assert.equal(only.status, 'ready');
  assert.deepEqual([only.side_a, only.side_b].sort(), Object.values(entry2).sort());
  const afterWithdraw = await ok(organiser, 'withdraw_entry', { p_registration_id: entry2[p2.userId] });
  const walkover = knockout(afterWithdraw, 1, 1);
  assert.equal(walkover.status, 'done');
  assert.equal(walkover.outcome, 'walkover');
  assert.equal(walkover.winner, walkover.side_a === entry2[p1.userId] ? 'a' : 'b');
  assert.equal(afterWithdraw.finished, true);
  assert.equal(afterWithdraw.winner, entry2[p1.userId]);
  assert.equal(afterWithdraw.entries.find((e) => e.registration_id === entry2[p2.userId])?.withdrawn, true);
  assert.equal((await noticesOf(p2, 'entry_withdrawn', { category_id: second })).length, 1, 'player 2 is told');
  assert.equal((await noticesOf(p1, 'category_won', { category_id: second })).length, 1, 'player 1 is told');
  const walkoverResults = (await sql(env, `select count(*)::int as n from public.match_results where tournament_match_id = '${only.id}'`))[0].n;
  assert.equal(walkoverResults, 0, 'a walkover writes no result');
  for (const p of [p1, p2]) {
    const now = padel(await ok(p, 'my_sports'), p.userId);
    assert.equal(now.rated_games, after[p.userId].rated_games, `${p.userId}: the walkover moved nothing`);
    assert.equal(now.rating, after[p.userId].rating);
  }
  assert.equal((await ok(p3, 'tournament_bracket', { p_tournament_id: tournamentId })).finished, true, 'the tournament is finished');
  console.log(`  walkover for ${p1.userId}; told; no result, no rating change; tournament finished`);

  console.log('\nBRACKETS END TO END: PASSED');
} catch (e) {
  failed = true;
  console.error(`\nBRACKETS END TO END: FAILED\n${e.stack ?? e}`);
} finally {
  step('Cleaning up the throw-away tournament, venue, results, ratings and accounts');
  const users = createdUsersSql();
  const matches = tournamentId
    ? `select m.id from public.tournament_matches m
       join public.tournament_categories c on c.id = m.category_id
       where c.tournament_id = '${tournamentId}'`
    : null;
  await removeAccounts({
    before: [
      // The throw-away admin goes first, so a later statement that fails never
      // leaves an admin account on the live project.
      ...(users ? [`delete from public.app_admins where user_id in (${users})`] : []),
      ...(tournamentId
        ? [
            // Results first (their players and rating events go with them),
            // then the blocks; both would also go with their matches.
            `delete from public.match_results where tournament_match_id in (${matches})`,
            `delete from public.bookings where tournament_match_id in (${matches})`,
            // Registrations block their category (on delete restrict). The
            // tournament takes its categories, organisers, draws, groups,
            // draw entries and matches with it.
            `delete from public.tournament_registrations
             where category_id in (select c.id from public.tournament_categories c where c.tournament_id = '${tournamentId}')`,
            `delete from public.tournaments where id = '${tournamentId}'`,
          ]
        : []),
      ...(users
        ? [
            `delete from public.rating_events where user_id in (${users})`,
            `delete from public.player_ratings where user_id in (${users})`,
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
        ? [`delete from public.audit_log where actor_id in (${users})`]
        : []),
    ],
  });

  const counts = {
    'test venues': `select count(*) from public.venues where name_en like 'E2E M8 brackets%'`,
    'test tournaments': `select count(*) from public.tournaments where title_en like 'E2E M8 brackets%'`,
    ...(venueId ? { 'venue bookings': `select count(*) from public.bookings where venue_id = '${venueId}'` } : {}),
    ...(tournamentId
      ? {
          categories: `select count(*) from public.tournament_categories where tournament_id = '${tournamentId}'`,
          organisers: `select count(*) from public.tournament_organizers where tournament_id = '${tournamentId}'`,
        }
      : {}),
    ...(users
      ? {
          registrations: `select count(*) from public.tournament_registrations where user_id in (${users}) or partner_id in (${users})`,
          'organiser rows': `select count(*) from public.tournament_organizers where user_id in (${users})`,
          results: `select count(*) from public.match_result_players where user_id in (${users})`,
          'rating events': `select count(*) from public.rating_events where user_id in (${users})`,
          ratings: `select count(*) from public.player_ratings where user_id in (${users})`,
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
