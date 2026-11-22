# Actra M1 — App Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Flutter player app for Android and iOS, in Uzbek, Russian and English, where a player can pick a city, browse venues, book back-to-back slots with correct prices, see and cancel bookings, and join games — all on sample data behind repository interfaces.

**Architecture:** Pure-Dart domain layer (slot generation, pricing, booking engine) with unit tests; repository interfaces with an in-memory sample-data implementation; Riverpod for state; go_router for navigation; Flutter gen-l10n ARB files for interface text. The Supabase implementation replaces the sample data in M2 without touching screens.

**Tech Stack:** Flutter 3.32.6 / Dart 3.8.1, flutter_riverpod 2.x, go_router 14.x, intl, shared_preferences, flutter_localizations.

**Spec:** [docs/actra-product-spec.md](../../actra-product-spec.md). Roadmap: [2026-11-22-actra-roadmap.md](2026-11-22-actra-roadmap.md).

## Global Constraints

- Languages: `uz` (Latin), `ru`, `en`. Every interface string exists in all three. Default: device language if supported, otherwise Russian (spec §3).
- Admin-entered content falls back to Russian, then English, when a translation is missing (spec §3).
- Cities: Tashkent (UZS), Almaty (KZT), Astana (KZT). All UTC+5 today; the offset is data on the city, never a constant in logic (spec §3).
- Prices are whole currency units shown in local currency, never converted (spec §3).
- Slots run back to back from opening time; a final slot that would end after closing is not offered (spec §11.3).
- A slot's price is the rule matching its start time, else the court's base price; the price is locked on the booking at confirmation (spec §11.4).
- A slot belongs to at most one active hold or booking (spec §14 rule 1). Hold lasts 5 minutes (spec §7.6).
- At most 3 upcoming pay-at-venue bookings per player; no past slots; at most 14 days ahead; cancellation is free until 6 hours before start, later ones are flagged late (spec §7.6).
- A game's participants never exceed its spots (spec §14 rule 3).
- No chat, no online payment (spec §2). Payment method is recorded as `payAtVenue` with a payment status from day one (spec §5).
- Sample venues, people and banners are fictional. No Playo code, names or artwork.
- All paths below are relative to `app/`.

## Review Focus

1. Court closed on the chosen day (venue closed, or court override closed): slot list is empty and the screen says so, no crash.
2. Opening hours shorter than one slot length, or closing before opening: zero slots, no negative or partial slot.
3. Two players holding the same slot: the second is refused with `slotTaken`, and the slot shows as unavailable to them.
4. A hold that expired before confirm: confirm is refused with `holdExpired` and the slots become free again.
5. Non-adjacent slot selection (07:00 and 10:00 on a 90-minute court): refused with `notContiguous`.

Each has a test in the owning task below.

---

### Task 1: Project setup, markets, money, localized text

**Files:**
- Modify: `pubspec.yaml`, `analysis_options.yaml`
- Create: `l10n.yaml`, `lib/core/markets.dart`, `lib/core/money.dart`, `lib/core/localized_text.dart`
- Test: `test/core/money_test.dart`, `test/core/localized_text_test.dart`

**Interfaces — Produces:**
- `enum Currency { uzs, kzt }`
- `class City { String id; LocalizedText name; String countryCode; Currency currency; int utcOffsetMinutes; }`, `const List<City> kCities`, `City cityById(String id)`
- `DateTime venueNow(City city, {DateTime? utcNow})` — venue wall-clock time as a UTC-flagged `DateTime`. **All domain `DateTime`s are venue wall-clock, UTC-flagged.**
- `String groupThousands(int amount)` — groups with U+00A0
- `class LocalizedText { const LocalizedText({String? uz, String? ru, String? en}); String resolve(String languageCode); }`

- [x] **Step 1:** Add dependencies: `flutter pub add flutter_riverpod:^2.6.1 go_router:^14.8.1 shared_preferences intl flutter_localizations --sdk=flutter`; set `flutter: generate: true`; `l10n.yaml` with `arb-dir: lib/l10n`, `template-arb-file: app_en.arb`, `output-dir: lib/l10n/gen`, `synthetic-package: false`, `output-class: AppLocalizations`.
- [x] **Step 2:** Write failing tests:

```dart
test('groups thousands with non-breaking spaces', () {
  expect(groupThousands(250000), '250 000');
  expect(groupThousands(999), '999');
  expect(groupThousands(1500000), '1 500 000');
  expect(groupThousands(0), '0');
});
test('falls back to Russian, then English', () {
  const t = LocalizedText(ru: 'Корт', en: 'Court');
  expect(t.resolve('uz'), 'Корт');
  expect(const LocalizedText(en: 'Court').resolve('uz'), 'Court');
  expect(const LocalizedText(uz: 'Kort', ru: 'Корт').resolve('uz'), 'Kort');
  expect(const LocalizedText().resolve('uz'), '');
});
test('venueNow applies the city offset', () {
  final now = venueNow(cityById('tashkent'), utcNow: DateTime.utc(2026, 11, 22, 20, 30));
  expect(now, DateTime.utc(2026, 11, 23, 1, 30));
});
```

