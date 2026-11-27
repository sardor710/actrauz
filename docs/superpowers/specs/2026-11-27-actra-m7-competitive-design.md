# Actra M7 — Competitive Layer: Design

**Date:** 2026-11-27
**Status:** draft for founder approval
**Spec:** [docs/actra-product-spec.md](../../actra-product-spec.md) §7.1, §7.2, §7.7, §8, §9.1, §9.3, §12.7, §13
**Roadmap row:** M7 in [2026-11-22-actra-roadmap.md](../plans/2026-11-22-actra-roadmap.md): "Padel and tennis 1.0–7.0 ratings, score entry and confirmation, leaderboards, teams, sportsmanship. Done when ratings move after confirmed results."

In this document, "**Founder**" marks a decision the founder made; "**Call**" marks a choice made during design that the founder can change; everything else comes from the spec.

---

## 1. Intent and why

Actra's promise to players is "find people to play with at the right level". Today that promise is empty for padel and tennis: the level is a number from 1 to 5 the player picks, nothing checks it, and in the live app there is not even a screen to pick it (everyone counts as level 1). The spec names this as a failure condition: "Skill levels are meaningless and matchmaking feels unfair."

M7 makes levels earned for padel and tennis (a 1.0–7.0 rating that moves with real results), gives players a reason to come back after a game (score, rating change, leaderboard position), lets players tell each other apart on behaviour and not only skill (sportsmanship, no-show reports), and turns the sample "Teams" row on the Social tab into real standing groups.

## 2. Goals, non-goals, anti-goals

**Goals**
1. A padel or tennis player has a rating 1.0–7.0 that starts from a questionnaire and moves after every confirmed score.
2. The host can enter a score in under a minute; the other players confirm or dispute with one tap.
3. A leaderboard per sport and city.
4. After any game, participants can give a thumbs up or down, say who did not show up, and report abuse.
5. Players can pick the sports they play and their level (the missing §7.1 step), because ratings and level ranges are meaningless without it.
6. Real teams: create, join, invite, team games shown to members first.
7. Admins can resolve disputed scores and read abuse reports without engineering help.

**Non-goals**
- Tournament results feeding ratings, and rating bands on tournament categories (both arrive with brackets in M8). Category eligibility keeps the 1–5 band, which for padel and tennis is now derived from the rating (§5.3).
- A "friendly game" switch. **Founder (2026-11-27):** every padel or tennis game can be scored; entering a score is optional and any confirmed score moves ratings.
- Suspending or banning users (spec §12.7). It is not in the M7 row; reports are read and closed by an admin, nothing is automatic.
- Team logo upload. The app has no photo upload at all yet; teams get initials on a colour.
- Team chat, team-vs-team matches, team rankings.
- Push notifications (still waits for a Firebase project).

**Anti-goals** (failures even if it works)
- A player can set or inflate their own rating by any route other than playing.
- One angry opponent can damage someone: a single thumbs-down or a single no-show report must not visibly brand or penalise a player.
- A result changes ratings twice, or a corrected or voided result leaves ratings wrong.
- The app built before M7 crashes or locks players out after the M7 backend is deployed.
- Mixed-language screens: every new string exists in uz, ru, kk and en.

## 3. Constraints

- The database is live. Migrations are additive and deployed with `node scripts/deploy.mjs migrations`, never `db`.
- Builds made before M7 keep calling the backend: no existing function loses or renames a parameter or an output key, and no existing key gets a value an old build cannot parse (in particular `games.visibility` stays `public` / `invite_only`, and `min_level` / `max_level` stay whole numbers 1–5).
- Four ARB files with a parity test; admin-entered text has four language fields.
- Every feature works in sample mode too (the app runs without a backend for tests and previews), following the existing split: repository interface, sample implementation, Supabase implementation.
- Rules live in the database, as in M2–M6: SQL functions under `app.` taking the acting user and a clock, thin `public.` wrappers for the app, tables closed to clients unless a policy says otherwise.
- `app.delete_account` must cover every new table.
- The GitHub repo is public: no secrets committed.
- Tests: `npm test` in `supabase/` and `flutter test` in `app/` pass at the end of every task.

