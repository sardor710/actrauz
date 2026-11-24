# Actra M4 — Community Core Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Players find each other and play: Available Games for every sport type (booked court, place-only venue, map meeting point), join requests, invites and host tools; Game Requests with "I'm in" and conversion; a reliability score that reacts to no-shows and late cancellations; an in-app notification inbox; and "Find players".

**Architecture:** Same shape as M2/M3: every rule runs in Postgres functions in the private `app` schema (acting user and current time as arguments), with thin `public` wrappers that pass `auth.uid()` and `now()`. Tables are not writable by clients. Two primitives come first because nearly every later function calls them: `app.notify(...)` writes one inbox row (skipped when the recipient muted that category) and `app.reliability_event(...)` records one scored event. The Flutter app adds repository methods behind the existing interfaces, with a sample-data implementation (tests, offline demo) and a Supabase one.

**Tech Stack:** Flutter 3.32.6, Riverpod 2, go_router 14, `supabase_flutter` 2.x; Supabase Postgres functions + RLS; `npm test` in `supabase/` (embedded Postgres, `node:test`).

**Spec:** [docs/actra-product-spec.md](../../actra-product-spec.md) §7.2, §7.3, §7.6, §7.7, §8.1, §8.3, §9.1, §9.2, §13, §14. Roadmap: [2026-11-22-actra-roadmap.md](2026-11-22-actra-roadmap.md) M4.

**Work location:** worktree `D:\actra\.worktrees\m4-community`, branch `m4-community`, based on `main` at `ee609b3`.

## Status (2026-11-24)

| Part | State | Evidence |
|---|---|---|
| M4a notifications, reliability, booking hooks | not started | |
| M4b games for all sport types, requests to join, invites, host tools | not started | |
| M4c Game Requests | not started | |
| M4d find players, player profile, settings | not started | |
| Push delivery | **waiting on the user**: needs a Firebase project (roadmap §5) | |

## Scope decisions (spec proposals taken as written unless stated)

- **In M4:** owner-marked no-shows, late cancellations (bookings and game spots) and completed bookings/games feed reliability.
- **Moved to M7 with the other post-game flows:** peer no-show reports (§8.3 row 2), sportsmanship votes (§8.4), score entry (§8.2). They all hang off a "game finished" screen that M7 builds.
- **Waits for Teams (M7):** team invites and team games. **Waits for M5:** tournament-pair invites. **Admin announcements** (§13 last row) wait for the M5 admin dashboard.
- Levels stay 1–5 for every sport (padel/tennis 1.0–7.0 is M7).
- **Push:** the inbox is built in full; device push needs the user's Firebase project and is a later task (not in this plan). Nothing here blocks on it.
- **Public launch** (roadmap "done when") also needs store accounts, an iOS build path and data-localisation legal advice (roadmap §5–6). These are the founder's; this plan builds the software.
- Running and gym are added as place-only sports (`bookable = false`) by migration, and to the sample data.

## Global Constraints

