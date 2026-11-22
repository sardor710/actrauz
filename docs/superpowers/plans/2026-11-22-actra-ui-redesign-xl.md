# Actra UI Redesign — XL Plan

> Managed by `/vibe`. This file is the single spec and progress tracker. Execute with `superpowers:executing-plans`. Update the markers and Progress block on every state change.

## Progress
| Status | Wave | Done | Last updated | Next action |
|---|---|---|---|---|
| Done | 8 | 29/29 (task 5.4 dropped by approved revision) | 2026-11-22 | User: decide on commit and on merging with Milestone 2; restyle onboarding after that merge |

Status values: `Draft – requirement` → `Draft – plan` → `Executing` → `Done` | `Done – partial` | `Blocked`
Markers: `[ ]` pending · `[~]` in progress · `[x]` done (+evidence) · `[!]` blocked (+reason) · `[-]` dropped

## 1. Requirement
- **Goal:** Make the Actra app look full, modern and polished instead of sparse, following the layout of the nine Playo reference screenshots, and deliver a new Android APK.
- **Deliverables:**
  1. Redesigned screens: Home, Games, Venues, Tournaments, Social, Profile, plus restyled venue page, slot picker, booking summary and My bookings.
  2. A design system in code: colours, type, spacing, shared components.
  3. Bundled sample imagery: about 12 venue and banner photos, 3D sport icons, a brand font.
  4. Translations for every new string in `uz`, `ru`, `en`.
  5. `app-debug.apk` built from the redesigned code.
- **Decisions from the interview (2026-11-22):**
  - Pictures: free-licence stock photos bundled in the app.
  - Main colour: green like the reference.
  - Tabs: Home, Games, Venues, Tournaments, Social. Profile opens from the avatar at the top.
- **Constraints:**
  - Layout follows the references; Playo's name, logo, photos, illustrations and copy are not used. The app is branded Actra.
  - Light theme only for now (the references are light; the current dark look is part of what reads as empty).
  - Work happens in a git worktree on branch `ui-redesign`, because the Milestone 2 session is editing the main checkout at the same time.
  - `app/lib/data/repositories.dart`, `app/lib/data/sample/sample_repositories.dart`, `app/lib/state/session.dart` and `app/lib/domain/**` are not changed (Milestone 2 depends on them). New data needs go in new files.
  - Every image and font has a recorded source and licence in `app/assets/CREDITS.md`.
  - All existing behaviour keeps working: onboarding, booking with hold and confirm, cancel, join and leave a game, language and city switch.
- **Non-goals:** backend work; trainers, chat, gift cards, coupons, wallet, karma, fit goals (not in the Actra spec); dark theme; real venue data; iOS build.
- **Assumptions:**
  - Downloads approved by this plan: photos from Unsplash or Pexels (about 3 MB), the Manrope font from its official repository (OFL licence, about 0.5 MB), and Microsoft Fluent Emoji 3D icons (MIT licence, about 0.3 MB).
  - Buttons for features that arrive in later milestones (create a game, notifications, tournament registration) show a "Coming soon" message rather than being hidden, so the screens match the reference layout.
  - Player counts, teams and levels shown on Social and Profile are sample data, labelled as such on the sign-in screen as today.
- **Open questions:** none.

## 2. Acceptance
| ID | Criterion (verifiable) | Mode (auto/manual) | Check |
|---|---|---|---|
| A1 | No analyzer issues | auto | `flutter analyze` → "No issues found" |
| A2 | All tests pass, including the click-through flows updated for the new navigation and new tests for favourites and the games sport filter | auto | `flutter test` → "All tests passed" |
| A3 | Every UI string exists in all three languages | auto | `flutter test test/l10n` |
| A4 | Android debug APK builds | auto | `flutter build apk --debug` → `build/app/outputs/flutter-apk/app-debug.apk` |
| A5 | No Playo name or asset in the app | auto | `grep -ril playo app/lib app/assets` → no output |
| A6 | Every bundled image and font is listed with source and licence | auto | each file in `app/assets/**` appears in `app/assets/CREDITS.md` |
| A7 | Each redesigned screen, at phone size, shows no overflow stripes, clipped text or empty placeholder blocks, in `uz` and `ru` | manual | browser screenshots of the 6 tabs/screens per language |
| A8 | An independent UI review against the reference screenshots has no unresolved blocking finding | manual | `ui-finish-gate-reviewer` report |

Manual spot checks: book two slots and cancel; join and leave a game; switch language and city from the profile; favourite a venue and filter by favourites.

