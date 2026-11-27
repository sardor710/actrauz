# Actra M7 — Competitive Layer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Padel and tennis players get a 1.0–7.0 rating that moves after confirmed scores, with a leaderboard; every game gets an after-game section (thumbs up/down, "didn't show", report); teams become real.

**Architecture:** Ratings are a server-only ledger: `player_ratings` holds the current value, `rating_events` one row per player per confirmed result, and only SQL functions write either. For rated sports the existing `player_levels.level` becomes a derived band (whole part of the rating, capped at 5) that the server keeps in step, so every existing level check keeps working and old builds keep seeing whole numbers. Scores, votes, reports and teams follow the M2–M6 pattern: rules in `app.*` functions taking the acting user and a clock, thin `public.*` wrappers, tables closed to clients. In the app each feature is a repository method with a sample implementation in `SampleBackend` and a Supabase one, plus screens.

**Tech Stack:** Flutter 3.32.6 (Riverpod, go_router, ARB), Supabase (Postgres migrations), Node test runner on embedded Postgres.

**Spec:** [docs/superpowers/specs/2026-11-27-actra-m7-competitive-design.md](../specs/2026-11-27-actra-m7-competitive-design.md) (approved by the founder 2026-11-27). Product spec: [docs/actra-product-spec.md](../../actra-product-spec.md) §7.1, §7.2, §7.7, §8, §9.1, §9.3, §12.7, §13. Executors read the design first; this plan does not repeat its reasoning.

**Founder decision (2026-11-27):** every padel or tennis game can be scored; a score is optional and any confirmed score moves ratings. There is no rated/friendly switch.

## Global Constraints

- Languages `uz`, `ru`, `kk`, `en`. Every UI string exists in all four ARB files (`app/test/l10n/arb_parity_test.dart`); Uzbek text never contains an ASCII `'` (use `ʻ`). Generated files in `app/lib/l10n/gen/` are committed: run `flutter gen-l10n` after ARB edits.
- The database is live. Migrations are **additive**, deployed only with `node scripts/deploy.mjs migrations`, never `db`.
- Builds made before M7 keep working: no existing `public.*` function loses or renames a parameter or output key; `games.visibility` stays `public` / `invite_only`; `min_level` / `max_level` stay whole numbers 1–5 in every JSON; `player_levels.level` and the foreign key name `player_levels_user_id_fkey` stay.
- `app.*` functions: `set search_path = ''`, explicit `p_user` and `p_now`, errors as `raise exception '<code>'`. `public.*` wrappers: `language sql security definer set search_path = ''`, then `revoke all … from public, anon, authenticated; grant execute … to authenticated, service_role`. Copy any function you replace from **the latest migration that defines it** (most are in `20261126110000_launch.sql` or `20261124110000_games_v2.sql`; `game_json`, `player_json`, `create_game`, `join_game` and `delete_account` are redefined by several M7 tasks, so from Task 2 on the latest copy is in an earlier M7 migration).
- New tables: `enable row level security; revoke all … from anon, authenticated; grant all … to service_role;` (the test shim grants everything by default). Foreign keys to `games`, `profiles` and `teams` use `on delete cascade` unless a task says otherwise (tests delete those rows directly).
- Tuning numbers live in one place: SQL function `app.rating_const(p_name text) returns numeric` and Dart `class RatingRules` in `app/lib/domain/competitive.dart`. Values: `k_provisional 0.30`, `k_established 0.12`, `provisional_games 10`, `margin_min 0.75`, `margin_span 0.50`, `questionnaire_cap 5.00`, `unrated_default 2.50`, `min 1.00`, `max 7.00`.
- New notification categories `ratings` and `teams`; all new kinds are listed in Task 2, 8 and 11.
- Every feature also works in sample mode (`SampleBackend` in `app/lib/data/sample/sample_repositories.dart`).
- The GitHub repo is public: no `.env`, `env/*.json`, keys.
- `npm test` in `supabase/` and `flutter test` plus `flutter analyze` in `app/` pass at the end of every task.
- Deploy, merge and push only when the founder asks.

## Review Focus

