// Test helper: plays Telegram's part for one sign-in attempt, so the app can
// be signed in on a machine with no Telegram (a browser build, an emulator,
// an automated run). It posts the same two updates Telegram would send to
// the webhook: "/start <token>" and a shared contact.
//
//   node scripts/dev-login.mjs <token-or-bot-link> <phone>
//
// It needs the webhook secret from supabase/.env, so only the project owner
// can use it. Never give test accounts a real person's phone number.

import { randomInt } from 'node:crypto';
import { loadEnv, requireEnv } from './env.mjs';

const [, , tokenOrLink, phone] = process.argv;
if (!tokenOrLink || !phone) {
  console.error('Usage: node scripts/dev-login.mjs <token-or-bot-link> <phone>');
  process.exit(2);
}
const token = tokenOrLink.includes('start=') ? new URL(tokenOrLink).searchParams.get('start') : tokenOrLink;

const env = loadEnv();
requireEnv(env, ['SUPABASE_URL', 'TELEGRAM_WEBHOOK_SECRET']);

const telegramId = 9_000_000_000 + randomInt(1_000_000);
const chat = { id: telegramId, type: 'private' };
const from = { id: telegramId, language_code: 'en' };

async function send(message) {
  const res = await fetch(`${env.SUPABASE_URL.replace(/\/+$/, '')}/functions/v1/telegram-webhook`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'X-Telegram-Bot-Api-Secret-Token': env.TELEGRAM_WEBHOOK_SECRET },
    body: JSON.stringify({ message: { chat, from, ...message } }),
  });
  if (res.status !== 200) throw new Error(`webhook answered ${res.status}`);
}

await send({ text: `/start ${token}` });
await send({ contact: { phone_number: phone, user_id: telegramId } });
console.log(`Contact ${phone} shared for this sign-in attempt. The app should sign in within a few seconds.`);
