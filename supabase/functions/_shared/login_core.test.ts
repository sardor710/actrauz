// Telegram sign-in with the database, Telegram and the clock faked.
// Run by `npm test` (node --test strips the TypeScript types).

import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { beforeEach, test } from 'node:test';
import { botTexts, pickLanguage } from './bot_texts.ts';
import { handleLoginRequest, handleWebhookRequest } from './http.ts';
import { authUserFor, claimLogin, handleUpdate, normalizePhone, startLogin } from './login_core.ts';
import type { AuthAccounts, Deps, LoginToken, TelegramUpdate } from './login_core.ts';
import { closedAuthUser, deleteAccount } from './delete_account_core.ts';
import type { DeleteDeps } from './delete_account_core.ts';

let clock: Date;
let tokens: Map<string, LoginToken & { created: number }>;
let accounts: Map<string, { userId: string; telegramUserId: number | null }>;
let sent: { chatId: number; text: string; markup: any }[];
let counter: number;
let deps: Deps;

beforeEach(() => {
  clock = new Date('2026-11-22T10:00:00Z');
  tokens = new Map();
  accounts = new Map();
  sent = [];
  counter = 0;
  deps = {
    botUsername: 'actra_test_bot',
    now: () => clock,
    randomToken: () => `tok${String(++counter).padStart(29, '0')}`,
    sha256: async (text) => createHash('sha256').update(text).digest('hex'),
    tokens: {
      insert: async (row) => void tokens.set(row.token, { ...row, created: ++counter }),
      get: async (token) => tokens.get(token) ?? null,
      transition: async (token, from, patch) => {
        const row = tokens.get(token);
        if (!row || !from.includes(row.status)) return false;
        Object.assign(row, patch);
        return true;
      },
      findAwaiting: async (telegramUserId, nowIso) =>
        [...tokens.values()]
          .filter((r) => r.telegram_user_id === telegramUserId && r.status === 'awaiting_contact' && r.expires_at > nowIso)
          .sort((a, b) => b.created - a.created)[0] ?? null,
      purgeExpired: async (beforeIso) => {
        for (const [key, row] of tokens) if (row.expires_at < beforeIso) tokens.delete(key);
      },
    },
    users: {
      findByPhone: async (phone) => (accounts.has(phone) ? { userId: accounts.get(phone)!.userId } : null),
      create: async (phone, telegramUserId) => {
        const userId = `user-${accounts.size + 1}`;
        accounts.set(phone, { userId, telegramUserId });
        return { userId };
      },
      linkTelegram: async (userId, telegramUserId) => {
        for (const account of accounts.values()) if (account.userId === userId) account.telegramUserId = telegramUserId;
      },
      issueSessionToken: async (userId, phone) => `session-for-${userId}-${phone}`,
    },
    telegram: {
      sendMessage: async (chatId, text, markup) => void sent.push({ chatId, text, markup }),
    },
  };
});

const minutes = (n: number) => (clock = new Date(clock.getTime() + n * 60_000));

const start = (from: number, token?: string, language_code = 'en'): TelegramUpdate => ({
  message: { chat: { id: from, type: 'private' }, from: { id: from, language_code }, text: token ? `/start ${token}` : '/start' },
});

/** contactUserId: null = a contact card with no Telegram account behind it. */
const contact = (from: number, phone: string, contactUserId: number | null = from): TelegramUpdate => ({
  message: {
    chat: { id: from, type: 'private' },
    from: { id: from },
    contact: { phone_number: phone, user_id: contactUserId ?? undefined },
  },
});

const lastMessage = () => sent.at(-1)!;

