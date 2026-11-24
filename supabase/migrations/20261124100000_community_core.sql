-- Community core (Milestone 4a): notifications, reliability, player
-- settings, and the hooks that connect bookings to them.
--
-- Additive only: new tables and columns, `create or replace` for the four
-- booking functions that gain hooks (same signatures, so grants stay). As
-- elsewhere, the rules live in the private `app` schema and take the acting
-- user and the clock; the `public` wrappers pass auth.uid() and now().
-- The database stores no sentences: the app renders text from kind + payload.

-- ---------------------------------------------------------------------------
-- Columns
-- ---------------------------------------------------------------------------

alter table public.profiles
  add column muted_categories text[] not null default '{}',
  add column hidden_from_search boolean not null default false;

alter table public.bookings add column reminded_at timestamptz;

-- ---------------------------------------------------------------------------
-- Notifications: written by app.notify only, read by their owner.
-- ---------------------------------------------------------------------------

create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  kind text not null,
  category text not null check (category in ('bookings', 'venue', 'games', 'requests', 'invites')),
  payload jsonb not null default '{}',
  created_at timestamptz not null default now(),
  read_at timestamptz
);
create index notifications_user_idx on public.notifications (user_id, created_at desc);

alter table public.notifications enable row level security;
revoke all on table public.notifications from anon, authenticated;
grant all on table public.notifications to service_role;
grant select on table public.notifications to authenticated;
create policy "players see their own notifications" on public.notifications for select to authenticated
  using (user_id = (select auth.uid()));

-- Live inbox updates, where Supabase Realtime exists (not in plain Postgres).
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table public.notifications;
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- Reliability events: no client access at all.
-- ---------------------------------------------------------------------------

create table public.reliability_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  kind text not null check (kind in ('no_show', 'late_cancel', 'booking_paid', 'game_completed')),
  delta integer not null,
  -- The booking or game the event is about.
  ref text not null,
  created_at timestamptz not null default now(),
  unique (user_id, kind, ref)
);
create index reliability_events_user_idx on public.reliability_events (user_id, created_at desc);

alter table public.reliability_events enable row level security;
revoke all on table public.reliability_events from anon, authenticated;
grant all on table public.reliability_events to service_role;

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

-- {"uz","ru","en"}: the app picks the language.
create function app.venue_name(p_venue_id uuid) returns jsonb
language sql stable
set search_path = ''
as $$
  select jsonb_build_object('uz', v.name_uz, 'ru', v.name_ru, 'en', v.name_en)
  from public.venues v where v.id = p_venue_id
$$;

-- Adds one notification unless the player muted its category.
create function app.notify(p_user uuid, p_kind text, p_category text, p_payload jsonb, p_now timestamptz)
returns void
language plpgsql
set search_path = ''
as $$
begin
  if p_user is null then return; end if;
  insert into public.notifications (user_id, kind, category, payload, created_at)
  select p.id, p_kind, p_category, coalesce(p_payload, '{}'), p_now
  from public.profiles p
  where p.id = p_user and not (p_category = any (p.muted_categories));
end $$;

-- Records a reliability event once per (player, kind, ref).
create function app.reliability_event(p_user uuid, p_kind text, p_ref text, p_now timestamptz)
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_delta integer := case p_kind
    when 'no_show' then -20
    when 'late_cancel' then -5
    when 'booking_paid' then 2
    when 'game_completed' then 2
  end;
begin
  if v_delta is null then raise exception 'invalid_argument'; end if;
  if p_user is null then return; end if;
  insert into public.reliability_events (user_id, kind, delta, ref, created_at)
  values (p_user, p_kind, v_delta, p_ref, p_now)
  on conflict (user_id, kind, ref) do nothing;
end $$;

-- Score and badge as of p_now. Only the last 90 days count towards the score;
-- "new" looks at all events ever, so a quiet player is not "reliable" by luck.
create function app.reliability(p_user uuid, p_now timestamptz) returns jsonb
language plpgsql stable
set search_path = ''
as $$
declare
  v_sum integer;
  v_ever integer;
  v_score integer;
