-- Tournaments (Milestone 5a): categories, registration, partners and the
-- waitlist (product spec §14, rule 2: a category never counts more than its
-- cap).
--
-- Additive only: new columns, tables and functions; `set_settings` and the
-- reminders job are redefined with the same signature and name. As
-- elsewhere, the rules live in the private `app` schema and take the acting
-- user and the clock; the `public` wrappers pass auth.uid() and now().
--
-- Locking order, everywhere: the category row, then registration rows, then
-- the tournament row (taken last, by app.sync_tournament_summary). Every
-- path that can raise a category's count takes the category row lock first.
--
-- Times and money come from the tournament's city (venue_id may be null):
-- its UTC offset for wall-clock times and its currency for fees.

-- ---------------------------------------------------------------------------
-- Columns
-- ---------------------------------------------------------------------------

alter table public.tournaments
  add column description_uz text,
  add column description_ru text,
  add column description_en text,
  -- Entered as venue wall-clock time; null means 00:00 on starts_on.
  add column registration_deadline timestamptz,
  add column cover_url text,
  add column color_seed integer not null default 0;

-- When the player last opened the app (touch_last_seen), for "active users".
-- Not in the column grant of 20261124100000_community_core.sql: other
-- players cannot read it.
alter table public.profiles add column last_seen_at timestamptz;

-- The new notification category. The check was declared inline, so look its
-- name up instead of assuming it.
do $$
declare
  v_name text;
begin
  select c.conname into v_name from pg_constraint c
  where c.conrelid = 'public.notifications'::regclass and c.contype = 'c'
    and pg_get_constraintdef(c.oid) like '%category%';
  if v_name is not null then
    execute format('alter table public.notifications drop constraint %I', v_name);
  end if;
end $$;
alter table public.notifications add constraint notifications_category_check
  check (category in ('bookings', 'venue', 'games', 'requests', 'invites', 'tournaments'));

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------

create table public.tournament_categories (
  id uuid primary key default gen_random_uuid(),
  tournament_id uuid not null references public.tournaments (id) on delete cascade,
  name_uz text,
  name_ru text,
  name_en text,
  kind text not null check (kind in ('singles', 'pairs')),
  -- Shown, not enforced: profiles have no gender.
  gender text not null default 'open' check (gender in ('men', 'women', 'mixed', 'open')),
  min_level integer not null default 1 check (min_level between 1 and 5),
  max_level integer not null default 5 check (max_level between 1 and 5),
  fee integer not null default 0 check (fee >= 0),
  -- Entries (players for singles, pairs for pairs).
  cap integer not null check (cap between 1 and 512),
  waitlist_enabled boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  constraint tournament_categories_levels check (min_level <= max_level),
  constraint tournament_categories_named check (coalesce(name_uz, name_ru, name_en) is not null)
);
create index tournament_categories_tournament_idx on public.tournament_categories (tournament_id, sort_order);

-- Order of joining the waitlist.
create sequence app.tournament_waitlist_seq;

-- One entry: a player (singles) or a pair, registrant first. States (spec
-- §14): pending_partner -> registered | expired | declined; registered ->
-- cancelled | removed; waitlisted -> offered -> registered | lapsed. Counted
-- toward the cap: registered, offered. Paid is a flag (paid_at).
create table public.tournament_registrations (
  id uuid primary key default gen_random_uuid(),
  category_id uuid not null references public.tournament_categories (id) on delete restrict,
  user_id uuid not null references public.profiles (id) on delete cascade,
  partner_id uuid references public.profiles (id) on delete cascade,
  -- true once the partner accepted; always true for singles.
  partner_confirmed boolean not null default false,
  status text not null check (status in (
    'pending_partner', 'registered', 'waitlisted', 'offered',
    'cancelled', 'removed', 'declined', 'expired', 'lapsed')),
  -- Locked at registration (spec §14 rule 4).
  fee integer not null check (fee >= 0),
  currency text not null,
  paid_at timestamptz,
  partner_expires_at timestamptz,
  offer_expires_at timestamptz,
  reminded_at timestamptz,
  waitlist_position bigint,
  created_at timestamptz not null default now(),
  decided_at timestamptz,
  cancelled_at timestamptz,
  admin_override boolean not null default false,
  constraint tournament_registrations_partner check (partner_id is distinct from user_id)
);
-- One live entry per registrant per category.
create unique index tournament_registrations_live_registrant on public.tournament_registrations (category_id, user_id)
  where status in ('pending_partner', 'registered', 'waitlisted', 'offered');
-- And per confirmed partner: a pending invite never locks anyone out.
create unique index tournament_registrations_live_partner on public.tournament_registrations (category_id, partner_id)
  where partner_confirmed and status in ('pending_partner', 'registered', 'waitlisted', 'offered');
create index tournament_registrations_category_idx on public.tournament_registrations (category_id, status);
create index tournament_registrations_user_idx on public.tournament_registrations (user_id);
create index tournament_registrations_partner_idx on public.tournament_registrations (partner_id);

-- find_player_by_phone calls, for its hourly limit.
create table public.phone_lookups (
  user_id uuid not null references public.profiles (id) on delete cascade,
  at timestamptz not null
);
create index phone_lookups_user_idx on public.phone_lookups (user_id, at);

-- No client access at all: everything goes through the functions.
alter table public.tournament_categories enable row level security;
alter table public.tournament_registrations enable row level security;
alter table public.phone_lookups enable row level security;
revoke all on table public.tournament_categories, public.tournament_registrations, public.phone_lookups
  from public, anon, authenticated;
grant all on table public.tournament_categories, public.tournament_registrations, public.phone_lookups
  to service_role;
revoke all on sequence app.tournament_waitlist_seq from public;

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

create function app.tournament_offset(t public.tournaments) returns integer
language sql stable
set search_path = ''
as $$ select ci.utc_offset_minutes from public.cities ci where ci.id = t.city_id $$;

