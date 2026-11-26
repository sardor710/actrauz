// End-to-end check of account deletion against the hosted project (run it
// after `deploy.mjs migrations` and `deploy.mjs functions`):
//
//   1. A throw-away player signs in the way dev-login.mjs does (webhook
//      updates in place of Telegram).
//   2. delete-account is called with that player's access token: 200
//      {"status":"deleted"}.
//   3. Signing in again with the same phone gives a different user id, and a
//      new account.
//   4. The old auth user (read with the admin API) has the e-mail
//      deleted-<old id>@<sign-in domain> and is banned.
//   5. Both users are deleted again, even when an assertion fails.
//
//   node scripts/e2e-delete.mjs

import assert from 'node:assert/strict';
import { randomInt } from 'node:crypto';
import { call, createdUsersSql, env, removeAccounts, signIn, url } from './e2e-lib.mjs';
import { requireEnv, sql, step } from './env.mjs';

requireEnv(env, ['SUPABASE_SECRET_KEY']);

/** The domain sign-in addresses use: functions/_shared/supabase_deps.ts loginDomain(). */
const loginDomain = env.LOGIN_EMAIL_DOMAIN || new URL(url).hostname;

/** The auth user, read with the admin API and the project's secret key. */
async function adminUser(id) {
  const key = env.SUPABASE_SECRET_KEY;
  const res = await fetch(`${url}/auth/v1/admin/users/${id}`, {
    // A new-style sb_secret_ key is not a JWT: it goes in apikey alone.
    headers: key.startsWith('sb_secret_') ? { apikey: key } : { apikey: key, Authorization: `Bearer ${key}` },
  });
  assert.equal(res.status, 200, `admin read of ${id} failed: ${res.status} ${await res.text()}`);
  return res.json();
}

let failed = false;
try {
  step('A throw-away player signs in');
  const phone = `+99806${String(randomInt(10_000_000)).padStart(7, '0')}`;
  const first = await signIn('player', phone);
  assert.equal(first.isNew, true);

  step('A call without a valid token is refused');
  const anon = await call('/functions/v1/delete-account', { body: {} });
  assert.equal(anon.status, 401, `expected 401, got ${anon.status} ${JSON.stringify(anon.data)}`);
  console.log('  401 with the anon key');

  step('The player deletes the account');
  const deleted = await call('/functions/v1/delete-account', { body: {}, token: first.jwt });
  assert.equal(deleted.status, 200, `delete-account answered ${deleted.status} ${JSON.stringify(deleted.data)}`);
  assert.deepEqual(deleted.data, { status: 'deleted' });
  console.log('  200 {"status":"deleted"}');

  step('The same phone signs in as a new, empty account');
  const second = await signIn('same phone again', phone);
  assert.notEqual(second.userId, first.userId, 'a deleted account must not be signed back in');
  assert.equal(second.isNew, true);

  step('The old auth user is renamed and banned');
  const old = await adminUser(first.userId);
  assert.equal(old.email, `deleted-${first.userId}@${loginDomain}`);
  assert.ok(old.banned_until, 'the old auth user has no ban');
  assert.ok(
    new Date(old.banned_until).getTime() > Date.now() + 365 * 24 * 3600 * 1000,
    `ban ends too soon: ${old.banned_until}`,
  );
  const fresh = await adminUser(second.userId);
  assert.equal(fresh.email, `${phone.replace(/\D/g, '')}@${loginDomain}`);
  assert.ok(!fresh.banned_until || new Date(fresh.banned_until).getTime() < Date.now(), 'the new auth user is banned');
  console.log(`  ${old.email}, banned until ${old.banned_until}`);

  console.log('\nACCOUNT DELETION END TO END: PASSED');
} catch (e) {
  failed = true;
  console.error(`\nACCOUNT DELETION END TO END: FAILED\n${e.stack ?? e}`);
} finally {
  step('Cleaning up both throw-away users');
  await removeAccounts();
  const users = createdUsersSql();
  if (users) {
    try {
      const left = await sql(env, `select count(*)::int as n from auth.users where id in (${users})`);
      console.log(`  throw-away users left behind: ${left[0].n}`);
    } catch (e) {
      console.error(`  could not check what is left: ${e.message}`);
    }
  }
}
process.exit(failed ? 1 : 0);