begin
  select coalesce(sum(e.delta) filter (where e.created_at > p_now - interval '90 days'), 0), count(*)
    into v_sum, v_ever
  from public.reliability_events e where e.user_id = p_user;
  v_score := greatest(0, least(100, 80 + v_sum));
  return jsonb_build_object(
    'score', v_score,
    'badge', case
      when v_score >= 70 and v_ever < 3 then 'new'
      when v_score >= 70 then 'reliable'
      when v_score >= 50 then 'limited'
      else 'blocked'
    end);
end $$;

create function app.require_reliable(p_user uuid, p_now timestamptz) returns void
language plpgsql stable
set search_path = ''
as $$
begin
  if app.reliability(p_user, p_now)->>'badge' = 'blocked' then
    raise exception 'reliability_too_low';
  end if;
end $$;

-- What every booking notification carries.
create function app.booking_note(p_booking public.bookings) returns jsonb
language sql stable
set search_path = ''
as $$
  select jsonb_build_object(
    'booking_id', p_booking.id,
    'venue_name', app.venue_name(p_booking.venue_id),
    'sport_id', c.sport_id,
    'starts_local', app.to_local(lower(p_booking.during), p_booking.utc_offset_minutes))
  from public.courts c where c.id = p_booking.court_id
$$;

-- Tells every owner of the booking's venue about a new or cancelled booking.
create function app.notify_owners(p_booking public.bookings, p_kind text, p_now timestamptz) returns void
language plpgsql
set search_path = ''
as $$
declare
  v_payload jsonb;
  v_owner uuid;
begin
  v_payload := app.booking_note(p_booking) - 'venue_name' || jsonb_build_object(
    'venue_id', p_booking.venue_id,
    'court_name', (select coalesce(c.name_en, c.name_ru, c.name_uz) from public.courts c where c.id = p_booking.court_id),
    'actor_name', (select p.full_name from public.profiles p where p.id = p_booking.user_id));
  for v_owner in select o.user_id from public.venue_owners o where o.venue_id = p_booking.venue_id loop
    perform app.notify(v_owner, p_kind, 'venue', v_payload, p_now);
  end loop;
end $$;

-- ---------------------------------------------------------------------------
-- Booking functions, redefined from their latest definitions
-- (hold_slots and cancel_booking from owner.sql; confirm_booking from
-- bookings.sql) with the new hooks.
-- ---------------------------------------------------------------------------

create or replace function app.hold_slots(p_user uuid, p_court_id uuid, p_starts timestamp[], p_now timestamptz)
returns public.bookings
language plpgsql
set search_path = ''
as $$
declare
  c_hold constant interval := interval '5 minutes';
  c_max_upcoming constant integer := 3;
  c_max_days_ahead constant integer := 14;

  v_venue_id uuid;
  v_offset integer;
  v_currency text;
  v_starts timestamp[];
  v_count integer := coalesce(cardinality(p_starts), 0);
  v_day_starts timestamp[];
  v_day_ends timestamp[];
  v_day_prices integer[];
  v_index integer;
  v_previous_end timestamp;
  v_total integer := 0;
  v_first timestamp;
  v_last_end timestamp;
  v_cap integer := c_max_upcoming;
  v_booking public.bookings;