-- When registration closes: the stored deadline, or 00:00 venue time on the
-- first day for a row written without one (the seed, until it carries it).
create function app.tournament_deadline(t public.tournaments) returns timestamptz
language sql stable
set search_path = ''
as $$ select coalesce(t.registration_deadline, app.to_instant(t.starts_on::timestamp, app.tournament_offset(t))) $$;

-- Entries holding a spot. Not stable: callers count right after writing.
create function app.category_counted(p_category_id uuid) returns integer
language sql
set search_path = ''
as $$
  select count(*)::integer from public.tournament_registrations r
  where r.category_id = p_category_id and r.status in ('registered', 'offered')
$$;

-- The player is in the category: registrant of a live entry, or its
-- confirmed partner. p_except leaves one entry out (the one being decided).
create function app.live_in_category(p_category_id uuid, p_user uuid, p_except uuid) returns boolean
language sql
set search_path = ''
as $$
  select exists (
    select 1 from public.tournament_registrations r
    where r.category_id = p_category_id
      and r.status in ('pending_partner', 'registered', 'waitlisted', 'offered')
      and r.id is distinct from p_except
      and (r.user_id = p_user or (r.partner_id = p_user and r.partner_confirmed)))
$$;

-- The entry is the player's: its registrant or its confirmed partner. Never
-- null (a singles entry has no partner), so `not` is safe on it.
create function app.entry_member(r public.tournament_registrations, p_user uuid) returns boolean
language sql immutable
set search_path = ''
as $$
  select p_user is not null
    and (r.user_id = p_user or coalesce(r.partner_id = p_user and r.partner_confirmed, false))
$$;

create function app.player_level(p_user uuid, p_sport_id text) returns integer
language sql stable
set search_path = ''
as $$
  select coalesce((select l.level from public.player_levels l where l.user_id = p_user and l.sport_id = p_sport_id), 1)
$$;

-- Recomputes the summary columns the installed M4 app reads (min_fee,
-- max_fee, slots_total, slots_filled) from the categories and their counted
-- entries. The tournament row is locked in its own statement first, so the
-- counts that follow see every change committed before it.
create function app.sync_tournament_summary(p_tournament_id uuid) returns void
language plpgsql
set search_path = ''
as $$
declare
  v_min integer;
  v_max integer;
  v_total integer;
  v_filled integer;
begin
  perform 1 from public.tournaments t where t.id = p_tournament_id for update;
  if not found then return; end if;
  select coalesce(min(c.fee), 0), coalesce(max(c.fee), 0), coalesce(sum(c.cap), 0),
         coalesce(sum(app.category_counted(c.id)), 0)
    into v_min, v_max, v_total, v_filled
  from public.tournament_categories c where c.tournament_id = p_tournament_id;
  update public.tournaments t
  set min_fee = v_min, max_fee = v_max, slots_total = v_total, slots_filled = v_filled
  where t.id = p_tournament_id;
end $$;

-- Locks an entry for a change: its category first, then the entry. Returns
-- null when there is no such entry.
create function app.lock_registration(p_registration_id uuid) returns public.tournament_registrations
language plpgsql
set search_path = ''
as $$
declare
  v_category_id uuid;
  v_reg public.tournament_registrations;
begin
  loop
    select r.category_id into v_category_id from public.tournament_registrations r where r.id = p_registration_id;
    if not found then return null; end if;
    perform 1 from public.tournament_categories c where c.id = v_category_id for update;
    select r.* into v_reg from public.tournament_registrations r where r.id = p_registration_id for update;
    if not found then return null; end if;
    -- An admin may have moved it to another category meanwhile: lock that one.
    if v_reg.category_id = v_category_id then return v_reg; end if;
  end loop;
end $$;

-- What every tournament notification carries besides its own keys.
create function app.registration_note(r public.tournament_registrations) returns jsonb
language sql stable
set search_path = ''
as $$
  select jsonb_build_object(
    'registration_id', r.id,
    'tournament_id', t.id,
    'category_id', c.id,
    'title', jsonb_build_object('uz', t.title_uz, 'ru', t.title_ru, 'en', t.title_en),
    'category_name', jsonb_build_object('uz', c.name_uz, 'ru', c.name_ru, 'en', c.name_en))
  from public.tournament_categories c
  join public.tournaments t on t.id = c.tournament_id
  where c.id = r.category_id
$$;

-- ---------------------------------------------------------------------------
-- JSON. Not stable: each must see rows written earlier in the same
-- statement (select app.registration_json(app.register(...))).
-- ---------------------------------------------------------------------------

-- An entry as the app receives it. Never a phone number.
create function app.registration_json(r public.tournament_registrations) returns jsonb
language sql
set search_path = ''
as $$
  select jsonb_build_object(
    'id', r.id,
    'tournament_id', c.tournament_id,
    'category_id', r.category_id,
    'category_name', jsonb_build_object('uz', c.name_uz, 'ru', c.name_ru, 'en', c.name_en),
    'kind', c.kind,
    'status', r.status,
    'registrant', jsonb_build_object('id', r.user_id, 'name', (select p.full_name from public.profiles p where p.id = r.user_id)),
    'partner', case when r.partner_id is null then null else
      jsonb_build_object('id', r.partner_id, 'name', (select p.full_name from public.profiles p where p.id = r.partner_id)) end,
    'partner_confirmed', r.partner_confirmed,
    'fee', r.fee,
    'currency', r.currency,
    'paid', r.paid_at is not null,
    'partner_expires_local', app.to_local(r.partner_expires_at, app.tournament_offset(t)),
    'offer_expires_local', app.to_local(r.offer_expires_at, app.tournament_offset(t)),
    -- 1 = next in line, among entries that can be offered a spot (singles,
    -- and pairs whose partner confirmed); null for a pair still waiting on
    -- its partner.
    'waitlist_place', case when r.status = 'waitlisted' and r.partner_confirmed then
      (select count(*) from public.tournament_registrations w
       where w.category_id = r.category_id and w.status = 'waitlisted' and w.partner_confirmed
         and (w.waitlist_position, w.id) <= (r.waitlist_position, r.id)) end,
    'created_at', r.created_at)
  from public.tournament_categories c
  join public.tournaments t on t.id = c.tournament_id
  where c.id = r.category_id
