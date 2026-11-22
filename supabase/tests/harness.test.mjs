import assert from 'node:assert/strict';
import { after, before, test } from 'node:test';
import { asAnon, asUser, createUser, freshDb } from './helpers/db.mjs';

let db;
before(async () => (db = await freshDb('harness')));
after(() => db.end());

test('the overlap constraint needs btree_gist, and it is installed', async () => {
  const { rows } = await db.pool.query(`select 1 from pg_extension where extname = 'btree_gist'`);
  assert.equal(rows.length, 1);
});

test('auth.uid() is the signed-in player, and null for a visitor', async () => {
  const user = await createUser(db.pool, 'Ali');
  assert.equal(await asUser(db.pool, user, async (c) => (await c.query('select auth.uid() as id')).rows[0].id), user);
  assert.equal(await asAnon(db.pool, async (c) => (await c.query('select auth.uid() as id')).rows[0].id), null);
});
