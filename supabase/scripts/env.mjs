// Shared by the scripts in this folder: reads supabase/.env and runs the
// Supabase CLI against the hosted project. Secret values are never printed.

import { spawn } from 'node:child_process';
import { readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));

/** D:\actra\supabase */
export const supabaseDir = path.resolve(here, '..');

/** D:\actra — the folder that contains supabase/, which the CLI wants. */
export const repoDir = path.resolve(supabaseDir, '..');

const envFile = path.join(supabaseDir, '.env');

export function loadEnv() {
  let text;
  try {
    text = readFileSync(envFile, 'utf8');
  } catch {
    throw new Error(`Missing ${envFile}. Copy .env.example to .env and fill it in.`);
  }
  const env = {};
  for (const line of text.split(/\r?\n/)) {
    const match = /^([A-Z0-9_]+)=(.*)$/.exec(line.trim());
    if (match) env[match[1]] = match[2].trim().replace(/^["'](.*)["']$/, '$1');
  }
  // The project ref is the first label of the project URL.
  const ref = /^https:\/\/([a-z0-9]{20})\.supabase\.co\/?$/.exec(env.SUPABASE_URL ?? '');
  if (!env.SUPABASE_PROJECT_REF && ref) env.SUPABASE_PROJECT_REF = ref[1];
  if (!env.SUPABASE_URL && env.SUPABASE_PROJECT_REF) env.SUPABASE_URL = `https://${env.SUPABASE_PROJECT_REF}.supabase.co`;
  return env;
}

/** Stops with the list of missing names (never values). */
export function requireEnv(env, names) {
  const missing = names.filter((name) => !env[name]);
  if (missing.length) {
    throw new Error(`supabase/.env is missing: ${missing.join(', ')}. See supabase/.env.example for where to find each.`);
  }
}

/** Writes one value back into supabase/.env, keeping the rest of the file. */
export function saveEnvValue(name, value) {
  const text = readFileSync(envFile, 'utf8');
  const line = new RegExp(`^${name}=.*$`, 'm');
  writeFileSync(envFile, line.test(text) ? text.replace(line, `${name}=${value}`) : `${text.trimEnd()}\n${name}=${value}\n`);
}

const cli = path.join(supabaseDir, 'node_modules', '.bin', process.platform === 'win32' ? 'supabase.cmd' : 'supabase');

/**
 * Runs the Supabase CLI. The access token and database password travel in
 * the environment, not on the command line.
 * `capture: true` returns stdout instead of showing it.
 */
export function supabase(env, args, { capture = false } = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(`"${cli}"`, [...args, '--workdir', `"${repoDir}"`], {
      shell: true,
      stdio: capture ? ['ignore', 'pipe', 'pipe'] : 'inherit',
      env: {
        ...process.env,
        // Without a token in .env the CLI uses the one saved by `supabase login`.
        ...(env.SUPABASE_ACCESS_TOKEN ? { SUPABASE_ACCESS_TOKEN: env.SUPABASE_ACCESS_TOKEN } : {}),
        ...(env.SUPABASE_DB_PASSWORD ? { SUPABASE_DB_PASSWORD: env.SUPABASE_DB_PASSWORD } : {}),
      },
    });
    let out = '';
    let err = '';
    child.stdout?.on('data', (d) => (out += d));
    child.stderr?.on('data', (d) => (err += d));
    child.on('error', reject);
    child.on('exit', (code) => {
      if (code === 0) resolve(out);
      else {
        // The CLI reports some failures on stdout; show both, minus the password.
        const detail = [err, out].map((s) => s.trim()).filter(Boolean).join('\n');
        const safe = env.SUPABASE_DB_PASSWORD ? detail.replaceAll(env.SUPABASE_DB_PASSWORD, '***') : detail;
        reject(new Error(`supabase ${args.slice(0, 2).join(' ')} failed (exit ${code})${safe ? `:\n${safe}` : ''}`));
      }
    });
  });
}

/**
 * Runs SQL on the hosted database through Supabase's Management API (plain
 * HTTPS) and returns the rows. This works on networks where the database
 * port itself is unreachable. Several statements in one call run as one
 * transaction: all of them apply or none do.
 */
export async function sql(env, query, { write = false } = {}) {
  requireEnv(env, ['SUPABASE_PROJECT_REF', 'SUPABASE_ACCESS_TOKEN']);
  const attempts = write ? 1 : 3; // never blindly repeat a write
  let lastError;
  for (let attempt = 1; attempt <= attempts; attempt++) {
    try {
      const res = await fetch(`https://api.supabase.com/v1/projects/${env.SUPABASE_PROJECT_REF}/database/query`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${env.SUPABASE_ACCESS_TOKEN}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({ query, read_only: !write }),
        signal: AbortSignal.timeout(120_000),
      });
      const text = await res.text();
      if (!res.ok) {
        let message = text;
        try {
          message = JSON.parse(text).message ?? text;
        } catch {}
        const error = new Error(`Database query failed (${res.status}): ${message}`);
        error.status = res.status;
        throw error;
      }
      const parsed = text ? JSON.parse(text) : [];
      return Array.isArray(parsed) ? parsed : [];
    } catch (e) {
      lastError = e;
      // An answer from the database is final; only a dropped connection is retried.
      if (e.status) throw e;
    }
  }
  throw lastError;
}

export async function telegram(env, method, body) {
  // Bot API calls here only read state or set it to a fixed value, so a
  // dropped connection is simply tried again.
  let res;
  for (let attempt = 1; ; attempt++) {
    try {
      res = await fetch(`https://api.telegram.org/bot${env.TELEGRAM_BOT_TOKEN}/${method}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body ?? {}),
        signal: AbortSignal.timeout(20_000),
      });
      break;
    } catch (e) {
      if (attempt === 4) throw new Error(`Could not reach Telegram for ${method}: ${e.cause?.code ?? e.message}`);
    }
  }
  const data = await res.json();
  if (!data.ok) throw new Error(`Telegram ${method} failed: ${data.description}`);
  return data.result;
}

export const step = (text) => console.log(`\n== ${text}`);