begin
  if p_user is null then raise exception 'not_authenticated'; end if;
  if v_count = 0 then raise exception 'empty_selection'; end if;

  select c.venue_id, ci.utc_offset_minutes, ci.currency into v_venue_id, v_offset, v_currency
  from public.courts c
  join public.venues v on v.id = c.venue_id
  join public.cities ci on ci.id = v.city_id
  where c.id = p_court_id;
  if not found then raise exception 'not_found'; end if;

  select array_agg(s order by s) into v_starts from unnest(p_starts) s;
  v_first := v_starts[1];

  -- Every requested time must be a slot the court really offers that day.
  select array_agg(s.starts_local order by s.starts_local),
         array_agg(s.ends_local order by s.starts_local),
         array_agg(s.price order by s.starts_local)
    into v_day_starts, v_day_ends, v_day_prices
  from app.court_slots(p_court_id, v_first::date) s;

  for i in 1..v_count loop
    if v_starts[i] is null or array_position(v_day_starts, v_starts[i]) is null then
      raise exception 'not_found';
    end if;
  end loop;

  -- Back to back, and priced slot by slot as of this moment.
  for i in 1..v_count loop
    v_index := array_position(v_day_starts, v_starts[i]);
    if i > 1 and v_starts[i] <> v_previous_end then raise exception 'not_contiguous'; end if;
    v_previous_end := v_day_ends[v_index];
    v_total := v_total + v_day_prices[v_index];
  end loop;
  v_last_end := v_previous_end;

  if app.to_instant(v_first, v_offset) <= p_now then raise exception 'in_past'; end if;
  if v_first::date - app.to_local(p_now, v_offset)::date > c_max_days_ahead then
    raise exception 'too_far_ahead';
  end if;

  -- One request at a time per player: a double tap cannot leave two holds
  -- or slip past the limit below.
  perform 1 from public.profiles p where p.id = p_user for update;
  if not found then raise exception 'not_authenticated'; end if;

  -- Reliability (spec 8.3): blocked players cannot book, limited players
  -- may keep one upcoming booking instead of three.
  perform app.require_reliable(p_user, p_now);
  if app.reliability(p_user, p_now)->>'badge' = 'limited' then v_cap := 1; end if;

  if (select count(*) from public.bookings b
      where b.user_id = p_user and b.source = 'app' and b.status = 'confirmed'
        and lower(b.during) > p_now) >= v_cap then
    raise exception 'too_many_bookings';
  end if;

  -- One hold request at a time per court, so the loser waits and gets a
  -- clean "taken" instead of a deadlock. The constraint is still the guard.
  perform pg_advisory_xact_lock(hashtextextended(p_court_id::text, 0));

  update public.bookings b set status = 'released', hold_expires_at = null
  where b.user_id = p_user and b.status = 'held';

  update public.bookings b set status = 'released'
  where b.court_id = p_court_id and b.status = 'held' and b.hold_expires_at <= p_now;

  begin
    insert into public.bookings (
      user_id, venue_id, court_id, during, utc_offset_minutes, slot_count, total_price, currency,
      status, hold_expires_at, created_at)
    values (
      p_user, v_venue_id, p_court_id,
      tstzrange(app.to_instant(v_first, v_offset), app.to_instant(v_last_end, v_offset), '[)'),
      v_offset, v_count, v_total, v_currency,
      'held', p_now + c_hold, p_now)
    returning * into v_booking;
  exception when exclusion_violation or deadlock_detected then
    raise exception 'slot_taken';
  end;

  return v_booking;
end $$;

create or replace function app.confirm_booking(p_user uuid, p_booking_id uuid, p_players integer, p_note text, p_now timestamptz)
returns public.bookings
language plpgsql
set search_path = ''
as $$
declare
  v_booking public.bookings;
begin
  if p_user is null then raise exception 'not_authenticated'; end if;

  select b.* into v_booking from public.bookings b
  where b.id = p_booking_id and b.user_id = p_user
  for update;
  if not found then raise exception 'not_found'; end if;

  -- A hold that ran out, whether or not someone has swept it up yet.
  if (v_booking.status = 'held' and v_booking.hold_expires_at <= p_now)
     or (v_booking.status = 'released' and v_booking.hold_expires_at is not null) then
    raise exception 'hold_expired';
  end if;
  if v_booking.status <> 'held' then raise exception 'not_found'; end if;

  update public.bookings b
  set status = 'confirmed',
      hold_expires_at = null,
      players = coalesce(p_players, b.players),
      note = coalesce(nullif(btrim(p_note), ''), b.note),
      confirmed_at = p_now
  where b.id = p_booking_id
  returning * into v_booking;

  perform app.notify(p_user, 'booking_confirmed', 'bookings', app.booking_note(v_booking), p_now);
  perform app.notify_owners(v_booking, 'venue_new_booking', p_now);
  return v_booking;
end $$;