## 3. Anti-drift
- **Primary objective:** when the user opens the new APK, the screens look as rich and modern as the references and follow their structure.
- **Proxy signals (not success by themselves):** tests passing, the APK building, the analyzer being clean, the number of widgets or screens added.
- **Intended scope:** visual layer and navigation of the player app, plus the sample content needed to fill it.
- **Completion target:** full delivery of all listed screens.

## 4. Modules and skill map
| Module | Outcome | Skill / agent (role) | Write scope | Depends on |
|---|---|---|---|---|
| M1 | Worktree, bundled assets, design system and shared components | `agent_direct` (owner) | `app/assets/**`, `app/pubspec.yaml`, `app/lib/core/theme.dart`, `app/lib/features/common/**` | – |
| M2 | Sample content for the new screens (photos per venue, teams, favourites) | `agent_direct` (owner), `superpowers:test-driven-development` (support) | `app/lib/data/sample/sample_media.dart`, `app/lib/data/social.dart`, `app/lib/state/ui_providers.dart`, `app/test/**` | M1 |
| M3 | Shell, Home and Games | `agent_direct` (owner) | `app/lib/router.dart`, `app/lib/features/shell/**`, `home/**`, `games/**` | M1, M2 |
| M4 | Venues, venue page, booking flow, My bookings | `agent_direct` (owner) | `app/lib/features/venues/**`, `booking/**`, `bookings/**` | M1, M2 |
| M5 | Tournaments, Social, Profile, onboarding restyle | `agent_direct` (owner) | `app/lib/features/tournaments/**`, `social/**`, `profile/**`, `onboarding/**` | M1, M2 |
| M6 | Translations and tests brought in line | `agent_direct` (owner) | `app/lib/l10n/*.arb`, `app/test/**` | M3–M5 |
| M7 | Independent design review and fixes | `ui-finish-gate-reviewer` (verifier), `agent_direct` (owner of fixes) | files named in findings | M6 |
| M8 | Verification and APK | `superpowers:verification-before-completion` (owner) | `app/build/**` | M7 |

Why one owner: every screen shares the theme, the translation files and the router, so the write scopes overlap; splitting screens across parallel agents would produce merge conflicts and an uneven look. The independent agent is used where it adds most: reviewing the result against the references.

Gaps (no fitting skill): the requested "taste" skill is not installed on this machine; design judgement is covered by the design system in M1 and the independent review in M7.

Waves (serial; scopes overlap):
- Wave 1: M1
- Wave 2: M2
- Wave 3: M3
- Wave 4: M4
- Wave 5: M5
- Wave 6: M6
- Wave 7: M7
- Wave 8: M8

## 5. Tasks

All paths are relative to the worktree `D:\actra\.worktrees\ui-redesign\`.

### Design reference (decisions the tasks rely on)
- **Colours:** primary green `#10B560`; ink `#1D2A2F`; muted text `#6B7A80`; page background `#F1F3F2`; cards white; time pill blue `#1F6BFF`; scarcity pill amber `#FFB020` on ink text; banner call-to-action lime `#C8F542`; error `#E5484D`.
- **Type:** Manrope. Greeting 22/700, section title 15/800 uppercase with 0.4 letter spacing, card title 17/700, body 14/500, caption 12/500.
- **Shape:** cards radius 20 with a 1 px `#E7EBEA` border and no shadow; pills radius 999; buttons radius 14, height 52; page gutter 16.
- **Header (all tabs):** avatar circle with the player's initial, "Hey {name}" with a waving-hand icon, city name with a chevron (opens the city picker), then bell and calendar icons (calendar opens My bookings).
- **Bottom bar:** five destinations, icon above label, selected item in primary green with a bold label, white background, hairline top border.

### M1 — Foundation (wave 1, owner: `agent_direct`)
- [x] 1.1 Create the worktree: `git worktree add .worktrees/ui-redesign -b ui-redesign`, add `.worktrees/` to `.git/info/exclude`, run `flutter pub get` there — verify: `flutter test` passes in the worktree (62 tests).
  - Evidence: worktree `.worktrees/ui-redesign` on branch `ui-redesign`; baseline `flutter test`: 62 passed
- [x] 1.2 Download Manrope static weights 500, 600, 700, 800 to `app/assets/fonts/` and register the family in `pubspec.yaml` — verify: files exist; a widget test renders text with `fontFamily: 'Manrope'`.
  - Evidence: `assets/fonts/Manrope.ttf`, 164 KB. Deviation: the static weight files were not at the planned URL, so the variable font from google/fonts is used and weights are set on the `wght` axis in `manrope()`; rendering checked in the browser
