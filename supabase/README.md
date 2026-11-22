# Actra backend (Supabase)

Everything the phone app talks to: the database schema and rules, the sample content, and Telegram sign-in.

```
supabase/
  migrations/     schema, row-level security, booking and game functions
  seed.sql        sample content, GENERATED from app/lib/data/sample/sample_data.dart
  functions/      telegram-login, telegram-webhook (Deno edge functions)
  scripts/        deploy.mjs, e2e.mjs
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

`deploy.mjs` applies the migrations, loads the sample content, sets the function secrets, deploys both functions, points the bot's webhook at the project, and writes `app/env/dev.json` so the Flutter app uses the project. It can be run again at any time; each part can also be run alone (`db`, `seed`, `functions`, `telegram`, `app`).

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
| `node scripts/deploy.mjs seed` | Reload sample content; re-dates the sample games and tournaments from today. |
| `node scripts/e2e.mjs` | Sign in two throw-away accounts through the real functions, book a slot, check the row in the database, check the second account is blocked, clean up. |
| `node scripts/dev-login.mjs <token-or-bot-link> <phone>` | Test helper: plays Telegram's part for one sign-in attempt, so the app can be signed in where there is no Telegram (browser build, emulator). Needs the webhook secret from `.env`. Use made-up numbers only and delete the account afterwards. |

## How booking is kept correct

- `bookings.during` is a time range. A Postgres exclusion constraint (`bookings_no_overlap`) refuses two active rows that overlap on one court. That constraint, not application code, is what prevents double booking.
- The rules (5-minute hold, one hold per player, at most 3 upcoming bookings, no past slots, at most 14 days ahead, free cancellation until 6 hours before, price locked at hold) live in the private `app` schema. Those functions take the acting player and the current time as arguments, which is how the tests fix the clock.
- The app can only call the `public` wrappers (`hold_slots`, `confirm_booking`, `release_hold`, `cancel_booking`, `my_bookings`, `court_availability`), which pass the signed-in player and the real time. Players have no insert, update or delete on `bookings`.
- Times are stored as real instants. Everything crossing the API is venue wall-clock time, converted with the city's `utc_offset_minutes`.

## How sign-in works (product spec §7.1)

1. The app calls `telegram-login` with `{action: "start"}` and gets a bot link plus a poll secret that never leaves the device.
2. The player opens the link. The bot (`telegram-webhook`) receives `/start <token>` and shows a "share my phone number" button.
3. The player shares their own contact. A contact that is not the sender's own is refused.
4. The app, polling `{action: "claim"}`, receives a one-time hash and exchanges it for a Supabase session. The account is the one that owns that phone number; it is created on first sign-in.

A token lasts 10 minutes and works once. The webhook only accepts calls carrying the secret registered with Telegram.

The project uses Supabase's new-style keys (`sb_publishable_…`, `sb_secret_…`), which are not JWTs. So `telegram-login` is deployed without the gateway's JWT check (see `config.toml`), and the secret key is passed to the functions as the function secret `ACTRA_SECRET_KEY`.

Supabase issues sessions for an e-mail or an SMS-verified phone. Since the phone is verified by Telegram instead, each account gets a private placeholder address (`<digits>@<project-ref>.supabase.co`, changeable with `LOGIN_EMAIL_DOMAIN` in `.env`). No mail is ever sent to it.

## Changing the sample content

Edit `app/lib/data/sample/sample_data.dart`, then:

```powershell
cd ..\app; dart run tool/gen_seed.dart
```

A Flutter test fails if `seed.sql` is out of date.
