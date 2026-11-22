# Actra M2 — Backend and Real Sign-in Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Replace the sample data behind the app's repository interfaces with a Supabase backend: schema with row-level security, booking functions that make double booking impossible, Telegram phone-share sign-in, and Supabase implementations of the three repositories.

**Architecture:** Every booking rule runs inside Postgres. Rule logic lives in a private `app` schema whose functions take the acting user and the current time as arguments (so tests can fix the clock); thin `public` wrappers pass `auth.uid()` and `now()` and are the only thing the phone app can call. Tables are read-only to clients; all writes go through those functions. Sign-in is two edge functions: one issues and redeems one-time login tokens, the other is the Telegram bot webhook. The Flutter app picks the Supabase repositories when `SUPABASE_URL` is compiled in, otherwise the M1 sample backend (tests, offline demo).

**Tech Stack:** Supabase (Postgres 15+, GoTrue auth, PostgREST, Deno edge functions), Supabase CLI 3.x via npm (no Docker), `embedded-postgres` + `pg` + `node:test` for database tests (Node 24), `supabase_flutter` 2.x, `url_launcher`.

**Spec:** [docs/actra-product-spec.md](../../actra-product-spec.md) §3, §4, §7.1, §7.6, §11.3–11.4, §14. Roadmap: [2026-11-22-actra-roadmap.md](2026-11-22-actra-roadmap.md) §3.1.

## Global Constraints

- No double booking: `bookings.during` is a `tstzrange`; the exclusion constraint is exactly the one in roadmap §3.1 (statuses `held, confirmed, completed, paid, no_show, unverified`).
- Rules identical to `app/lib/domain/booking_engine.dart`: hold 5 minutes; one hold per player (a new hold replaces the old one); at most 3 upcoming confirmed bookings; no slot starting at or before now; at most 14 calendar days ahead (venue-local dates); cancellation free until 6 hours before start, later ones set `late_cancellation`; total price summed per slot and locked at hold.
- Check order in `hold_slots` matches the engine: empty → not a real slot → not contiguous → past → too far → too many → release own holds → taken.
- Times: stored as real instants (`timestamptz`); every value crossing the API is venue wall-clock (`timestamp` without zone), converted with `cities.utc_offset_minutes`. The offset is copied onto each booking and game. Nothing hard-codes UTC+5.
- Weekdays are ISO: 1 = Monday … 7 = Sunday (Dart `DateTime.weekday`, Postgres `isodow`).
- Money: whole units in `integer` columns, currency taken from the city (`UZS`, `KZT`), never converted.
- Admin-entered text: one column per language, suffixes `_uz`, `_ru`, `_en`.
- Errors raised by functions: SQLSTATE `P0001`, message is the code: `slot_taken`, `not_contiguous`, `empty_selection`, `in_past`, `too_far_ahead`, `too_many_bookings`, `hold_expired`, `not_found`, `not_cancellable`, `not_authenticated`, and for games `full`, `already_joined`, `level_out_of_range`, `not_participant`, `host_cannot_leave`.
- Players see only their own bookings and their own phone number. Clients have no insert/update/delete on any table except their own `profiles` and `player_levels` rows.
- Secrets live in `supabase/.env` and `app/env/dev.json`, both git-ignored. The bot token is only ever a function secret.
- No screen changes outside `features/onboarding`. At the repository boundary the signed-in player always has id `kMeId` (`'me'`), as in the sample backend.
- Languages `uz`, `ru`, `en` for every new interface string and every bot message.
- New tooling goes on D: (`D:\actra\supabase\node_modules`, npm cache `D:\actra\.npm-cache`).

## Review Focus

1. Someone forwards **another person's contact** to the bot: refused, no phone is recorded, no session.
2. A login token is **redeemed twice, after 10 minutes, or without the device's poll secret**: refused each time.
3. The webhook is called **without Telegram's secret header**: 401 and no change.
4. A signed-in player **writes to `bookings` directly** through the API (insert, or update status/price): denied; and cannot read another player's bookings or phone.
5. The **same player sends two holds at once** (double tap): exactly one hold remains.

Each has a test in the owning task below.

---

### Task 1: Tooling, secrets layout, database test harness

**Files:**
- Create: `.gitignore`, `supabase/.env.example`, `supabase/package.json`, `supabase/config.toml`
- Create: `supabase/tests/helpers/shim.sql` (what a plain Postgres lacks: roles `anon`, `authenticated`, `service_role`; schema `auth` with `auth.users` and `auth.uid()` reading `request.jwt.claims`), `supabase/tests/helpers/db.mjs`, `supabase/tests/run.mjs`
- Test: `supabase/tests/harness.test.mjs`

