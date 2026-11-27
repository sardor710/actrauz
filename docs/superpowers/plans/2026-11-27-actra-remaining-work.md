# Actra: what is left, from M8 to launch

Status on 2026-11-27. M1–M7 are built, deployed to the hosted Supabase project and pushed (`main` = dd5ea3e).
The roadmap ends at M8. After M8 comes the work the roadmap runs "alongside" (none of it is built yet) and the launch checklist.

Who does each item: **[me]** = I can build it, **[you]** = needs the founder (an account, money, a decision, a phone).

---

## 0. Owed right now (small)

1. [me] Build a fresh release APK from `main`. Old builds predate M6/M7 and break on newer data.
2. [you] Install it on a phone (uninstall any old debug build first) and do a short smoke test: sign-in, booking, a game, ratings questionnaire.
3. [you] Fix the categories of the 3 live sample tournaments in Admin → Tournaments (or hide them).
4. [me] Add a timeout to the app's `delete-account` call (a launch-checklist blocker).
5. [me] Write `e2e-tournaments.mjs` (live check for M5, never written; also needed for M8a).
6. [you] Rotate the Supabase keys that were pasted into chat.

## 1. M8a: tournament brackets and results (no outside dependencies)

1. [me] Design doc: draw formats, seeding, byes, tie-breaks in groups, who may enter scores.
2. [me] Database: draws, groups, rounds, matches, match courts/times, results.
3. [me] Draw generation per category: knockout (seeded by rating, byes) and groups → knockout.
4. [me] Match scheduling on the venue's courts; those slots are auto-blocked in the owner calendar.
5. [me] Score entry by admin/organiser; winners advance automatically; withdrawals and walkovers.
6. [me] Padel/tennis results feed ratings (reuses the M7 rating engine).
7. [me] Live bracket and group tables in the app; "my next match" for players; notifications.
8. [me] Admin tournament manager: generate/redo the draw, schedule, enter scores, close the tournament.
9. [me] Tests, reviews, browser walkthrough in four languages.
10. [you] Approve the deploy; [me] deploy and run the live checks.
11. [you] Approve merge/push; [me] fresh app build.

## 2. M8b: online payments (blocked on merchant agreements)

**Founder first (nothing goes live without these):**
1. [you] Merchant agreements with Click and Payme (Uzbekistan) and Kaspi and Freedom (Kazakhstan): registered company + bank account in each country; get API keys and sandbox access.
2. [you] Decide: commission rate, payout schedule, who pays provider fees, refund window (proposal: full refund if cancelled 24 h or more before the start; venue cancellations always fully refunded).

**Build (can start against sandboxes before the agreements are done):**
3. [me] Design doc: money flow, payment states (Pending payment, Refunded), what happens when a payment times out.
4. [me] Payments ledger in the database: every charge, refund, commission and payout recorded.
5. [me] One server-side function per provider (create payment, provider callback, check status, refund), secrets kept server-side only.
6. [me] Booking checkout: pay online, slot held while paying, released if payment fails or times out; per-venue "pay at venue allowed" switch.
7. [me] Games: each player pays their share when joining.
8. [me] Tournaments: spot confirmed only after payment; waitlist offers respect payment.
9. [me] Cancellations and refunds by the policy, through the provider's refund API.
10. [me] Owner panel: payouts and statements. Admin: commission settings, payout runs, reconciliation against provider reports.
11. [me] Tests, sandbox end-to-end checks per provider, reviews.
12. [you] Approve the deploy and switch each provider to live keys; a real small payment and refund per country.

## 3. Running alongside (in the roadmap, not built yet)

1. [you] Firebase project → [me] push notifications (the in-app inbox exists; phones don't get pushes yet). Update `data-safety.md`.
2. [me] Crash reporting (e.g. Sentry or Firebase Crashlytics).
3. [me] Analytics events (sign-up, booking, game join, tournament registration, payment).
4. [me] CI on GitHub: run backend and app tests and build the APK on every push.
5. [you] Decide the iOS build route (a Mac, or Codemagic) → [me] iOS build setup, location texts in four languages.
6. [me] Upgrade Flutter (3.32.6 is old) before the store release.

## 4. Launch (from `docs/store/launch-checklist.md`)

**Accounts and identity**
1. [you] Google Play Console account (25 USD). Apple Developer (99 USD/year) when iOS is ready.
2. [you] Confirm the final `applicationId` (now `uz.actra.actra`; it cannot change after the first upload).
3. [you] Back up the upload key in `D:\actra-keys` to two safe places.

**Legal**
4. [you] Legal advice on keeping personal data in Mumbai (data-localisation rules in KZ/UZ); this may force a move.
5. [you] Legal review of the privacy policy, write terms of use, fill every `<founder` placeholder (entity, address, e-mail).
6. [you] Retention rule for free text (reports, disputes, team texts) copied into the audit log.

**Content and checks**
7. [you] Native speaker checks the Kazakh texts (app, bot, store, site); a quick check of Uzbek and Russian store texts.
8. [you] Add real Almaty and Astana venues and owners; hide the samples (`hide-samples.mjs --apply`).
9. [you] Phone checks: real geolocation, account deletion, signing up again with the same phone.
10. [me] Live check of the `delete-account` function and its `verify_jwt` setting.

**Store**
11. [you] Choose where the website lives (GitHub Pages is cheapest; pages become public) → [me] publish it.
12. [you + me] Screenshots, feature graphic, final icon, Play data-safety form, content rating, reviewer sign-in route.
13. [me] Release build → [you] upload to Play (then the App Store).

## 5. Open decisions (founder)

- Should changing the city in the app header also move the player's leaderboard / Find-players city?
- Phase 1 venue fee (per-booking fee or subscription) and the free-cancellation window, if they go in the store text or terms.
- Order of M8a and M8b (my suggestion: brackets first, payments once the agreements are moving).