test('the whole flow: start, open the bot, share the contact, claim a session', async () => {
  const login = await startLogin(deps, { language: 'en' });
  assert.equal(login.bot_url, `https://t.me/actra_test_bot?start=${login.token}`);
  assert.equal(login.expires_in, 600);
  assert.match(login.token, /^[A-Za-z0-9_-]{1,64}$/);
  assert.notEqual(login.token, login.poll_secret);
  // Only a hash of the poll secret is stored.
  assert.ok(!JSON.stringify([...tokens.values()]).includes(login.poll_secret));

  assert.deepEqual(await claimLogin(deps, { token: login.token, pollSecret: login.poll_secret }), { status: 'pending' });

  await handleUpdate(deps, start(777, login.token));
  assert.equal(lastMessage().chatId, 777);
  assert.equal(lastMessage().text, botTexts.en.askContact);
  assert.deepEqual(lastMessage().markup.keyboard, [[{ text: botTexts.en.shareButton, request_contact: true }]]);
  assert.deepEqual(await claimLogin(deps, { token: login.token, pollSecret: login.poll_secret }), { status: 'pending' });

  await handleUpdate(deps, contact(777, '998901234567'));
  assert.equal(lastMessage().text, botTexts.en.done);
  assert.deepEqual(lastMessage().markup, { remove_keyboard: true });

  assert.deepEqual(await claimLogin(deps, { token: login.token, pollSecret: login.poll_secret }), {
    status: 'ok',
    token_hash: 'session-for-user-1-+998901234567',
    is_new: true,
  });
  assert.deepEqual(accounts.get('+998901234567'), { userId: 'user-1', telegramUserId: 777 });
});

test('the same phone number signs in to the same account again', async () => {
  const signIn = async (telegramId: number) => {
    const login = await startLogin(deps, { language: 'ru' });
    await handleUpdate(deps, start(telegramId, login.token));
    await handleUpdate(deps, contact(telegramId, '+998 90 123-45-67'));
    return claimLogin(deps, { token: login.token, pollSecret: login.poll_secret });
  };
  const first = await signIn(777);
  const second = await signIn(888); // the same number, now on another Telegram account
  assert.deepEqual(first, { status: 'ok', token_hash: 'session-for-user-1-+998901234567', is_new: true });
  assert.deepEqual(second, { status: 'ok', token_hash: 'session-for-user-1-+998901234567', is_new: false });
  assert.equal(accounts.size, 1);
  assert.equal(accounts.get('+998901234567')!.telegramUserId, 888);
});

test("someone else's contact is refused and nothing is recorded", async () => {
  const login = await startLogin(deps, { language: 'en' });
  await handleUpdate(deps, start(777, login.token));

  // A contact card of another Telegram user, and one with no Telegram account at all.
  await handleUpdate(deps, contact(777, '998909999999', 555));
  assert.equal(lastMessage().text, botTexts.en.ownNumberOnly);
  assert.ok(lastMessage().markup.keyboard, 'the share button is offered again');
  await handleUpdate(deps, contact(777, '998909999999', null));
  assert.equal(lastMessage().text, botTexts.en.ownNumberOnly);

  assert.equal(tokens.get(login.token)!.phone, null);
  assert.deepEqual(await claimLogin(deps, { token: login.token, pollSecret: login.poll_secret }), { status: 'pending' });
  assert.equal(accounts.size, 0);
});

test('a token is redeemed once', async () => {
  const login = await startLogin(deps, { language: 'en' });
  await handleUpdate(deps, start(777, login.token));
  await handleUpdate(deps, contact(777, '998901234567'));
  assert.equal((await claimLogin(deps, { token: login.token, pollSecret: login.poll_secret })).status, 'ok');
  assert.deepEqual(await claimLogin(deps, { token: login.token, pollSecret: login.poll_secret }), { status: 'expired' });
  // The link cannot be reused in the bot either.
  await handleUpdate(deps, start(999, login.token));
  assert.equal(lastMessage().text, botTexts.en.linkExpired);
});

test('a token expires after ten minutes, verified or not', async () => {
  const unused = await startLogin(deps, { language: 'en' });
  const verified = await startLogin(deps, { language: 'en' });
  await handleUpdate(deps, start(777, verified.token));
  await handleUpdate(deps, contact(777, '998901234567'));

  minutes(9);
  assert.deepEqual(await claimLogin(deps, { token: unused.token, pollSecret: unused.poll_secret }), { status: 'pending' });
  minutes(1);
  assert.deepEqual(await claimLogin(deps, { token: unused.token, pollSecret: unused.poll_secret }), { status: 'expired' });
  assert.deepEqual(await claimLogin(deps, { token: verified.token, pollSecret: verified.poll_secret }), { status: 'expired' });
  assert.equal(accounts.size, 0);

  await handleUpdate(deps, start(888, unused.token));
  assert.equal(lastMessage().text, botTexts.en.linkExpired);
});

