# Actra M8a — Tournament Brackets and Results: Design

**Date:** 2026-11-27
**Status:** draft for founder approval (read by an independent reviewer; its gaps are settled in §14a)
**Spec:** [docs/actra-product-spec.md](../../actra-product-spec.md) §10.2 (brackets and results), §10.1 (registration), §11 (owner calendar)
**Roadmap row:** M8 in [2026-11-22-actra-roadmap.md](../plans/2026-11-22-actra-roadmap.md), the "tournament brackets and results" half. Online payments are M8b, a separate design.

In this document, "**Founder**" marks a decision the founder made; "**Call**" marks a choice made during design that the founder can change; everything else comes from the spec.

---

## 1. Intent and why

Today a tournament in Actra ends at registration: players sign up, the admin marks them paid, and then everything that matters on the day (who plays whom, on which court, at what time, who won) happens on paper or in a chat. Players have no reason to open the app during the event, venues get no calendar protection for the courts the tournament uses, and padel/tennis tournament results do not count toward the ratings M7 introduced.

M8a carries a tournament through the day: a draw per category, matches on the venue's courts (blocked in the owner calendar), live scores entered courtside by the people running the event, a live bracket players can follow, and ratings that move with tournament results.

## 2. Goals, non-goals, anti-goals

**Goals**
1. An admin can name one or more organisers per tournament; an organiser runs that tournament without admin rights.
2. The organiser makes a draw per category in two formats: knockout, or groups then knockout.
3. The organiser places matches on courts and times; those slots are blocked in the owner calendar.
4. The organiser enters scores courtside; the bracket updates for everyone immediately and winners advance automatically.
5. Padel and tennis tournament matches move ratings through the M7 rating engine.
6. Players see the bracket, group tables, their next match, and are told when the draw, a match time or a result changes.
7. Each category ends with a winner and runner-up shown on the tournament page.

**Non-goals**
- Online entry-fee payment (M8b). Payment stays the admin's "Paid" mark.
- Third-place matches, consolation brackets, round-robin-only formats (Americano, Mexicano), double elimination.
- Live point-by-point or game-by-game scoring; only the final set scores of a match.
- Players entering or confirming tournament scores. **Founder (2026-11-27):** organisers enter results (option B).
- Rating bands on tournament categories (categories keep the 1–5 level band from M5/M7).
- Tournament matches appearing in "Past games" (it is built on games; see §8.4).
- Push notifications (still waits for a Firebase project; the in-app inbox carries everything).

**Anti-goals** (failures even if it works)
- A score changes ratings twice, or a corrected or withdrawn score leaves ratings wrong.
- A bracket gets stuck: a match whose players are known can always be played, walked over or corrected.
- A tournament block silently overlaps a paying booking, or a cancelled match leaves a court blocked.
- An organiser can act on any tournament other than the ones they were named for.
- Old app builds (M7 APK) break: every JSON change is additive.

## 3. Constraints (from the code as it is)

- **Only admins manage tournaments today** (`app.require_admin` in `20261125110000_admin_tournaments.sql`). There is no organiser role.
- **A tournament's venue is optional** (`tournaments.venue_id` nullable). Without a venue there are no courts to schedule on.
- **Courts have a fixed slot length** of 60, 90 or 120 minutes (`courts.slot_minutes`); calendar blocks are `bookings` rows with `source = 'block'`, protected by the `bookings_no_overlap` constraint.
- **Entries** are `tournament_registrations` rows; a live entry in the draw sense is `status = 'registered'` (a pair counts once, registrant + confirmed partner).
- **M7 results are tied to games:** `match_results.game_id` is `not null unique`; several functions find the sport through `games` (`apply_result`, `admin_resolve_score`, `admin_review`, `result_note`, the after-game admin resolver, `auto_confirm_scores`).
- **Rating maths** (`app.apply_result`) needs exactly 2 or 4 players with equal sides, valid sets (1–5 sets, no 0–0), and a winner of `a`, `b` or `draw`. Voiding a confirmed result subtracts each player's stored change (it does not recompute later results); M8a reuses that behaviour as it is.
- **Live data:** the hosted project holds 0 match results today, so changing `match_results` columns is safe.
- **Migrations:** every `create or replace` must start from the function's latest definition across all migrations (`delete_account` was last redefined in `20261127130000_teams.sql`, `game_json` in the same file, `complete_games` in `20261127120000_after_game.sql`).
- All UI strings in four ARB files (uz, ru, kk, en); a test enforces it.

