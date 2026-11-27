// End-to-end check of ratings, scores, votes and reports (Milestone 7)
// against the hosted project, with real sessions:
//
//   0. Read-only first: the M7 tables exist and the live sports padel and
//      tennis have competitive_rating = true (the M7 migration does not set
//      that flag). Otherwise it stops before creating anything.
//   1. Five throw-away accounts sign in: an admin and four players (a host,
//      a partner, two opponents). The admin (a row in app_admins) creates a
//      throw-away venue "E2E M7 <timestamp>" with one padel court, so no real
//      venue owner is ever notified.
//   2. The four players answer the padel questionnaire (set_my_sport) with
//      the same answers: everyone starts at the same rating.
//   3. The host books a slot on that court and makes an invite-only game on
//      it with rating range 1-7 (invite-only, so no real player can join it);
//      the host invites the other three and they join.
//   4. A live game cannot be made in the past, so the script moves this
//      game's and this booking's time range (by their ids only) to "started
//      two hours ago, ended one hour ago" through the Management API, then
//      runs app.complete_games(now()).
//   5. The host enters 6-2 6-3 for the host and partner; an opponent
//      confirms. Both winners' ratings rose and both losers' fell (my_sports
//      before and after), the leaderboard lists all four, each has a
//      rating_updated notification, the game is in my_past_games.
//   6. The partner gives an opponent a thumbs up; it reads back. An opponent
//      reports the host; a plain player cannot open the admin review; the
//      report shows in admin_review, the admin closes it, it is gone.
//   7. Everything made here (results, votes, reports, rating events, ratings,
//      the game, the booking, the court, the venue, the admin's audit rows,
//      the app_admins row, the accounts) is deleted, whatever happened; what
//      is left is printed, and anything left fails the run.
//
//   node scripts/e2e-ratings.mjs
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

/** The player's padel entry in my_sports (the list set_my_sport also returns). */
function padel(sports, who) {
  const entry = sports.find((s) => s.sport_id === 'padel');
  assert.ok(entry, `${who} has no padel entry: ${JSON.stringify(sports)}`);
  return { ...entry, rating: Number(entry.rating) };
}

// -- 0. Preconditions (read-only, before anything is created) ---------------
step('Checking the live database is ready for M7 ratings');
const tables = (await sql(env, `select to_regclass('public.player_ratings')::text as ratings,
                                       to_regclass('public.match_results')::text as results,
                                       to_regclass('public.abuse_reports')::text as reports`))[0];
if (!tables.ratings || !tables.results || !tables.reports) {
  console.error('  The M7 tables are missing: run `node scripts/deploy.mjs migrations` first.');
  process.exit(1);
}
const rated = await sql(env, `select id, competitive_rating from public.sports where id in ('padel', 'tennis') order by id`);
const notRated = ['padel', 'tennis'].filter((id) => !rated.some((s) => s.id === id && s.competitive_rating === true));
if (notRated.length) {
  console.error(
    `  Not rated on the live project: ${notRated.join(', ')}. The M7 migration does not set sports.competitive_rating;\n` +
      `  set it to true for padel and tennis (admin panel, or deploy.mjs seed), then run this again. Nothing was created.`,
  );
  process.exit(1);
}
console.log('  M7 tables present; padel and tennis are rated');