$$;

create function app.category_json(c public.tournament_categories, p_user uuid) returns jsonb
language sql
set search_path = ''
as $$
  select jsonb_build_object(
    'id', c.id,
    'tournament_id', c.tournament_id,
    'name_uz', c.name_uz,
    'name_ru', c.name_ru,
    'name_en', c.name_en,
    'kind', c.kind,
    'gender', c.gender,
    'min_level', c.min_level,
    'max_level', c.max_level,
    'fee', c.fee,
    'cap', c.cap,
    'filled', app.category_counted(c.id),
    'full', app.category_counted(c.id) >= c.cap,
    'waitlist_enabled', c.waitlist_enabled,
    'waitlist_count', (select count(*) from public.tournament_registrations r
                       where r.category_id = c.id and r.status = 'waitlisted'),
    'sort_order', c.sort_order,
    -- The caller's live entry in it, as registrant or named partner.
    'my_status', case when p_user is null then null else
      (select r.status from public.tournament_registrations r
       where r.category_id = c.id and r.status in ('pending_partner', 'registered', 'waitlisted', 'offered')
         and (r.user_id = p_user or r.partner_id = p_user)
       order by (r.user_id = p_user or r.partner_confirmed) desc, r.created_at desc
       limit 1) end)
$$;

-- A tournament for one viewing player. my_registrations: the caller's live
-- entries (as registrant, or as partner whether confirmed or invited).
create function app.tournament_json(t public.tournaments, p_user uuid, p_now timestamptz) returns jsonb
language sql
set search_path = ''
as $$
  select jsonb_build_object(
    'id', t.id,
    'city_id', t.city_id,
    'sport_id', t.sport_id,
    'venue_id', t.venue_id,
    'venue_name', app.venue_name(t.venue_id),
    'title_uz', t.title_uz,
    'title_ru', t.title_ru,
    'title_en', t.title_en,
    'description_uz', t.description_uz,
    'description_ru', t.description_ru,
    'description_en', t.description_en,
    'starts_on', t.starts_on,
    'ends_on', t.ends_on,
    'registration_deadline_local', app.to_local(app.tournament_deadline(t), app.tournament_offset(t)),
    'registration_open', t.active and p_now < app.tournament_deadline(t),
    'cover_url', t.cover_url,
    'color_seed', t.color_seed,
    'active', t.active,
    'currency', (select ci.currency from public.cities ci where ci.id = t.city_id),
    'fee_min', (select min(c.fee) from public.tournament_categories c where c.tournament_id = t.id),
    'fee_max', (select max(c.fee) from public.tournament_categories c where c.tournament_id = t.id),
    'slots_total', t.slots_total,
    'slots_filled', t.slots_filled,
    'categories', coalesce(
      (select jsonb_agg(app.category_json(c, p_user) order by c.sort_order, c.created_at, c.id)
       from public.tournament_categories c where c.tournament_id = t.id),
      '[]'::jsonb),
    'my_registrations', case when p_user is null then '[]'::jsonb else coalesce(
      (select jsonb_agg(app.registration_json(r) order by r.created_at desc, r.id)
       from public.tournament_registrations r
       join public.tournament_categories c on c.id = r.category_id
       where c.tournament_id = t.id
         and r.status in ('pending_partner', 'registered', 'waitlisted', 'offered')
         and (r.user_id = p_user or r.partner_id = p_user)),
      '[]'::jsonb) end)
$$;

-- ---------------------------------------------------------------------------
-- Backfill: run once below; idempotent, so tests can call it on rows of
-- their own.
-- ---------------------------------------------------------------------------

-- Every tournament gets a deadline (00:00 venue time on its first day) and,
-- when it has no category, one open singles category with the tournament's
-- min_fee and slots_total (clamped to 1..512), under the id the sample data
-- uses too, so a later seed run upserts it instead of adding a second.
create function app.backfill_tournaments() returns void
language plpgsql
set search_path = ''
as $$
declare
  v_id uuid;
begin
  update public.tournaments t
  set registration_deadline = app.to_instant(t.starts_on::timestamp, ci.utc_offset_minutes)
  from public.cities ci
  where ci.id = t.city_id and t.registration_deadline is null;

  for v_id in
    insert into public.tournament_categories (
      id, tournament_id, name_uz, name_ru, name_en, kind, gender, min_level, max_level, fee, cap)
    select md5('actra:default-category:' || t.id::text)::uuid, t.id, 'Ochiq', 'Открытая', 'Open',
           'singles', 'open', 1, 5, greatest(t.min_fee, 0), greatest(1, least(512, t.slots_total))
    from public.tournaments t
    where not exists (select 1 from public.tournament_categories c where c.tournament_id = t.id)
    on conflict (id) do nothing
    returning tournament_id
  loop
    perform app.sync_tournament_summary(v_id);
  end loop;
end $$;

select app.backfill_tournaments();

-- ---------------------------------------------------------------------------
-- Registering
-- ---------------------------------------------------------------------------

-- The checks register and join_waitlist share, in this order: reliability,
-- deadline, arguments, levels, already in, partner already in. The caller
-- holds the category row lock, so the "already in" answers stay true.
create function app.check_entry(
  p_user uuid, c public.tournament_categories, t public.tournaments, p_partner_id uuid, p_now timestamptz)
returns void
language plpgsql
set search_path = ''
as $$
begin
  perform app.require_reliable(p_user, p_now);
  if p_now >= app.tournament_deadline(t) then raise exception 'deadline_passed'; end if;

  if c.kind = 'singles' and p_partner_id is not null then raise exception 'invalid_argument'; end if;
  if c.kind = 'pairs' then
    if p_partner_id is null or p_partner_id = p_user then raise exception 'invalid_argument'; end if;
    if not exists (select 1 from public.profiles p where p.id = p_partner_id) then raise exception 'not_found'; end if;
  end if;

  if app.player_level(p_user, t.sport_id) not between c.min_level and c.max_level
     or (p_partner_id is not null and app.player_level(p_partner_id, t.sport_id) not between c.min_level and c.max_level) then
    raise exception 'level_out_of_range';
  end if;

  if app.live_in_category(c.id, p_user, null) then raise exception 'already_registered'; end if;
  if p_partner_id is not null and app.live_in_category(c.id, p_partner_id, null) then
    raise exception 'partner_unavailable';
  end if;