## 4. Approaches

Three ways were considered for where a tournament match and its score live:

1. **Own match tables, scores shared with M7 for ratings.** Brackets, groups and matches get new tables; the score is stored on the match; for a rated sport a scored match also writes an M7 `match_results` row (with a new `tournament_match_id` instead of `game_id`) so the rating engine and leaderboards work unchanged. *Trade-off:* every reader of `match_results` has to tolerate a result without a game (listed in §8).
2. **Every match is a hidden game.** Reuses the most code (score entry, results, notifications), but games carry joining, visibility, reminders, reliability and completion rules that would all need exceptions. *Trade-off:* high risk of side effects across M4–M7.
3. **Fully separate scores** with their own call into the rating maths. *Trade-off:* duplicates scoring rules and leaves two kinds of results for leaderboards and history.

**Founder (2026-11-27): option 1.**

## 5. Organisers

- A new table `tournament_organizers (tournament_id, user_id, added_by, added_at)`.
- Admins add or remove organisers on the tournament editor (pick an account by phone or username, the same lookup the pair invite uses).
- An organiser can, for that tournament only: open the tournament manager (draw, schedule, scores) and see the entry list with names and phones. They cannot edit the tournament's details, categories, fees, or mark payments; those stay admin-only (M5 screens unchanged).
- Admins can do everything an organiser can, on every tournament.
- A new check `app.require_organizer(p_user, p_tournament_id)` passes for admins and named organisers, else raises `not_allowed`.
- Every organiser action is written to the audit log (`app.audit`), like admin actions.
- The person is told when they are added or removed (inbox, category `tournaments`).
- An organiser sees "Tournaments I run" in their profile menu, leading to the manager. **Call.**

## 6. Draws

### 6.1 Formats

Per category the organiser picks one format:

- **Knockout.** Single elimination. The bracket size is the next power of two at or above the number of entries; the top seeds get the byes. Minimum 2 entries.
- **Groups then knockout.** Entries are split into groups; each group plays a round robin; the top 1 or 2 of each group go into a knockout. The organiser picks the group size (3 or 4; groups differ by at most one entry) and how many advance (1 or 2). Minimum 3 entries. **Call:** group sizes 3–4 and 1–2 advancing cover the common local formats; larger groups make match counts unmanageable in one day.

### 6.2 Who is in the draw

