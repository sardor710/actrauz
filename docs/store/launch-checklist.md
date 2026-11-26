# Launch checklist

Status as of the M6 (Kazakhstan) branch. The founder has no store accounts yet.

## 1. Built and verified (in the repo)

- Four languages (uz Latin, ru, kk Cyrillic, en) in the app, with an ARB parity test; Almaty and Astana added with KZT and venue-local time (UTC+5).
- Telegram sign-in through the bot (@actraapp); no passwords.
- City detection once during onboarding, on the device only; manual list when location is unavailable (tests cover denied, off, timeout).
- Delete account in the app (Profile → Delete account), with tests for busy accounts, same phone signing up again, and "Deleted player" placeholders for other people.
- Kazakh-only admin content falls back to the Kazakh text in every language.
- Android release signing configured and target API 36 (`app/android`); signing keys are outside the repo.
- Store texts in four languages (`listing.md`), data-safety answers (`data-safety.md`), and the static site (`site/index.html`, `privacy.html`, `delete-account.html`) with the privacy text marked as a draft.
- `npm test` in `supabase/` and `flutter test` in `app/` pass.

## 2. Deploy order (do not reorder)

1. **Launch migration first**: `node scripts/deploy.mjs migrations` (never `db`; that reloads the seed and resets sample hours and prices). The new app reads `profiles.deleted_at`, so a build must never reach users before this migration is live.
2. **Edge functions second**: `delete-account`, `telegram-login`, `telegram-webhook` (the deletion function depends on `delete_account_service` from the migration).
3. **App builds last**: upload to Play (and later the App Store) only after steps 1 and 2.

## 3. Live checks still pending (need the live backend or a real phone)

- [ ] `delete-account` edge function against the live project: after deletion the auth user is renamed and banned (rename + ban actually applied).
- [ ] `verify_jwt` on the live project matches `supabase/config.toml`: `delete-account` true (valid user JWT required), `telegram-login` and `telegram-webhook` false. Try calling `delete-account` without a token and expect 401.
- [ ] Real geolocation on a physical Android phone: permission prompt, nearest city suggested for Tashkent, Almaty and Astana, and the denied / off / timeout paths show the manual list with no spinner left.
- [ ] Sign in with the same phone after deleting an account, on the live project: a new, empty account.

## 4. Native-speaker review needed (Kazakh drafts)

Kazakh was drafted without a native review. Have a native speaker (polite register, Cyrillic) check:

- [ ] `app/lib/l10n/app_kk.arb` (all app strings)
- [ ] `botTexts.kk` in `supabase/functions/_shared/bot_texts.ts` (Telegram bot messages)
- [ ] The Kazakh texts in `docs/store/listing.md` and the Kazakh sections of `site/privacy.html`, `site/delete-account.html`, `site/index.html`
- [ ] Also check Uzbek and Russian store texts once; the uz texts follow the app's `ʻ` (U+02BB) apostrophe style.

## 5. Founder owns

**Accounts and money**
- [ ] Google Play Console developer account (25 USD, one time).
- [ ] Apple Developer Program (99 USD per year) — only when the iOS build is ready.
- [ ] Decide the iOS build route: a Mac, or a cloud builder such as Codemagic.
- [ ] Firebase project for push notifications (push is not implemented yet; the in-app inbox is all there is today). Re-do `data-safety.md` when push is added.

**Identity of the app**
- [ ] Confirm the final `applicationId` before the first upload. It is `uz.actra.actra` today (`app/android/app/build.gradle.kts`) and can never change after the first Play upload.
- [ ] Back up the upload key at `D:\actra-keys` (keystore and `key.properties`) to at least two safe places. If it is lost, Play needs a reset request. **Never commit it: the repo is public.** `.env` and `env/*.json` also never go in the repo.

**Legal**
- [ ] Legal advice on personal-data localisation in Kazakhstan and Uzbekistan. The Supabase project is in ap-south-1 (Mumbai, India), and spec §15.6 lists this as an open question; it may force a change of storage location.
- [ ] Legal check of the data-safety declaration that name and phone number are SHARED with venue owners (Play Data safety, purpose app functionality; the Apple label and privacy text must say the same).
- [ ] Legal review of `site/privacy.html`; then remove the "draft" marking. Also terms of service (the app asks users to accept "Terms of use and Privacy policy"; the terms text does not exist yet).
- [ ] Fill every placeholder: contact e-mail, legal entity name, postal address, last-updated date, backup / retention wording. Search the repo for `<founder` to find them all. Use a business address, not a personal one.

**Website**
- [ ] Decide where to host `site/` (GitHub Pages on the public repo is the cheapest; needs the founder's go-ahead because the pages become public). Play and the App Store need the privacy-policy URL and (Play) the account-deletion URL.

**Data**
- [ ] Add real Almaty and Astana venues and owners through Admin.
- [ ] Run `node scripts/hide-samples.mjs --apply` (in `supabase/`) to hide the sample venues, games and tournaments before launch; check the app afterwards.
- [ ] Set Phase 1 venue fee and cancellation windows (spec §15.1, §15.3) if they are to be shown in the store text or terms.

**Store submission**
- [ ] Take the screenshots listed in `listing.md` (after the real venues and `hide-samples`).
- [ ] Feature graphic (1024 x 500) and the final icon.
- [ ] Fill the Play Data safety form and content rating from `data-safety.md`; give reviewers a test sign-in route (the bot sign-in needs a Telegram account).
- [ ] iOS only: location usage description in four languages, App Privacy answers, review notes.
