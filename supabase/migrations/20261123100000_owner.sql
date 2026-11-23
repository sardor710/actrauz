-- Venue owners run their calendar (product spec §4, §5, §11.5, §12.7, §14;
-- Milestone 3a).
--
-- Walk-ins and blocks are rows in public.bookings, so bookings_no_overlap
-- keeps guarding every slot whoever takes it. As in bookings.sql, the rules
-- live in the private `app` schema: every function takes the acting user
-- and the current time, and checks first that the user may manage the venue
-- (an owner in venue_owners, or an admin in app_admins). The `public`
-- wrappers at the end pass auth.uid() and now(). Every owner write adds one
-- row to audit_log.

-- ---------------------------------------------------------------------------
-- Bookings: who the walk-in is, how they pay, why a slot is blocked.
-- ---------------------------------------------------------------------------

alter table public.bookings
  add column guest_name text,
  add column guest_phone text,
  -- How a walk-in says they will pay. payment_method stays 'pay_at_venue'.
  add column walk_in_payment text check (walk_in_payment in ('cash', 'card', 'transfer')),
  add column block_reason text;

alter table public.bookings drop constraint bookings_source_check;
alter table public.bookings drop constraint bookings_app_has_player;
alter table public.bookings
  add constraint bookings_source_check check (source in ('app', 'walk_in', 'block')),
  -- A walk-in may be linked to the account whose phone it gave; a block never is.
  add constraint bookings_app_has_player check (source <> 'app' or user_id is not null),
  add constraint bookings_block_has_no_player check (source <> 'block' or user_id is null),
  add constraint bookings_walk_in_named check (source <> 'walk_in' or btrim(coalesce(guest_name, '')) <> ''),
  add constraint bookings_walk_in_payment_given check ((source = 'walk_in') = (walk_in_payment is not null)),
  add constraint bookings_block_reason_on_blocks check (block_reason is null or source = 'block'),
  -- The limits the owner functions enforce (they raise invalid_argument first).
  add constraint bookings_guest_name_length check (char_length(guest_name) <= 80),
  add constraint bookings_guest_phone_shape check (guest_phone ~ '^\+?[0-9]{7,15}$'),
  add constraint bookings_block_reason_length check (char_length(block_reason) <= 200),
  add constraint bookings_walk_in_players_limit check (source <> 'walk_in' or players is null or players <= 100),
  add constraint bookings_owner_slot_limit check (source = 'app' or slot_count <= 24);

-- For the scheduled job below.
create index bookings_advance_idx on public.bookings (status, upper(during))
  where status in ('confirmed', 'completed');

-- ---------------------------------------------------------------------------
-- Admins and the audit log: no client access at all.
-- ---------------------------------------------------------------------------

-- Admins act on every venue (product spec §4). Rows are added by hand with
-- the service role; see supabase/README.md.
create table public.app_admins (
  user_id uuid primary key references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now()
);

-- Who changed what, when, before and after (product spec §12.7, §14 rule 5).
-- No foreign keys: the record outlives the rows it describes.
create table public.audit_log (
  id bigint generated always as identity primary key,
  actor_id uuid,
  action text not null,
  entity text not null,
  entity_id text,
  before jsonb,
  after jsonb,
  created_at timestamptz not null default now()
);
create index audit_log_entity_idx on public.audit_log (entity, entity_id);

alter table public.app_admins enable row level security;
alter table public.audit_log enable row level security;
revoke all on table public.app_admins, public.audit_log from anon, authenticated;
grant all on table public.app_admins, public.audit_log to service_role;
revoke all on sequence public.audit_log_id_seq from anon, authenticated;

-- ---------------------------------------------------------------------------
-- Roles
-- ---------------------------------------------------------------------------

create function app.is_admin(p_user uuid) returns boolean
language sql stable
set search_path = ''
as $$ select exists (select 1 from public.app_admins a where a.user_id = p_user) $$;

-- Never null: false for a missing user or venue (an admin passes either way).
create function app.can_manage_venue(p_user uuid, p_venue_id uuid) returns boolean
language sql stable
set search_path = ''
as $$
  select p_user is not null and (
    app.is_admin(p_user)
    or exists (select 1 from public.venue_owners o where o.venue_id = p_venue_id and o.user_id = p_user))
$$;

-- Active venues the user manages: all of them for an admin.
create function app.my_venue_ids(p_user uuid) returns uuid[]
language sql stable
set search_path = ''
as $$
  select coalesce(array_agg(v.id order by v.created_at, v.id), '{}')
  from public.venues v
  where v.active and app.can_manage_venue(p_user, v.id)