- Everything in M2/M3's Global Constraints still holds: venue wall-clock times across the API, ISO weekdays, whole-unit money, `_uz/_ru/_en` columns, errors as SQLSTATE `P0001` with the code as message, secrets only in git-ignored files, `kMeId` (`'me'`) for the signed-in player at the repository boundary.
- **Migrations are additive** (`alter table`, `create or replace`): the hosted project has live rows. Start redefinitions from the latest definition: `app.hold_slots` and `app.cancel_booking` from `20261123100000_owner.sql`, not M2's. A `drop function` loses grants; prefer `create or replace` with the same signature.
- Every new `public` function: `security definer`, `set search_path = ''`, `revoke all ... from public, anon, authenticated`, `grant execute ... to authenticated, service_role`. `schema.test.mjs`-style test that `anon` cannot call any of them.
- Anything that adds a game participant (`join_game`, approving a request, accepting an invite, converting a Game Request) first takes `select ... for update` on the game row. A game's participants never exceed its spots (spec §14 rule 3).
- Never return a phone number from any M4 function.
- Every new interface string in `app_en.arb`, `app_ru.arb`, `app_uz.arb` (a test enforces it). Notification text is rendered by the app from `kind` + `payload`; the database stores no sentence.
- Rule changes to bookings are mirrored in `app/lib/domain/booking_engine.dart` and the sample backend.
- Deploy with `node scripts/deploy.mjs migrations` only (`db` reloads the seed and resets sample venues' hours and prices). Deploying and pushing need the user's go-ahead.

### Reliability (spec §8.3; numbers are this plan's, from the spec's proposals)

| Event (`kind`) | Delta | When |
|---|---|---|
| `no_show` | −20 | owner marks an **app** booking no-show |
| `late_cancel` | −5 | player cancels an app booking inside 6 h, or leaves a game inside 6 h of its start |
| `booking_paid` | +2 | owner marks an app booking paid |
| `game_completed` | +2 | each participant of a non-cancelled game, once it ends (scheduled job) |

- Score = `clamp(80 + sum(delta of events in the last 90 days), 0, 100)`. Events are unique per `(user_id, kind, ref)`; `ref` is the booking or game id (`game_id:user_id` is unnecessary since user is in the key).
- Re-marking a booking replaces its event: `paid` deletes that booking's `no_show` event, `no_show` deletes its `booking_paid` event. Venue cancellations never create events. Walk-ins never create events.
- Badge: `new` when the player has fewer than 3 events ever and score ≥ 70; else `reliable` when score ≥ 70; else `limited` when 50–69; else `blocked` (< 50).
- `limited`: at most **1** upcoming app booking (instead of 3). `blocked`: `hold_slots`, `join_game`, `request_to_join`, `create_game`, `create_game_request`, `request_interest` raise `reliability_too_low`. A blocked player recovers as events pass 90 days.

### Notifications (spec §13)

`notifications(id uuid, user_id, kind text, category text, payload jsonb, created_at, read_at)`. Categories a player can mute: `bookings`, `venue`, `games`, `requests`, `invites`. Muted ⇒ `app.notify` inserts nothing.

| kind | category | to | payload keys (always also `sport_id`, `starts_local` when there is one) | opens |
|---|---|---|---|---|
| `booking_confirmed` | bookings | player | `booking_id`, `venue_name` | `/bookings` |
| `booking_cancelled_by_venue` | bookings | player | `booking_id`, `venue_name` | `/bookings` |
| `booking_reminder` | bookings | player, 2 h before | `booking_id`, `venue_name` | `/bookings` |
| `venue_new_booking` | venue | each owner of the venue | `booking_id`, `venue_id`, `court_name`, `actor_name` | `/owner/:venueId` |
| `venue_booking_cancelled` | venue | each owner | same | `/owner/:venueId` |
| `game_joined` / `game_left` | games | host | `game_id`, `actor_name` | `/games/:id` |
| `join_request` | games | host | `game_id`, `request_id`, `actor_name` | `/games/:id` |
| `join_approved` / `join_declined` | games | requester | `game_id` | `/games/:id` |
| `game_full` | games | every participant but the one who filled it | `game_id` | `/games/:id` |
| `game_changed` | games | participants but the host | `game_id` | `/games/:id` |
| `game_cancelled` | games | participants but the actor | `game_id` | `/games/:id` |
| `game_removed` | games | the removed player | `game_id` | `/games/:id` |
| `game_reminder` | games | participants, 2 h before | `game_id` | `/games/:id` |
| `game_invite` | invites | invitee | `game_id`, `actor_name` | `/games/:id` |
| `request_interest` | requests | poster | `request_id`, `actor_name` | `/games/requests/:id` |
| `request_converted` | requests | interested players | `request_id`, `game_id`, `added` (bool) | `/games/:id` |
| `request_expired` | requests | poster and interested | `request_id` | `/games/requests/:id` |

`venue_name` is `{"uz","ru","en"}`; `actor_name` is the acting player's `full_name`.

## Review Focus

1. A host **approves a request, removes a player or cancels a game that is not theirs** (or a player converts someone else's Game Request): `not_found`/`forbidden`, nothing changes. — tests in Tasks 2, 3.
2. A player **reads another player's notifications** (table or function) or **sees an invite-only game** they were not invited to, through `list_games`, `get_game` or the tables directly: nothing returned. — Tasks 1, 2.
3. **Two players take the last spot at once** by different routes (one joins, the host approves another's request): exactly one gets in, the other gets `full`. — Task 2 concurrency test.
4. A **venue cancels the court booking** a game sits on: the game is cancelled and every participant notified; nobody's reliability drops. — Task 2.
5. An owner marks no-show, **then corrects it to paid**: the −20 disappears and +2 appears, once each, however many times it flips. — Task 1.

---

## M4a — notifications, reliability, booking hooks

### Task 1: Backend — notifications, reliability, settings, booking hooks, reminders

**Files:**
- Create: `supabase/migrations/20261124100000_community_core.sql`
- Test: `supabase/tests/community_core.test.mjs`
- Modify: `supabase/tests/helpers/fixtures.mjs` only if a helper is needed

**Interfaces — Produces:**
- Tables: `notifications` (above; RLS on, `select` policy `user_id = auth.uid()`, no client writes; index `(user_id, created_at desc)`; added to publication `supabase_realtime` when that publication exists), `reliability_events(id, user_id, kind check in the four kinds, delta int, ref text not null, created_at, unique (user_id, kind, ref))` (no client access). `profiles` gains `muted_categories text[] not null default '{}'` and `hidden_from_search boolean not null default false`. `bookings` gains `reminded_at timestamptz`.
- `app.notify(p_user uuid, p_kind text, p_category text, p_payload jsonb, p_now timestamptz) returns void`
- `app.reliability_event(p_user uuid, p_kind text, p_ref text, p_now timestamptz) returns void` (delta from the table above; `on conflict do nothing`)
- `app.reliability(p_user uuid, p_now timestamptz) returns jsonb` → `{"score": int, "badge": "new"|"reliable"|"limited"|"blocked"}`
- `app.require_reliable(p_user uuid, p_now timestamptz) returns void` (raises `reliability_too_low` when blocked)
- `app.venue_name(p_venue_id uuid) returns jsonb` (`{"uz","ru","en"}`)
- `app.send_reminders(p_now timestamptz) returns integer` — `booking_reminder` for confirmed app bookings starting within the next 2 h with `reminded_at is null` (then sets it). Task 2 extends it for games.
- Public: `my_notifications(p_limit integer default 50, p_before timestamptz default null) returns setof jsonb` (`id, kind, category, payload, created_at, read`), `unread_notification_count() returns integer`, `mark_notifications_read(p_ids uuid[] default null) returns void` (null = all mine), `my_settings() returns jsonb` (`muted_categories`, `hidden_from_search`, `reliability`), `set_settings(p_muted text[], p_hidden boolean) returns void` (unknown category → `invalid_argument`), `my_reliability() returns jsonb`.
- Redefined (same signatures): `app.hold_slots` (after the `for update` on profiles: `require_reliable`, cap 1 when `limited`), `app.confirm_booking` (notify player `booking_confirmed`, owners `venue_new_booking`), `app.cancel_booking` (`late_cancel` event when late; owners `venue_booking_cancelled`), `app.owner_cancel_booking` (player `booking_cancelled_by_venue` for app bookings), `app.owner_mark_booking` (event swap for app bookings).
- Seed rows by migration: sports `running` and `gym`, `bookable = false`, names in three languages, `on conflict (id) do nothing`.
- Scheduled job `actra-send-reminders` every 10 minutes, guarded like `jobs.sql`.

- [ ] **Step 1: Write failing tests** in `community_core.test.mjs`:
  - `notify` inserts a row; with the category muted it inserts nothing.
  - As user A, `select * from notifications` returns only A's rows; `my_notifications()` likewise; `insert into notifications` fails `42501`; `mark_notifications_read(array[<B's id>])` leaves B's row unread.
  - `unread_notification_count` drops to 0 after `mark_notifications_read()`.
  - Reliability: new user → `{score: 80, badge: 'new'}`; three `booking_paid` → `reliable`, 86; one `no_show` from 80 → 60 `limited`; two → 40 `blocked`; an event dated 91 days ago does not count.
  - `hold_slots` for a `blocked` player → `reliability_too_low`; a `limited` player with one upcoming confirmed booking → `too_many_bookings`.
  - Player cancels 3 h before start → one `late_cancel` event, score 75; cancels 10 h before → no event.
  - Owner marks app booking no-show → score 60; marks it paid → 82; no-show again → 60; repeating paid twice still 82. A walk-in marked no-show → no event.
  - Owner cancels an app booking → player gets `booking_cancelled_by_venue` with `venue_name.en`; no reliability event.
  - Confirm booking → player has `booking_confirmed`; each venue owner has `venue_new_booking`.
  - `send_reminders` at start − 1 h 50 m sends one `booking_reminder`; run again → none.
  - `set_settings(array['spam'], false)` → `invalid_argument`. `anon` cannot execute any of the six public functions.
- [ ] **Step 2:** `npm test` → new tests FAIL.
- [ ] **Step 3:** Write the migration. Run `npm test` → all PASS (the existing 169 included).
- [ ] **Step 4:** Commit `M4: notifications, reliability and booking hooks`.

## M4b — games for every sport type

### Task 2: Backend — create games, requests to join, invites, host tools, visibility

**Files:**
- Create: `supabase/migrations/20261124110000_games_v2.sql`
- Test: `supabase/tests/games_v2.test.mjs`; extend `supabase/tests/concurrency.test.mjs`

**Interfaces — Consumes:** Task 1's `notify`, `reliability_event`, `require_reliable`, `reliability`, `venue_name`, `send_reminders`.

**Interfaces — Produces:**
- `games` alterations: `venue_id` nullable; `kind text not null default 'booked' check in ('booked','place','map_point')`; `visibility text not null default 'public' check in ('public','invite_only')`; `meeting_point text`, `meeting_lat double precision`, `meeting_lng double precision`, `distance_km numeric(5,1)`, `pace text`; `reminded_at`, `completed_at timestamptz`. Checks: `kind in ('booked','place')` ⇒ `venue_id is not null`; `kind = 'map_point'` ⇒ `meeting_point is not null`.
- Tables `game_join_requests(id uuid, game_id, user_id, status check in ('pending','approved','declined','withdrawn'), created_at, decided_at)` with a partial unique index on `(game_id, user_id) where status = 'pending'`; `game_invites(game_id, user_id, invited_by, status check in ('pending','accepted','declined'), created_at, primary key (game_id, user_id))`.
- Direct `select` on `games`, `game_participants` and the two new tables is **revoked** from `authenticated` (the app only uses functions; check with grep that nothing in `app/lib` selects them).
- `app.game_json(g, p_user uuid)` replaces the one-argument version (drop the old one and recreate the four public M2 wrappers with their grants). Adds `kind, visibility, venue_id (nullable), meeting_point, meeting_lat, meeting_lng, distance_km, pace, status, my_status ('host'|'participant'|'invited'|'requested'|null), participants: [{id, name, level, reliability}]` (keeps `participant_ids`), and for the host only `join_requests: [{id, user_id, name, level, reliability, created_at}]` (pending ones).
- `app.can_see_game(p_user, g) returns boolean`: public, or host/participant/invited/has a request.
- Rules in `app.create_game(p_user uuid, p_game jsonb, p_now timestamptz) returns public.games`. Input keys: `sport_id`, `booking_id` | `venue_id` | (`meeting_point`, `meeting_lat`, `meeting_lng`), `starts_local`, `ends_local` (ignored for booked), `spots`, `min_level`, `max_level`, `visibility`, `note`, `distance_km`, `pace`.
  - `require_reliable`. `spots` 2..30, levels 1..5 with min ≤ max, else `invalid_argument`.
  - Bookable sport ⇒ `booking_id` required: the player's own `source = 'app'`, `status = 'confirmed'`, not started, court's sport = `sport_id`, else `booking_not_usable`; an open game already on it ⇒ `game_exists`. Time, venue and city from the booking; `price_per_player = ceil(total_price / spots)`.
  - Place-only sport ⇒ `venue_id` (kind `place`, city from the venue) or a meeting point (kind `map_point`, city = the player's profile city); start in the future (`in_past`), ≤ 14 days ahead (`too_far_ahead`), 0 < duration ≤ 12 h (`invalid_argument`). No price.
  - Inserts the host as participant.
- `app.join_game` redefined: `require_reliable`; invite-only without a pending invite ⇒ `not_found`; with a pending invite the level check is skipped and the invite becomes `accepted`; otherwise as before. Notifies host `game_joined`; when the game becomes full, `game_full` to the others.
- `app.leave_game` redefined: inside 6 h of the start ⇒ `late_cancel` event (ref = game id); notifies host `game_left`.
- `app.request_to_join(p_user, p_game_id, p_now) returns public.game_join_requests`: `require_reliable`; game must be visible (`not_found`), open and not started (`not_found`), not full (`full`); already participant ⇒ `already_joined`; pending exists ⇒ `already_requested`. Notifies host `join_request`.
- `app.withdraw_join_request(p_user, p_request_id)`.
- `app.decide_join_request(p_user, p_request_id, p_approve boolean, p_now) returns public.games`: host only (else `not_found`); request must be pending (`not_found`); locks the game `for update`; approve when full ⇒ `full`. Notifies `join_approved`/`join_declined`, plus `game_joined`-style `game_full` as in join.
- `app.invite_to_game(p_user, p_game_id, p_invitee, p_now)`: host only; invitee not already in ⇒ else `already_joined`; upsert pending. Notifies `game_invite`. `app.decline_invite(p_user, p_game_id)`.
- `app.host_remove_participant(p_user, p_game_id, p_member, p_now)`: host only; cannot remove self (`host_cannot_leave`). Notifies `game_removed`. No reliability event.
- `app.host_update_game(p_user, p_game_id, p_note text, p_spots integer, p_now)`: host only; `p_spots` < participant count or < 2 ⇒ `invalid_argument`; recomputes `price_per_player` for booked games. Notifies `game_changed`.
- `app.host_cancel_game(p_user, p_game_id, p_cancel_booking boolean, p_now)`: host only; status `cancelled`; if `p_cancel_booking` and booking linked and still confirmed → `app.cancel_booking(host, booking, now)` (late rules apply to the host). Notifies `game_cancelled`.
- `app.cancel_games_for_booking(p_booking_id uuid, p_actor uuid, p_now)`: every open game on that booking → cancelled, notifies participants but `p_actor`. Called from `app.cancel_booking` and `app.owner_cancel_booking` (both redefined again here from Task 1's text).
- `app.list_games(p_user, p_city_id, p_now)` redefined: visible games only, open, not started, not full unless the player is in it; plus every upcoming game where the player is host/participant/invited, whatever the city.
- `app.send_reminders` extended: `game_reminder` to participants of open games starting within 2 h, `reminded_at` set. New `app.complete_games(p_now) returns integer`: open games ended → `completed_at = now`, `game_completed` event for each participant; added to the job.
- Public wrappers (return `game_json(…, auth.uid())` where a game comes back): `create_game(p_game jsonb)`, `request_to_join(p_game_id uuid)`, `withdraw_join_request(p_request_id uuid)`, `decide_join_request(p_request_id uuid, p_approve boolean)`, `invite_to_game(p_game_id uuid, p_user_id uuid)`, `decline_invite(p_game_id uuid)`, `host_remove_participant(p_game_id uuid, p_user_id uuid)`, `host_update_game(p_game_id uuid, p_note text, p_spots integer)`, `host_cancel_game(p_game_id uuid, p_cancel_booking boolean)`; `get_game` returns null when not visible.

- [ ] **Step 1: Write failing tests** in `games_v2.test.mjs`:
  - Create from own confirmed padel booking, 4 spots, total 400 000 → `price_per_player` 100 000, host is the only participant, kind `booked`. From another player's booking or a cancelled one → `booking_not_usable`; second game on it → `game_exists`; football sport on a padel booking → `booking_not_usable`.
  - Running game with a meeting point → `map_point`, no price; gym game with a venue → `place`; running with start in the past → `in_past`; football without booking → `booking_not_usable`.
  - Invite-only game: stranger's `list_games` and `get_game` don't show it; `join_game` → `not_found`; `select from games` as `authenticated` → `42501`. After `invite_to_game` the invitee sees it and joins despite a level outside the range.
  - Level out of range → `request_to_join` → host sees it in `join_requests` with reliability; another player cannot `decide_join_request` (`not_found`); host approves → participant, requester notified `join_approved`.
  - Approving when full → `full`.
  - Leave 3 h before → `late_cancel`, host notified `game_left`; leave 10 h before → no event.
  - Host `host_update_game` spots below participant count → `invalid_argument`; note change notifies participants but not the host.
  - Host cancels with `p_cancel_booking = true` → booking `cancelled_by_player`, participants notified `game_cancelled`. Owner cancels the booking under an open game → game cancelled, participants notified, nobody has a reliability event.
  - `complete_games` after the end gives each participant one `game_completed`; running twice gives no more.
  - A blocked player: `join_game`, `request_to_join`, `create_game` → `reliability_too_low`.
  - `anon` cannot execute any new public function.
- [ ] **Step 2: Concurrency test** in `concurrency.test.mjs`: game with one spot left; in parallel, player X calls `join_game` and the host approves player Y's pending request → exactly one succeeds, the other gets `full`, participant count = spots.
- [ ] **Step 3:** `npm test` → FAIL. Write the migration. `npm test` → PASS, including the M2 `games.test.mjs` (update its calls to the two-argument `game_json` only where the signature forces it).
- [ ] **Step 4:** Commit `M4: games for every sport type, join requests, invites, host tools`.

## M4c — Game Requests

### Task 3: Backend — Game Requests, find players, player profile

**Files:**
- Create: `supabase/migrations/20261124120000_game_requests.sql`
- Test: `supabase/tests/game_requests.test.mjs`, `supabase/tests/players.test.mjs`

**Interfaces — Consumes:** Tasks 1–2 (`notify`, `require_reliable`, `reliability`, `app.create_game`).

**Interfaces — Produces:**
- `game_requests(id uuid, sport_id, city_id, host_id, during tstzrange (the time window), utc_offset_minutes, area text, venue_id uuid null, players_needed int check 1..29 (others, poster not counted), min_level, max_level, note, status check in ('open','converted','expired','cancelled'), game_id uuid null, created_at)`; `game_request_interest(request_id, user_id, created_at, primary key both)`. No client table access.
- `app.game_request_json(r, p_user)`: all fields as `starts_local`/`ends_local`, `interested: [{id, name, level, reliability}]`, `interested_count`, `my_status ('host'|'interested'|null)`.
- `app.create_game_request(p_user, p_request jsonb, p_now)`: keys `sport_id, starts_local, ends_local, area, venue_id, players_needed, min_level, max_level, note`; `require_reliable`; window in the future, ≤ 14 days, ≤ 12 h; city = venue's city if given, else the poster's profile city.
- `app.request_interest(p_user, p_request_id, p_now)` ("I'm in"): `require_reliable`; open and window not ended (`not_found`); poster ⇒ `invalid_argument`; twice ⇒ `already_joined`. Notifies poster `request_interest`. `app.withdraw_interest`, `app.remove_interested(p_user, p_request_id, p_member)` (poster only), `app.cancel_game_request(p_user, p_request_id)` (poster only, open only).
- `app.convert_game_request(p_user, p_request_id, p_place jsonb, p_now) returns public.games`: poster only (`not_found`); open (`not_found`); `p_place` has `booking_id` or `venue_id` or the meeting-point keys plus `spots` (default `1 + players_needed`) and for place-only `starts_local/ends_local` (default: the window); calls `app.create_game` with the request's sport, levels and note; then, holding the game lock, adds interested players in interest order while spots remain; request → `converted`, `game_id` set; each interested player gets `request_converted` with `added` true/false.
- `app.expire_game_requests(p_now) returns integer`: open requests whose window ended → `expired`, `request_expired` to poster and interested. Added to the 10-minute job.
- `app.list_game_requests(p_user, p_city_id, p_now)`: open, window not ended, earliest first; plus the player's own open ones.
- `app.list_players(p_user, p_city_id, p_sport_id text, p_min_level int, p_max_level int, p_query text, p_limit int)`: profiles in the city with `hidden_from_search = false`, not the caller, name `ilike` query, level filter on that sport (no level row counts as 1); returns `{id, name, city_id, levels: {sport: level}, reliability, games_played}`; never phone.
- `app.player_profile(p_user, p_id)`: same shape for one player (also for hidden players, who are only hidden from the list).
- Public wrappers: `create_game_request(p_request jsonb)`, `get_game_request(p_request_id uuid)`, `list_game_requests(p_city_id text)`, `request_interest(p_request_id uuid)`, `withdraw_interest(p_request_id uuid)`, `remove_interested(p_request_id uuid, p_user_id uuid)`, `cancel_game_request(p_request_id uuid)`, `convert_game_request(p_request_id uuid, p_place jsonb)`, `list_players(p_city_id text, p_sport_id text default null, p_min_level integer default 1, p_max_level integer default 5, p_query text default null, p_limit integer default 50)`, `player_profile(p_user_id uuid)`.

- [ ] **Step 1: Write failing tests**:
  - Create a football request Saturday 18:00–21:00, 9 needed; three players "I'm in" → `interested_count` 3, poster has three `request_interest`.
  - Another player cannot convert, remove or cancel it (`not_found`).
  - Convert with the poster's football booking and `spots` 3 → game with poster + first two interested; the third gets `request_converted` with `added: false`; request `converted`; a second convert → `not_found`.
  - Convert a running request with a meeting point → `map_point` game with everyone interested.
  - `expire_game_requests` after the window → `expired`, poster and interested notified once.
  - `list_players`: hidden player absent; caller absent; sport/level filter; result has no `phone` key anywhere; `player_profile` of a hidden player works.
  - `anon` cannot execute any new public function.
- [ ] **Step 2:** `npm test` → FAIL. Write the migration. `npm test` → PASS.
- [ ] **Step 3:** Commit `M4: Game Requests and find players`.

## App

### Task 4: App — domain types and data layer

**Files:**
- Modify: `app/lib/domain/games.dart`, `app/lib/data/repositories.dart`, `app/lib/data/social.dart`, `app/lib/data/sample/sample_repositories.dart`, `app/lib/data/sample/sample_data.dart` (running, gym; a few sample requests and notifications), `app/lib/data/supabase/supabase_game_repository.dart`, `app/lib/data/supabase/mappers.dart`, `app/lib/data/supabase/errors.dart`, `app/lib/domain/booking_engine.dart`, `app/lib/state/providers.dart`, `app/tool/seed_sql.dart` only if the new sports must appear in `seed.sql` (then regenerate it)
- Create: `app/lib/domain/community.dart` (reliability, notifications, game requests, player profile types), `app/lib/data/supabase/supabase_social_repository.dart`, `app/lib/data/supabase/supabase_notification_repository.dart`
- Test: `app/test/domain/games_test.dart`, `app/test/data/sample_backend_test.dart`, `app/test/data/supabase_mappers_test.dart`

**Interfaces — Produces (Dart):**
- `enum ReliabilityBadge { isNew, reliable, limited, blocked }`; `class Reliability { int score; ReliabilityBadge badge; }`.
- `enum GameKind { booked, place, mapPoint }`, `enum GameVisibility { public, inviteOnly }`, `enum MyGameStatus { host, participant, invited, requested }`. `Game` gains `kind`, `visibility`, `venueId` becomes `String?`, `meetingPoint`, `meetingLat`, `meetingLng`, `distanceKm`, `pace`, `myStatus`, `participants: List<GameMember>`, `joinRequests: List<JoinRequest>`, `cancelled`. `GameMember { id, name, level, reliability }`; `JoinRequest { id, member: GameMember, createdAt }`.
- `class GameDraft` (the `create_game` keys), `class GameRequest` (Task 3 json), `class GameRequestDraft`, `class PlacePick` (booking id | venue id | meeting point, spots, start/end).
- `JoinError` gains `alreadyRequested, notFound, reliabilityTooLow, bookingNotUsable, gameExists, invalidArgument, inPast, tooFarAhead, forbidden`; `BookingError` (in `booking_engine.dart`) gains `reliabilityTooLow`. `guardJoin` maps the new codes.
- `GameRepository` adds: `create(GameDraft) → Game`, `requestToJoin(String gameId)`, `withdrawRequest(String requestId)`, `decideRequest(String requestId, {required bool approve}) → Game`, `invite(String gameId, String userId)`, `declineInvite(String gameId)`, `removeParticipant(String gameId, String userId) → Game`, `updateGame(String gameId, {String? note, required int spots}) → Game`, `cancelGame(String gameId, {required bool cancelBooking})`, and for requests `requests(String cityId) → List<GameRequest>`, `request(String id)`, `createRequest(GameRequestDraft)`, `imIn(String id)`, `withdrawInterest(String id)`, `removeInterested(String id, String userId)`, `cancelRequest(String id)`, `convertRequest(String id, PlacePick place) → Game`.
- `SocialRepository` adds `players(String cityId, {String? sportId, int minLevel = 1, int maxLevel = 5, String? query})` (returns `List<PlayerProfile>`), `profile(String userId) → PlayerProfile`; teams stay sample.
- New `NotificationRepository`: `inbox({DateTime? before}) → List<AppNotification>`, `unreadCount() → int`, `markRead([List<String>? ids])`, `settings() → CommunitySettings` (`mutedCategories`, `hiddenFromSearch`, `reliability`), `saveSettings(CommunitySettings)`.
- `AppNotification { id, kind (String), category, payload, createdAt, read }` with `String? get route` per the table above.
- Providers: `socialRepositoryProvider`, `notificationRepositoryProvider`, `inboxProvider`, `unreadCountProvider`, `communitySettingsProvider`, `gameRequestsProvider`, `gameRequestProvider.family`, `playersProvider.family`, `playerProfileProvider.family`.
- Sample backend: same rules for joins/requests/invites/requests-to-play as the SQL, notifications written to an in-memory inbox, demo player `reliable`.

- [ ] **Step 1: Write failing tests**: domain (`joinGame` on invite-only without invite throws `notFound`; with invite it ignores level), sample backend (create game from own booking sets price per player; request → approve → participant; convert request adds interested up to spots; inbox gets `game_joined` when a sample player joins the demo player's game; muted category writes nothing), mappers (game json with `kind: 'map_point'`, null venue, participants and join requests; game request json; notification route for each kind in the table).
- [ ] **Step 2:** `flutter test` → FAIL. Implement. `flutter analyze` clean, `flutter test` → PASS.
- [ ] **Step 3:** Commit `M4: app data layer for games, requests, players, inbox`.

### Task 5: App — inbox, settings, reliability badge

**Files:**
- Create: `app/lib/features/inbox/inbox_screen.dart`, `app/lib/features/common/reliability_badge.dart`, `app/lib/features/profile/settings_screen.dart` (or a section in `profile_screen.dart` if smaller)
- Modify: `app/lib/router.dart` (`/inbox`, `/settings`), `app/lib/features/home/home_screen.dart` (bell with unread badge in the app bar), `app/lib/features/profile/profile_screen.dart` (reliability badge, settings row), ARB files
- Test: `app/test/community_flow_test.dart`

- [ ] **Step 1: Write failing widget tests** (sample backend): the home bell shows the unread count; opening the inbox lists notifications newest first with text rendered per kind in the current language; tapping a `game_joined` opens `/games/:id` and marks it read; "Mark all read" clears the badge; in settings, muting "Games" and saving persists through `communitySettingsProvider`; the hidden-from-search switch saves; the profile shows the reliability badge.
- [ ] **Step 2:** Run → FAIL. Implement. Run → PASS; `flutter analyze` clean.
- [ ] **Step 3:** Commit.

### Task 6: App — create a game, join requests, invites, host tools

**Files:**
- Create: `app/lib/features/games/create_game_screen.dart`, `app/lib/features/games/host_tools.dart` (requests list, participants with remove, edit sheet, cancel dialog with keep/cancel booking)
- Modify: `app/lib/features/games/game_screen.dart`, `games_screen.dart` (FAB "Create game"), `game_card.dart` (kind/visibility/meeting point), `app/lib/features/bookings/bookings_screen.dart` ("Create a game from this booking"), `app/lib/router.dart` (`/games/new?booking=`), ARB files
- Test: `app/test/community_flow_test.dart`

Behaviour: the create screen asks sport first. Bookable sport → choose one of the player's upcoming confirmed bookings for that sport (or a link to book a court); place-only → venue picker or meeting-point text field (+ distance and pace for running); then spots, level range, visibility, note. Game screen: join (one tap) when inside the level range; "Ask to join" otherwise; "Requested" with withdraw; invited players see Accept/Decline; host sees pending requests with level and reliability badge and Approve/Decline, participants with Remove, Edit (note, spots) and Cancel game (with "Also cancel my court booking" choice when booked). Every error code shows a translated message.

- [ ] **Step 1: Write failing widget tests**: create a padel game from the sample booking → it opens and shows "≈ X per player"; create a running game with a meeting point; out-of-range player taps "Ask to join" → host view (switch sample identity or seed a request) shows it and approving adds the player; host edits spots below the count → error text; cancel with keep booking leaves the booking in My bookings.
- [ ] **Step 2:** Run → FAIL. Implement. Run → PASS; analyze clean.
- [ ] **Step 3:** Commit.

### Task 7: App — Game Requests, find players, player profile

**Files:**
- Create: `app/lib/features/games/game_request_screen.dart`, `app/lib/features/games/create_request_screen.dart`, `app/lib/features/games/convert_request_sheet.dart`, `app/lib/features/social/player_profile_screen.dart`
- Modify: `games_screen.dart` (tabs "Games" / "Requests"), `app/lib/features/home/home_screen.dart` (Game Requests section: sport, window, "X of Y interested", level range, See all), `app/lib/features/social/social_screen.dart` (Find players: search, sport and level filters, reliability badge), `app/lib/router.dart` (`/games/requests/:id`, `/games/requests/new`, `/players/:id`), ARB files
- Test: `app/test/community_flow_test.dart`

Behaviour: request screen shows window, area, interested players with level and reliability; others tap "I'm in"/"Leave"; the poster removes players, cancels, or converts (booking picker for bookable sports, venue or meeting point for place-only; spots default `1 + players needed`). Player profile shows name, levels per sport, reliability badge, games played, and "Invite to a game" listing the viewer's upcoming hosted games.

- [ ] **Step 1: Write failing widget tests**: home shows a Game Requests section; "I'm in" increments the count; the poster converts with a booking and lands on the new game with the interested players in it; Find players filters by sport and level and hides nobody but hidden players; inviting from a profile makes the game appear as invited for that player in the sample backend.
- [ ] **Step 2:** Run → FAIL. Implement. Run → PASS; analyze clean.
- [ ] **Step 3:** Commit.

### Task 8: Verify M4

**Files:**
- Create: `supabase/scripts/e2e-community.mjs` (live check in the style of `e2e-owner.mjs`, cleans up after itself, never touches the user's own account)
- Modify: this plan's Status table, `supabase/README.md` (new functions and job)

- [ ] **Step 1:** `npm test` (supabase) and `flutter analyze` + `flutter test` (app) — all pass; record counts.
- [ ] **Step 2:** Run the app on sample data in the browser (`tool/run_web.cmd`), click through create game → request to join → approve → inbox → Game Request → convert → Find players, at phone width, in at least two languages; screenshot.
- [ ] **Step 3:** Independent security review of the three migrations against Review Focus; fix should-fix items.
- [ ] **Step 4:** Ask the user before `node scripts/deploy.mjs migrations` and before running `e2e-community.mjs` on the hosted project, and before any push or merge.
- [ ] **Step 5:** Update Status; commit.
