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
| Padel and tennis rating, rated-game count, match scores and who confirmed or disputed them (with an optional dispute reason) | Matching players by skill, leaderboards | Supabase | Other players see the rating, the leaderboard position and the scores of games; a dispute reason is seen by the game's players and admins |
| Thumbs up / down given to other players, "didn't show up" marks | Sportsmanship score, reliability | Supabase | Nobody sees who gave them; other players see only the share of thumbs up once a player has 5 votes |
| Reports about a player's behaviour (reason and optional free text) | Moderation | Supabase | Admins only; the reported player is not told who reported them |
| Teams: name, description, membership, captain | Teams feature | Supabase | Other players (teams and their members are visible in the app) |
| Notifications | In-app inbox | Supabase | Nobody |
| Audit log of owner/admin actions | Accountability for staff accounts | Supabase | Admins |
| Approximate location | Suggest the nearest city once during onboarding | Device only: used on the phone, never sent or stored on the server | Nobody |

Not collected: e-mail address, passwords, payment or card data, contacts, photos, files, advertising id, precise location, device identifiers for analytics. No ads, no analytics or crash-reporting SDK, no data sold. Push notifications do not exist yet.

## Google Play — Data safety form

**Data collection and security**
- Does the app collect or share any of the required user data types? **Yes**
- Is all of the user data collected by the app encrypted in transit? **Yes** (HTTPS)
- Do you provide a way for users to request that their data be deleted? **Yes** — in the app (Profile → Delete account) and on the web (`delete-account.html`, URL to be entered in Play Console). Deletion removes the phone number, Telegram link, levels and the player's notifications, and removes the name from the profile and the player's own notes (booking notes, notes and meeting points of games they host, notes and areas of their game requests). Since M7 deletion also removes the player's ratings and rating history, the thumbs up/down and "didn't show up" marks they gave, their team memberships (a team they captain passes to its longest-standing member or is removed), closes the reports they sent and deletes the reports' text and any dispute reason they wrote; scores still waiting for confirmation are cancelled, and scores already confirmed stay for the other players without the name. Anonymous booking and game history stays for venues. Notifications already delivered to other people may still show the name (it is part of the message, written when the action happened); the privacy policy and the deletion page say so.
- Data sharing: **Yes — name and phone number are declared as SHARED** with venue owners (independent businesses), purpose: app functionality (so the venue can confirm and honour the booking). The backend provider Supabase acts as a service provider on our behalf and is not declared as sharing. The privacy policy says the same. Legal check of this declaration is on the launch checklist.
- Independent security review: No.

**Data types collected** (all "collected"; name and phone number also "shared" with venue owners)

| Play category | Data type | Collected | Purpose | Required or optional |
|---|---|---|---|---|
| Personal info | Name | Yes, and **shared** with venue owners | App functionality, account management | Required |
| Personal info | Phone number | Yes, and **shared** with venue owners | Account management, app functionality | Required |
| Personal info | User IDs (Telegram user id, account id) | Yes | Account management | Required |
| App activity | Other user-generated content / in-app actions (bookings, games, game requests, tournament registrations, levels, ratings and match scores, thumbs up/down, "didn't show up" marks, reports about players with optional free text, teams and their descriptions, reliability) | Yes | App functionality (reports: also safety and moderation) | Required for those features; votes, reports, teams and score entry are optional |
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
- Contact Info: Name, Phone Number (both visible to the owner of a venue you book at; Apple's label has no separate "shared" flag, so state it in the privacy policy and review notes)
- Identifiers: User ID
- User Content / Usage Data: app activity (bookings, games, game requests, tournament registrations, ratings and match scores, thumbs up/down and "didn't show up" marks, reports about players, teams). User-written text now exists in three more places: a score dispute reason, a report's details and a team's name and description ("Other User Content").

Not collected: Location (approximate location stays on the device), Contacts, Financial info, Health, Browsing history, Search history, Purchases, Diagnostics, Advertising data.

- Data used to track you: **No** (no tracking, no App Tracking Transparency prompt needed).
- Account deletion: in-app deletion exists (Profile → Delete account), as App Store guideline 5.1.1(v) requires.
- Location permission text (iOS `NSLocationWhenInUseUsageDescription`): required once an iOS build exists; `<to write with the iOS build — in four languages>`.
- Sign-in: the app uses Telegram phone sharing instead of Sign in with Apple; the app does not use a third-party social login from Apple's list, but confirm guideline 4.8 with the reviewer notes at submission.
- Privacy policy URL: `<founder: hosted URL of site/privacy.html>`.
- Review notes: explain the Telegram sign-in and give a reviewer account (`<founder>`).