1. **A result is applied exactly once.** Two opponents confirming at the same moment, or a confirm racing the 24-hour job, produce one set of rating events. (Task 2 tests `confirm twice changes ratings once`, `concurrent confirm and auto-confirm`.)
2. **Voiding a confirmed result after later games** subtracts that result's own changes from today's ratings; it does not put back the old rating. (Task 2 test `void after a later result`.)
3. **A player who never answered the questionnaire appears in a result** (invited, or on an old build): they start at the others' average, capped at 5.00; if nobody has a rating everyone starts at 2.50. (Task 2 tests `unrated player starts at the others' average`, `all unrated start at 2.50`.)
4. **Old builds:** a padel game created with only `min_level`/`max_level` gets a rating range; every game JSON still has integer `min_level`/`max_level` and a `visibility` of `public` or `invite_only`, including team games. (Task 1 test `old build creates a padel game`, Task 12 test `team game reads as invite-only`.)
5. **A deleted account** in a pending result, in a confirmed result, as the only reporter of a no-show, and as a team captain: deletion succeeds, pending results are voided, confirmed ones keep the other players' changes, the team gets a new captain or is removed. (Task 3 test `deleting an account with results`, Task 8 `deleting an account with votes and reports`, Task 11 `captain account deleted`.)

---

## File Structure

| File | Responsibility |
|---|---|
| `supabase/migrations/20261127100000_ratings.sql` (new) | rating storage, questionnaire, My sports, derived level, rating ranges on games and requests, rating-aware join, categories |
| `supabase/migrations/20261127110000_scores.sql` (new) | results, confirm/dispute, rating maths, admin resolve, roster freeze, leaderboard, past games, game-finished notice, job, deletion |
| `supabase/migrations/20261127120000_after_game.sql` (new) | votes, no-show reports, abuse reports, sportsmanship, admin review |
| `supabase/migrations/20261127130000_teams.sql` (new) | teams, membership, invites, team games |
| `supabase/tests/{ratings,scores,after_game,teams}.test.mjs` (new) | one test file per migration |
| `supabase/scripts/e2e-ratings.mjs`, `e2e-teams.mjs` (new) | live checks |
| `app/lib/domain/competitive.dart` (new) | `RatingRules`, `SportRating`, `MySport`, `MatchResult`, `Leaderboard`, `Sportsmanship`, `AfterGame`, questionnaire and rating maths |
| `app/lib/domain/teams.dart` (new) | `Team`, `TeamMember`, `TeamDraft`, `TeamRef` (moved out of `data/social.dart`) |
| `app/lib/data/repositories.dart`, `data/social.dart`, `data/admin_repository.dart` | new repository methods |
| `app/lib/data/sample/sample_competitive.dart`, `sample_teams.dart` (new, `part of` or helper classes used by `SampleBackend`) | sample rules, so `sample_repositories.dart` does not grow further |
| `app/lib/data/supabase/*` | mappers and RPC calls |
| `app/lib/features/profile/my_sports_screen.dart`, `questionnaire_sheet.dart` (new) | sports, levels, questionnaire |
| `app/lib/features/games/finished_section.dart`, `score_sheet.dart`, `past_games_screen.dart` (new) | after-game section, score entry, past games |
| `app/lib/features/social/leaderboard_screen.dart`, `team_screen.dart`, `team_editor_screen.dart` (new) | leaderboard, teams |
| `app/lib/features/admin/admin_review_screen.dart` (new) | disputed scores, reports, team removal |

---

### Task 0: Workspace

- [ ] **Step 1:** In `D:\actra\.worktrees\m7-competitive`: copy the git-ignored `supabase/.env` and `app/env/dev.json` from `D:\actra\.worktrees\m6-kazakhstan`; run `npm ci --cache D:\actra\.npm-cache` in `supabase/` and `flutter pub get` in `app/` (Flutter at `D:\lab\flutter\bin`).
- [ ] **Step 2:** Run `npm test` in `supabase/` and `flutter test` in `app/`. Expected: 358 and 454 pass (the M6 baseline). `git status` shows nothing new.

## Part 7a — sports, ratings, scores, leaderboard

### Task 1: Ratings, questionnaire and rating ranges (backend)

**Files:**
- Create: `supabase/migrations/20261127100000_ratings.sql`, `supabase/tests/ratings.test.mjs`
- Modify: `supabase/tests/helpers/fixtures.mjs` (add `addRatedSports(pool)`: sets `competitive_rating = true` on `padel` and inserts `tennis` rated; called only by the new test files), `supabase/tests/players.test.mjs:49` (exact key list gains `ratings`)

**Interfaces — produces:**
- Table `public.player_ratings (user_id, sport_id, rating numeric(3,2) check (rating between 1 and 7), rated_games integer not null default 0, source text check (source in ('questionnaire','level','first_result')), created_at, updated_at, primary key (user_id, sport_id))`, server-only.
- Columns `min_rating`, `max_rating numeric(3,2)` on `games` and `game_requests`: both null or `1 <= min <= max <= 7`.
- `app.rating_const(p_name text) returns numeric`; `app.is_rated_sport(p_sport_id text) returns boolean`; `app.questionnaire_rating(p_answers integer[]) returns numeric`; `app.effective_rating(p_user uuid, p_sport_id text) returns numeric` (1.00 when the player has none); `app.rating_json(p_user uuid, p_sport_id text) returns jsonb` (`{"rating","provisional","rated_games"}` or null); `app.sync_level(p_user uuid, p_sport_id text) returns void` (upserts `player_levels.level = least(5, floor(rating))`).
- `app.set_my_sport(p_user uuid, p_sport_id text, p_level integer, p_answers integer[], p_now timestamptz) returns void`; `app.remove_my_sport(p_user uuid, p_sport_id text) returns void`; `app.my_sports(p_user uuid) returns jsonb` — array of `{"sport_id","level","rating","provisional","rated_games","can_retake"}`.
- Public: `my_sports() returns jsonb`; `set_my_sport(p_sport_id text, p_level integer default null, p_answers integer[] default null) returns jsonb`; `remove_my_sport(p_sport_id text) returns jsonb` (both return `my_sports`); `list_players_rated(p_city_id text, p_sport_id text, p_min_rating numeric, p_max_rating numeric, p_query text default null, p_limit integer default 50) returns setof jsonb`.
- JSON additions: `game_json` and `game_request_json` gain top-level `min_rating`, `max_rating` (null for simple sports) and, per participant / join request / interested player, `rating` and `provisional`; `player_json` gains `ratings` `{sport_id: {"rating","provisional","rated_games"}}`.
- New error codes: `rating_locked`.

**Rules to implement**
- Questionnaire: exactly five answers, each 0–3. Points per answer index: Q1 `[0, 0.3, 0.6, 0.8]`, Q2 `[0, 0.2, 0.4, 0.6]`, Q3 `[0, 0.4, 0.8, 1.2]`, Q4 `[0, 0.3, 0.6, 0.7]`, Q5 `[0, 0.3, 0.6, 0.7]`. Rating = `least(5.00, 1.00 + sum)`.
- `set_my_sport`: simple sport → needs `p_level` 1–5, upserts `player_levels`; rated sport → if a rating with `rated_games > 0` exists, only `sync_level` (answers ignored); else needs five answers, upserts the rating with source `questionnaire`, then `sync_level`. Unknown or inactive sport, or wrong arguments → `invalid_argument`. `can_retake` = rated sport and `rated_games = 0`.
- `remove_my_sport` deletes the `player_levels` row only.
- Backfill in the migration: every `player_levels` row of a rated sport with no rating gets `rating = level + 0.5`, source `level`; every game and game request of a rated sport with a null rating range gets one from its level range by the old-build conversion below.
- Replace the three write policies on `player_levels` (insert, update, delete) so they also require `exists (select 1 from public.sports s where s.id = sport_id and not s.competitive_rating)`.
- `create_game`, `create_game_request`: for a rated sport, if `min_rating`/`max_rating` are in the JSON (numbers 1.0–7.0, min ≤ max, else `invalid_argument`) store them and set `min_level = least(5, floor(min_rating))`, `max_level = least(5, floor(max_rating))`; if absent, set `min_rating = min_level`, `max_rating = case max_level when 5 then 7.00 else max_level + 0.99 end`. Simple sports store null. `convert_game_request` passes the request's rating range into the game.
- `join_game`: for a game with `min_rating` set, compare `app.effective_rating` with the range instead of the level; still `level_out_of_range`, still skipped for invited players.
- `list_players_rated`: as `app.list_players` but filtering on `effective_rating between p_min_rating and p_max_rating`; `invalid_argument` if the sport is not rated.
- `admin_save_sport`: on update keep the stored `competitive_rating` whatever the payload says; on create it stays false.
- Notification categories: widen the `notifications` category check (drop by name lookup as `20261125100000_tournaments.sql:38-49` does) and the list inside `public.set_settings` (same signature) to include `ratings` and `teams`.

- [ ] **Step 1: Write the failing tests** in `ratings.test.mjs` (`freshDb('ratings')`, `addCities`, `addRatedSports`, local `player(name, levels)` helper as in `games_v2.test.mjs:36`):
  - `questionnaire scoring`: `[0,0,0,0,0]` → `1.00`; `[3,3,3,3,3]` → `5.00`; `[1,2,1,0,2]` → `2.70`; four answers, an answer of 4, or null → `invalid_argument`.
  - `answering sets rating and level`: `set_my_sport(u,'padel',null,'{1,2,1,0,2}')` → `player_ratings.rating = 2.70`, `player_levels.level = 2`, `my_sports` row `{rating: 2.7, provisional: true, rated_games: 0, can_retake: true}`.
  - `simple sport takes a level`: football level 4 stored; football with answers and no level → `invalid_argument`; padel with only a level → `invalid_argument`.
  - `rating is locked after a rated game`: set `rated_games = 1`, answer again → rating unchanged, no error, `can_retake: false`.
  - `clients cannot write a rated level`: `asUser` insert, update and delete on `player_levels` for padel fail (`42501` or zero rows changed); the same for football succeeds.
  - `backfill`: run the backfill block (between `-- backfill:start` / `-- backfill:end` markers, as `games_v2.test.mjs` does) on a padel level 3 row → rating `3.50`, level 3; an existing open padel game with levels 2–4 and null ratings → `2.00`–`4.99`; a football game stays null.
  - `old build creates a padel game`: `create_game` with `min_level: 2, max_level: 4` → `min_rating 2.00`, `max_rating 4.99`; `max_level: 5` → `7.00`; JSON `min_level`/`max_level` are integers.
  - `rating range sets the level range`: `min_rating: 3.0, max_rating: 4.5` → `min_level 3`, `max_level 4`; `min_rating: 5` with `max_rating: 4` → `invalid_argument`; football game has null ratings.
  - `join checks the rating`: range 3.0–4.5: rating 4.70 → `level_out_of_range`; 4.50 joins; a player with no rating → `level_out_of_range` and joins a 1.0–2.5 game; an invited 4.70 player joins.
  - `request keeps its rating range through conversion`.
  - `players filter by rating`: `list_players_rated` 3.0–4.0 returns the 3.50 player and not the 4.70 one; `player_json.ratings.padel.rating = 3.5`.
  - `sport rating switch is locked`: `admin_save_sport` update with `competitive_rating: false` on padel leaves it true.
  - `new categories can be muted`: `set_settings('{ratings,teams}', false)` succeeds; `'{nonsense}'` still fails.
- [ ] **Step 2: Run** `npm test -- ratings`. Expected: FAIL (relation `player_ratings` does not exist).
- [ ] **Step 3: Write the migration** per "Rules to implement".
- [ ] **Step 4: Run** `npm test`. Expected: all pass (fix the exact-key assertion in `players.test.mjs`).
- [ ] **Step 5: Commit** `M7: ratings, questionnaire and rating ranges in the database`.

### Task 2: Scores and rating changes (backend)

**Files:**
- Create: `supabase/migrations/20261127110000_scores.sql`, `supabase/tests/scores.test.mjs`
- Modify: `supabase/tests/concurrency.test.mjs` (one new test)

**Interfaces — consumes:** Task 1's `effective_rating`, `sync_level`, `rating_const`, `rating_json`.

**Interfaces — produces:**
- Tables (server-only): `match_results (id uuid pk, game_id uuid unique → games, entered_by uuid → profiles, status text check in ('pending','confirmed','disputed','void'), sets jsonb, winner text check in ('a','b','draw'), entered_at, confirm_deadline, confirmed_at, dispute_by uuid, dispute_reason text, flagged_no_show boolean not null default false, resolved_by uuid, resolved_at)`; `match_result_players (result_id, user_id, side text check in ('a','b'), confirmed_at, primary key (result_id, user_id))`; `rating_events (id, user_id, sport_id, result_id, old_rating numeric(3,2), new_rating numeric(3,2), delta numeric(3,2), created_at, unique (result_id, user_id))`.
- `app.enter_score(p_user uuid, p_game_id uuid, p_side_a uuid[], p_side_b uuid[], p_sets jsonb, p_now timestamptz) returns public.match_results`
- `app.confirm_score(p_user uuid, p_result_id uuid, p_now timestamptz) returns public.match_results`
- `app.dispute_score(p_user uuid, p_result_id uuid, p_reason text, p_now timestamptz) returns public.match_results`
- `app.apply_result(p_result_id uuid, p_now timestamptz) returns void` (locks the row `for update`; does nothing unless status is `pending` or `disputed`)
- `app.auto_confirm_scores(p_now timestamptz) returns integer`
- `app.admin_resolve_score(p_user uuid, p_result_id uuid, p_action text, p_sets jsonb, p_now timestamptz) returns void` — `p_action` in `confirm`, `correct`, `void`
- `app.result_json(r public.match_results) returns jsonb` — `{"id","status","sets","winner","entered_by","side_a":[ids],"side_b":[ids],"confirmed_by":[ids],"dispute_reason","flagged_no_show","changes":{user_id:{"old","new"}}}` (`changes` only when confirmed)
- `game_json` gains `result` (null or `result_json`).
- Public: `enter_score(p_game_id uuid, p_side_a uuid[], p_side_b uuid[], p_sets jsonb) returns jsonb`, `confirm_score(p_result_id uuid) returns jsonb`, `dispute_score(p_result_id uuid, p_reason text default null) returns jsonb` (all return the game JSON); `admin_resolve_score(p_result_id uuid, p_action text, p_sets jsonb default null) returns void`.
- Notification kinds, category `ratings`, payload `app.game_note(g) || {"result_id"}`: `score_entered` (to the other players in the result), `score_disputed` (to all players in the result except the disputer), `score_resolved` (to all, with `"action"`), `rating_updated` (to each player, with `"old"`, `"new"`).
- New error codes: `score_closed`.

**Rules to implement**
- `enter_score` checks, in order: signed in (`not_authenticated`); game exists, not cancelled, rated sport, caller is a participant (`not_found`); `upper(during) <= p_now < upper(during) + 7 days` (`score_closed`); caller is the host, or `p_now >= upper(during) + 24 hours` (`not_allowed`); sides are 1+1 or 2+2 distinct participants and include the caller; sets is an array of 1–5 pairs of integers 0–30, no pair `[0,0]` (`invalid_argument`). No result yet → insert `pending`, `confirm_deadline = p_now + 24 hours`. A `pending` result entered by the caller → replace players and sets, clear `confirmed_at`, reset the deadline. A `pending` result entered by someone else → `not_allowed`. Any other status → `already_exists`.
- Winner: more sets won; equal sets → more games; equal → `draw`.
- `confirm_score`: caller is in the result, is not `entered_by`, status `pending` (else `not_found`); records the caller's `confirmed_at`; if the caller is on the other side from `entered_by`, calls `apply_result`.
- `dispute_score`: caller in the result, status `pending` (else `not_found`); status `disputed`, reason trimmed to 300 characters.
- `auto_confirm_scores`: `apply_result` for every `pending` result with `confirm_deadline <= p_now`.
- `apply_result`: after locking the result row, insert missing `player_ratings` rows, then lock the result's players' `player_ratings` rows `for update` in `user_id` order, so two results that share a player cannot lose an update. Players with no `player_ratings` row first get one — the average rating of the result's players who do have a row, rounded to 2 decimals, capped at `questionnaire_cap`; `unrated_default` if nobody has one — source `first_result`. Then with `Ra`, `Rb` the side averages:
  ```
  expected_a = 1 / (1 + 10 ^ (Rb - Ra))            expected_b = 1 - expected_a
  actual     = 1 win, 0.5 draw, 0 loss
  margin     = draw ? 1.0 : margin_min + margin_span * greatest(0, (gw - gl) / (gw + gl))   -- games of winner / loser
  k          = rated_games < provisional_games ? k_provisional : k_established              -- per player
  new        = least(max, greatest(min, old + round(k * margin * (actual - expected), 2)))
  ```
  One `rating_events` row per player (`delta = new - old`), `rated_games + 1`, `sync_level`, status `confirmed`, `rating_updated` notice.
- `admin_resolve_score` (`app.require_admin`): `confirm` and `correct` need status `disputed`; `correct` replaces `sets` and the winner first; both then `apply_result`. `void` accepts `pending`, `disputed` or `confirmed`: for a confirmed result subtract each player's `delta` from their **current** rating (clamped), `rated_games - 1`, `sync_level`, delete its events; status `void`. Every action writes `app.audit(p_user, 'score_' || p_action, 'match_result', id, before, after, p_now)` and sends `score_resolved`.

- [ ] **Step 1: Write the failing tests** in `scores.test.mjs`. Helper `finishedGame(sport, playerIds)` inserts a game that ended one hour before `now` with those participants (first is the host). All ratings below are set directly in `player_ratings`.
  - `host enters and an opponent confirms`: four players at 3.50 with `rated_games 0`; sets `[[6,4],[6,4]]`; after the opponent's `confirm_score`: winners `3.63`, losers `3.37`, four `rating_events`, `rated_games 1`, status `confirmed`, `changes` in the game JSON, four `rating_updated` notices.
  - `established players move less`: same match with `rated_games 10` → `3.55` / `3.45`.
  - `favourite wins small, underdog wins big`: singles 4.50 v 3.50, `[[6,0],[6,0]]`: favourite wins → `4.53` / `3.47`; underdog wins → `3.84` / `4.16`.
  - `draw`: `[[6,4],[4,6]]` at equal ratings → no change, events with `delta 0`.
  - `partner confirming is not enough`: the enterer's partner confirms → still `pending`.
  - `confirm twice changes ratings once`: second `confirm_score` → `not_found`; still four events.
  - `auto-confirm after 24 hours`: `auto_confirm_scores(now + 23h)` → 0; `(now + 24h)` → 1 and ratings moved.
  - `dispute freezes the result`: no events; `auto_confirm_scores(now + 2 days)` → 0; `score_disputed` sent.
  - `host can correct a pending score`: re-entering clears the partner's confirmation and resets the deadline; another participant re-entering → `not_allowed`.
  - `who may enter and when`: before the end → `score_closed`; 8 days after → `score_closed`; a non-host 1 hour after → `not_allowed`, 25 hours after → accepted; football game → `not_found`; cancelled game → `not_found`.
  - `bad scores are refused` (`invalid_argument` each): three players; the same player on both sides; a non-participant; caller not in the sides; six sets; `[[0,0]]`; `[[6]]`; `[[31,0]]`.
  - `unrated player starts at the others' average`: three at 3.00, 4.00, 5.00 and one with no rating → the fourth has a rating row with source `first_result` whose event `old_rating = 4.00`; with others at 6.00, 6.00, 6.00 → `5.00`.
  - `all unrated start at 2.50`.
  - `rating stays within 1.00–7.00`: a 1.00 player loses → `1.00`.
  - `admin confirms, corrects and voids a dispute`: `confirm` applies; `correct` with `[[6,0],[6,0]]` applies the new score; `void` on a disputed result leaves ratings alone; each writes one audit row; a non-admin → `not_allowed`.
  - `void after a later result`: confirm result 1 (+0.13 for player A), then confirm a second game A also wins; read A's rating `r2`; void result 1 → A's rating is `r2 − 0.13`, `rated_games 1`, result 1's events gone, result 2's events untouched, level synced.
  - `levels follow ratings`: a player crossing from 2.95 to 3.05 has `player_levels.level 3`.
  - `client calls`: `asUser` → `public.enter_score` returns game JSON with `result.status = 'pending'`; `asAnon` → `42501`.
- [ ] **Step 2:** Add to `concurrency.test.mjs` the test `concurrent confirm and auto-confirm`: two connections run `app.confirm_score` (opponent) and `app.auto_confirm_scores(now + 24h)` at once (the pattern the file already uses for bookings) → exactly four `rating_events`. And `two results sharing a player`: two games with player A in both, confirmed at once on two connections → A's rating equals the start plus both events' deltas.
- [ ] **Step 3: Run** `npm test -- scores`. Expected: FAIL.
- [ ] **Step 4: Write the migration** per "Rules to implement".
- [ ] **Step 5: Run** `npm test`. Expected: all pass.
- [ ] **Step 6: Commit** `M7: score entry, confirmation and rating changes`.

### Task 3: Leaderboard, past games, game-finished notice, roster freeze (backend)

**Files:**
- Modify: `supabase/migrations/20261127110000_scores.sql` (append), `supabase/tests/scores.test.mjs`, `supabase/tests/games_v2.test.mjs` and `launch.test.mjs` only where the roster freeze changes an existing expectation

**Interfaces — produces:**
- `app.leaderboard(p_user uuid, p_sport_id text, p_city_id text, p_limit integer) returns jsonb` — `{"rows":[{"position","id","name","rating","provisional","rated_games"}],"me":{…same keys} | null}`; `public.leaderboard(p_sport_id text, p_city_id text) returns jsonb` (limit 100).
- `app.my_past_games(p_user uuid, p_now timestamptz) returns setof jsonb`; `public.my_past_games() returns setof jsonb`.
- `app.leave_game` raises `not_found` once `lower(during) <= p_now`.
- `app.complete_games` sends `game_finished` (category `games`, payload `app.game_note(g) || {"can_score": <host of a rated-sport game>}`) to every participant of a game with at least two.
- `actra-send-reminders` job command becomes `select app.send_reminders(now()), app.complete_games(now()), app.expire_game_requests(now()), app.expire_tournament_entries(now()), app.auto_confirm_scores(now())`.
- `app.delete_account` additionally: sets every `pending` or `disputed` result the player is in to `void` (others get `score_resolved` with action `void`), deletes the player's `rating_events` and `player_ratings`. Confirmed results and the other players' events stay.

**Rules:** leaderboard rows are players with `rated_games >= 1` in the sport whose profile city is `p_city_id`, not deleted, not `hidden_from_search`, ordered by rating desc, `rated_games` desc, id; `me` is the caller's own row with their position counted among the same set plus themselves, null when they have no confirmed result. Past games: games the player is a participant of, not cancelled, ended within the last 30 days, newest first, as `game_json`.

- [ ] **Step 1: Write the failing tests:** `leaderboard orders by rating` (positions 1..n; a hidden player and a deleted player are missing; a player in another city is missing; the caller hidden from search is missing from `rows` but present in `me`); `no results, no place` (`me` null); `past games` (ended yesterday listed, ended 31 days ago not, cancelled not, someone else's not); `nobody leaves after the start` (`leave_game` at start + 1 minute → `not_found`; before start still works); `game finished notice` (`complete_games` → each of three participants gets `game_finished`, the padel host's has `can_score: true`, a one-player game sends none); `deleting an account with results` (pending result → `void`; confirmed result keeps the three other players' events and ratings; the deleted player has no `player_ratings` row; deletion does not raise).
- [ ] **Step 2: Run** `npm test -- scores`. Expected: the new tests FAIL.
- [ ] **Step 3: Implement.** Copy `leave_game`, `complete_games` from `20261124110000_games_v2.sql` and `delete_account` from `20261126110000_launch.sql`; reschedule the job in the same `do $$ … pg_cron …` guard.
- [ ] **Step 4: Run** `npm test`. Expected: all pass.
- [ ] **Step 5: Commit** `M7: leaderboard, past games, finished-game notice, roster freeze`.

### Task 4: Ratings in the app's domain, sample backend and Supabase layer

**Files:**
- Create: `app/lib/domain/competitive.dart`, `app/lib/data/sample/sample_competitive.dart`, `app/test/domain/competitive_test.dart`
- Modify: `app/lib/domain/games.dart`, `domain/community.dart`, `data/social.dart`, `data/repositories.dart`, `data/sample/sample_data.dart`, `data/sample/sample_repositories.dart`, `data/supabase/mappers.dart`, `supabase_social_repository.dart`, `supabase_game_repository.dart`, `errors.dart`, `features/common/formatters.dart` (`joinErrorText`), `state/providers.dart`, `app/tool/seed_sql.dart`, four ARB files
- Test: `app/test/data/sample_backend_test.dart`, `test/data/supabase_mappers_test.dart`, `test/data/seed_sql_test.dart`, `test/domain/games_test.dart`

**Interfaces — produces (Dart):**
- `class RatingRules` (constants from Global Constraints); `double questionnaireRating(List<int> answers)` (throws `ArgumentError` on a bad list); `class SportRating { final double rating; final int ratedGames; bool get provisional; }`; `class MySport { final String sportId; final int? level; final SportRating? rating; final bool canRetake; }`.
- `Player.ratings` and `PlayerProfile.ratings` (`Map<String, SportRating>`); `double Player.ratingFor(String sportId)` (1.0 when missing); `GameMember.rating` (`double?`) and `GameMember.provisional` (`bool`, false when absent); `Game.minRating`, `Game.maxRating` (`double?`, in the constructor and `copyWith`); `GameDraft.minRating/maxRating`; `GameRequest` and `GameRequestDraft` likewise.
- `joinGame` uses the rating range when `game.minRating != null`.
- `SocialRepository`: `Future<List<MySport>> mySports()`, `Future<List<MySport>> setSport(String sportId, {int? level, List<int>? answers})`, `Future<List<MySport>> removeSport(String sportId)`; `players(...)` gains `double? minRating, double? maxRating` (used instead of the level range when the sport is rated; the Supabase implementation then calls `list_players_rated`).
- `JoinError.ratingLocked` (`rating_locked`) and `JoinError.scoreClosed` (`score_closed`), with `errRatingLocked`, `errScoreClosed` strings.
- Providers: `mySportsProvider` (`FutureProvider<List<MySport>>`), `refreshSports(WidgetRef ref)` (invalidates `mySportsProvider`, `playerProvider`, `playerProfileProvider`, games).
- Sample data: `kSamplePlayers` get a `ratings` entry for every padel/tennis level they have (`level + 0.5`, 12 rated games so they are established, except p2 with 4). `seed_sql.dart` writes matching `player_ratings` rows and the derived level.
- **The demo player's sports and the test seam.** `SampleBackend` gains `Map<String, int> meLevels` and `Map<String, SportRating> meRatings` (both default empty: a new player has no sports; today's hard-coded level 3 everywhere goes). `sampleBackendProvider` passes them from a new `demoSportsProvider` (`Provider<({Map<String, int> levels, Map<String, SportRating> ratings})>`, default empty). In `app/test/app_flow_test.dart`, `pumpApp` gains `bool withSports = true`: when true it overrides `demoSportsProvider` with level 3 in every simple sport and rating 3.50 with 12 rated games in padel and tennis, so the existing flow tests behave as before; new tests that need a fresh player pass `withSports: false`. The shared `signedIn` prefs gain `'sports_prompted': true` (Task 5 reads it).

- [ ] **Step 1: Write the failing tests.** `competitive_test.dart`: the three questionnaire values from Task 1 and `ArgumentError` for four answers. `games_test.dart`: `joinGame` with range 3.0–4.5 and a 4.7 player → `JoinError.levelOutOfRange`, 4.5 joins, invited 4.7 joins. `sample_backend_test.dart`: `setSport('padel', answers: [1,2,1,0,2])` → rating 2.7, level 2, `canRetake`; `setSport('football', level: 4)`; `removeSport`; `players('tashkent', sportId: 'padel', minRating: 3, maxRating: 4)` returns only players in range; a padel game created with `minRating: 3, maxRating: 4.5` has `minLevel 3`, `maxLevel 4`. Mappers: `gameFromJson` reads `min_rating`, participant `rating`/`provisional`; `playerProfileFromJson` reads `ratings`; a JSON without the new keys still maps (old backend). Seed: `seed_sql_test.dart` expects `player_ratings` rows.
- [ ] **Step 2: Run** `flutter test test/domain test/data`. Expected: FAIL (missing symbols).
- [ ] **Step 3: Implement**, then `dart run tool/gen_seed.dart` and `flutter gen-l10n`. Tests that build `SampleBackend` directly and relied on the demo player being level 3 pass `meLevels` / `meRatings` themselves.
- [ ] **Step 4: Run** `flutter test`, `flutter analyze`, and `npm test -- seed` in `supabase/`. Expected: all pass.
- [ ] **Step 5: Commit** `M7: ratings in the app's domain, sample data and backend calls`.

### Task 5: My sports, questionnaire and rating ranges (screens)

**Files:**
- Create: `app/lib/features/profile/my_sports_screen.dart`, `questionnaire_sheet.dart`, `app/lib/features/common/rating_pill.dart`, `app/test/sports_flow_test.dart`
- Modify: `app/lib/router.dart` (`/sports`), `features/profile/profile_screen.dart`, `features/social/player_profile_screen.dart`, `features/social/social_screen.dart`, `features/games/game_pickers.dart` (`LevelRangeCard` gains a rated mode), `create_game_screen.dart`, `create_request_screen.dart`, `game_screen.dart`, `games_screen.dart`, `game_card.dart`, `request_card.dart`, `features/admin/admin_sports_screen.dart`, `features/shell/home_shell.dart` or `router.dart` (one-time prompt), four ARB files

**Interfaces — produces:** `RatingPill(SportRating rating)` showing `3.47` and a "provisional" tag; `String levelOrRating(BuildContext, Sport, {int? level, SportRating? rating})`; `Future<bool> ensureRated(BuildContext context, WidgetRef ref, Sport sport)` — for a rated sport with no rating opens the questionnaire and returns false if the player closes it.

**Behaviour**
- `/sports` lists every active sport with a switch. Turning on a simple sport opens a 1–5 picker (`showOptionSheet`); turning on a rated sport opens the questionnaire (five single-choice questions, one per page, with a result page "Your starting rating: 2.70"); a rated sport with `canRetake` shows "Retake"; turning off calls `removeSport`.
- Questionnaire copy (en; translate into ru, uz, kk): Q1 "How long have you played?" — under 6 months / 6–24 months / 2–5 years / over 5 years. Q2 "How often do you play?" — rarely / 2–3 times a month / weekly / several times a week. Q3 "Have you competed?" — never / friendly matches with score / amateur tournaments / regular tournaments or league. Q4 padel "How do you play off the back wall?" — I avoid it / I return slow balls / I return most balls / I attack off the wall; tennis "How is your serve?" — I just start the point / it goes in, slowly / steady first and second serve / I win points with it. Q5 padel "At the net…" — I rarely go / I volley easy balls / I hold the net and volley with direction / I finish points with volleys and smashes; tennis "In a rally…" — I keep a few balls in / I rally at medium pace / I control direction and depth / I change pace and spin on purpose.
- Profile: the "My sports" card shows only the player's sports with level or `RatingPill`, an "Edit" link to `/sports`, and an empty state with a button when there are none. Other players' profiles show the same pills.
- One-time prompt: after sign-in, when `mySportsProvider` is empty and the pref `sports_prompted` is not set, show a dismissible sheet "Pick your sports" leading to `/sports`; set the pref either way.
- Rating ranges: for a rated sport `LevelRangeCard` is a 1.0–7.0 slider in 0.5 steps and writes `minRating`/`maxRating`; cards and the game page show "3.0–4.5" instead of "Level 3–4"; the "My level" filter and the join button's in-range test use the rating; Find players shows the rating slider when a rated sport is chosen.
- Before creating or joining a game in a rated sport, call `ensureRated`.
- Admin sports sheet: the rating `SegmentedButton` is disabled with a line "Set by Actra. Ask engineering to change it."

- [ ] **Step 1: Write the failing widget tests** in `sports_flow_test.dart` (import `pumpApp`, `signedIn`, `tap` from `app_flow_test.dart`; these tests use `withSports: false`, and the prompt test uses prefs without `sports_prompted`): `new player is asked to pick sports` (sheet shown once; not on the second launch); `padel questionnaire sets a rating` (answers 2nd, 3rd, 2nd, 1st, 3rd options → "2.70" and "Provisional" on the profile); `football takes a level`; `turning a sport off removes it`; `joining padel without a rating opens the questionnaire`; `padel game shows a rating range` (create with 3.0–4.5 → card shows "3.0–4.5"); `admin cannot switch rating mode` (control disabled).
- [ ] **Step 2: Run** `flutter test test/sports_flow_test.dart`. Expected: FAIL.
- [ ] **Step 3: Implement** with the existing widgets (`SectionCard`, `Pill`, `showOptionSheet`, `AsyncBody`); no new colours or type styles.
- [ ] **Step 4: Run** `flutter test` (including `test/ui`) and `flutter analyze`. Expected: all pass.
- [ ] **Step 5: Commit** `M7: My sports, rating questionnaire and rating ranges in the app`.

### Task 6A: Scores and past games in the app's data layer

**Files:**
- Modify: `app/lib/domain/competitive.dart` (`MatchResult`, `ResultStatus`, `RatingChange`, `ratingChanges(...)`), `domain/games.dart` (`Game.result`, `bool Game.endedAt(DateTime now)`), `domain/community.dart` (`kNotificationCategories` gains `ratings`, `teams`; routes for the new kinds), `data/repositories.dart`, `data/sample/sample_competitive.dart`, `sample_repositories.dart`, `sample_data.dart` (finished padel game seeds, sample-only, not written to `seed.sql`: `gf1` hosted by `me` with p1, p2, p3, ended yesterday, no result; `gf2` hosted by p1 with `me`, p2, p3, ended yesterday, with a pending result entered by p1), `data/supabase/mappers.dart`, `supabase_game_repository.dart`, `features/inbox/inbox_screen.dart` (`notificationText` and icon cases), `features/profile/settings_screen.dart` (`_categoryLabel` cases), `state/providers.dart`, four ARB files
- Test: `app/test/domain/competitive_test.dart`, `test/data/sample_backend_test.dart`, `test/data/supabase_mappers_test.dart`, `test/domain/tournaments_test.dart:817` (category list)

**Interfaces — produces:**
- `GameRepository`: `Future<List<Game>> pastGames()`, `Future<Game> enterScore(String gameId, {required List<String> sideA, required List<String> sideB, required List<(int, int)> sets})`, `Future<Game> confirmScore(String resultId)`, `Future<Game> disputeScore(String resultId, {String? reason})`. `SampleBackend` adds `enterScoreAs`, `confirmScoreAs`, `disputeScoreAs(userId, …)`, `autoConfirmScores()`.
- `class MatchResult { id, status, sets, winner, enteredBy, sideA, sideB, confirmedBy, disputeReason, changes (Map<String, RatingChange>) }`; `({List<RatingChange> a, List<RatingChange> b}) ratingChanges({required List<SportRating?> sideA, required List<SportRating?> sideB, required List<(int, int)> sets})` implementing Task 2's formula, including the starting rating of a player passed as null; `class RatingChange { final double oldRating; final double newRating; double get delta; }`.
- `pastGamesProvider`; notification kinds `game_finished`, `score_entered`, `score_disputed`, `score_resolved`, `rating_updated` all route to `/games/<game_id>` and each has its own inbox text in four languages (`game_finished` has two: "enter the score" when `can_score`, "rate the game" otherwise).
- Sample rules mirror Tasks 2–3: who may enter and when, opponent confirmation, `autoConfirmScores()`, dispute, roster freeze in `leaveAs` (`JoinError.notFound` once started), `game_finished` to `me` when a sample game ends.

- [ ] **Step 1: Write the failing tests.** `competitive_test.dart`: `ratingChanges` gives `+0.13 / −0.13` (four provisional 3.50, 6–4 6–4), `+0.05` established, `+0.03 / −0.03` and `+0.34 / −0.34` for 4.50 v 3.50, `0` for a draw, a null player starting at the others' average capped at 5.00, all null → 2.50. `sample_backend_test.dart`: `gf1` is in `pastGames()` and not in `games()`; `enterScore` by `me` → `pending`; `confirmScoreAs('p2', …)` (opponent) → confirmed, `me` gets `rating_updated`, `mySports` rating moved; a partner's confirm stays pending; `disputeScoreAs` → disputed and no change; `autoConfirmScores()` after 24 hours on a mutable test clock; `leaveAs` on a started game throws `JoinError.notFound`; a score on a football game throws `notFound`; the inbox entry routes to `/games/<id>`. Mappers: `result` maps with `changes`; an absent `result` is null. `tournaments_test.dart:817`: the category list includes `ratings` and `teams`.
- [ ] **Step 2: Run** `flutter test test/domain test/data`. Expected: FAIL.
- [ ] **Step 3: Implement**, then `flutter gen-l10n`.
- [ ] **Step 4: Run** `flutter test`, `flutter analyze`. Expected: all pass.
- [ ] **Step 5: Commit** `M7: scores and past games in the app's data layer`.

### Task 6B: Score entry, confirmation and past games (screens)

**Files:**
- Create: `app/lib/features/games/finished_section.dart`, `score_sheet.dart`, `past_games_screen.dart`, `app/test/scores_flow_test.dart`
- Modify: `app/lib/features/games/game_screen.dart`, `games_screen.dart`, `router.dart` (`/games/past` before `/games/:id`), four ARB files

**Interfaces — consumes:** Task 6A's repository methods, `pastGamesProvider`, `Game.result`, `Game.endedAt`, seeds `gf1`, `gf2`.

**Behaviour**
- The game page shows `FinishedSection` to participants once the game has ended and was not cancelled. For a rated sport its score block is one of: "Enter the score" (host; or any participant after 24 hours) opening `ScoreSheet`; the pending score with "Confirm" / "Dispute" for the other players and "Edit" for whoever entered it; "Waiting for the other side" for the enterer's partner after confirming; the confirmed score with each player's change ("3.50 → 3.63"); "Disputed — an Actra admin will review"; "Result cancelled by Actra" for void. After 7 days with no result: "Score entry closed".
- `ScoreSheet`: pick who played (pre-filled for 2 or 4 participants: host's side first), then 1–5 set rows with two number steppers each, an "Add set" button, and Save.
- Games tab: a "Past games" link above the list opens `/games/past` (cards as in the list, newest first, empty state).

- [ ] **Step 1: Write the failing widget tests** in `scores_flow_test.dart`: `host enters a score` (open `gf1` from Past games, enter 6–4 6–4, see the pending score and "Edit"); `rating change is shown after confirmation` (`confirmScoreAs('p2', …)` on the backend, refresh → the "3.50 → 3.63" line, and an inbox entry that opens the game); `opponent can confirm or dispute` (`gf2`: Confirm shows the confirmed score; in a second test Dispute shows "Disputed"); `past games is empty for a new player`; `a football game has no score block`.
- [ ] **Step 2: Run** `flutter test test/scores_flow_test.dart`. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `flutter test`, `flutter analyze`. Expected: all pass.
- [ ] **Step 5: Commit** `M7: score entry, confirmation and past games screens`.

### Task 7: Leaderboard screen

**Files:**
- Create: `app/lib/features/social/leaderboard_screen.dart`, `app/test/leaderboard_flow_test.dart`
- Modify: `app/lib/domain/competitive.dart` (`LeaderboardRow`, `Leaderboard`), `data/social.dart`, sample and Supabase social repositories, `mappers.dart`, `router.dart` (`/leaderboard/:sportId`), `features/social/social_screen.dart`, `features/profile/profile_screen.dart`, `state/providers.dart`, four ARB files

**Interfaces — produces:** `Future<Leaderboard> SocialRepository.leaderboard(String sportId, String cityId)`; `class Leaderboard { final List<LeaderboardRow> rows; final LeaderboardRow? me; }`; `class LeaderboardRow { position, id, name, rating (SportRating), isMe }`; `leaderboardProvider` (family on `({String sportId, String cityId})`).

**Behaviour:** the Social tab gets a "Leaderboards" card with one row per rated sport; the screen has a sport switch, the city name in the title, rows "1 · name · 4.52 · 14 games" opening the player's profile, the caller's row highlighted, and when `me.position > 100` a pinned row at the bottom. The rating pill on the player's own profile opens the same screen. Empty state: "No confirmed results in {city} yet."

- [ ] **Step 1: Write the failing tests:** sample backend `leaderboard('padel', 'tashkent')` is ordered by rating, has no deleted player, and `me` is null before and present after a confirmed result; mapper test for the JSON of Task 3; widget test `leaderboard lists players and opens a profile`.
- [ ] **Step 2: Run** them. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `flutter test`, `flutter analyze`. Expected: all pass.
- [ ] **Step 5: Commit** `M7: leaderboards`.

## Part 7b — after-game votes, no-shows, reports, admin review

### Task 8: Votes, no-show reports, abuse reports, admin review (backend)

**Files:**
- Create: `supabase/migrations/20261127120000_after_game.sql`, `supabase/tests/after_game.test.mjs`
- Modify: `supabase/tests/players.test.mjs:49` (key list gains `sportsmanship`)

**Interfaces — produces:**
- Tables (server-only): `game_votes (game_id, voter_id, target_id, up boolean not null, updated_at, primary key (game_id, voter_id, target_id))`; `game_no_show_reports (game_id, reporter_id, target_id, created_at, primary key (game_id, reporter_id, target_id))`; `abuse_reports (id uuid pk, reporter_id, target_id, game_id uuid references games on delete set null, reason text check in ('language','aggression','false_score','other'), details text check (char_length(details) <= 500), status text check in ('open','closed') default 'open', admin_note text, closed_by uuid, closed_at, created_at)` with a unique index on `(reporter_id, target_id, coalesce(game_id, '00000000-0000-0000-0000-000000000000'))` where `status = 'open'`.
- `app.vote_player(p_user uuid, p_game_id uuid, p_target uuid, p_up boolean, p_now timestamptz) returns void` (`p_up` null removes the vote)
- `app.report_no_show(p_user uuid, p_game_id uuid, p_target uuid, p_reported boolean, p_now timestamptz) returns void`
- `app.report_player(p_user uuid, p_target uuid, p_game_id uuid, p_reason text, p_details text, p_now timestamptz) returns uuid`
- `app.sportsmanship(p_user uuid) returns jsonb` — `{"votes": n, "percent": p}` with `percent` null when `n < 5`
- `app.admin_review(p_user uuid) returns jsonb` — `{"disputes":[{"result": result_json, "game": game_note, "players":[{"id","name","side"}], "disputed_by_name"}], "reports":[{"id","reporter_id","reporter_name","target_id","target_name","game_id","game","result","reason","details","created_at"}], "counts":{"disputes","reports"}}`; disputes = results with status `disputed` or `flagged_no_show`; a report's `game` is `game_note` and `result` is the `result_json` of that game's result (both null without a game), so an admin can void a confirmed score from a "false score" report
- `app.admin_close_report(p_user uuid, p_report_id uuid, p_note text, p_now timestamptz) returns void` (audit action `report_closed`)
- Public: `vote_player(p_game_id uuid, p_target uuid, p_up boolean) returns jsonb`, `report_no_show(p_game_id uuid, p_target uuid, p_reported boolean) returns jsonb` (both return the game JSON), `report_player(p_target uuid, p_game_id uuid default null, p_reason text default 'other', p_details text default null) returns void`, `admin_review() returns jsonb`, `admin_close_report(p_report_id uuid, p_note text default null) returns void`.
- `game_json` gains `after_game` for participants of an ended game: `{"votes": {target_id: bool}, "no_shows": [target_id]}` (the caller's own entries only; the app works out the 7-day and 48-hour windows from `ends_local` and its own clock, the server enforces them); `player_json` gains `sportsmanship`.
- Notification kind `no_show_recorded` (category `games`, payload `app.game_note(g)`).

**Rules**
- Votes: caller and target are different participants of a non-cancelled game that has ended, within 7 days of its end; otherwise `not_found` (not a participant / not ended) or `score_closed` (too late).
- No-show: same participants rule, within 48 hours of the end (`score_closed` after). After each change recount for the target: `reporters` vs `others = participants − 1`. Majority = `reporters * 2 > others and reporters >= 2`.
  - Majority reached and no `no_show` reliability event with `ref = game id` yet: unless the target is the host and a `no_show` event exists for the game's booking id, insert the event through `app.reliability_event`, delete the target's `game_completed` event for the game, send `no_show_recorded`. If a result of the game includes the target: `pending` → `disputed` with `dispute_reason = 'no_show'`; `confirmed` → `flagged_no_show = true`.
  - Majority lost (a report withdrawn inside the window): delete that `no_show` event and restore `game_completed`. A result already moved to `disputed` stays for the admin.
- Reports: target is a live profile other than the caller; with a game, both are participants; details trimmed, over 500 characters → `invalid_argument`; a second open report for the same pair and game → `already_exists`.
- `delete_account`: delete the player's votes, their no-show reports (recount each affected target) and close their open reports as reporter; reports about them stay.

- [ ] **Step 1: Write the failing tests:** `vote up, change, remove`; `votes need a finished shared game` (before the end, non-participant, self, 8 days later); `sportsmanship hides small samples` (4 votes → `percent` null, `votes 4`; 5 votes with 4 up → `percent 80`); `majority no-show` in a 4-player game (one report → nothing; two reports of three others → `no_show` event, `game_completed` event gone, one `no_show_recorded`; a third report adds nothing); `three-player game needs both others`; `two-player game never reaches a majority`; `withdrawing undoes the penalty`; `venue no-show is not doubled` (host already has a booking `no_show` event → no game event); `no-show reports close after 48 hours`; `no-show against a player in a result` (pending → disputed with reason `no_show`; confirmed → `flagged_no_show` and ratings unchanged); `abuse report` (stored; duplicate → `already_exists`; 501 characters → `invalid_argument`; self → `invalid_argument`; reported player gets no notification); `admin review lists and closes` (one dispute, one flagged result, one report; close writes an audit row; counts drop; non-admin → `not_allowed`); `game json shows only my own votes`; `deleting an account with votes and reports` (a majority that depended on the deleted reporter is undone; no raise).
- [ ] **Step 2: Run** `npm test -- after_game`. Expected: FAIL.
- [ ] **Step 3: Write the migration.**
- [ ] **Step 4: Run** `npm test`. Expected: all pass.
- [ ] **Step 5: Commit** `M7: after-game votes, no-show reports, abuse reports, admin review in the database`.

### Task 9: Votes, "didn't show" and reports in the app

**Files:**
- Create: `app/lib/features/games/report_sheet.dart`, `app/test/after_game_flow_test.dart`
- Modify: `app/lib/domain/competitive.dart` (`AfterGame { myVotes, myNoShows }`, `bool canVote(Game, DateTime now)`, `bool canReportNoShow(Game, DateTime now)`, `Sportsmanship`, `enum ReportReason { language, aggression, falseScore, other }`), `domain/games.dart` (`Game.afterGame`), `domain/community.dart` (`PlayerProfile.sportsmanship`, route for `no_show_recorded`), `data/repositories.dart`, `data/social.dart`, sample and Supabase repositories, `mappers.dart`, `features/games/finished_section.dart`, `features/social/player_profile_screen.dart`, `features/profile/profile_screen.dart`, `features/inbox/inbox_screen.dart`, four ARB files

**Interfaces — produces:** `GameRepository.vote(String gameId, String targetId, bool? up) → Future<Game>`, `GameRepository.reportNoShow(String gameId, String targetId, {required bool reported}) → Future<Game>`, `SocialRepository.reportPlayer(String targetId, {String? gameId, required ReportReason reason, String? details}) → Future<void>`; `SampleBackend.voteAs`, `reportNoShowAs`; `JoinError.alreadyReported` (`already_exists` from `report_player`) with `errAlreadyReported`.

**Behaviour:** `FinishedSection` lists the other participants, each with thumbs up / thumbs down toggles (disabled after 7 days), and an overflow menu with "Didn't show up" (a check mark when set; hidden after 48 hours) and "Report". `ReportSheet`: four reasons as radio rows, an optional text field with a 500-character counter, Send → "Report sent". Profiles show "👍 80% · 5 votes" once `percent` is not null, nothing before that. A player's profile has "Report" in its app-bar menu.

- [ ] **Step 1: Write the failing tests:** sample backend — votes stored and changeable; majority no-show lowers `_reliability` and notifies; `reportPlayer` twice throws `alreadyReported`; `PlayerProfile.sportsmanship.percent` null under five votes. Mappers — `after_game` and `sportsmanship`. Widget tests — `thumbs up a player after the game`; `mark a no-show and undo it`; `report a player` (reason + text → "Report sent"); `sportsmanship appears after five votes`.
- [ ] **Step 2: Run** them. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `flutter test`, `flutter analyze`. Expected: all pass.
- [ ] **Step 5: Commit** `M7: after-game votes, no-shows and reports in the app`.

### Task 10: Admin review screen

**Files:**
- Create: `app/lib/features/admin/admin_review_screen.dart`
- Modify: `app/lib/domain/admin.dart` (`AdminReview`, `AdminDispute`, `AdminReport`), `data/admin_repository.dart`, `_SampleAdminRepository`, `supabase_admin_repository.dart`, `mappers.dart`, `state/admin_providers.dart` (`adminReviewProvider`, included in `refreshAdmin`), `features/admin/admin_home_screen.dart` (entry with the open count), `router.dart` (`/admin/review`), four ARB files
- Test: `app/test/admin_flow_test.dart` (add `/admin/review` to the locked-pages list at line 88, plus the new tests), `test/data/admin_mappers_test.dart`, `test/domain/admin_sample_test.dart`

**Interfaces — produces:** `AdminRepository.review() → Future<AdminReview>`, `resolveScore(String resultId, String action, {List<(int, int)>? sets}) → Future<void>` (`action` is `confirm`, `correct` or `void`), `closeReport(String reportId, {String? note}) → Future<void>`.

**Behaviour:** two tabs. **Scores:** each card shows the sport, date, both sides, the entered score, "Disputed by {name}: {reason}" or "Flagged: no-show", and the buttons Confirm, Correct (opens the set editor from `score_sheet.dart`), Void; each asks for confirmation (`confirmDelete` style). **Reports:** reporter, reported player (opens their profile), reason, text, date, and "Close" with an optional note; when the report's game has a result that is not void, the card shows the score and a "Void this score" button.

- [ ] **Step 1: Write the failing tests:** sample admin — a disputed result appears in `review()`, `resolveScore(id, 'confirm')` applies ratings and removes it, `'void'` on a confirmed result reverses the change, `closeReport` removes the report and adds an audit entry; mapper for the Task 8 JSON; widget tests `admin confirms a disputed score`, `admin closes a report`, and the locked-page check for a non-admin.
- [ ] **Step 2: Run** them. Expected: FAIL.
- [ ] **Step 3: Implement** with `AdminScaffold`, `AdminListView`, `adminWrite`.
- [ ] **Step 4: Run** `flutter test`, `flutter analyze`. Expected: all pass.
- [ ] **Step 5: Commit** `M7: admin review of disputed scores and reports`.

## Part 7c — teams

### Task 11: Teams (backend)

**Files:**
- Create: `supabase/migrations/20261127130000_teams.sql`, `supabase/tests/teams.test.mjs`
- Modify: `supabase/tests/players.test.mjs:49` (key list gains `teams`)

**Interfaces — produces:**
- Tables (server-only): `teams (id uuid pk, name text check (char_length(btrim(name)) between 3 and 40), sport_id → sports, city_id → cities, description text check (char_length(description) <= 500), join_policy text check in ('open','approval'), color_seed integer not null default 0, captain_id uuid → profiles, created_at)` with a unique index on `(city_id, sport_id, lower(btrim(name)))`; `team_members (team_id, user_id, joined_at, primary key (team_id, user_id))` (the captain has a row too); `team_join_requests (id uuid pk, team_id, user_id, status text check in ('pending','approved','declined','withdrawn'), created_at, decided_at)` with one pending row per `(team_id, user_id)`; `team_invites (team_id, user_id, invited_by, status text check in ('pending','accepted','declined'), created_at, primary key (team_id, user_id))`.
- `app.create_team(p_user uuid, p_team jsonb, p_now timestamptz) returns public.teams` — keys `name`, `sport_id`, `city_id`, `description`, `join_policy`
- `app.update_team(p_user uuid, p_team_id uuid, p_team jsonb, p_now timestamptz) returns public.teams` — `name`, `description`, `join_policy` only
- `app.delete_team(p_user uuid, p_team_id uuid, p_now timestamptz) returns void`
- `app.join_team(p_user uuid, p_team_id uuid, p_now timestamptz) returns public.teams`; `app.leave_team(p_user uuid, p_team_id uuid, p_now timestamptz) returns void`
- `app.withdraw_team_request(p_user uuid, p_request_id uuid) returns void`; `app.decide_team_request(p_user uuid, p_request_id uuid, p_approve boolean, p_now timestamptz) returns public.teams`
- `app.remove_team_member(p_user uuid, p_team_id uuid, p_member uuid, p_now timestamptz) returns public.teams`
- `app.invite_to_team(p_user uuid, p_team_id uuid, p_invitee uuid, p_now timestamptz) returns void`; `app.respond_team_invite(p_user uuid, p_team_id uuid, p_accept boolean, p_now timestamptz) returns public.teams`
- `app.transfer_captain(p_user uuid, p_team_id uuid, p_member uuid, p_now timestamptz) returns public.teams`
- `app.admin_delete_team(p_user uuid, p_team_id uuid, p_now timestamptz) returns void` (audit action `team_deleted`, `before` = the team row)
- `app.team_summary_json(t public.teams, p_user uuid) returns jsonb` — `{"id","name","sport_id","city_id","description","join_policy","color_seed","captain_id","member_count","upcoming_games","my_status","my_request_id"}`, `my_status` in `captain`, `member`, `requested`, `invited` or null
- `app.team_json(t public.teams, p_user uuid) returns jsonb` — summary plus `"members":[{"id","name","level","rating","provisional","reliability","captain",("deleted")}]`, `"requests"` (captain only, `[{"id","user_id","name","level","rating","reliability","created_at"}]`), `"games":[game_json]` (filled by Task 12; `[]` here)
- `app.list_teams(p_user uuid, p_city_id text) returns setof jsonb` — the caller's teams (any city) first, then the other teams of the city, by member count desc then name; summaries
- Public wrappers, same names and arguments without `p_user`/`p_now`: `create_team(p_team jsonb) returns jsonb`, `update_team(p_team_id uuid, p_team jsonb)`, `delete_team(p_team_id uuid) returns void`, `join_team(p_team_id uuid)`, `leave_team(p_team_id uuid) returns void`, `withdraw_team_request(p_request_id uuid) returns void`, `decide_team_request(p_request_id uuid, p_approve boolean)`, `remove_team_member(p_team_id uuid, p_member uuid)`, `invite_to_team(p_team_id uuid, p_invitee uuid) returns void`, `respond_team_invite(p_team_id uuid, p_accept boolean)`, `transfer_captain(p_team_id uuid, p_member uuid)`, `get_team(p_team_id uuid) returns jsonb` (null when missing), `list_teams(p_city_id text) returns setof jsonb`, `admin_delete_team(p_team_id uuid) returns void`. Those returning a team return `team_json`.
- `player_json` gains `teams` `[{"id","name","sport_id"}]`.
- Notification kinds, category `teams`, payload `{"team_id","team_name","actor_name"}`: `team_invite` (invitee), `team_join_request` (captain), `team_join_approved`, `team_join_declined`, `team_removed` (the member), `team_captain` (the new captain), `team_deleted` (every member except the actor).
- New error codes: `team_limit`, `captain_cannot_leave`.

**Rules**
- Create: active sport, known city, name 3–40 after trimming, `join_policy` valid (`invalid_argument`); the caller captains fewer than 5 teams (`team_limit`); the name is free in that city and sport, case-insensitive (`already_exists`). `color_seed` = a number 0–7 derived from the id. The creator becomes captain and member.
- Join: already a member → `already_joined`; open team → member (a pending invite becomes accepted); approval team → a pending request (`already_requested` if one exists) and `team_join_request` to the captain. A pending invite lets the invitee join an approval team directly through `respond_team_invite`.
- Captain-only actions (`not_allowed` otherwise): update, delete, decide requests, remove a member, invite, transfer. The captain cannot be removed and cannot leave (`captain_cannot_leave`); transfer needs an existing member.
- Invite: invitee is a live profile, not a member (`already_joined`), not the caller; re-inviting resets a declined invite to pending.
- `delete_account`: for each team the player captains, the member with the earliest `joined_at` among the others becomes captain (`team_captain` notice); with no other member the team is deleted. Then delete the player's memberships, requests and invites.

- [ ] **Step 1: Write the failing tests:** `create a team` (captain is a member; summary `member_count 1`, `my_status 'captain'`); `team names are unique per city and sport` (same name, other case → `already_exists`; same name in another sport or city works); `six teams is too many` (`team_limit`); `open team joins at once`; `approval team needs the captain` (request → `team_join_request`; approve → member and `team_join_approved`; decline → `team_join_declined`; second request while pending → `already_requested`; withdraw); `invite and accept` (invite → `team_invite`; accept joins an approval team; decline; re-invite); `only the captain manages` (member calling update, delete, decide, remove, invite, transfer → `not_allowed`); `captain cannot leave until they hand over` (`captain_cannot_leave`; after `transfer_captain` the old captain leaves; transfer to a non-member → `not_found`); `remove a member` (`team_removed`; removing the captain → `invalid_argument`); `delete a team notifies members`; `team lists` (my team in another city listed first; others ordered by size; `team_json.requests` absent for a non-captain; a deleted member shows `deleted: true`); `player json lists teams`; `admin deletes a team` (audit row; non-admin `not_allowed`); `captain account deleted` (oldest member becomes captain and is notified; a solo team disappears; no raise).
- [ ] **Step 2: Run** `npm test -- teams`. Expected: FAIL.
- [ ] **Step 3: Write the migration.**
- [ ] **Step 4: Run** `npm test`. Expected: all pass.
- [ ] **Step 5: Commit** `M7: teams in the database`.

### Task 12: Team games (backend)

**Files:**
- Modify: `supabase/migrations/20261127130000_teams.sql` (append), `supabase/tests/teams.test.mjs`

**Interfaces — produces:**
- `games.team_id uuid references public.teams (id) on delete set null`, `games.public_from timestamptz`.
- `create_game` accepts `team_id` and `open_hours_before` (null, 12, 24 or 48) in its JSON.
- `game_json` gains `team` (`{"id","name"}` or null) and `public_from_local`; `team_json.games` = the team's games that have not started and are not cancelled, soonest first; `team_summary_json.upcoming_games` = their count.
- Notification kind `team_game_posted` (category `teams`, payload `app.game_note(g) || {"team_id","team_name"}`) to every member except the host; routes to the game.
- `admin_review` gains `"teams":[team summary]` (all teams, newest first, limit 200) for the removal list.

**Rules**
- A team game: the caller is the team's captain, the team's sport and city equal the game's (`invalid_argument` otherwise; unknown team → `not_found`); stored `visibility = 'invite_only'`; `public_from = lower(during) − open_hours_before hours` or null.
- Who sees and may join a game with `team_id`: team members always; everyone from `public_from` on (while spots remain); invited players as today. Add `app.can_see_game(p_user uuid, g public.games, p_now timestamptz)` holding the whole rule; the existing two-argument form stays and calls it with `now()` (it is what `public.get_game` uses). `app.list_games`, `app.join_game`, `app.request_to_join` and every other caller that has a `p_now` use the three-argument form. Level, rating and reliability rules are unchanged.
- A team that is deleted leaves its games as ordinary invite-only games (`team_id` becomes null).

- [ ] **Step 1: Write the failing tests:** `captain posts a team game` (members get `team_game_posted`; a member sees it in `list_games` and joins with one tap; a non-member does not see it, `get_game` is null and `join_game` → `not_found`); `only the captain, only the team's sport` (a member → `not_allowed`; football game for a padel team → `invalid_argument`); `team game reads as invite-only` (`visibility = 'invite_only'`, `team.name` present, `min_level` integer); `opens to everyone` (`open_hours_before: 24` on a game 48 hours away: a non-member is refused at `now`, sees and joins it at `now + 25 hours`); `rating range still applies to members`; `team page lists its games` (`team_json.games` has it, `upcoming_games 1`, a started game is not counted); `deleting the team keeps the game` (`team_id` null, still invite-only); `admin review lists teams`.
- [ ] **Step 2: Run** `npm test -- teams`. Expected: the new tests FAIL.
- [ ] **Step 3: Implement**, copying `create_game`, `can_see_game`, `join_game`, `request_to_join` and `list_games` from their latest definitions (Tasks 1–3 redefined some of them in this milestone's own migrations).
- [ ] **Step 4: Run** `npm test`. Expected: all pass.
- [ ] **Step 5: Commit** `M7: team games in the database`.

### Task 13A: Teams in the app's data layer

**Files:**
- Create: `app/lib/domain/teams.dart`, `app/lib/data/sample/sample_teams.dart`, `app/test/domain/teams_test.dart`
- Modify: `app/lib/data/social.dart` (the old `Team`, `kSampleTeams` and `SampleSocialRepository.teams` go; sample teams are seeded in `SampleBackend` from `kTeamSeeds` in `sample_data.dart`: the eight current names, each with a sample captain and 2–4 sample members, none including `me`), sample and Supabase social repositories, `mappers.dart`, `errors.dart`, `features/common/formatters.dart`, `domain/community.dart` (`PlayerProfile.teams`, routes for team kinds → `/teams/<team_id>`), `features/inbox/inbox_screen.dart` (text for the team kinds), `features/social/social_screen.dart` (only what is needed to compile against the new `Team`), `data/admin_repository.dart` (+ implementations: `deleteTeam(String id)`, `AdminReview.teams`), `state/providers.dart`, `state/ui_providers.dart`, four ARB files, `app/test/ui/ui_content_test.dart` ("teams" group rewritten against `kTeamSeeds`)
- Test: `app/test/data/sample_backend_test.dart`, `test/data/supabase_mappers_test.dart`, `test/data/admin_mappers_test.dart`

**Interfaces — produces:**
- `class Team { id, name, sportId, cityId, description, joinPolicy (TeamJoinPolicy.open | approval), colorSeed, captainId, memberCount, upcomingGames, myStatus (MyTeamStatus.captain | member | requested | invited | null), myRequestId, members (List<TeamMember>), requests (List<TeamRequest>), games (List<Game>) }`; `class TeamMember { id, name, level, rating (double?), provisional, reliability, captain, deleted }`; `class TeamRequest { id, userId, name, level, rating, reliability }`; `class TeamDraft { name, sportId, cityId, description, joinPolicy }`; `class TeamRef { id, name, sportId }`.
- `SocialRepository`: `teams(String cityId) → Future<List<Team>>`, `team(String id) → Future<Team>`, `createTeam(TeamDraft) → Future<Team>`, `updateTeam(String id, TeamDraft) → Future<Team>`, `deleteTeam(String id) → Future<void>`, `joinTeam(String id) → Future<Team>`, `leaveTeam(String id) → Future<void>`, `withdrawTeamRequest(String requestId) → Future<void>`, `decideTeamRequest(String requestId, {required bool approve}) → Future<Team>`, `removeTeamMember(String teamId, String userId) → Future<Team>`, `inviteToTeam(String teamId, String userId) → Future<void>`, `respondTeamInvite(String teamId, {required bool accept}) → Future<Team>`, `transferCaptain(String teamId, String userId) → Future<Team>`. `SampleBackend` adds `createTeamAs`, `joinTeamAs`, `inviteToTeamAs`.
- `JoinError.teamLimit`, `captainCannotLeave`, `nameTaken` (`already_exists` from the team calls) with their strings; `teamProvider` (family), `teamsProvider` (now from the repository), `refreshTeams(WidgetRef ref)`.

- [ ] **Step 1: Write the failing tests.** `teams_test.dart` and `sample_backend_test.dart`: create (I am captain and a member), name taken → `nameTaken`, sixth team → `teamLimit`, open join, approval request → `decideTeamRequest` as the captain, invite → accept, captain cannot leave → `transferCaptain` → leave, remove member, delete; inbox entries for `team_invite` and `team_join_request` route to `/teams/<id>`; `markDeleted` on a sample captain hands the team to the oldest member. Mappers: `team_json` and the summary; `player_json.teams`; `admin_review.teams`.
- [ ] **Step 2: Run** `flutter test test/domain test/data test/ui`. Expected: FAIL.
- [ ] **Step 3: Implement**, then `flutter gen-l10n`.
- [ ] **Step 4: Run** `flutter test`, `flutter analyze`. Expected: all pass.
- [ ] **Step 5: Commit** `M7: teams in the app's data layer`.

### Task 13B: Team screens

**Files:**
- Create: `app/lib/features/social/team_screen.dart`, `team_editor_screen.dart`, `app/test/teams_flow_test.dart`
- Modify: `app/lib/features/social/social_screen.dart`, `player_profile_screen.dart`, `features/profile/profile_screen.dart`, `features/admin/admin_review_screen.dart` (third tab "Teams" with Delete), `router.dart` (`/teams/new` before `/teams/:id`, `/teams/:id`, `/teams/:id/edit`), four ARB files

**Interfaces — consumes:** Task 13A's models, repository methods and providers.

**Behaviour**
- Social tab: "My teams" (tiles with initials on the seeded colour, sport badge, member count, a dot when I have a pending invite) and "Teams in {city}" filtered to my sports with a "Show all" toggle; a "Create a team" button. Tiles open `/teams/:id`.
- Team page: header (initials, name, sport, city, "Open" / "By approval"), description, the main button by status — Join / Request to join / Cancel request / Accept invite + Decline / Leave — and for the captain: Edit, requests with Approve / Decline, a remove action and "Make captain" on each member, Delete team (confirmation). Members list with level or rating and `ReliabilityPill`. The games section is added in Task 14.
- Editor: name, sport and city (fixed after creation), description with a 500 counter, join policy.
- Player profile: "Invite to team" next to "Invite to game", listing the teams I captain that the player is not in; the profile lists the player's teams as tappable pills. My own profile lists my teams.

- [ ] **Step 1: Write the failing widget tests** in `teams_flow_test.dart`: `create a team and see it under My teams`; `join an open team`; `request to join and get approved` (approve through `SampleBackend` as the captain, refresh); `invite a player to my team from their profile`; `captain hands over and leaves`; `a taken name shows an error`; `admin deletes a team`.
- [ ] **Step 2: Run** `flutter test test/teams_flow_test.dart`. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `flutter test`, `flutter analyze`. Expected: all pass.
- [ ] **Step 5: Commit** `M7: team screens`.

### Task 14: Team games in the app

**Files:**
- Modify: `app/lib/domain/games.dart` (`Game.team` (`TeamRef?`), `Game.publicFrom`, `GameDraft.teamId`, `GameDraft.openHoursBefore`), `data/sample/sample_repositories.dart`, `sample_teams.dart`, `mappers.dart` (`gameFromJson`, `gameDraftJson`), `features/games/create_game_screen.dart`, `game_screen.dart`, `game_card.dart`, `features/social/team_screen.dart`, `features/inbox/inbox_screen.dart`, `domain/community.dart`, four ARB files
- Test: `app/test/teams_flow_test.dart`, `test/data/sample_backend_test.dart`, `test/data/supabase_mappers_test.dart`

**Behaviour:** when the chosen sport has a team I captain in the current city, the create-game form shows a "Who can join" choice: Everyone / Invite only / one row per such team. Choosing a team adds "Open to everyone if spots remain": Never / 12 / 24 / 48 hours before. A team game shows a pill with the team name on its card and page (and "Opens to everyone on {date}" when set); the team page gets an "Upcoming games" section and, for the captain, "Post a game" (opens the create form with the team preselected). Members see team games in the Games tab.

- [ ] **Step 1: Write the failing tests:** sample backend — a team game is in `games()` for a member (`joinTeamAs` then view as that player through the `*As` helpers) and not for a non-member; visible to all once the clock passes `publicFrom`; a non-captain creating one throws `forbidden`; members get `team_game_posted`. Mappers — `team`, `public_from_local`, `team_id`/`open_hours_before` in the draft JSON. Widget tests — `captain posts a team game` (pill with the team name; listed on the team page); `team choice is hidden without a team`.
- [ ] **Step 2: Run** them. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `flutter test`, `flutter analyze`. Expected: all pass.
- [ ] **Step 5: Commit** `M7: team games in the app`.

## Wrap-up

### Task 15: Live checks, review, walkthrough, handover

**Files:**
- Create: `supabase/scripts/e2e-ratings.mjs`, `supabase/scripts/e2e-teams.mjs`
- Modify: `supabase/README.md` (the new scripts), `docs/store/data-safety.md` (ratings, votes and reports are now collected), `site/privacy.html` (same, all four languages), this plan's Status section, `docs/superpowers/plans/2026-11-22-actra-roadmap.md` (M7 row note)

- [ ] **Step 1: Write `e2e-ratings.mjs`** in the style of `e2e-community.mjs` (`e2e-lib.mjs`, `step`, `ok`, `refused`, cleanup in `finally`): an admin creates a throw-away Tashkent venue with one padel court; four throw-away players answer the questionnaire (`set_my_sport`); the host books a slot, creates a game with `min_rating 1, max_rating 7`, three join. Because a live game cannot be in the past, the script then moves the game's and booking's `during` two hours back through the Management API query helper `deploy.mjs` uses, and runs `select app.complete_games(now())`. Then: `enter_score` by the host, `confirm_score` by an opponent, assert both winners' ratings rose and both losers' fell in `my_sports`, `leaderboard` lists all four, each has a `rating_updated` notification; a thumbs up and an abuse report are stored and the report shows in `admin_review`; the admin closes it. Cleanup deletes results, votes, reports, ratings, games, bookings, the venue, audit rows and the accounts; it notifies no real owner (throw-away venue).
- [ ] **Step 2: Write `e2e-teams.mjs`:** a captain creates an approval team, a second player requests and is approved, a third is invited and accepts, the captain posts a team game on a throw-away venue, the member sees it and an outsider does not, the captain transfers the role and leaves; cleanup removes the team and everything else.
- [ ] **Step 3: Whole-branch review** by a fresh reviewer against the design and this plan (Review Focus first); fix findings; re-run `npm test`, `flutter test`, `flutter analyze`.
- [ ] **Step 4: Browser walkthrough in sample mode** with a preview entry `actra-m7` (port 5671, `app/tool/run_web_sample.cmd 5671`; do not commit `launch.json`): pick sports and answer the padel questionnaire; open the finished sample game, enter a score, vote, mark a no-show, send a report; leaderboard; create a team, post a team game; admin Review. Repeat the main path in Russian and Kazakh for overflow. Screenshots go in the report.
- [ ] **Step 5: With the founder's go-ahead only:** `node scripts/deploy.mjs migrations`, then `node scripts/e2e-ratings.mjs`, `node scripts/e2e-teams.mjs`, `node scripts/e2e-community.mjs`. `scripts/e2e.mjs` still notifies the real owners of seeded venue v1; do not run it.
- [ ] **Step 6: Update this plan's Status and the roadmap; commit** `Plan: M7 status`. Merge and push only when the founder asks. A fresh app build must go out with the deploy (the level for padel and tennis changes meaning).

---

## Status

**2026-11-27: built and reviewed; not deployed, not merged, not pushed.** Worktree `D:\actra\.worktrees\m7-competitive`, branch `m7-competitive` from `main` 12e94df.

- **Done:** Tasks 0–14 and Task 15 Steps 1–4. Every task had its own reviewer (fix rounds on Tasks 7, 10 and 13B; pre-review fixes on Tasks 2, 3, 5 and 8). The whole branch was then reviewed in two halves (database and app) by senior reviewers: no critical findings, 7 important ones, all fixed in one fix wave per half and re-reviewed; one small follow-up fix for a regression the app fix wave introduced (a failed reload replacing a loaded page).
- **Tests:** supabase `npm test` 463 pass (358 before M7); app `flutter test` 709 pass (454 before M7); `flutter analyze` clean.
- **Not done (needs the founder's go-ahead):** Task 15 Step 5 — deploying the four migrations and running the two live checks. The live-check scripts `e2e-ratings.mjs` and `e2e-teams.mjs` are written and syntax-checked but have never been run.
- **Browser walkthrough (sample mode, phone width):** onboarding → "Pick your sports" prompt → padel questionnaire (2.70, provisional) → Past games → score entry (6–4, waiting for the other side) → thumbs up, "Didn't show up" / Report menu, report sent → Social (My teams, teams of the city, leaderboards) → team page, join → profile (rating, team) → Admin → Review (report with "Void this score", Teams tab). Spot-checked in Russian and Kazakh. Not walked through in the browser: posting a team game and an opponent confirming a score (both need a second player or a booking; covered by tests). Preview entry `actra-m7` (port 5671) is in `D:\actra\.claude\launch.json` (not committed).

**What changed against this plan while building** (each was a ruling recorded during the build):
- The migration itself marks padel and tennis as rated sports before converting levels (design §5.1); nothing has to be set by hand.
- A fourth admin action, **Keep**, for a confirmed score flagged by a no-show report (design §6.2 promised "keep or void").
- A score cannot name a deleted account or a player with a recorded no-show; a result that loses a player is cancelled, never applied.
- A venue's no-show mark and a players' no-show majority for the same game give one penalty, in either order.
- The leaderboard shows a player's own position only in their own profile city.
- `rating_locked` is never raised: answering the questionnaire again after a rated game silently keeps the rating.
- Rating ranges converted from old levels read "2.0–4.9" (one decimal, cut not rounded).
- The rating formula divides last, so an exact half rounds away from zero (established equal sides, 6–3 6–3 → ±0.06) in SQL and in the app alike.
- `list_games` / `join_game` use a helper for the team part of the visibility rule; a team's "upcoming games" count is the same for every viewer.
- Screens now reload what another player changed: on opening a notification, on returning to the app, after a refused action, and by pull-to-refresh; a failed reload keeps the page that was already loaded.

**Before deploying (operator checks, read-only SQL on the live project):**
1. `select id, active, competitive_rating from public.sports where id in ('padel','tennis');` — expect two rows (the migration sets the flag; if a row is missing, padel or tennis stays unrated).
2. `select l.sport_id, l.level, count(*) from public.player_levels l join public.sports s on s.id = l.sport_id where s.id in ('padel','tennis') group by 1,2;` — these rows become "level + 0.5" ratings; only sample players are expected.
3. `select polname from pg_policy where polrelid = 'public.player_levels'::regclass;` — the three write policies the migration replaces.
4. `select command from cron.job where jobname = 'actra-send-reminders';` — one row, four calls.
Deploy at a quiet time (`node scripts/deploy.mjs migrations`): the first file briefly locks `games`, `game_requests`, `notifications` and `player_levels`.

**After deploying:**
1. `select version from supabase_migrations.schema_migrations where version like '20261127%';` — four rows.
2. The cron query again — one row, five calls (now with `app.auto_confirm_scores(now())`); then two successful runs in `cron.job_run_details`.
3. `select count(*) from public.games g join public.sports s on s.id = g.sport_id where s.competitive_rating and g.min_rating is null;` — 0 (same for `game_requests`).
4. `node scripts/e2e-ratings.mjs`, `node scripts/e2e-teams.mjs`, `node scripts/e2e-community.mjs`. Do not run `scripts/e2e.mjs` (it notifies the real owners of seeded venue v1).
5. Ship a fresh app build with the deploy: the level for padel and tennis changes meaning, and builds made before M7 cannot answer the questionnaire.

**Open decisions for the founder:**
- The player's city is saved to the server only at onboarding; changing the city in the app header does not move the player's leaderboard or Find-players city. Decide whether a city change should move them.
- Never hard-delete an account that has match results directly in the database (use the in-app deletion): a hard delete removes confirmed results while leaving the other players' rating changes in place.
- Free text now exists in three more places (a score dispute reason, a report's text, a team's name and description) and is copied into the admin audit log; decide a retention rule with the legal review already on the launch checklist.
- Kazakh and Uzbek wording of the new screens is a draft, like the M6 texts; in Kazakh "өтінім" is used both for a join request and for a Game Request.

**Known and left for later (small):**
- While one game or team action is waiting on the network, a second, different action tapped at the same moment is ignored.
- Two rare lock-order overlaps remain in account deletion (a captain creating a team game while deleting their own account; a deletion with more than ten reported games): Postgres cancels one call and the app retries.
- A no-show flag can stay on a result with two reported players when one of them joined late.
- The sample backend does not recount no-shows when a sample account is deleted (the server does).
- A profile's own row in the game's player list wraps its labels onto a second line on narrow phones; bottom-tab labels are still cut on narrow phones in English and Russian (older than M7).
- On this PC a leftover test-database process (PID 22680, from an interrupted run) blocks a plain `npm test`; end it or reboot, or run the tests with `ACTRA_TEST_DATABASE_URL` pointing at another server.
