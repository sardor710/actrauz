// Telegram sign-in (product spec §7.1), free of any runtime: no Deno, no
// Supabase client, no network. Everything it touches arrives through `Deps`,
// so the same code runs in the edge functions and under `node --test`.
//
//   1. The app calls startLogin and opens the returned bot link.
//   2. The bot receives "/start <token>" and asks for the contact.
//   3. The player shares their own contact; the token becomes verified.
//   4. The app, polling claimLogin with its secret, receives a one-time
//      session token for the account that owns that phone number.

import { botTexts, pickLanguage } from './bot_texts.ts';
import type { Language } from './bot_texts.ts';

export type TokenStatus = 'pending' | 'awaiting_contact' | 'verified' | 'claimed';

export interface LoginToken {
  token: string;
  poll_secret_hash: string;
  language: Language;
  status: TokenStatus;
  telegram_user_id: number | null;
  chat_id: number | null;
  phone: string | null;
  /** ISO 8601. */
  expires_at: string;
}

export interface TokenStore {
  insert(row: LoginToken): Promise<void>;
  get(token: string): Promise<LoginToken | null>;
  /** Applies `patch` only while the status is one of `from`. True if it did. */
  transition(token: string, from: TokenStatus[], patch: Partial<LoginToken>): Promise<boolean>;
  /** The newest unexpired attempt waiting for this Telegram user's contact. */
  findAwaiting(telegramUserId: number, nowIso: string): Promise<LoginToken | null>;
  /** Housekeeping: drop attempts that expired before `beforeIso`. */
  purgeExpired(beforeIso: string): Promise<void>;
}

export interface UserStore {
  findByPhone(phone: string): Promise<{ userId: string } | null>;
  create(phone: string, telegramUserId: number | null, language: Language): Promise<{ userId: string }>;
  /** Remembers which Telegram account this phone last signed in from. */
  linkTelegram(userId: string, telegramUserId: number): Promise<void>;
  /** A single-use hash the app exchanges for a session. */
  issueSessionToken(userId: string, phone: string): Promise<string>;
}

/** The auth admin calls account creation needs (supabase_deps wires them to supabase-js). */
export interface AuthAccounts {
  /** Creates the auth user; an error (no userId) when the address is taken. */
  create(email: string, phone: string): Promise<{ userId?: string; error?: string }>;
  /** The auth user with this address. */
  findByEmail(email: string): Promise<{ userId?: string; error?: string }>;
  /** True once the account's profile has been deleted (profiles.deleted_at). */
  isDeleted(userId: string): Promise<boolean>;
  /** Renames and bans the auth user, as account deletion does. */
  close(userId: string): Promise<void>;
}

/**
 * The auth user for a new account at `email`. An earlier attempt may have
 * created the auth user and stopped before the profile rows; that user is
 * picked up instead of failing forever. Unless its profile was deleted: a
 * deletion that scrubbed the account but failed to close the auth user, then
 * the person signed in again before retrying. That user is closed now and a
 * fresh one created, so the scrubbed account is never revived.
 */
export async function authUserFor(auth: AuthAccounts, email: string, phone: string): Promise<string> {
  const created = await auth.create(email, phone);
  if (created.userId) return created.userId;
  const existing = await auth.findByEmail(email);
  if (!existing.userId) throw new Error(created.error ?? existing.error ?? 'could not create the account');
  if (!(await auth.isDeleted(existing.userId))) return existing.userId;

  await auth.close(existing.userId);
  const fresh = await auth.create(email, phone);
  if (!fresh.userId) throw new Error(fresh.error ?? 'could not create the account');
  return fresh.userId;
}

export interface Telegram {
  sendMessage(chatId: number, text: string, replyMarkup?: unknown): Promise<void>;
}

export interface Deps {
  tokens: TokenStore;
  users: UserStore;
  telegram: Telegram;
  botUsername: string;
  now(): Date;
  /** 32 characters from [A-Za-z0-9_-]: valid as a Telegram start parameter. */
  randomToken(): string;
  sha256(text: string): Promise<string>;
}

export const LOGIN_TTL_SECONDS = 600;

export type StartResult = { token: string; poll_secret: string; bot_url: string; expires_in: number };
export type ClaimResult =
  | { status: 'pending' }
  | { status: 'expired' }
  | { status: 'ok'; token_hash: string; is_new: boolean };

/** "+998901234567" from whatever Telegram or a person typed; null if it is not a phone number. */
export function normalizePhone(raw: string | null | undefined): string | null {
  const digits = (raw ?? '').replace(/\D/g, '');
  if (digits.length < 7 || digits.length > 15) return null;
  return `+${digits}`;
}

const isExpired = (row: LoginToken, now: Date) => new Date(row.expires_at).getTime() <= now.getTime();