## 4. Approaches considered

**A. Keep 1–5 levels and let results nudge them.** Cheapest: no new scale, results move a player up or down a whole level now and then. Rejected: five steps are too coarse to show movement after a game, and the founder already chose the 1.0–7.0 model (spec decision log).

**B. Ratings computed in the app, stored in the player's own row.** Little backend work. Rejected: the player's level row is writable by the player today, so anyone could set their own rating; and old builds would not compute it.

**C. Ratings as a server-only ledger (chosen).** A table of rating events that only database functions write, one row per player per confirmed result, with the current rating kept beside it. Scores, confirmations and the rating maths all run in SQL functions, the same way bookings, reliability and tournaments already work. The 1–5 level for padel and tennis becomes a band derived from the rating, so every existing level check (joining games, Find players, tournament eligibility) keeps working without being rewritten, and old builds keep seeing whole numbers.

C costs the most backend work but is the only one that satisfies the first anti-goal, and it follows the pattern the codebase already uses for reliability.

**Order of work (Call):** one plan in three parts, as M4 was: **7a** sports and ratings, scores, leaderboard; **7b** after-game votes, no-show reports, abuse reports, admin review; **7c** teams. 7a goes first because the roadmap's "done when" is about ratings. Each part ends shippable.

## 5. Part 7a — sports, ratings, scores, leaderboard

### 5.1 My sports (the missing §7.1 step)

- A "My sports" screen reached from the profile, and offered once after first sign-in (skippable; **Call**: it does not block the app, because a new player should reach a venue or game quickly).
- The player ticks the sports they play. For a simple sport they pick a level 1–5 and can change it any time (spec §8.1). For padel and tennis they answer the questionnaire (§5.2).
- Removing a sport removes its level; a rating that has confirmed results behind it is kept and comes back if the sport is added again.
- The profile and other players' profiles show, per sport, the level or the rating with its "provisional" label and rated-games count.

### 5.2 Starting rating

- A questionnaire per rated sport with five questions: years played, how often, competition experience, and two skill questions specific to the sport. The answers are sent to the server, which computes the rating; the app never sends a rating.
- **Call:** the questionnaire can place a player between 1.0 and 5.0, never higher. The top of the scale has to be earned.
- **Call:** the questionnaire can be retaken until the player's first confirmed result in that sport, not after.
- A player who already has a 1–5 level in padel or tennis when M7 is deployed starts at that level plus 0.5 (level 3 → 3.5), provisional, and may still take the questionnaire once.
- A padel or tennis player with no rating yet (never answered) counts as 1.0 for level checks and is asked to answer before joining a rated-sport game with a level range.
- The question texts and the scoring table are left to the builder, in all four languages, modelled on the Playtomic-style self-assessment the spec refers to.

### 5.3 Rating and level together

- The rating is stored with two decimals and shown with two (3.47), so a player sees it move after one game. **Call.**
- For padel and tennis the 1–5 level becomes the whole part of the rating, capped at 5 (2.00–2.99 → 2, 5.00–7.00 → 5). The server keeps it in step with the rating and the player can no longer set it. A build made before M7 that tries to set it must not fail: for a player with no rating, the chosen level seeds the rating as in §5.2; otherwise the write is ignored.
- Games and game requests in padel and tennis get a rating range in half steps (for example 3.0–4.5) next to the existing whole-number range. The new app shows and edits the rating range; the whole-number range is filled from it for old builds, and a range sent by an old build is converted (2–4 → 2.0–4.99).
- Joining follows today's rule with the rating in place of the level: inside the range joins with one tap, outside sends a join request.
- Find players filters padel and tennis by rating range.

### 5.4 Entering a score

