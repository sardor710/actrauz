# Actra — Build Roadmap

**Date:** 2026-11-22
**Product spec:** [docs/actra-product-spec.md](../../actra-product-spec.md) (source of truth for behaviour)
**First detailed plan:** [2026-11-22-actra-m1-foundation.md](2026-11-22-actra-m1-foundation.md)

This is the whole-product plan: what gets built, in what order, on what technology, and what has to be true before each stage is called done. Each milestone gets its own detailed task plan when it starts; Milestone 1's is linked above.

---

## 1. Decisions

| Decision | Made by | Note |
|---|---|---|
| Phone app in **Flutter**, one codebase for Android and iOS | Founder, 2026-11-22 | |
| Languages: **Uzbek (Latin), Russian, Kazakh (Cyrillic), English** | Founder, 2026-11-22; Kazakh added 2026-11-26 | Kazakh built in M6 as a draft; a native speaker reviews it before the Kazakhstan launch. |
| Markets: Uzbekistan and Kazakhstan (Tashkent, Almaty, Astana) | Founder (spec §3) | |
| Backend on **Supabase** (Postgres, auth, realtime, storage, edge functions) | Design call, accepted 2026-11-22 | Self-hostable later if data-localisation law requires in-country storage (spec §15.6). |
| App state with Riverpod, navigation with go_router, translations with Flutter's built-in ARB files | Design call | |
| Owner and admin panels as a **Flutter web app** sharing the booking logic with the phone app | Design call | Avoids writing slot and price rules twice. Revisit if the admin panel needs heavy tables and exports. |
| Money stored as whole units (UZS, KZT), never converted or summed across currencies | Spec §3, §12.1 | |
| Every scored padel or tennis game moves ratings; there is no rated/friendly switch | Founder, 2026-11-27 | Built in M7. Rated sports are padel and tennis; the admin switch is locked. Design: [2026-11-27-actra-m7-competitive-design.md](../specs/2026-11-27-actra-m7-competitive-design.md). |
| Times stored and shown in the venue's local time, offset per city, never hard-coded | Spec §3 | |

## 2. What the Playo analysis showed

Analysed: `Playo.apk` v9.4.1 (build 479), package `com.techmash.playo`, read statically with REA/JADX. Nothing was run and nothing is copied; this is a feature reference.

**How it is built:** native Android in Kotlin (no Flutter, no native libraries), 38,239 classes of which about 7,900 are Playo's own, 118 activities and roughly 630 screens. Third-party services: Juspay, Stripe, Paytabs, Instamojo and Amazon Pay for payments; Sendbird for chat; Firebase, CleverTap and OneSignal for push and analytics; Google Maps and Places; Google Fit; AdMob.

**Feature areas found, and what Actra does with each:**

| Playo area | Evidence (package) | Actra |
|---|---|---|
| Venue discovery, search, filters, map, gallery | `explore`, `modules.venue` | In scope (spec §7.4–7.5) |
| Slot booking: availability → checkout hold → confirm, cancel | `shared.booking` (`getBookingAvailability`, `postCheckoutSlots`, `createOrder`, `confirmOrder`, `cancelOrder`) | In scope (spec §7.6). Same hold-then-confirm shape. |
| Pay-at-venue ("offline") orders | `OfflineBookingCheckoutFragment`, `createOfflineOrder` | In scope; it is Actra's Phase 1 money model |
| Games ("activities"): create, join requests, invites, players, co-host | `modules.playoactivity`, `playoActivities` | In scope (spec §9) |
| Skill levels, player rating after a game, no-show reporting, "karma" | `gamebook`, `ratePlaypal`, `updatePlaypalNoShowStatus` | In scope (spec §8) |
| Groups ("squads") | `communities.squads` | In scope as Teams (spec §9.3) |
| Leaderboard | `modules.user.leaderboard` | In scope for padel and tennis (spec §8.2) |
| Guest browsing before sign-in | `onboardingV2.home.HomeGuestUserFragment` | **Not in spec.** Cheap to allow; recommended, decide in M2. |
| Reschedule a booking, extend a slot | `RescheduleSlotSelectionFragment`, `ExtendSlotDialog` | **Not in spec.** Candidate for after launch. |
| "Notify me" when a full slot frees up | `NotifyMeDialog`, `notifyUserForBooking` | **Not in spec.** Candidate for after launch. |
| Venue ratings | `VenueRatingBottomSheet` | **Not in spec.** Candidate for after launch. |
| Chat (1:1, group, per game) | `chat`, Sendbird | Out: spec non-goal |
| Wallet, credits, gift cards, coupons, passes, subscriptions | `modules.giftcard`, `modules.user.passbook`, `gametimeUnlocked` | Out for now |
| Expense splitting between players | `playoActivities.details.splitwise` | Out |
| Trainers and coaching marketplace | `trainerlisting`, `shared.trainer` | Out |
| Bulk and corporate booking | `modules.book.bulkbooking`, `modules.venue.corporatebooking` | Out |
| Google Fit goals, stories, ads | `modules.healthapi`, `modules.yip`, `services.ads` | Out |
| Tournaments | not present in Playo | In scope (spec §10), Actra's own |