**Interfaces — Produces:**
- `npm test` in `supabase/`: `run.mjs` starts embedded Postgres in `supabase/tests/.pgdata`, builds database `actra_template` from `shim.sql` + every file in `migrations/` in name order, runs `node --test`, stops Postgres. If `ACTRA_TEST_DATABASE_URL` is set it uses that server instead.
- `db.mjs`: `freshDb(name) → { pool, connect(), end() }` (a new database cloned from the template); `asUser(client, userId, fn)` (runs `fn` in a transaction as role `authenticated` with that `sub`); `asAnon(client, fn)`; `expectError(promise, code)`; `createUser(pool, name) → uuid` (row in `auth.users` and `profiles`).

- [x] **Step 1:** Install `supabase`, `embedded-postgres`, `pg` as dev dependencies with `--cache D:\actra\.npm-cache`.
- [x] **Step 2:** Write `harness.test.mjs`: `create extension btree_gist` succeeds; `select auth.uid()` inside `asUser(u)` returns `u`; inside `asAnon` returns null.
- [x] **Step 3:** Run `npm test` → FAIL (no harness). Implement. Run → PASS.

### Task 2: Catalog and profile schema with row-level security

**Files:**
- Create: `supabase/migrations/20261122100000_catalog.sql`, `supabase/migrations/20261122100100_profiles.sql`
- Test: `supabase/tests/schema.test.mjs`

**Interfaces — Produces (tables, all in `public`, RLS enabled on every one):**
- `cities(id text pk, name_uz, name_ru, name_en, country_code, currency check in ('UZS','KZT'), utc_offset_minutes int)`
- `sports(id text pk, name_*, icon_key, bookable bool, competitive_rating bool, default_players int, sort_order int, active bool)`
- `venues(id uuid pk, city_id, name_*, description_*, address_*, district_*, phone, amenities text[], color_seed int, active bool)`
- `courts(id uuid pk, venue_id, sport_id, name_*, slot_minutes check in (60,90,120), base_price int, indoor bool, sort_order int, active bool)`
- `working_hours(id uuid pk, venue_id null, court_id null, weekday 1..7, closed bool, open_minute, close_minute)` — exactly one of `venue_id`/`court_id`; unique per (owner, weekday). No venue row for a weekday = closed. A court row overrides the venue for that weekday; `closed = true` closes the court.
- `price_rules(id uuid pk, court_id, weekdays int[], from_minute, to_minute (exclusive), price int, sort_order int)` — first match by `sort_order` wins.
- `banners(id uuid pk, city_id null = every city, title_*, subtitle_*, url, color_seed, sort_order, active)`
- `tournaments(id uuid pk, city_id, sport_id, venue_id, title_*, starts_on date, ends_on date, min_fee, max_fee, slots_total, slots_filled, active)`
- `profiles(id uuid pk → auth.users on delete cascade, full_name, city_id, language check in ('uz','ru','en'), terms_accepted_at, created_at)`
- `profile_contacts(user_id pk → profiles, phone text unique not null, telegram_user_id bigint unique)`
- `player_levels(user_id, sport_id, level 1..5, pk (user_id, sport_id))`
- `venue_owners(venue_id, user_id, pk both)`
- `login_tokens(token text pk, poll_secret_hash text, language text, status check in ('pending','awaiting_contact','verified','claimed'), telegram_user_id bigint, chat_id bigint, phone text, created_at, expires_at)`
- Policies: catalog tables `select` for `anon` and `authenticated`; `profiles` and `player_levels` `select` for `authenticated`, insert/update own row only; `profile_contacts` and `venue_owners` `select` own row only; `login_tokens` no policy and all privileges revoked from `anon`/`authenticated`.

- [x] **Step 1:** Write failing tests: as `anon`, `select` from each catalog table works and `insert into venues` fails with `42501`; as user A, `update profiles set full_name` on B's row changes 0 rows and on A's row 1; A sees 0 rows of B's `profile_contacts`; `select from login_tokens` as `authenticated` fails with `42501`; a `working_hours` row with both or neither owner fails the check; `slot_minutes = 45` fails the check.
- [x] **Step 2:** Run → FAIL. Write the migrations with explicit `grant`/`revoke` (do not rely on Supabase default privileges). Run → PASS.

### Task 3: Bookings table and booking functions

