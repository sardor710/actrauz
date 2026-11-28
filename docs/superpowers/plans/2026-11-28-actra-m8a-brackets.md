# Actra M8a — Tournament Brackets and Results Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Organisers named per tournament make draws (knockout, or groups then knockout), put matches on the venue's courts (blocked in the owner calendar), enter final scores; brackets update live for players, winners advance, padel/tennis matches move ratings.

**Architecture:** Brackets are server-only tables (`tournament_draws`, `tournament_draw_entries`, `tournament_groups`, `tournament_matches`, `tournament_organizers`) written only by `app.*` functions, as in M5/M7. The score lives on the match; for a rated sport a played match also writes an M7 `match_results` row (linked by a new `tournament_match_id`) and calls the existing `app.apply_result`, so ratings and leaderboards need no second path. Calendar blocks are `bookings` rows with `source = 'block'` and a new `tournament_match_id`. In the app, pure bracket rules live in `domain/brackets.dart` (used by the sample backend and mirrored by SQL tests), a new `OrganizerRepository` carries organiser actions, and screens are added to the tournament page and a new tournament manager.

**Tech Stack:** Flutter 3.32.6 (Riverpod, go_router, ARB), Supabase (Postgres migrations), Node test runner on embedded Postgres.

**Spec:** [docs/superpowers/specs/2026-11-27-actra-m8a-brackets-design.md](../specs/2026-11-27-actra-m8a-brackets-design.md) (approved by the founder 2026-11-28). §14a overrides earlier sections where they touch. Executors read the design first; this plan does not repeat its reasoning.

**Founder decisions:** organisers per tournament (option B); option 1 (own match tables, ratings through M7 results); an organiser who plays may score their own match.

## Global Constraints