end $$;

-- The category of an active tournament, locked.
create function app.lock_category(p_category_id uuid) returns public.tournament_categories
language plpgsql
set search_path = ''
as $$
declare
  v_category public.tournament_categories;
begin
  select c.* into v_category from public.tournament_categories c
  join public.tournaments t on t.id = c.tournament_id
  where c.id = p_category_id and t.active
  for update of c;
  if not found then raise exception 'not_found'; end if;
  return v_category;
end $$;

-- Singles: registered at once while there is room. Pairs: pending until the
-- partner accepts (48 hours, or until the deadline if sooner); not counted.
create function app.register(p_user uuid, p_category_id uuid, p_partner_id uuid, p_now timestamptz)
returns public.tournament_registrations
language plpgsql
set search_path = ''
as $$
declare
  v_category public.tournament_categories;
  v_tournament public.tournaments;
  v_deadline timestamptz;
  v_reg public.tournament_registrations;
begin
  if p_user is null then raise exception 'not_authenticated'; end if;
  v_category := app.lock_category(p_category_id);
  -- Expired offers and invites hold no spot and block nobody.
  perform app.sweep_category(v_category.id, p_now);
  select t.* into v_tournament from public.tournaments t where t.id = v_category.tournament_id;
  perform app.check_entry(p_user, v_category, v_tournament, p_partner_id, p_now);
  v_deadline := app.tournament_deadline(v_tournament);

  if v_category.kind = 'singles' and app.category_counted(v_category.id) >= v_category.cap then
    raise exception 'full';
  end if;

  begin
    insert into public.tournament_registrations (
      category_id, user_id, partner_id, partner_confirmed, status, fee, currency,
      partner_expires_at, reminded_at, created_at, decided_at)
    values (
      v_category.id, p_user, p_partner_id, v_category.kind = 'singles',
      case v_category.kind when 'singles' then 'registered' else 'pending_partner' end,
      v_category.fee,
      (select ci.currency from public.cities ci where ci.id = v_tournament.city_id),
      case when v_category.kind = 'pairs' then least(p_now + interval '48 hours', v_deadline) end,
      -- Invited inside the last 24 hours: the deadline is already close, so
      -- no separate reminder follows.
      case when v_category.kind = 'pairs' and v_deadline <= p_now + interval '24 hours' then p_now end,
      p_now,
      case when v_category.kind = 'singles' then p_now end)
    returning * into v_reg;
  exception when unique_violation then
    raise exception 'already_registered';
  end;

  if v_category.kind = 'singles' then
    perform app.notify(p_user, 'tournament_registered', 'tournaments', app.registration_note(v_reg), p_now);
    perform app.sync_tournament_summary(v_tournament.id);
  else
    perform app.notify(p_partner_id, 'tournament_partner_invite', 'invites',
      app.registration_note(v_reg) || jsonb_build_object('actor_name', (select p.full_name from public.profiles p where p.id = p_user)),
      p_now);
  end if;
  return v_reg;
end $$;

-- The named partner answers a pending pair, or an unconfirmed waitlisted
-- pair. Accepting a pending pair registers it while there is room; accepting
-- a waitlisted pair confirms it (it keeps its place, and is offered at once
-- if a spot is free).
create function app.respond_partner(p_user uuid, p_registration_id uuid, p_accept boolean, p_now timestamptz)
returns public.tournament_registrations
language plpgsql
set search_path = ''
as $$
declare
  v_reg public.tournament_registrations;
  v_category public.tournament_categories;
  v_tournament public.tournaments;
  v_note jsonb;
  v_actor jsonb;
begin
  if p_user is null then raise exception 'not_authenticated'; end if;
  if p_accept is null then raise exception 'invalid_argument'; end if;
  v_reg := app.lock_registration(p_registration_id);
  if v_reg.id is null or v_reg.partner_id is distinct from p_user then raise exception 'not_found'; end if;
  select c.* into v_category from public.tournament_categories c where c.id = v_reg.category_id;
  select t.* into v_tournament from public.tournaments t where t.id = v_category.tournament_id;
  if p_now >= app.tournament_deadline(v_tournament) then raise exception 'deadline_passed'; end if;
  if not (v_reg.status in ('pending_partner', 'waitlisted') and not v_reg.partner_confirmed
          and coalesce(v_reg.partner_expires_at > p_now, true)) then
    raise exception 'not_found';
  end if;

  v_actor := jsonb_build_object('actor_name', (select p.full_name from public.profiles p where p.id = p_user));

  if not p_accept then
    update public.tournament_registrations r set status = 'declined', decided_at = p_now
    where r.id = v_reg.id returning * into v_reg;
    perform app.notify(v_reg.user_id, 'tournament_partner_declined', 'tournaments', app.registration_note(v_reg) || v_actor, p_now);
    return v_reg;
  end if;

  perform app.require_reliable(p_user, p_now);
  -- Levels may have changed since the invite: both players must still fit.
  if app.player_level(v_reg.user_id, v_tournament.sport_id) not between v_category.min_level and v_category.max_level
     or app.player_level(p_user, v_tournament.sport_id) not between v_category.min_level and v_category.max_level then
    raise exception 'level_out_of_range';
  end if;
  -- Expired offers and invites hold no spot and block nobody.
  perform app.sweep_category(v_category.id, p_now);
  if app.live_in_category(v_category.id, v_reg.user_id, v_reg.id)
     or app.live_in_category(v_category.id, p_user, v_reg.id) then
    raise exception 'partner_unavailable';
  end if;

  if v_reg.status = 'pending_partner' then
    if app.category_counted(v_category.id) >= v_category.cap then raise exception 'full'; end if;
    begin
      update public.tournament_registrations r
      set status = 'registered', partner_confirmed = true, decided_at = p_now
      where r.id = v_reg.id returning * into v_reg;
    exception when unique_violation then
      raise exception 'partner_unavailable';
    end;
    v_note := app.registration_note(v_reg);
    perform app.notify(v_reg.user_id, 'tournament_partner_accepted', 'tournaments', v_note || v_actor, p_now);
    perform app.notify(v_reg.user_id, 'tournament_registered', 'tournaments', v_note, p_now);
    perform app.notify(p_user, 'tournament_registered', 'tournaments', v_note, p_now);
  else
    begin
      update public.tournament_registrations r set partner_confirmed = true
      where r.id = v_reg.id returning * into v_reg;
    exception when unique_violation then
      raise exception 'partner_unavailable';
    end;
    perform app.notify(v_reg.user_id, 'tournament_partner_accepted', 'tournaments', app.registration_note(v_reg) || v_actor, p_now);
    perform app.offer_next(v_category.id, p_now);
    select r.* into v_reg from public.tournament_registrations r where r.id = v_reg.id;
  end if;

  perform app.sync_tournament_summary(v_tournament.id);
  return v_reg;