**Files:**
- Create: `supabase/migrations/20261122100200_bookings.sql`
- Test: `supabase/tests/booking.test.mjs`, `supabase/tests/concurrency.test.mjs`, `supabase/tests/booking_rls.test.mjs`

**Interfaces — Produces:**
- `bookings(id uuid pk, user_id → profiles, venue_id, court_id, during tstzrange, utc_offset_minutes, slot_count, total_price, currency, status, source default 'app' check in ('app','walk_in'), payment_method default 'pay_at_venue', payment_status default 'unpaid', hold_expires_at timestamptz, late_cancellation bool, players, note, created_at)`; status one of `held, confirmed, cancelled_by_player, cancelled_by_venue, completed, paid, no_show, unverified, released`; constraint `bookings_no_overlap` from roadmap §3.1. Policy: `select` where `user_id = auth.uid()` or the caller is in `venue_owners` for the venue. No write policy.
- Private (`app` schema, no grants to API roles):
  - `app.court_slots(p_court_id uuid, p_date date) → table(starts_local timestamp, ends_local timestamp, price int)`
  - `app.court_availability(p_user uuid, p_court_id uuid, p_date date, p_now timestamptz) → table(starts_local, ends_local, price, state text)` — state `free | taken | past | mine` exactly as `BookingEngine._stateOf`
  - `app.hold_slots(p_user uuid, p_court_id uuid, p_starts timestamp[], p_now timestamptz) → bookings`
  - `app.confirm_booking(p_user uuid, p_booking_id uuid, p_players int, p_note text, p_now timestamptz) → bookings`
  - `app.release_hold(p_user uuid, p_booking_id uuid) → void`
  - `app.cancel_booking(p_user uuid, p_booking_id uuid, p_now timestamptz) → bookings`
  - `app.release_expired_holds(p_now timestamptz) → int`
  - `app.booking_json(b bookings) → jsonb` with keys `id, user_id, venue_id, court_id, starts_local, ends_local, slot_count, total_price, currency, status, payment_method, payment_status, hold_expires_local, late_cancellation, players, note`
- Public (`security definer`, `search_path = ''`, execute granted to `authenticated` only, raise `not_authenticated` when `auth.uid()` is null): `hold_slots(p_court_id uuid, p_starts timestamp[]) → jsonb`, `confirm_booking(p_booking_id uuid, p_players int default null, p_note text default null) → jsonb`, `release_hold(p_booking_id uuid) → void`, `cancel_booking(p_booking_id uuid) → jsonb`, `my_bookings() → setof jsonb` (not held/released, newest start first), `court_availability(p_court_id uuid, p_date date) → table(...)` (also granted to `anon`).
- `hold_slots` locks the caller's `profiles` row first (serialises one player's requests), releases expired holds on the court, and turns an exclusion violation (`23P01`) into `slot_taken`.

- [x] **Step 1:** Port every case of `app/test/domain/booking_engine_test.dart` to `booking.test.mjs` against the `app.*` functions with the same fixture (court 90 min, 07:00–23:00, base 180 000, Mon–Fri 18:00–23:00 → 250 000; now = Sunday 2026-11-22 20:00 Tashkent) and the same expected values, one `test()` per Dart test, same names. Add: a court whose override closes Monday has no Monday slots and `hold_slots` gives `not_found`; a booking in a city with offset 360 returns the same wall-clock times it was given.
- [x] **Step 2:** Write `concurrency.test.mjs`: two connections call `app.hold_slots` for the same slot at the same moment, 20 different slots → each time exactly one succeeds and the other raises `slot_taken`; a raw `insert` overlapping a confirmed booking fails with `23P01`; **(Review Focus 5)** one player fires two holds for different slots at once → exactly one booking of theirs is `held` afterwards.
- [x] **Step 3:** Write `booking_rls.test.mjs` **(Review Focus 4)**: through the public wrappers as user A: hold then confirm works and `my_bookings()` returns it; as B `select from bookings` returns 0 rows and `my_bookings()` is empty; B's `court_availability` shows A's slot as `taken`; as A `insert into bookings` and `update bookings set total_price = 1` fail with `42501`; as `anon` `hold_slots` fails with `42501`; B confirming or cancelling A's booking raises `not_found`; a venue owner sees A's booking at their venue and not at another venue.
- [x] **Step 4:** Run → FAIL. Write the migration. Run → PASS.

### Task 4: Games in the database

