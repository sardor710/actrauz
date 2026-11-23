# Actra M3 — Owner Calendar and Admin Panel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Venue owners run their week in Actra: a weekly calendar per court where they add walk-in and phone bookings, block slots, cancel, and mark bookings paid or no-show, with the same no-double-booking guarantee as app bookings. Then hours and prices, the owner dashboard, and the admin screens.

**Architecture:** The owner and admin screens live in the same Flutter app as the player screens, behind role checks, so one sign-in, one design system and one copy of the booking rules serve phone and web. (This replaces the roadmap's separate `panel/` app and `packages/actra_core` package: there is nothing to share across packages if there is one package.) Every write goes through a Postgres function in the private `app` schema with a thin `public` wrapper, exactly as Milestone 2 did for player bookings; walk-ins and blocks are rows in `public.bookings`, so the existing exclusion constraint covers them.

**Tech Stack:** Flutter 3.32.6, Riverpod 2, go_router 14, Supabase (Postgres functions, RLS), Node test runner with embedded Postgres (`npm test` in `supabase/`).

**Spec:** [docs/actra-product-spec.md](../../actra-product-spec.md) §4, §5, §11, §12, §14. Roadmap: [2026-11-22-actra-roadmap.md](2026-11-22-actra-roadmap.md).

**Work location:** worktree `D:\actra\.worktrees\m3-owner`, branch `m3-owner-panel`, based on `main` at `f693f62`. Committed on that branch (`ede911d` and a follow-up for the end-to-end scripts) and deployed to the hosted project on 2026-11-23 at the user's request; not pushed and not merged into `main`.

## Status (2026-11-23)

| Part | State | Evidence |
|---|---|---|
| M3a owner calendar | built and verified | backend `npm test` 144 pass (39 in `owner.test.mjs`); app `flutter test` 192 pass (8 calendar flow tests); used in a browser at phone and desktop width; independent security review: no authorization hole, three should-fix items fixed and re-tested |
| M3b hours, prices, dashboard | built and verified | `owner_settings.test.mjs`; 6 settings flow tests; both screens seen in a browser; second security review: nothing blocking, price cap (50 000 000, so 24 slots cannot overflow an integer) and currency filter added |
| M3c admin | built and verified on sample data | backend `npm test` 169 pass (21 in `admin.test.mjs`); app `flutter analyze` clean and `flutter test` 241 pass (15 admin flow tests); admin home, venue editor (phone and desktop width) and sports list seen in a browser; the sport and banner forms were not looked at by eye |

| Deployment | the three migrations are applied to the hosted project | `node scripts/deploy.mjs migrations`: applied `owner`, `owner_settings`, `admin`; both scheduled jobs active; 25 new public functions, none callable by `anon`; RLS on `app_admins` and `audit_log`; `node scripts/e2e.mjs` PASSED (player flow after `hold_slots` and `cancel_booking` were redefined); `node scripts/e2e-owner.mjs` PASSED (admin creates a venue and court, assigns an owner; owner calendar, walk-in, block, mark paid, pricing, hours, dashboard, cancel; a player refused at every step; 11 audit rows), and it removed everything it made |

Not done: not pushed and not merged into `main`; no admin account exists yet (needs the phone number of the first admin, then the insert in `supabase/README.md`); the owner and admin **screens** have not been used against the real backend: the app was run in a browser on the hosted project as a plain player (no "My venues" or "Admin" row, as expected), and the 25 owner and admin calls in the Dart repositories match the SQL functions by name and parameter, but making a throw-away browser account an admin on the live project was blocked by the permission system, so that walk-through waits for a real admin account; photo upload for banners and venues is out of scope; the audit log pages by timestamp only; in sample mode an admin can open the calendar only of venues v1, v4 and v6. Debug APK built from this branch (94.9 MB).

Decisions made while building (spec proposals, open to change): a walk-in whose phone matches an account is linked to it but the owner is not told, the player cannot cancel it and it does not count toward the player's limit of 3 upcoming bookings; walk-ins may start in a slot that is in progress but not one that has ended; in sample mode the demo player manages venues v1, v4 and v6.

## Parts

| Part | Delivers | Status |
|---|---|---|
| **M3a** | Owner roles, weekly calendar, walk-ins, blocks, cancel, paid/no-show | this plan, tasks 1–4 |
| **M3b** | Working hours editor, price rule editor, owner dashboard | tasks 5–7 |
| **M3c** | Admin: venues and courts (with duplicate), owner assignment, sports, banners, audit log viewer | tasks 8–10 |

## Global Constraints

- A slot belongs to at most one active hold, booking or block, whatever its source (spec §14 rule 1). The existing `bookings_no_overlap` constraint stays the only enforcement point.
- Owners act only on venues assigned to them in `public.venue_owners`; admins act on every venue (spec §4).
- Owners cannot create or delete venues or courts (spec §11.2).
- Walk-in fields: name (required), phone, number of players, payment method Cash, Card or Transfer (spec §11.5).
- If a walk-in's phone matches an Actra account, the booking is linked to that account (spec §11.5 proposal).
- Mark Paid or No-show only after the booking's start time; Paid drives revenue (spec §5, §11.5).
- A booking not marked within 48 hours of its end becomes `unverified` (spec §5 proposal).
- Cancelling requires a confirmation dialog; the slot is free immediately (spec §11.5).
- Every owner write is recorded in an audit log with who, what, when, before and after (spec §12.7, §14 rule 5).
- Prices are locked on the booking when it is created (spec §11.4).
- Every interface string exists in `uz`, `ru` and `en`; `test/l10n/arb_parity_test.dart` enforces it.
- Times are venue wall-clock; the Dart side carries them as UTC-flagged `DateTime`, the SQL side as `timestamp` with the city's offset (existing convention).
- Existing public function signatures and the player app's behaviour do not change. All 106 app tests and the existing backend tests keep passing.

## Review Focus

1. Owner and player take the same slot at the same moment: exactly one succeeds, the other gets `slot_taken`.
2. A user who is not an owner of the venue calls any owner function: refused with `not_allowed`, nothing changes, nothing is logged.
3. Marking paid before the start time: refused with `not_markable`.
4. Walk-in on a slot that has already ended, or on a time that is not one of the court's slots: refused (`in_past`, `not_found`).
5. Cancelling a booking twice, or cancelling a block: the second call is refused with `not_cancellable`; a cancelled block frees its slots.

---

## Contract shared by tasks 1–3

### Public functions (called by the app)

| Function | Returns |
|---|---|
| `public.my_venue_ids()` | `uuid[]`: venues the caller manages; every active venue for an admin; empty for anyone else |
| `public.owner_calendar(p_court_id uuid, p_from date, p_days integer)` | `jsonb` `{ "slots": [...], "bookings": [...] }`; `p_days` 1–14 |
| `public.owner_create_walk_in(p_court_id uuid, p_starts timestamp[], p_name text, p_phone text, p_players integer, p_payment_method text)` | owner booking json |
| `public.owner_block_slots(p_court_id uuid, p_starts timestamp[], p_reason text)` | owner booking json |
| `public.owner_cancel_booking(p_booking_id uuid)` | owner booking json |
| `public.owner_mark_booking(p_booking_id uuid, p_outcome text)` | owner booking json; `p_outcome` is `paid` or `no_show` |

Slot object: `{ "starts_local", "ends_local", "price", "state", "booking_id" }`. `state` is `booked` or `blocked` when an active row covers the slot (whatever the time), otherwise `past` when the slot has ended, otherwise `free`. `booking_id` is null for `free` and `past`.

Owner booking json: every key of `app.booking_json`, plus `source` (`app`, `walk_in`, `block`), `walk_in_payment` (`cash`, `card`, `transfer` or null), `customer_name`, `customer_phone` (the guest's for a walk-in; the player's profile name and phone for an app booking; null for a block), and `reason` (blocks only).

Rules:
- Walk-ins and blocks: same slot validity and contiguity checks as `app.hold_slots`; allowed while the last selected slot has not ended; up to 14 days ahead; no "3 upcoming bookings" cap. A walk-in is created `confirmed` with `source = 'walk_in'`, price summed from the court's rules. A block is `confirmed` with `source = 'block'`, `total_price = 0`.
- `owner_cancel_booking`: allowed for `confirmed` rows that have not ended; sets `cancelled_by_venue`, never touches the player's late-cancellation flag.
- `owner_mark_booking`: allowed once the start has passed, for `confirmed`, `completed`, `unverified`, `paid`, `no_show` rows that are not blocks; `paid` sets `status = 'paid'` and `payment_status = 'paid'`; `no_show` sets `status = 'no_show'` and `payment_status = 'unpaid'`.
- New error names, raised the way `bookings.sql` already raises its errors: `not_allowed`, `not_markable`, `name_required`.
- Scheduled job `app.advance_bookings(p_now)`: `confirmed` rows whose end has passed become `completed`; `completed` rows whose end is more than 48 hours ago become `unverified`. Blocks are skipped.

### Dart types (`app/lib/domain/owner.dart`)

```dart
enum BookingSource { app, walkIn, block }
enum WalkInPayment { cash, card, transfer }
enum BookingOutcome { paid, noShow }
enum OwnerSlotState { free, booked, blocked, past }

class OwnerBooking {
  final String id, venueId, courtId;
  final DateTime start, end;          // venue wall-clock, UTC-flagged
  final int slotCount, totalPrice;
  final BookingStatus status;
  final BookingSource source;
  final PaymentStatus paymentStatus;
  final WalkInPayment? walkInPayment;
  final String? customerName, customerPhone, note, reason;
  final int? players;
}

class OwnerSlot { final SlotTime time; final int price; final OwnerSlotState state; final String? bookingId; }

class OwnerCalendar {
  final List<OwnerSlot> slots;
  final Map<String, OwnerBooking> bookings;
  List<OwnerSlot> slotsOn(DateTime date);   // slots starting on that wall-clock day
}
```

### Repository (`app/lib/data/owner_repository.dart`)

```dart
abstract class OwnerRepository {
  Future<List<Venue>> myVenues();
  Future<OwnerCalendar> calendar(String venueId, String courtId, DateTime from, int days);
  Future<OwnerBooking> createWalkIn(String venueId, String courtId, List<SlotTime> slots,
      {required String name, String? phone, int? players, required WalkInPayment payment});
  Future<OwnerBooking> blockSlots(String venueId, String courtId, List<SlotTime> slots, {String? reason});
  Future<OwnerBooking> cancel(String bookingId);
  Future<OwnerBooking> mark(String bookingId, BookingOutcome outcome);
}
```

Errors surface as `BookingException` with new `BookingError` values `notAllowed`, `notMarkable`, `nameRequired`.

Providers (`app/lib/state/owner_providers.dart`): `ownerRepositoryProvider`, `myVenuesProvider` (`FutureProvider<List<Venue>>`), `ownerCalendarProvider` (`FutureProvider.family<OwnerCalendar, ({String venueId, String courtId, DateTime from})>`, always 7 days), `void refreshOwner(WidgetRef ref)`.

---

### Task 1: Backend — owner roles, calendar functions, audit log

**Files:**
- Create: `supabase/migrations/20261123100000_owner.sql`, `supabase/tests/owner.test.mjs`
- Modify: `supabase/tests/helpers/fixtures.mjs` (owner and admin fixtures), `supabase/tests/schema.test.mjs` if it lists tables or functions, `supabase/README.md` (one section)

- [x] **Step 1:** Write `owner.test.mjs` first, one test per rule in the contract and one per Review Focus line, plus: a walk-in whose phone matches an account is linked to it; an admin (row in `app_admins`) can act on any venue; `my_venue_ids` for owner, admin and plain player; every successful owner write adds one `audit_log` row with actor, action, booking id, before and after; `advance_bookings` moves rows as specified and skips blocks; the player-side `court_availability` shows walk-ins and blocks as taken.
- [x] **Step 2:** `npm test` → the new file fails.
- [x] **Step 3:** Write the migration: `guest_name`, `guest_phone`, `walk_in_payment`, `block_reason` columns on `bookings`; `source` check widened to include `block`; a check that a walk-in has a guest name; `public.app_admins (user_id)` and `public.audit_log (id, actor_id, action, entity, entity_id, before jsonb, after jsonb, created_at)` with RLS on and no client grants; `app.is_admin`, `app.can_manage_venue`; the `app.*` functions taking the acting user and `p_now`; `app.owner_booking_json`; `public` wrappers with `security definer`, `search_path = ''`, grants to `authenticated` only; the `advance_bookings` cron schedule guarded like `jobs.sql`.
- [x] **Step 4:** `npm test` → every test passes, old and new.

### Task 2: App — owner domain and data layer

**Files:**
- Create: `app/lib/domain/owner.dart`, `app/lib/data/owner_repository.dart`, `app/lib/data/supabase/supabase_owner_repository.dart`, `app/lib/state/owner_providers.dart`, `app/test/domain/owner_engine_test.dart`, `app/test/data/owner_mappers_test.dart`
- Modify: `app/lib/domain/booking_engine.dart` (source and guest fields on `Booking`, owner operations on `BookingEngine`, three new `BookingError` values), `app/lib/data/sample/sample_repositories.dart` (`SampleBackend implements OwnerRepository`), `app/lib/data/sample/sample_data.dart` (`kSampleOwnedVenueIds = {'v1', 'v4', 'v6'}`), `app/lib/data/supabase/mappers.dart`, `app/lib/data/supabase/errors.dart`

- [x] **Step 1:** Write `owner_engine_test.dart`: the same rules as Task 1's tests, against `BookingEngine` (`ownerCalendar`, `createWalkIn`, `blockSlots`, `cancelByVenue`, `mark`), including that a player's `availability` shows walk-ins and blocks as `taken`, and that the calendar's `booked` slot carries the customer's name. Write `owner_mappers_test.dart`: an owner booking json and a calendar json map to the Dart types.
- [x] **Step 2:** `flutter test test/domain/owner_engine_test.dart test/data/owner_mappers_test.dart` → fail.
- [x] **Step 3:** Implement. In sample mode the signed-in demo player manages `kSampleOwnedVenueIds`; customer names for sample app bookings come from the sample players, and the demo player's own bookings use the session name.
- [x] **Step 4:** `flutter analyze` clean; `flutter test` → all pass (106 existing plus the new ones).

### Task 3: App — owner calendar screens

**Files:**
- Create: `app/lib/features/owner/owner_venues_screen.dart`, `app/lib/features/owner/owner_calendar_screen.dart`, `app/lib/features/owner/walk_in_sheet.dart`, `app/lib/features/owner/booking_details_sheet.dart`, `app/test/owner_flow_test.dart`
- Modify: `app/lib/router.dart` (`/owner`, `/owner/:venueId`), `app/lib/features/profile/profile_screen.dart` ("My venues" row when `myVenuesProvider` is not empty), the three ARB files

- [x] **Step 1:** Write `owner_flow_test.dart`: from the profile open My venues → the calendar shows this week for the first court; tap a free cell → fill name and payment → the cell is booked and shows the name; open it → Mark paid is disabled before the start; cancel with confirmation → the cell is free; block a cell → it shows as blocked; next week and Today navigate.
- [x] **Step 2:** Run → fail. Implement: week header with previous, next and Today; court switcher; a grid with one column per day and one row per slot time, a fixed time column, cells coloured free (green), booked (grey, customer name), blocked (hatched), past (faint); the walk-in sheet with name, phone, players, Cash/Card/Transfer and "also book the next slot"; the details sheet with customer, phone, time, price, source, status and the actions.
- [x] **Step 3:** `flutter analyze` clean; `flutter test` all pass; look at it in a browser at phone and desktop width in `uz` and `ru`.

### Task 4: Verify M3a

- [x] `npm test` in `supabase/` and `flutter analyze`, `flutter test`, `flutter build apk --debug` in `app/`; record the results here.
- [x] Independent review of the migration (security: grants, `search_path`, role checks) and of the calendar UI; fix what it finds.

## M3b — working hours, prices, dashboard

### Contract shared by tasks 5–7

Public functions (all refuse a caller who does not manage the venue with `not_allowed`, all write one `audit_log` row on success):

| Function | Returns |
|---|---|
| `public.owner_set_venue_hours(p_venue_id uuid, p_hours jsonb)` | `void`. `p_hours`: exactly seven objects `{ "weekday": 1–7, "open_minute": int or null, "close_minute": int or null }`; both null = closed |
| `public.owner_set_court_hours(p_court_id uuid, p_hours jsonb)` | `void`. `p_hours`: zero to seven objects of the same shape, one per weekday that differs from the venue; an empty array means the court follows the venue every day |
| `public.owner_set_court_pricing(p_court_id uuid, p_slot_minutes integer, p_base_price integer, p_rules jsonb)` | `void`. `p_rules`: array of `{ "weekdays": [1–7…], "from_minute": int, "to_minute": int, "price": int }`, replacing the court's rules in the given order |
| `public.owner_dashboard(p_venue_id uuid, p_court_id uuid, p_from date, p_to date)` | `jsonb`, see below. `p_court_id` null = every court of the venue; the range is inclusive and at most 92 days |

Validation errors: `invalid_hours` (minutes outside 0–1440, open not before close, a weekday missing or repeated), `invalid_argument` (slot length not 60, 90 or 120; a negative price; an empty weekday list; a malformed array), `rules_overlap` (two rules share a weekday and their time ranges intersect; spec §11.4).

Existing bookings are never changed by these functions: they keep their times and their locked price (spec §11.3, §11.4).

Dashboard json: `{ "currency", "days", "bookings_app", "bookings_walk_in", "revenue_paid", "revenue_unconfirmed", "no_shows", "slots_available", "slots_booked", "heatmap": [{ "weekday": 1–7, "hour": 0–23, "count": int }] }`.
- A booking belongs to the day and hour of its start, in venue wall-clock time. Counted statuses: `confirmed`, `completed`, `paid`, `no_show`, `unverified`; blocks and cancelled rows are never counted.
- `revenue_paid`: sum of `total_price` for `paid`. `revenue_unconfirmed`: sum for `unverified` (spec §5).
- `slots_available`: slots the courts offer in the range minus blocked slots; `slots_booked`: sum of `slot_count` of counted bookings. The app derives utilisation, daily average and no-show rate from these.
- `heatmap` lists only cells with a count above zero.

Dart (`app/lib/domain/owner.dart`, `app/lib/data/owner_repository.dart`):

```dart
class OwnerDashboard {
  final Currency currency;
  final int days, bookingsApp, bookingsWalkIn, revenuePaid, revenueUnconfirmed, noShows, slotsAvailable, slotsBooked;
  final Map<({int weekday, int hour}), int> heatmap;
  int get bookings;              // app + walk-in
  double get dailyAverage;       // bookings / days
  double get utilisation;        // slotsBooked / slotsAvailable, 0 when nothing is offered
  double get noShowRate;         // noShows / bookings, 0 when there are none
}

// added to OwnerRepository
Future<void> setVenueHours(String venueId, WeekHours hours);
Future<void> setCourtHours(String venueId, String courtId, WeekHours override);
Future<void> setCourtPricing(String venueId, String courtId,
    {required int slotMinutes, required int basePrice, required List<PriceRule> rules});
Future<OwnerDashboard> dashboard(String venueId, {String? courtId, required DateTime from, required DateTime to});
```

- `WeekHours` and `PriceRule` are the existing types in `domain/models.dart`. For `setVenueHours` the map has all seven weekdays; for `setCourtHours` it has only the overridden days (a key mapped to null = closed that day).
- New `BookingError` values `invalidHours`, `rulesOverlap`, `invalidArgument`.
- `List<(PriceRule, PriceRule)> overlappingRules(List<PriceRule> rules)` in `domain/pricing.dart`, used by the form and by the sample implementation.
- Provider `ownerDashboardProvider` (family keyed by `({String venueId, String? courtId, DateTime from, DateTime to})`). After a settings change, `refreshOwner` also invalidates `myVenuesProvider`, `venuesProvider` and `venueProvider`, so the player screens show the new hours and prices.
- In sample mode the changes are applied to `SampleBackend`'s venues for the rest of the app run, and the dashboard is computed from the engine's bookings.

### Task 5: Backend — settings and dashboard functions

**Files:** create `supabase/migrations/20261123110000_owner_settings.sql`, `supabase/tests/owner_settings.test.mjs`; add to the README section.

- [x] Tests first: each function for owner, admin and stranger; each validation error; saved hours and prices change what `court_availability` offers and charges for new bookings while an existing booking keeps its time and price; one audit row per change; dashboard numbers for a prepared set of bookings (app, walk-in, paid, no-show, unverified, cancelled, block) over a range, with and without a court filter; a range over 92 days is refused.
- [x] Migration; `npm test` passes in full.

### Task 6: App — settings and dashboard data layer

**Files:** modify `app/lib/domain/owner.dart`, `domain/pricing.dart`, `domain/booking_engine.dart`, `data/owner_repository.dart`, `data/sample/sample_repositories.dart`, `data/supabase/supabase_owner_repository.dart`, `data/supabase/mappers.dart`, `data/supabase/errors.dart`, `state/owner_providers.dart`; create `app/test/domain/owner_settings_test.dart`, extend `app/test/data/owner_mappers_test.dart`.

- [x] Tests first: overlap detection; sample settings change what players see; the dashboard numbers for a prepared engine state; json mapping.
- [x] Implement; `flutter analyze` clean and the data, domain and core tests pass.

### Task 7: App — settings and dashboard screens

**Files:** create `app/lib/features/owner/owner_settings_screen.dart`, `hours_editor.dart`, `pricing_editor.dart`, `owner_dashboard_screen.dart`, `app/test/owner_settings_flow_test.dart`; modify `owner_calendar_screen.dart` (app bar actions), `router.dart`, the ARB files.

- [x] Flow tests: close a weekday for the venue and see the calendar column empty; change a court's base price and see it in the walk-in form; an overlapping rule is refused with a message; the dashboard shows today's walk-in in its counts and the heatmap.
- [x] Implement; all tests pass; look at both screens in a browser.

## M3c — admin: venues, courts, owners, sports, banners, audit log

Scope note: banner and venue photo upload needs file storage and a file picker, which is its own piece of work; in M3c banners and venues keep their placeholder artwork. The admin dashboard and the tournament manager belong to Milestone 5, user governance to Milestone 4.

### Contract shared by tasks 8–10

Every function below refuses a caller who is not in `public.app_admins` with `not_allowed`, before reading anything, and every write adds one `audit_log` row.

| Function | Returns |
|---|---|
| `public.am_i_admin()` | `boolean`; callable by any signed-in user |
| `public.admin_list_venues()` | `setof jsonb`: every venue, active or not, newest first. Each: the venue's columns, `courts` (every court with its columns, `hours` and `price_rules`), `hours` (the venue's seven days), `owners` (`[{ "user_id", "full_name", "phone" }]`) |
| `public.admin_save_venue(p_venue jsonb)` | `uuid`. No `id` key = create (with working hours 08:00–22:00 every day), otherwise update. Keys: `city_id`, `name_uz|ru|en`, `description_uz|ru|en`, `address_uz|ru|en`, `district_uz|ru|en`, `phone`, `amenities` (array of `parking`, `showers`, `lighting`, `cafe`, `rental`), `active` |
| `public.admin_save_court(p_court jsonb)` | `uuid`. Keys: `id` (absent = create), `venue_id`, `sport_id`, `name_uz|ru|en`, `slot_minutes`, `base_price`, `indoor`, `active` |
| `public.admin_duplicate_court(p_court_id uuid)` | `uuid` of the copy: same venue, sport, slot length, prices, price rules and hour overrides; each name gets ` 2` appended; placed after the original |
| `public.admin_delete_court(p_court_id uuid)`, `public.admin_delete_venue(p_venue_id uuid)` | `void`. Refused with `has_bookings` when any booking row references it; deactivating (`active = false`) is the alternative and is always allowed |
| `public.admin_search_users(p_query text)` | `setof jsonb` `{ "user_id", "full_name", "phone" }`, at most 20, matching name (case-insensitive substring) or phone (digits substring); a query under 2 characters returns nothing |
| `public.admin_set_owner(p_venue_id uuid, p_user_id uuid, p_assigned boolean)` | `void`; assigning twice or removing an absent owner is not an error |
| `public.admin_list_sports()` | `setof jsonb`: every sport, by `sort_order` |
| `public.admin_save_sport(p_sport jsonb, p_create boolean)` | `text` id. Keys: `id` (`^[a-z][a-z0-9_]{1,29}$`), `name_uz|ru|en`, `icon_key`, `bookable`, `competitive_rating`, `default_players`, `sort_order`, `active`. Creating an id that exists gives `already_exists` |
| `public.admin_list_banners()` | `setof jsonb`: every banner, by `sort_order` |
| `public.admin_save_banner(p_banner jsonb)` | `uuid`. Keys: `id` (absent = create), `city_id` (null = every city), `title_uz|ru|en`, `subtitle_uz|ru|en`, `url` (must start with `https://`), `sort_order`, `active` |
| `public.admin_delete_banner(p_banner_id uuid)` | `void` |
| `public.admin_audit_log(p_limit integer, p_before timestamptz)` | `setof jsonb` `{ "id", "created_at", "actor_name", "action", "entity", "entity_id", "before", "after" }`, newest first; `p_limit` 1–100; `p_before` null = from the newest |

