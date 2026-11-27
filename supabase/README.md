# Actra backend (Supabase)

Everything the phone app talks to: the database schema and rules, the sample content, and Telegram sign-in.

```
supabase/
  migrations/     schema, row-level security, booking and game functions
  seed.sql        sample content, GENERATED from app/lib/data/sample/sample_data.dart
  functions/      telegram-login, telegram-webhook, delete-account (Deno edge functions)
  scripts/        deploy.mjs, e2e.mjs, e2e-owner.mjs, e2e-community.mjs, e2e-kz.mjs, e2e-delete.mjs,
                  e2e-ratings.mjs, e2e-teams.mjs
  tests/          database tests (Node + a throw-away Postgres, no Docker)
  .env            your secrets (git-ignored); .env.example is the template
```

## One-time setup

1. Create a project at supabase.com. Note the database password.
2. In Telegram, ask **@BotFather** for a bot (`/newbot`) and keep the token.
3. Copy `.env.example` to `.env` and fill it in. Each line says where to find its value.
4. From this folder:

```powershell
npm install --cache D:\actra\.npm-cache
```

```powershell
node scripts/deploy.mjs
```

`deploy.mjs` applies the migrations, loads the sample content, sets the function secrets, deploys both functions, points the bot's webhook at the project, and writes `app/env/dev.json` so the Flutter app uses the project. It can be run again at any time; each part can also be run alone (`db`, `migrations`, `seed`, `functions`, `telegram`, `app`).

Migrations and the seed go through Supabase's HTTPS API, not the database port, because port 5432 is not reachable from every network. Each applied migration is recorded in `supabase_migrations.schema_migrations`, the table `supabase db push` uses, so the two agree.

Then run the app against the project:

```powershell
cd ..\app; flutter run --dart-define-from-file=env/dev.json
```

Without `--dart-define-from-file` the app runs on built-in sample data with the demo sign-in.

## Commands