**Files:**
- Create: `supabase/migrations/20261122100300_games.sql`
- Test: `supabase/tests/games.test.mjs`

**Interfaces — Produces:**
- `games(id uuid pk, sport_id, city_id, venue_id, host_id → profiles, booking_id → bookings null, during tstzrange, utc_offset_minutes, spots, min_level, max_level, price_per_player null, note, status default 'open' check in ('open','cancelled'))`, `game_participants(game_id, user_id, joined_at, pk both)`; `select` for `authenticated`, no write policy.
- `app.join_game(p_user uuid, p_game_id uuid) → games`, `app.leave_game(p_user uuid, p_game_id uuid) → games` (row lock on the game), `app.game_json(g games) → jsonb` with keys `id, sport_id, city_id, venue_id, host_id, starts_local, ends_local, spots, min_level, max_level, price_per_player, booking_id, note, participant_ids` (host first, then by `joined_at`).
- Public: `list_games(p_city_id text) → setof jsonb` (open, start after now, not full unless the caller is in it, earliest first), `get_game(p_game_id uuid) → jsonb`, `join_game(p_game_id uuid) → jsonb`, `leave_game(p_game_id uuid) → jsonb`.

- [x] **Step 1:** Port `app/test/domain/games_test.dart` (join lowers spots; `full`; `already_joined`; `level_out_of_range`; no level = level 1; leave; `host_cannot_leave`; `not_participant`) and add: two players joining the last spot at once → exactly one succeeds and participants never exceed spots; `list_games` hides a full game from an outsider and shows it to a participant.
- [x] **Step 2:** Run → FAIL. Write the migration. Run → PASS.

### Task 5: Seed data generated from the sample data

**Files:**
- Create: `app/tool/seed_sql.dart` (`String buildSeedSql()`), `app/tool/gen_seed.dart` (writes the file), `supabase/seed.sql` (generated, committed), `supabase/migrations/20261122100400_jobs.sql`
- Test: `app/test/data/seed_sql_test.dart`, `supabase/tests/seed.test.mjs`

**Interfaces — Produces:** `supabase/seed.sql`, safe to run repeatedly: upserts cities (from `kCities`), sports, venues, hours, courts, price rules, banners, tournaments (dated from today) and the eight sample players (rows in `auth.users`, `profiles`, `player_levels`, no way to sign in); then deletes and recreates the sample games through `app.hold_slots`/`app.confirm_booking` so each sits on a real booking. Ids are `md5('actra:' || sampleId)::uuid`. `jobs.sql` schedules `app.release_expired_holds(now())` every minute when `pg_cron` is available and does nothing otherwise.

- [x] **Step 1:** Write failing tests. Dart: `buildSeedSql()` equals the contents of `../supabase/seed.sql`; it mentions every venue, court, sport, player and banner id of the sample data. Node: after running `seed.sql`, venues per city are 3 / 2 / 1, 5 sports, 14 courts, every `*_uz`/`*_ru`/`*_en` column of venues and courts is non-empty, at least 4 games each within its spots and each game's slot is `taken` in `app.court_availability`; the court closed on Mondays has no Monday slots; running the seed a second time leaves every count unchanged.
- [x] **Step 2:** Run → FAIL. Implement, generate (`dart run tool/gen_seed.dart`). Run both → PASS.

### Task 6: Telegram sign-in edge functions

**Files:**
- Create: `supabase/functions/_shared/login_core.ts` (pure logic, no Deno or Supabase imports), `supabase/functions/_shared/bot_texts.ts`, `supabase/functions/_shared/supabase_deps.ts` (wires the core to supabase-js and the Bot API), `supabase/functions/telegram-login/index.ts`, `supabase/functions/telegram-webhook/index.ts`, `supabase/scripts/setup-telegram.mjs` (sets function secrets and the webhook)
- Test: `supabase/functions/_shared/login_core.test.ts` (run by `node --test`, in-memory fakes)

**Interfaces — Produces:**
- `POST /functions/v1/telegram-login` (anon key required)
  - `{action:"start", language}` → `{token, poll_secret, bot_url:"https://t.me/<bot>?start=<token>", expires_in:600}`
  - `{action:"claim", token, poll_secret}` → `{status:"pending"}` | `{status:"expired"}` | `{status:"ok", token_hash, is_new}`; the app redeems `token_hash` with `auth.verifyOTP(type: magiclink)`.