create or replace function app.cancel_booking(p_user uuid, p_booking_id uuid, p_now timestamptz)
returns public.bookings
language plpgsql
set search_path = ''
as $$
declare
  c_free_window constant interval := interval '6 hours';
  v_booking public.bookings;
begin
  if p_user is null then raise exception 'not_authenticated'; end if;

  select b.* into v_booking from public.bookings b
  where b.id = p_booking_id and b.user_id = p_user
  for update;
  if not found then raise exception 'not_found'; end if;
  if v_booking.source <> 'app' or v_booking.status <> 'confirmed' or lower(v_booking.during) <= p_now then
    raise exception 'not_cancellable';
  end if;

  update public.bookings b
  set status = 'cancelled_by_player',
      late_cancellation = (lower(b.during) - p_now) < c_free_window,
      cancelled_at = p_now
  where b.id = p_booking_id
  returning * into v_booking;

  if v_booking.late_cancellation then
    perform app.reliability_event(p_user, 'late_cancel', v_booking.id::text, p_now);
  end if;
  perform app.notify_owners(v_booking, 'venue_booking_cancelled', p_now);
  return v_booking;
end $$;

create or replace function app.owner_cancel_booking(p_user uuid, p_booking_id uuid, p_now timestamptz)
returns public.bookings
language plpgsql
set search_path = ''
as $$
declare
  v_before public.bookings;
  v_after public.bookings;
begin
  select * into v_before from app.lock_managed_booking(p_user, p_booking_id);
  if v_before.status <> 'confirmed' or upper(v_before.during) <= p_now then
    raise exception 'not_cancellable';
  end if;

  update public.bookings b
  set status = 'cancelled_by_venue', cancelled_at = p_now
  where b.id = p_booking_id
  returning * into v_after;

  perform app.audit(p_user, 'cancel_booking', 'booking', v_after.id::text, to_jsonb(v_before), to_jsonb(v_after), p_now);

  -- The player hears about it; their reliability is never touched.
  if v_after.source = 'app' and v_after.user_id is not null then
    perform app.notify(v_after.user_id, 'booking_cancelled_by_venue', 'bookings', app.booking_note(v_after), p_now);
  end if;
  return v_after;
end $$;

create or replace function app.owner_mark_booking(p_user uuid, p_booking_id uuid, p_outcome text, p_now timestamptz)
returns public.bookings
language plpgsql
set search_path = ''
as $$
declare
  v_before public.bookings;
  v_after public.bookings;
begin
  select * into v_before from app.lock_managed_booking(p_user, p_booking_id);
  if p_outcome is null or p_outcome not in ('paid', 'no_show') then raise exception 'invalid_argument'; end if;
  if v_before.source = 'block'
     or v_before.status not in ('confirmed', 'completed', 'unverified', 'paid', 'no_show')
     or lower(v_before.during) > p_now then
    raise exception 'not_markable';
  end if;

  update public.bookings b
  set status = p_outcome,
      payment_status = case p_outcome when 'paid' then 'paid' else 'unpaid' end
  where b.id = p_booking_id
  returning * into v_after;

  perform app.audit(p_user, 'mark_booking', 'booking', v_after.id::text, to_jsonb(v_before), to_jsonb(v_after), p_now);

  -- App bookings only: the new outcome replaces the other one's event, so
  -- flipping back and forth never stacks.
  if v_after.source = 'app' and v_after.user_id is not null then
    delete from public.reliability_events e
    where e.user_id = v_after.user_id and e.ref = v_after.id::text
      and e.kind = case p_outcome when 'paid' then 'no_show' else 'booking_paid' end;
    perform app.reliability_event(
      v_after.user_id, case p_outcome when 'paid' then 'booking_paid' else 'no_show' end, v_after.id::text, p_now);
  end if;
  return v_after;
end $$;

-- ---------------------------------------------------------------------------
-- Reminders: two hours before a confirmed app booking. Task 2 adds games.
-- ---------------------------------------------------------------------------

create function app.send_reminders(p_now timestamptz) returns integer
language plpgsql
set search_path = ''
as $$
declare
  v_booking public.bookings;
  v_count integer := 0;
