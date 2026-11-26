// Account deletion with the database and auth faked.
// Run by `npm test` (node --test strips the TypeScript types).

import assert from 'node:assert/strict';
import { test } from 'node:test';
import { closedAuthUser, deleteAccount } from './delete_account_core.ts';
import type { DeleteDeps } from './delete_account_core.ts';
import { handleDeleteRequest } from './http.ts';

/** Fake deps that record the calls; `jwt-<id>` is a valid token for <id>. */
function fakeDeps(overrides: Partial<DeleteDeps> = {}) {
  const calls: string[] = [];
  const deps: DeleteDeps = {
    userIdFromToken: async (token) => (token.startsWith('jwt-') ? token.slice(4) : null),
    scrub: async (userId) => void calls.push(`scrub ${userId}`),
    closeAuthUser: async (userId) => void calls.push(`close ${userId}`),
    ...overrides,
  };
  return { deps, calls };
}

test('an unknown or missing token is unauthorized and nothing is scrubbed', async () => {
  const { deps, calls } = fakeDeps();
  assert.deepEqual(await deleteAccount(deps, 'garbage'), { error: 'unauthorized' });
  assert.deepEqual(await deleteAccount(deps, ''), { error: 'unauthorized' });
  assert.deepEqual(calls, []);
});

test('an admin account is refused and the auth user is left alone', async () => {
  const { deps, calls } = fakeDeps({
    scrub: async () => {
      throw new Error('admin_account');
    },
  });
  assert.deepEqual(await deleteAccount(deps, 'jwt-u1'), { error: 'admin_account' });
  assert.deepEqual(calls, []);
});

test('the account is scrubbed first, then the auth user is closed', async () => {
  const { deps, calls } = fakeDeps();
  assert.deepEqual(await deleteAccount(deps, 'jwt-u1'), { status: 'deleted' });
  assert.deepEqual(calls, ['scrub u1', 'close u1']);
});

test('closing the auth user failing after the scrub is an error the client retries', async () => {
  const { deps, calls } = fakeDeps({
    closeAuthUser: async () => {
      throw new Error('auth is down');
    },
  });
  await assert.rejects(deleteAccount(deps, 'jwt-u1'), /auth is down/);
  assert.deepEqual(calls, ['scrub u1']);
});

test('any other scrub failure is an error, and the auth user is not closed', async () => {
  const { deps, calls } = fakeDeps({
    scrub: async () => {
      throw new Error('connection reset');
    },
  });
  await assert.rejects(deleteAccount(deps, 'jwt-u1'), /connection reset/);
  assert.deepEqual(calls, []);
});

test('a closed auth user is renamed, banned and loses its phone', () => {
  assert.deepEqual(closedAuthUser('3f1c'), {
    email: 'deleted-3f1c@deleted.actra.invalid',
    ban_duration: '876000h',
    app_metadata: { phone: null, deleted: true },
  });
});

// ---- HTTP edge ----

const call = (headers: Record<string, string> = {}, method = 'POST') =>
  new Request('https://example.test/delete-account', { method, headers });

test('delete endpoint: 200 deleted, 403 admin, 401 without a valid JWT, CORS for the web app', async () => {
  const { deps, calls } = fakeDeps();
  const ok = await handleDeleteRequest(deps, call({ Authorization: 'Bearer jwt-u1' }));
  assert.equal(ok.status, 200);
  assert.equal(ok.headers.get('Access-Control-Allow-Origin'), '*');
  assert.deepEqual(await ok.json(), { status: 'deleted' });
  assert.deepEqual(calls, ['scrub u1', 'close u1']);

  for (const headers of [{}, { Authorization: 'Bearer nope' }, { Authorization: 'jwt-u2' }]) {
    const res = await handleDeleteRequest(deps, call(headers));
    assert.equal(res.status, 401);
    assert.deepEqual(await res.json(), { error: 'unauthorized' });
  }
  assert.deepEqual(calls, ['scrub u1', 'close u1'], 'nothing else was touched');

  const admin = fakeDeps({
    scrub: async () => {
      throw new Error('admin_account');
    },
  });
  const refused = await handleDeleteRequest(admin.deps, call({ Authorization: 'Bearer jwt-u3' }));
  assert.equal(refused.status, 403);
  assert.deepEqual(await refused.json(), { error: 'admin_account' });

  const preflight = await handleDeleteRequest(deps, call({}, 'OPTIONS'));
  assert.equal(preflight.headers.get('Access-Control-Allow-Origin'), '*');
  assert.equal((await handleDeleteRequest(deps, call({}, 'GET'))).status, 405);
});

test('delete endpoint: a failure is a 500 the client can retry', async () => {
  const { deps } = fakeDeps({
    closeAuthUser: async () => {
      throw new Error('auth is down');
    },
  });
  const original = console.error;
  console.error = () => {};
  try {
    const res = await handleDeleteRequest(deps, call({ Authorization: 'Bearer jwt-u1' }));
    assert.equal(res.status, 500);
    assert.deepEqual(await res.json(), { error: 'server_error' });
  } finally {
    console.error = original;
  }
});