end $$;

-- The registrant or the confirmed partner, until the deadline. A spot that
-- held a place goes to the waitlist. On a pair, the other player is told
-- (tournament_partner_cancelled): the partner when the registrant cancels,
-- whether the partner confirmed or was only invited, and the registrant when
-- the partner cancels.
create function app.cancel_registration(p_user uuid, p_registration_id uuid, p_now timestamptz)
returns public.tournament_registrations
language plpgsql
set search_path = ''
as $$
declare
  v_reg public.tournament_registrations;
  v_tournament public.tournaments;
  v_counted boolean;
  v_other uuid;
begin
  if p_user is null then raise exception 'not_authenticated'; end if;
  v_reg := app.lock_registration(p_registration_id);
  if v_reg.id is null or not app.entry_member(v_reg, p_user) then raise exception 'not_found'; end if;
  select t.* into v_tournament from public.tournaments t
  join public.tournament_categories c on c.tournament_id = t.id
  where c.id = v_reg.category_id;
  if not v_tournament.active then raise exception 'not_found'; end if;
  if p_now >= app.tournament_deadline(v_tournament) then raise exception 'deadline_passed'; end if;
  if v_reg.status not in ('pending_partner', 'registered', 'waitlisted', 'offered') then raise exception 'not_found'; end if;

  v_counted := v_reg.status in ('registered', 'offered');
  update public.tournament_registrations r set status = 'cancelled', cancelled_at = p_now
  where r.id = v_reg.id returning * into v_reg;

  v_other := case when v_reg.user_id = p_user then v_reg.partner_id else v_reg.user_id end;
  if v_other is not null then
    perform app.notify(v_other, 'tournament_partner_cancelled', 'tournaments',
      app.registration_note(v_reg) || jsonb_build_object('actor_name', (select p.full_name from public.profiles p where p.id = p_user)),
      p_now);
  end if;

  if v_counted then perform app.offer_next(v_reg.category_id, p_now); end if;
  perform app.sync_tournament_summary(v_tournament.id);
  return v_reg;
end $$;

-- Only into a full category with the waitlist on. Same checks as register.
-- A pairs entry waits for its partner's confirmation before it can be
-- offered a spot; singles entries are confirmed from the start.
create function app.join_waitlist(p_user uuid, p_category_id uuid, p_partner_id uuid, p_now timestamptz)
returns public.tournament_registrations
language plpgsql
set search_path = ''
as $$
declare
  v_category public.tournament_categories;
  v_tournament public.tournaments;
  v_deadline timestamptz;
  v_reg public.tournament_registrations;
begin
  if p_user is null then raise exception 'not_authenticated'; end if;
  v_category := app.lock_category(p_category_id);
  -- Expired offers and invites hold no spot and block nobody.
  perform app.sweep_category(v_category.id, p_now);
  select t.* into v_tournament from public.tournaments t where t.id = v_category.tournament_id;
  perform app.check_entry(p_user, v_category, v_tournament, p_partner_id, p_now);
  if not v_category.waitlist_enabled then raise exception 'waitlist_closed'; end if;
  if app.category_counted(v_category.id) < v_category.cap then raise exception 'not_full'; end if;
  v_deadline := app.tournament_deadline(v_tournament);

  -- A pair's invite runs like a pending pair's: 48 hours, or until the
  -- deadline if sooner, with the same reminder rule.
  begin
    insert into public.tournament_registrations (
      category_id, user_id, partner_id, partner_confirmed, status, fee, currency, waitlist_position,
      partner_expires_at, reminded_at, created_at)
    values (
      v_category.id, p_user, p_partner_id, v_category.kind = 'singles', 'waitlisted', v_category.fee,
      (select ci.currency from public.cities ci where ci.id = v_tournament.city_id),
      nextval('app.tournament_waitlist_seq'),
      case when v_category.kind = 'pairs' then least(p_now + interval '48 hours', v_deadline) end,
      case when v_category.kind = 'pairs' and v_deadline <= p_now + interval '24 hours' then p_now end,
      p_now)
    returning * into v_reg;
  exception when unique_violation then
    raise exception 'already_registered';
  end;

  if v_category.kind = 'pairs' then
    perform app.notify(p_partner_id, 'tournament_partner_invite', 'invites',
      app.registration_note(v_reg) || jsonb_build_object('actor_name', (select p.full_name from public.profiles p where p.id = p_user)),
      p_now);
  end if;
  return v_reg;
end $$;

