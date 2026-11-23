-- Owner settings and dashboard (product spec §11.2-§11.4, §11.6; Milestone 3b).
--
-- Owners set their venue's hours, a court's own hours, a court's slot length,
-- base price and price rules, and read a dashboard. Same conventions as
-- owner.sql: rules in the private `app` schema taking the acting user and the
-- time, the role check before anything else, one audit_log row per change,
-- thin `public` wrappers at the end.
--
-- What is saved is exactly what app.court_slots reads: venue hours are one
-- working_hours row per open weekday (no row = closed); court hours are one
-- row per overridden weekday (closed = true shuts the court that day); price
-- rules are rows in price_rules with sort_order in the given order. Existing
-- bookings are never touched: they keep their times and locked prices.

-- ---------------------------------------------------------------------------
-- Reading what the app sends
-- ---------------------------------------------------------------------------

-- An integer field of a json object: null when missing or null, and
-- invalid_argument when it is not a whole number.
create function app.json_int(p_object jsonb, p_key text) returns integer
language plpgsql immutable
set search_path = ''
as $$
declare
  v_value jsonb := p_object -> p_key;
  v_number numeric;
begin
  if v_value is null or jsonb_typeof(v_value) = 'null' then return null; end if;
  if jsonb_typeof(v_value) <> 'number' then raise exception 'invalid_argument'; end if;
  v_number := (v_value #>> '{}')::numeric;
  if v_number <> trunc(v_number) or v_number < -2147483648 or v_number > 2147483647 then
    raise exception 'invalid_argument';
  end if;
  return v_number::integer;
end $$;

-- [{ "weekday": 1-7, "open_minute": int|null, "close_minute": int|null }],
-- both minutes null = closed. With p_full_week every weekday must appear
-- exactly once; otherwise each at most once.
create function app.parse_hours(p_hours jsonb, p_full_week boolean)
returns table (weekday integer, closed boolean, open_minute integer, close_minute integer)
language plpgsql immutable
set search_path = ''
as $$
declare
  v_item jsonb;
  v_day integer;
  v_open integer;
  v_close integer;
  v_seen integer[] := '{}';
begin
  if p_hours is null or jsonb_typeof(p_hours) <> 'array' then raise exception 'invalid_argument'; end if;
  for v_item in select e from jsonb_array_elements(p_hours) e loop
    if jsonb_typeof(v_item) <> 'object' then raise exception 'invalid_argument'; end if;
    v_day := app.json_int(v_item, 'weekday');
    v_open := app.json_int(v_item, 'open_minute');
    v_close := app.json_int(v_item, 'close_minute');
    if v_day is null then raise exception 'invalid_argument'; end if;
    if v_day not between 1 and 7 or v_day = any (v_seen) then raise exception 'invalid_hours'; end if;
    v_seen := v_seen || v_day;
    if (v_open is null) <> (v_close is null) then raise exception 'invalid_hours'; end if;
    if v_open is not null and (v_open < 0 or v_close > 1440 or v_open >= v_close) then
      raise exception 'invalid_hours';
    end if;
    weekday := v_day;
    closed := v_open is null;
    open_minute := coalesce(v_open, 0);
    close_minute := coalesce(v_close, 0);
    return next;
  end loop;
  if p_full_week and cardinality(v_seen) <> 7 then raise exception 'invalid_hours'; end if;
end $$;

-- What the audit log keeps of hours and pricing.
create function app.hours_json(p_venue_id uuid, p_court_id uuid) returns jsonb
language sql stable
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
      'weekday', h.weekday, 'closed', h.closed, 'open_minute', h.open_minute, 'close_minute', h.close_minute)
    order by h.weekday), '[]'::jsonb)
  from public.working_hours h
  where (p_venue_id is not null and h.venue_id = p_venue_id)
     or (p_court_id is not null and h.court_id = p_court_id)
$$;

create function app.pricing_json(p_court_id uuid) returns jsonb
language sql stable
set search_path = ''
as $$
  select jsonb_build_object(
    'slot_minutes', c.slot_minutes,
    'base_price', c.base_price,
    'rules', coalesce((
      select jsonb_agg(jsonb_build_object(
          'weekdays', to_jsonb(r.weekdays), 'from_minute', r.from_minute, 'to_minute', r.to_minute, 'price', r.price)
        order by r.sort_order, r.id)
      from public.price_rules r where r.court_id = c.id), '[]'::jsonb))
  from public.courts c
  where c.id = p_court_id