- [x] **Step 3:** Run `flutter test test/core` → FAIL (symbols missing). Implement. Run → PASS.

### Task 2: Domain models and slot generation

**Files:**
- Create: `lib/domain/models.dart`, `lib/domain/slot_generator.dart`
- Test: `test/domain/slot_generator_test.dart`

**Interfaces — Produces:**
- `class DayHours { int openMinute; int closeMinute; }` (minutes from midnight)
- `typedef WeekHours = Map<int, DayHours?>` keyed by `DateTime.weekday` (1 = Monday); `null` = closed
- `class PriceRule { Set<int> weekdays; int fromMinute; int toMinute; int price; }` (`toMinute` exclusive)
- `class Court { id, venueId, sportId, LocalizedText name, int slotMinutes (60|90|120), int basePrice, List<PriceRule> priceRules, WeekHours hoursOverride, bool indoor }`
- `class Venue { id, cityId, LocalizedText name, description, address; String district; String phone; List<String> sportIds; WeekHours hours; List<String> amenities; List<Court> courts; int colorSeed }`
- `class Sport { id, LocalizedText name, bool bookable, bool competitiveRating, int defaultPlayers, String iconKey }`
- `class SlotTime { DateTime start; DateTime end; }` with value equality
- `DayHours? effectiveHours(Venue venue, Court court, DateTime date)` — court override for that weekday if the key is present, else venue hours
- `List<SlotTime> generateSlots(Venue venue, Court court, DateTime date)`

- [x] **Step 1:** Write failing tests:

```dart
test('07:00–23:00 with 90-minute slots gives 07:00 … 20:30', () {
  final slots = generateSlots(venue(open: 7 * 60, close: 23 * 60), court(slot: 90), monday);
  expect(slots.length, 10);
  expect(slots.first.start, DateTime.utc(2026, 11, 23, 7, 0));
  expect(slots.last.start, DateTime.utc(2026, 11, 23, 20, 30));
  expect(slots.last.end, DateTime.utc(2026, 11, 23, 22, 0));
});
test('slots are back to back', () { /* every slots[i].end == slots[i+1].start */ });
test('closed day gives no slots', () { /* venue hours null for that weekday → [] */ });
test('court override replaces venue hours, including closed', () { /* override 10:00–12:00 → 2 slots of 60; override null → [] */ });
test('hours shorter than a slot, or close before open, give no slots', () { /* 07:00–08:00 with 90 → []; 20:00–08:00 → [] */ });
```

- [x] **Step 2:** Run → FAIL. Implement. Run → PASS.

### Task 3: Pricing

**Files:**
- Create: `lib/domain/pricing.dart`
- Test: `test/domain/pricing_test.dart`

**Interfaces — Produces:** `int priceForSlot(Court court, SlotTime slot)`; `({int min, int max})? feeRange(Venue venue, String sportId, DateTime weekStart)` — min and max slot price over seven days for that sport's courts, `null` if no slots.

- [x] **Step 1:** Write failing tests:

```dart
// court: base 180000; rule Mon–Fri 18:00–23:00 → 250000; rule Sat–Sun 00:00–24:00 → 300000
test('rule matching the start time wins', () { expect(priceForSlot(c, slotAt(monday, 18, 0)), 250000); });
test('no matching rule uses base price', () { expect(priceForSlot(c, slotAt(monday, 10, 0)), 180000); });
test('rule end is exclusive, start inclusive', () {
  expect(priceForSlot(c, slotAt(monday, 17, 30)), 180000);
  expect(priceForSlot(c, slotAt(monday, 23, 0)), 180000);
});
test('weekend rule applies all day', () { expect(priceForSlot(c, slotAt(saturday, 9, 0)), 300000); });
test('fee range spans min and max', () { expect(feeRange(v, 'padel', monday), (min: 180000, max: 300000)); });
```

- [x] **Step 2:** Run → FAIL. Implement. Run → PASS.

### Task 4: Booking engine

**Files:**
- Create: `lib/domain/booking_engine.dart`
- Test: `test/domain/booking_engine_test.dart`

