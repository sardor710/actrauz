# Actra M6 — Kazakhstan Launch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Actra ready to go live in Almaty and Astana next to Tashkent: Kazakh as a fourth language, the player's city found from their location, sample venues kept away from real players, account deletion, and everything a first store submission needs that does not require a store account.

**Architecture:** Kazakh follows the pattern the roadmap set for a fourth language: one ARB file plus one `_kk` column per piece of admin-entered text, read through the existing `textOf`/`textJson` mappers and `LocalizedText`. City detection is a small `CityLocator` interface behind a provider, so tests and sample mode never touch real location. Account deletion is an edge function (it must change the auth user, which SQL cannot do safely) that calls one SQL function to cancel, withdraw and scrub, then renames and bans the auth user.

**Tech Stack:** Flutter 3.32.6 (Riverpod, go_router, ARB), Supabase (Postgres migrations, Deno edge functions), Node test runner with embedded Postgres, `geolocator` (new).

**Spec:** [docs/actra-product-spec.md](../../actra-product-spec.md) §3 (markets, languages, city detection), §15.6 (data localisation); roadmap M6 row in [2026-11-22-actra-roadmap.md](2026-11-22-actra-roadmap.md).

**Founder decisions for M6 (2026-11-26):**
- Add **Kazakh (Cyrillic)** as a fourth language. Translations are a draft; a native speaker reviews them before launch.
- **Hide the sample venues** in Kazakhstan (Alatau Padel & Tennis, Zhetisu Arena, Esil Sport Hub) and the sample Almaty tournament on the live project; the founder adds real venues through the admin screens.
- **No store accounts yet:** prepare everything that does not need one and hand over a checklist.
- **Detect the city from location**, falling back to a manual choice.

## Global Constraints