let venueId = null;
let failed = false;
try {
  step('Signing in an admin and four players');
  const suffix = String(randomInt(10_000_000)).padStart(7, '0');
  const stamp = new Date().toISOString().replace(/\D/g, '').slice(0, 14);
  const admin = await signIn('admin', `+99809${suffix}`);
  const host = await signIn('host', `+99805${suffix}`);
  const partner = await signIn('partner', `+99806${suffix}`);
  const opp1 = await signIn('opponent 1', `+99807${suffix}`);
  const opp2 = await signIn('opponent 2', `+99808${suffix}`);
  const players = [host, partner, opp1, opp2];
  const tag = [...suffix].map((d) => 'abcdefghij'[d]).join('');
  await saveProfile(admin, `E2E M7 Admin ${tag}`);
  await saveProfile(host, `E2E M7 Host ${tag}`);
  await saveProfile(partner, `E2E M7 Partner ${tag}`);
  await saveProfile(opp1, `E2E M7 Opponent ${tag}`);
  await saveProfile(opp2, `E2E M7 Rival ${tag}`);
  const today = (await sql(env, `select (app.to_local(now(), 300))::date::text as d`))[0].d;

  step('The admin creates a throw-away venue with one padel court');
  await sql(env, `insert into public.app_admins (user_id) values ('${admin.userId}')`, { write: true });
  venueId = await ok(admin, 'admin_save_venue', {
    p_venue: { city_id: 'tashkent', name_en: `E2E M7 ${stamp}`, address_en: 'Nowhere 1', district_en: 'Test', phone: '+998710000000' },
  });
  const court = await ok(admin, 'admin_save_court', {
    p_court: { venue_id: venueId, sport_id: 'padel', name_en: 'Court 1', slot_minutes: 60, base_price: 100000, indoor: true },
  });
  console.log(`  venue ${venueId}, court ${court}`);

  step('The four players answer the padel questionnaire');
  const before = {};
  for (const p of players) {
    const entry = padel(await ok(p, 'set_my_sport', { p_sport_id: 'padel', p_answers: [1, 1, 1, 1, 1] }), p.userId);
    assert.equal(entry.rating, 2.5, `questionnaire rating: ${JSON.stringify(entry)}`);
    assert.equal(entry.rated_games, 0);
    assert.equal(entry.can_retake, true);
    before[p.userId] = entry.rating;
  }
  console.log('  all four start at 2.50, provisional, can retake');

  step('The host books the court and makes an invite-only game rated 1-7; three join');
  let slot = null;
  for (let ahead = 3; ahead <= 10 && !slot; ahead++) {
    const day = await ok(host, 'court_availability', { p_court_id: court, p_date: addDays(today, ahead) });
    slot = day.find((s) => s.state === 'free') ?? null;
  }
  assert.ok(slot, 'no free slot found on the throw-away court');
  const held = await ok(host, 'hold_slots', { p_court_id: court, p_starts: [slot.starts_local] });
  const booking = await ok(host, 'confirm_booking', { p_booking_id: held.id, p_players: 4, p_note: 'e2e m7 ratings' });
  assert.equal(booking.status, 'confirmed');
  const game = await ok(host, 'create_game', {
    p_game: { sport_id: 'padel', booking_id: booking.id, spots: 4, visibility: 'invite_only', min_rating: 1, max_rating: 7 },
  });
  assert.equal(game.my_status, 'host');
  assert.equal(Number(game.min_rating), 1);
  assert.equal(Number(game.max_rating), 7);
  for (const p of [partner, opp1, opp2]) {
    await ok(host, 'invite_to_game', { p_game_id: game.id, p_user_id: p.userId });
    assert.equal((await ok(p, 'join_game', { p_game_id: game.id })).my_status, 'participant');
  }
  const full = await ok(host, 'get_game', { p_game_id: game.id });
  assert.deepEqual([...full.participant_ids].sort(), players.map((p) => p.userId).sort());
  console.log(`  game ${game.id} on booking ${booking.id} (${slot.starts_local}), four players`);

  step('Moving this game and its booking into the past, then completing games');
  const range = `tstzrange(now() - interval '2 hours', now() - interval '1 hour', '[)')`;
  const moved = await sql(
    env,
    `with b as (
       update public.bookings set during = ${range}
       where id = '${booking.id}' and court_id = '${court}' and user_id = '${host.userId}'
       returning id),
     g as (
       update public.games set during = ${range}
       where id = '${game.id}' and booking_id = '${booking.id}' and host_id = '${host.userId}'
       returning id)
     select (select count(*) from b)::int as bookings, (select count(*) from g)::int as games`,
    { write: true },
  );
  assert.deepEqual(moved[0], { bookings: 1, games: 1 }, `the move touched ${JSON.stringify(moved[0])}`);
  // Global, like the scheduled job that runs it every 10 minutes: it also
  // completes any other game that has ended since the job last ran.
  await sql(env, 'select app.complete_games(now())', { write: true });
  const finished = (await notifications(host)).find((n) => n.kind === 'game_finished' && n.payload.game_id === game.id);
  assert.equal(finished?.payload.can_score, true, 'the host is told the game finished and may enter the score');
  console.log('  moved (1 booking, 1 game); the host has game_finished with can_score');

  step('The host enters 6-2 6-3; an opponent confirms');
  const entered = await ok(host, 'enter_score', {
    p_game_id: game.id, p_side_a: [host.userId, partner.userId], p_side_b: [opp1.userId, opp2.userId], p_sets: [[6, 2], [6, 3]],
  });
  assert.equal(entered.result?.status, 'pending', JSON.stringify(entered.result));
  assert.equal(entered.result.winner, 'a');
  await refused(host, 'confirm_score', { p_result_id: entered.result.id }, 'not_found');
  // The partner is on the host's side: recorded, but it does not confirm.
  const sameSide = await ok(partner, 'confirm_score', { p_result_id: entered.result.id });
  assert.equal(sameSide.result.status, 'pending', JSON.stringify(sameSide.result));
  const confirmed = await ok(opp1, 'confirm_score', { p_result_id: entered.result.id });
  assert.equal(confirmed.result.status, 'confirmed', JSON.stringify(confirmed.result));
  console.log(`  result ${entered.result.id} confirmed`);

  step('Ratings rose for the winners and fell for the losers');
  for (const [p, won] of [[host, true], [partner, true], [opp1, false], [opp2, false]]) {
    const after = padel(await ok(p, 'my_sports'), p.userId);
    assert.equal(after.rated_games, 1, JSON.stringify(after));
    assert.equal(after.can_retake, false);
    if (won) assert.ok(after.rating > before[p.userId], `winner ${p.userId}: ${before[p.userId]} -> ${after.rating}`);
    else assert.ok(after.rating < before[p.userId], `loser ${p.userId}: ${before[p.userId]} -> ${after.rating}`);
    const change = confirmed.result.changes[p.userId];
    assert.equal(Number(change.new), after.rating, `changes in the result: ${JSON.stringify(change)}`);
    console.log(`  ${won ? 'winner' : 'loser '} ${p.userId}: ${before[p.userId].toFixed(2)} -> ${after.rating.toFixed(2)}`);
  }

  step('Leaderboard, notifications and past games');
  const board = await ok(host, 'leaderboard', { p_sport_id: 'padel', p_city_id: 'tashkent' });
  const listed = board.rows.map((r) => r.id);
  // The rows stop at 100; past that, each player's own place (me) still shows.
  if (board.rows.length < 100) {
    for (const p of players) assert.ok(listed.includes(p.userId), `${p.userId} missing from the leaderboard`);
  }
  for (const p of players) {
    const own = await ok(p, 'leaderboard', { p_sport_id: 'padel', p_city_id: 'tashkent' });
    assert.equal(own.me?.id, p.userId, `me for ${p.userId}: ${JSON.stringify(own.me)}`);
    assert.equal(own.me.rated_games, 1);
    const note = (await notifications(p)).find((n) => n.kind === 'rating_updated' && n.payload.game_id === game.id);
    assert.ok(note, `${p.userId} has no rating_updated notification`);
    assert.ok((await ok(p, 'my_past_games')).some((g) => g.id === game.id), `${p.userId}: the game is not in my_past_games`);
  }
  console.log(`  all four on the leaderboard (${board.rows.length} rows), each told rating_updated, game in past games`);

  step('A thumbs up and an abuse report; the admin reviews and closes it');
  const voted = await ok(partner, 'vote_player', { p_game_id: game.id, p_target: opp1.userId, p_up: true });
  assert.equal(voted.after_game?.votes?.[opp1.userId], true, JSON.stringify(voted.after_game));
  await ok(opp2, 'report_player', { p_target: host.userId, p_game_id: game.id, p_reason: 'aggression', p_details: 'E2E M7 check' });
  await refused(opp2, 'report_player', { p_target: host.userId, p_game_id: game.id, p_reason: 'other' }, 'already_exists');
  await refused(opp2, 'admin_review', {}, 'not_allowed');
  // The review lists every open report on the live project: only ours is
  // looked at, and nothing from it is printed.
  const ours = (r) => r.reporter_id === opp2.userId && r.target_id === host.userId;
  const report = (await ok(admin, 'admin_review')).reports.find(ours);
  assert.ok(report, 'the report is not in admin_review');
  assert.equal(report.game_id, game.id);
  assert.equal(report.reason, 'aggression');
  await refused(opp2, 'admin_close_report', { p_report_id: report.id }, 'not_allowed');
  await ok(admin, 'admin_close_report', { p_report_id: report.id, p_note: 'E2E M7 closed' });
  assert.ok(!(await ok(admin, 'admin_review')).reports.some(ours), 'the closed report is still listed');
  console.log(`  vote stored; report ${report.id} listed, closed, gone`);

  console.log('\nRATINGS END TO END: PASSED');
} catch (e) {
  failed = true;
  console.error(`\nRATINGS END TO END: FAILED\n${e.stack ?? e}`);
} finally {
  step('Cleaning up the throw-away venue, game, results, ratings and accounts');
  const users = createdUsersSql();
  const games = `select id from public.games where host_id in (${users})`;
  await removeAccounts({
    before: [
      ...(users
        ? [
            // Results first (their players and rating events go with them).
            `delete from public.match_results where game_id in (${games})`,
            `delete from public.game_votes where game_id in (${games}) or voter_id in (${users})`,
            `delete from public.abuse_reports where reporter_id in (${users}) or target_id in (${users})`,
            `delete from public.game_no_show_reports where game_id in (${games}) or reporter_id in (${users})`,
            `delete from public.rating_events where user_id in (${users})`,
            `delete from public.player_ratings where user_id in (${users})`,
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
          games: `select count(*) from public.games where host_id in (${users})`,
          results: `select count(*) from public.match_result_players where user_id in (${users})`,
          'rating events': `select count(*) from public.rating_events where user_id in (${users})`,
          ratings: `select count(*) from public.player_ratings where user_id in (${users})`,
          votes: `select count(*) from public.game_votes where voter_id in (${users}) or target_id in (${users})`,
          reports: `select count(*) from public.abuse_reports where reporter_id in (${users}) or target_id in (${users})`,
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