export async function startLogin(deps: Deps, input: { language?: string }): Promise<StartResult> {
  const now = deps.now();
  const token = deps.randomToken();
  const pollSecret = deps.randomToken();
  await deps.tokens.purgeExpired(new Date(now.getTime() - 24 * 3600 * 1000).toISOString());
  await deps.tokens.insert({
    token,
    poll_secret_hash: await deps.sha256(pollSecret),
    language: pickLanguage(input.language),
    status: 'pending',
    telegram_user_id: null,
    chat_id: null,
    phone: null,
    expires_at: new Date(now.getTime() + LOGIN_TTL_SECONDS * 1000).toISOString(),
  });
  return {
    token,
    poll_secret: pollSecret,
    bot_url: `https://t.me/${deps.botUsername}?start=${token}`,
    expires_in: LOGIN_TTL_SECONDS,
  };
}

/**
 * Called by the app while it waits. Only the device that started the attempt
 * knows the poll secret, so seeing the link (which carries the token) is not
 * enough to take the session. A token is redeemed at most once.
 */
export async function claimLogin(deps: Deps, input: { token?: string; pollSecret?: string }): Promise<ClaimResult> {
  if (!input.token || !input.pollSecret) return { status: 'expired' };
  const row = await deps.tokens.get(input.token);
  if (!row) return { status: 'expired' };
  if ((await deps.sha256(input.pollSecret)) !== row.poll_secret_hash) return { status: 'expired' };
  if (isExpired(row, deps.now())) return { status: 'expired' };
  if (row.status === 'pending' || row.status === 'awaiting_contact') return { status: 'pending' };
  if (row.status !== 'verified' || !row.phone) return { status: 'expired' };

  // Whoever flips verified -> claimed owns the redemption.
  if (!(await deps.tokens.transition(row.token, ['verified'], { status: 'claimed' }))) return { status: 'expired' };

  let user = await deps.users.findByPhone(row.phone);
  const isNew = user === null;
  if (user === null) {
    user = await deps.users.create(row.phone, row.telegram_user_id, row.language);
  } else if (row.telegram_user_id !== null) {
    await deps.users.linkTelegram(user.userId, row.telegram_user_id);
  }
  return { status: 'ok', token_hash: await deps.users.issueSessionToken(user.userId, row.phone), is_new: isNew };
}

// ---- The bot ----

/** The parts of a Telegram update this bot reads. */
export interface TelegramUpdate {
  message?: {
    chat: { id: number; type: string };
    from?: { id: number; language_code?: string };
    text?: string;
    contact?: { phone_number: string; user_id?: number };
  };
}

const shareContactKeyboard = (language: Language) => ({
  keyboard: [[{ text: botTexts[language].shareButton, request_contact: true }]],
  resize_keyboard: true,
  one_time_keyboard: true,
});

const removeKeyboard = { remove_keyboard: true };

export async function handleUpdate(deps: Deps, update: TelegramUpdate): Promise<void> {
  const message = update.message;
  // Sign-in happens in a private chat with the player, nowhere else.
  if (!message || !message.from || message.chat.type !== 'private') return;

  const chatId = message.chat.id;
  const senderId = message.from.id;
  const fallback = pickLanguage(message.from.language_code);
  const now = deps.now();

  if (message.text?.startsWith('/start')) {
    const token = message.text.split(/\s+/)[1];
    if (!token) return deps.telegram.sendMessage(chatId, botTexts[fallback].openApp, removeKeyboard);

    const row = await deps.tokens.get(token);
    const usable = row !== null && !isExpired(row, now) && (row.status === 'pending' || row.status === 'awaiting_contact');
    if (!usable || !(await deps.tokens.transition(token, ['pending', 'awaiting_contact'], {
      status: 'awaiting_contact',
      telegram_user_id: senderId,
      chat_id: chatId,
    }))) {
      return deps.telegram.sendMessage(chatId, botTexts[row?.language ?? fallback].linkExpired, removeKeyboard);
    }
    return deps.telegram.sendMessage(chatId, botTexts[row.language].askContact, shareContactKeyboard(row.language));
  }

  const waiting = await deps.tokens.findAwaiting(senderId, now.toISOString());
  const language = waiting?.language ?? fallback;

  if (message.contact) {
    if (!waiting) return deps.telegram.sendMessage(chatId, botTexts[language].openApp, removeKeyboard);
    // Telegram fills contact.user_id only for a real Telegram account; it
    // must be the sender's own. A forwarded or typed-in contact is refused.
    if (message.contact.user_id !== senderId) {
      return deps.telegram.sendMessage(chatId, botTexts[language].ownNumberOnly, shareContactKeyboard(language));
    }
    const phone = normalizePhone(message.contact.phone_number);
    if (!phone || !(await deps.tokens.transition(waiting.token, ['awaiting_contact'], { status: 'verified', phone }))) {
      return deps.telegram.sendMessage(chatId, botTexts[language].linkExpired, removeKeyboard);
    }
    return deps.telegram.sendMessage(chatId, botTexts[language].done, removeKeyboard);
  }

  // Anything else: remind them what to do.
  if (waiting) return deps.telegram.sendMessage(chatId, botTexts[language].askContact, shareContactKeyboard(language));
  return deps.telegram.sendMessage(chatId, botTexts[language].openApp, removeKeyboard);
}