**Interfaces — Produces:**
- `enum BookingStatus { held, confirmed, cancelledByPlayer, cancelledByVenue, completed, paid, noShow, released }`; `enum PaymentMethod { payAtVenue }`; `enum PaymentStatus { unpaid, paid }`
- `class Booking { id, userId, venueId, courtId, DateTime start, DateTime end, int slotCount, int totalPrice, BookingStatus status, PaymentMethod paymentMethod, PaymentStatus paymentStatus, DateTime? holdExpiresAt, bool lateCancellation, int? players, String? note }`
- `enum SlotState { free, taken, past, mine }`; `class SlotView { SlotTime time; int price; SlotState state; }`
- `enum BookingError { slotTaken, notContiguous, emptySelection, inPast, tooFarAhead, tooManyBookings, holdExpired, notFound, notCancellable }`; `class BookingException implements Exception { BookingError error; }`
- `class BookingEngine { BookingEngine({required Venue Function(String) venueById}); static const holdDuration = Duration(minutes: 5), maxUpcoming = 3, maxDaysAhead = 14, freeCancelWindow = Duration(hours: 6);`
  - `List<SlotView> availability(String venueId, String courtId, DateTime date, {required DateTime now, String? userId})`
  - `Booking hold({required String userId, required String venueId, required String courtId, required List<SlotTime> slots, required DateTime now})`
  - `Booking confirm(String bookingId, {required DateTime now, int? players, String? note})`
  - `void release(String bookingId)`
  - `Booking cancel(String bookingId, {required DateTime now})`
  - `List<Booking> bookingsOf(String userId)`; `Booking? byId(String id)` `}`

- [x] **Step 1:** Write failing tests, one per rule: hold then confirm locks the summed price and sets `confirmed`/`payAtVenue`/`unpaid`; second user's hold on the same slot throws `slotTaken`; held slot shows `taken` to others and `mine` to the holder; expired hold → `confirm` throws `holdExpired` and the slot is `free` again; 07:00 + 10:00 on a 90-minute court throws `notContiguous`; empty list throws `emptySelection`; slot starting before `now` throws `inPast` and shows `past`; date 15 days ahead throws `tooFarAhead`; fourth upcoming confirmed booking throws `tooManyBookings`; cancel 7 hours before → `cancelledByPlayer`, `lateCancellation == false`, slot free; cancel 2 hours before → `lateCancellation == true`; cancel after start throws `notCancellable`; price locked: changing the court's `basePrice` after confirm leaves `totalPrice` unchanged; `release` frees a held slot.
- [x] **Step 2:** Run → FAIL. Implement (active statuses for conflict checks: `held` with `holdExpiresAt > now`, `confirmed`, `completed`, `paid`, `noShow`). Run → PASS.

### Task 5: Games

**Files:**
- Create: `lib/domain/games.dart`
- Test: `test/domain/games_test.dart`

**Interfaces — Produces:**
- `class Player { id, name, Map<String, int> levels }`
- `class Game { id, sportId, cityId, venueId, hostId, DateTime start, DateTime end, int spots, int minLevel, int maxLevel, int? pricePerPlayer, String? bookingId, String? note, List<String> participantIds }` with `int get spotsLeft`, `bool get isFull`
- `enum JoinError { full, alreadyJoined, levelOutOfRange, notParticipant, hostCannotLeave }`; `class JoinException`
- `Game joinGame(Game game, Player player)`, `Game leaveGame(Game game, String playerId)` — return updated copies

- [x] **Step 1:** Write failing tests: joining adds the player and lowers `spotsLeft`; joining a full game throws `full` and participants never exceed spots; joining twice throws `alreadyJoined`; level 2 player on a 3–5 game throws `levelOutOfRange`; a player with no level for the sport is treated as level 1; leaving removes the player; host leaving throws `hostCannotLeave`; a non-participant leaving throws `notParticipant`.
- [x] **Step 2:** Run → FAIL. Implement. Run → PASS.

### Task 6: Translations

**Files:**
- Create: `lib/l10n/app_en.arb`, `lib/l10n/app_ru.arb`, `lib/l10n/app_uz.arb`
- Test: `test/l10n/arb_parity_test.dart`

- [x] **Step 1:** Write the failing test: read the three ARB files as JSON; the set of non-`@` keys is identical in all three; no value is empty; every placeholder name used in English (`{name}`) appears in the other two.
- [x] **Step 2:** Write the three files (Uzbek in Latin script with `ʻ` U+02BB; plurals with ICU `one/few/many/other` for Russian). Run `flutter gen-l10n`, then the test → PASS.

### Task 7: Sample data and repositories

**Files:**
- Create: `lib/data/repositories.dart`, `lib/data/sample/sample_data.dart`, `lib/data/sample/sample_repositories.dart`
- Test: `test/data/sample_repositories_test.dart`