## 3. Architecture

```
┌────────────────────┐   ┌──────────────────────────┐
│ Player app          │   │ Owner + Admin panel       │
│ Flutter (Android,   │   │ Flutter web               │
│ iOS)                │   │ calendar, pricing, admin  │
└─────────┬──────────┘   └────────────┬─────────────┘
          │      shared Dart package: models, slot generation, pricing
          └───────────────┬───────────────┘
                          ▼
┌──────────────────────────────────────────────────────────┐
│ Supabase                                                   │
│  Postgres   tables, row-level security, booking functions  │
│  Auth       session issued after Telegram phone share      │
│  Realtime   slot and game changes pushed to open screens   │
│  Storage    venue, court, banner and profile photos        │
│  Functions  Telegram bot webhook, push sender, scheduled   │
│             jobs (hold expiry, reminders, auto-complete)   │
└──────────────────────────────────────────────────────────┘
        Telegram Bot API            Firebase Cloud Messaging (push)
```

### 3.1 The rule that must never break: no double booking

The database enforces it, not the apps. Every hold and booking is a row with a time range, and Postgres refuses two active rows that overlap on the same court:

```sql
create extension if not exists btree_gist;

alter table bookings add constraint bookings_no_overlap
  exclude using gist (court_id with =, during with &&)
  where (status in ('held', 'confirmed', 'completed', 'paid', 'no_show', 'unverified'));
```

`during` is a `tstzrange`. App bookings and owner walk-ins write to the same table through the same functions (`hold_slots`, `confirm_booking`, `create_walk_in`, `cancel_booking`), so both sources are covered by one constraint. Expired holds are released by `hold_slots` itself before it inserts, and by a scheduled job. The in-app booking engine built in Milestone 1 implements the same rules in Dart for sample data; in Milestone 2 its tests are re-pointed at the database functions.

### 3.2 Repository layout

```
actra/
  docs/                      spec, plans
  app/                       player app (Flutter)
    lib/core/                markets, money, localized text, theme
    lib/domain/              models, slot generator, pricing, booking engine
    lib/data/                repository interfaces + sample-data implementation
    lib/features/            one folder per screen group
    lib/l10n/                app_en.arb, app_ru.arb, app_uz.arb
  panel/                     owner + admin web app          (from M3)
  packages/actra_core/       domain code shared by app and panel (extracted in M3)
  supabase/                  migrations, edge functions, seed data (from M2)
```

Screens talk to repository interfaces only. Milestone 1 ships a sample-data implementation; Milestone 2 adds the Supabase implementation behind the same interfaces, so no screen changes.

### 3.3 Translations

- Interface text: one ARB file per language. A test fails the build if any key is missing in any language (spec anti-goal: no mixed-language screens).
- Admin-entered content (venue descriptions, sport names, banners, tournament text): stored as one value per language, falling back to Russian then English when one is missing (spec §3).
- Dates, plurals and number grouping use each language's own rules.

