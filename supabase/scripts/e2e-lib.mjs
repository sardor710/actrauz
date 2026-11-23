// Shared by e2e.mjs and e2e-owner.mjs: calls to the hosted project, and
// throw-away accounts signed in the way a phone and Telegram would.

import assert from 'node:assert/strict';
import { createHash, randomInt } from 'node:crypto';
import { loadEnv, requireEnv, sql } from './env.mjs';

export const env = loadEnv();
requireEnv(env, [
  'SUPABASE_PROJECT_REF', 'SUPABASE_URL', 'SUPABASE_ANON_KEY',
  'SUPABASE_DB_PASSWORD', 'TELEGRAM_WEBHOOK_SECRET',
]);
export const url = env.SUPABASE_URL.replace(/\/+$/, '');
const anon = env.SUPABASE_ANON_KEY;

/** The id the seed gives a sample row, e.g. `sampleId('v1c2')`. */
export const sampleId = (id) => {
  const h = createHash('md5').update(`actra:${id}`).digest('hex');
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20)}`;
};

export async function call(pathname, { body, token = anon, headers = {}, method = 'POST' } = {}) {
  const res = await fetch(`${url}${pathname}`, {
    method,
    headers: { apikey: anon, Authorization: `Bearer ${token}`, 'Content-Type': 'application/json', ...headers },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await res.text();
  let data = null;
  try {
    data = text ? JSON.parse(text) : null;
  } catch {
    data = text;
  }
  return { status: res.status, data };
}

export const login = (body) => call('/functions/v1/telegram-login', { body });
export const webhook = (update, secret = env.TELEGRAM_WEBHOOK_SECRET) =>
  fetch(`${url}/functions/v1/telegram-webhook`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', ...(secret ? { 'X-Telegram-Bot-Api-Secret-Token': secret } : {}) },
    body: JSON.stringify(update),
  });

export const rpc = (session, name, params = {}) => call(`/rest/v1/rpc/${name}`, { body: params, token: session.jwt });

const created = { users: [], tokens: [] };

/** Signs in a throw-away account the way a phone and Telegram would. */
export async function signIn(label, phone) {
  const telegramId = 9_000_000_000 + randomInt(1_000_000);
  const started = await login({ action: 'start', language: 'en' });
  assert.equal(started.status, 200, `start failed: ${JSON.stringify(started.data)}`);
  const { token, poll_secret, bot_url } = started.data;
  created.tokens.push(token);
  assert.match(bot_url, /^https:\/\/t\.me\/\w+\?start=/);

  assert.deepEqual((await login({ action: 'claim', token, poll_secret })).data, { status: 'pending' });

  const from = { id: telegramId, language_code: 'en' };
  const chat = { id: telegramId, type: 'private' };
  assert.equal((await webhook({ message: { chat, from, text: `/start ${token}` } })).status, 200);
  assert.equal((await webhook({ message: { chat, from, contact: { phone_number: phone, user_id: telegramId } } })).status, 200);

  const claimed = await login({ action: 'claim', token, poll_secret });
  assert.equal(claimed.data?.status, 'ok', `claim failed: ${JSON.stringify(claimed.data)}`);

  const verified = await call('/auth/v1/verify', { body: { type: 'magiclink', token_hash: claimed.data.token_hash } });
  assert.equal(verified.status, 200, `session exchange failed: ${JSON.stringify(verified.data)}`);
  const session = { jwt: verified.data.access_token, userId: verified.data.user.id, isNew: claimed.data.is_new, token, poll_secret };
  created.users.push(session.userId);
  console.log(`  ${label}: signed in as ${session.userId} (${session.isNew ? 'new account' : 'existing account'})`);
  return session;
}

/** Fills in what the app asks for on first sign-in. */
export async function saveProfile(session, fullName) {
  const profile = await call(`/rest/v1/profiles?id=eq.${session.userId}`, {
    method: 'PATCH',
    token: session.jwt,
    headers: { Prefer: 'return=representation' },
    body: { full_name: fullName, city_id: 'tashkent', language: 'en', terms_accepted_at: new Date().toISOString() },
  });
  assert.equal(profile.status, 200, JSON.stringify(profile.data));
  assert.equal(profile.data[0].full_name, fullName);
}

/** The throw-away account ids as a SQL list, or '' when none were made. */
export const createdUsersSql = () => [...new Set(created.users)].map((id) => `'${id}'`).join(', ');

/**
 * Deletes every account made by `signIn`, with their bookings and login
 * tokens. `before` is extra SQL to run first, for rows that would block it.
 */
export async function removeAccounts({ before = [] } = {}) {
  const users = createdUsersSql();
  const tokens = created.tokens.map((t) => `'${t}'`).join(', ');
  try {
    for (const statement of before) await sql(env, statement, { write: true });
    if (users) {
      await sql(env, `delete from public.bookings where user_id in (${users})`, { write: true });
      await sql(env, `delete from auth.users where id in (${users})`, { write: true });
    }
    if (tokens) await sql(env, `delete from public.login_tokens where token in (${tokens})`, { write: true });
    console.log(`  removed ${new Set(created.users).size} accounts`);
  } catch (e) {
    console.error(`  cleanup failed, remove by hand: users ${users || '-'}\n  ${e.message}`);
  }
}
