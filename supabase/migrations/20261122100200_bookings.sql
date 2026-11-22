-- Bookings and the rules around them (product spec §7.6, roadmap §3.1).
--
-- The rules are the ones in app/lib/domain/booking_engine.dart. They live in
-- the private `app` schema, where every function takes the acting player and
-- the current time as arguments so tests can fix the clock. The `public`
-- wrappers at the end pass auth.uid() and now(); they are the only way the
-- phone app can create or change a booking.

create schema if not exists app;
revoke all on schema app from public;

create table public.bookings (
  id uuid primary key default gen_random_uuid(),
  -- null only for owner walk-ins (Milestone 3).
  user_id uuid references public.profiles (id),
  venue_id uuid not null references public.venues (id),
  court_id uuid not null references public.courts (id),
  -- The real instants the booking covers, start inclusive, end exclusive.
  during tstzrange not null,
  -- The city's offset when the booking was made, so its wall-clock times
  -- never move if a city's offset changes later.
  utc_offset_minutes integer not null,
  slot_count integer not null check (slot_count > 0),
  -- Locked when the slots are held; later price changes do not touch it.
  total_price integer not null check (total_price >= 0),
  currency text not null check (currency in ('UZS', 'KZT')),
  status text not null check (status in (
    'held', 'confirmed', 'cancelled_by_player', 'cancelled_by_venue',
    'completed', 'paid', 'no_show', 'unverified', 'released')),
  source text not null default 'app' check (source in ('app', 'walk_in')),
  payment_method text not null default 'pay_at_venue' check (payment_method in ('pay_at_venue')),
  payment_status text not null default 'unpaid' check (payment_status in ('unpaid', 'paid')),
  -- Set while held. Kept on a hold released by expiry, cleared on one the
  -- player gave back, so "expired" and "released" can be told apart.
  hold_expires_at timestamptz,
  late_cancellation boolean not null default false,
  players integer check (players is null or players > 0),
  note text,
  created_at timestamptz not null default now(),
  confirmed_at timestamptz,
  cancelled_at timestamptz,
  constraint bookings_app_has_player check (source = 'walk_in' or user_id is not null),
  constraint bookings_range_shape check (not isempty(during) and lower_inc(during) and not upper_inc(during)),
  -- The rule that must never break: no two active rows overlap on a court.
  constraint bookings_no_overlap exclude using gist (court_id with =, during with &&)
    where (status in ('held', 'confirmed', 'completed', 'paid', 'no_show', 'unverified'))
);
create index bookings_user_idx on public.bookings (user_id, status);
create index bookings_venue_idx on public.bookings (venue_id);

alter table public.bookings enable row level security;
revoke all on table public.bookings from anon, authenticated;
grant all on table public.bookings to service_role;
-- Read-only for players; every write goes through the functions below.
grant select on table public.bookings to authenticated;
create policy "players see their own bookings" on public.bookings for select to authenticated
  using (user_id = (select auth.uid()));
create policy "owners see bookings at their venues" on public.bookings for select to authenticated
  using (exists (
    select 1 from public.venue_owners o
    where o.venue_id = bookings.venue_id and o.user_id = (select auth.uid())));

-- ---------------------------------------------------------------------------
-- Time: instants in the database, venue wall-clock time at the edges.
-- ---------------------------------------------------------------------------

create function app.to_local(p_instant timestamptz, p_offset_minutes integer) returns timestamp
language sql immutable
as $$ select (p_instant at time zone 'UTC') + make_interval(mins => p_offset_minutes) $$;

create function app.to_instant(p_local timestamp, p_offset_minutes integer) returns timestamptz
language sql immutable
as $$ select (p_local - make_interval(mins => p_offset_minutes)) at time zone 'UTC' $$;

-- ---------------------------------------------------------------------------
-- Slots and prices (product spec §11.3, §11.4)
-- ---------------------------------------------------------------------------

