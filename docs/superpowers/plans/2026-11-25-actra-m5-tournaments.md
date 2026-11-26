# Actra M5 — Tournament Registration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Players browse tournaments and register in categories (singles, or pairs with a partner who must accept), with caps that are never exceeded, a waitlist with time-limited offers, and cancellation until the deadline; admins create and manage tournaments and participants, mark registrations paid, and see an admin dashboard with users and revenue split between venues and tournaments.

**Architecture:** Same as M2–M4. Rules live in `app` schema Postgres functions that take the acting user and the time; thin `public` security-definer wrappers pass `auth.uid()` and `now()`; clients cannot write tables. Registration notifications go through M4's `app.notify`. The app gets repository methods with a sample implementation and a Supabase implementation. Owner and admin screens stay in the same Flutter app behind role checks.

**Tech Stack:** Flutter 3.32.6, Riverpod 2, go_router 14; Supabase Postgres functions and RLS; `npm test` in `supabase/` (embedded Postgres).

**Spec:** [docs/actra-product-spec.md](../../actra-product-spec.md) §10.1, §12.1, §12.5, §13, §14 (registration lifecycle, integrity rule 2). Roadmap: [2026-11-22-actra-roadmap.md](2026-11-22-actra-roadmap.md) M5 ("A tournament fills and closes a category correctly").

**Work location:** worktree `D:\actra\.worktrees\m5-tournaments`, branch `m5-tournaments`, based on `main` at `4e7290b`.

## Status (2026-11-25)

| Part | State | Evidence |
|---|---|---|
| M5a registration backend | built and verified on local Postgres | backend `npm test` 322 pass, incl. cap races (singles, pairs, admin vs admin) |
| M5b admin tournament manager and dashboard backend | built and verified | `admin_tournaments.test.mjs`; revenue per currency matches the owner dashboard |
| M5c app | built and verified on sample data | `flutter analyze` clean, `flutter test` 420 pass (tournaments and admin tournaments flows) |
| Reviews | every task reviewed; final whole-branch review found 2 Important items (seed overwriting live categories, silent pair cancel), fixed and re-reviewed (approved) | |
| Deployment | **deployed 2026-11-26** at the user's request (`deploy.mjs migrations`: tournaments, admin_tournaments) | cron `actra-send-reminders` now also runs `expire_tournament_entries`; each of the 3 live tournaments has 1 backfilled category, `slots_filled` 0; `admin_dashboard` owner (postgres) can read `auth.users`. No live end-to-end run yet |

After deploy: the three live tournaments get one "Open" singles category each. Fix their categories in Admin → Tournaments before announcing registration, because a category's kind locks once anyone registers. The installed M4 app shows 0 filled spots and a single fee for them until then. Check that `admin_dashboard` can read `auth.users.last_sign_in_at` on the hosted project. Not built yet: the live check script `e2e-tournaments.mjs` (Task 6 step 2); the backend has 322 local tests but has not run on the hosted project.

Deferred: the seed guard has a one-statement race when seeding a live database under traffic; a seed run can still add missing sample categories to a registered tournament; `my_registrations` does not sweep (display only); `00`-prefixed phone input is not normalised; admins can move only `registered` entries; extending a deadline does not auto-offer the waitlist; no rate limit on partner invites; ru/uz copy needs a native-speaker pass.

## Scope decisions (spec proposals taken unless stated)