test('the link alone is not enough: a wrong or missing poll secret gets nothing', async () => {
  const login = await startLogin(deps, { language: 'en' });
  await handleUpdate(deps, start(777, login.token));
  await handleUpdate(deps, contact(777, '998901234567'));

  assert.deepEqual(await claimLogin(deps, { token: login.token, pollSecret: 'guess' }), { status: 'expired' });
  assert.deepEqual(await claimLogin(deps, { token: login.token, pollSecret: login.token }), { status: 'expired' });
  assert.deepEqual(await claimLogin(deps, { token: login.token }), { status: 'expired' });
  assert.deepEqual(await claimLogin(deps, { token: 'unknown', pollSecret: login.poll_secret }), { status: 'expired' });
  // The rightful device still gets its session afterwards.
  assert.equal((await claimLogin(deps, { token: login.token, pollSecret: login.poll_secret })).status, 'ok');
});

test('/start with no token or an unknown one explains what to do and stores nothing', async () => {
  await handleUpdate(deps, start(777, undefined, 'uz'));
  assert.equal(lastMessage().text, botTexts.uz.openApp);
  await handleUpdate(deps, start(777, 'made-up', 'ru'));
  assert.equal(lastMessage().text, botTexts.ru.linkExpired);
  assert.equal(tokens.size, 0);
});

test('a contact sent without a sign-in in progress is ignored politely', async () => {
  await handleUpdate(deps, contact(777, '998901234567'));
  assert.equal(lastMessage().text, botTexts.ru.openApp);
  assert.equal(accounts.size, 0);
});

test('the bot only talks in private chats', async () => {
  const login = await startLogin(deps, { language: 'en' });
  await handleUpdate(deps, {
    message: { chat: { id: -100, type: 'group' }, from: { id: 777 }, text: `/start ${login.token}` },
  });
  await handleUpdate(deps, {});
  assert.equal(sent.length, 0);
  assert.equal(tokens.get(login.token)!.status, 'pending');
});

test('the bot answers in the language chosen in the app', async () => {
  for (const language of ['uz', 'ru', 'kk', 'en'] as const) {
    const login = await startLogin(deps, { language });
    await handleUpdate(deps, start(1000, login.token, 'en'));
    assert.equal(lastMessage().text, botTexts[language].askContact);
    assert.equal(lastMessage().markup.keyboard[0][0].text, botTexts[language].shareButton);
    await handleUpdate(deps, { message: { chat: { id: 1000, type: 'private' }, from: { id: 1000 }, text: 'hello?' } });
    assert.equal(lastMessage().text, botTexts[language].askContact);
    await handleUpdate(deps, contact(1000, '998901234567'));
    assert.equal(lastMessage().text, botTexts[language].done);
  }
  // An unsupported language falls back to Russian.
  const login = await startLogin(deps, { language: 'kz' });
  await handleUpdate(deps, start(1001, login.token));
  assert.equal(lastMessage().text, botTexts.ru.askContact);
});

test('Kazakh is picked from kk codes, and kz is not a language code', () => {
  assert.equal(pickLanguage('kk'), 'kk');
  assert.equal(pickLanguage('kk-KZ'), 'kk');
  assert.equal(pickLanguage('kz'), 'ru');
});

test('a Kazakh-speaking user with a Kazakh login gets Kazakh replies', async () => {
  const login = await startLogin(deps, { language: 'kk' });
  await handleUpdate(deps, start(1002, login.token, 'kk'));
  assert.equal(lastMessage().text, botTexts.kk.askContact);
  await handleUpdate(deps, contact(1002, '77011234567'));
  assert.equal(lastMessage().text, botTexts.kk.done);
});

test('every bot text exists in all four languages', () => {
  const keys = Object.keys(botTexts.en).sort();
  for (const language of ['uz', 'ru', 'kk'] as const) {
    assert.deepEqual(Object.keys(botTexts[language]).sort(), keys);
    for (const key of keys) assert.ok((botTexts[language] as any)[key].trim().length > 0, `${language}.${key}`);
  }
});

