// Hides the invented sample venues and tournament in Kazakhstan from real
// players, ahead of the Kazakhstan launch.
//
//   node scripts/hide-samples.mjs           dry run: lists the rows, changes nothing
//   node scripts/hide-samples.mjs --apply   sets active = false on those rows and
//                                           writes one audit_log row (action
//                                           hide_sample) per row changed
//
// Targets: venues md5('actra:v4'), md5('actra:v5'), md5('actra:v6') and the
// tournament md5('actra:t3'), all in Almaty/Astana. Nothing in Tashkent is
// touched. Safe to repeat: rows already hidden are listed but not changed again
// and get no second audit row. Games and requests at a hidden venue drop out of
// the player lists (20261126110000_launch.sql).
//
// Reads supabase/.env (git-ignored). Runs SQL through the Management API like
// deploy.mjs does, so it needs no database port. Run it against the live
// project only at deploy time, with the founder's go-ahead.

import { loadEnv, requireEnv, sql } from './env.mjs';

const apply = process.argv.includes('--apply');
const unknown = process.argv.slice(2).filter((a) => a !== '--apply');
if (unknown.length) {
  console.error(`Unknown argument: ${unknown.join(' ')}. Only --apply is accepted.`);
  process.exit(1);
}

const env = loadEnv();
requireEnv(env, ['SUPABASE_PROJECT_REF', 'SUPABASE_ACCESS_TOKEN']);

// The fixed ids come from this file, never from input.
const venueSeeds = ['actra:v4', 'actra:v5', 'actra:v6'];
const tournamentSeeds = ['actra:t3'];
const ids = (seeds) => seeds.map((s) => `md5('${s}')::uuid`).join(', ');

const listQuery = `
  select 'venue' as entity, v.id::text as id, v.city_id,
         coalesce(v.name_en, v.name_ru, v.name_uz) as name, v.active
  from public.venues v where v.id in (${ids(venueSeeds)})
  union all
  select 'tournament', t.id::text, t.city_id,
         coalesce(t.title_en, t.title_ru, t.title_uz), t.active
  from public.tournaments t where t.id in (${ids(tournamentSeeds)})
  order by 1 desc, 4`;

// One statement, so it applies as one transaction. Only rows that are still
// active change, and each change gets its audit row (actor unknown: null).
const applyQuery = `
  with hidden_venues as (
    update public.venues v set active = false
    where v.id in (${ids(venueSeeds)}) and v.active
    returning v.id
  ), hidden_tournaments as (
    update public.tournaments t set active = false
    where t.id in (${ids(tournamentSeeds)}) and t.active
    returning t.id
  )
  insert into public.audit_log (actor_id, action, entity, entity_id, before, after, created_at)
  select null, 'hide_sample', 'venue', id::text, '{"active": true}'::jsonb, '{"active": false}'::jsonb, now() from hidden_venues
  union all
  select null, 'hide_sample', 'tournament', id::text, '{"active": true}'::jsonb, '{"active": false}'::jsonb, now() from hidden_tournaments
  returning entity, entity_id`;

const show = (rows) => {
  for (const r of rows) console.log(`  ${r.entity.padEnd(10)} ${String(r.city_id).padEnd(8)} active=${String(r.active).padEnd(5)} ${r.name}`);
};

const before = await sql(env, listQuery);
console.log(apply ? 'Sample rows before:' : 'DRY RUN. Sample rows that --apply would hide:');
show(before);
const expected = venueSeeds.length + tournamentSeeds.length;
if (before.length !== expected) console.log(`  Note: found ${before.length} of ${expected} rows (the others are not in this database).`);

if (!apply) {
  const pending = before.filter((r) => r.active).length;
  console.log(`\n${pending} row(s) would change. Nothing was changed. Run with --apply to hide them.`);
} else {
  const changed = await sql(env, applyQuery, { write: true });
  console.log(`\nHid ${changed.length} row(s); wrote ${changed.length} audit_log row(s) with action hide_sample.`);
  console.log('Sample rows now:');
  show(await sql(env, listQuery));
}