-- While the category has room, the first confirmed waitlisted entry is
-- offered the spot for 24 hours (or until the deadline if sooner); the offer
-- holds the spot. Unconfirmed pairs are skipped, not removed. Nothing once
-- the deadline has passed. Returns how many entries were offered.
create function app.offer_next(p_category_id uuid, p_now timestamptz) returns integer
language plpgsql
set search_path = ''
as $$
declare
  v_category public.tournament_categories;
  v_tournament public.tournaments;
  v_deadline timestamptz;
  v_reg public.tournament_registrations;
  v_note jsonb;
  v_count integer := 0;
begin
  select c.* into v_category from public.tournament_categories c where c.id = p_category_id for update;
  if not found then return 0; end if;
  select t.* into v_tournament from public.tournaments t where t.id = v_category.tournament_id;
  v_deadline := app.tournament_deadline(v_tournament);
  if not v_tournament.active or p_now >= v_deadline then return 0; end if;

  loop
    exit when app.category_counted(p_category_id) >= v_category.cap;
    update public.tournament_registrations r
    set status = 'offered', offer_expires_at = least(p_now + interval '24 hours', v_deadline)
    where r.id = (
      select w.id from public.tournament_registrations w
      where w.category_id = p_category_id and w.status = 'waitlisted' and w.partner_confirmed
      order by w.waitlist_position, w.id
      limit 1)
    returning * into v_reg;
    exit when not found;

    v_note := app.registration_note(v_reg)
      || jsonb_build_object('offer_expires_local', app.to_local(v_reg.offer_expires_at, app.tournament_offset(v_tournament)));
    perform app.notify(v_reg.user_id, 'tournament_spot_offered', 'tournaments', v_note, p_now);
    perform app.notify(v_reg.partner_id, 'tournament_spot_offered', 'tournaments', v_note, p_now);
    v_count := v_count + 1;
  end loop;

  if v_count > 0 then perform app.sync_tournament_summary(v_tournament.id); end if;
  return v_count;
end $$;

-- The registrant or the confirmed partner takes an offered spot while the
-- offer runs. Both players already agreed, so one claim completes it.
create function app.claim_offer(p_user uuid, p_registration_id uuid, p_now timestamptz)
returns public.tournament_registrations
language plpgsql
set search_path = ''
as $$
declare
  v_reg public.tournament_registrations;
  v_note jsonb;
begin
  if p_user is null then raise exception 'not_authenticated'; end if;
  v_reg := app.lock_registration(p_registration_id);
  if v_reg.id is null or not app.entry_member(v_reg, p_user)
     or v_reg.status <> 'offered' or coalesce(v_reg.offer_expires_at <= p_now, true)
     or not (select t.active from public.tournaments t
             join public.tournament_categories c on c.tournament_id = t.id
             where c.id = v_reg.category_id) then
    raise exception 'not_found';
  end if;
  perform app.require_reliable(p_user, p_now);
  -- Expired offers and invites elsewhere in the category are settled too.
  perform app.sweep_category(v_reg.category_id, p_now);

  update public.tournament_registrations r set status = 'registered', decided_at = p_now
  where r.id = v_reg.id returning * into v_reg;

  v_note := app.registration_note(v_reg);
  perform app.notify(v_reg.user_id, 'tournament_registered', 'tournaments', v_note, p_now);
  perform app.notify(v_reg.partner_id, 'tournament_registered', 'tournaments', v_note, p_now);
  perform app.sync_tournament_summary((select c.tournament_id from public.tournament_categories c where c.id = v_reg.category_id));
  return v_reg;
end $$;

-- ---------------------------------------------------------------------------
-- Scheduled work
-- ---------------------------------------------------------------------------

-- Settles one category's expired entries as of p_now: invites past their
-- expiry (pending pairs, and waitlisted pairs whose partner never confirmed)
-- become expired and the registrant is told; offers past theirs become
-- lapsed and the spot goes to the next entry. The caller holds the
-- category's row lock. Used by the job, by get_tournament before it shows
-- the categories and, before they count, by register, respond_partner,
-- join_waitlist and claim_offer, so an expired entry never holds a spot,
-- blocks anyone or shows as claimable until the job runs. Returns how many entries
-- expired or lapsed.
create function app.sweep_category(p_category_id uuid, p_now timestamptz) returns integer
language plpgsql
set search_path = ''
as $$
declare
  v_reg public.tournament_registrations;
  v_lapsed integer;
  v_count integer := 0;
begin
  for v_reg in
    update public.tournament_registrations r set status = 'expired', decided_at = p_now
    where r.category_id = p_category_id and not r.partner_confirmed and r.partner_expires_at <= p_now
      and r.status in ('pending_partner', 'waitlisted')
    returning r.*
  loop
    perform app.notify(v_reg.user_id, 'tournament_partner_expired', 'tournaments', app.registration_note(v_reg), p_now);
    v_count := v_count + 1;
  end loop;

  update public.tournament_registrations r set status = 'lapsed', decided_at = p_now
  where r.category_id = p_category_id and r.status = 'offered' and r.offer_expires_at <= p_now;
  get diagnostics v_lapsed = row_count;
  if v_lapsed > 0 then
    v_count := v_count + v_lapsed;
    perform app.offer_next(p_category_id, p_now);
    perform app.sync_tournament_summary((select c.tournament_id from public.tournament_categories c where c.id = p_category_id));
  end if;
  return v_count;
end $$;

-- Every category with expired entries is swept (app.sweep_category). Pairs
-- still waiting on their partner (pending, or waitlisted unconfirmed) whose
-- deadline is within 24 hours: the registrant reminded once. Every category
-- it will touch is locked first, in id order, before any tournament row, so
-- the job never deadlocks with a player's call. Returns how many entries
-- expired or lapsed.
create function app.expire_tournament_entries(p_now timestamptz) returns integer
language plpgsql
set search_path = ''
as $$
declare
  v_categories uuid[];
  v_category_id uuid;
  v_reg public.tournament_registrations;
  v_count integer := 0;