$$;

-- The role check every court-level owner function starts with. A court the
-- user cannot manage and a court that does not exist look the same to a
-- non-admin, so ids cannot be probed. Returns the court's venue.
create function app.require_court_manager(p_user uuid, p_court_id uuid) returns uuid
language plpgsql stable
set search_path = ''
as $$
declare
  v_venue_id uuid;
begin
  select c.venue_id into v_venue_id from public.courts c where c.id = p_court_id;
  if not app.can_manage_venue(p_user, v_venue_id) then raise exception 'not_allowed'; end if;
  if v_venue_id is null then raise exception 'not_found'; end if;
  return v_venue_id;
end $$;

-- The same for a booking, which it then locks for the change that follows.
create function app.lock_managed_booking(p_user uuid, p_booking_id uuid) returns public.bookings
language plpgsql
set search_path = ''
as $$
declare
  v_venue_id uuid;
  v_booking public.bookings;
begin
  select b.venue_id into v_venue_id from public.bookings b where b.id = p_booking_id;
  if not app.can_manage_venue(p_user, v_venue_id) then raise exception 'not_allowed'; end if;
  select b.* into v_booking from public.bookings b where b.id = p_booking_id for update;
  if not found then raise exception 'not_found'; end if;
  return v_booking;
end $$;

create function app.audit(
  p_actor uuid, p_action text, p_entity text, p_entity_id text, p_before jsonb, p_after jsonb, p_at timestamptz)
returns void
language sql
set search_path = ''
as $$
  insert into public.audit_log (actor_id, action, entity, entity_id, before, after, created_at)
  values (p_actor, p_action, p_entity, p_entity_id, p_before, p_after, p_at)
$$;

-- ---------------------------------------------------------------------------
-- Owner bookings
-- ---------------------------------------------------------------------------

-- "+998 (90) 111-11-11" -> "+998901111111": spaces, dashes and brackets
-- dropped, so the number can be matched against profile_contacts. What is
-- left must then look like a phone number (checked by the caller).
create function app.normalize_phone(p_phone text) returns text
language sql immutable
set search_path = ''
as $$ select nullif(regexp_replace(coalesce(p_phone, ''), '[[:space:]()-]', '', 'g'), '') $$;

-- The slot checks of app.hold_slots, for owners: real slots of the court,
-- back to back, up to 14 days ahead; allowed while the first selected slot
-- has not ended (it may be under way). At most 24 slots, no cap on upcoming
-- bookings. Prices are summed as of now.
create function app.owner_selection(
  p_court_id uuid, p_starts timestamp[], p_now timestamptz,
  out o_venue_id uuid, out o_offset integer, out o_currency text,
  out o_first timestamp, out o_last_end timestamp, out o_count integer, out o_total integer)
language plpgsql stable
set search_path = ''
as $$
declare
  c_max_days_ahead constant integer := 14;
  v_starts timestamp[];
  v_day_starts timestamp[];
  v_day_ends timestamp[];
  v_day_prices integer[];
  v_index integer;
  v_previous_end timestamp;
  v_first_end timestamp;
begin
  o_count := coalesce(cardinality(p_starts), 0);
  if o_count = 0 then raise exception 'empty_selection'; end if;
  if o_count > 24 then raise exception 'invalid_argument'; end if;

  select c.venue_id, ci.utc_offset_minutes, ci.currency into o_venue_id, o_offset, o_currency
  from public.courts c
  join public.venues v on v.id = c.venue_id
  join public.cities ci on ci.id = v.city_id
  where c.id = p_court_id;
  if not found then raise exception 'not_found'; end if;

  select array_agg(s order by s) into v_starts from unnest(p_starts) s;
  o_first := v_starts[1];

  select array_agg(s.starts_local order by s.starts_local),
         array_agg(s.ends_local order by s.starts_local),
         array_agg(s.price order by s.starts_local)
    into v_day_starts, v_day_ends, v_day_prices
  from app.court_slots(p_court_id, o_first::date) s;

  for i in 1..o_count loop
    if v_starts[i] is null or array_position(v_day_starts, v_starts[i]) is null then
      raise exception 'not_found';
    end if;
  end loop;

  o_total := 0;
  for i in 1..o_count loop
    v_index := array_position(v_day_starts, v_starts[i]);
    if i > 1 and v_starts[i] <> v_previous_end then raise exception 'not_contiguous'; end if;
    v_previous_end := v_day_ends[v_index];
    if i = 1 then v_first_end := v_previous_end; end if;
    o_total := o_total + v_day_prices[v_index];
  end loop;
  o_last_end := v_previous_end;

  if app.to_instant(v_first_end, o_offset) <= p_now then raise exception 'in_past'; end if;
  if o_first::date - app.to_local(p_now, o_offset)::date > c_max_days_ahead then
    raise exception 'too_far_ahead';
  end if;
