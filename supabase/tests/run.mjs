// Runs the database and edge-function tests.
//
// Starts a throw-away Postgres (the `embedded-postgres` package, no Docker),
// builds the template database from tests/helpers/shim.sql plus every
// migration in name order, runs `node --test`, then stops Postgres.
// Set ACTRA_TEST_DATABASE_URL to use a server that is already running.

import { spawn } from 'node:child_process';
import { readdir, readFile, rm } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import pg from 'pg';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '..');
const dataDir = path.join(here, '.pgdata');
const port = Number(process.env.ACTRA_TEST_PG_PORT ?? 54329);

let server = null;
let adminUrl = process.env.ACTRA_TEST_DATABASE_URL;

async function startPostgres() {
  const { default: EmbeddedPostgres } = await import('embedded-postgres');
  await rm(dataDir, { recursive: true, force: true });
  server = new EmbeddedPostgres({
    databaseDir: dataDir,
    user: 'postgres',
    password: 'postgres',
    port,
    persistent: false,
    // Hosted Supabase is UTF-8; do not inherit the Windows code page.
    initdbFlags: ['--encoding=UTF8', '--locale=C'],
    onLog: () => {},
    onError: () => {},
  });
  await server.initialise();
  await server.start();
  adminUrl = `postgres://postgres:postgres@127.0.0.1:${port}/postgres`;
}

async function buildTemplate() {
  const admin = new pg.Client({ connectionString: adminUrl });
  await admin.connect();
  await admin.query('drop database if exists actra_template with (force)');
  await admin.query('create database actra_template');
  await admin.end();

  const url = new URL(adminUrl);
  url.pathname = '/actra_template';
  const db = new pg.Client({ connectionString: url.toString() });
  await db.connect();
  try {
    await db.query(await readFile(path.join(here, 'helpers', 'shim.sql'), 'utf8'));
    const dir = path.join(root, 'migrations');
    for (const file of (await readdir(dir)).filter((f) => f.endsWith('.sql')).sort()) {
      try {
        await db.query(await readFile(path.join(dir, file), 'utf8'));
      } catch (e) {
        throw new Error(`Migration ${file} failed: ${e.message}`, { cause: e });
      }
    }
  } finally {
    await db.end();
  }
}

async function findTests() {
  const files = [];
  for (const dir of [here, path.join(root, 'functions', '_shared')]) {
    for (const f of await readdir(dir).catch(() => [])) {
      if (/\.test\.(mjs|ts)$/.test(f)) files.push(path.join(dir, f));
    }
  }
  const only = process.argv.slice(2);
  return only.length ? files.filter((f) => only.some((o) => f.includes(o))) : files;
}

function runTests(files) {
  return new Promise((resolve) => {
    const child = spawn(process.execPath, ['--test', '--test-concurrency=1', '--test-timeout=120000', ...files], {
      stdio: 'inherit',
      env: { ...process.env, ACTRA_PG_ADMIN_URL: adminUrl, ACTRA_ROOT: root },
    });
    child.on('exit', (code) => resolve(code ?? 1));
  });
}

// Never leave Postgres running behind a cancelled run.
for (const signal of ['SIGINT', 'SIGTERM', 'SIGBREAK']) {
  process.on(signal, async () => {
    if (server) await server.stop().catch(() => {});
    process.exit(130);
  });
}

let code = 1;
try {
  if (!adminUrl) await startPostgres();
  await buildTemplate();
  code = await runTests(await findTests());
} catch (e) {
  console.error(e.message);
  if (e.cause?.position) console.error(`  at character ${e.cause.position}`);
} finally {
  if (server) await server.stop().catch(() => {});
}
process.exit(code);