begin
  select array_agg(x.id order by x.id) into v_categories
  from (
    select distinct r.category_id as id
    from public.tournament_registrations r
    join public.tournament_categories c on c.id = r.category_id
    join public.tournaments t on t.id = c.tournament_id
    where (r.status in ('pending_partner', 'waitlisted') and not r.partner_confirmed
           and (r.partner_expires_at <= p_now
                or (r.reminded_at is null
                    and app.tournament_deadline(t) > p_now and app.tournament_deadline(t) <= p_now + interval '24 hours')))
       or (r.status = 'offered' and r.offer_expires_at <= p_now)
  ) x;
  if v_categories is null then return 0; end if;

  perform 1 from public.tournament_categories c where c.id = any (v_categories) order by c.id for update;

  foreach v_category_id in array v_categories loop
    v_count := v_count + app.sweep_category(v_category_id, p_now);
  end loop;

  for v_reg in
    update public.tournament_registrations r set reminded_at = p_now
    from public.tournament_categories c, public.tournaments t
    where c.id = r.category_id and t.id = c.tournament_id
      and r.category_id = any (v_categories)
      and r.status in ('pending_partner', 'waitlisted') and not r.partner_confirmed and r.reminded_at is null
      and app.tournament_deadline(t) > p_now and app.tournament_deadline(t) <= p_now + interval '24 hours'
    returning r.*
  loop
    perform app.notify(v_reg.user_id, 'tournament_deadline_reminder', 'tournaments', app.registration_note(v_reg), p_now);
  end loop;

  return v_count;
end $$;

-- The reminders job also expires tournament entries (scheduling by the same
-- name replaces the command; the three existing calls stay).
do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron;
    execute $job$
      select cron.schedule(
        'actra-send-reminders',
        '*/10 * * * *',
        'select app.send_reminders(now()), app.complete_games(now()), app.expire_game_requests(now()), app.expire_tournament_entries(now())')
    $job$;
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- Lists, finding a partner, last seen
-- ---------------------------------------------------------------------------

-- Active tournaments in the city ending today (city time) or later, and on
-- or after p_from when given. 'date': by first day; 'az': by title in the
-- caller's language (falling back to Russian, then English, then Uzbek).
create function app.list_tournaments(
  p_user uuid, p_city_id text, p_sport_id text, p_from date, p_sort text, p_now timestamptz)
returns setof jsonb
language plpgsql
set search_path = ''
as $$
declare
  v_sort text := coalesce(p_sort, 'date');
  v_language text := (select p.language from public.profiles p where p.id = p_user);
begin
  if v_sort not in ('date', 'az') then raise exception 'invalid_argument'; end if;
  return query
    select app.tournament_json(t, p_user, p_now)
    from public.tournaments t
    join public.cities ci on ci.id = t.city_id
    where t.active
      and t.city_id = p_city_id
      and (p_sport_id is null or t.sport_id = p_sport_id)
      and t.ends_on >= app.to_local(p_now, ci.utc_offset_minutes)::date
      and (p_from is null or t.ends_on >= p_from)
    order by
      case when v_sort = 'date' then t.starts_on end,
      case when v_sort = 'az' then lower(coalesce(
        case v_language when 'uz' then t.title_uz when 'en' then t.title_en else t.title_ru end,
        t.title_ru, t.title_en, t.title_uz)) end,
      t.starts_on, t.id;
end $$;

-- One active tournament for the player, or null. Its expired offers and
-- invites are settled first (app.sweep_category), so an offer past its time
-- never shows as claimable. Only categories with something expired are
-- locked, all of them in id order before any is swept (as the job does), so
-- a plain read takes no lock and the lock order stays category, then
-- registration, then tournament.
create function app.get_tournament(p_user uuid, p_tournament_id uuid, p_now timestamptz) returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  v_categories uuid[];
  v_category_id uuid;
  v_tournament public.tournaments;
begin
  if not exists (select 1 from public.tournaments t where t.id = p_tournament_id and t.active) then return null; end if;
  select array_agg(x.id order by x.id) into v_categories
  from (
    select distinct r.category_id as id
    from public.tournament_registrations r
    join public.tournament_categories c on c.id = r.category_id
    where c.tournament_id = p_tournament_id
      and ((r.status in ('pending_partner', 'waitlisted') and not r.partner_confirmed and r.partner_expires_at <= p_now)
           or (r.status = 'offered' and r.offer_expires_at <= p_now))
  ) x;
  if v_categories is not null then
    perform 1 from public.tournament_categories c where c.id = any (v_categories) order by c.id for update;
    foreach v_category_id in array v_categories loop
      perform app.sweep_category(v_category_id, p_now);
    end loop;
  end if;

  select t.* into v_tournament from public.tournaments t where t.id = p_tournament_id and t.active;
  if not found then return null; end if;
  return app.tournament_json(v_tournament, p_user, p_now);
end $$;

-- Every entry of mine (as registrant or partner, any state) in active
-- tournaments that have not ended, newest first, each with its tournament
-- (and whether registration is still open, which decides what the entry can
-- still do).
create function app.my_registrations(p_user uuid, p_now timestamptz) returns setof jsonb
language sql
set search_path = ''
as $$
  select app.registration_json(r) || jsonb_build_object('tournament', jsonb_build_object(
    'id', t.id, 'city_id', t.city_id, 'sport_id', t.sport_id, 'venue_id', t.venue_id,
    'title_uz', t.title_uz, 'title_ru', t.title_ru, 'title_en', t.title_en,
    'starts_on', t.starts_on, 'ends_on', t.ends_on, 'color_seed', t.color_seed, 'cover_url', t.cover_url,
    'registration_open', t.active and p_now < app.tournament_deadline(t)))
  from public.tournament_registrations r
  join public.tournament_categories c on c.id = r.category_id
  join public.tournaments t on t.id = c.tournament_id
  where p_user is not null
    and t.active
    and (r.user_id = p_user or r.partner_id = p_user)
    and t.ends_on >= app.to_local(p_now, app.tournament_offset(t))::date
  order by r.created_at desc, r.id desc
$$;