| Command | What it does |
|---|---|
| `npm test` | Database and sign-in tests on a throw-away local Postgres. No account, no Docker. |
| `node scripts/deploy.mjs` | Bring the hosted project up to date (see above). |
| `node scripts/deploy.mjs migrations` | Apply new migrations only. Use this instead of `db` once venue owners edit hours and prices: the sample content resets them for the sample venues. |
| `node scripts/deploy.mjs seed` | Reload sample content; re-dates the sample games and tournaments from today. |
| `node scripts/e2e.mjs` | Sign in two throw-away accounts through the real functions, book a slot, check the row in the database, check the second account is blocked, clean up. |
| `node scripts/e2e-owner.mjs` | The same for venue owners and admins: a throw-away admin creates a venue and court and assigns an owner; the owner adds a walk-in and a block, changes prices and reads the dashboard; a plain player is refused throughout; everything made is deleted again. |
| `node scripts/e2e-community.mjs` | The same for games and the community: a throw-away admin creates a throw-away venue and court, a throw-away host books it and makes a game on it, a second account asks to join and is approved, the inbox is read, paged and marked read, an invite-only run stays invisible to a third account until it is invited, a Game Request gets an "I'm in" and is converted, finding players returns no phone numbers and respects "hidden", reliability reads back; everything made is deleted again and existing accounts are never changed. |
| `node scripts/e2e-kz.mjs` | Kazakhstan: a throw-away Almaty venue (no owners, so nobody real is notified) with a court at 12 000, a throw-away player holds and confirms tomorrow 18:00 Almaty time, the booking must be KZT, 12 000 and read 18:00 on the wall clock, the player is set to Kazakh, everything is deleted. Run it after `deploy.mjs migrations`. |
| `node scripts/e2e-delete.mjs` | Account deletion: a throw-away player calls the deployed `delete-account` function (expects 200 `{"status":"deleted"}`), calls it again with the old token and prints that status (200 or 401 are fine, a 5xx fails), signs in again with the same phone and must get a different user id; the old auth user must be renamed `deleted-<id>@<sign-in domain>`, banned and free of the phone's digits (read with the admin API and `SUPABASE_SECRET_KEY`); both users are deleted. Run it after `deploy.mjs migrations` and `deploy.mjs functions`. |
| `node scripts/e2e-ratings.mjs` | Ratings (M7): a throw-away admin creates a throw-away venue `E2E M7 <timestamp>` with a padel court; four throw-away players answer the padel questionnaire, the host books the court and makes an invite-only game rated 1-7 and invites the other three, who join; the script moves that one game and its booking into the past (by their ids, through the Management API) and runs `app.complete_games(now())` (which, like the scheduled job, also completes any other game that has ended); the host enters the score, an opponent confirms, and it checks the winners' ratings rose and the losers' fell, the leaderboard lists all four, each has a `rating_updated` notification, a thumbs up is stored and an abuse report shows in the admin review until the admin closes it; everything made is deleted, and anything left fails the run. **Precondition:** `sports.competitive_rating` must be true for padel and tennis on the live project (the M7 migration does not set it); the script checks this read-only first and stops without creating anything if not. Run it after `deploy.mjs migrations`. |
| `node scripts/e2e-teams.mjs` | Teams (M7): a throw-away captain creates a padel team that needs approval, a second account asks and is approved, a third is invited and accepts; the captain books a throw-away venue's court and posts a team game: the members are told and one joins, an outsider gets null from `get_game`, does not find it in the list or on the team page and cannot join; the captain cannot leave until the role is handed over, then hands it over and leaves, and the new captain deletes the team; everything made is deleted, and anything left fails the run. The team is listed in Tashkent's team list for the minute the script runs. Run it after `deploy.mjs migrations`. |
| `node scripts/dev-login.mjs <token-or-bot-link> <phone>` | Test helper: plays Telegram's part for one sign-in attempt, so the app can be signed in where there is no Telegram (browser build, emulator). Needs the webhook secret from `.env`. Use made-up numbers only and delete the account afterwards. |

## How booking is kept correct

- `bookings.during` is a time range. A Postgres exclusion constraint (`bookings_no_overlap`) refuses two active rows that overlap on one court. That constraint, not application code, is what prevents double booking.
- The rules (5-minute hold, one hold per player, at most 3 upcoming bookings, no past slots, at most 14 days ahead, free cancellation until 6 hours before, price locked at hold) live in the private `app` schema. Those functions take the acting player and the current time as arguments, which is how the tests fix the clock.
- The app can only call the `public` wrappers (`hold_slots`, `confirm_booking`, `release_hold`, `cancel_booking`, `my_bookings`, `court_availability`), which pass the signed-in player and the real time. Players have no insert, update or delete on `bookings`.
- Times are stored as real instants. Everything crossing the API is venue wall-clock time, converted with the city's `utc_offset_minutes`.

## Venue owners and admins (Milestone 3)

Owners run their venue's calendar through `public` functions (rules in `migrations/20261123100000_owner.sql`): `my_venue_ids`, `owner_calendar`, `owner_create_walk_in`, `owner_block_slots`, `owner_cancel_booking`, `owner_mark_booking`. Walk-ins and blocks are rows in `bookings` (`source` `walk_in` or `block`), so the same exclusion constraint guards them. Each function first checks the caller manages the venue and otherwise raises `not_allowed`, before any other check. Every owner write adds a row to `audit_log`. A scheduled job (`app.advance_bookings`, every ten minutes) moves finished bookings to `completed`, then to `unverified` 48 hours after the end if nobody marked them.

Settings and the dashboard (`migrations/20261123110000_owner_settings.sql`): `owner_set_venue_hours`, `owner_set_court_hours`, `owner_set_court_pricing`, `owner_dashboard`. They write exactly what `app.court_slots` reads: one `working_hours` row per open weekday for a venue (no row means closed), one row per overridden weekday for a court (`closed = true` shuts it that day), and `price_rules` rows with `sort_order` in the order given. Overlapping rules are refused (`rules_overlap`). Existing bookings keep their times and locked prices. Each change is audited; reading the dashboard is not.

