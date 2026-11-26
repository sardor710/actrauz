// Connects the sign-in logic to the real world: the database and auth
// through supabase-js with the service role, and the Telegram Bot API.
// Deno-only; the logic it serves is in login_core.ts and
// delete_account_core.ts.

import { createClient } from 'npm:@supabase/supabase-js@2';
import type { SupabaseClient } from 'npm:@supabase/supabase-js@2';
import { authUserFor } from './login_core.ts';
import type { AuthAccounts, Deps, LoginToken, TokenStatus } from './login_core.ts';
import { closedAuthUser } from './delete_account_core.ts';
import type { DeleteDeps } from './delete_account_core.ts';
import type { Language } from './bot_texts.ts';

const env = (name: string): string => {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`Function secret ${name} is not set`);
  return value;
};

const base64url = (bytes: Uint8Array) =>
  btoa(String.fromCharCode(...bytes)).replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '');

/**
 * Supabase issues sessions for an e-mail or a phone with an SMS provider.
 * Actra verifies the phone through Telegram instead, so each account gets a
 * private placeholder address derived from its number. No mail is ever sent
 * to it. By default it sits under this project's own host name, which
 * resolves (so address validation accepts it) and has no mailbox. Closed
 * (deleted) accounts are renamed under the same domain.
 */
const loginDomain = () => Deno.env.get('LOGIN_EMAIL_DOMAIN') || new URL(env('SUPABASE_URL')).hostname;

const loginEmail = (phone: string) => `${phone.replace(/\D/g, '')}@${loginDomain()}`;

const must = <T>(result: { data: T; error: { message: string } | null }): T => {
  if (result.error) throw new Error(result.error.message);
  return result.data;
};

function adminClient(): SupabaseClient {
  // The project's secret key when it was set as a function secret (new-style
  // sb_secret_ keys), else the service-role key every function is given.
  const adminKey = Deno.env.get('ACTRA_SECRET_KEY') || env('SUPABASE_SERVICE_ROLE_KEY');
  return createClient(env('SUPABASE_URL'), adminKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

/** Renames (on the sign-in domain) and bans the auth user (delete_account_core.ts). */
const closeAuthUser = (admin: SupabaseClient) => async (userId: string) => {
  const { error } = await admin.auth.admin.updateUserById(userId, closedAuthUser(userId, loginDomain()));
  if (error) throw new Error(error.message);
};

export function makeDeps(): Deps {
  const admin = adminClient();
  const botToken = env('TELEGRAM_BOT_TOKEN');

  const authAccounts: AuthAccounts = {
    create: async (email, phone) => {
      const created = await admin.auth.admin.createUser({ email, email_confirm: true, app_metadata: { phone } });
      return { userId: created.data?.user?.id, error: created.error?.message };
    },
    findByEmail: async (email) => {
      const existing = await admin.auth.admin.generateLink({ type: 'magiclink', email });
      return { userId: existing.data?.user?.id, error: existing.error?.message };
    },
    isDeleted: async (userId) =>
      (must(await admin.from('profiles').select('deleted_at').eq('id', userId).maybeSingle()) as { deleted_at: string | null } | null)
        ?.deleted_at != null,
    close: closeAuthUser(admin),
  };

  /** A Telegram account points at one Actra account at a time. */
  const linkTelegram = async (userId: string, telegramUserId: number) => {
    must(await admin.from('profile_contacts').update({ telegram_user_id: null }).eq('telegram_user_id', telegramUserId).neq('user_id', userId));
    must(await admin.from('profile_contacts').update({ telegram_user_id: telegramUserId }).eq('user_id', userId));
  };

  return {
    botUsername: env('TELEGRAM_BOT_USERNAME'),
    now: () => new Date(),
    randomToken: () => base64url(crypto.getRandomValues(new Uint8Array(24))),
    sha256: async (text) => {
      const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(text));
      return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, '0')).join('');
    },

    tokens: {
      insert: async (row: LoginToken) => void must(await admin.from('login_tokens').insert(row)),
      get: async (token: string) =>
        must(await admin.from('login_tokens').select('*').eq('token', token).maybeSingle()) as LoginToken | null,
      transition: async (token: string, from: TokenStatus[], patch: Partial<LoginToken>) => {
        const rows = must(await admin.from('login_tokens').update(patch).eq('token', token).in('status', from).select('token'));
        return (rows ?? []).length > 0;
      },
      findAwaiting: async (telegramUserId: number, nowIso: string) =>
        must(
          await admin
            .from('login_tokens')
            .select('*')
            .eq('telegram_user_id', telegramUserId)
            .eq('status', 'awaiting_contact')
            .gt('expires_at', nowIso)
            .order('created_at', { ascending: false })
            .limit(1)
            .maybeSingle(),
        ) as LoginToken | null,
      purgeExpired: async (beforeIso: string) => void must(await admin.from('login_tokens').delete().lt('expires_at', beforeIso)),
    },

    users: {
      findByPhone: async (phone: string) => {
        const row = must(await admin.from('profile_contacts').select('user_id').eq('phone', phone).maybeSingle());
        return row ? { userId: row.user_id as string } : null;
      },

      create: async (phone: string, telegramUserId: number | null, language: Language) => {
        // Picks up an auth user an earlier attempt left behind, unless its
        // account was deleted (login_core.ts authUserFor).
        const userId = await authUserFor(authAccounts, loginEmail(phone), phone);
        must(await admin.from('profiles').upsert({ id: userId, language }, { onConflict: 'id', ignoreDuplicates: true }));
        must(await admin.from('profile_contacts').upsert({ user_id: userId, phone }, { onConflict: 'user_id' }));
        if (telegramUserId !== null) await linkTelegram(userId, telegramUserId);
        return { userId };
      },

      linkTelegram,

      issueSessionToken: async (userId: string, phone: string) => {
        // The address the account was created with, even if the default
        // domain has changed since.
        const account = await admin.auth.admin.getUserById(userId);
        const email = account.data?.user?.email ?? loginEmail(phone);
        const link = await admin.auth.admin.generateLink({ type: 'magiclink', email });
        const hash = link.data?.properties?.hashed_token;
        if (!hash) throw new Error(link.error?.message ?? 'could not issue a session');
        return hash;
      },
    },

    telegram: {
      sendMessage: async (chatId: number, text: string, replyMarkup?: unknown) => {
        const res = await fetch(`https://api.telegram.org/bot${botToken}/sendMessage`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ chat_id: chatId, text, reply_markup: replyMarkup }),
        });
        if (!res.ok) throw new Error(`Telegram sendMessage failed: ${res.status} ${await res.text()}`);
      },
    },
  };
}

/** The delete-account function's deps: the database and auth with the service role. */
export function makeDeleteDeps(): DeleteDeps {
  const admin = adminClient();
  return {
    userIdFromToken: async (token) => {
      const { data, error } = await admin.auth.getUser(token);
      return error ? null : (data.user?.id ?? null);
    },
    // A refusal arrives as the exception's message ('admin_account').
    scrub: async (userId) => void must(await admin.rpc('delete_account_service', { p_user: userId })),
    closeAuthUser: closeAuthUser(admin),
  };
}
