import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import pg from 'pg';

// `timestamp without time zone` is venue wall-clock time: keep it as the
// string Postgres prints, never as a JS Date in the machine's zone.
pg.types.setTypeParser(1114, (v) => v.replace(' ', 'T'));
pg.types.setTypeParser(1115, (v) => pg.types.arrayParser(v, (s) => s.replace(' ', 'T')));

const adminUrl = process.env.ACTRA_PG_ADMIN_URL;
if (!adminUrl) throw new Error('Run the tests with `npm test` (tests/run.mjs starts Postgres).');

function urlFor(database) {
  const url = new URL(adminUrl);
  url.pathname = `/${database}`;
  return url.toString();
}

/** A new database cloned from the migrated template; dropped by `end()`. */
export async function freshDb(name) {
  const database = `t_${name}_${randomUUID().slice(0, 8)}`;
  const admin = new pg.Client({ connectionString: adminUrl });
  await admin.connect();
  await admin.query(`create database ${database} template actra_template`);
  await admin.end();

  const pool = new pg.Pool({ connectionString: urlFor(database), max: 12, statement_timeout: 20000 });
  return {
    pool,
    connect: () => pool.connect(),
    async end() {
      await pool.end();
      const a = new pg.Client({ connectionString: adminUrl });
      await a.connect();
      await a.query(`drop database if exists ${database} with (force)`);
      await a.end();
    },
  };
}

/** A player: a row in auth.users and in profiles. */
export async function createUser(pool, name) {
  const id = randomUUID();
  await pool.query(`insert into auth.users (id, aud, role, email) values ($1, 'authenticated', 'authenticated', $2)`, [
    id,
    `${id}@test.invalid`,
  ]);
  await pool.query(`insert into public.profiles (id, full_name) values ($1, $2)`, [id, name]);
  return id;
}

async function asRole(pool, role, sub, fn) {
  const client = await pool.connect();
  try {
    await client.query('begin');
    await client.query(`select set_config('request.jwt.claims', $1, true)`, [sub ? JSON.stringify({ sub, role }) : '']);
    await client.query(`set local role ${role}`);
    const result = await fn(client);
    await client.query('commit');
    return result;
  } catch (e) {
    await client.query('rollback').catch(() => {});
    throw e;
  } finally {
    client.release();
  }
}

/** Runs `fn(client)` in one transaction as a signed-in player, as the API would. */
export const asUser = (pool, userId, fn) => asRole(pool, 'authenticated', userId, fn);

/** Runs `fn(client)` in one transaction as a visitor who is not signed in. */
export const asAnon = (pool, fn) => asRole(pool, 'anon', null, fn);

/**
 * The promise must reject with a Postgres error whose SQLSTATE or message is
 * `code` ("42501", "23P01", or one of the function error codes such as
 * "slot_taken").
 */
export async function expectError(promise, code) {
  let error;
  try {
    await promise;
  } catch (e) {
    error = e;
  }
  assert.ok(error, `expected an error "${code}", but the call succeeded`);
  assert.ok(error.code === code || error.message === code, `expected "${code}", got ${error.code}: ${error.message}`);
}

/** The error code of a rejected call, or null when it succeeded. */
export async function errorOf(promise) {
  try {
    await promise;
    return null;
  } catch (e) {
    return e.code === 'P0001' ? e.message : e.code;
  }
}