$$;

-- The role check for venue-level functions; see app.require_court_manager.
create function app.require_venue_manager(p_user uuid, p_venue_id uuid) returns void
language plpgsql stable
set search_path = ''
as $$
begin
  if not app.can_manage_venue(p_user, p_venue_id) then raise exception 'not_allowed'; end if;
  if not exists (select 1 from public.venues v where v.id = p_venue_id) then raise exception 'not_found'; end if;
end $$;

-- ---------------------------------------------------------------------------
-- Hours
-- ---------------------------------------------------------------------------

create function app.owner_set_venue_hours(p_user uuid, p_venue_id uuid, p_hours jsonb, p_now timestamptz)
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_before jsonb;
begin
  perform app.require_venue_manager(p_user, p_venue_id);
  perform count(*) from app.parse_hours(p_hours, true);

  perform 1 from public.venues v where v.id = p_venue_id for update;
  v_before := app.hours_json(p_venue_id, null);

  delete from public.working_hours h where h.venue_id = p_venue_id;
  insert into public.working_hours (venue_id, weekday, closed, open_minute, close_minute)
  select p_venue_id, h.weekday, false, h.open_minute, h.close_minute
  from app.parse_hours(p_hours, true) h
  where not h.closed;

  perform app.audit(p_user, 'set_venue_hours', 'venue', p_venue_id::text, v_before, app.hours_json(p_venue_id, null), p_now);
end $$;

-- Only the weekdays that differ from the venue; [] = follow the venue.
create function app.owner_set_court_hours(p_user uuid, p_court_id uuid, p_hours jsonb, p_now timestamptz)
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_before jsonb;
begin
  perform app.require_court_manager(p_user, p_court_id);
  perform count(*) from app.parse_hours(p_hours, false);

  perform 1 from public.courts c where c.id = p_court_id for update;
  v_before := app.hours_json(null, p_court_id);

  delete from public.working_hours h where h.court_id = p_court_id;
  insert into public.working_hours (court_id, weekday, closed, open_minute, close_minute)
  select p_court_id, h.weekday, h.closed, h.open_minute, h.close_minute
  from app.parse_hours(p_hours, false) h;

  perform app.audit(p_user, 'set_court_hours', 'court', p_court_id::text, v_before, app.hours_json(null, p_court_id), p_now);
end $$;

-- ---------------------------------------------------------------------------
-- Slot length and prices (product spec §11.3, §11.4)
-- ---------------------------------------------------------------------------

-- Replaces the court's rules with p_rules, in order (the first match wins in
-- app.court_slots). Two rules may not share a weekday and an overlapping
-- time range.
create function app.owner_set_court_pricing(
  p_user uuid, p_court_id uuid, p_slot_minutes integer, p_base_price integer, p_rules jsonb, p_now timestamptz)
returns void
language plpgsql
set search_path = ''
as $$
declare
  c_max_rules constant integer := 50;
  -- Keeps a summed booking total far from the integer limit.
  c_max_price constant integer := 50000000;
  v_item jsonb;
  v_weekdays jsonb;
  v_element jsonb;
  v_number numeric;
  v_days integer[];
  v_from integer;
  v_to integer;
  v_price integer;
  v_rules jsonb := '[]'::jsonb;
  v_before jsonb;