## 4. Milestones

Order follows spec §16 option C: full player loop in Tashkent first, then Kazakhstan, then the competitive layer, then online payments.

| # | Milestone | Delivers | Done when |
|---|---|---|---|
| **M1** | **App foundation** *(this session)* | Flutter app in uz/ru/en; city and currency handling; onboarding; home feed; venue list and profile; full booking flow (slots, prices, hold, confirm, cancel) and games list/join on sample data | Tests pass; Android build succeeds; flows click through in all three languages |
| **M2** | **Backend + real sign-in** | Supabase project; schema and row-level security; booking functions with the overlap constraint; Telegram bot phone-share sign-in; Supabase implementation of the repositories; photos | Two phones booking the same slot at once: exactly one succeeds. Sign-in works end to end |
| **M3** | **Owner panel + admin basics** | Weekly calendar with walk-ins, cancel, paid/no-show; working hours; price configurator; owner dashboard; admin: venues, courts (with duplicate), owners, sports, banners | A venue runs a real week on the calendar without a paper schedule. **Tashkent venue pilot.** |
| **M4** | **Community core** | Available Games for all sport types, Game Requests, simple levels, reliability score, in-app notification inbox with push, find players, invites | **Public launch in Tashkent** |
| **M5** | **Tournaments (registration)** | Categories, pairs with partner accept, caps, waitlist, admin tournament manager, admin dashboard with revenue split | A tournament fills and closes a category correctly |
| **M6** | **Kazakhstan launch** | Almaty and Astana content, KZT, Kazakh language decision carried out, store listings | Live in both countries |
| **M7** | **Competitive layer** | Padel and tennis 1.0–7.0 ratings, score entry and confirmation, leaderboards, teams, sportsmanship | Ratings move after confirmed results |
| **M8** | **Online payments + brackets** | Click and Payme (UZ), Kaspi and Freedom (KZ), commission and payouts, refunds, tournament brackets and results | Paid booking and refund work per country |

Running alongside from M2: crash reporting, analytics events, CI that runs tests and builds on every change, store release pipeline.

## 5. Tools and accounts

| Need | State on 2026-11-22 |
|---|---|
| Flutter SDK | Installed at `D:\lab\flutter`, version 3.32.6 (July 2025). Works for M1. Upgrade to current stable before store release; left alone for now because other projects may share it. |
| JDK 17 | Installed at `D:\dev\jdk-17` for Android builds |
| Android SDK | Installed at `D:\dev\android-sdk` |
| iOS builds | **Not possible on this Windows PC.** Needs a Mac with Xcode, or a cloud build service such as Codemagic. Required from M2 for device testing. |
| Apple Developer account (99 USD/year), Google Play Console (25 USD once) | Needed before M4 |
| Supabase project | Needed at the start of M2 |
| Telegram bot (via BotFather) | Needed at the start of M2 |
| Firebase project (push only) | Needed in M4 |

## 6. Risks and open questions

1. **Apple sign-in rule.** If the iOS app offers Google sign-in, App Store review requires an equivalent option such as Sign in with Apple. Either add it or offer Telegram only on iOS. Decide in M2.
2. **Personal-data localisation** in Uzbekistan and Kazakhstan may require in-country storage. Supabase can be self-hosted; get legal advice before M4 (spec §15.6).
3. **Kazakh language:** decided 2026-11-26: added as the fourth language (Cyrillic) in M6. Needs a native-speaker review before launch.
4. **Pay-at-venue no-shows** can cost venue trust. Reliability rules arrive in M4, after the M3 pilot; during the pilot the three-active-bookings cap is the only guard.
5. **Phase 1 venue fee, Phase 2 commission, final cancellation windows, website scope, tournament organisers** (spec §15) remain open business questions.
6. **Telegram availability:** sign-in depends on one third-party service. Google sign-in is the fallback; SMS codes are a later option.