Validation errors: `invalid_argument` (a required key missing, an unknown city, sport, amenity or key, a name with no language filled in, text over 200 characters or a description over 2000, a bad url), `not_found` (unknown id on update, duplicate or delete), `has_bookings`, `already_exists`.

Admins can also call every owner function for any venue (already true since M3a).

Dart (`app/lib/domain/admin.dart`, `app/lib/data/admin_repository.dart`, `app/lib/state/admin_providers.dart`):

```dart
class OwnerRef { final String userId, name; final String? phone; }
class AdminVenue { final Venue venue; final bool active; final Set<String> inactiveCourtIds; final List<OwnerRef> owners; }
class VenueDraft { String? id; String cityId; LocalizedText name, description, address, district; String phone; List<String> amenities; bool active; }
class CourtDraft { String? id; String venueId, sportId; LocalizedText name; int slotMinutes, basePrice; bool indoor, active; }
class AdminSport { final Sport sport; final int sortOrder; final bool active; }
class SportDraft { String id; LocalizedText name; String iconKey; bool bookable, competitiveRating; int defaultPlayers, sortOrder; bool active; }
class AdminBanner { final String id; final String? cityId; final LocalizedText title, subtitle; final String url; final int sortOrder; final bool active; }
class BannerDraft { String? id; String? cityId; LocalizedText title, subtitle; String url; int sortOrder; bool active; }
class AuditEntry { final String id, action, entity; final String? entityId, actorName; final DateTime at; final Map<String, dynamic>? before, after; }

abstract class AdminRepository {
  Future<bool> isAdmin();
  Future<List<AdminVenue>> venues();
  Future<String> saveVenue(VenueDraft draft);
  Future<void> deleteVenue(String venueId);
  Future<String> saveCourt(CourtDraft draft);
  Future<String> duplicateCourt(String courtId);
  Future<void> deleteCourt(String courtId);
  Future<List<OwnerRef>> searchUsers(String query);
  Future<void> setOwner(String venueId, String userId, {required bool assigned});
  Future<List<AdminSport>> sports();
  Future<String> saveSport(SportDraft draft, {required bool create});
  Future<List<AdminBanner>> banners();
  Future<String> saveBanner(BannerDraft draft);
  Future<void> deleteBanner(String bannerId);
  Future<List<AuditEntry>> auditLog({int limit = 50, DateTime? before});
}
```