begin
  for v_booking in
    with due as (
      update public.bookings b set reminded_at = p_now
      where b.status = 'confirmed' and b.source = 'app' and b.user_id is not null
        and b.reminded_at is null
        and lower(b.during) > p_now and lower(b.during) <= p_now + interval '2 hours'
      returning b.*
    )
    select * from due
  loop
    perform app.notify(v_booking.user_id, 'booking_reminder', 'bookings', app.booking_note(v_booking), p_now);
    v_count := v_count + 1;
  end loop;
  return v_count;
end $$;

do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron;
    execute $job$
      select cron.schedule(
        'actra-send-reminders',
        '*/10 * * * *',
        'select app.send_reminders(now())')
    $job$;
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- Sports without slots: places to run or train, used by games.
-- ---------------------------------------------------------------------------

insert into public.sports (id, name_uz, name_ru, name_en, icon_key, bookable, default_players, sort_order) values
  ('running', 'Yugurish', 'Бег', 'Running', 'running', false, 4, 90),
  ('gym', 'Sport zali', 'Тренажёрный зал', 'Gym', 'gym', false, 2, 91)
on conflict (id) do nothing;

-- ---------------------------------------------------------------------------
-- What the app calls
-- ---------------------------------------------------------------------------

create function public.my_notifications(p_limit integer default 50, p_before timestamptz default null)
returns setof jsonb
language sql stable security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'id', n.id, 'kind', n.kind, 'category', n.category, 'payload', n.payload,
    'created_at', n.created_at, 'read', n.read_at is not null)
  from public.notifications n
  where n.user_id = (select auth.uid()) and (p_before is null or n.created_at < p_before)
  order by n.created_at desc, n.id desc
  limit greatest(1, least(coalesce(p_limit, 50), 100))
$$;

create function public.unread_notification_count() returns integer
language sql stable security definer
set search_path = ''
as $$
  select count(*)::integer from public.notifications n
  where n.user_id = (select auth.uid()) and n.read_at is null
$$;

-- null marks every notification of mine.
create function public.mark_notifications_read(p_ids uuid[] default null) returns void
language sql security definer
set search_path = ''
as $$
  update public.notifications n set read_at = now()
  where n.user_id = (select auth.uid()) and n.read_at is null and (p_ids is null or n.id = any (p_ids))
$$;

create function public.my_reliability() returns jsonb
language sql stable security definer
set search_path = ''
as $$ select app.reliability((select auth.uid()), now()) $$;

create function public.my_settings() returns jsonb
language sql stable security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'muted_categories', to_jsonb(p.muted_categories),
    'hidden_from_search', p.hidden_from_search,
    'reliability', app.reliability(p.id, now()))
  from public.profiles p where p.id = (select auth.uid())
$$;

-- A null argument leaves that setting as it is.
create function public.set_settings(p_muted text[], p_hidden boolean) returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  v_user uuid := (select auth.uid());
begin
  if v_user is null then raise exception 'not_authenticated'; end if;
  if exists (
    select 1 from unnest(coalesce(p_muted, '{}')) m
    where m is null or m not in ('bookings', 'venue', 'games', 'requests', 'invites')) then
    raise exception 'invalid_argument';
  end if;
  update public.profiles p
  set muted_categories = coalesce((select array_agg(distinct m order by m) from unnest(p_muted) m), p.muted_categories),
      hidden_from_search = coalesce(p_hidden, p.hidden_from_search)
  where p.id = v_user;
end $$;

revoke all on function
  public.my_notifications(integer, timestamptz),
  public.unread_notification_count(),
  public.mark_notifications_read(uuid[]),
  public.my_reliability(),
  public.my_settings(),
  public.set_settings(text[], boolean)
from public, anon, authenticated;

grant execute on function
  public.my_notifications(integer, timestamptz),
  public.unread_notification_count(),
  public.mark_notifications_read(uuid[]),
  public.my_reliability(),
  public.my_settings(),
  public.set_settings(text[], boolean)
to authenticated, service_role;