-- Whether an account has this exact phone number: {id, name} or null; never
-- the phone. At most 20 calls per caller in any rolling hour, hits and misses
-- alike. The caller's profile row lock makes simultaneous calls take turns;
-- `for no key update`, so rows that reference the profile (bookings, games,
-- registrations) are not blocked by it. Stored phones are E.164, so a number
-- typed with digits only gets its leading `+`.
create function app.find_player_by_phone(p_user uuid, p_phone text, p_now timestamptz) returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  c_limit constant integer := 20;
  v_phone text := app.normalize_phone(p_phone);
begin
  if p_user is null then raise exception 'not_authenticated'; end if;
  if v_phone ~ '^[0-9]+$' then v_phone := '+' || v_phone; end if;
  perform 1 from public.profiles p where p.id = p_user for no key update;
  if not found then raise exception 'not_authenticated'; end if;
  if (select count(*) from public.phone_lookups l
      where l.user_id = p_user and l.at > p_now - interval '1 hour') >= c_limit then
    raise exception 'rate_limited';
  end if;
  -- Older calls no longer count: keep the table small.
  delete from public.phone_lookups l where l.user_id = p_user and l.at <= p_now - interval '1 hour';
  insert into public.phone_lookups (user_id, at) values (p_user, p_now);

  if v_phone is null or v_phone !~ '^\+[0-9]{7,15}$' then return null; end if;
  return (
    select jsonb_build_object('id', p.id, 'name', p.full_name)
    from public.profile_contacts pc
    join public.profiles p on p.id = pc.user_id
    where pc.phone = v_phone);
end $$;

-- At most one write an hour per player.
create function app.touch_last_seen(p_user uuid, p_now timestamptz) returns void
language sql
set search_path = ''
as $$
  update public.profiles p set last_seen_at = p_now
  where p.id = p_user and (p.last_seen_at is null or p.last_seen_at < p_now - interval '1 hour')
$$;

-- ---------------------------------------------------------------------------
-- Settings: set_settings, redefined from 20261124100000_community_core.sql
-- with the new category. Same signature, so its grants stay.
-- ---------------------------------------------------------------------------

create or replace function public.set_settings(p_muted text[], p_hidden boolean) returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  v_user uuid := (select auth.uid());
begin
  if v_user is null then raise exception 'not_authenticated'; end if;
  if exists (
    select 1 from unnest(coalesce(p_muted, '{}')) m
    where m is null or m not in ('bookings', 'venue', 'games', 'requests', 'invites', 'tournaments')) then
    raise exception 'invalid_argument';
  end if;
  update public.profiles p
  set muted_categories = case when p_muted is null then p.muted_categories
        else coalesce((select array_agg(distinct m order by m) from unnest(p_muted) m), '{}') end,
      hidden_from_search = coalesce(p_hidden, p.hidden_from_search)
  where p.id = v_user;
end $$;

-- ---------------------------------------------------------------------------
-- What the app calls. The registration calls return the entry.
-- ---------------------------------------------------------------------------

create function public.list_tournaments(
  p_city_id text, p_sport_id text default null, p_from date default null, p_sort text default 'date')
returns setof jsonb
language sql security definer
set search_path = ''
as $$ select app.list_tournaments((select auth.uid()), p_city_id, p_sport_id, p_from, p_sort, now()) $$;

-- null when there is no such active tournament. Volatile (it may settle
-- expired entries), so the API runs it in a read-write transaction.
create function public.get_tournament(p_tournament_id uuid) returns jsonb
language sql security definer
set search_path = ''
as $$ select app.get_tournament((select auth.uid()), p_tournament_id, now()) $$;

create function public.register_tournament(p_category_id uuid, p_partner_id uuid default null) returns jsonb
language sql security definer
set search_path = ''
as $$ select app.registration_json(app.register((select auth.uid()), p_category_id, p_partner_id, now())) $$;

create function public.respond_partner(p_registration_id uuid, p_accept boolean) returns jsonb
language sql security definer
set search_path = ''
as $$ select app.registration_json(app.respond_partner((select auth.uid()), p_registration_id, p_accept, now())) $$;

create function public.cancel_registration(p_registration_id uuid) returns jsonb
language sql security definer
set search_path = ''
as $$ select app.registration_json(app.cancel_registration((select auth.uid()), p_registration_id, now())) $$;

create function public.join_waitlist(p_category_id uuid, p_partner_id uuid default null) returns jsonb
language sql security definer
set search_path = ''
as $$ select app.registration_json(app.join_waitlist((select auth.uid()), p_category_id, p_partner_id, now())) $$;

create function public.claim_offer(p_registration_id uuid) returns jsonb
language sql security definer
set search_path = ''
as $$ select app.registration_json(app.claim_offer((select auth.uid()), p_registration_id, now())) $$;

create function public.my_registrations() returns setof jsonb
language sql security definer
set search_path = ''
as $$ select app.my_registrations((select auth.uid()), now()) $$;

create function public.find_player_by_phone(p_phone text) returns jsonb
language sql security definer
set search_path = ''
as $$ select app.find_player_by_phone((select auth.uid()), p_phone, now()) $$;

create function public.touch_last_seen() returns void
language sql security definer
set search_path = ''
as $$ select app.touch_last_seen((select auth.uid()), now()) $$;

revoke all on function
  public.list_tournaments(text, text, date, text),
  public.get_tournament(uuid),
  public.register_tournament(uuid, uuid),
  public.respond_partner(uuid, boolean),
  public.cancel_registration(uuid),
  public.join_waitlist(uuid, uuid),
  public.claim_offer(uuid),
  public.my_registrations(),
  public.find_player_by_phone(text),
  public.touch_last_seen()
from public, anon, authenticated;

grant execute on function
  public.list_tournaments(text, text, date, text),
  public.get_tournament(uuid),
  public.register_tournament(uuid, uuid),
  public.respond_partner(uuid, boolean),
  public.cancel_registration(uuid),
  public.join_waitlist(uuid, uuid),
  public.claim_offer(uuid),
  public.my_registrations(),
  public.find_player_by_phone(text),
  public.touch_last_seen()
to authenticated, service_role;