- `POST /functions/v1/telegram-webhook` (deployed with `--no-verify-jwt`; requires header `X-Telegram-Bot-Api-Secret-Token`)
  - `/start <token>` → marks the token `awaiting_contact`, sends a "share your phone number" button (`request_contact`) in the token's language
  - a contact message → if `contact.user_id == from.id`, stores the phone as `+<digits>`, marks `verified`, replies "return to the app" and removes the keyboard
- Core signatures: `startLogin(deps, {language})`, `claimLogin(deps, {token, pollSecret})`, `handleUpdate(deps, update)`, `normalizePhone(raw) → string | null`; `deps = { tokens, users, telegram, now(), randomToken() }`.
- Account rule: one account per phone. `claim` looks up `profile_contacts.phone`; if absent creates the auth user, `profiles` and `profile_contacts` rows.
- Function secrets: `TELEGRAM_BOT_TOKEN`, `TELEGRAM_WEBHOOK_SECRET`, `TELEGRAM_BOT_USERNAME`, `LOGIN_EMAIL_DOMAIN`.

- [x] **Step 1:** Write failing tests with fakes: start → `/start <token>` → own contact → claim returns `ok` with `is_new: true`, and a second sign-in with the same phone returns the same user with `is_new: false`; **(RF 1)** contact with a different `user_id` → no phone stored, claim stays `pending`, the bot asks for the user's own number; **(RF 2)** claim twice → second is `expired`; claim after 10 minutes → `expired`; claim with a wrong poll secret → `expired`; `/start` with an unknown token → help text, nothing stored; **(RF 3)** handler without the secret header → 401 and no call reaches the core; `normalizePhone('998 90 123-45-67') == '+998901234567'`, `normalizePhone('abc') == null`; bot replies are in the token's language for `uz`, `ru`, `en`.
- [x] **Step 2:** Run → FAIL. Implement. Run → PASS.

### Task 7: Supabase repositories in the app

**Files:**
- Modify: `app/pubspec.yaml` (`supabase_flutter`, `url_launcher`), `app/lib/main.dart`, `app/lib/state/providers.dart`
- Create: `app/lib/core/app_config.dart`, `app/lib/data/supabase/mappers.dart`, `app/lib/data/supabase/errors.dart`, `app/lib/data/supabase/supabase_catalog_repository.dart`, `app/lib/data/supabase/supabase_booking_repository.dart`, `app/lib/data/supabase/supabase_game_repository.dart`, `app/env/example.json`
- Test: `app/test/data/supabase_mappers_test.dart`

**Interfaces — Produces:**
- `class AppConfig { static const supabaseUrl = String.fromEnvironment('SUPABASE_URL'); static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY'); static bool get hasBackend; }`
- `mappers.dart` (pure): `LocalizedText textOf(Map row, String field)`, `DateTime wallClock(String iso)` (UTC-flagged), `String isoDate(DateTime d)`, `String isoLocal(DateTime d)`, `Sport sportFromRow(Map)`, `Venue venueFromRow(Map)`, `Booking bookingFromJson(Map, {required String? myUserId})`, `SlotView slotFromRow(Map)`, `Game gameFromJson(Map, {required String? myUserId})`, `Player playerFromRow(Map, {required String? myUserId})`, `BannerItem bannerFromRow(Map)`, `TournamentItem tournamentFromRow(Map)`. The caller's own user id is replaced by `kMeId`; status `unverified` maps to `BookingStatus.completed`.
- `errors.dart`: `Never rethrowDomain(Object error)` — a `PostgrestException` whose message is a known code becomes `BookingException` or `JoinException`; anything else is rethrown.
- Repositories take a `SupabaseClient`. `providers.dart`: `backendEnabledProvider` (`AppConfig.hasBackend`), `supabaseClientProvider`; the three repository providers return the Supabase implementations when enabled, else `sampleBackendProvider`.

- [x] **Step 1:** Write failing mapper tests: a venue row with nested `working_hours`, `courts`, `price_rules` gives `hours` keyed 1–7 with missing weekdays `null`, a court override with `closed: true` maps to a `null` entry, rules come out in `sort_order`, and `generateSlots`/`priceForSlot` on the result give 07:00…20:30 and 250 000 at 19:00 Monday; booking JSON `starts_local: "2026-11-23T17:30:00"` → `DateTime.utc(2026, 11, 23, 17, 30)`; status strings map to every `BookingStatus`; my user id becomes `kMeId` and others are kept; `rethrowDomain` maps `slot_taken` → `BookingError.slotTaken`, `level_out_of_range` → `JoinError.levelOutOfRange`, and rethrows an unknown message unchanged.
- [x] **Step 2:** Run → FAIL. Implement. Run → PASS. `flutter analyze` clean.

