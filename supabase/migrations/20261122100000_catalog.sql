-- Catalog: what players browse. Readable by everyone, written only by the
-- service role until the owner and admin panels arrive (Milestone 3).
--
-- Admin-entered text has one column per language (_uz, _ru, _en); the app
-- falls back to Russian, then English (product spec §3).

create schema if not exists extensions;
create extension if not exists btree_gist with schema extensions;

create table public.cities (
  id text primary key,
  name_uz text,
  name_ru text,
  name_en text,
  country_code text not null,
  currency text not null check (currency in ('UZS', 'KZT')),
  -- Offset of local time from UTC. Data, never a constant in logic.
  utc_offset_minutes integer not null check (utc_offset_minutes between -720 and 840)
);

create table public.sports (
  id text primary key,
  name_uz text,
  name_ru text,
  name_en text,
  icon_key text not null,
  -- false for place-only sports (running, gym): no slots, no payment.
  bookable boolean not null default true,
  -- true for padel and tennis: 1.0-7.0 rating instead of level 1-5.
  competitive_rating boolean not null default false,
  default_players integer not null default 2 check (default_players > 0),
  sort_order integer not null default 0,
  active boolean not null default true
);

create table public.venues (
  id uuid primary key default gen_random_uuid(),
  city_id text not null references public.cities (id),
  name_uz text,
  name_ru text,
  name_en text,
  description_uz text,
  description_ru text,
  description_en text,
  address_uz text,
  address_ru text,
  address_en text,
  district_uz text,
  district_ru text,
  district_en text,
  phone text not null default '',
  amenities text[] not null default '{}',
  -- Picks the placeholder colour until venues have photos.
  color_seed integer not null default 0,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  constraint venues_named check (coalesce(name_uz, name_ru, name_en) is not null)
);
create index venues_city_idx on public.venues (city_id);

create table public.courts (
  id uuid primary key default gen_random_uuid(),
  venue_id uuid not null references public.venues (id) on delete cascade,
  sport_id text not null references public.sports (id),
  name_uz text,
  name_ru text,
  name_en text,
  slot_minutes integer not null check (slot_minutes in (60, 90, 120)),
  base_price integer not null check (base_price >= 0),
  indoor boolean not null default false,
  sort_order integer not null default 0,
  active boolean not null default true,
  constraint courts_named check (coalesce(name_uz, name_ru, name_en) is not null)
);
create index courts_venue_idx on public.courts (venue_id);

-- Hours per weekday (1 = Monday ... 7 = Sunday), in minutes from midnight.
-- A venue with no row for a weekday is closed that day. A court row replaces
-- the venue's hours for that weekday; closed = true shuts the court even if
-- the venue is open.
create table public.working_hours (
  id uuid primary key default gen_random_uuid(),
  venue_id uuid references public.venues (id) on delete cascade,
  court_id uuid references public.courts (id) on delete cascade,
  weekday integer not null check (weekday between 1 and 7),
  closed boolean not null default false,
  open_minute integer not null default 0 check (open_minute between 0 and 1440),
  close_minute integer not null default 0 check (close_minute between 0 and 1440),
  constraint working_hours_one_owner check ((venue_id is null) <> (court_id is null)),
  constraint working_hours_venue_day unique (venue_id, weekday),
  constraint working_hours_court_day unique (court_id, weekday)
);

-- "These days, this time range -> this price per slot" (product spec §11.4).
-- The first matching rule by sort_order wins; no match means base_price.
create table public.price_rules (
  id uuid primary key default gen_random_uuid(),
  court_id uuid not null references public.courts (id) on delete cascade,
  weekdays integer[] not null check (weekdays <@ array[1, 2, 3, 4, 5, 6, 7]),
  from_minute integer not null check (from_minute between 0 and 1440),
  -- Exclusive.
  to_minute integer not null check (to_minute between 0 and 1440),
  price integer not null check (price >= 0),
  sort_order integer not null default 0
);
create index price_rules_court_idx on public.price_rules (court_id, sort_order);

create table public.banners (
  id uuid primary key default gen_random_uuid(),
  -- null = shown in every city.
  city_id text references public.cities (id),
  title_uz text,
  title_ru text,
  title_en text,
  subtitle_uz text,
  subtitle_ru text,
  subtitle_en text,
  url text not null,
  color_seed integer not null default 0,
  sort_order integer not null default 0,
  active boolean not null default true
);

create table public.tournaments (
  id uuid primary key default gen_random_uuid(),
  city_id text not null references public.cities (id),
  sport_id text not null references public.sports (id),
  venue_id uuid references public.venues (id),
  title_uz text,
  title_ru text,
  title_en text,
  starts_on date not null,
  ends_on date not null,
  min_fee integer not null default 0,
  max_fee integer not null default 0,
  slots_total integer not null default 0,
  slots_filled integer not null default 0,
  active boolean not null default true,
  constraint tournaments_dates check (ends_on >= starts_on)
);

-- Access: read-only for the API roles. Privileges are spelled out instead of
-- relying on the project's default grants.
do $$
declare
  t text;
begin
  foreach t in array array['cities', 'sports', 'venues', 'courts', 'working_hours', 'price_rules', 'banners', 'tournaments']
  loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on table public.%I from anon, authenticated', t);
    execute format('grant select on table public.%I to anon, authenticated', t);
    execute format('grant all on table public.%I to service_role', t);
  end loop;
end $$;

create policy "cities are public" on public.cities for select to anon, authenticated using (true);
create policy "active sports are public" on public.sports for select to anon, authenticated using (active);
create policy "active venues are public" on public.venues for select to anon, authenticated using (active);
create policy "active courts are public" on public.courts for select to anon, authenticated using (active);
create policy "working hours are public" on public.working_hours for select to anon, authenticated using (true);
create policy "price rules are public" on public.price_rules for select to anon, authenticated using (true);
create policy "active banners are public" on public.banners for select to anon, authenticated using (active);
create policy "active tournaments are public" on public.tournaments for select to anon, authenticated using (active);