- Entries with `status = 'registered'` at the moment the draw is made. Unpaid entries are included (payment is still the admin's business until M8b). **Call.**
- Waitlisted, offered, pending-partner and every other status are left out.

### 6.3 Seeding

- Each entry's strength: for a rated sport, the player's current rating (pairs: the average of the two); for other sports, the player's level 1–5 (pairs: average). Entries without a rating or level sort last. Ties are broken randomly.
- **Knockout:** standard seeded placement (seed 1 and 2 in opposite halves, 3–4 in the remaining quarters, and so on); byes go to the top seeds.
- **Groups:** snake seeding (group A gets seed 1, B seed 2, …, then back the other way). In the knockout after groups, group winners are placed apart and two players from the same group meet as late as possible. **Call:** standard practice.
- The organiser can swap any two entries (in the bracket or between groups) while the draw is a draft.

### 6.4 Draft, publish, redo

- A draw starts as a **draft**, visible only to organisers and admins. The organiser can regenerate it or swap entries.
- **Publishing** shows it to everyone and notifies every player in the category.
- **Entries lock at publish:** after publishing, the category accepts no new registrations, waitlist offers stop, and the M5 cancel/remove paths are refused with `draw_published` — except the organiser's own "withdraw" (§7.5). Admins can still mark payment. **Call:** a published bracket must not change under players' feet; a late withdrawal becomes a walkover, which is how real events handle it.
- **Redo:** a published draw can be thrown away and redone until the first score in that category is entered. Redoing releases every calendar block of that category's matches and notifies the players. After the first score the draw is final.

## 7. Matches

### 7.1 What a match is

A row in `tournament_matches`: category, stage (group or knockout), group (for group matches), round and position (for knockout), side A entry, side B entry (either may still be unknown, "winner of match X"), court and start time (optional), state, score.

States: `waiting` (a side not known yet) → `ready` (both sides known) → `done`. A knockout match with a bye on one side is `done` at once as a bye and advances the other entry; it is never shown as a match to play.

### 7.2 Scheduling

- Each match can get a court of the tournament's venue and a start time. A match takes **one court slot** of that court (the court's `slot_minutes`). **Call:** whole slots keep the calendar consistent; an organiser who needs more time can schedule the next match a slot later.
- Scheduling a match creates a calendar block on that court for that slot (`bookings`, `source = 'block'`, a new link column `tournament_match_id`, reason "Tournament: <title>"). It goes through a new `app.organizer_schedule_match` that checks the organiser, the court belongs to the tournament's venue, the time is within the court's working hours and on the tournament's dates, and that the slot is free. A clash with an existing booking or block returns `slot_taken` (never a raw constraint error).
- **"Fill the day":** for a chosen day, the organiser picks courts and a start time; the server lays the unscheduled `ready` and `waiting` matches into free slots in order (group matches round by round, then knockout rounds in order), never putting one entry in two overlapping matches, and leaving a gap of at least one slot between an entry's group matches when possible. It reports which matches did not fit. **Call.**
- Moving a match moves its block (old block released, new one created, in one transaction). Clearing a match's time releases its block.
- When the match is done, its block stays as it is (the court was used); a walkover done before the slot starts releases the block. **Call.**
- **Owners and tournament blocks:** the owner sees tournament blocks in the calendar marked "Tournament" with the title; the owner cannot cancel them (the M3 owner-cancel path refuses blocks that belong to a match with `tournament_block`). Only the organiser moves or clears them. **Call:** an owner cancelling one would silently break the schedule; the venue agreed to host the event.
- **Tournament without a venue:** matches get a start time and a free-text place note (up to 100 characters); no blocks.
- Players in the match are notified when a time is set or changed.

### 7.3 Scores

- The organiser enters the set scores (the M7 rules: 1–5 sets, whole numbers 0–30, no 0–0) and the match is `done`. A draw is refused in knockout matches (`draw_not_allowed`); a group match may end in a draw only for sports whose scores allow it (in practice a tie in games). **Call:** padel and tennis can't draw; leaving it possible for other sports in groups costs nothing.
- **The organiser's score is final.** There is no confirmation or dispute by players.
- The winner of a knockout match moves into the next match at once; a final's winner is the category winner.
- When every match of a group is done, the group's standings are final and its advancing entries move into the knockout.
- **Other outcomes:** walkover (one side did not show) and retired (one side stopped; the organiser enters the score so far). Both name the winner.

### 7.4 Corrections

- The organiser can correct a score (or change the outcome) **until the next match that depends on it has a score**. Correcting a knockout result that changes the winner moves the new winner into the next match. Correcting a group match recomputes the group; if that changes who advances, the knockout entries are replaced only while the affected knockout matches have no score, else the correction is refused (`next_match_played`).
- A correction on a rated sport withdraws the old rating change and applies the new one (§9).

### 7.5 Withdrawals after publish

- The organiser can withdraw an entry from a published draw (injury, no-show for the day). Every remaining unplayed match of that entry becomes a walkover for the opponent; matches already played stay. The registration becomes `removed` with `admin_override` noted in the audit log.
- A player whose account is deleted is withdrawn the same way automatically (part of `app.delete_account`); their played matches keep their scores, but the ratings part follows M7's rule (a result losing a player is voided, §9.3).

### 7.6 Group standings

Points: win 2, draw 1, loss 0, walkover win 2 (the walkover loser 0). Order: points; then head-to-head between the tied entries; then set difference; then game difference; then the seed. **Call:** common tennis/padel convention, deterministic.

## 8. Shared results with M7 (option 1 in detail)

### 8.1 Where the score lives

The score (sets, winner, outcome: played / walkover / retired / bye) lives on `tournament_matches`. That covers every sport, walkovers and byes, which M7's `match_results` cannot hold (it requires non-empty sets and is only for rated sports).

### 8.2 The rating side

For a **rated sport** (padel, tennis), a match that is **played** (not walkover, not bye, not retired) writes an M7 result:

- `match_results.game_id` becomes nullable, and a new column `tournament_match_id` (unique, references `tournament_matches`) is added, with a check that exactly one of the two is set.
- The row is inserted with the organiser as `entered_by`, status `pending`, `confirm_deadline` = the entry time, and `app.apply_result` is called at once, which moves ratings and marks it `confirmed`. It is never pending for longer than that transaction, so player confirm/dispute, auto-confirm and no-show flags never reach it.
- **Call:** retired matches do not move ratings (an injury should not cost a player rating).

### 8.3 Where M7 code reads results (each one checked)

| Reader | What changes |
|---|---|
| `app.apply_result` | Find the sport through a new `app.result_sport(result)` (game's sport, or the tournament's sport). |
| `app.admin_resolve_score` and the after-game admin resolver | Same sport lookup. They can only reach disputed/flagged results, which tournament results never are; kept correct anyway. |
| `app.result_note` | Tournament results get a note naming the tournament and category instead of a game, so `rating_updated` notices still open something sensible (the tournament page). |
| `app.result_json` | Unchanged fields; adds `tournament_match_id` (additive). |
| `app.auto_confirm_scores`, `confirm_score`, `dispute_score` | Inner joins to games / lookups by game already skip tournament results; they are never pending. No change beyond a test. |
| `app.admin_review` | Its inner join to games skips tournament results; they are never disputed. No change beyond a test. |
| No-show reports (after-game) | Per game only; never touch tournament results. |
| `app.game_json`, `my_past_games`, game-detail results | Look up by `game_id`; unaffected. |
| Leaderboard | Reads `player_ratings`; tournament rating changes show up there automatically. |
| `app.delete_account` | Already voids pending results of the deleted player and deletes their `rating_events`; it also withdraws them from published draws (§7.5). |

### 8.4 Past games

"Past games" lists games the player took part in; tournament matches do not appear there. A player's tournament results are seen on the tournament page and in a new "My matches" section of "My tournaments". **Call.**

## 9. Ratings in detail

1. A played match in a rated sport writes a result and moves ratings at once (§8.2), with `rating_updated` notices to the players.
2. A **correction** withdraws the old result (subtract each player's stored change, delete its rating events, mark it void, exactly as M7's admin void does; the subtraction is moved into a shared function `app.reverse_result` used by both) and, if the new outcome is a played match, writes a new result and applies it.
3. A result that cannot be applied (a player's account was deleted, M7's `result_unplayable`) becomes void, as in M7; the bracket keeps the score.
4. Ratings use the same formula and constants as M7; tournament matches count toward `rated_games`.

## 10. What players see

- **Tournament page:** per category, a "Draw" section once published: a bracket view (rounds side by side, scroll sideways; each match shows the two entries, the score, court and time) and, for group formats, group tables (played, won, lost, points) with the advancing places marked. Live: the page reloads on opening, on return to the app and by pull-to-refresh (as M7 screens do).
- **"Your next match" card** at the top of the tournament page and in "My tournaments": opponent, court, time.
- **Winner and runner-up** shown on the category once its final is done; the tournament shows "Finished" when every category is done.
- **Notifications (inbox, category `tournaments`):** draw published; your match time set or changed; your match result; you were withdrawn; you won the category. Muting follows the existing category setting.

## 11. What organisers see

A "Manage" entry on the tournament page (organisers and admins only) opens the **tournament manager**:

- Per category: format picker, "Make draw", swap entries, publish, redo.
- **Schedule:** a day view per court with the matches placed; tap a match to set or move its court and time; "Fill the day".
- **Scores:** a list of matches in play order; tap to enter sets, or mark walkover / retired; correct a score.
- **Withdraw an entry.**
- Phone-width first (used courtside), works on the web for admins.

## 12. Data (summary for the builder)

New tables: `tournament_organizers`, `tournament_draws` (one per category: format, group size, advancing count, status draft/published, published_at), `tournament_groups`, `tournament_group_entries`, `tournament_matches`. New columns: `match_results.tournament_match_id` (+ nullable `game_id`, one-of check), `bookings.tournament_match_id`. All new tables closed to the API roles; reads and writes through `app.*` functions with `public` wrappers, like M5/M7.

One migration, `20261128100000_brackets.sql`; it is additive apart from the `match_results.game_id` change (safe: 0 live rows).

## 13. Testing and release

