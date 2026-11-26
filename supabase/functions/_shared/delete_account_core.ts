// Account deletion (both app stores require it in the app), free of any
// runtime: everything it touches arrives through `DeleteDeps`, so the same
// code runs in the edge function and under `node --test`.
//
//   1. The player's JWT names the account.
//   2. scrub: public.delete_account_service cancels what is still to come,
//      deletes the personal rows and scrubs the profile (admins: refused).
//   3. closeAuthUser: the auth user is renamed and banned. Sign-in finds
//      accounts by their phone's address, so the old one can no longer be
//      reached and the same phone signs up as a new, empty account.
//
// Both steps are idempotent: when step 3 fails the client retries the whole
// call.

export interface DeleteDeps {
  /** The account a JWT belongs to; null for a missing, invalid or expired token. */
  userIdFromToken(token: string): Promise<string | null>;
  /** Scrubs the account; throws Error('admin_account') for an admin. */
  scrub(userId: string): Promise<void>;
  /** Renames and bans the auth user (closedAuthUser, on the sign-in domain). */
  closeAuthUser(userId: string): Promise<void>;
}

export type DeleteResult = { status: 'deleted' } | { error: 'unauthorized' | 'admin_account' };

/**
 * What closing an auth user writes with auth.admin.updateUserById. `domain`
 * is the one sign-in addresses use (supabase_deps.ts loginDomain), which
 * auth accepts; sign-in local parts are digits only, so `deleted-<id>` never
 * collides with one.
 */
export const closedAuthUser = (userId: string, domain: string) => ({
  email: `deleted-${userId}@${domain}`,
  ban_duration: '876000h',
  app_metadata: { phone: null, deleted: true },
});

export async function deleteAccount(deps: DeleteDeps, accessToken: string): Promise<DeleteResult> {
  const userId = accessToken ? await deps.userIdFromToken(accessToken) : null;
  if (!userId) return { error: 'unauthorized' };
  try {
    await deps.scrub(userId);
  } catch (e) {
    if (e instanceof Error && e.message === 'admin_account') return { error: 'admin_account' };
    throw e;
  }
  await deps.closeAuthUser(userId);
  return { status: 'deleted' };
}