- **Eligibility per category:** a level range (1–5, from `player_levels` for the tournament's sport; no row counts as 1) and a `gender` label (`men`, `women`, `mixed`, `open`). Profiles have no gender, so the label is **shown, not enforced**; the level range is enforced. For pairs, both players must be in range. An admin can add a player to a category **bypassing eligibility** (spec: "checked but can be overridden"), never bypassing the cap.
- **Partner invite:** by picking a player (Find players) or by exact phone number. The phone lookup returns only whether an account exists and its id and name, never the phone.
- **Pending partner:** expires 48 h after the invite, or at the registration deadline, whichever is first. Pending registrations do not count toward the cap. Accepting when the category is full fails with `full` (the registrant may then join the waitlist).
- **Waitlist:** optional per category (`waitlist_enabled`). When a counted spot frees (cancel, remove, move, lapse, cap raised), the first waitlisted entry becomes `offered` for **24 hours** and **holds the spot** (offered counts toward the cap). Claim → `registered`. A lapsed offer moves to the next entry. A pairs entry is only offered once the partner has confirmed it.
- **Cancellation:** by the registrant or the partner, until the deadline. Paid registrations can be cancelled too (Phase 1 money is handled offline). After the deadline only an admin can remove.
- **Payment:** admin marks a registration paid or unpaid. The entry fee is **locked** onto the registration at registration time (spec §14 rule 4).
- **Cover image:** a URL field plus the existing colour fallback; photo upload stays out of scope (as in M3).
- **Organisers** (spec §15 open question) are not a role yet: admins run tournaments.
- **Revenue (admin dashboard):** venues = `sum(total_price)` of `paid` bookings (app and walk-in) by venue-local start date in the period, as in the owner dashboard; tournaments = `sum(fee)` of `registered` rows with `paid_at` in the period. Per currency, never summed across currencies. Users: total, active (signed in within 30 days, from `auth.users.last_sign_in_at`), new today / last 7 days / this month (city-local dates), all filterable by city. Secondary counts: bookings created, games created, tournament registrations in the period.
- **Brackets, scheduling, results:** Phase 2 (M8), not here.
- Existing live tournaments keep working: the migration gives each tournament that has no category one `open` singles category with `fee = min_fee`, `cap = slots_total`, and id `md5('actra:default-category:' || tournament_id)::uuid`. The sample data's first category of each sample tournament uses that same id formula, so a later seed run upserts it instead of duplicating it.
- **Legacy summary columns** `tournaments.min_fee, max_fee, slots_total, slots_filled` are read directly by the installed M4 app (home strip, tournaments list). One helper, `app.sync_tournament_summary(p_tournament_id)`, recomputes them from the categories and counted registrations, and **every function that changes a category or a counted registration calls it**. The seeded fake `slots_filled` numbers become the real counts (0 at first).
- **Active users:** sign-in sets `auth.users.last_sign_in_at` only once per device (token refreshes do not move it), so add `profiles.last_seen_at` and a `touch_last_seen()` RPC the app calls on start and on resume (written at most once per hour per user, enforced in SQL). Active = `last_seen_at` within 30 days, falling back to `last_sign_in_at`.
- **Blocked players** (M4 reliability `blocked`) cannot register, accept as partner, join the waitlist or claim (`reliability_too_low`); admin add bypasses it.

## Global Constraints

- Everything in M2–M4 Global Constraints still holds: venue wall-clock times across the API; ISO weekdays; whole-unit money with the city's currency; `_uz/_ru/_en` columns; errors SQLSTATE `P0001` with the code as message; new public functions `security definer`, `set search_path = ''`, revoked from `public, anon, authenticated`, granted to `authenticated, service_role`, with an anon test; never return a phone number; every new UI string in the three ARB files; additive migrations (live rows exist); deploy only with `deploy.mjs migrations` and only on the user's go-ahead.
- **Integrity rule 2:** a category's counted registrations (status `registered` or `offered`; paid is a flag on `registered`) never exceed its cap. Every path that can raise the count (register singles, accept partner, claim offer, admin add, admin move, waitlist offer) first takes `select ... for update` on the category row.
- Registration closes at `registration_deadline` (timestamptz, entered as venue-local wall clock like other times). Nothing but admin actions changes registrations after it.
- Every admin change to a tournament, category or registration writes `app.audit(...)` (M3).
- **Phones:** only admin functions (`admin_list_registrations`, its CSV) return phone numbers; every player-facing function returns none.
- **The installed M4 app keeps working:** additive columns only; nothing it reads (`tournaments` columns, existing RPCs) is renamed or removed.
- **Offers stop at the deadline:** `offer_next` does nothing once `registration_deadline` has passed; after it only `admin_offer_next` and `admin_add_registration` change who is in.
- **Foreign keys:** `tournament_registrations.user_id` and `partner_id` reference `profiles(id) on delete cascade`; `category_id` references categories `on delete restrict` (categories with registrations cannot be deleted anyway).
- New notification category `tournaments` (mutable like the others; add it to the allowed list in `set_settings`).

### Registration states (spec §14)

`pending_partner` → `registered` | `expired` | `declined`; `registered` → `cancelled` | `removed`; `waitlisted` → `offered` → `registered` | `lapsed`. `paid` is a flag (`paid_at`), not a state, so a paid registration is still `registered`. Counted toward the cap: `registered`, `offered`.

### Notifications

| kind | to | payload (plus `tournament_id`, `category_id`, `title` `{uz,ru,en}`, `category_name` `{uz,ru,en}`) | opens |
|---|---|---|---|
| `tournament_registered` | registrant (and partner) | `registration_id` | `/tournaments/:id` |
| `tournament_partner_invite` (category `invites`, as spec §13 lists pair invites under invites) | invited partner | `registration_id`, `actor_name` | `/tournaments/:id` |
| `tournament_partner_accepted` / `_declined` | registrant | `registration_id`, `actor_name` | `/tournaments/:id` |
| `tournament_partner_expired` | registrant | `registration_id` | `/tournaments/:id` |
| `tournament_spot_offered` | waitlisted player(s) | `registration_id`, `offer_expires_local` | `/tournaments/:id` |
| `tournament_deadline_reminder` | registrants whose entry is `pending_partner`, 24 h before the deadline | `registration_id` | `/tournaments/:id` |
| `tournament_removed` | registrant (and partner) when an admin removes them | `registration_id` | `/tournaments/:id` |
| `tournament_moved` | registrant (and partner) when an admin moves them | `registration_id`, `from_category_name` `{uz,ru,en}` | `/tournaments/:id` |

## Review Focus

1. **Two players take the last spot at once** (two singles registrations, or a partner accepting while a waitlist claim runs): exactly one gets it, the cap holds. — Task 1 concurrency test.
2. **A player registers, accepts, cancels or claims on someone else's registration** (or after the deadline): `not_found` / `deadline_passed`, nothing changes. — Task 1.
3. **A spot frees while the waitlist has entries:** the first gets an offer that holds the spot; an expired offer passes it on; nobody past the cap. — Task 1.
4. **A non-admin calls an admin function** or reads another player's registrations: refused. — Task 2.
5. **Revenue never sums UZS and KZT,** and only `registered` rows with `paid_at` count (a paid entry later cancelled or removed is not revenue). — Task 2.
6. **`find_player_by_phone` used to harvest names:** at most 20 lookups per caller per hour (`rate_limited`). — Task 1.

---

## M5a — registration backend

### Task 1: Backend — tournaments, categories, registration, partners, waitlist

**Files:**
- Create: `supabase/migrations/20261125100000_tournaments.sql`
- Test: `supabase/tests/tournaments.test.mjs`; extend `supabase/tests/concurrency.test.mjs`

**Interfaces — Produces:**
- `tournaments` gains `description_uz/ru/en text`, `registration_deadline timestamptz`, `cover_url text`, `color_seed integer not null default 0`. Backfill: `registration_deadline = starts_on 00:00 venue-local` where null.
- `tournament_categories(id uuid, tournament_id → tournaments on delete cascade, name_uz/ru/en, kind check in ('singles','pairs'), gender check in ('men','women','mixed','open') default 'open', min_level 1..5, max_level 1..5 (min ≤ max), fee integer ≥ 0, cap integer 1..512, waitlist_enabled boolean default true, sort_order int, created_at)`.
- `tournament_registrations(id uuid, category_id, user_id (registrant), partner_id null, partner_confirmed boolean, status (states above), fee integer, currency, paid_at timestamptz null, partner_expires_at, offer_expires_at, reminded_at, waitlist_position bigint (from a sequence; order of joining), created_at, decided_at, cancelled_at, admin_override boolean default false)`. A player appears in at most one live entry per category as registrant (partial unique index on `(category_id, user_id)` for live statuses: pending_partner, registered, waitlisted, offered). As partner, uniqueness applies only once confirmed (partial unique index on `(category_id, partner_id)` for live rows where `partner_confirmed`), so a pending invite cannot lock someone out; `respond_partner` re-checks at accept that neither player is already live in the category (`partner_unavailable`). No client table access.
- Backfill one default category per tournament without categories (see Scope).
- `app.category_counted(p_category_id) returns integer`; `app.tournament_json(t, p_user, p_now)` (all fields, dates as `starts_on/ends_on`, `registration_deadline_local`, `registration_open` boolean, `currency`, `fee_min/fee_max` from categories, `categories: [category_json]`, `my_registrations: [registration_json]`); `app.category_json(c, p_user)` (`filled`, `cap`, `waitlist_count`, `full`); `app.registration_json(r)` (ids, status, partner `{id, name}`, registrant `{id, name}`, fee, currency, paid, expiry times local; no phone).
- `app.register(p_user, p_category_id, p_partner_id uuid, p_now) returns public.tournament_registrations`: deadline passed ⇒ `deadline_passed`; level out of range (registrant, and partner for pairs) ⇒ `level_out_of_range`; already live in the category ⇒ `already_registered`; singles: lock category, full ⇒ `full`, else `registered`; pairs: partner required (`invalid_argument`), partner ≠ self, partner not live in the category (`partner_unavailable`), insert `pending_partner` with `partner_expires_at = least(now + 48h, deadline)`, notify partner. Fee and currency locked from the category and city.
- `app.respond_partner(p_user, p_registration_id, p_accept boolean, p_now)`: only the named partner (`not_found`); pending only; accept locks category, full ⇒ `full`; accept ⇒ `registered`, notify registrant `tournament_partner_accepted` and both `tournament_registered`; decline ⇒ `declined`, notify.
- `app.cancel_registration(p_user, p_registration_id, p_now)`: registrant or partner; before the deadline (`deadline_passed`); live statuses only; ⇒ `cancelled`; if it was counted, `app.offer_next(category, now)`.
- `app.join_waitlist(p_user, p_category_id, p_partner_id uuid, p_now)`: only when the category is full and `waitlist_enabled` (else `not_full` / `waitlist_closed`); same eligibility, deadline and duplicate checks as `register`. Creates a `waitlisted` row with the next `waitlist_position`. For pairs the row has `partner_confirmed = false` and the partner gets `tournament_partner_invite`; the partner confirms with `respond_partner` (accept sets `partner_confirmed = true` and the row stays `waitlisted`; decline ⇒ `declined`). Singles rows are created with `partner_confirmed = true`.
- `app.offer_next(p_category_id, p_now)`: while counted < cap, take the `waitlisted` row with the lowest `waitlist_position` **and `partner_confirmed`**, set it `offered`, `offer_expires_at = least(now + 24h, deadline)`, notify `tournament_spot_offered` (registrant and partner). Unconfirmed pairs are skipped, not removed.
- `app.claim_offer(p_user, p_registration_id, p_now)`: registrant or partner; `offered` and not expired (`not_found`) ⇒ `registered` (both players already agreed, so one claim completes it).
- `app.expire_tournament_entries(p_now) returns integer` (added to the `actra-send-reminders` job's command, keeping its existing calls): pending partners past `partner_expires_at` ⇒ `expired` + notify; offers past `offer_expires_at` ⇒ `lapsed` + `offer_next`; `tournament_deadline_reminder` once for `pending_partner` entries whose deadline is within 24 h (`reminded_at` column on registrations).
- `app.find_player_by_phone(p_user, p_phone, p_now)` ⇒ `{id, name}` or null (uses `app.normalize_phone`; never echoes the phone); at most 20 calls per caller per rolling hour, else `rate_limited` (a small `phone_lookups(user_id, at)` table).
- `app.touch_last_seen(p_user, p_now)` and public `touch_last_seen()`: sets `profiles.last_seen_at` when it is null or older than 1 hour.
- `app.sync_tournament_summary(p_tournament_id)` (see Scope), called by every count- or category-changing function in this task and Task 2.
- Public wrappers: `list_tournaments(p_city_id text, p_sport_id text default null, p_from date default null, p_sort text default 'date')` (`'date'` | `'az'`; only active tournaments ending today or later), `get_tournament(p_tournament_id uuid)`, `register_tournament(p_category_id uuid, p_partner_id uuid default null)`, `respond_partner(p_registration_id uuid, p_accept boolean)`, `cancel_registration(p_registration_id uuid)`, `join_waitlist(p_category_id uuid, p_partner_id uuid default null)`, `claim_offer(p_registration_id uuid)`, `my_registrations()` (upcoming tournaments, newest first), `find_player_by_phone(p_phone text)`.
- `set_settings` accepts the new category `tournaments`.

- [ ] **Step 1: Write failing tests** in `tournaments.test.mjs`: existing tournaments get one default category; singles register → `filled` 1, fee locked (changing the category fee later does not change it); cap 2 → third gets `full`; cancel frees the spot and offers it to the first waitlisted player (who sees `offered`, a notification, and the category still counts 2); the offer lapses after 24 h → next player offered; claim inside the window → `registered`; pairs: register with partner → `pending_partner`, not counted; a third party cannot respond (`not_found`); partner accepts → both see `registered`, registrant notified; accept when full → `full`; pending expires after 48 h (job) → `expired`, registrant notified; a pending invite does not stop the named partner from registering on their own; after the deadline the job offers nothing and sends no offer notifications; `find_player_by_phone` returns `rate_limited` on the 21st call within an hour; `slots_filled` on the tournament row follows every register, accept, cancel and claim; a blocked player gets `reliability_too_low`; `touch_last_seen` twice within an hour writes once; deadline passed → `register`, `cancel_registration`, `respond_partner` all `deadline_passed`; level out of range for the partner → `level_out_of_range`; a player who is someone's partner cannot register separately in that category (`already_registered`); `find_player_by_phone` returns id and name, no phone; `get_tournament` shows only the caller's own registrations in `my_registrations`; muting `tournaments` suppresses those notifications; anon cannot execute any new public function.
- [ ] **Step 2: Concurrency tests:** (a) a singles category with one spot left; two players register in parallel ⇒ one `registered`, one `full`, counted = cap; (b) a pairs category with one spot left; a partner accepts one pending pair while another pending pair's partner accepts at the same moment ⇒ one `registered`, one `full`. Repeat each 10 times.
- [ ] **Step 3:** `npm test` → FAIL. Write the migration. `npm test` → PASS.
- [ ] **Step 4:** Commit `M5: tournament registration, partners and waitlist`.

## M5b — admin

### Task 2: Backend — admin tournament manager and admin dashboard

**Files:**
- Create: `supabase/migrations/20261125110000_admin_tournaments.sql`
- Test: `supabase/tests/admin_tournaments.test.mjs`

**Interfaces — Consumes:** Task 1's tables, `offer_next`, `registration_json`, `category_counted`; M3's `app.require_admin`, `app.audit`, `app.clean_payload` (see `20261123120000_admin.sql` for the save pattern).

**Interfaces — Produces:**
- `app.admin_save_tournament(p_user, p_tournament jsonb, p_now) returns uuid`: create or update (id present ⇒ update); fields `city_id, sport_id, venue_id, title_*, description_*, starts_on, ends_on, registration_deadline_local, cover_url, color_seed, active`; venue must be in the city; `registration_deadline` ≤ end of `ends_on`. Keeps `min_fee/max_fee/slots_total/slots_filled` in step with the categories (so M1–M4 code reading them stays right).
- `app.admin_save_category(p_user, p_category jsonb, p_now) returns uuid`: create or update; `cap` cannot go below the counted registrations (`invalid_argument`); raising the cap calls `offer_next`; changing `kind` is refused once the category has live registrations (`has_registrations`).
- `app.admin_delete_category(p_user, p_category_id, p_now)`: refused with live registrations (`has_registrations`).
- `app.admin_list_registrations(p_user, p_tournament_id) returns setof jsonb`: every registration of the tournament with category, status, registrant and partner `{id, name, phone}` (admins see phones, as in M3 owner screens), fee, currency, paid, `admin_override`, waitlist position, created_at.
- `app.admin_set_paid(p_user, p_registration_id, p_paid boolean, p_now)`: `registered` only; sets or clears `paid_at`. Revenue counts only `registered` rows with `paid_at`, so cancelling or removing a paid entry takes it out of revenue.
- `app.admin_remove_registration(p_user, p_registration_id, p_now)`: any live status ⇒ `removed`, notify `tournament_removed`, `offer_next` if it was counted.
- `app.admin_move_registration(p_user, p_registration_id, p_category_id, p_now)`: same tournament only; target kind must match (pairs↔pairs); locks both categories in id order; target full ⇒ `full`; keeps the original fee (locked); notify `tournament_removed`-style `tournament_moved` (add the kind, category `tournaments`, payload with the new category) ; `offer_next` on the source.
- `app.admin_add_registration(p_user, p_category_id, p_user_id, p_partner_id, p_now)`: bypasses eligibility and the deadline, not the cap; pairs are created `registered` directly; `admin_override = true`.
- `app.admin_offer_next(p_user, p_category_id, p_now)` and `app.admin_remove_waitlisted` = `admin_remove_registration` on a waitlisted row.
- `app.admin_dashboard(p_user, p_city_id text, p_from date, p_to date, p_now) returns jsonb`: `users {total, active_30d, new_today, new_7d, new_month}` (active as in Scope), `revenue [{currency, venues, tournaments}]` (one row per currency present, never summed across), `counts {bookings, games, registrations}`; city null = all cities. Venue revenue uses `app.owner_dashboard`'s definition so admin and owner totals agree: `sum(total_price)` of bookings with status `paid`, app and walk-in (not blocks), by the booking's venue-local start date. Tournament revenue: `sum(fee)` of `registered` rows with `paid_at` in the period (city-local date of `paid_at`). Dates are city-local; with all cities use each row's own city offset.
- Public wrappers: `admin_save_tournament(p_tournament jsonb)`, `admin_save_category(p_category jsonb)`, `admin_delete_category(p_category_id uuid)`, `admin_list_tournaments()` (all, incl. inactive, newest first, with category counts), `admin_list_registrations(p_tournament_id uuid)`, `admin_set_paid(p_registration_id uuid, p_paid boolean)`, `admin_remove_registration(p_registration_id uuid)`, `admin_move_registration(p_registration_id uuid, p_category_id uuid)`, `admin_add_registration(p_category_id uuid, p_user_id uuid, p_partner_id uuid default null)`, `admin_offer_next(p_category_id uuid)`, `admin_dashboard(p_city_id text, p_from date, p_to date)`.
- Every write audits with before/after.

- [ ] **Step 1: Write failing tests:** a non-admin gets `forbidden` (or the M3 code `require_admin` raises) from every function; create a tournament with two categories, then `list_tournaments` shows it with `fee_min/fee_max` and the old `slots_total` in step; lowering a cap below the count ⇒ `invalid_argument`; raising it offers the waitlist; move between categories keeps the fee and refuses a full target; admin add bypasses a level range and the deadline but not a full cap; set paid then dashboard shows tournament revenue in UZS only, KZT tournament in another row, venues from paid bookings, unpaid excluded; users counts with `last_sign_in_at` set on some test users (extend the shim's `auth.users` with that column if missing, in `supabase/tests/helpers/shim.sql`); every admin write leaves one audit row; `admin_list_registrations` includes phones and is admin-only; anon test for all wrappers.
- [ ] **Step 2:** `npm test` → FAIL. Write the migration. `npm test` → PASS.
- [ ] **Step 3:** Commit `M5: admin tournament manager and dashboard`.

## M5c — app

### Task 3: App — tournament domain and data layer

**Files:**
- Create: `app/lib/domain/tournaments.dart`, `app/lib/data/supabase/supabase_tournament_repository.dart`
- Modify: `app/lib/data/repositories.dart` (new `TournamentRepository`), `app/lib/data/admin_repository.dart` and `app/lib/data/supabase/supabase_admin_repository.dart` (tournament manager + dashboard), `app/lib/data/sample/sample_repositories.dart`, `app/lib/data/sample/sample_data.dart` (categories for the sample tournaments; regenerate `supabase/seed.sql` with `dart run tool/gen_seed.dart` so the seed test passes), `app/lib/data/supabase/mappers.dart`, `app/lib/domain/community.dart` (notification routes for the new kinds), `app/lib/state/providers.dart`, `app/lib/state/admin_providers.dart`
- Test: `app/test/domain/tournaments_test.dart`, `app/test/data/sample_backend_test.dart`, `app/test/data/supabase_mappers_test.dart`

**Interfaces — Produces (Dart):**
- `enum CategoryKind { singles, pairs }`, `enum CategoryGender { men, women, mixed, open }`, `enum RegistrationStatus { pendingPartner, registered, waitlisted, offered, declined, expired, cancelled, removed, lapsed }`; `class TournamentCategory {id, name LocalizedText, kind, gender, minLevel, maxLevel, fee, cap, filled, waitlistCount, waitlistEnabled, full}`; `class Registration {id, categoryId, status, registrant PlayerRef, partner PlayerRef?, fee, currency, paid, partnerExpiresAt, offerExpiresAt, mine role: registrant|partner}`; `class Tournament {… existing TournamentItem fields …, description, registrationDeadline, registrationOpen, coverUrl, categories, myRegistrations}`. Keep `TournamentItem` working for the home strip (derive or keep the list endpoint mapping into it).
- `enum TournamentError { full, deadlinePassed, levelOutOfRange, alreadyRegistered, partnerUnavailable, notFull, waitlistClosed, notFound, invalidArgument, hasRegistrations, reliabilityTooLow, rateLimited, unavailable }` with a guard mapping the SQL codes.
- `TournamentRepository`: `list(String cityId, {String? sportId, DateTime? from, TournamentSort sort})`, `get(String id)`, `register(String categoryId, {String? partnerId})`, `respondPartner(String registrationId, {required bool accept})`, `cancel(String registrationId)`, `joinWaitlist(String categoryId, {String? partnerId})`, `claimOffer(String registrationId)`, `myRegistrations()`, `findPlayerByPhone(String phone) → PlayerRef?`.
- Admin additions: `tournaments()`, `saveTournament(TournamentDraft) → String`, `saveCategory(CategoryDraft) → String`, `deleteCategory(String)`, `registrations(String tournamentId) → List<AdminRegistration>`, `setPaid(String registrationId, bool)`, `removeRegistration(String)`, `moveRegistration(String, String categoryId)`, `addRegistration(String categoryId, String userId, {String? partnerId})`, `offerNext(String categoryId)`, `dashboard({String? cityId, required DateTime from, required DateTime to}) → AdminDashboard` (`users`, `revenue: List<CurrencyRevenue{currency, venues, tournaments}>`, `counts`).
- The app calls `touch_last_seen` once on start and on resume (Supabase mode only; a no-op in sample mode).
- Providers: `tournamentRepositoryProvider`, `tournamentsProvider.family<…, TournamentQuery>`, `tournamentProvider.family`, `myRegistrationsProvider`; admin: `adminTournamentsProvider`, `adminRegistrationsProvider.family`, `adminDashboardProvider.family`.
- Sample backend follows the same rules (cap, deadline, partner pending, waitlist offers held for 24 h, fee locked), demo player is admin as before.

- [ ] **Step 1: Write failing tests** (domain/sample: register to cap then `full`; cancel offers to the waitlist; pairs pending not counted; accept completes; deadline refusal; mappers: tournament json with two categories and `my_registrations`; dashboard json with two currencies; routes for every new notification kind).
- [ ] **Step 2:** Run → FAIL. Implement. `flutter analyze` clean, `flutter test` → PASS.
- [ ] **Step 3:** Commit.

### Task 4: App — player tournament screens

**Files:**
- Modify: `app/lib/features/tournaments/tournaments_screen.dart` (filters: date, sport, city, A–Z; cards with cover or colour, title, sport, city, dates, fee range, "Registration open/closed"), `app/lib/features/home/home_screen.dart` (tournament strip keeps working), `app/lib/features/profile/profile_screen.dart` (My tournaments row), `app/lib/features/inbox/` (render the new kinds), `app/lib/router.dart`, ARB files
- Create: `app/lib/features/tournaments/tournament_screen.dart` (detail: cover, title, description, venue, dates, deadline, categories with kind, gender label, level band, fee, "X of Y filled", full → greyed and disabled, waitlist button when enabled), `app/lib/features/tournaments/register_sheet.dart` (singles confirm; pairs: pick partner from Find players or enter a phone number), `app/lib/features/tournaments/my_tournaments_screen.dart` (registrations with status chips; actions: cancel, accept/decline as partner, claim an offer with its countdown)
- Test: `app/test/tournaments_flow_test.dart`

- [ ] **Step 1: Write failing widget tests:** list filters by sport and sorts A–Z; detail shows "X of Y filled" and a full category disabled with "Join waitlist"; registering singles updates the count; pairs by phone sends an invite and shows "Waiting for partner"; as partner, accepting from My tournaments shows "Registered"; cancelling before the deadline frees the spot; an offered entry shows "Claim" and claiming registers; after the deadline register/cancel are hidden; every new notification kind renders text in en/ru/uz.
- [ ] **Step 2:** Run → FAIL. Implement. Run → PASS; analyze clean.
- [ ] **Step 3:** Commit.

### Task 5: App — admin tournament manager and dashboard

**Files:**
- Create: `app/lib/features/admin/admin_tournaments_screen.dart` (list with filters date/sport/city/A–Z), `app/lib/features/admin/tournament_editor_screen.dart` (fields in three languages via `localized_field.dart`, categories list with add/edit sheet), `app/lib/features/admin/tournament_participants_screen.dart` (per category: registrations with status, paid toggle, remove, move, add player (search users), waitlist with "Offer next", "Copy CSV" of the category's participants), `app/lib/features/admin/admin_dashboard_screen.dart` (city filter, period presets Today / 7 days / This month / custom; user tiles; revenue table per currency with Venues and Tournaments columns, never a combined total; secondary counts)
- Modify: `app/lib/features/admin/admin_home_screen.dart` (Tournaments and Dashboard rows), `app/lib/router.dart`, ARB files
- Test: `app/test/admin_tournaments_flow_test.dart`

- [ ] **Step 1: Write failing widget tests:** create a tournament with a singles and a pairs category and see it in the player list; lowering a cap below the count shows the error; marking paid updates the dashboard's tournament revenue; moving a registration to a full category shows `full`; the dashboard shows UZS and KZT in separate rows with no combined total; CSV copy contains the header and one line per registration.
- [ ] **Step 2:** Run → FAIL. Implement. Run → PASS; analyze clean.
- [ ] **Step 3:** Commit.

### Task 6: Verify M5

- [ ] **Step 1:** `npm test`, `flutter analyze`, `flutter test` all pass; record counts.
- [ ] **Step 2:** Create `supabase/scripts/e2e-tournaments.mjs` in the style of `e2e-community.mjs` (throw-away admin, players and tournament; fills a 2-spot category, waitlist offer and claim, pairs invite and accept, mark paid, dashboard sees it, cleans up). Syntax-check only until deployed.
- [ ] **Step 3:** Browser walk-through on sample data at phone width in two languages: list → detail → register → pairs invite → admin participants → mark paid → dashboard.
- [ ] **Step 4:** Whole-branch review; fix wave; update Status and `supabase/README.md`; ask the user before deploy and push.