- Backend tests (embedded Postgres, `npm test`): draw sizes 2–64, byes, seeding order, snake groups, standings tie-breaks, advance and correction rules, schedule clashes and fill-the-day, block release on move/redo/walkover, owner cannot cancel a tournament block, organiser scope, ratings applied once and reversed on correction, deleted account mid-tournament, every M7 reader in §8.3.
- App tests for the bracket and group views, manager flows, in four languages.
- A live check script `e2e-brackets.mjs` (throw-away venue, accounts and tournament; cleans up), plus the missing `e2e-tournaments.mjs` for M5 registration.
- Deploy with `node scripts/deploy.mjs migrations`; old APKs keep working (additive JSON). A fresh app build after deploy.

## 14. Left to the builder

- Exact JSON shapes, function names beyond those named here, and screen layouts within the existing design system.
- The bracket drawing widget (custom, no new dependency unless a small, maintained package clearly fits).
- How "fill the day" breaks ties between equally good slots.

## 14a. Rules settled after the builder review

These close the gaps an independent reviewer found; where they touch an earlier section, this section wins.

1. **Admin edits after a draw exists.** Once any category of a tournament has a draw (draft or published), `admin_save_tournament` refuses a change of sport or venue (`draw_exists`), and refuses a date change that would leave a scheduled match outside the new dates. Hiding a tournament (`active = false`) releases every calendar block of its unplayed matches. `admin_save_category` refuses a change of kind and `admin_delete_category` refuses deletion while that category has a draw; `admin_move_registration` and `admin_add_registration` are refused after publish and mark a draft out of date (rule 7). **Call.**
2. **Clashes are per player, across all categories of the tournament.** A manual schedule is refused with `player_busy` when any player of either entry is in another match in an overlapping slot. "Fill the day" covers the categories the organiser ticks (default: all) and interleaves them: group rounds of every category first, round by round, then knockout rounds in order. **Call.**
3. **Withdrawals that the walkover rule does not cover.** Both sides of a knockout match withdrawn: the match is done with no winner, and the next match is a walkover for whoever reaches it. A withdrawn entry in a group: its played matches still count for its opponents, its unplayed ones are walkovers, and it is placed last in the group (it never advances). A withdrawn entry already placed in a later knockout match: that match becomes a walkover for whoever reaches the other side. **Call.**
4. **Scores by sport.** Rated sports (padel, tennis) use M7 sets. Every other sport uses a single score per side (whole numbers 0–99, e.g. goals), stored as one "set" on the tournament match; a draw is allowed in group matches; in a knockout match a level score needs the organiser to pick the winner (penalties, a deciding game) and the match records it as "won on decider". No new sport column. **Call.**
5. **Walkovers and retirements in group tie-breaks.** A walkover counts for points only; it is left out of set and game differences. A retirement counts the score as entered. **Call.**
6. **Ranking group finishers for the knockout.** All group winners come first, ordered by points per match, then set difference per match, then game difference per match, then seed; then all runners-up the same way. Byes go to the best-ranked; two entries from the same group are kept in opposite halves where possible. **Call.**
7. **Entries changing around the draft.** If a registration changes after a draft was made (new, cancelled, moved), the draft is marked out of date and publishing is refused (`draw_outdated`) until the organiser makes it again. At publish, open waitlist offers lapse and the waitlist closes, with a notice to those players. A redo keeps the category locked; it redraws from the entries still registered (withdrawn entries stay out). **Call.**
8. **Organisers who play.** **Founder (2026-11-27):** an organiser who plays in a match can enter and correct that match's score like any other; no extra check. (Every entry is in the audit log, as for all organiser actions.)
9. **Account deletion.** `app.delete_account` withdraws the player from published draws (§7.5) before its existing cancel-registrations step, which would otherwise be refused with `draw_published`.

## 15. Calls made during design (for the founder to check)

1. Organisers can run the event but not change tournament details, fees or payments (§5).
2. Unpaid registered entries are included in the draw (§6.2).
3. Entries lock when the draw is published; later withdrawals become walkovers (§6.4, §7.5).
4. A match takes exactly one court slot (§7.2).
5. Owners cannot cancel tournament blocks (§7.2).
6. Retired matches do not move ratings; walkovers and byes never do (§8.2).
7. Group points 2/1/0 with head-to-head, then sets, then games (§7.6).
8. Tournament matches are not in "Past games"; they show under "My tournaments" (§8.4).