- Languages: `uz`, `ru`, `kk`, `en`. Kazakh code is `kk`, native name `Қазақша`, Cyrillic script.
- Fallback for admin-entered text: chosen language → `ru` → `en` → `uz` → `kk` (spec §3: "falling back to Russian then English").
- Every UI string exists in all four ARB files; `app/test/l10n/arb_parity_test.dart` enforces it.
- Money stays in whole UZS/KZT units, never converted or summed across currencies. Times stay in venue local time; both Kazakh cities keep `utc_offset_minutes = 300` (correct since Kazakhstan's 2024 switch to UTC+5).
- The database is live: migrations are **additive** (new nullable columns, widened checks, `create or replace`), deployed with `node scripts/deploy.mjs migrations`, never `db` (that reloads the seed and resets sample hours and prices).
- Old app builds keep calling the backend: no RPC loses or renames a parameter or an output key; new parameters get defaults.
- The GitHub repo is **public**: keystores, `key.properties`, `.env` and `env/*.json` never get committed.
- Tests: `npm test` in `supabase/` (embedded Postgres) and `flutter test` in `app/` both pass at the end of every task.

## Review Focus

1. **Location unavailable** — permission denied (once or forever), location services off, an 8-second timeout, or a browser that refuses geolocation: the city step shows the manual list with nothing preselected and no spinner left running. (Task 7 test `detection failure leaves manual choice`.)
2. **Deleting an account that is busy** — an upcoming booking inside the late-cancellation window, a hosted game with other players, a pending tournament partner invite, an open game request: deletion succeeds, the other people get their usual notifications, and nothing raises. (Task 4 test `deletes a busy account`.)
3. **Signing up again with the same phone after deletion** creates a new, empty account, not the scrubbed one. (Task 4 test `same phone after deletion gets a new account`.)
4. **A deleted player in someone else's history** (past game participants, owner calendar, tournament lists) shows as "Deleted player", never blank and never a crash. (Task 8 test `deleted player shows a placeholder name`.)
5. **Content entered only in Kazakh** (a venue an admin named only in the `kk` field) shows that Kazakh name in every language of the new app instead of an empty string. (Task 5 test `kazakh-only text falls back`.)

---

## File Structure

| File | Responsibility |
|---|---|
| `supabase/migrations/20261126100000_kazakh.sql` (new) | `_kk` columns, widened language checks and `*_named` checks, Kazakh city and sport names, every SQL function that lists languages redefined with `kk` |
| `supabase/migrations/20261126110000_launch.sql` (new) | games at inactive venues hidden; `profiles.deleted_at`; `app.delete_account`; `public.delete_account_service` |
| `supabase/functions/_shared/bot_texts.ts` | Kazakh bot messages |
| `supabase/functions/_shared/delete_account_core.ts` (new) + `.test.ts` | runtime-free deletion flow |
| `supabase/functions/delete-account/index.ts` (new) | Deno entry wiring the core to Supabase |
| `supabase/scripts/hide-samples.mjs` (new) | live data change: deactivate sample KZ venues and tournament |
| `supabase/scripts/e2e-kz.mjs` (new) | live check of a KZT booking on a throw-away Almaty venue |
| `app/lib/l10n/app_kk.arb` (new) | Kazakh UI strings |
| `app/lib/core/localized_text.dart`, `app/lib/core/markets.dart` | `kk` field; city coordinates and `nearestCity` |
| `app/lib/core/languages.dart` (new) | `kLanguageCodes`, `kLanguageNames` in one place |
| `app/lib/data/location/city_locator.dart` (new) | `CityLocator` interface, geolocator and fixed implementations |
| `app/lib/features/onboarding/onboarding_screen.dart` | detection on the city step |
| `app/lib/features/profile/delete_account.dart` (new) | delete-account confirmation flow |
| `app/android/app/build.gradle.kts`, `app/android/key.properties.example` (new) | release signing, target API 36 |
| `docs/store/` (new) | store listing texts, data-safety answers, launch checklist |
| `site/` (new) | privacy policy and account-deletion pages (static HTML) |

---

### Task 1: Kazakh in the database

**Files:**
- Create: `supabase/migrations/20261126100000_kazakh.sql`
- Modify: `app/tool/seed_sql.dart` (`_langCols` and every row writer), regenerate `supabase/seed.sql`
- Test: `supabase/tests/kazakh.test.mjs` (new), `app/test/data/seed_sql_test.dart`

**Interfaces:**
- Produces: columns `cities.name_kk`, `sports.name_kk`, `venues.{name,description,address,district}_kk`, `courts.name_kk`, `banners.{title,subtitle}_kk`, `tournaments.{title,description}_kk`, `tournament_categories.name_kk`; `'kk'` accepted by `profiles.language` and `login_tokens.language`; every localized JSON object built in SQL (`jsonb_build_object('uz', …)`) gains a `'kk'` key; admin save payloads accept `<field>_kk`.

- [ ] **Step 1: Write the failing tests** in `supabase/tests/kazakh.test.mjs` using the helpers the other test files use:
  - `kk columns exist`: for each column listed above, `information_schema.columns` has it, nullable, type `text`.
  - `profile accepts kk`: updating a profile's `language` to `'kk'` succeeds; `'kz'` fails the check. Same for `login_tokens.language`.
  - `admin saves kk text`: `app.admin_save_venue` with `{"city_id":"almaty","name_kk":"Алатау"}` (no other name) creates a venue whose `name_kk = 'Алатау'`; same round trip for court, sport, banner, tournament and category saves with their `_kk` fields.
  - `notification payloads carry kk`: the booking notification `court_name` and the tournament notification `title`/`category_name` objects have keys `uz, ru, kk, en`.
  - `tournament json carries kk`: `app.tournament_json` output has `title_kk`, `description_kk`, and each category has `name_kk`.
  - `kazakh city names`: `select name_kk from cities` gives `Ташкент`, `Алматы`, `Астана`.
- [ ] **Step 2: Run** `npm test -- kazakh` in `supabase/`. Expected: FAIL (columns missing).
- [ ] **Step 3: Write the migration.** Add the columns; drop and recreate `venues_named`, `courts_named`, `tournament_categories_named` (and any other `coalesce(name_uz, name_ru, name_en)` check) with `name_kk` added; widen both `language` checks to `('uz', 'ru', 'kk', 'en')`; update `name_kk` for the three cities and seven sports (`Футбол`, `Падел`, `Теннис`, `Баскетбол`, `Волейбол`, `Жүгіру`, `Жаттығу залы`). Then `create or replace` every function found by `grep -n "_en\b" supabase/migrations/*.sql` that lists languages, copying each from **the latest migration that defines it**, and adding `kk` next to `en`: the admin `c_spec` objects and the `update … set` lists in `admin_save_venue`, `admin_save_court`, `admin_duplicate_court` (`name_kk || ' 2'`), `admin_save_sport`, `admin_save_banner`, the admin tournament and category saves and copy in `20261125110000_admin_tournaments.sql`; the `jsonb_build_object('uz', …)` builders in `20261124100000_community_core.sql` and `20261125100000_tournaments.sql`; `app.tournament_json` and the line-951 builder; and the title sort in `list_tournaments` (`when 'kk' then t.title_kk`, fallback list gains `t.title_kk` last). Keep every signature unchanged.
- [ ] **Step 4: Add `_kk` to `app/tool/seed_sql.dart`** (`_langCols` returns four columns; rows write `LocalizedText.kk`, which Task 5 adds — until then write `null`), run `dart run tool/gen_seed.dart`, and update `seed_sql_test.dart` expectations.
- [ ] **Step 5: Run** `npm test` in `supabase/` and `flutter test test/data` in `app/`. Expected: all pass.
- [ ] **Step 6: Commit** `M6: Kazakh content columns and language in the database`.

### Task 2: Kazakh Telegram bot messages

**Files:**
- Modify: `supabase/functions/_shared/bot_texts.ts`
- Test: `supabase/functions/_shared/login_core.test.ts`

**Interfaces:**
- Produces: `Language = 'uz' | 'ru' | 'kk' | 'en'`; `botTexts.kk`.

- [ ] **Step 1: Write the failing tests:** `pickLanguage('kk')` and `pickLanguage('kk-KZ')` return `'kk'`; `pickLanguage('kz')` returns `'ru'`; a contact from a Telegram user with `language_code: 'kk'` whose token was started with language `kk` gets `botTexts.kk.done`.
- [ ] **Step 2: Run** the login core tests the way `npm test` runs them. Expected: FAIL.
- [ ] **Step 3: Add `kk` to `languages` and a full `kk` entry in `botTexts`** (same six messages, same safety warning in `askContact`; button text `📱 Нөмірімді жіберу`).
- [ ] **Step 4: Run** `npm test`. Expected: PASS.
- [ ] **Step 5: Commit** `M6: Kazakh bot messages`.

### Task 3: Keep hidden venues out of player lists, and hide the samples

**Files:**
- Create: `supabase/migrations/20261126110000_launch.sql` (this task adds the `list_games` part; Task 4 appends to the same file)
- Create: `supabase/scripts/hide-samples.mjs`
- Test: `supabase/tests/launch.test.mjs` (new)

**Interfaces:**
- Produces: `app.list_games` and `app.list_game_requests` (whatever function lists open requests) skip rows whose `venue_id` points to an inactive venue; games and requests without a venue are unaffected.

- [ ] **Step 1: Write the failing tests:** `games at inactive venue are hidden` — create an open game at seeded venue v4, set `venues.active = false`, `app.list_games(<other player>, 'almaty', now())` no longer returns it, but a participant still sees it in their own games; same for an open game request tied to v4; `place games stay listed` — a game with `venue_id null` in Almaty is still listed.
- [ ] **Step 2: Run** `npm test -- launch`. Expected: FAIL.
- [ ] **Step 3: `create or replace` `app.list_games`** (copy from `20261124110000_games_v2.sql:859`) adding `and (g.venue_id is null or exists (select 1 from public.venues v where v.id = g.venue_id and v.active))`, and the same condition in the request feed.
- [ ] **Step 4: Write `supabase/scripts/hide-samples.mjs`** using `env.mjs` and the Management API query helper `deploy.mjs` uses. Default run prints the rows it would change (`venues` `md5('actra:v4')`, `md5('actra:v5')`, `md5('actra:v6')` and `tournaments` `md5('actra:t3')`, with name and current `active`); `--apply` sets `active = false` on exactly those rows and writes an `audit_log` row per change with action `hide_sample`. It touches nothing in Tashkent. (Checked: the seeded sample games in Kazakhstan are all at v4–v6, so the venue filter hides them; the eight sample players have no city, so Find players does not list them by city.) It is run against the live project only at deploy time, with the founder's go-ahead.
- [ ] **Step 5: Run** `npm test`. Expected: PASS. Run `node scripts/hide-samples.mjs` (dry run, read-only). Expected: four rows listed, nothing changed.
- [ ] **Step 6: Commit** `M6: hide games at inactive venues; sample-hiding script`.

### Task 4: Account deletion (backend)

Both stores require in-app account deletion. Bookings and games reference profiles without cascading, and owners need their booking history, so the account is **scrubbed and closed**, not hard-deleted: personal data goes, anonymous history stays.

**Files:**
- Modify: `supabase/migrations/20261126110000_launch.sql`
- Create: `supabase/functions/_shared/delete_account_core.ts`, `supabase/functions/_shared/delete_account_core.test.ts`, `supabase/functions/delete-account/index.ts`
- Modify: `supabase/config.toml` (function entry, `verify_jwt = true`), `supabase/scripts/deploy.mjs` (deploy the new function with the other two)
- Test: `supabase/tests/launch.test.mjs`

**Interfaces:**
- Produces (SQL): `profiles.deleted_at timestamptz` (null = live account); `app.delete_account(p_user uuid, p_now timestamptz) returns void`; `public.delete_account_service(p_user uuid) returns void`, executable by `service_role` only, calling `app.delete_account(p_user, now())`. Raises `admin_account` if the user is in `public.app_admins`.
- Produces (edge function): `POST /functions/v1/delete-account` with the player's JWT → `200 {"status":"deleted"}`; `403 {"error":"admin_account"}`; `401` without a valid JWT.
- Produces (core): `deleteAccount(deps: DeleteDeps, accessToken: string): Promise<{status: 'deleted'} | {error: 'unauthorized' | 'admin_account'}>` where `DeleteDeps = { userIdFromToken(token): Promise<string | null>; scrub(userId): Promise<void>; closeAuthUser(userId): Promise<void> }`.

- [ ] **Step 1: Write the failing SQL tests** in `launch.test.mjs`:
  - `deletes a busy account`: a player with (a) a confirmed booking starting in 1 hour, (b) an open hosted game with one other participant, (c) a joined game hosted by someone else, (d) a pending join request, (e) an open game request they host, (f) a tournament registration waiting on them as partner and one they lead. After `app.delete_account`: (a) is `cancelled_by_player`; (b) is cancelled and the other participant has the usual game-cancelled notification; (c) no longer lists them; (d) withdrawn; (e) cancelled; (f) both cancelled with the usual notices; `profile_contacts`, `player_levels`, `venue_owners` and `notifications` rows for them are gone; `profiles.full_name` and `city_id` are null and `deleted_at` is set. Nothing raises, including for the booking inside the late-cancellation window.
  - `delete is idempotent`: a second call does nothing and does not raise.
  - `admin cannot self-delete`: raises `admin_account` and changes nothing.
  - `sole owner can delete`: a player who is the only owner of a venue can delete; the venue stays (an admin assigns a new owner) and an `audit_log` row `owner_account_deleted` names the venue.
  - `deleted players are invisible`: a deleted player is absent from Find players and cannot be invited to a game or team (the invite call raises `not_found`).
  - `service only`: `authenticated` cannot execute `public.delete_account_service`.
  - `deleted_at is readable`: `profiles` has a column-level grant (`20261124100000_community_core.sql:25`); the migration adds `deleted_at` to it, and a `select *` on `profiles` as `authenticated` still succeeds.
- [ ] **Step 2: Run** `npm test -- launch`. Expected: FAIL.
- [ ] **Step 3: Implement `app.delete_account`** by calling the existing functions so every side effect (notifications, freed slots, waitlist offers) happens as usual: `app.host_cancel_game(p_user, id, false, p_now)` for hosted open games, `app.cancel_booking` for upcoming `held`/`confirmed` bookings, `app.leave_game(p_user, id, p_now)`, `app.withdraw_join_request`, `app.cancel_game_request`, `app.withdraw_interest`, `app.cancel_registration`. Where one of them refuses because of a timing rule (late leave, past deadline), make the same state change directly rather than skipping it; never use a blanket `exception when others`. Then delete the rows listed in the test and scrub the profile. Add `public.delete_account_service` with grants.
- [ ] **Step 4: Run** `npm test`. Expected: PASS.
- [ ] **Step 5: Write the failing core tests** in `delete_account_core.test.ts`: unknown token → `{error:'unauthorized'}` and no scrub; scrub throwing `admin_account` → `{error:'admin_account'}` and `closeAuthUser` not called; happy path calls `scrub` then `closeAuthUser` in that order; `closeAuthUser` failing after a successful scrub rethrows (the client retries and both steps are idempotent).
- [ ] **Step 6: Implement the core and `delete-account/index.ts`.** `closeAuthUser` uses `auth.admin.updateUserById(id, { email: 'deleted-<id>@deleted.actra.invalid', ban_duration: '876000h', app_metadata: { phone: null, deleted: true } })`. Renaming the e-mail is what makes Review Focus 3 hold: sign-in looks users up by `loginEmail(phone)`, so the old account can no longer be found. Add a core test `same phone after deletion gets a new account` against the fake deps in `login_core.test.ts`: after `closeAuthUser`, `users.create` for the same phone produces a different user id. Partial failure (scrub done, auth close failed, person signs in again before retrying): `users.findByPhone` finds nothing because `profile_contacts` is gone, and the `generateLink` fallback in `supabase_deps.ts` would revive the scrubbed user; guard it — when the fallback finds a user whose profile has `deleted_at` set, close that user (same `closeAuthUser`) and create a fresh one. Test it with the fake deps. The real path is proven live in Task 11.
- [ ] **Step 7: Run** `npm test`. Expected: PASS.
- [ ] **Step 8: Commit** `M6: account deletion backend`.

### Task 5: Kazakh UI strings

**Files:**
- Create: `app/lib/l10n/app_kk.arb`
- Modify: `app/test/l10n/arb_parity_test.dart` (check `['ru', 'uz', 'kk']`)

**Interfaces:**
- Produces: `AppLocalizations.supportedLocales` includes `Locale('kk')` (generated by `flutter gen-l10n`).

- [ ] **Step 1: Change the parity test** to loop over `['ru', 'uz', 'kk']`. Run `flutter test test/l10n`. Expected: FAIL (file missing).
- [ ] **Step 2: Write `app_kk.arb`** with every key of `app_en.arb` (606 messages) in Kazakh Cyrillic, `"@@locale": "kk"`, same placeholders, ICU plurals as `{count, plural, =1{…} other{…}}` (Kazakh nouns after numbers stay singular). `currencyUzs` is `сом`; `currencyKzt` is `₸`. Keep sport and venue terms consistent with Task 1's names. Translate in batches by feature prefix so nothing is skipped; no Russian or English left in any value except brand names (Actra, Telegram).
- [ ] **Step 3: Run** `flutter gen-l10n` and `flutter test test/l10n`. Expected: PASS. Run `flutter test test/ui` to catch overflow from longer strings. Expected: PASS.
- [ ] **Step 4: Commit** `M6: Kazakh UI strings (draft for native review)`.

### Task 6: Kazakh wired through the app

**Files:**
- Create: `app/lib/core/languages.dart`
- Modify: `app/lib/core/localized_text.dart`, `app/lib/data/supabase/mappers.dart` (`textOf`, `textJson`), `app/lib/data/supabase/supabase_catalog_repository.dart:52` (add `name_kk`), `app/lib/state/session.dart`, `app/lib/features/onboarding/onboarding_screen.dart`, `app/lib/features/profile/profile_screen.dart`, `app/lib/features/admin/localized_field.dart`, `app/lib/data/sample/sample_data.dart` (city and sport `kk` names), `app/tool/seed_sql.dart`
- Test: `app/test/core/core_test.dart`, `app/test/data/supabase_mappers_test.dart`, `app/test/data/admin_mappers_test.dart`, `app/test/data/sample_backend_test.dart`, `app/test/domain/tournaments_test.dart`, `app/test/app_flow_test.dart`

**Interfaces:**
- Consumes: `app_kk.arb` (Task 5); `_kk` columns and `'kk'` payload keys (Task 1).
- Produces: `LocalizedText({String? uz, String? ru, String? kk, String? en})`; `const kLanguageCodes = ['uz', 'ru', 'kk', 'en']` and `const kLanguageNames = {'uz': 'Oʻzbekcha', 'ru': 'Русский', 'kk': 'Қазақша', 'en': 'English'}` in `languages.dart` (removed from `session.dart` and `onboarding_screen.dart`, imports updated).

- [ ] **Step 1: Write the failing tests:**
  - `core_test.dart` `kazakh-only text falls back`: `LocalizedText(kk: 'Алатау').resolve(c)` is `'Алатау'` for `c` in `uz, ru, kk, en`; `LocalizedText(ru: 'А', kk: 'Ә').resolve('kk')` is `'Ә'`; `LocalizedText(ru: 'А', en: 'B').resolve('kk')` is `'А'`.
  - mappers: `textOf` reads `name_kk`; `textJson('name', LocalizedText(kk: ' Ә '))` has `name_kk: 'Ә'`; the admin mapper loop at `admin_mappers_test.dart:153` covers `kk`.
  - sample backend and tournaments: payload maps contain `kk` (update the `containsAll` lists at `sample_backend_test.dart:525`, `tournaments_test.dart:160` and `:576`).
  - flow: choosing `Қазақша` at onboarding shows the city step title from `app_kk.arb`, and the profile language picker lists four languages.
  - admin: `LocalizedField` renders inputs keyed `name-kk`; saving a venue with only the Kazakh name succeeds.
- [ ] **Step 2: Run** `flutter test`. Expected: the new tests FAIL.
- [ ] **Step 3: Implement.** `resolve` uses the order `[code, 'ru', 'en', 'uz', 'kk']`. `LocalizedField` shows four inputs: a 2×2 grid when `maxWidth >= 560` (uz | ru, kk | en), stacked otherwise. Sample payload builders add `kk`. `seed_sql.dart` writes `LocalizedText.kk` now that it exists; regenerate `seed.sql` and confirm it only differs by `kk` values.
- [ ] **Step 4: Run** `flutter test` and `npm test` (seed). Expected: PASS.
- [ ] **Step 5: Commit** `M6: Kazakh language through the app and admin editors`.

### Task 7: City from location

**Files:**
- Modify: `app/pubspec.yaml` (add `geolocator`, newest version that resolves on Flutter 3.32.6), `app/lib/core/markets.dart`, `app/lib/state/providers.dart`, `app/lib/features/onboarding/onboarding_screen.dart`, all four ARB files, `app/android/app/src/main/AndroidManifest.xml` (`ACCESS_COARSE_LOCATION` only), `app/ios/Runner/Info.plist` (`NSLocationWhenInUseUsageDescription`: "Actra uses your location once to pick your city.")
- Create: `app/lib/data/location/city_locator.dart`
- Test: `app/test/core/core_test.dart`, `app/test/onboarding_location_test.dart` (new)

**Interfaces:**
- Produces: `City.latitude`, `City.longitude` (`tashkent` 41.2995, 69.2401; `almaty` 43.2389, 76.8897; `astana` 51.1694, 71.4491); `City? nearestCity(double lat, double lng, {double maxKm = 150})` (great-circle distance; null when no city is within `maxKm`); `abstract class CityLocator { Future<String?> detectCityId(); }` with `GeolocatorCityLocator` (asks permission once, low accuracy, 8-second timeout, any error or denial → null) and `FixedCityLocator(String? cityId)`; `cityLocatorProvider` returning `FixedCityLocator(null)` when no backend is compiled in (tests, sample mode) and `GeolocatorCityLocator` otherwise.

- [ ] **Step 1: Write the failing tests:** `nearestCity(41.31, 69.28)` → `tashkent`; `nearestCity(43.22, 76.85)` → `almaty`; `nearestCity(51.13, 71.43)` → `astana`; `nearestCity(39.65, 66.96)` (Samarkand) → null. Widget tests overriding `cityLocatorProvider`: `detected city is preselected` — `FixedCityLocator('almaty')` shows a "Found: Almaty" hint and the Almaty tile selected, without advancing until tapped; `detection failure leaves manual choice` — a locator that throws, and one that never completes within the test's pumped 9 seconds, both end with no tile selected, no progress indicator, and all three cities tappable.
- [ ] **Step 2: Run** `flutter test test/core test/onboarding_location_test.dart`. Expected: FAIL.
- [ ] **Step 3: Implement.** On first entry to the city step, if no city is chosen yet, call `detectCityId()` once (timeout enforced by the screen too, so a hung plugin cannot hold the spinner); while waiting show a `detectingCity` row above the list; on a result preselect it and show `cityDetected(city)`; tapping any tile still sets the city and advances. Never ask again after a denial. New strings `detectingCity`, `cityDetected` in all four ARB files.
- [ ] **Step 4: Run** `flutter test`. Expected: PASS. Run `flutter build apk --debug` to confirm the plugin builds on this Flutter. Expected: success.
- [ ] **Step 5: Commit** `M6: detect the player's city from location`.

### Task 8: Account deletion (app)

**Files:**
- Create: `app/lib/features/profile/delete_account.dart`
- Modify: `app/lib/data/auth/auth_repository.dart` (+ sample and Supabase implementations), `app/lib/features/profile/profile_screen.dart`, the mapper(s) that read `full_name` for other players, all four ARB files
- Test: `app/test/features/delete_account_test.dart` (new), `app/test/data/supabase_mappers_test.dart`

**Interfaces:**
- Consumes: `POST delete-account` (Task 4).
- Produces: `Future<void> AuthRepository.deleteAccount()` throwing `AdminAccountException` on `admin_account`; Supabase implementation calls `client.functions.invoke('delete-account')` then signs out; sample implementation signs out. Session state after deletion is the same as after sign-out (language and city kept).

- [ ] **Step 1: Write the failing tests:** `delete account asks before deleting` — Profile → "Delete account" opens a dialog listing what happens (upcoming bookings cancelled, games left, name and phone removed, cannot be undone); Cancel changes nothing; Confirm calls `deleteAccount` and lands on onboarding's sign-in step. `admin sees why not` — `AdminAccountException` shows `deleteAccountAdmin`. `deleted player shows a placeholder name` — a participant / booking / registration row whose profile has `deleted_at` set (the signal; a null `full_name` alone means "has not finished sign-in") renders as `deletedPlayer`; the SQL JSON builders that return other players' names add `"deleted": true` for such rows (extend Task 4's migration), and the app reads that key ("Deleted player" / "Удалённый игрок" / …) in a game's participant list and the owner booking sheet.
- [ ] **Step 2: Run** them. Expected: FAIL.
- [ ] **Step 3: Implement**, with strings `deleteAccount`, `deleteAccountTitle`, `deleteAccountBody`, `deleteAccountConfirm`, `deleteAccountAdmin`, `deletedPlayer` in all four ARB files. The button sits at the bottom of the profile/settings list in the error colour.
- [ ] **Step 4: Run** `flutter test`. Expected: PASS.
- [ ] **Step 5: Commit** `M6: delete account in the app`.

### Task 9: Android release setup

**Files:**
- Modify: `app/android/app/build.gradle.kts`, `.gitignore` (`app/android/key.properties`, `*.jks`, `*.keystore`), `app/pubspec.yaml` version stays `1.0.0+1`
- Create: `app/android/key.properties.example`, `app/tool/build_release.cmd`

**Interfaces:**
- Produces: `flutter build appbundle --release --dart-define-from-file=env/dev.json` signs with the upload key when `app/android/key.properties` exists, and falls back to debug signing (with a Gradle warning) when it does not, so tests and dev builds keep working.

- [ ] **Step 1: Set `compileSdk = 36` and `targetSdk = 36`** (Google Play requires API 36 for new apps since 2026-08-31). Run `flutter build apk --debug`. If the Android Gradle Plugin or a plugin refuses API 36 on Flutter 3.32.6, install the current stable Flutter **side by side** at `D:\dev\flutter-stable` (never touch `D:\lab\flutter`), build with it, re-run the full `flutter test` on it, and record the version in the plan's status. Expected: success with one of the two.
- [ ] **Step 2: Add the release signing config** reading `storeFile`, `storePassword`, `keyAlias`, `keyPassword` from `key.properties`; `key.properties.example` documents the four keys with placeholder values.
- [ ] **Step 3: Generate the upload keystore** with `D:\dev\jdk-17\bin\keytool` at `D:\actra-keys\actra-upload.jks` (outside the repo), alias `upload`, a random 24-character password written only to `app/android/key.properties` (git-ignored) and `D:\actra-keys\README.txt`. Confirm `git status` does not show either file.
- [ ] **Step 4: Write `app/tool/build_release.cmd`** that runs `flutter build appbundle --release --dart-define-from-file=env/dev.json` and prints the `.aab` path. Run it. Expected: `build/app/outputs/bundle/release/app-release.aab` exists; `keytool -printcert -jarfile` on it shows the upload certificate, not the debug one.
- [ ] **Step 5: Commit** `M6: Android release signing and target API 36` (no key material in the diff).

### Task 10: Store texts, privacy policy, launch checklist

**Files:**
- Create: `docs/store/listing.md`, `docs/store/data-safety.md`, `docs/store/launch-checklist.md`, `site/index.html`, `site/privacy.html`, `site/delete-account.html`

- [ ] **Step 1: Write `listing.md`**: app name (≤ 30 characters), short description (≤ 80), full description (≤ 4000) in uz, ru, kk and en; category (Sports); contact e-mail left as `<founder to fill>`; screenshot list (which screens, phone size) for both countries. A small script or test is not needed; count characters with a one-liner and note the counts next to each text.
- [ ] **Step 2: Write `data-safety.md`**: Play data-safety and App Store privacy answers from what the app actually collects — phone number (account), name, approximate location (city choice, not stored on the server), app activity (bookings, games), no ads, no data sold, deletion in-app and on the web page; encryption in transit.
- [ ] **Step 3: Write the `site/` pages**: plain static HTML in four languages with a language switcher, no external scripts or trackers. `privacy.html` covers what is collected, why, where it is stored (Supabase, region ap-south-1), retention, deletion, contact. `delete-account.html` explains in-app deletion and a request route for people without the app (contact placeholder). Mark the privacy text as a draft for legal review.
- [ ] **Step 4: Write `launch-checklist.md`**, split into "built and verified" and "founder owns": Play Console (25 USD) and Apple Developer (99 USD/year) accounts; hosting `site/` (GitHub Pages on the public repo is the cheapest; needs the founder's go-ahead); native-speaker review of `app_kk.arb` and `botTexts.kk`; legal advice on personal-data localisation in Kazakhstan and Uzbekistan (the project is in ap-south-1, spec §15.6); real Almaty and Astana venues and owners through Admin; running `hide-samples.mjs --apply`; iOS build route (Mac or Codemagic); Firebase project for push; back up `D:\actra-keys`; the final `applicationId` before first upload (it can never change afterwards).
- [ ] **Step 5: Commit** `M6: store listing, data safety, privacy and deletion pages, launch checklist`.

### Task 11: Live checks, docs and handover

**Files:**
- Create: `supabase/scripts/e2e-kz.mjs`
- Modify: `docs/superpowers/plans/2026-11-22-actra-roadmap.md` (decision row: Kazakh added 2026-11-26; risk 3 closed), this plan's status section

- [ ] **Step 1: Write `e2e-kz.mjs`** with `e2e-lib.mjs`: as service role create a throw-away Almaty venue ("E2E KZ <timestamp>") with one court priced 12 000, sign in a throw-away player, hold and confirm a slot tomorrow at 18:00 Almaty time, check the booking's `currency = 'KZT'`, `total_price = 12000` and that its wall-clock start reads `18:00`, set the player's language to `kk`, then delete the booking, venue, court and player. It notifies no real owner.
- [ ] **Step 1b: Extend the live checks for deletion:** in a second script section, sign in a throw-away player with `dev-login.mjs`'s flow, call the deployed `delete-account` function, sign in again with the same phone, and assert a different user id and that the old auth user is banned with the renamed e-mail. Clean up both users.
- [ ] **Step 2: Whole-branch review** (fresh reviewer on the full diff against this plan), fix findings, re-run `npm test` and `flutter test`.
- [ ] **Step 3: Browser walkthrough in sample mode** (new preview entry `actra-m6`, port 5661): onboarding in Қазақша → Almaty → home, venue, booking with ₸ prices, admin venue editor with four language inputs, delete-account dialog. Screenshots attached to the report. Then one pass in the live-backend web build (`run_web.cmd`), where `GeolocatorCityLocator` is real: allow location → a city is preselected (or "no nearby city" from this PC's location), deny → manual list. If it cannot be exercised, the report says so.
- [ ] **Step 4: With the founder's go-ahead:** `node scripts/deploy.mjs migrations`, `node scripts/deploy.mjs functions`, `node scripts/e2e-kz.mjs`, `node scripts/e2e-community.mjs`, then `node scripts/hide-samples.mjs --apply`.
- [ ] **Step 5: Update the roadmap and this plan's status; commit** `Plan: M6 status`. Merge and push only when the founder asks.

---

## Status

Not started. Worktree `D:\actra\.worktrees\m6-kazakhstan`, branch `m6-kazakhstan` from `main` ba3ad17.