- Languages `uz`, `ru`, `kk`, `en`. Every UI string exists in all four ARB files (`app/test/l10n/arb_parity_test.dart`); Uzbek text never contains an ASCII `'` (use `ʻ`). Generated files in `app/lib/l10n/gen/` are committed: run `flutter gen-l10n` after ARB edits.
- The database is live. Migrations are additive (the one exception: `match_results.game_id` becomes nullable; live has 0 rows), deployed only with `node scripts/deploy.mjs migrations`, never `db`.
- Builds made before M8 keep working: no existing `public.*` function loses or renames a parameter or output key; new JSON keys only.
- `app.*` functions: `set search_path = ''`, explicit `p_user` and `p_now`, errors as `raise exception '<code>'`. `public.*` wrappers: `language sql security definer set search_path = ''`, then `revoke all … from public, anon, authenticated; grant execute … to authenticated, service_role`. Copy any function you replace from **the latest migration that defines it**: `admin_save_tournament` → `20261126110000_launch.sql`; `admin_save_category` → `20261126100000_kazakh.sql`; `admin_delete_category` → `20261125110000_admin_tournaments.sql`; `owner_cancel_booking` → `20261124110000_games_v2.sql`; `delete_account` and `game_json` → `20261127130000_teams.sql`; `apply_result`, `admin_resolve_score`, `result_note`, `result_json` → `20261127110000_scores.sql`; the after-game resolver → `20261127120000_after_game.sql`. Functions replaced by an earlier M8 task are copied from that task's migration.
- New tables: `enable row level security; revoke all … from anon, authenticated; grant all … to service_role;`.
- **Lock order, everywhere:** scheduling, score entry and withdrawal first take `pg_advisory_xact_lock(hashtext('tournament:' || tournament_id))` (one lock per tournament, so cross-category checks are serialised); then the category row (several categories: in id order), then its `tournament_draws` row, then matches in `(stage, round, position)` order, then registration rows, then bookings, then `match_results` (and M7's rating rows after it), then the tournament row last.
- Times: functions take venue wall-clock `timestamp` and convert with the tournament city's offset, as `app.hold_slots` and M5's deadline do; JSON times use the same format as game JSON.
- Notifications: category `tournaments`; payload always has `tournament_id`, `category_id` and, where there is one, `match_id`. Kinds: `organizer_added`, `organizer_removed`, `draw_published`, `draw_redone`, `waitlist_closed`, `match_scheduled`, `match_result`, `entry_withdrawn`, `category_won`.
- New error codes (SQL → Dart `TournamentError`): `draw_exists` → `drawExists`, `draw_published` → `drawPublished`, `draw_outdated` → `drawOutdated`, `draw_final` → `drawFinal`, `too_few_entries` → `tooFewEntries`, `slot_taken` → `slotTaken`, `player_busy` → `playerBusy`, `next_match_played` → `nextMatchPlayed`, `draw_not_allowed` → `drawNotAllowed`, `tournament_block` → `tournamentBlock`, `matches_outside_dates` → `matchesOutsideDates`. Existing `not_allowed`, `not_found`, `invalid_argument` keep their meaning.
- Group points: win 2, draw 1, loss 0, walkover win 2 / loss 0. Non-rated sports' score: one pair of whole numbers 0–99. Rated sports: M7 `app.check_sets` (1–5 sets, 0–30, no 0–0).
- Every feature also works in sample mode (`SampleBackend`, `app/lib/data/sample/`).
- The GitHub repo is public: no `.env`, `env/*.json`, keys.
- `npm test` in `supabase/` and `flutter test` plus `flutter analyze` in `app/` pass at the end of every task.
- Deploy, merge and push only when the founder asks.

## Review Focus

1. **Correcting a knockout score after the winner has moved on** (next match scheduled, unscored): the new winner replaces the old one in the next match, both are notified, and the rating change is reversed exactly once and the new one applied once. (Task 3 test `correction moves the new winner on`; Task 4 test `correction reverses once`.)
2. **A bracket full of withdrawals still finishes:** an 8-draw where both sides of one quarter-final withdraw, and a player waiting in a semi-final withdraws before their opponent is known, still produces a winner with no match stuck in `waiting`. (Task 3 test `bracket with withdrawals completes`.)
3. **The same player in two categories** is never scheduled by an organiser in overlapping slots, manually, by "fill the day", or by two organisers at once; a winner who advances into a slot that overlaps their match elsewhere is flagged `clash` for the organiser to move. (Task 2 tests `player busy across categories`, `fill the day respects players`, the concurrency test; Task 3 test `advancing into a clash is flagged`.)
4. **Two organisers at once:** two concurrent score entries on one match leave one winner in the next match and one non-void rating result; "fill the day" racing an app booking on the same slot leaves no overlap and a clean `slot_taken` or skip. (Task 3 and Task 2 tests in `concurrency.test.mjs`; Task 4 test `concurrent entries apply ratings once`.)
5. **An account deleted mid-tournament:** its unplayed matches become walkovers, its played scores stay, its pending results follow M7 (void), and the deletion itself succeeds even though the category is locked. (Task 3 test `deleted account is withdrawn`; Task 4 test `deleted account keeps others' rating changes`.)

---

## File Structure

| File | Responsibility |
|---|---|
| `supabase/migrations/20261128100000_draws.sql` (new) | organisers, draw tables, draw making, seeding, swap, publish/redo, entry lock, M5 guards, `draw_json`, `tournament_bracket` |
| `supabase/migrations/20261128110000_schedule.sql` (new) | match courts/times, calendar blocks, fill the day, owner refusal, tournament edits that touch the schedule |
| `supabase/migrations/20261128120000_match_scores.sql` (new) | score entry, advancement, standings, qualifiers, corrections, withdrawals, deletion, my matches |
| `supabase/migrations/20261128130000_tournament_ratings.sql` (new) | `match_results` link, `result_sport`, `reverse_result`, ratings from tournament matches |
| `supabase/tests/{draws,schedule,match_scores,tournament_ratings}.test.mjs` (new) | one test file per migration; `helpers/fixtures.mjs` gains `addTournament`, `addCategory`, `addEntries` |
| `supabase/scripts/e2e-tournaments.mjs`, `e2e-brackets.mjs` (new) | live checks |
| `app/lib/domain/brackets.dart` (new) | types and pure rules (seed order, groups, round robin, standings, qualifiers) |
| `app/lib/data/organizer_repository.dart` (new) | organiser actions interface |
| `app/lib/data/sample/sample_brackets.dart` (new) | sample implementation, used by `SampleBackend` |
| `app/lib/data/supabase/supabase_organizer_repository.dart` (new) | RPC calls; mappers in `mappers.dart` |
| `app/lib/features/tournaments/bracket_view.dart`, `group_table.dart`, `next_match_card.dart` (new) | player views |
| `app/lib/features/organizer/` (new folder) | `organized_tournaments_screen.dart`, `manager_screen.dart`, `draw_tab.dart`, `schedule_tab.dart`, `scores_tab.dart`, `score_sheet.dart` |

The design's §12 named one migration and a `tournament_group_entries` table; this plan uses four migrations (one per backend task, as M7 did) and puts the group on `tournament_draw_entries.group_id`. Same data, smaller review units.

---

### Task 0: Workspace

- [ ] **Step 1:** In `D:\actra\.worktrees\m8-brackets` (already created from `main` dd5ea3e, with `supabase/.env` and `app/env/dev.json` copied): run `npm ci --cache D:\actra\.npm-cache` in `supabase/` and `flutter pub get` in `app/` (Flutter at `D:\lab\flutter\bin`).
- [ ] **Step 2:** Run `npm test` in `supabase/` and `flutter test` in `app/`. Expected: 463 and 712 pass (the M7 baseline). If `npm test` hangs in initdb, a leftover embedded-Postgres process is running: use `ACTRA_TEST_DATABASE_URL` against a side server (the runner supports it) and say so in the report.

## Part 1 — backend

### Task 1: Organisers, draws and seeding

**Files:**
- Create: `supabase/migrations/20261128100000_draws.sql`, `supabase/tests/draws.test.mjs`
- Modify: `supabase/tests/helpers/fixtures.mjs` (add `addTournament(pool, {sportId='padel', venueId=null, startsOn, endsOn})`, `addCategory(pool, tournamentId, {kind='singles', cap=32})`, `addEntries(pool, categoryId, users, {partners})` inserting `registered` rows)

**Interfaces — produces:**
- Tables: `tournament_organizers (tournament_id → tournaments cascade, user_id → profiles cascade, added_by uuid → profiles set null, added_at timestamptz, primary key (tournament_id, user_id))`; `tournament_draws (category_id uuid pk → tournament_categories cascade, format text check in ('knockout','groups'), group_size integer check in (3,4), advance integer check in (1,2), status text check in ('draft','published'), locked boolean not null default false, outdated boolean not null default false, made_by uuid, made_at, published_at, first_score_at)` (`group_size`/`advance` null for knockout); `tournament_groups (id, category_id → cascade, label text, sort_order)`; `tournament_draw_entries (registration_id uuid pk → tournament_registrations cascade, category_id, seed integer, strength numeric, group_id → tournament_groups null, withdrawn_at timestamptz)`; `tournament_matches (id, category_id → cascade, stage text check in ('group','knockout'), group_id null, round integer, position integer, side_a uuid → tournament_registrations null, side_b null, a_empty boolean default false, b_empty boolean default false, status text check in ('waiting','ready','done'), outcome text check in ('played','walkover','retired','decider','bye','none'), winner text check in ('a','b','draw'), sets jsonb, court_id → courts null, starts_at timestamptz, place_note text check (char_length <= 100), scored_by uuid, scored_at, unique (category_id, stage, group_id, round, position))`. On delete: `group_id` → cascade; `side_a`, `side_b` → `set null` (only a hard delete of a profile reaches it; the product never hard-deletes); `court_id` → `set null`; `made_by`, `scored_by`, `added_by` → profiles `set null`.
- `app.require_organizer(p_user uuid, p_tournament_id uuid) returns void` — admins and named organisers pass; else `not_allowed`.
- `app.admin_set_organizer(p_user uuid, p_tournament_id uuid, p_target uuid, p_add boolean, p_now timestamptz) returns void` — admin only; audited; notifies `organizer_added` / `organizer_removed`.
- `app.make_draw(p_user uuid, p_category_id uuid, p_format text, p_group_size integer, p_advance integer, p_now timestamptz) returns void`
- `app.swap_draw_entries(p_user uuid, p_category_id uuid, p_registration_a uuid, p_registration_b uuid, p_now timestamptz) returns void`
- `app.publish_draw(p_user uuid, p_category_id uuid, p_now timestamptz) returns void`; `app.redo_draw(p_user uuid, p_category_id uuid, p_now timestamptz) returns void`
- `app.match_json(m public.tournament_matches) returns jsonb` — `{"id","stage","group_id","round","position","side_a","side_b","a_empty","b_empty","status","outcome","winner","sets","court_id","starts_at","place_note"}` (sides are registration ids).
- `app.draw_json(p_category_id uuid, p_user uuid) returns jsonb` — null for a non-organiser unless published; `{"category_id","format","group_size","advance","status","outdated","entries":[{"registration_id","seed","strength","group_id","withdrawn","players":[{"id","name"}]}],"groups":[{"id","label"}],"matches":[match_json…]}`.
- Public: `admin_set_organizer(p_tournament_id uuid, p_user_id uuid, p_add boolean) returns jsonb` (the organiser list `[{"id","name"}]`), `tournament_organizers(p_tournament_id uuid) returns jsonb` (admin), `make_draw(p_category_id uuid, p_format text, p_group_size integer default null, p_advance integer default null) returns jsonb`, `swap_draw_entries(p_category_id uuid, p_registration_a uuid, p_registration_b uuid) returns jsonb`, `publish_draw(p_category_id uuid) returns jsonb`, `redo_draw(p_category_id uuid) returns jsonb` (these four return `draw_json`), `tournament_bracket(p_tournament_id uuid) returns jsonb` → `{"organizer": bool, "draws": [draw_json…]}` (Tasks 2–3 add keys), `my_organized_tournaments() returns jsonb` → `[{"id","title_uz","title_ru","title_en","starts_on","ends_on","city_id","sport_id"}]`, `organizer_entries(p_tournament_id uuid) returns jsonb` (organisers and admins: the same entry JSON as the admin participants list, names and phones included).

**Rules to implement**
- Entries = `registered` rows of the category. Strength: rated sport → `app.effective_rating` (pairs: average of registrant and partner); other sports → `app.player_level`, 0 if none (pairs: average). Order: strength desc, then `random()`; seed = position.
- Knockout: `n >= 2` else `too_few_entries`. Size `S` = next power of two ≥ n. Seed order of bracket slots: start `[1, 2]`; each doubling maps every `s` to `[s, 2·len + 1 − s]` (S=4 → `[1,4,2,3]`, S=8 → `[1,8,4,5,2,7,3,6]`). Round 1 match `p` takes slots `2p−1` (side a) and `2p` (side b); a seed `> n` is an empty side; a match with one empty side is `done`, outcome `bye`, winner the other side, which is placed in the next match. Later rounds exist from the start as `waiting` rows. Winner of `(r, p)` goes to `(r+1, ceil(p/2))`, side a if `p` odd.
- Groups: `n >= 3` else `too_few_entries`; `group_size` in (3,4) and `advance` in (1,2) else `invalid_argument`. Group count `G = ceil(n / group_size)`; if the smallest group would have fewer than 3 entries, `G = G − 1` (minimum 1). Group sizes differ by at most one. Snake seeding: seeds 1..G to groups A..G, then G..A, and so on. Labels `A`, `B`, …. Round robin by the circle method (a dummy for odd sizes); group matches carry `round` and `position`. Knockout rounds after groups: `Q = G · advance` qualifiers, `S` = next power of two ≥ Q, rows created `waiting` (filled in Task 3); a round-1 slot whose qualifier seed is `> Q` is marked empty now, and when the qualifiers are placed such a match becomes `done` with outcome `bye`, never `walkover`. `G = 1` with `advance = 1`: no knockout; the group winner wins the category (Task 3).
- `make_draw`: `require_organizer` on the category's tournament; refused `draw_published` when the draw is published; replaces any draft (delete its matches, groups, entries); `outdated = false`.
- `swap_draw_entries`: draft only (`draw_published`); swaps seeds (knockout) or groups (groups format) of two entries and rebuilds the affected matches.
- **Outdated drafts:** a trigger on `tournament_registrations` (insert, or update of `status` / `category_id`) sets `outdated = true` on the draft of every category it touches.
- **Entry lock (§6.4, §14a.7):** `locked` becomes true at first publish and stays. A trigger on `tournament_registrations` refuses, with `draw_published`, in a locked category: inserting a row with a live status; any update of `status` where old or new status is `registered`, or new status is `pending_partner`, `waitlisted` or `offered`; moving a `registered` row in or out. It skips when `current_setting('actra.draw_override', true) = 'on'` (set locally by Task 3's withdraw). Expiring invites and offers to dead statuses and changing `paid_at` stay allowed.
- `publish_draw`: draft and not outdated (`draw_outdated`); sets `status = 'published'`, `locked`, `published_at`; every `offered` or `waitlisted` row becomes `lapsed` (under the override) with `waitlist_closed` to its players; `draw_published` to every player of every entry.
- `redo_draw`: published; refused `draw_final` once `first_score_at` is set; deletes the category's matches (their blocks go with them, Task 2's cascade), remakes the draw as a draft with the same format from the current `registered` entries; `draw_redone` to every player.
- Every organiser action writes `app.audit`.

- [ ] **Step 1: Write the failing tests** in `draws.test.mjs` (`freshDb('draws')`, `addCities`, `addRatedSports`, fixtures above):
  - `seed order`: S=8 knockout of 8 entries with ratings 7..0 → round 1 pairs seeds (1,8), (4,5), (2,7), (3,6).
  - `byes go to top seeds`: 5 entries → S=8; seeds 1–3 have `bye` matches and already sit in round 2; seeds 4 and 5 meet.
  - `two entries make a final`: 2 entries → one round-1 match `ready`; 1 entry → `too_few_entries`.
  - `pairs strength is the average`: pair (3.0, 5.0) is seeded above pair (3.5, 3.5) only when its average is higher — assert 4.0 above 3.5.
  - `group sizes`: n=10 size 3 → 4,3,3; n=10 size 4 → 4,3,3; n=5 size 4 → one group of 5; n=7 size 4 → 4,3; n=2 groups → `too_few_entries`.
  - `snake seeding`: n=8 size 4 → group A has seeds 1,4,5,8, B has 2,3,6,7.
  - `round robin`: a group of 4 has 6 matches in 3 rounds, nobody twice in one round; a group of 3 has 3 matches.
  - `organiser scope`: a named organiser makes a draw; an organiser of another tournament gets `not_allowed`; an admin passes; a stranger gets `not_allowed`.
  - `draft is hidden`: `draw_json` for a player of the category is null before publish, present after.
  - `swap in draft`: swapping seeds 1 and 8 changes round 1; after publish → `draw_published`.
  - `outdated draft cannot be published`: a new registration after `make_draw` → `publish_draw` gives `draw_outdated`; `make_draw` again → publish works.
  - `publish locks entries`: after publish, `register` → `draw_published`; `cancel_registration` of a registered entry → `draw_published`; `admin_set_paid` still works; an offered row became `lapsed` with a `waitlist_closed` notice; every entry's players got `draw_published`.
  - `job can still expire invites`: a `pending_partner` row in a locked category expires through `app.expire_tournament_entries` without error.
  - `redo`: redo before any score → draft again from current entries, players got `draw_redone`; set `first_score_at` → `draw_final`.
  - `organizers`: `admin_set_organizer` add/remove notifies; non-admin → `not_allowed`; `my_organized_tournaments` lists only the caller's; `organizer_entries` returns phones to an organiser and `not_allowed` to a player.
- [ ] **Step 2: Run** `npm test -- draws`. Expected: FAIL (relation `tournament_draws` does not exist).
- [ ] **Step 3: Write the migration** per "Rules to implement".
- [ ] **Step 4: Run** `npm test`. Expected: all pass.
- [ ] **Step 5: Commit** `M8a: organisers, draws and seeding in the database`.

### Task 2: Schedule and calendar blocks

**Files:**
- Create: `supabase/migrations/20261128110000_schedule.sql`, `supabase/tests/schedule.test.mjs`
- Modify: `supabase/tests/concurrency.test.mjs` (one test)

**Interfaces — consumes:** Task 1 tables, `require_organizer`, `match_json`, `tournament_bracket`.

**Interfaces — produces:**
- Column `bookings.tournament_match_id uuid unique references tournament_matches on delete cascade` (only on `source = 'block'` rows; check constraint).
- `app.schedule_match(p_user uuid, p_match_id uuid, p_court_id uuid, p_starts_at timestamp, p_place_note text, p_now timestamptz) returns void` — `p_starts_at` null clears the schedule.
- `app.fill_day(p_user uuid, p_tournament_id uuid, p_day date, p_court_ids uuid[], p_from time, p_category_ids uuid[], p_now timestamptz) returns jsonb` → `{"scheduled": int, "unscheduled": [match ids]}`; `p_category_ids` null = all categories.
- `app.release_match_block(p_match_id uuid) returns void` (deletes the match's block; used by Tasks 3–4).
- `match_json` gains `court_name`, `ends_at` and `clash` (true when a player of a known side is in another scheduled match of the tournament overlapping this one; computed on read). **Call:** advancing never moves a match; the organiser sees the flag and moves it. `tournament_bracket` gains `"courts": [{"id","name","slot_minutes"}]` of the venue (organisers only).
- Public: `schedule_match(p_match_id uuid, p_court_id uuid default null, p_starts_at timestamp default null, p_place_note text default null) returns jsonb` (the match), `fill_day(p_tournament_id uuid, p_day date, p_court_ids uuid[], p_from time, p_category_ids uuid[] default null) returns jsonb`.
- `owner_calendar` slot JSON gains `"tournament": {"title", "match_id"}` for tournament blocks (additive).

**Rules to implement**
- `schedule_match`: draw published (`not_found` otherwise); match not `done`. With a venue: `p_court_id` is an active court of the tournament's venue; `p_starts_at` is one of `app.court_slots(court, day)` starts; the day is within `starts_on..ends_on`; length = the court's `slot_minutes` (`invalid_argument` otherwise). Refuse `player_busy` when any player (registrant or partner) of either side is in another match of the same tournament whose time overlaps. Refuse `slot_taken` on an overlap with any booking or block (catch the exclusion violation and re-raise). Moving: old block released and new one inserted in the same transaction; block reason `Tournament: <title in uz/ru/en coalesce>`, status `confirmed`, `source = 'block'`. Without a venue: `p_court_id` must be null, the day within the dates, `p_place_note` trimmed ≤100; no block. `match_scheduled` to every player of known sides when a time is set or changed.
- `fill_day`: candidates = unscheduled matches with status `waiting` or `ready` and outcome null in the ticked published categories. Order: group matches by `(round, category sort_order, group label, position)`, then knockout by `(round, category sort_order, position)`. For each match in order, take the earliest free slot (time, then court in `p_court_ids` order) from `p_from` to closing that: is free; has no player of a known side busy; starts after both feeder matches end when they are scheduled (`(r−1, 2p−1)`, `(r−1, 2p)`); for knockout round 1 after groups, starts after the category's last scheduled group match ends. First pass also requires one free slot between an entry's group matches; matches that fail get a second pass without that gap. Return the rest as `unscheduled`.
- `owner_cancel_booking`: a block with `tournament_match_id` → `tournament_block`.
- `admin_save_tournament` (§14a.1): once any category has a draw, a change of `sport_id` or `venue_id` → `draw_exists`; a date change leaving a scheduled match outside → `matches_outside_dates`; `active` set false → release blocks of every match not `done`.
- `admin_save_category`: change of `kind` with a draw → `draw_exists`. `admin_delete_category` with a draw → `draw_exists`.

- [ ] **Step 1: Write the failing tests** in `schedule.test.mjs` (venue with two 90-minute padel courts, a published 8-entry knockout):
  - `schedule blocks the court`: `schedule_match` at 10:00 → a `block` booking with the match id; `court_slots` shows it `blocked`; `owner_calendar` slot has `tournament.title`.
  - `slot taken`: an app booking at 10:00 on court 1 → `slot_taken`; off-grid 10:15 → `invalid_argument`; a day outside the dates → `invalid_argument`.
  - `move and clear release`: moving to 11:30 leaves exactly one block; clearing leaves none.
  - `player busy across categories`: a player in two categories at 10:00 on courts 1 and 2 → second gives `player_busy`.
  - `owner cannot cancel`: `owner_cancel_booking` on the block → `tournament_block`.
  - `fill the day`: 4 round-1 matches, 2 courts from 09:00 → 09:00 ×2, 10:30 ×2; the semi-finals land at 12:00 or later; `scheduled = 6` when the semis and final fit, `unscheduled` lists the rest.
  - `fill the day respects players`: a player in two categories never gets overlapping slots.
  - `fill the day gap`: a group of 4 on 2 courts: no entry plays two consecutive slots when a schedule without that exists.
  - `no venue`: a venueless tournament schedules with a place note and makes no booking; a court id → `invalid_argument`.
  - `tournament edits`: venue change with a draw → `draw_exists`; dates moved past a scheduled match → `matches_outside_dates`; `active = false` releases the blocks; category kind change and delete → `draw_exists`.
  - `redo releases blocks`: `redo_draw` leaves no blocks for the category.
  - concurrency (`concurrency.test.mjs`): `fill_day` and an app `hold_slots` on the same slot at once → no overlap, one of them skipped or refused cleanly; two organisers scheduling the same player in two categories at the same time → one gets `player_busy`.
- [ ] **Step 2: Run** `npm test -- schedule`. Expected: FAIL.
- [ ] **Step 3: Write the migration.**
- [ ] **Step 4: Run** `npm test`. Expected: all pass.
- [ ] **Step 5: Commit** `M8a: match schedule and calendar blocks`.

### Task 3: Scores, advancement, standings, withdrawals

**Files:**
- Create: `supabase/migrations/20261128120000_match_scores.sql`, `supabase/tests/match_scores.test.mjs`
- Modify: `supabase/tests/concurrency.test.mjs` (one test)

**Interfaces — consumes:** Tasks 1–2; M7 `app.check_sets`, `app.whole_sets`, `app.score_winner`.

**Interfaces — produces:**
- `app.enter_match_score(p_user uuid, p_match_id uuid, p_outcome text, p_winner text, p_sets jsonb, p_now timestamptz) returns void` — `p_outcome` in `played`, `walkover`, `retired`, `decider`.
- `app.withdraw_entry(p_user uuid, p_registration_id uuid, p_now timestamptz) returns void` and `app.withdraw_entry_service(p_registration_id uuid, p_now timestamptz) returns void` (no organiser check; used by deletion).
- `app.group_standings(p_group_id uuid) returns jsonb` → `[{"registration_id","played","won","drawn","lost","points","sets_for","sets_against","games_for","games_against","place","advancing","withdrawn"}]` in place order.
- `draw_json` gains `groups[].standings`, `"winner"`, `"runner_up"` (registration ids or null), `"finished"`. `tournament_bracket` gains `"my_next_match"` (`match_json` + `category_id`, or null) and `"finished"` (all categories finished).
- Hook for Task 4: `app.after_match_scored(p_match_id uuid, p_previous public.tournament_matches, p_now timestamptz) returns void`, a no-op here, called at the end of every score entry or correction.
- Public: `enter_match_score(p_match_id uuid, p_outcome text, p_winner text default null, p_sets jsonb default null) returns jsonb` (the draw), `withdraw_entry(p_registration_id uuid) returns jsonb` (the draw), `my_tournament_matches() returns jsonb` → `[match_json + {"tournament_id","category_id","title_uz","title_ru","title_en"}]` for the caller's entries, upcoming first.

**Rules to implement**
- Match must be in a published draw, both sides known (`not_found` otherwise). `played`: rated sport → `check_sets`, winner by `score_winner`; other sports → exactly one pair 0–99, winner by the higher number, level = `draw`. A `draw` in a knockout match → `draw_not_allowed`. `decider`: non-rated knockout only, a level single pair, `p_winner` in (a,b). `walkover`: `p_winner` required, sets null. `retired`: `p_winner` required, sets valid but may be unfinished. Sets `status = 'done'`, `scored_by`, `scored_at`; first scored match sets `first_score_at`. A walkover entered before the match's start releases its block.
- **Advancement:** knockout winner → next match side (Task 1 rule); a match whose sides are both known becomes `ready`. A side that will never come (`a_empty`/`b_empty`): one empty and the other known → `done`, outcome `walkover`, winner the known side; both empty → `done`, outcome `none`, winner null, and the next match's side becomes empty. The final's winner/runner-up go into `draw_json`; `category_won` to the winner's players.
- **Groups:** standings per §7.6 and §14a.5 (walkovers count points only; retirements count their score; withdrawn entries are placed last). When every match of every group is `done`, rank qualifiers per §14a.6 (winners first by points per match, set difference per match, game difference per match, seed; then runners-up), place them by the Task 1 seed order into knockout round 1, keeping two entries of one group in opposite halves where possible (swap a lower qualifier with the nearest-ranked one of another group in the other half). `G = 1`, `advance = 1`: the group winner wins the category.
- **Corrections:** a `done` match can be scored again while its dependent match has no score (outcome not in played/walkover/retired/decider) → otherwise `next_match_played`. A knockout correction that changes the winner replaces the side in the next match (and its players are notified with `match_result`). A group correction is refused with `next_match_played` once any knockout match of the category has a non-bye outcome; before that, standings and any already-filled knockout slots are recomputed.
- `match_result` to every player of both sides on each entry or correction.
- **Withdraw:** the category is `locked` (published, or a draft after a redo), else `not_found`. Always under `set_config('actra.draw_override','on', true)`: the registration becomes `removed`, `admin_override = true`. In a draft: the draft is marked outdated, nothing else. In a published draw: `withdrawn_at` set; every unplayed match of the entry: other side known → `walkover` for it (release the block if not started); otherwise the entry's side becomes empty (the empty-side rule above settles it when the other side arrives). Played matches stay. `entry_withdrawn` to the entry's players. Audited.
- `delete_account` (copy from teams.sql): call `withdraw_entry_service` for every live entry where the user is registrant or confirmed partner in a `locked` category, before the existing cancel-registrations step.

- [ ] **Step 1: Write the failing tests** in `match_scores.test.mjs`:
  - `knockout to a winner`: 4-entry padel draw, three `played` scores → `winner`, `runner_up`, `finished`; `category_won` notice; `first_score_at` set.
  - `draw refused in knockout`: padel `[[6,4],[4,6]]` (level on sets and games) → `draw_not_allowed`; football knockout 2–2 → `draw_not_allowed`; `decider` with winner a → done.
  - `football group allows a draw`: 1–1 in a group gives each 1 point.
  - `correction moves the new winner on`: correct a quarter-final after its semi is scheduled → the semi's side changes; correcting after the semi has a score → `next_match_played`.
  - `standings tie-breaks`: three entries on 4 points each: head-to-head decides two-way ties, set difference a three-way tie; a walkover win adds 2 points and no sets.
  - `groups fill the knockout`: 2 groups, advance 2 → semis A1–B2 and B1–A2; 3 groups advance 1 → S=4, the best winner's match has outcome `bye` (not `walkover`) and a group correction is still allowed afterwards.
  - `single group`: G=1 advance 1 → the group winner is `winner`.
  - `bracket with withdrawals completes`: 8 entries; withdraw both sides of quarter-final 1 → it is `none`, semi 1 becomes a walkover for whoever wins QF2; withdraw a semi-finalist before their opponent is known; finish the rest → `finished`, no match `waiting`.
  - `group withdrawal`: an entry with one played match withdraws → its played result stays, the rest are walkovers, it is placed last.
  - `deleted account is withdrawn`: delete a player with a published entry → succeeds; their unplayed match is a walkover; their registration `removed`. Deleting a confirmed partner works the same.
  - `withdraw from a redone draft`: after `redo_draw`, `withdraw_entry` removes the entry and marks the draft outdated; deleting an account with an entry there succeeds.
  - `advancing into a clash is flagged`: a winner placed into a semi that overlaps their match in another category → that semi's `clash` is true.
  - `walkover releases a future block`; `my next match` in `tournament_bracket`; `my_tournament_matches` lists the caller's matches.
  - `organiser plays`: an organiser who is in the match can score it.
  - concurrency: two concurrent `enter_match_score` on one match → both finish without error or one gets a clean error; the next match holds exactly one winner.
- [ ] **Step 2: Run** `npm test -- match_scores`. Expected: FAIL.
- [ ] **Step 3: Write the migration.**
- [ ] **Step 4: Run** `npm test`. Expected: all pass.
- [ ] **Step 5: Commit** `M8a: match scores, advancement, standings and withdrawals`.

### Task 4: Tournament matches move ratings

**Files:**
- Create: `supabase/migrations/20261128130000_tournament_ratings.sql`, `supabase/tests/tournament_ratings.test.mjs`
- Modify: `supabase/tests/concurrency.test.mjs` (one test)

**Interfaces — consumes:** Task 3's `after_match_scored` hook; M7's `apply_result`, `result_unplayable`.

**Interfaces — produces:**
- `match_results.game_id` nullable; `match_results.tournament_match_id uuid references tournament_matches on delete cascade`; check `num_nonnulls(game_id, tournament_match_id) = 1`; unique index on `tournament_match_id where status <> 'void'`.
- `app.result_sport(r public.match_results) returns text` (game's sport, else the tournament's sport).
- `app.reverse_result(p_result_id uuid, p_now timestamptz) returns void` — the subtraction now in `admin_resolve_score`'s void branch, moved here; leaves the result `void`.
- `app.after_match_scored` (replaced): rated sport only. If the match has a non-void result → `reverse_result`. If the new outcome is `played` → insert a result (`entered_by` = scorer, status `pending`, `confirm_deadline = p_now`, sides from the entries' registrant and partner), then `apply_result`.
- `apply_result`, `admin_resolve_score`, the after-game resolver: sport through `result_sport`. `result_note`: for a tournament result `{"tournament_id","category_id","match_id","title_uz","title_ru","title_en","result_id"}`. `result_json` gains `tournament_match_id`.

- [ ] **Step 1: Write the failing tests** in `tournament_ratings.test.mjs`:
  - `played match moves ratings`: padel singles 6–2 6–3 between 2.50 players → 2.64 / 2.36 (M7's numbers), one `rating_events` row each, `rating_updated` with a tournament note.
  - `pairs`: a 2v2 match moves four ratings.
  - `walkover, retired, bye do not move ratings`.
  - `correction reverses once`: correct to the other winner → each player's rating equals the start plus the new change only; one non-void result; correct to a walkover → back to the start.
  - `football moves nothing`.
  - `M7 paths ignore tournament results`: `auto_confirm_scores`, `admin_review`, `my_past_games`, `confirm_score`/`dispute_score` on a tournament result id → no effect or `not_found`; leaderboard shows the new rating.
  - `deleted account keeps others' rating changes`: after a confirmed tournament result, deleting one player leaves the opponent's rating as it is.
  - `game results unchanged`: rerun one M7 scenario (enter, confirm) to show games still score.
  - `concurrent entries apply ratings once` (`concurrency.test.mjs`): two concurrent `enter_match_score` on one padel match → exactly one non-void result and one `rating_events` row per player.
- [ ] **Step 2: Run** `npm test -- tournament_ratings`. Expected: FAIL.
- [ ] **Step 3: Write the migration.**
- [ ] **Step 4: Run** `npm test`. Expected: all pass, including every M7 test file.
- [ ] **Step 5: Commit** `M8a: tournament matches move ratings`.

## Part 2 — app

### Task 5A: Bracket rules, types and the Supabase layer

**Files:**
- Create: `app/lib/domain/brackets.dart`, `app/lib/data/organizer_repository.dart`, `app/lib/data/supabase/supabase_organizer_repository.dart`, `app/test/domain/brackets_test.dart`
- Modify: `app/lib/domain/tournaments.dart` (`TournamentError` values), `data/repositories.dart`, `data/admin_repository.dart`, `data/supabase/mappers.dart`, `supabase_tournament_repository.dart`, `supabase_admin_repository.dart`, `errors.dart`, `state/providers.dart`, four ARB files
- Test: `app/test/data/supabase_mappers_test.dart`

**Interfaces — produces (Dart):**
- `enum DrawFormat { knockout, groups }`, `enum MatchStage { group, knockout }`, `enum MatchStatus { waiting, ready, done }`, `enum MatchOutcome { played, walkover, retired, decider, bye, none }`, `enum Side { a, b, draw }`.
- `class DrawEntry { registrationId, seed, strength, groupId?, withdrawn, List<PlayerRef> players }`; `class TournamentMatch { id, stage, groupId?, round, position, sideA?, sideB?, aEmpty, bEmpty, status, outcome?, winner?, List<List<int>>? sets, courtId?, courtName?, startsAt?, endsAt?, placeNote? }`; `class GroupStanding { registrationId, played, won, drawn, lost, points, setsFor, setsAgainst, gamesFor, gamesAgainst, place, advancing, withdrawn }`; `class DrawGroup { id, label, List<GroupStanding> standings }`; `class CategoryDraw { categoryId, format, groupSize?, advance?, published, outdated, entries, groups, matches, winner?, runnerUp?, finished }`; `class TournamentBracket { bool organizer, List<CategoryDraw> draws, NextMatch? myNextMatch, bool finished, List<CourtRef> courts }`; `class MyMatch` (match + tournament id/title + category id); `class FillResult { int scheduled; List<String> unscheduled }`.
- `class BracketRules` (static, mirrors SQL): `List<int> seedOrder(int size)`, `List<int> groupSizes(int n, int groupSize)`, `List<List<(int, int)>> roundRobin(int n)`, `List<GroupStanding> standings(List<TournamentMatch> groupMatches, Map<String, int> seeds, Set<String> withdrawn)`, `List<String> rankQualifiers(List<DrawGroup> groups, int advance, Map<String, int> seeds)`, `List<String?> placeQualifiers(List<String> ranked, Map<String, String> groupOf, int size)` (bracket slots 1..size, null = bye; keeps one group's entries in opposite halves where possible).
- `TournamentRepository`: `Future<TournamentBracket> bracket(String tournamentId)`, `Future<List<MyMatch>> myMatches()`.
- `abstract class OrganizerRepository`: `organizedTournaments()`, `makeDraw(String categoryId, DrawFormat format, {int? groupSize, int? advance})`, `swapEntries(String categoryId, String registrationA, String registrationB)`, `publish(String categoryId)`, `redo(String categoryId)` (all `Future<CategoryDraw>`), `scheduleMatch(String matchId, {String? courtId, DateTime? startsAt, String? placeNote})` → `Future<TournamentMatch>`, `fillDay(String tournamentId, DateTime day, List<String> courtIds, TimeOfDay from, {List<String>? categoryIds})` → `Future<FillResult>`, `enterScore(String matchId, MatchOutcome outcome, {Side? winner, List<List<int>>? sets})`, `withdraw(String registrationId)` (both `Future<CategoryDraw>`). Failures throw `TournamentException`.
- `OrganizerRepository.entries(String tournamentId)` → `Future<List<AdminRegistration>>` (names and phones).
- `AdminRepository`: `Future<List<PlayerRef>> organizers(String tournamentId)`, `Future<List<PlayerRef>> setOrganizer(String tournamentId, String userId, {required bool add})`.
- Providers: `organizerRepositoryProvider`, `bracketProvider` (`FutureProvider.family<TournamentBracket, String>`), `myMatchesProvider`, `organizedTournamentsProvider`.
- Error strings `errDrawExists` … `errMatchesOutsideDates` for every new `TournamentError`.
- Until Task 5B, `SampleBackend` implements the new methods by throwing `UnimplementedError` (sample mode is not used by Task 5A's tests).

- [ ] **Step 1: Write the failing tests.** `brackets_test.dart`: `seedOrder(8)` → `[1,8,4,5,2,7,3,6]`; `groupSizes(10,3)` → `[4,3,3]`, `(5,4)` → `[5]`, `(7,4)` → `[4,3]`; `roundRobin(4)` has 3 rounds of 2; the Task 3 tie-break case; `rankQualifiers` orders winners before runners-up; `placeQualifiers` for 2 groups × 2 gives slots `[A1, B2, B1, A2]` (A1 and A2 in opposite halves) and for 3 qualifiers in 4 slots one null next to the best. Mappers: `draw_json` with a group draw maps fully; a `tournament_bracket` without the Task 2–3 keys still maps; every new error code maps to its `TournamentError`.
- [ ] **Step 2: Run** `flutter test test/domain/brackets_test.dart test/data/supabase_mappers_test.dart`. Expected: FAIL.
- [ ] **Step 3: Implement**, then `flutter gen-l10n`.
- [ ] **Step 4: Run** `flutter test` and `flutter analyze`. Expected: all pass.
- [ ] **Step 5: Commit** `M8a: bracket rules, types and backend calls`.

### Task 5B: Brackets in the sample backend

**Files:**
- Create: `app/lib/data/sample/sample_brackets.dart`, `app/test/data/sample_brackets_test.dart`
- Modify: `data/sample/sample_repositories.dart`, `data/sample/sample_tournaments.dart`

**Interfaces — consumes:** Task 5A's `BracketRules`, types and interfaces (replaces the `UnimplementedError` stubs).

- Sample rules follow Tasks 1–3 (same errors, same lock, same empty-side, standings and correction rules), built on `BracketRules`. Ratings in sample mode move with the M7 sample rating maths for played padel/tennis matches.
- Sample data: sample tournament `t1` (padel) gets a published 8-entry knockout with the quarter-finals played and semis scheduled on sample courts; the demo player is an organiser of `t1` and plays in one of its matches; one sample tournament keeps no draw. Sample brackets live in the sample backend, not in `seed.sql`.

- [ ] **Step 1: Write the failing tests** in `sample_brackets_test.dart`: make, swap, publish, schedule, `fillDay` (2 courts from 09:00 → four quarter-finals at 09:00 ×2 and 10:30 ×2, the rest reported), score to a winner, correction refused after the next match is scored, withdrawal makes a walkover, `playerBusy` across categories, outdated draft refuses publish.
- [ ] **Step 2: Run** `flutter test test/data/sample_brackets_test.dart`. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `flutter test` and `flutter analyze`. Expected: all pass.
- [ ] **Step 5: Commit** `M8a: brackets in the sample backend`.

### Task 6: Bracket on the tournament page (players)

**Files:**
- Create: `app/lib/features/tournaments/bracket_view.dart`, `group_table.dart`, `next_match_card.dart`, `app/test/features/bracket_view_test.dart`
- Modify: `features/tournaments/tournament_screen.dart`, `my_tournaments_screen.dart`, `features/inbox/inbox_screen.dart` (open the tournament for the new kinds), four ARB files

**Interfaces — consumes:** Task 5A's `bracketProvider`, `myMatchesProvider`, `TournamentBracket`.

- Per category, once published: a "Draw" section with the bracket (rounds side by side in a horizontal scroll; each match card: two entries' names, the score or outcome label, court and time) and, for groups, a table per group (P, W, L, Pts; advancing places marked). Byes are not drawn as matches. Winner and runner-up shown when the final is done; "Finished" on the tournament when every category is.
- "Your next match" card at the top of the tournament page and on My tournaments (opponent, court, time, place note).
- A "My matches" section on My tournaments from `myMatchesProvider`.
- A "Manage" button for organisers (`bracket.organizer`) opening `/tournaments/:id/manage` (Task 7 builds the screen; until then the route shows a placeholder).
- Reload on open, on app resume and by pull-to-refresh, keeping the loaded page on a failed reload (M7 pattern).
- Inbox: the nine new kinds have texts in four languages and open the tournament.

- [ ] **Step 1: Write the failing widget tests:** an 8-draw shows 3 rounds and the score `6–2 6–3`; a bye is not shown; a group table orders by place and marks two advancing; the next-match card shows opponent and court; "Manage" visible only to an organiser; each new notification kind renders a text in `en` and `kk`.
- [ ] **Step 2: Run** `flutter test test/features/bracket_view_test.dart`. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `flutter test` and `flutter analyze`. Expected: all pass.
- [ ] **Step 5: Commit** `M8a: brackets and group tables for players`.

### Task 7: Organisers and the draw manager

**Files:**
- Create: `app/lib/features/organizer/organized_tournaments_screen.dart`, `manager_screen.dart`, `draw_tab.dart`, `app/test/features/organizer_draw_test.dart`
- Modify: `features/admin/tournament_editor_screen.dart` (organisers block: list, add by phone/username with the pair-invite lookup, remove), `features/profile/profile_screen.dart` ("Tournaments I run", shown when the list is not empty), `router.dart` (`/tournaments/:id/manage`, `/organizing`), four ARB files

**Interfaces — consumes:** Task 5A's `OrganizerRepository`, `AdminRepository.organizers/setOrganizer`, `organizedTournamentsProvider`.

- Manager screen: tabs Draw, Schedule, Scores (the last two built in Task 8; placeholders here). Phone-width first.
- Draw tab per category: entry count and an "Entries" list (names, phones, paid) from `OrganizerRepository.entries`; format picker (Knockout / Groups); for groups, group size 3 or 4 and advancing 1 or 2; "Make draw"; the draft preview with tap-two-entries-to-swap; "Out of date — make the draw again" banner when `outdated`; "Publish" (confirm dialog: entries lock and the waitlist closes); "Redo" (confirm dialog) while allowed; every `TournamentException` shown with its string.

- [ ] **Step 1: Write the failing widget tests:** admin adds and removes an organiser on the editor; "Tournaments I run" appears for an organiser and opens the manager; make a groups draw (size 4, advance 2) shows groups A and B; swap two entries; outdated banner blocks publish; publish confirm locks; redo after a score shows `errDrawFinal`.
- [ ] **Step 2: Run** `flutter test test/features/organizer_draw_test.dart`. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `flutter test` and `flutter analyze`. Expected: all pass.
- [ ] **Step 5: Commit** `M8a: organisers and the draw manager`.

### Task 8: Schedule and scores in the manager; owner calendar

**Files:**
- Create: `app/lib/features/organizer/schedule_tab.dart`, `scores_tab.dart`, `score_sheet.dart`, `app/test/features/organizer_matches_test.dart`
- Modify: `features/organizer/manager_screen.dart`, the owner calendar screen and its slot model/mapper (`tournament` label on blocks; `tournamentBlock` error text on cancel), four ARB files

**Interfaces — consumes:** Task 5A's `OrganizerRepository.scheduleMatch/fillDay/enterScore/withdraw`, `TournamentBracket.courts`.

- Schedule tab: day picker within the tournament dates; a column per court with placed matches; tap a match → sheet with court, start (court slot grid) or, without a venue, time + place note; "Clear time"; "Fill the day" sheet (courts, start time, categories) reporting what did not fit.
- Matches with `clash` show a warning on the Schedule and Scores tabs.
- Scores tab: matches in play order (scheduled time, then round); tap → score sheet: rated sports enter sets like M7's score sheet (reuse its set input widget); other sports one score per side; level knockout score asks for the decider winner; "Walkover" and "Retired" with a winner pick; corrections reopen the sheet; "Withdraw entry" from an entry's menu with a confirm dialog.
- Owner calendar: tournament blocks read "Tournament: <title>"; cancelling one shows `errTournamentBlock`.

- [ ] **Step 1: Write the failing widget tests:** schedule a match on court 1 at 10:00; `playerBusy` shown; fill the day reports unscheduled matches; enter `6–2 6–3` and the bracket advances; football level score asks for the decider; walkover with winner; correction refused shows `errNextMatchPlayed`; withdraw makes the opponent's match a walkover; owner calendar shows the tournament label and refuses cancel.
- [ ] **Step 2: Run** `flutter test test/features/organizer_matches_test.dart`. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `flutter test` and `flutter analyze`. Expected: all pass.
- [ ] **Step 5: Commit** `M8a: schedule and scores in the tournament manager`.

## Wrap-up

### Task 9: Live checks, review, walkthrough, handover

**Files:**
- Create: `supabase/scripts/e2e-tournaments.mjs`, `supabase/scripts/e2e-brackets.mjs`
- Modify: `supabase/README.md` (the new scripts), this plan's Status section, `docs/superpowers/plans/2026-11-22-actra-roadmap.md` (M8 row note), `docs/superpowers/plans/2026-11-27-actra-remaining-work.md` (tick M8a)

- [ ] **Step 1: Write `e2e-tournaments.mjs`** in the style of `e2e-community.mjs` (`e2e-lib.mjs`, `step`, `ok`, `refused`, cleanup in `finally`): an admin creates a throw-away tournament and pairs category; players register, a partner accepts, the cap fills, a waitlisted player gets an offer after a cancel and claims it; the admin marks paid; cleanup removes everything.
- [ ] **Step 2: Write `e2e-brackets.mjs`:** throw-away venue with two padel courts and a throw-away tournament; the admin names a throw-away organiser; four players register; the organiser makes and publishes a knockout draw, fills the day, enters three scores; assert the winner, the calendar blocks, ratings moved for the played matches, the notices; a withdrawal on a second category makes a walkover; cleanup removes results, rating rows, matches, blocks, the venue, audit rows and the accounts; it notifies no real owner.
- [ ] **Step 3: Whole-branch review** by fresh reviewers in two halves (database, app) against the design and this plan, Review Focus first; fix findings; re-run `npm test`, `flutter test`, `flutter analyze`.
- [ ] **Step 4: Browser walkthrough in sample mode** with a preview entry `actra-m8` (port 5681, `app/tool/run_web_sample.cmd 5681`; do not commit `launch.json`): open `t1`'s bracket; as organiser make a groups draw on another category, publish, fill the day, enter scores to a winner, correct one, withdraw one; owner calendar label. Repeat the main path in Russian and Kazakh at phone width for overflow. Screenshots in the report.
- [ ] **Step 5: With the founder's go-ahead only:** `node scripts/deploy.mjs migrations` (four files `20261128*`), then `node scripts/e2e-brackets.mjs`, `node scripts/e2e-tournaments.mjs`, `node scripts/e2e-ratings.mjs`, `node scripts/e2e-community.mjs`. Do not run `scripts/e2e.mjs` (it notifies real owners).
- [ ] **Step 6: Update this plan's Status, the roadmap and the remaining-work list; commit** `Plan: M8a status`. Merge and push only when the founder asks. A fresh app build goes out with the deploy.

---

## Status

**2026-11-28: built and reviewed on branch `m8-brackets`; NOT deployed, NOT merged, NOT pushed.** Tasks 0–8 and Task 9 Steps 1–4 and 6 are done. Step 5 (deploy and live checks) waits for the founder's go-ahead.

- **How it was built:** subagent-driven. Every task had its own implementer and a separate reviewer, with fix rounds on Tasks 1, 2 (controller rulings), 3, 6 and 7. The whole branch was then reviewed in two halves (database, app) by senior reviewers: no critical findings, 6 important ones (entry lock invisible to players after a redo; walkover by withdrawal not notified; players placed into an already-scheduled match not told the time; a started slot could not be scheduled; a page reopened after a failed account switch could show the previous account's data, M7 screens included; app driving the lock from the wrong place), all fixed in one fix wave with a few small items (identical re-entry is a no-op, deleted accounts left out of draws, privilege test, safer live-check cleanup, organiser error text, load-error retries) and re-reviewed clean.
- **Tests:** supabase `npm test` 534 pass (527 before the fix wave, 463 before M8a); app `flutter test` 850 pass (712 before M8a); `flutter analyze` clean. On this PC run backend tests as `ACTRA_TEST_PG_PORT=54339 npm test`: a leftover Postgres holds the default port and plain `npm test` then exits 0 having run nothing.
- **Browser walkthrough (sample mode, 400 px, English):** tournament t1 shows the next-match card, Manage and the bracket; the locked Men's pairs entry offers no Cancel; in Manage → Scores a semi-final score (6–2) was entered and the winner moved into the final; the Schedule tab shows both courts and the unscheduled final. Russian and Kazakh at phone width are covered by widget tests, not re-walked. Sample-only oddity: sample categories show summary counts ("9 of 12 filled") with no registration rows, so the organiser's Draw tab says "No entries" for them.
- **Deploy (founder go-ahead only):** `node scripts/deploy.mjs migrations` (four files `20261128*`), then at a quiet hour `node scripts/e2e-brackets.mjs`, `node scripts/e2e-tournaments.mjs`, `node scripts/e2e-ratings.mjs`, `node scripts/e2e-community.mjs`. The two new scripts have never run live. While a check runs its throw-away tournament is listed in Tashkent for a few seconds. Then a fresh app build.
- **Known limits for organisers:** an automatic walkover blocks correcting the match that fed it (and redo is closed after the first score); head-to-head is a single pass, not the recursive ITF rule; a winner advancing into a slot that clashes with their other category is flagged, not moved; a hidden tournament cannot be managed until it is shown again.
- **Deferred small items:** listed in the build ledger `.superpowers/sdd/…/progress.md` (git-ignored) and in the final review reports; none block deploy.
