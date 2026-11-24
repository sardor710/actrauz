// Brings the hosted Supabase project up to date with this folder.
//
//   node scripts/deploy.mjs            everything, in order
//   node scripts/deploy.mjs db         migrations + seed
//   node scripts/deploy.mjs migrations migrations only; use this once owners
//                                      edit hours and prices, which the seed
//                                      resets for the sample venues
//   node scripts/deploy.mjs seed       seed only (re-dates the sample games)
//   node scripts/deploy.mjs functions  function secrets + both edge functions
//   node scripts/deploy.mjs telegram   point the bot's webhook at the function
//   node scripts/deploy.mjs app        write app/env/dev.json for the Flutter app
//
// Reads supabase/.env (git-ignored). Needs no Docker.

import { randomBytes } from 'node:crypto';
import { mkdirSync, readdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { loadEnv, repoDir, requireEnv, saveEnvValue, sql, step, supabase, supabaseDir, telegram } from './env.mjs';

const only = process.argv.slice(2);
const wants = (name) => only.length === 0 || only.includes(name);

/** A SQL string literal that no content can break out of. */
const literal = (text) => {
  let tag = 'actra';
  while (text.includes(`$${tag}$`)) tag += 'x';
  return `$${tag}$${text}$${tag}$`;
};

const env = loadEnv();
requireEnv(env, ['SUPABASE_PROJECT_REF', 'SUPABASE_URL', 'SUPABASE_ANON_KEY']);
if (!env.SUPABASE_ACCESS_TOKEN) console.log('No SUPABASE_ACCESS_TOKEN in .env: relying on `npx supabase login` done on this PC.');
const url = env.SUPABASE_URL.replace(/\/+$/, '');

if (wants('functions')) {
  step('Linking to the project');
  await supabase(env, ['link', '--project-ref', env.SUPABASE_PROJECT_REF]);
}

if (wants('db') || only.includes('migrations')) {
  step('Applying migrations');
  // Over HTTPS rather than `supabase db push`, which needs the database port
  // (5432) and is blocked on some networks. Applied versions are recorded in
  // the same history table the CLI uses, so `db push` elsewhere agrees.
  await sql(
    env,
    `create schema if not exists supabase_migrations;
     create table if not exists supabase_migrations.schema_migrations (
       version text not null primary key, statements text[], name text);`,
    { write: true },
  );
  const applied = new Set((await sql(env, 'select version from supabase_migrations.schema_migrations')).map((r) => r.version));
  const dir = path.join(supabaseDir, 'migrations');
  const files = readdirSync(dir).filter((f) => /^\d+_.+\.sql$/.test(f)).sort();
  for (const file of files) {
    const version = file.slice(0, file.indexOf('_'));
    const name = file.slice(file.indexOf('_') + 1, -'.sql'.length);
    if (applied.has(version)) {
      console.log(`  already applied  ${file}`);
      continue;
    }
    const body = readFileSync(path.join(dir, file), 'utf8');
    // The migration and its history row go in one explicit transaction: both
    // or neither, so a migration that fails half way leaves nothing behind.
    await sql(
      env,
      `begin;\n${body}\n;\ninsert into supabase_migrations.schema_migrations (version, name, statements)
       values (${literal(version)}, ${literal(name)}, array[${literal(body)}]);\ncommit;`,
      { write: true },
    );
    console.log(`  applied          ${file}`);
  }
}

if (wants('db') || wants('seed')) {
  step('Loading sample content (safe to repeat)');
  await sql(env, readFileSync(path.join(supabaseDir, 'seed.sql'), 'utf8'), { write: true });
  const [counts] = await sql(
    env,
    `select (select count(*) from public.venues) as venues, (select count(*) from public.courts) as courts,
            (select count(*) from public.games) as games, (select count(*) from public.bookings) as bookings`,
  );
  console.log(`  venues ${counts.venues}, courts ${counts.courts}, sample games ${counts.games}, their bookings ${counts.bookings}`);
}

if (wants('functions') || wants('telegram')) {
  requireEnv(env, ['TELEGRAM_BOT_TOKEN']);
  if (!env.TELEGRAM_WEBHOOK_SECRET) {
    env.TELEGRAM_WEBHOOK_SECRET = randomBytes(32).toString('hex');
    saveEnvValue('TELEGRAM_WEBHOOK_SECRET', env.TELEGRAM_WEBHOOK_SECRET);
    console.log('Generated TELEGRAM_WEBHOOK_SECRET and saved it to supabase/.env');
  }
}

if (wants('functions')) {
  step('Setting function secrets');
  const bot = await telegram(env, 'getMe');
  console.log(`Bot: @${bot.username}`);

  // Through a short-lived file, so the values never appear in a command line.
  const tempDir = path.join(supabaseDir, '.temp');
  const secretsFile = path.join(tempDir, 'function-secrets.env');
  mkdirSync(tempDir, { recursive: true });
  writeFileSync(
    secretsFile,
    [
      `TELEGRAM_BOT_TOKEN=${env.TELEGRAM_BOT_TOKEN}`,
      `TELEGRAM_WEBHOOK_SECRET=${env.TELEGRAM_WEBHOOK_SECRET}`,
      `TELEGRAM_BOT_USERNAME=${bot.username}`,
      ...(env.LOGIN_EMAIL_DOMAIN ? [`LOGIN_EMAIL_DOMAIN=${env.LOGIN_EMAIL_DOMAIN}`] : []),
      // Function secrets may not start with SUPABASE_, hence the other name.
      ...(env.SUPABASE_SECRET_KEY ? [`ACTRA_SECRET_KEY=${env.SUPABASE_SECRET_KEY}`] : []),
    ].join('\n') + '\n',
  );
  try {
    // --yes: running this script is the confirmation the CLI asks for.
    await supabase(env, ['secrets', 'set', '--env-file', `"${secretsFile}"`, '--yes']);
  } finally {
    rmSync(secretsFile, { force: true });
  }

  step('Deploying edge functions');
  // verify_jwt per function comes from config.toml (off for the webhook).
  await supabase(env, ['functions', 'deploy', 'telegram-login', 'telegram-webhook', '--use-api', '--yes']);
}

if (wants('telegram')) {
  step('Pointing the bot at the webhook');
  const webhook = `${url}/functions/v1/telegram-webhook`;
  await telegram(env, 'setWebhook', {
    url: webhook,
    secret_token: env.TELEGRAM_WEBHOOK_SECRET,
    allowed_updates: ['message'],
    drop_pending_updates: true,
  });
  const info = await telegram(env, 'getWebhookInfo');
  console.log(`Webhook: ${info.url}`);
  console.log(`Pending updates: ${info.pending_update_count}; last error: ${info.last_error_message ?? 'none'}`);
  if (info.url !== webhook) throw new Error('Telegram did not accept the webhook URL');
}

if (wants('app')) {
  step('Writing app/env/dev.json');
  const file = path.join(repoDir, 'app', 'env', 'dev.json');
  mkdirSync(path.dirname(file), { recursive: true });
  writeFileSync(file, JSON.stringify({ SUPABASE_URL: url, SUPABASE_ANON_KEY: env.SUPABASE_ANON_KEY }, null, 2) + '\n');
  console.log(`Wrote ${file} (git-ignored). Run the app with --dart-define-from-file=env/dev.json`);
}

console.log('\nDone.');