### Task 8: Real sign-in in the app

**Files:**
- Create: `app/lib/data/auth/auth_repository.dart` (interface + `DemoAuthRepository`), `app/lib/data/supabase/supabase_auth_repository.dart`
- Modify: `app/lib/state/session.dart`, `app/lib/state/providers.dart`, `app/lib/features/onboarding/onboarding_screen.dart`, `app/lib/main.dart`, `app/lib/l10n/app_{en,ru,uz}.arb`
- Test: `app/test/onboarding_telegram_test.dart`

**Interfaces — Produces:**
- `class LoginChallenge { String token; String pollSecret; Uri botUrl; DateTime expiresAt; }`
- `sealed class LoginPoll` → `LoginPending`, `LoginExpired`, `LoginSignedIn({String? fullName})`
- `abstract class AuthRepository { bool get isDemo; Future<LoginChallenge> startTelegramLogin(String languageCode); Future<LoginPoll> pollTelegramLogin(LoginChallenge challenge); Future<void> saveProfile({required String fullName, required String cityId, required String languageCode}); bool get hasSession; Future<void> signOut(); }`
- Providers: `authRepositoryProvider`, `urlOpenerProvider` (`Future<bool> Function(Uri)`, overridden in tests).
- Onboarding step 3: demo mode keeps the M1 name form. With a backend: "Continue with Telegram" → opens `botUrl` → waiting state polling every 2 s with "Open Telegram again" and "Cancel" → on `LoginSignedIn` with a name the session is signed in; without one, a name field and a required terms-and-privacy checkbox, then `saveProfile`. `LoginExpired` shows a message and returns to the button.
- `SessionController.signOut` also signs out of Supabase; at start-up a stored `user_name` without a Supabase session is cleared.

- [x] **Step 1:** Write failing widget tests with a fake `AuthRepository` (`isDemo: false`) and a recording URL opener: new player — tap "Continue with Telegram" → the opener received the bot URL and the waiting text shows → fake returns signed-in without a name → continuing without ticking terms shows the terms error → name + terms → home greets by name and `saveProfile` got name, city and language; returning player — signed-in with a name goes straight to home; expired — the expiry message shows and the Telegram button is back; a stored `user_name` with `hasSession == false` starts at onboarding.
- [x] **Step 2:** Run → FAIL. Implement; add the strings in all three languages. Run `flutter test` → PASS (including the unchanged M1 tests). `flutter analyze` clean.

### Task 9: Deploy and verify end to end

**Files:**
- Create: `supabase/scripts/env.mjs`, `supabase/scripts/deploy.mjs` (push migrations and seed, deploy functions, set secrets, set webhook, write `app/env/dev.json`), `supabase/scripts/e2e.mjs`, `supabase/README.md`
- Modify: `app/tool/run_web.cmd` (passes `--dart-define-from-file=env/dev.json` when the file exists)

- [x] **Step 1:** `npm test` in `supabase/` → all database and edge-function tests pass.
- [x] **Step 2:** `flutter analyze` → no issues; `flutter test` → all pass.
- [x] **Step 3:** `node scripts/deploy.mjs` against the hosted project → migrations applied, seed loaded, both functions deployed, webhook set (`getWebhookInfo` shows the function URL and no last error). *Done 2026-11-22 on project `xxqxlowlwxyjvngycrue` (ap-south-1). Migrations go over the HTTPS API: port 5432 is unreachable from the dev PC.*
- [x] **Step 4:** `node scripts/e2e.mjs` against the hosted project: signs in two throw-away accounts through the real functions (posting Telegram-shaped updates to the webhook with the secret header), account A holds and confirms a seeded slot, the row is read back from `bookings`, account B's `court_availability` shows it `taken` and B's `hold_slots` raises `slot_taken`; then cancels and deletes both accounts.
- [x] **Step 5:** On a phone or in the browser build: Sign in with Telegram through the real bot, share the contact, land in the app; book a slot; see it in the Supabase table editor; sign in as a second Telegram account and see the slot disabled. *Done 2026-11-22 in the browser build with Telegram's part played by `scripts/dev-login.mjs`: sign-in, name and terms, booking (row confirmed in the database, second account refused with `slot_taken`), cancel, join and leave a game, sign out. Real sign-in through @actraapp on a phone confirmed by the founder the same day: one account with phone, Telegram id, name and accepted terms in the database.*
