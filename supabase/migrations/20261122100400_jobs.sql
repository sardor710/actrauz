-- Scheduled work: every minute, release holds nobody confirmed.
--
-- hold_slots already sweeps the court it writes to and availability ignores
-- expired holds, so this job only keeps the table tidy. It needs pg_cron,
-- which hosted Supabase has; where it is missing (plain Postgres in tests)
-- this migration does nothing.

do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron;
    execute $job$
      select cron.schedule(
        'actra-release-expired-holds',
        '* * * * *',
        'select app.release_expired_holds(now())')
    $job$;
  end if;
end $$;