-- Slots of one court on one day: back to back from opening time, each
-- slot_minutes long; a final slot that would end after closing is not
-- offered. Each carries its price: the first matching rule, else base price.
create function app.court_slots(p_court_id uuid, p_date date)
returns table (starts_local timestamp, ends_local timestamp, price integer)
language plpgsql stable
set search_path = ''
as $$
declare
  v_court public.courts;
  v_hours public.working_hours;
  v_weekday integer := extract(isodow from p_date)::integer;
  v_minute integer;
begin
  select c.* into v_court
  from public.courts c join public.venues v on v.id = c.venue_id
  where c.id = p_court_id and c.active and v.active;
  if not found then return; end if;

  -- The court's own hours for that weekday when it has them, else the venue's.
  select h.* into v_hours from public.working_hours h where h.court_id = p_court_id and h.weekday = v_weekday;
  if not found then
    select h.* into v_hours from public.working_hours h where h.venue_id = v_court.venue_id and h.weekday = v_weekday;
    if not found then return; end if;
  end if;
  if v_hours.closed then return; end if;

  v_minute := v_hours.open_minute;
  while v_minute + v_court.slot_minutes <= v_hours.close_minute loop
    starts_local := p_date::timestamp + make_interval(mins => v_minute);
    ends_local := starts_local + make_interval(mins => v_court.slot_minutes);
    price := coalesce(
      (select r.price from public.price_rules r
       where r.court_id = p_court_id
         and v_weekday = any (r.weekdays)
         and v_minute >= r.from_minute and v_minute < r.to_minute
       order by r.sort_order, r.id
       limit 1),
      v_court.base_price);
    return next;
    v_minute := v_minute + v_court.slot_minutes;
  end loop;
end $$;

-- free | taken | past | mine for every slot of the day, as one player sees it.
-- A hold counts only until it expires; "mine" is the player's own live hold.
create function app.court_availability(p_user uuid, p_court_id uuid, p_date date, p_now timestamptz)
returns table (starts_local timestamp, ends_local timestamp, price integer, state text)
language plpgsql stable
set search_path = ''
as $$
declare
  v_offset integer;
begin
  select ci.utc_offset_minutes into v_offset
  from public.courts c
  join public.venues v on v.id = c.venue_id
  join public.cities ci on ci.id = v.city_id
  where c.id = p_court_id;
  if not found then return; end if;

  return query
  select s.starts_local, s.ends_local, s.price,
    case
      when app.to_instant(s.starts_local, v_offset) <= p_now then 'past'
      when blocker.id is null then 'free'
      when blocker.status = 'held' and blocker.user_id = p_user then 'mine'
      else 'taken'
    end
  from app.court_slots(p_court_id, p_date) s
  left join lateral (
    select b.id, b.status, b.user_id
    from public.bookings b
    where b.court_id = p_court_id
      and b.during && tstzrange(app.to_instant(s.starts_local, v_offset), app.to_instant(s.ends_local, v_offset))
      and (b.status in ('confirmed', 'completed', 'paid', 'no_show', 'unverified')
           or (b.status = 'held' and b.hold_expires_at > p_now))
    limit 1
  ) blocker on true
  order by s.starts_local;
end $$;

-- ---------------------------------------------------------------------------
-- Hold, confirm, release, cancel
-- ---------------------------------------------------------------------------

-- Holds back-to-back slots for five minutes. A player has one hold at a
-- time: a new hold replaces their previous one.
create function app.hold_slots(p_user uuid, p_court_id uuid, p_starts timestamp[], p_now timestamptz)
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

  if (select count(*) from public.bookings b
      where b.user_id = p_user and b.status = 'confirmed' and lower(b.during) > p_now) >= c_max_upcoming then
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

create function app.confirm_booking(p_user uuid, p_booking_id uuid, p_players integer, p_note text, p_now timestamptz)
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
  return v_booking;
end $$;

-- Gives a held slot back, e.g. when the player leaves the summary screen.
create function app.release_hold(p_user uuid, p_booking_id uuid) returns void
language sql
set search_path = ''
as $$
  update public.bookings b set status = 'released', hold_expires_at = null
  where b.id = p_booking_id and b.user_id = p_user and b.status = 'held';
$$;