test('phone numbers are normalised to +digits', () => {
  assert.equal(normalizePhone('998 90 123-45-67'), '+998901234567');
  assert.equal(normalizePhone('+7 (727) 200-00-04'), '+77272000004');
  assert.equal(normalizePhone('abc'), null);
  assert.equal(normalizePhone(''), null);
  assert.equal(normalizePhone(undefined), null);
  assert.equal(normalizePhone('12345'), null);
  assert.equal(normalizePhone('1234567890123456'), null);
});

// ---- HTTP edges ----

const post = (body: unknown, headers: Record<string, string> = {}) =>
  new Request('https://example.test/fn', { method: 'POST', headers, body: typeof body === 'string' ? body : JSON.stringify(body) });

test('webhook: without the Telegram secret header nothing happens', async () => {
  const login = await startLogin(deps, { language: 'en' });
  let reached = 0;
  const lazyDeps = () => (reached++, deps);

  for (const headers of [{}, { 'X-Telegram-Bot-Api-Secret-Token': 'wrong' }]) {
    const res = await handleWebhookRequest(lazyDeps, 's3cret', post(start(777, login.token), headers));
    assert.equal(res.status, 401);
  }
  // An unset secret must not turn into "anything goes".
  const unset = await handleWebhookRequest(lazyDeps, '', post(start(777, login.token), { 'X-Telegram-Bot-Api-Secret-Token': '' }));
  assert.equal(unset.status, 401);

  assert.equal(reached, 0);
  assert.equal(sent.length, 0);
  assert.equal(tokens.get(login.token)!.status, 'pending');

  const ok = await handleWebhookRequest(lazyDeps, 's3cret', post(start(777, login.token), { 'X-Telegram-Bot-Api-Secret-Token': 's3cret' }));
  assert.equal(ok.status, 200);
  assert.equal(tokens.get(login.token)!.status, 'awaiting_contact');
});

test('webhook: a failing update is still acknowledged so Telegram does not resend it', async () => {
  deps.telegram.sendMessage = async () => {
    throw new Error('Telegram is down');
  };
  const res = await handleWebhookRequest(() => deps, 's3cret', post(start(777), { 'X-Telegram-Bot-Api-Secret-Token': 's3cret' }));
  assert.equal(res.status, 200);
  const bad = await handleWebhookRequest(() => deps, 's3cret', post('not json', { 'X-Telegram-Bot-Api-Secret-Token': 's3cret' }));
  assert.equal(bad.status, 400);
});

test('login endpoint: start and claim over HTTP, with CORS for the web app', async () => {
  const preflight = await handleLoginRequest(deps, new Request('https://example.test/fn', { method: 'OPTIONS' }));
  assert.equal(preflight.headers.get('Access-Control-Allow-Origin'), '*');

  const started = await (await handleLoginRequest(deps, post({ action: 'start', language: 'uz' }))).json();
  assert.equal(tokens.get(started.token)!.language, 'uz');

  const pending = await handleLoginRequest(deps, post({ action: 'claim', token: started.token, poll_secret: started.poll_secret }));
  assert.equal(pending.headers.get('Access-Control-Allow-Origin'), '*');
  assert.deepEqual(await pending.json(), { status: 'pending' });

  assert.equal((await handleLoginRequest(deps, post({ action: 'nope' }))).status, 400);
  assert.equal((await handleLoginRequest(deps, post('not json'))).status, 400);
  assert.equal((await handleLoginRequest(deps, new Request('https://example.test/fn'))).status, 405);
  assert.deepEqual(await (await handleLoginRequest(deps, post({ action: 'claim' }))).json(), { status: 'expired' });
});

// ---- Auth users and account deletion ----

/**
 * Supabase auth faked: one user per address, as auth.admin.createUser
 * enforces; `deleted` stands for profiles.deleted_at.
 */