- Scoring applies to a game in a rated sport (the admin's "Rating 1.0–7.0" switch on the sport), that was not cancelled, once its end time has passed, for up to 7 days after it. **Call** on the 7 days.
- The host enters the result: who played on each side (1 against 1, or 2 against 2, chosen from the game's participants; the host must be one of them) and the games won per set, for 1 to 5 sets (6–4, 3–6, 7–6).
- **Call:** if the host has not entered a score 24 hours after the end, any participant may. Otherwise one forgetful host loses everyone's result.
- The side with more sets wins; with equal sets, more games; equal on both is a draw.
- Until it is confirmed, whoever entered the score can correct it; a correction clears the confirmations given so far.
- One result per game.

### 5.5 Confirming and disputing

- Every other player in the result is notified and can **confirm** or **dispute** (with an optional short reason).
- **Call:** the result is confirmed as soon as one player from the *other* side confirms, or 24 hours after it was entered if nobody disputed. The other side is the one with a reason to object, so their word is enough, and ratings move the same evening instead of a day later.
- Any dispute while the result is pending freezes it: no ratings change, and it appears in the admin review list (§6.4). The admin can confirm it as entered, confirm it with a corrected score, or void it. Each of these is written to the audit log and the players are notified.
- A confirmed result is final for players. Only an admin can void a confirmed result, which reverses its rating changes exactly.

### 5.6 How ratings move

All numbers here are **Calls**, kept as named constants in one place so they can be tuned without touching the logic.

- Side strength = the average of its players' ratings at the moment of confirmation.
- Expected result for a side: `1 / (1 + 10 ^ (opponent strength − own strength))`. A side one full point stronger is expected to win about nine times in ten.
- Actual result: 1 for a win, 0.5 for a draw, 0 for a loss.
- Margin factor from 0.75 to 1.25, growing with the share of games won by the winner (a 6–0 6–0 win counts more than 7–6 7–6).
- Each player's change = their own step size × margin factor × (actual − expected). Step size is 0.30 while provisional and 0.12 after.
- Provisional = fewer than 10 confirmed results in that sport (spec proposal).
- Ratings stay within 1.00–7.00.
- Each player in a confirmed result gets exactly one rating event (old rating, new rating, change), a "rating updated" notification, and their rated-games count goes up by one.
- A deleted account's rating events are removed with the account; the other players' past changes stay as they were.

Known gap, accepted for now: two friends could trade results to climb. Every padel and tennis game needs a real court booking, which makes this slow and costly; nothing more is built against it in M7.

### 5.7 Leaderboard

- Per rated sport and city (the player's own city), ordered by rating, showing position, name, rating, "provisional" label and rated games.
- **Call:** it lists everyone with at least one confirmed result, so it is not empty for the first weeks. Players who hid themselves from Find players are not listed, and deleted accounts never are.
- The top 100, plus the signed-in player's own position if they are lower.
- Reached from the Social tab and from the rating on the profile.

### 5.8 After a game: one place for everything

The game page gains a "Game finished" section once the end time has passed, visible to participants only. It holds the score block (enter, or confirm/dispute, or the confirmed score with each player's rating change) for rated sports, and the votes and reports of Part 7b for every sport.

## 6. Part 7b — sportsmanship, no-shows, reports, admin review

### 6.1 Thumbs up or down

- For 7 days after a game ends, each participant can give every other participant a thumbs up or down, and change it within that time. One vote per pair per game. Votes are anonymous.
- The profile shows the share of thumbs up and the number of votes. **Call:** nothing is shown until a player has 5 votes, so one early thumbs-down cannot brand someone.
- Games with fewer than two participants have nothing to vote on.

### 6.2 "Didn't show up"

- For 48 hours after a game ends, a participant can mark another participant as not having shown up, and can undo it.
- When more than half of the *other* participants, and at least two people, have marked the same player, that player gets the existing no-show reliability penalty for that game, once, and loses the small "game completed" credit for it. They are notified. If reports are withdrawn below the majority within the 48 hours, the penalty is removed.
- **Call:** a host already marked no-show by the venue for the same booking is not penalised a second time for the same game.
- A two-player game can never reach "at least two reporters", so a no-show there is handled through the venue's mark or an abuse report. Accepted.
- **Call:** a player with a majority no-show cannot be part of that game's result; a pending result that includes them becomes disputed for the admin to look at.

### 6.3 Reporting abuse

- From the "Game finished" section or a player's profile: pick a reason (abusive language, aggressive behaviour, false score, other) and optionally write up to 500 characters. One open report per reporter per player per game.
- The reporter sees "sent"; the reported player is told nothing. Nothing happens automatically.

### 6.4 Admin review

- A new "Review" screen in the admin area with two lists and a count on the admin home: **disputed scores** (the game, both sides, the entered score, who disputed and why; actions in §5.5) and **reports** (who, about whom, which game, reason, text; action: close with a note).
- Every action is in the audit log.
- Admins can also delete a team from this screen (§7), for names or descriptions that should not stay up.

## 7. Part 7c — teams

- **A team** has a name, one sport, one city, a description, and a join policy: open, or approval required. It is shown with its initials on a colour.
- **Roles:** the creator is the captain; everyone else is a member. One captain per team.
- **Creating:** any signed-in player. **Call:** a player can be captain of at most 5 teams, and a name must be unique within its city and sport, to keep junk down.
- **Joining:** open teams join with one tap; approval teams send a request the captain approves or declines. Members can leave. The captain can remove a member, and can invite a player from that player's profile or from Find players (spec §7.7); the invited player accepts or declines.
- **Captain leaving:** the captain hands the role to a member first, or deletes the team. When a captain's account is deleted, the longest-standing member becomes captain; a team with no one left is deleted.
- **Team games:** when the captain creates a game in the team's sport they can post it "for the team". Members are notified and see it in their games list and on the team page; nobody else sees it. The captain may choose that it opens to everyone a set number of hours before the start if spots remain (**Call:** off, 12, 24 or 48 hours). Level and reliability rules for joining are unchanged.
- **Old builds:** a team-only game reads as "invite-only" to a build made before M7.
- **Where it shows:** the Social tab lists the player's teams first, then other teams in the city for their sports; a team page shows the description, members with level or rating, upcoming team games, and the join / leave / captain tools; the profile lists the player's teams (spec §7.2).
- The sample teams in the app today are replaced by this.

## 8. Notifications

New kinds, each opening the relevant screen: score entered (confirm or dispute), score confirmed with rating change, score disputed, dispute resolved, no-show recorded against you, team invite, team join request, join approved or declined, removed from team, made captain, team game posted, team deleted.

Two new mute categories in settings: **Ratings** and **Teams**. Old builds show an unknown kind as a generic line (already the case), so nothing breaks.

## 9. Left to the builder

- Table and function names, the exact JSON shapes, indexes, and how the derived level is kept in step (trigger or inside the functions), as long as §3 holds.
- Questionnaire wording and scoring table (§5.2), within the 1.0–5.0 limit.
- Screen layout, following the existing design system in `app/lib/core/theme.dart` and `app/lib/features/common/`; no new visual language.
- Sample data: a few sample players with ratings and results so the leaderboard, the finished-game section and teams are not empty in sample mode.
- Whether the 24-hour auto-confirm runs in the existing ten-minute job or is also applied when a result is read; it must not depend on someone opening the screen.
- Live check scripts in the style of `e2e-community.mjs` for a full score → confirm → rating change, and for a team game.

## 10. Rollout

Built on branch `m7-competitive` (worktree `D:\actra\.worktrees\m7-competitive`, from `main` 12e94df). Deploying to the live project, merging and pushing happen only when the founder asks, as in M2–M6. Because the level for padel and tennis changes meaning, a fresh app build should go out with the deploy.