end $$;

-- Owner writes and player holds on one court queue on the same lock that
-- app.hold_slots takes, so the loser gets a clean slot_taken. Holds that ran
-- out are given back first. The exclusion constraint is still the guard.
create function app.lock_court_for_write(p_court_id uuid, p_now timestamptz) returns void
language plpgsql
set search_path = ''
as $$
begin
  perform pg_advisory_xact_lock(hashtextextended(p_court_id::text, 0));
  update public.bookings b set status = 'released'
  where b.court_id = p_court_id and b.status = 'held' and b.hold_expires_at <= p_now;
end $$;

-- A walk-in or phone booking (product spec §11.5): confirmed at once, priced
-- from the court's rules. Linked to the account whose phone it gives.
create function app.owner_create_walk_in(
  p_user uuid, p_court_id uuid, p_starts timestamp[], p_name text, p_phone text, p_players integer,
  p_payment_method text, p_now timestamptz)
returns public.bookings
language plpgsql
set search_path = ''
as $$
declare
  v_name text := nullif(btrim(p_name), '');
  v_phone text := app.normalize_phone(p_phone);
  v_payment text := lower(btrim(p_payment_method));
  v_sel record;
  v_linked uuid;
  v_booking public.bookings;
begin
  perform app.require_court_manager(p_user, p_court_id);
  if v_name is null then raise exception 'name_required'; end if;
  if v_payment is null or v_payment not in ('cash', 'card', 'transfer') then raise exception 'invalid_argument'; end if;
  if char_length(v_name) > 80 then raise exception 'invalid_argument'; end if;
  if v_phone is not null and v_phone !~ '^\+?[0-9]{7,15}$' then raise exception 'invalid_argument'; end if;
  if p_players is not null and (p_players <= 0 or p_players > 100) then raise exception 'invalid_argument'; end if;

  select * into v_sel from app.owner_selection(p_court_id, p_starts, p_now);

  if v_phone is not null then
    select c.user_id into v_linked from public.profile_contacts c where c.phone = v_phone;
  end if;

  perform app.lock_court_for_write(p_court_id, p_now);
  begin
    insert into public.bookings (
      user_id, venue_id, court_id, during, utc_offset_minutes, slot_count, total_price, currency,
      status, source, guest_name, guest_phone, walk_in_payment, players, created_at, confirmed_at)
    values (
      v_linked, v_sel.o_venue_id, p_court_id,
      tstzrange(app.to_instant(v_sel.o_first, v_sel.o_offset), app.to_instant(v_sel.o_last_end, v_sel.o_offset), '[)'),
      v_sel.o_offset, v_sel.o_count, v_sel.o_total, v_sel.o_currency,
      'confirmed', 'walk_in', v_name, v_phone, v_payment, p_players, p_now, p_now)
    returning * into v_booking;
  exception when exclusion_violation or deadlock_detected then
    raise exception 'slot_taken';
  end;

  perform app.audit(p_user, 'create_walk_in', 'booking', v_booking.id::text, null, to_jsonb(v_booking), p_now);
  return v_booking;
end $$;

-- Closes slots to everyone (repairs, private events). Costs nothing.
create function app.owner_block_slots(p_user uuid, p_court_id uuid, p_starts timestamp[], p_reason text, p_now timestamptz)
returns public.bookings
language plpgsql
set search_path = ''
as $$
declare
  v_sel record;
  v_booking public.bookings;
begin
  perform app.require_court_manager(p_user, p_court_id);
  if char_length(btrim(p_reason)) > 200 then raise exception 'invalid_argument'; end if;

  select * into v_sel from app.owner_selection(p_court_id, p_starts, p_now);

  perform app.lock_court_for_write(p_court_id, p_now);
  begin
    insert into public.bookings (
      user_id, venue_id, court_id, during, utc_offset_minutes, slot_count, total_price, currency,
      status, source, block_reason, created_at, confirmed_at)
    values (
      null, v_sel.o_venue_id, p_court_id,
      tstzrange(app.to_instant(v_sel.o_first, v_sel.o_offset), app.to_instant(v_sel.o_last_end, v_sel.o_offset), '[)'),
      v_sel.o_offset, v_sel.o_count, 0, v_sel.o_currency,
      'confirmed', 'block', nullif(btrim(p_reason), ''), p_now, p_now)
    returning * into v_booking;
  exception when exclusion_violation or deadlock_detected then
    raise exception 'slot_taken';
  end;

  perform app.audit(p_user, 'block_slots', 'booking', v_booking.id::text, null, to_jsonb(v_booking), p_now);
  return v_booking;