-- Player cancellation: free until six hours before the start, flagged late
-- after that, impossible once the slot has started.
create function app.cancel_booking(p_user uuid, p_booking_id uuid, p_now timestamptz)
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
  if v_booking.status <> 'confirmed' or lower(v_booking.during) <= p_now then
    raise exception 'not_cancellable';
  end if;

  update public.bookings b
  set status = 'cancelled_by_player',
      late_cancellation = (lower(b.during) - p_now) < c_free_window,
      cancelled_at = p_now
  where b.id = p_booking_id
  returning * into v_booking;
  return v_booking;
end $$;

-- Sweeps holds nobody confirmed. Run every minute by the scheduled job;
-- hold_slots also does it for the court it is about to write to.
create function app.release_expired_holds(p_now timestamptz) returns integer
language plpgsql
set search_path = ''
as $$
declare
  v_count integer;
begin
  update public.bookings b set status = 'released'
  where b.status = 'held' and b.hold_expires_at <= p_now;
  get diagnostics v_count = row_count;
  return v_count;
end $$;

-- A booking as the app receives it: wall-clock times, no ranges.
create function app.booking_json(b public.bookings) returns jsonb
language sql stable
set search_path = ''
as $$
  select jsonb_build_object(
    'id', b.id,
    'user_id', b.user_id,
    'venue_id', b.venue_id,
    'court_id', b.court_id,
    'starts_local', app.to_local(lower(b.during), b.utc_offset_minutes),
    'ends_local', app.to_local(upper(b.during), b.utc_offset_minutes),
    'slot_count', b.slot_count,
    'total_price', b.total_price,
    'currency', b.currency,
    'status', b.status,
    'payment_method', b.payment_method,
    'payment_status', b.payment_status,
    'hold_expires_local',
      case when b.status = 'held' then app.to_local(b.hold_expires_at, b.utc_offset_minutes) end,
    'late_cancellation', b.late_cancellation,
    'players', b.players,
    'note', b.note)
$$;

-- ---------------------------------------------------------------------------
-- What the app calls. Each runs as the signed-in player at the real time.
-- ---------------------------------------------------------------------------

create function public.court_availability(p_court_id uuid, p_date date)
returns table (starts_local timestamp, ends_local timestamp, price integer, state text)
language sql stable security definer
set search_path = ''
as $$ select * from app.court_availability((select auth.uid()), p_court_id, p_date, now()) $$;

create function public.hold_slots(p_court_id uuid, p_starts timestamp[]) returns jsonb
language sql security definer
set search_path = ''
as $$ select app.booking_json(app.hold_slots((select auth.uid()), p_court_id, p_starts, now())) $$;

create function public.confirm_booking(p_booking_id uuid, p_players integer default null, p_note text default null)
returns jsonb
language sql security definer
set search_path = ''
as $$ select app.booking_json(app.confirm_booking((select auth.uid()), p_booking_id, p_players, p_note, now())) $$;

create function public.release_hold(p_booking_id uuid) returns void
language sql security definer
set search_path = ''
as $$ select app.release_hold((select auth.uid()), p_booking_id) $$;

create function public.cancel_booking(p_booking_id uuid) returns jsonb
language sql security definer
set search_path = ''
as $$ select app.booking_json(app.cancel_booking((select auth.uid()), p_booking_id, now())) $$;

-- A player's bookings, newest start first. Holds are not bookings yet.
create function public.my_bookings() returns setof jsonb
language sql stable security definer
set search_path = ''
as $$
  select app.booking_json(b)
  from public.bookings b
  where b.user_id = (select auth.uid()) and b.status not in ('held', 'released')
  order by lower(b.during) desc
$$;

revoke all on function
  public.court_availability(uuid, date),
  public.hold_slots(uuid, timestamp[]),
  public.confirm_booking(uuid, integer, text),
  public.release_hold(uuid),
  public.cancel_booking(uuid),
  public.my_bookings()
from public, anon, authenticated;

grant execute on function public.court_availability(uuid, date) to anon, authenticated, service_role;
grant execute on function
  public.hold_slots(uuid, timestamp[]),
  public.confirm_booking(uuid, integer, text),
  public.release_hold(uuid),
  public.cancel_booking(uuid),
  public.my_bookings()
to authenticated, service_role;