function fakeAuth() {
  const users = new Map<string, { email: string; deleted: boolean; banned: boolean }>();
  let created = 0;
  const auth: AuthAccounts = {
    create: async (email) => {
      if ([...users.values()].some((u) => u.email === email)) return { error: 'already registered' };
      const userId = `auth-${++created}`;
      users.set(userId, { email, deleted: false, banned: false });
      return { userId };
    },
    findByEmail: async (email) => {
      const hit = [...users].find(([, u]) => u.email === email);
      return hit ? { userId: hit[0] } : { error: 'user not found' };
    },
    isDeleted: async (userId) => users.get(userId)?.deleted ?? false,
    close: async (userId) => {
      const user = users.get(userId)!;
      user.email = closedAuthUser(userId, 'login.test').email;
      user.banned = true;
    },
  };
  return { users, auth };
}

/** The fake deps, with accounts created through authUserFor and a deletion that scrubs and closes. */
function withAuth() {
  const world = fakeAuth();
  deps.users.create = async (phone, telegramUserId) => {
    const userId = await authUserFor(world.auth, `${phone.replace(/\D/g, '')}@login.test`, phone);
    accounts.set(phone, { userId, telegramUserId });
    return { userId };
  };
  const deleteDeps: DeleteDeps = {
    userIdFromToken: async (token) => token.match(/^session-for-(.+)-\+\d+$/)?.[1] ?? null,
    scrub: async (userId) => {
      world.users.get(userId)!.deleted = true;
      // profile_contacts goes with the scrub.
      for (const [phone, account] of accounts) if (account.userId === userId) accounts.delete(phone);
    },
    closeAuthUser: (userId) => world.auth.close(userId),
  };
  return { world, deleteDeps };
}

async function signIn(telegramId: number, phone: string) {
  const login = await startLogin(deps, { language: 'ru' });
  await handleUpdate(deps, start(telegramId, login.token));
  await handleUpdate(deps, contact(telegramId, phone));
  const claimed = await claimLogin(deps, { token: login.token, pollSecret: login.poll_secret });
  assert.equal(claimed.status, 'ok');
  return claimed as { status: 'ok'; token_hash: string; is_new: boolean };
}

test('an auth user left behind by an interrupted sign-up is picked up, not replaced', async () => {
  const { world } = withAuth();
  // The auth user exists, its profile rows were never written.
  const { userId: orphan } = (await world.auth.create('77010000001@login.test', '+77010000001')) as { userId: string };
  const first = await signIn(777, '+77010000001');
  assert.equal(first.token_hash, `session-for-${orphan}-+77010000001`);
  assert.equal(first.is_new, true);
  assert.equal(world.users.size, 1);
  assert.equal(world.users.get(orphan)!.banned, false);
});

test('same phone after deletion gets a new account', async () => {
  const { world, deleteDeps } = withAuth();
  const first = await signIn(777, '+77010000001');
  const oldId = (await deleteDeps.userIdFromToken(first.token_hash))!;
  assert.deepEqual(await deleteAccount(deleteDeps, first.token_hash), { status: 'deleted' });

  const again = await signIn(777, '+77010000001');
  assert.equal(again.is_new, true);
  const newId = (await deleteDeps.userIdFromToken(again.token_hash))!;
  assert.notEqual(newId, oldId);
  assert.equal(world.users.get(newId)!.deleted, false);
  assert.equal(world.users.get(oldId)!.banned, true);
});

test('a deletion that stopped before closing the auth user: signing in again closes it and starts fresh', async () => {
  const { world, deleteDeps } = withAuth();
  const first = await signIn(777, '+77010000001');
  const oldId = (await deleteDeps.userIdFromToken(first.token_hash))!;
  const failing = { ...deleteDeps, closeAuthUser: async () => Promise.reject(new Error('auth is down')) };
  await assert.rejects(deleteAccount(failing, first.token_hash), /auth is down/);
  assert.equal(world.users.get(oldId)!.banned, false, 'the scrubbed user is still open');

  // Before the app retries, the same phone signs in again.
  const again = await signIn(777, '+77010000001');
  const newId = (await deleteDeps.userIdFromToken(again.token_hash))!;
  assert.notEqual(newId, oldId, 'the scrubbed account is not revived');
  assert.equal(again.is_new, true);
  assert.equal(world.users.get(oldId)!.banned, true);
  assert.equal(world.users.get(oldId)!.email, `deleted-${oldId}@login.test`, 'renamed on the sign-in domain');
  assert.equal(world.users.get(newId)!.email, '77010000001@login.test');
});