end $$;

-- Venue cancellation of a booking or a block that has not ended. The slot is
-- free at once; the player's late-cancellation flag is never touched.
create function app.owner_cancel_booking(p_user uuid, p_booking_id uuid, p_now timestamptz)
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
  return v_after;
end $$;

-- Paid or no-show, once the start has passed (product spec §5). Can be
-- changed again to correct a mistake. Paid is what counts as revenue.
create function app.owner_mark_booking(p_user uuid, p_booking_id uuid, p_outcome text, p_now timestamptz)
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
  return v_after;
end $$;

-- A booking as the owner screens receive it: app.booking_json plus who the
-- customer is. For an app booking that is the player's profile name and
-- account phone; for a walk-in, what the owner typed.
create function app.owner_booking_json(b public.bookings) returns jsonb
language sql stable
set search_path = ''
as $$
  select app.booking_json(b) || jsonb_build_object(
    -- Never say whether a walk-in's phone matched an account.
    'user_id', case when b.source = 'walk_in' then null else b.user_id end,
    'source', b.source,
    'walk_in_payment', b.walk_in_payment,
    'customer_name', case b.source
      when 'walk_in' then b.guest_name
      when 'app' then (select p.full_name from public.profiles p where p.id = b.user_id)
    end,
    'customer_phone', case b.source
      when 'walk_in' then b.guest_phone
      when 'app' then (select c.phone from public.profile_contacts c where c.user_id = b.user_id)
    end,
    'reason', case when b.source = 'block' then b.block_reason end)
$$;

-- One court, p_days days from p_from: every slot with its price and state,
-- and every row that covers a slot. A slot is booked or blocked while an
-- active row covers it (a player's live hold counts as booked), otherwise
-- past once it has ended, otherwise free.
create function app.owner_calendar(p_user uuid, p_court_id uuid, p_from date, p_days integer, p_now timestamptz)
returns jsonb
language plpgsql stable
set search_path = ''
as $$
declare
  v_offset integer;
  v_range tstzrange;
  v_slots jsonb;
  v_bookings jsonb;
begin
  perform app.require_court_manager(p_user, p_court_id);
  if p_from is null or p_days is null or p_days < 1 or p_days > 14 then raise exception 'invalid_argument'; end if;

  select ci.utc_offset_minutes into v_offset
  from public.courts c
  join public.venues v on v.id = c.venue_id
  join public.cities ci on ci.id = v.city_id
  where c.id = p_court_id;

  v_range := tstzrange(
    app.to_instant(p_from::timestamp, v_offset), app.to_instant((p_from + p_days)::timestamp, v_offset), '[)');

  with active as (
    select b as bk, b.id, b.source, b.during
    from public.bookings b
    where b.court_id = p_court_id
      and b.during && v_range
      and (b.status in ('confirmed', 'completed', 'paid', 'no_show', 'unverified')
           or (b.status = 'held' and b.hold_expires_at > p_now))
  ),
  slots as (
    select s.starts_local, s.ends_local, s.price
    from generate_series(0, p_days - 1) d (n)
    cross join lateral app.court_slots(p_court_id, p_from + d.n) s
  )
  select
    coalesce((
      select jsonb_agg(jsonb_build_object(
          'starts_local', s.starts_local,
          'ends_local', s.ends_local,
          'price', s.price,
          'state', case
            when cover.id is not null then case when cover.source = 'block' then 'blocked' else 'booked' end
            when app.to_instant(s.ends_local, v_offset) <= p_now then 'past'
            else 'free'
          end,
          'booking_id', cover.id)
        order by s.starts_local)
      from slots s
      left join lateral (
        select a.id, a.source from active a
        where a.during && tstzrange(app.to_instant(s.starts_local, v_offset), app.to_instant(s.ends_local, v_offset))
        order by lower(a.during)
        limit 1
      ) cover on true), '[]'::jsonb),
    coalesce((
      select jsonb_agg(app.owner_booking_json(a.bk) order by lower(a.during), a.id)
      from active a), '[]'::jsonb)
  into v_slots, v_bookings;

  return jsonb_build_object('slots', v_slots, 'bookings', v_bookings);
end $$;

-- ---------------------------------------------------------------------------
-- Scheduled job: finished bookings move on (product spec §5).
-- ---------------------------------------------------------------------------

-- confirmed -> completed once the end has passed; completed -> unverified
-- when nobody marked it within 48 hours of the end. A confirmed booking found
-- more than 48 hours after its end goes straight to unverified. Blocks stay
-- as they are. Returns the number of rows changed.
create function app.advance_bookings(p_now timestamptz) returns integer
language plpgsql
set search_path = ''
as $$
declare
  c_unmarked constant interval := interval '48 hours';
  v_completed integer;
  v_confirmed integer;
begin
  update public.bookings b set status = 'unverified'
  where b.status = 'completed' and b.source <> 'block' and upper(b.during) < p_now - c_unmarked;
  get diagnostics v_completed = row_count;

  update public.bookings b
  set status = case when upper(b.during) < p_now - c_unmarked then 'unverified' else 'completed' end
  where b.status = 'confirmed' and b.source <> 'block' and upper(b.during) <= p_now;
  get diagnostics v_confirmed = row_count;

  return v_completed + v_confirmed;
end $$;

-- ---------------------------------------------------------------------------
-- Player holds: only app bookings count toward the three-booking cap.
-- ---------------------------------------------------------------------------

-- app.hold_slots from bookings.sql, unchanged except that the cap counts
-- rows with source = 'app': a walk-in an owner linked to the player is not
-- the pay-at-venue app booking the cap guards against.
-- Holds back-to-back slots for five minutes. A player has one hold at a
-- time: a new hold replaces their previous one.
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
      where b.user_id = p_user and b.source = 'app' and b.status = 'confirmed'
        and lower(b.during) > p_now) >= c_max_upcoming then
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