- [x] 1.3 Download Fluent Emoji 3D icons (soccer ball, tennis, ping pong, basketball, volleyball, waving hand, trophy) to `app/assets/icons/` — verify: 7 PNG files, each under 100 KB.
  - Evidence: 7 PNGs in `assets/icons/`, 32–47 KB each
- [x] 1.4 Choose and download 12 photos (6 venues, 3 banners, 3 tournaments) at 1200 px wide JPEG to `app/assets/photos/`; look at each one before keeping it — verify: 12 files, each under 350 KB, none showing a recognisable brand logo.
  - Evidence: 12 JPEGs in `assets/photos/`, 77–322 KB; each viewed; the first padel photo showed a club sign and was replaced
- [x] 1.5 Write `app/assets/CREDITS.md` with file, source URL, author and licence for every asset — verify: A6 check.
  - Evidence: `assets/CREDITS.md`; test `every bundled file is credited` passes
- [x] 1.6 Rewrite `lib/core/theme.dart`: `buildTheme()` (light), `AppColors`, `AppText` per the design reference; `app.dart` uses the light theme only — verify: `flutter analyze`.
  - Evidence: `lib/core/theme.dart` rewritten; `flutter analyze`: No issues found
- [x] 1.7 Rebuild `lib/features/common/widgets.dart` into shared components: `AppHeader`, `SectionCard` (titled white card), `PhotoBox` (rounded asset image with fallback colour), `SportBadge` (3D icon), `InfoPill`, `AvatarStack`, `PrimaryButton`, `FilterChipButton`, keeping `AsyncBody`, `EmptyState`, `showMessage` — verify: `flutter analyze`; widget test that `PhotoBox` shows its fallback when the asset is missing.
  - Evidence: `lib/features/common/widgets.dart` and `app_header.dart`; test `a missing photo shows the placeholder` passes

### M2 — Sample content (wave 2, owner: `agent_direct`, support: `superpowers:test-driven-development`)
- [x] 2.1 `lib/data/sample/sample_media.dart`: `String venuePhoto(String venueId)`, `String bannerPhoto(String bannerId)`, `String tournamentPhoto(String id)`, `String sportIconAsset(String sportId)` — verify test: every sample venue, banner, tournament and sport maps to a file that exists on disk.
  - Evidence: `lib/data/sample/sample_media.dart`; test `every sample venue, banner, tournament and sport has its image` passes
- [x] 2.2 `lib/data/social.dart`: `class Team { id, name, sportId, cityId, memberCount, upcomingGames }`, `abstract class SocialRepository { Future<List<Team>> teams(String cityId); Future<List<Player>> players(String cityId); }`, and `SampleSocialRepository` with 6 fictional teams — verify test: each city has at least one team; every team's sport exists.
  - Evidence: `lib/data/social.dart`; both tests in group `teams` pass
- [x] 2.3 `lib/state/ui_providers.dart`: `favouritesProvider` (set of venue ids, toggle), `gamesSportFilterProvider`, `gamesDayProvider`, `socialRepositoryProvider`, `teamsProvider`, `playersProvider` — verify test: toggling a favourite twice returns to the original set.
  - Evidence: `lib/state/ui_providers.dart`; test `toggling adds, then removes` passes

### M3 — Shell, Home, Games (wave 3, owner: `agent_direct`)
- [x] 3.1 `router.dart` and `shell/home_shell.dart`: five branches `/home`, `/games`, `/venues`, `/tournaments`, `/social`; `/profile` and `/profile/bookings` become top-level routes above the shell; custom bottom bar per the design reference — verify: updated navigation test finds the five tab labels in `ru`.
  - Evidence: five-tab shell and top-level `/profile`, `/bookings`; test `onboarding: … the five tabs in Russian` passes
- [x] 3.2 `home/home_screen.dart`: header, search bar (opens Venues with focus on search), photo banner carousel with headline and call-to-action pill, "Games by sports" card with 3D icons (tap sets the games sport filter and opens Games), "Your go-to venues" horizontal photo tiles, "Free courts today", tournaments strip — verify: widget test taps a sport and lands on Games filtered to it.
  - Evidence: `home_screen.dart`; tests `the home screen renders in Uzbek with every section` and `a sport on Home opens Games filtered to it` pass; seen in the browser
- [x] 3.3 `games/games_screen.dart` and `games/game_card.dart`: banner, month label plus day strip, filter chips (sport, level), game cards with blue time pill, avatar stack, "{n}/{spots} going", amber "Only {n} slot" pill when two or fewer remain, "{host}'s {sport} game" title, venue and level bar, floating "Create new game" button (Coming soon) — verify: widget test picks a day with no games and sees the empty state.
  - Evidence: `games_screen.dart`, `game_card.dart`; test `a day with no games shows the empty state` passes; seen in the browser