Admin functions (`migrations/20261123120000_admin.sql`), all refused with `not_allowed` to anyone not in `app_admins`: `am_i_admin` (any signed-in user), `admin_list_venues`, `admin_save_venue`, `admin_save_court`, `admin_duplicate_court`, `admin_delete_court`, `admin_delete_venue`, `admin_search_users`, `admin_set_owner`, `admin_list_sports`, `admin_save_sport`, `admin_list_banners`, `admin_save_banner`, `admin_delete_banner`, `admin_audit_log`. Save payloads are checked key by key and an unknown key is refused (`invalid_argument`), so a typo cannot silently drop a field. A court or venue that any booking row references cannot be deleted (`has_bookings`; for a venue, also a tournament, game or Game Request); deactivate it instead (`active = false`), which hides it from players and leaves its bookings as they are. Every write is audited.

An owner is a row in `venue_owners`; an admin, who can act on every venue, is a row in `app_admins`. Neither table can be written from the app. Once there is an admin, owners are assigned in the app (`admin_set_owner`). The first admin is added by hand in the SQL editor of the Supabase dashboard (it runs with full rights). The person must have signed in to the app once, so their account exists; then, with their phone number in the international form the app shows:

```sql
insert into public.app_admins (user_id)
select user_id from public.profile_contacts where phone = '+998901234567'
on conflict (user_id) do nothing;

-- Check: one row, with their name.
select a.user_id, p.full_name from public.app_admins a join public.profiles p on p.id = a.user_id;
```

To make someone an owner by hand in the same way:

```sql
insert into public.venue_owners (venue_id, user_id)
select '<venue id>', user_id from public.profile_contacts where phone = '+998901234567'
on conflict do nothing;
```

## Community: notifications, reliability, games, Game Requests (Milestone 4)

The rules live in `migrations/20261124100000_community_core.sql` (notifications, reliability, settings, booking hooks), `20261124110000_games_v2.sql` (games for every sport, requests to join, invites, host tools) and `20261124120000_game_requests.sql` (Game Requests, finding players). As elsewhere, the app calls `public` wrappers that pass the signed-in player and the real time; none of them returns a phone number.