-- app.cancel_booking from bookings.sql, unchanged except that a player can
-- cancel only their own app bookings: a walk-in the venue linked to their
-- account is the venue's to cancel.
-- Player cancellation: free until six hours before the start, flagged late
-- after that, impossible once the slot has started.
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
  return v_booking;
end $$;

-- ---------------------------------------------------------------------------
-- What the app calls. Each runs as the signed-in user at the real time.
-- ---------------------------------------------------------------------------

create function public.my_venue_ids() returns uuid[]
language sql stable security definer
set search_path = ''
as $$ select app.my_venue_ids((select auth.uid())) $$;

create function public.owner_calendar(p_court_id uuid, p_from date, p_days integer) returns jsonb
language sql stable security definer
set search_path = ''
as $$ select app.owner_calendar((select auth.uid()), p_court_id, p_from, p_days, now()) $$;

create function public.owner_create_walk_in(
  p_court_id uuid, p_starts timestamp[], p_name text, p_phone text, p_players integer, p_payment_method text)
returns jsonb
language sql security definer
set search_path = ''
as $$
  select app.owner_booking_json(app.owner_create_walk_in(
    (select auth.uid()), p_court_id, p_starts, p_name, p_phone, p_players, p_payment_method, now()))
$$;

create function public.owner_block_slots(p_court_id uuid, p_starts timestamp[], p_reason text default null)
returns jsonb
language sql security definer
set search_path = ''
as $$ select app.owner_booking_json(app.owner_block_slots((select auth.uid()), p_court_id, p_starts, p_reason, now())) $$;

create function public.owner_cancel_booking(p_booking_id uuid) returns jsonb
language sql security definer
set search_path = ''
as $$ select app.owner_booking_json(app.owner_cancel_booking((select auth.uid()), p_booking_id, now())) $$;

create function public.owner_mark_booking(p_booking_id uuid, p_outcome text) returns jsonb
language sql security definer
set search_path = ''
as $$ select app.owner_booking_json(app.owner_mark_booking((select auth.uid()), p_booking_id, p_outcome, now())) $$;

revoke all on function
  public.my_venue_ids(),
  public.owner_calendar(uuid, date, integer),
  public.owner_create_walk_in(uuid, timestamp[], text, text, integer, text),
  public.owner_block_slots(uuid, timestamp[], text),
  public.owner_cancel_booking(uuid),
  public.owner_mark_booking(uuid, text)
from public, anon, authenticated;

grant execute on function
  public.my_venue_ids(),
  public.owner_calendar(uuid, date, integer),
  public.owner_create_walk_in(uuid, timestamp[], text, text, integer, text),
  public.owner_block_slots(uuid, timestamp[], text),
  public.owner_cancel_booking(uuid),
  public.owner_mark_booking(uuid, text)
to authenticated, service_role;

-- Every ten minutes, where pg_cron exists (as in jobs.sql).
do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron;
    execute $job$
      select cron.schedule(
        'actra-advance-bookings',
        '*/10 * * * *',
        'select app.advance_bookings(now())')
    $job$;
  end if;
end $$;