- [x] 3.4 `games/game_screen.dart`: photo header, info rows, player list restyled; join and leave unchanged — verify: existing join/leave test passes.
  - Evidence: `game_screen.dart`; test `join and leave a game` passes

### M4 — Venues and booking (wave 4, owner: `agent_direct`)
- [x] 4.1 `venues/venues_screen.dart`: search bar, chip row (sort, sport, favourites), large photo cards with "Bookable" tag, heart toggle, sport icons on the photo, name, district, "Price starting from … onwards" row — verify: widget test favourites a venue, turns the favourites filter on, and sees only that venue.
  - Evidence: `venues_screen.dart`; test `favourite a venue, then filter by favourites` passes; seen in the browser
- [x] 4.2 `venues/venue_screen.dart`: photo header with back and heart, title block, about, address and phone rows, hours card, amenities, court cards with price and Book button — verify: existing booking flow test passes.
  - Evidence: `venue_screen.dart`; booking flow test passes; seen in the browser
- [x] 4.3 `booking/booking_screen.dart`, `booking/booking_summary_screen.dart`, `bookings/bookings_screen.dart`: restyle with the new components; logic unchanged — verify: existing booking, hold-release, closed-day and cancel tests pass.
  - Evidence: restyled through the theme, plus receding unavailable slots and the new back route; the four booking tests pass; slot picker seen in the browser

### M5 — Tournaments, Social, Profile, onboarding (wave 5, owner: `agent_direct`)
- [x] 5.1 `tournaments/tournaments_screen.dart`: photo cards with sport icon, title, venue, dates, entry fee, "X of Y filled" bar, "Full" state — verify: widget test shows the Tashkent tournaments and the full one marked full.
  - Evidence: `tournaments_screen.dart`; test `tournaments show the city's events and mark the full one` passes; seen in the browser
- [x] 5.2 `social/social_screen.dart`: "Discover teams" circles with an upcoming-games badge, "Players near you" list with level and sport, invite card (Coming soon) — verify: widget test shows teams for the selected city only.
  - Evidence: `social_screen.dart`; test `social shows teams of the selected city and players` passes; seen in the browser
- [x] 5.3 `profile/profile_screen.dart`: stats card (games joined, bookings, late cancellations from this run), "My sports" chips with levels, menu card (My bookings, Language, City, Sign out) — verify: existing language and city switching still works in a widget test.
  - Evidence: `profile_screen.dart`; test `profile opens from the avatar and switches language and city` passes
- [-] 5.4 `onboarding/onboarding_screen.dart`: photo hero and restyled choices; steps unchanged — verify: existing onboarding test passes.
  - Not done: dropped by revision approved by the user on 2026-11-22 ("Yes, leave it"). The Milestone 2 session rewrote `onboarding_screen.dart` on `main` for real sign-in, so this screen carries the new colours and font only and is restyled after that work is merged.

### M6 — Translations and tests (wave 6, owner: `agent_direct`)
- [x] 6.1 Add every new string to `app_en.arb`, `app_ru.arb`, `app_uz.arb`; remove unused keys — verify: `flutter test test/l10n`.
  - Evidence: 35 keys added to the three ARB files (136 each); `flutter test test/l10n`: passed
- [x] 6.2 Update `test/app_flow_test.dart` for the new navigation; add the new tests named above — verify: `flutter test` all pass.
  - Evidence: `flutter test`: 75 passed (13 flow tests, 8 new content tests)

### M7 — Independent design review (wave 7, verifier: `ui-finish-gate-reviewer`)
- [x] 7.1 Capture phone-size browser screenshots of Home, Games, Venues, a venue page, Tournaments, Social and Profile in `uz` and `ru` to the scratchpad.
  - Evidence: phone-size browser captures of Home, Games, Venues, venue page, slot picker, Tournaments, Social and Profile in `uz`; Home and Games also in `ru`. Deviation: kept as the browser tool's capture files rather than copied to the scratchpad
- [x] 7.2 Dispatch `ui-finish-gate-reviewer` with the reference screenshots, the new screenshots and section 1 of this plan; it returns findings ranked blocking / should-fix / nit.
  - Evidence: `ui-finish-gate-reviewer` read all 19 images and returned 11 findings: 1 blocking (slot picker still sparse), 6 should-fix, 4 nits. Verdict: HOLD until findings 1–4 are fixed
