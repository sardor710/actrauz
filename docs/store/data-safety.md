# Data safety (Google Play) and App Privacy (App Store)

Answers for the current app (pay at the venue, in-app inbox only). Re-check this file before each store submission and whenever an SDK or feature is added (payments, push notifications, analytics, crash reporting each change the answers).

## What the app collects

| Data | Why | Stored where | Shared with |
|---|---|---|---|
| Phone number | Account sign-in (via the Actra Telegram bot) | Supabase (ap-south-1) | Venue owners see it for bookings at their venue |
| Telegram user id | Links the Telegram chat to the account | Supabase | Nobody |
| Name | Shown to other players and venue owners | Supabase | Other players, venue owners |
| Chosen city, language | App setup | Supabase | Nobody |
| Levels per sport, reliability score and events | Matching players, reliability | Supabase | Other players see level and reliability |
| Bookings, games joined/hosted, game requests, tournament registrations | The app's features | Supabase | Venue owners (their venue's bookings); other players (game participants) |
| Notifications | In-app inbox | Supabase | Nobody |
| Audit log of owner/admin actions | Accountability for staff accounts | Supabase | Admins |
| Approximate location | Suggest the nearest city once during onboarding | Device only: used on the phone, never sent or stored on the server | Nobody |

Not collected: e-mail address, passwords, payment or card data, contacts, photos, files, advertising id, precise location, device identifiers for analytics. No ads, no analytics or crash-reporting SDK, no data sold. Push notifications do not exist yet.

## Google Play — Data safety form

**Data collection and security**
- Does the app collect or share any of the required user data types? **Yes**
- Is all of the user data collected by the app encrypted in transit? **Yes** (HTTPS)
- Do you provide a way for users to request that their data be deleted? **Yes** — in the app (Profile → Delete account) and on the web (`delete-account.html`, URL to be entered in Play Console).
- Data sharing: **No data shared with third parties** in the Play sense (the backend provider Supabase acts as a service provider on our behalf; venue owners and players seeing a name is a feature of the app, disclosed in the privacy policy). Confirm this reading with legal advice.
- Independent security review: No.

**Data types collected** (all "collected", none "shared", none optional except where noted)

| Play category | Data type | Collected | Purpose | Required or optional |
|---|---|---|---|---|
| Personal info | Name | Yes | App functionality, account management | Required |
| Personal info | Phone number | Yes | Account management, app functionality | Required |
| Personal info | User IDs (Telegram user id, account id) | Yes | Account management | Required |
| App activity | Other user-generated content / in-app actions (bookings, games, game requests, tournament registrations, levels, reliability) | Yes | App functionality | Required for those features |
| Location | Approximate location | **No** (processed on the device only to suggest a city; never leaves the phone, so it is not "collected" under Play's definition) | n/a | Optional |
| Financial info | Any | No | n/a | n/a |
| Messages, photos, files, contacts, calendar, health | Any | No | n/a | n/a |
| Device or other IDs / Diagnostics | Any | No | n/a | n/a |

Advertising: the app does not contain ads. Data is not used for advertising or marketing. Data is not sold.

Other Play declarations
- Target audience: 13+ / general (not designed for children).
- App access: login needs the Telegram bot; provide Play review with a test account (`<founder: reviewer test phone / instructions>`). Never put real credentials in the repo.
- Permission declared in the manifest: `ACCESS_COARSE_LOCATION` (city suggestion, once).
- Account deletion: both the in-app path and the web URL must be filled in (Play requirement).

## Apple — App Privacy ("nutrition label") and review notes

Data **linked to the user**, used for **App Functionality** only (none used for tracking):
- Contact Info: Name, Phone Number
- Identifiers: User ID
- User Content / Usage Data: app activity (bookings, games, game requests, tournament registrations)

Not collected: Location (approximate location stays on the device), Contacts, Financial info, Health, Browsing history, Search history, Purchases, Diagnostics, Advertising data.

- Data used to track you: **No** (no tracking, no App Tracking Transparency prompt needed).
- Account deletion: in-app deletion exists (Profile → Delete account), as App Store guideline 5.1.1(v) requires.
- Location permission text (iOS `NSLocationWhenInUseUsageDescription`): required once an iOS build exists; `<to write with the iOS build — in four languages>`.
- Sign-in: the app uses Telegram phone sharing instead of Sign in with Apple; the app does not use a third-party social login from Apple's list, but confirm guideline 4.8 with the reviewer notes at submission.
- Privacy policy URL: `<founder: hosted URL of site/privacy.html>`.
- Review notes: explain the Telegram sign-in and give a reviewer account (`<founder>`).