- Draft classes have mutable fields and a constructor with sensible defaults, plus `VenueDraft.from(AdminVenue)`, `CourtDraft.from(Court, {required bool active})`, `SportDraft.from(AdminSport)`, `BannerDraft.from(AdminBanner)`.
- New `BookingError` values `hasBookings`, `alreadyExists` (`notFound` exists).
- Providers: `adminRepositoryProvider`, `isAdminProvider`, `adminVenuesProvider`, `adminSportsProvider`, `adminBannersProvider`, `adminAuditProvider`, `void refreshAdmin(WidgetRef ref)` (also invalidates everything `refreshOwner` does, plus `sportsProvider` and `bannersProvider`).
- In sample mode the demo player is an admin; changes apply to `SampleBackend`'s in-memory data for the rest of the run, with the same validation; user search runs over the sample players; the audit log lists the changes made in this run.

### Task 8: Backend — admin functions

**Files:** create `supabase/migrations/20261123120000_admin.sql`, `supabase/tests/admin.test.mjs`; extend the README section.

- [x] Tests first: each function as admin, owner and plain player; each validation error; create and update round-trips through `admin_list_*`; a created venue and court are bookable by a player through the existing functions; duplicate copies price rules and hour overrides; delete refused with a booking present and allowed without; search by name and by phone; assigning an owner makes `my_venue_ids` return the venue for that user; one audit row per write; the audit reader pages with `p_before`.
- [x] Migration; `npm test` passes in full.