**Interfaces — Produces:**
- `abstract class CatalogRepository { Future<List<Sport>> sports(); Future<List<Venue>> venues(String cityId); Future<Venue> venue(String id); Future<List<BannerItem>> banners(String cityId); Future<List<TournamentItem>> tournaments(String cityId); }`
- `abstract class BookingRepository { Future<List<SlotView>> availability(String venueId, String courtId, DateTime date); Future<Booking> hold(String venueId, String courtId, List<SlotTime> slots); Future<Booking> confirm(String bookingId, {int? players, String? note}); Future<void> release(String bookingId); Future<Booking> cancel(String bookingId); Future<List<Booking>> myBookings(); }`
- `abstract class GameRepository { Future<List<Game>> games(String cityId); Future<Game> game(String id); Future<Game> join(String id); Future<Game> leave(String id); Future<Player> player(String id); }`
- Sample implementations take `DateTime Function() clock` and the current user id.

- [x] **Step 1:** Write failing tests: each city has at least one venue and every venue's `cityId` matches; every court's `sportId` exists in `sports()`; every sample venue yields at least one slot on some day of the coming week; sample games reference existing venues and are not over capacity; a hold made through the sample repository shows as `mine` in `availability`.
- [x] **Step 2:** Run → FAIL. Implement (6 fictional venues: 3 Tashkent, 2 Almaty, 1 Astana; 5 sports; games and tournaments dated relative to the clock). Run → PASS.

### Task 8: App shell, session and onboarding

**Files:**
- Create: `lib/app.dart`, `lib/router.dart`, `lib/core/theme.dart`, `lib/state/session.dart`, `lib/state/providers.dart`, `lib/features/onboarding/onboarding_screen.dart`, `lib/features/shell/home_shell.dart`
- Modify: `lib/main.dart`
- Test: `test/app_smoke_test.dart`

**Interfaces — Produces:**
- `class SessionState { String? languageCode; String? cityId; String? userName; bool get onboarded; }`; `class SessionController extends Notifier<SessionState>` with `setLanguage`, `setCity`, `signIn(String name)`, `signOut`; persisted with `shared_preferences` keys `lang`, `city`, `user_name`
- Providers: `sessionProvider`, `catalogRepositoryProvider`, `bookingRepositoryProvider`, `gameRepositoryProvider`, `currentCityProvider`, `clockProvider`
- Routes: `/onboarding`, `/home`, `/venues`, `/venues/:id`, `/venues/:id/book/:courtId`, `/games`, `/games/:id`, `/profile`, `/profile/bookings`; redirect to `/onboarding` until `onboarded`

- [x] **Step 1:** Write the failing widget test: pump the app with empty preferences → onboarding shows the three language names (`Oʻzbekcha`, `Русский`, `English`); choose Русский, choose Ташкент, enter a name, continue → bottom navigation with the Russian tab labels is visible.
- [x] **Step 2:** Run → FAIL. Implement. Run → PASS.

### Task 9: Home, venues, booking, bookings, games, profile screens

**Files:**
- Create: `lib/features/home/home_screen.dart`, `lib/features/venues/venues_screen.dart`, `lib/features/venues/venue_screen.dart`, `lib/features/booking/booking_screen.dart`, `lib/features/bookings/bookings_screen.dart`, `lib/features/games/games_screen.dart`, `lib/features/games/game_screen.dart`, `lib/features/profile/profile_screen.dart`, `lib/features/common/widgets.dart`, `lib/features/common/formatters.dart`
- Test: `test/booking_flow_test.dart`

- [x] **Step 1:** Write the failing widget test: with a signed-in English session in Tashkent and a fixed clock, open a venue → Book → pick two adjacent free slots → Continue → summary shows the summed price with `soʻm`/`UZS` label → Confirm → "My bookings" lists the booking; a closed day shows the "closed" message.
- [x] **Step 2:** Run → FAIL. Implement the screens: home feed (banners, games, courts free today, tournaments), venue list with search and sport filter, venue profile, slot picker with date strip and court switcher, hold countdown, summary and confirm, bookings with cancel, games list and detail with join/leave, profile with language and city switch and sign out. Run → PASS.

### Task 10: Platform configuration and verification

**Files:**
- Modify: `android/app/src/main/AndroidManifest.xml` (label `Actra`), `ios/Runner/Info.plist` (`CFBundleDisplayName` = `Actra`, `CFBundleLocalizations` = `en`, `ru`, `uz`), `web/index.html`, `web/manifest.json` (title)

- [x] **Step 1:** `flutter analyze` → no issues.
- [x] **Step 2:** `flutter test` → all pass.
- [x] **Step 3:** `flutter build apk --debug` → `build/app/outputs/flutter-apk/app-debug.apk` exists.
- [x] **Step 4:** Run in a browser and click through onboarding → booking → cancel in each of the three languages.