begin
  perform app.require_court_manager(p_user, p_court_id);
  if p_slot_minutes is null or p_slot_minutes not in (60, 90, 120) then raise exception 'invalid_argument'; end if;
  if p_base_price is null or p_base_price < 0 or p_base_price > c_max_price then raise exception 'invalid_argument'; end if;
  if p_rules is null or jsonb_typeof(p_rules) <> 'array' or jsonb_array_length(p_rules) > c_max_rules then
    raise exception 'invalid_argument';
  end if;

  for v_item in select e from jsonb_array_elements(p_rules) e loop
    if jsonb_typeof(v_item) <> 'object' then raise exception 'invalid_argument'; end if;

    v_weekdays := v_item -> 'weekdays';
    if v_weekdays is null or jsonb_typeof(v_weekdays) <> 'array' or jsonb_array_length(v_weekdays) = 0
       or jsonb_array_length(v_weekdays) > 7 then
      raise exception 'invalid_argument';
    end if;
    v_days := '{}';
    for v_element in select e from jsonb_array_elements(v_weekdays) e loop
      if jsonb_typeof(v_element) <> 'number' then raise exception 'invalid_argument'; end if;
      v_number := (v_element #>> '{}')::numeric;
      if v_number <> trunc(v_number) or v_number < 1 or v_number > 7 then raise exception 'invalid_argument'; end if;
      if not (v_number::integer = any (v_days)) then v_days := v_days || v_number::integer; end if;
    end loop;
    select array_agg(d order by d) into v_days from unnest(v_days) d;

    v_from := app.json_int(v_item, 'from_minute');
    v_to := app.json_int(v_item, 'to_minute');
    v_price := app.json_int(v_item, 'price');
    if v_from is null or v_to is null or v_price is null or v_price < 0 or v_price > c_max_price then
      raise exception 'invalid_argument';
    end if;
    if v_from < 0 or v_to > 1440 or v_from >= v_to then raise exception 'invalid_hours'; end if;

    v_rules := v_rules || jsonb_build_array(jsonb_build_object(
      'weekdays', to_jsonb(v_days), 'from_minute', v_from, 'to_minute', v_to, 'price', v_price));
  end loop;

  if exists (
    select 1
    from jsonb_array_elements(v_rules) with ordinality a (r, i)
    join jsonb_array_elements(v_rules) with ordinality b (r, i) on a.i < b.i
    where (select array_agg(x::integer) from jsonb_array_elements_text(a.r -> 'weekdays') x)
          && (select array_agg(x::integer) from jsonb_array_elements_text(b.r -> 'weekdays') x)
      and (a.r ->> 'from_minute')::integer < (b.r ->> 'to_minute')::integer
      and (b.r ->> 'from_minute')::integer < (a.r ->> 'to_minute')::integer
  ) then
    raise exception 'rules_overlap';
  end if;

  perform 1 from public.courts c where c.id = p_court_id for update;
  v_before := app.pricing_json(p_court_id);

  update public.courts c set slot_minutes = p_slot_minutes, base_price = p_base_price where c.id = p_court_id;
  delete from public.price_rules r where r.court_id = p_court_id;
  insert into public.price_rules (court_id, weekdays, from_minute, to_minute, price, sort_order)
  select p_court_id,
         array(select x::integer from jsonb_array_elements_text(t.r -> 'weekdays') x),
         (t.r ->> 'from_minute')::integer, (t.r ->> 'to_minute')::integer, (t.r ->> 'price')::integer,
         (t.i - 1)::integer
  from jsonb_array_elements(v_rules) with ordinality t (r, i);

  perform app.audit(p_user, 'set_court_pricing', 'court', p_court_id::text, v_before, app.pricing_json(p_court_id), p_now);
end $$;

-- ---------------------------------------------------------------------------
-- Dashboard (product spec §11.6)
-- ---------------------------------------------------------------------------

-- p_from..p_to inclusive, at most 92 days, every court of the venue or one.
-- A booking belongs to the day and hour of its start in venue wall-clock
-- time. Counted: confirmed, completed, paid, no_show, unverified; never
-- blocks or cancelled rows. slots_available is what the courts offer in the
-- range under today's hours, minus blocked slots. Reading it is not logged.
create function app.owner_dashboard(p_user uuid, p_venue_id uuid, p_court_id uuid, p_from date, p_to date)
returns jsonb
language plpgsql stable
set search_path = ''
as $$
declare
  c_max_days constant integer := 92;
  c_max_years constant interval := interval '10 years';
  v_currency text;
  v_offset integer;
  v_days integer;
  v_result jsonb;
begin
  perform app.require_venue_manager(p_user, p_venue_id);
  if p_court_id is not null
     and not exists (select 1 from public.courts c where c.id = p_court_id and c.venue_id = p_venue_id) then
    raise exception 'not_found';
  end if;
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from + 1 > c_max_days
     or p_from < current_date - c_max_years or p_to > current_date + c_max_years then
    raise exception 'invalid_argument';
  end if;
  v_days := p_to - p_from + 1;

  select ci.currency, ci.utc_offset_minutes into v_currency, v_offset
  from public.venues v join public.cities ci on ci.id = v.city_id
  where v.id = p_venue_id;

  with scoped as (
    select b.source, b.status, b.total_price, b.slot_count,
           app.to_local(lower(b.during), b.utc_offset_minutes) as starts
    from public.bookings b
    where b.venue_id = p_venue_id
      -- Never mix currencies if the venue has moved to another city.
      and b.currency = v_currency
      and (p_court_id is null or b.court_id = p_court_id)
      and b.status in ('confirmed', 'completed', 'paid', 'no_show', 'unverified')
      -- A day of slack each side for offsets; the exact day test follows.
      and b.during && tstzrange(app.to_instant((p_from - 1)::timestamp, v_offset), app.to_instant((p_to + 2)::timestamp, v_offset))
      and app.to_local(lower(b.during), b.utc_offset_minutes)::date between p_from and p_to
  ),
  counted as (
    select * from scoped where source <> 'block'
  ),
  heat as (
    select extract(isodow from starts)::integer as weekday, extract(hour from starts)::integer as hour, count(*)::integer as n
    from counted
    group by 1, 2
  ),
  offered as (
    select count(*)::integer as n
    from public.courts c
    cross join generate_series(0, v_days - 1) d (k)
    cross join lateral app.court_slots(c.id, p_from + d.k) s
    where c.venue_id = p_venue_id and (p_court_id is null or c.id = p_court_id)
  )
  select jsonb_build_object(
    'currency', v_currency,
    'days', v_days,
    'bookings_app', (select count(*) from counted where source = 'app'),
    'bookings_walk_in', (select count(*) from counted where source = 'walk_in'),
    'revenue_paid', (select coalesce(sum(total_price), 0) from counted where status = 'paid'),
    'revenue_unconfirmed', (select coalesce(sum(total_price), 0) from counted where status = 'unverified'),
    'no_shows', (select count(*) from counted where status = 'no_show'),
    'slots_available', greatest(
      (select n from offered) - (select coalesce(sum(slot_count), 0) from scoped where source = 'block'), 0),
    'slots_booked', (select coalesce(sum(slot_count), 0) from counted),
    'heatmap', coalesce((
      select jsonb_agg(jsonb_build_object('weekday', h.weekday, 'hour', h.hour, 'count', h.n) order by h.weekday, h.hour)
      from heat h), '[]'::jsonb))
  into v_result;
  return v_result;
end $$;

-- Lets the dashboard read one venue's bookings in a time range instead of
-- the venue's whole history (btree_gist, as for bookings_no_overlap).
create index bookings_venue_during_idx on public.bookings using gist (venue_id, during);

-- ---------------------------------------------------------------------------
-- What the app calls. Each runs as the signed-in user at the real time.
-- ---------------------------------------------------------------------------

create function public.owner_set_venue_hours(p_venue_id uuid, p_hours jsonb) returns void
language sql security definer
set search_path = ''
as $$ select app.owner_set_venue_hours((select auth.uid()), p_venue_id, p_hours, now()) $$;

create function public.owner_set_court_hours(p_court_id uuid, p_hours jsonb) returns void
language sql security definer
set search_path = ''
as $$ select app.owner_set_court_hours((select auth.uid()), p_court_id, p_hours, now()) $$;

create function public.owner_set_court_pricing(p_court_id uuid, p_slot_minutes integer, p_base_price integer, p_rules jsonb)
returns void
language sql security definer
set search_path = ''
as $$ select app.owner_set_court_pricing((select auth.uid()), p_court_id, p_slot_minutes, p_base_price, p_rules, now()) $$;

create function public.owner_dashboard(p_venue_id uuid, p_court_id uuid, p_from date, p_to date) returns jsonb
language sql stable security definer
set search_path = ''
as $$ select app.owner_dashboard((select auth.uid()), p_venue_id, p_court_id, p_from, p_to) $$;

revoke all on function
  public.owner_set_venue_hours(uuid, jsonb),
  public.owner_set_court_hours(uuid, jsonb),
  public.owner_set_court_pricing(uuid, integer, integer, jsonb),
  public.owner_dashboard(uuid, uuid, date, date)
from public, anon, authenticated;

grant execute on function
  public.owner_set_venue_hours(uuid, jsonb),
  public.owner_set_court_hours(uuid, jsonb),
  public.owner_set_court_pricing(uuid, integer, integer, jsonb),
  public.owner_dashboard(uuid, uuid, date, date)
to authenticated, service_role;