### Task 9: App — admin data layer

**Files:** create `app/lib/domain/admin.dart`, `app/lib/data/admin_repository.dart`, `app/lib/data/supabase/supabase_admin_repository.dart`, `app/lib/state/admin_providers.dart`, `app/test/domain/admin_sample_test.dart`, `app/test/data/admin_mappers_test.dart`; modify `sample_repositories.dart`, `mappers.dart`, `errors.dart`, `booking_engine.dart` (two error values).

- [x] Tests first, then implement; `flutter analyze` clean and the domain, data and core tests pass.

### Task 10: App — admin screens

**Files:** create `app/lib/features/admin/` (`admin_home_screen.dart`, `admin_venues_screen.dart`, `venue_editor_screen.dart`, `court_editor_sheet.dart`, `owners_sheet.dart`, `admin_sports_screen.dart`, `admin_banners_screen.dart`, `admin_audit_screen.dart`, `localized_field.dart`), `app/test/admin_flow_test.dart`; modify `router.dart`, `profile_screen.dart`, the ARB files.

- [x] Flow tests: the profile shows Admin for an admin; create a venue with a court and see it in the player's venue list; duplicate a court; deactivate a court and see it leave the player's venue page; assign an owner found by search; add a sport and see it in the list; add a banner and see it on Home; the audit log lists those actions; a non-admin sees no Admin row.
- [x] Implement with the existing design system (`core/theme.dart`, `features/common/widgets.dart`); every string in the three ARB files; laid out to work at phone width and to use the space at desktop width.
- [x] `flutter analyze` clean, `flutter test` all pass, checked in a browser.

Needs from the user: which phone number is the first admin (one `insert into public.app_admins` after that person has signed in once; see `supabase/README.md`).