- [x] 7.3 Fix every blocking finding and the should-fix ones that take under ten minutes each; re-capture the affected screens — verify: A7 and A8.
  - Evidence: fixed: 1 slot picker rebuilt (venue header, morning/afternoon/evening groups, always-visible Continue bar, theme tokens); 2 padel line icon is now a racket; 3 profile chevrons aligned; 4 courts moved to the top of the venue page and identical hours collapsed; 5 banner carousel added to Venues; 7 sports shown as one swipeable row; 8 Games banner has a button; 9 Home and Venues show the same from-price. Re-captured the slot picker, venue page and profile in `ru`. Not fixed, listed under Result: 3D padel icon is still a table-tennis paddle; Social player rows have no action and use letter avatars; no distance on cards; nits 10 and 11

### M8 — Verification and delivery (wave 8, owner: `superpowers:verification-before-completion`)
- [x] 8.1 Run A1–A6 and record the output summaries here.
  - Evidence: A1 `flutter analyze`: No issues found. A2 `flutter test`: 75 passed. A3 `test/l10n`: passed (141 keys in each of three files). A5 `grep -ril playo lib assets`: no output. A6 test `every bundled file is credited`: passed
- [x] 8.2 Build the APK and record its path, size and time.
  - Evidence: `build/app/outputs/flutter-apk/app-debug.apk` in the worktree, built after the last code change
- [x] 8.3 Commit on branch `ui-redesign` only if the user asks; tell the Milestone 2 session which files changed.
  - Evidence: nothing committed (not asked); the Milestone 2 session was told which files changed
- [x] 8.4 Fill Result and Handoff.
  - Evidence: Result and Handoff filled in below

## 6. Verification
Run in `D:\actra\.worktrees\ui-redesign\app`:
- `flutter analyze`
- `flutter test`
- `flutter build apk --debug`
- `grep -ril playo lib assets`

## 7. Rollback
All work is on branch `ui-redesign` in its own worktree; `main` and the Milestone 2 session's uncommitted files are never touched. To discard: `git worktree remove .worktrees/ui-redesign` and `git branch -D ui-redesign`.

## Blockers
| Task | Reason | Question / needed | Since |
|---|---|---|---|

## Revisions
- 2026-11-22: requirement and plan drafted together after the interview.
- 2026-11-22: plan approved by the user ("Approve, build it").
- 2026-11-22: task 5.4 dropped during execution to avoid a conflict with Milestone 2; confirmed by the user ("Yes, leave it").
- 2026-11-22: task 1.2 used the variable Manrope file instead of four static weights (source URL differed).

## Result
- **Delivered:** redesigned Home, Games, Venues, venue page, slot picker, Tournaments, Social and Profile; five-tab navigation with the profile behind the avatar; a design system in `lib/core/theme.dart` and `lib/features/common/`; 12 photos, 7 icons and the Manrope font with `assets/CREDITS.md`; 40 new strings in `uz`, `ru`, `en`; `app-debug.apk` (108.0 MB, built Nov 22 16:40) at `D:\actra\.worktrees\ui-redesign\app\build\app\outputs\flutter-apk\`.
- **Checks run:** `flutter analyze` clean; `flutter test` 75 passed; APK built; no Playo name or asset in `lib` or `assets`; every asset credited; screens viewed at phone size in a browser in `uz` and `ru`; independent review run and its blocking finding fixed.
- **Gaps:** A7 was checked on eight screens in `uz` but only on Home, Games, slot picker, venue page and Profile in `ru`, and not on an Android device. A8: the reviewer was not re-run after the fixes, so its HOLD verdict is answered by my own re-check, not by a second independent pass. The 3D padel icon is a table-tennis paddle because the icon set has no padel racket. Social player rows are a plain list with letter avatars. Cards show no distance because the app has no location yet. Onboarding (task 5.4) has the new colours and font only.
- **Follow-ups:** merge `ui-redesign` with the Milestone 2 work on `main` (both touch `pubspec.yaml`, the ARB files, `app_flow_test.dart` and the router area); a real padel icon; an Actra-specific accent so the pills differ from Playo’s; dark theme.

## Handoff
All waves are finished; task 5.4 (onboarding restyle) was dropped with the user’s approval and should be done after the Milestone 2 merge. The work is uncommitted in the worktree `D:\actra\.worktrees\ui-redesign` on branch `ui-redesign` (based on `380ba40`). Next action: the user decides whether to commit, then the branch is merged with the Milestone 2 changes on `main`, where conflicts are expected in `pubspec.yaml`, the three ARB files and `test/app_flow_test.dart`. Run it with `tool\run_web.cmd` in the worktree’s `app` folder. `main` and the Milestone 2 session’s files were not touched, apart from one added entry in `.claude/launch.json`.