| Area | Public functions |
|---|---|
| Inbox and settings | `my_notifications(p_limit, p_before, p_before_id)` (newest first, `created_at` at millisecond precision; the next page passes the last entry's `created_at` and `id`), `unread_notification_count`, `mark_notifications_read(p_ids)` (null: all), `my_reliability`, `my_settings`, `set_settings(p_muted, p_hidden)` |
| Games | `list_games(p_city_id)`, `get_game`, `create_game(p_game)`, `join_game`, `leave_game`, `request_to_join`, `withdraw_join_request`, `decide_join_request`, `invite_to_game`, `decline_invite`, `host_remove_participant`, `host_update_game`, `host_cancel_game` |
| Game Requests | `create_game_request`, `get_game_request`, `list_game_requests`, `request_interest`, `withdraw_interest`, `remove_interested`, `cancel_game_request`, `convert_game_request(p_request_id, p_place)` |
| Players | `list_players(p_city_id, p_sport_id, p_min_level, p_max_level, p_query, p_limit)`, `player_profile(p_user_id)` |

- Notifications are rows written only by the database (`app.notify`), read by their owner, and skipped when the player muted the category. The database stores no sentence: the app renders each one from `kind` and `payload`.
- Reliability is a score from events in the last 90 days (no-show −20, late cancellation −5, paid booking and completed game +2, positive credit capped at +20). A `limited` player may hold one upcoming booking; a `blocked` one cannot book, create, join or ask to join games, or post or join Game Requests, and is skipped when a Game Request they tapped is converted.
- Players read games only through the functions, which apply visibility: the city list shows public games, and invite-only games appear only to their host, players and invitees. A player the host removes cannot join or ask again until the host invites them.
- Players can read every column of `profiles` except `muted_categories` and `hidden_from_search`, which only `my_settings` returns.
- The scheduled job `actra-send-reminders` (every ten minutes) runs `app.send_reminders` (booking and game reminders two hours ahead; nothing for a booking confirmed or a game created inside that window), `app.complete_games` (marks ended games completed and gives `game_completed` to players of games with at least two) and `app.expire_game_requests` (expires requests whose window has ended and tells the poster and the interested players).

## How sign-in works (product spec §7.1)

1. The app calls `telegram-login` with `{action: "start"}` and gets a bot link plus a poll secret that never leaves the device.
2. The player opens the link. The bot (`telegram-webhook`) receives `/start <token>` and shows a "share my phone number" button.
3. The player shares their own contact. A contact that is not the sender's own is refused.
4. The app, polling `{action: "claim"}`, receives a one-time hash and exchanges it for a Supabase session. The account is the one that owns that phone number; it is created on first sign-in.

A token lasts 10 minutes and works once. The webhook only accepts calls carrying the secret registered with Telegram.

The project uses Supabase's new-style keys (`sb_publishable_…`, `sb_secret_…`), which are not JWTs. So `telegram-login` is deployed without the gateway's JWT check (see `config.toml`), and the secret key is passed to the functions as the function secret `ACTRA_SECRET_KEY`.

Supabase issues sessions for an e-mail or an SMS-verified phone. Since the phone is verified by Telegram instead, each account gets a private placeholder address (`<digits>@<project-ref>.supabase.co`, changeable with `LOGIN_EMAIL_DOMAIN` in `.env`). No mail is ever sent to it.

## How account deletion works

The app calls `delete-account` with the player's session (the gateway checks the JWT). The function calls `public.delete_account_service` (service role only), which runs `app.delete_account`. Everything still to come is cancelled through the usual functions, so the other people get their usual notifications: bookings, hosted and joined games, join requests and invites, Game Requests and entries in tournaments that have not started yet (a tournament that has started, today included in venue time, keeps its entries as history). An entry past its deadline, or one only waiting on the player as partner, is cancelled directly with the same notice. The phone, levels, venue ownerships, notifications and phone lookups are deleted; the player's own free text is cleared on every row, past and future (booking notes, notes and meeting points of the games they host, notes and areas of their Game Requests; a meeting-point game keeps `''`, which `game_json` returns as null); and the profile keeps only its id, its history and `deleted_at`, and can no longer be edited with the old session. Notifications already delivered to other people keep the `actor_name` they were written with. A venue left without an owner stays and gets an `owner_account_deleted` audit row. Admins are refused (`admin_account`).

Then the auth user is renamed to `deleted-<id>@<the sign-in domain>` (the domain of the placeholder addresses below; sign-in local parts are digits only, so they never collide) and banned, so the same phone signs up again as a new, empty account. If that step fails the app retries the call (both steps are idempotent); if the person signs in before that, sign-in closes the scrubbed auth user and creates a fresh one. A retry whose token is no longer accepted gets 401, and the app then signs out locally, as after a successful deletion.

If a valid player token gets 401 from the gateway itself (it happens with the new-style keys, whose sessions the gateway's JWT check may not accept; `scripts/e2e-delete.mjs` shows it as a 401 on the first call), set `verify_jwt = false` for `[functions.delete-account]` in `config.toml` and deploy the functions again. That is safe: the function checks the token itself with `auth.getUser` before deleting anything and answers 401 to anything else.

## Changing the sample content

Edit `app/lib/data/sample/sample_data.dart`, then:

```powershell
cd ..\app; dart run tool/gen_seed.dart
```

A Flutter test fails if `seed.sql` is out of date.
