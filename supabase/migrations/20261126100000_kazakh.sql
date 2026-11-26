-- Kazakh (kk, Cyrillic) as a fourth content language.
--
-- Additive: new nullable text columns, widened checks, and create or replace
-- of every function that lists the languages, with signatures, search_path,
-- security and grants unchanged and only a 'kk' key added next to 'en'.
-- Admin-entered text falls back: chosen language, then Russian, English,
-- Uzbek, and Kazakh last.

-- ---------------------------------------------------------------------------
-- Columns
-- ---------------------------------------------------------------------------

alter table public.cities add column name_kk text;
alter table public.sports add column name_kk text;
alter table public.venues
  add column name_kk text,
  add column description_kk text,
  add column address_kk text,
  add column district_kk text;
alter table public.courts add column name_kk text;
alter table public.banners
  add column title_kk text,
  add column subtitle_kk text;
alter table public.tournaments
  add column title_kk text,
  add column description_kk text;
alter table public.tournament_categories add column name_kk text;

-- A row needs a name in at least one language; Kazakh counts.
alter table public.venues drop constraint venues_named;
alter table public.venues add constraint venues_named check (coalesce(name_uz, name_ru, name_en, name_kk) is not null);
alter table public.courts drop constraint courts_named;
alter table public.courts add constraint courts_named check (coalesce(name_uz, name_ru, name_en, name_kk) is not null);
alter table public.tournament_categories drop constraint tournament_categories_named;
alter table public.tournament_categories add constraint tournament_categories_named
  check (coalesce(name_uz, name_ru, name_en, name_kk) is not null);

-- ---------------------------------------------------------------------------
-- Language
-- ---------------------------------------------------------------------------

alter table public.profiles drop constraint profiles_language_check;
alter table public.profiles add constraint profiles_language_check check (language in ('uz', 'ru', 'kk', 'en'));
alter table public.login_tokens drop constraint login_tokens_language_check;
alter table public.login_tokens add constraint login_tokens_language_check check (language in ('uz', 'ru', 'kk', 'en'));

-- ---------------------------------------------------------------------------
-- Kazakh names of the catalog rows that already exist
-- ---------------------------------------------------------------------------

update public.cities set name_kk = case id
  when 'tashkent' then 'Ташкент' when 'almaty' then 'Алматы' when 'astana' then 'Астана' end
where id in ('tashkent', 'almaty', 'astana');

update public.sports set name_kk = case id
  when 'football' then 'Футбол' when 'padel' then 'Падел' when 'tennis' then 'Теннис'
  when 'basketball' then 'Баскетбол' when 'volleyball' then 'Волейбол'
  when 'running' then 'Жүгіру' when 'gym' then 'Жаттығу залы' end
where id in ('football', 'padel', 'tennis', 'basketball', 'volleyball', 'running', 'gym');

-- ---------------------------------------------------------------------------
-- app.venue_name (from 20261124100000_community_core.sql)
-- ---------------------------------------------------------------------------

create or replace function app.venue_name(p_venue_id uuid) returns jsonb
language sql stable
set search_path = ''
as $$
  select jsonb_build_object('uz', v.name_uz, 'ru', v.name_ru, 'kk', v.name_kk, 'en', v.name_en)
  from public.venues v where v.id = p_venue_id
$$;

-- ---------------------------------------------------------------------------
-- app.notify_owners (from 20261124100000_community_core.sql)
-- ---------------------------------------------------------------------------

create or replace function app.notify_owners(p_booking public.bookings, p_kind text, p_now timestamptz) returns void
language plpgsql
set search_path = ''
as $$
declare
  v_payload jsonb;
  v_owner uuid;
begin
  v_payload := app.booking_note(p_booking) - 'venue_name' || jsonb_build_object(
    'venue_id', p_booking.venue_id,
    'court_name', (select jsonb_build_object('uz', c.name_uz, 'ru', c.name_ru, 'kk', c.name_kk, 'en', c.name_en) from public.courts c where c.id = p_booking.court_id),
    'actor_name', (select p.full_name from public.profiles p where p.id = p_booking.user_id));
  for v_owner in select o.user_id from public.venue_owners o where o.venue_id = p_booking.venue_id loop
    perform app.notify(v_owner, p_kind, 'venue', v_payload, p_now);
  end loop;
end $$;

-- ---------------------------------------------------------------------------
-- app.registration_note (from 20261125100000_tournaments.sql)
-- ---------------------------------------------------------------------------

create or replace function app.registration_note(r public.tournament_registrations) returns jsonb
language sql stable
set search_path = ''
as $$
  select jsonb_build_object(
    'registration_id', r.id,
    'tournament_id', t.id,
    'category_id', c.id,
    'title', jsonb_build_object('uz', t.title_uz, 'ru', t.title_ru, 'kk', t.title_kk, 'en', t.title_en),
    'category_name', jsonb_build_object('uz', c.name_uz, 'ru', c.name_ru, 'kk', c.name_kk, 'en', c.name_en))
  from public.tournament_categories c
  join public.tournaments t on t.id = c.tournament_id
  where c.id = r.category_id
$$;

-- ---------------------------------------------------------------------------
-- app.registration_json (from 20261125100000_tournaments.sql)
-- ---------------------------------------------------------------------------

create or replace function app.registration_json(r public.tournament_registrations) returns jsonb
language sql
set search_path = ''
as $$
  select jsonb_build_object(
    'id', r.id,
    'tournament_id', c.tournament_id,
    'category_id', r.category_id,
    'category_name', jsonb_build_object('uz', c.name_uz, 'ru', c.name_ru, 'kk', c.name_kk, 'en', c.name_en),
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

-- ---------------------------------------------------------------------------
-- app.category_json (from 20261125100000_tournaments.sql)
-- ---------------------------------------------------------------------------

create or replace function app.category_json(c public.tournament_categories, p_user uuid) returns jsonb
language sql
set search_path = ''
as $$
  select jsonb_build_object(
    'id', c.id,
    'tournament_id', c.tournament_id,
    'name_uz', c.name_uz,
    'name_ru', c.name_ru,
    'name_kk', c.name_kk,
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

-- ---------------------------------------------------------------------------
-- app.tournament_json (from 20261125100000_tournaments.sql)
-- ---------------------------------------------------------------------------

create or replace function app.tournament_json(t public.tournaments, p_user uuid, p_now timestamptz) returns jsonb
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
    'title_kk', t.title_kk,
    'title_en', t.title_en,
    'description_uz', t.description_uz,
    'description_ru', t.description_ru,
    'description_kk', t.description_kk,
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
-- app.list_tournaments (from 20261125100000_tournaments.sql)
-- ---------------------------------------------------------------------------

create or replace function app.list_tournaments(
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
        case v_language when 'uz' then t.title_uz when 'kk' then t.title_kk when 'en' then t.title_en else t.title_ru end,
        t.title_ru, t.title_en, t.title_uz, t.title_kk)) end,
      t.starts_on, t.id;
end $$;

-- ---------------------------------------------------------------------------
-- app.my_registrations (from 20261125100000_tournaments.sql)
-- ---------------------------------------------------------------------------

create or replace function app.my_registrations(p_user uuid, p_now timestamptz) returns setof jsonb
language sql
set search_path = ''
as $$
  select app.registration_json(r) || jsonb_build_object('tournament', jsonb_build_object(
    'id', t.id, 'city_id', t.city_id, 'sport_id', t.sport_id, 'venue_id', t.venue_id,
    'title_uz', t.title_uz, 'title_ru', t.title_ru, 'title_kk', t.title_kk, 'title_en', t.title_en,
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

-- ---------------------------------------------------------------------------
-- app.admin_save_venue (from 20261123120000_admin.sql)
-- ---------------------------------------------------------------------------

create or replace function app.admin_save_venue(p_user uuid, p_venue jsonb, p_now timestamptz) returns uuid
language plpgsql
set search_path = ''
as $$
declare
  c_spec constant jsonb := '{
    "id": "uuid", "city_id": "string",
    "name_uz": "text", "name_ru": "text", "name_kk": "text", "name_en": "text",
    "description_uz": "long_text", "description_ru": "long_text", "description_kk": "long_text", "description_en": "long_text",
    "address_uz": "text", "address_ru": "text", "address_kk": "text", "address_en": "text",
    "district_uz": "text", "district_ru": "text", "district_kk": "text", "district_en": "text",
    "phone": "phone", "amenities": "strings", "active": "bool"}';
  c_amenities constant text[] := array['parking', 'showers', 'lighting', 'cafe', 'rental'];
  v_patch jsonb;
  v_creating boolean;
  v_row public.venues;
  v_before public.venues;
  v_amenities text[];
begin
  perform app.require_admin(p_user);
  v_patch := app.clean_payload(p_venue, c_spec);
  v_creating := not (v_patch ? 'id');

  if v_creating then
    if not (v_patch ? 'city_id') then raise exception 'invalid_argument'; end if;
    v_row.id := gen_random_uuid();
    v_row.phone := '';
    v_row.amenities := '{}';
    v_row.color_seed := abs(hashtext(v_row.id::text)) % 1000;
    v_row.active := true;
    v_row.created_at := p_now;
  else
    select v.* into v_row from public.venues v where v.id = (v_patch ->> 'id')::uuid for update;
    if not found then raise exception 'not_found'; end if;
    v_before := v_row;
  end if;

  if v_patch ? 'amenities' then
    select coalesce(array_agg(distinct a order by a), '{}') into v_amenities
    from jsonb_array_elements_text(v_patch -> 'amenities') a;
    if not (v_amenities <@ c_amenities) then raise exception 'invalid_argument'; end if;
    v_row.amenities := v_amenities;
  end if;
  v_row := jsonb_populate_record(v_row, v_patch - 'id' - 'amenities');

  if not exists (select 1 from public.cities ci where ci.id = v_row.city_id) then raise exception 'invalid_argument'; end if;
  if coalesce(v_row.name_uz, v_row.name_ru, v_row.name_en, v_row.name_kk) is null then raise exception 'invalid_argument'; end if;

  if v_creating then
    insert into public.venues select (v_row).*;
    insert into public.working_hours (venue_id, weekday, open_minute, close_minute)
    select v_row.id, d, 480, 1320 from generate_series(1, 7) d;
  else
    update public.venues v set
      city_id = v_row.city_id,
      name_uz = v_row.name_uz, name_ru = v_row.name_ru, name_kk = v_row.name_kk, name_en = v_row.name_en,
      description_uz = v_row.description_uz, description_ru = v_row.description_ru, description_kk = v_row.description_kk, description_en = v_row.description_en,
      address_uz = v_row.address_uz, address_ru = v_row.address_ru, address_kk = v_row.address_kk, address_en = v_row.address_en,
      district_uz = v_row.district_uz, district_ru = v_row.district_ru, district_kk = v_row.district_kk, district_en = v_row.district_en,
      phone = v_row.phone, amenities = v_row.amenities, active = v_row.active
    where v.id = v_row.id
    returning * into v_row;
  end if;

  perform app.audit(p_user, case when v_creating then 'create_venue' else 'update_venue' end, 'venue', v_row.id::text,
    case when v_creating then null else to_jsonb(v_before) end, to_jsonb(v_row), p_now);
  return v_row.id;
end $$;

-- ---------------------------------------------------------------------------
-- app.admin_save_court (from 20261123120000_admin.sql)
-- ---------------------------------------------------------------------------

create or replace function app.admin_save_court(p_user uuid, p_court jsonb, p_now timestamptz) returns uuid
language plpgsql
set search_path = ''
as $$
declare
  c_spec constant jsonb := '{
    "id": "uuid", "venue_id": "uuid", "sport_id": "string",
    "name_uz": "text", "name_ru": "text", "name_kk": "text", "name_en": "text",
    "slot_minutes": "int", "base_price": "int", "indoor": "bool", "active": "bool"}';
  v_patch jsonb;
  v_creating boolean;
  v_row public.courts;
  v_before public.courts;
begin
  perform app.require_admin(p_user);
  v_patch := app.clean_payload(p_court, c_spec);
  v_creating := not (v_patch ? 'id');

  if v_creating then
    if not (v_patch ?& array['venue_id', 'sport_id', 'slot_minutes', 'base_price']) then
      raise exception 'invalid_argument';
    end if;
    if not exists (select 1 from public.venues v where v.id = (v_patch ->> 'venue_id')::uuid) then
      raise exception 'invalid_argument';
    end if;
    v_row.id := gen_random_uuid();
    v_row.indoor := false;
    v_row.active := true;
    select coalesce(max(c.sort_order) + 1, 0) into v_row.sort_order
    from public.courts c where c.venue_id = (v_patch ->> 'venue_id')::uuid;
  else
    select c.* into v_row from public.courts c where c.id = (v_patch ->> 'id')::uuid for update;
    if not found then raise exception 'not_found'; end if;
    v_before := v_row;
    if v_patch ? 'venue_id' and (v_patch ->> 'venue_id')::uuid <> v_row.venue_id then
      raise exception 'invalid_argument';
    end if;
  end if;
  v_row := jsonb_populate_record(v_row, v_patch - 'id');

  if not exists (select 1 from public.sports s where s.id = v_row.sport_id) then raise exception 'invalid_argument'; end if;
  if v_row.slot_minutes not in (60, 90, 120) then raise exception 'invalid_argument'; end if;
  if v_row.base_price < 0 or v_row.base_price > 50000000 then raise exception 'invalid_argument'; end if;
  if coalesce(v_row.name_uz, v_row.name_ru, v_row.name_en, v_row.name_kk) is null then raise exception 'invalid_argument'; end if;

  if v_creating then
    insert into public.courts select (v_row).*;
  else
    update public.courts c set
      sport_id = v_row.sport_id,
      name_uz = v_row.name_uz, name_ru = v_row.name_ru, name_kk = v_row.name_kk, name_en = v_row.name_en,
      slot_minutes = v_row.slot_minutes, base_price = v_row.base_price,
      indoor = v_row.indoor, active = v_row.active
    where c.id = v_row.id
    returning * into v_row;
  end if;

  perform app.audit(p_user, case when v_creating then 'create_court' else 'update_court' end, 'court', v_row.id::text,
    case when v_creating then null else to_jsonb(v_before) end, to_jsonb(v_row), p_now);
  return v_row.id;
end $$;

-- ---------------------------------------------------------------------------
-- app.admin_duplicate_court (from 20261123120000_admin.sql)
-- ---------------------------------------------------------------------------

create or replace function app.admin_duplicate_court(p_user uuid, p_court_id uuid, p_now timestamptz) returns uuid
language plpgsql
set search_path = ''
as $$
declare
  v_original public.courts;
  v_copy public.courts;
begin
  perform app.require_admin(p_user);
  select c.* into v_original from public.courts c where c.id = p_court_id for update;
  if not found then raise exception 'not_found'; end if;

  update public.courts c set sort_order = c.sort_order + 1
  where c.venue_id = v_original.venue_id and c.sort_order > v_original.sort_order;

  v_copy := v_original;
  v_copy.id := gen_random_uuid();
  v_copy.name_uz := v_original.name_uz || ' 2';
  v_copy.name_ru := v_original.name_ru || ' 2';
  v_copy.name_kk := v_original.name_kk || ' 2';
  v_copy.name_en := v_original.name_en || ' 2';
  v_copy.sort_order := v_original.sort_order + 1;
  insert into public.courts select (v_copy).*;

  insert into public.price_rules (court_id, weekdays, from_minute, to_minute, price, sort_order)
  select v_copy.id, r.weekdays, r.from_minute, r.to_minute, r.price, r.sort_order
  from public.price_rules r where r.court_id = p_court_id;

  insert into public.working_hours (court_id, weekday, closed, open_minute, close_minute)
  select v_copy.id, h.weekday, h.closed, h.open_minute, h.close_minute
  from public.working_hours h where h.court_id = p_court_id;

  perform app.audit(p_user, 'duplicate_court', 'court', v_copy.id::text, null,
    to_jsonb(v_copy) || jsonb_build_object('copied_from', p_court_id), p_now);
  return v_copy.id;
end $$;

-- ---------------------------------------------------------------------------
-- app.admin_save_sport (from 20261123120000_admin.sql)
-- ---------------------------------------------------------------------------

create or replace function app.admin_save_sport(p_user uuid, p_sport jsonb, p_create boolean, p_now timestamptz) returns text
language plpgsql
set search_path = ''
as $$
declare
  c_spec constant jsonb := '{
    "id": "string", "name_uz": "text", "name_ru": "text", "name_kk": "text", "name_en": "text", "icon_key": "string",
    "bookable": "bool", "competitive_rating": "bool", "default_players": "int", "sort_order": "int", "active": "bool"}';
  v_patch jsonb;
  v_row public.sports;
  v_before public.sports;
begin
  perform app.require_admin(p_user);
  v_patch := app.clean_payload(p_sport, c_spec);
  if p_create is null or not (v_patch ? 'id') or (v_patch ->> 'id') !~ '^[a-z][a-z0-9_]{1,29}$' then
    raise exception 'invalid_argument';
  end if;

  if p_create then
    if not (v_patch ? 'icon_key') then raise exception 'invalid_argument'; end if;
    v_row.bookable := true;
    v_row.competitive_rating := false;
    v_row.default_players := 2;
    v_row.sort_order := 0;
    v_row.active := true;
  else
    select s.* into v_row from public.sports s where s.id = v_patch ->> 'id' for update;
    if not found then raise exception 'not_found'; end if;
    v_before := v_row;
  end if;
  v_row := jsonb_populate_record(v_row, v_patch);

  if v_row.default_players <= 0 or v_row.default_players > 100 then raise exception 'invalid_argument'; end if;
  if coalesce(v_row.name_uz, v_row.name_ru, v_row.name_en, v_row.name_kk) is null then raise exception 'invalid_argument'; end if;

  if p_create then
    if exists (select 1 from public.sports s where s.id = v_row.id) then raise exception 'already_exists'; end if;
    insert into public.sports select (v_row).*;
  else
    update public.sports s set
      name_uz = v_row.name_uz, name_ru = v_row.name_ru, name_kk = v_row.name_kk, name_en = v_row.name_en,
      icon_key = v_row.icon_key, bookable = v_row.bookable, competitive_rating = v_row.competitive_rating,
      default_players = v_row.default_players, sort_order = v_row.sort_order, active = v_row.active
    where s.id = v_row.id
    returning * into v_row;
  end if;

  perform app.audit(p_user, case when p_create then 'create_sport' else 'update_sport' end, 'sport', v_row.id,
    case when p_create then null else to_jsonb(v_before) end, to_jsonb(v_row), p_now);
  return v_row.id;
end $$;

-- ---------------------------------------------------------------------------
-- app.admin_save_banner (from 20261123120000_admin.sql)
-- ---------------------------------------------------------------------------

create or replace function app.admin_save_banner(p_user uuid, p_banner jsonb, p_now timestamptz) returns uuid
language plpgsql
set search_path = ''
as $$
declare
  c_spec constant jsonb := '{
    "id": "uuid", "city_id": "text",
    "title_uz": "text", "title_ru": "text", "title_kk": "text", "title_en": "text",
    "subtitle_uz": "text", "subtitle_ru": "text", "subtitle_kk": "text", "subtitle_en": "text",
    "url": "string", "sort_order": "int", "active": "bool"}';
  v_patch jsonb;
  v_creating boolean;
  v_row public.banners;
  v_before public.banners;
begin
  perform app.require_admin(p_user);
  v_patch := app.clean_payload(p_banner, c_spec);
  v_creating := not (v_patch ? 'id');

  if v_creating then
    v_row.id := gen_random_uuid();
    v_row.color_seed := abs(hashtext(v_row.id::text)) % 1000;
    v_row.sort_order := 0;
    v_row.active := true;
  else
    select b.* into v_row from public.banners b where b.id = (v_patch ->> 'id')::uuid for update;
    if not found then raise exception 'not_found'; end if;
    v_before := v_row;
  end if;
  v_row := jsonb_populate_record(v_row, v_patch - 'id');

  if v_row.url is null or v_row.url !~ '^https://[^[:space:]]+$' then raise exception 'invalid_argument'; end if;
  if v_row.city_id is not null and not exists (select 1 from public.cities ci where ci.id = v_row.city_id) then
    raise exception 'invalid_argument';
  end if;
  if coalesce(v_row.title_uz, v_row.title_ru, v_row.title_en, v_row.title_kk) is null then raise exception 'invalid_argument'; end if;

  if v_creating then
    insert into public.banners select (v_row).*;
  else
    update public.banners b set
      city_id = v_row.city_id,
      title_uz = v_row.title_uz, title_ru = v_row.title_ru, title_kk = v_row.title_kk, title_en = v_row.title_en,
      subtitle_uz = v_row.subtitle_uz, subtitle_ru = v_row.subtitle_ru, subtitle_kk = v_row.subtitle_kk, subtitle_en = v_row.subtitle_en,
      url = v_row.url, sort_order = v_row.sort_order, active = v_row.active
    where b.id = v_row.id
    returning * into v_row;
  end if;

  perform app.audit(p_user, case when v_creating then 'create_banner' else 'update_banner' end, 'banner', v_row.id::text,
    case when v_creating then null else to_jsonb(v_before) end, to_jsonb(v_row), p_now);
  return v_row.id;
end $$;

-- ---------------------------------------------------------------------------
-- app.category_spec (from 20261125110000_admin_tournaments.sql)
-- ---------------------------------------------------------------------------

create or replace function app.category_spec() returns jsonb
language sql immutable
set search_path = ''
as $$
  select '{
    "id": "uuid", "tournament_id": "uuid",
    "name_uz": "text", "name_ru": "text", "name_kk": "text", "name_en": "text",
    "kind": "string", "gender": "string", "min_level": "int", "max_level": "int",
    "fee": "int", "cap": "int", "waitlist_enabled": "bool", "sort_order": "int"}'::jsonb
$$;

-- ---------------------------------------------------------------------------
-- app.apply_category (from 20261125110000_admin_tournaments.sql)
-- ---------------------------------------------------------------------------

create or replace function app.apply_category(p_row public.tournament_categories, p_patch jsonb)
returns public.tournament_categories
language plpgsql
set search_path = ''
as $$
declare
  v public.tournament_categories := jsonb_populate_record(p_row, p_patch - 'id' - 'tournament_id');
begin
  if not coalesce(v.kind in ('singles', 'pairs'), false)
     or not coalesce(v.gender in ('men', 'women', 'mixed', 'open'), false)
     or not coalesce(v.min_level between 1 and 5 and v.max_level between 1 and 5 and v.min_level <= v.max_level, false)
     or not coalesce(v.fee between 0 and 50000000, false)
     or not coalesce(v.cap between 1 and 512, false)
     or v.waitlist_enabled is null or v.sort_order is null
     or coalesce(v.name_uz, v.name_ru, v.name_en, v.name_kk) is null then
    raise exception 'invalid_argument';
  end if;
  return v;
end $$;

-- ---------------------------------------------------------------------------
-- app.admin_save_tournament (from 20261125110000_admin_tournaments.sql)
-- ---------------------------------------------------------------------------

create or replace function app.admin_save_tournament(p_user uuid, p_tournament jsonb, p_now timestamptz) returns uuid
language plpgsql
set search_path = ''
as $$
declare
  c_spec constant jsonb := '{
    "id": "uuid", "city_id": "string", "sport_id": "string", "venue_id": "text",
    "title_uz": "text", "title_ru": "text", "title_kk": "text", "title_en": "text",
    "description_uz": "long_text", "description_ru": "long_text", "description_kk": "long_text", "description_en": "long_text",
    "starts_on": "string", "ends_on": "string", "registration_deadline_local": "text",
    "cover_url": "long_text", "color_seed": "int", "active": "bool"}';
  v_categories jsonb := p_tournament -> 'categories';
  v_patch jsonb;
  v_creating boolean;
  v_row public.tournaments;
  v_before public.tournaments;
  v_offset integer;
  v_deadline_local timestamp;
  v_category public.tournament_categories;
  v_item jsonb;
  v_index integer := 0;
  v_after jsonb;
begin
  perform app.require_admin(p_user);
  v_patch := app.clean_payload(p_tournament - 'categories', c_spec);
  v_creating := not (v_patch ? 'id');

  if v_creating then
    if not (v_patch ?& array['city_id', 'sport_id', 'starts_on', 'ends_on']) then raise exception 'invalid_argument'; end if;
    if v_categories is not null
       and (jsonb_typeof(v_categories) <> 'array' or jsonb_array_length(v_categories) = 0) then
      raise exception 'invalid_argument';
    end if;
    v_row.id := gen_random_uuid();
    v_row.color_seed := abs(hashtext(v_row.id::text)) % 1000;
    v_row.active := true;
    v_row.min_fee := 0;
    v_row.max_fee := 0;
    v_row.slots_total := 0;
    v_row.slots_filled := 0;
  else
    if p_tournament ? 'categories' then raise exception 'invalid_argument'; end if;
    select t.* into v_row from public.tournaments t where t.id = (v_patch ->> 'id')::uuid for update;
    if not found then raise exception 'not_found'; end if;
    v_before := v_row;
    -- Kept as wall-clock time, so a city change keeps the local deadline.
    v_deadline_local := app.to_local(app.tournament_deadline(v_row), app.tournament_offset(v_row));
  end if;

  if v_patch ->> 'venue_id' is not null
     and (v_patch ->> 'venue_id') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    raise exception 'invalid_argument';
  end if;
  if v_patch ? 'starts_on' then perform app.admin_date(v_patch ->> 'starts_on'); end if;
  if v_patch ? 'ends_on' then perform app.admin_date(v_patch ->> 'ends_on'); end if;
  if v_patch ? 'registration_deadline_local' then
    v_deadline_local := case when v_patch ->> 'registration_deadline_local' is null then null
                             else app.admin_timestamp(v_patch ->> 'registration_deadline_local') end;
  end if;
  v_row := jsonb_populate_record(v_row, v_patch - 'id' - 'registration_deadline_local');

  select ci.utc_offset_minutes into v_offset from public.cities ci where ci.id = v_row.city_id;
  if not found then raise exception 'invalid_argument'; end if;
  if not exists (select 1 from public.sports s where s.id = v_row.sport_id) then raise exception 'invalid_argument'; end if;
  if v_row.venue_id is not null
     and not exists (select 1 from public.venues v where v.id = v_row.venue_id and v.city_id = v_row.city_id) then
    raise exception 'invalid_argument';
  end if;
  if coalesce(v_row.title_uz, v_row.title_ru, v_row.title_en, v_row.title_kk) is null then raise exception 'invalid_argument'; end if;
  if v_row.ends_on < v_row.starts_on then raise exception 'invalid_argument'; end if;
  if v_row.cover_url is not null and v_row.cover_url !~ '^https://[^[:space:]]+$' then raise exception 'invalid_argument'; end if;
  v_row.registration_deadline := app.to_instant(coalesce(v_deadline_local, v_row.starts_on::timestamp), v_offset);
  if v_row.registration_deadline > app.to_instant((v_row.ends_on + 1)::timestamp, v_offset) then
    raise exception 'invalid_argument';
  end if;

  if v_creating then
    insert into public.tournaments select (v_row).*;
    if v_categories is null then
      insert into public.tournament_categories (
        tournament_id, name_uz, name_ru, name_en, kind, gender, min_level, max_level, fee, cap, created_at)
      values (v_row.id, 'Ochiq', 'Открытая', 'Open', 'singles', 'open', 1, 5, 0, 16, p_now);
    else
      for v_item in select e from jsonb_array_elements(v_categories) e loop
        v_category := app.apply_category(
          app.new_category(v_row.id, v_index, p_now),
          app.clean_payload(v_item, app.category_spec() - 'id' - 'tournament_id'));
        insert into public.tournament_categories select (v_category).*;
        v_index := v_index + 1;
      end loop;
    end if;
    perform app.sync_tournament_summary(v_row.id);
    select t.* into v_row from public.tournaments t where t.id = v_row.id;
    v_after := to_jsonb(v_row) || jsonb_build_object('categories',
      (select jsonb_agg(to_jsonb(c) order by c.sort_order, c.created_at, c.id)
       from public.tournament_categories c where c.tournament_id = v_row.id));
  else
    -- Fees already taken are in the old city's currency.
    if v_row.city_id <> v_before.city_id and exists (
      select 1 from public.tournament_registrations r
      join public.tournament_categories c on c.id = r.category_id
      where c.tournament_id = v_row.id
        and r.status in ('pending_partner', 'registered', 'waitlisted', 'offered')) then
      raise exception 'has_registrations';
    end if;
    update public.tournaments t set
      city_id = v_row.city_id, sport_id = v_row.sport_id, venue_id = v_row.venue_id,
      title_uz = v_row.title_uz, title_ru = v_row.title_ru, title_kk = v_row.title_kk, title_en = v_row.title_en,
      description_uz = v_row.description_uz, description_ru = v_row.description_ru, description_kk = v_row.description_kk, description_en = v_row.description_en,
      starts_on = v_row.starts_on, ends_on = v_row.ends_on, registration_deadline = v_row.registration_deadline,
      cover_url = v_row.cover_url, color_seed = v_row.color_seed, active = v_row.active
    where t.id = v_row.id
    returning * into v_row;
    v_after := to_jsonb(v_row);
  end if;

  perform app.audit(p_user, case when v_creating then 'create_tournament' else 'update_tournament' end, 'tournament',
    v_row.id::text, case when v_creating then null else to_jsonb(v_before) end, v_after, p_now);
  return v_row.id;
end $$;

-- ---------------------------------------------------------------------------
-- app.admin_save_category (from 20261125110000_admin_tournaments.sql)
-- ---------------------------------------------------------------------------

create or replace function app.admin_save_category(p_user uuid, p_category jsonb, p_now timestamptz) returns uuid
language plpgsql
set search_path = ''
as $$
declare
  v_patch jsonb;
  v_creating boolean;
  v_row public.tournament_categories;
  v_before public.tournament_categories;
begin
  perform app.require_admin(p_user);
  v_patch := app.clean_payload(p_category, app.category_spec());
  v_creating := not (v_patch ? 'id');

  if v_creating then
    if not (v_patch ? 'tournament_id') then raise exception 'invalid_argument'; end if;
    -- The tournament row is locked before the insert. Otherwise two creates
    -- in one tournament each take the foreign key's share lock on it with
    -- the insert, then both wait for its update lock in
    -- sync_tournament_summary: a deadlock. Taking it first does not break
    -- the global order (category, registration, tournament): the new
    -- category does not exist yet, so nobody can hold its lock or wait on
    -- this one for it, and nothing else is locked here. It also makes
    -- concurrent creates take turns for sort_order.
    perform 1 from public.tournaments t where t.id = (v_patch ->> 'tournament_id')::uuid for update;
    if not found then raise exception 'invalid_argument'; end if;
    v_row := app.apply_category(
      app.new_category((v_patch ->> 'tournament_id')::uuid,
        (select coalesce(max(c.sort_order) + 1, 0) from public.tournament_categories c
         where c.tournament_id = (v_patch ->> 'tournament_id')::uuid),
        p_now),
      v_patch);
    insert into public.tournament_categories select (v_row).*;
  else
    select c.* into v_row from public.tournament_categories c where c.id = (v_patch ->> 'id')::uuid for update;
    if not found then raise exception 'not_found'; end if;
    v_before := v_row;
    if v_patch ? 'tournament_id' and (v_patch ->> 'tournament_id')::uuid <> v_row.tournament_id then
      raise exception 'invalid_argument';
    end if;
    perform app.sweep_category(v_row.id, p_now);
    v_row := app.apply_category(v_row, v_patch);
    if v_row.cap < app.category_counted(v_row.id) then raise exception 'invalid_argument'; end if;
    if v_row.kind <> v_before.kind and exists (
      select 1 from public.tournament_registrations r
      where r.category_id = v_row.id and r.status in ('pending_partner', 'registered', 'waitlisted', 'offered')) then
      raise exception 'has_registrations';
    end if;
    update public.tournament_categories c set
      name_uz = v_row.name_uz, name_ru = v_row.name_ru, name_kk = v_row.name_kk, name_en = v_row.name_en,
      kind = v_row.kind, gender = v_row.gender, min_level = v_row.min_level, max_level = v_row.max_level,
      fee = v_row.fee, cap = v_row.cap, waitlist_enabled = v_row.waitlist_enabled, sort_order = v_row.sort_order
    where c.id = v_row.id
    returning * into v_row;
    if v_row.cap > v_before.cap then perform app.offer_next(v_row.id, p_now); end if;
  end if;

  perform app.sync_tournament_summary(v_row.tournament_id);
  perform app.audit(p_user, case when v_creating then 'create_category' else 'update_category' end, 'tournament_category',
    v_row.id::text, case when v_creating then null else to_jsonb(v_before) end, to_jsonb(v_row), p_now);
  return v_row.id;
end $$;

-- ---------------------------------------------------------------------------
-- app.admin_move_registration (from 20261125110000_admin_tournaments.sql)
-- ---------------------------------------------------------------------------

create or replace function app.admin_move_registration(p_user uuid, p_registration_id uuid, p_category_id uuid, p_now timestamptz)
returns public.tournament_registrations
language plpgsql
set search_path = ''
as $$
declare
  v_source_id uuid;
  v_source public.tournament_categories;
  v_target public.tournament_categories;
  v_reg public.tournament_registrations;
  v_before public.tournament_registrations;
  v_note jsonb;
  v_partner uuid;
begin
  perform app.require_admin(p_user);
  loop
    select r.category_id into v_source_id from public.tournament_registrations r where r.id = p_registration_id;
    if not found then raise exception 'not_found'; end if;
    if not exists (select 1 from public.tournament_categories c where c.id = p_category_id) then raise exception 'not_found'; end if;
    perform 1 from public.tournament_categories c where c.id in (v_source_id, p_category_id) order by c.id for update;
    select r.* into v_reg from public.tournament_registrations r where r.id = p_registration_id for update;
    if not found then raise exception 'not_found'; end if;
    -- Moved by someone else meanwhile: lock its new category instead.
    exit when v_reg.category_id = v_source_id;
  end loop;
  select c.* into v_source from public.tournament_categories c where c.id = v_source_id;
  select c.* into v_target from public.tournament_categories c where c.id = p_category_id;

  if v_target.id = v_source.id or v_target.tournament_id <> v_source.tournament_id or v_target.kind <> v_source.kind
     or v_reg.status <> 'registered' then
    raise exception 'invalid_argument';
  end if;

  perform app.sweep_category(v_source.id, p_now);
  perform app.sweep_category(v_target.id, p_now);
  v_partner := case when v_reg.partner_confirmed then v_reg.partner_id end;
  if app.live_in_category(v_target.id, v_reg.user_id, v_reg.id) then raise exception 'already_registered'; end if;
  if v_partner is not null and app.live_in_category(v_target.id, v_partner, v_reg.id) then
    raise exception 'partner_unavailable';
  end if;
  if app.category_counted(v_target.id) >= v_target.cap then raise exception 'full'; end if;

  v_before := v_reg;
  begin
    update public.tournament_registrations r set category_id = v_target.id
    where r.id = v_reg.id returning * into v_reg;
  exception when unique_violation then
    raise exception 'already_registered';
  end;

  v_note := app.registration_note(v_reg) || jsonb_build_object('from_category_name',
    jsonb_build_object('uz', v_source.name_uz, 'ru', v_source.name_ru, 'kk', v_source.name_kk, 'en', v_source.name_en));
  perform app.notify(v_reg.user_id, 'tournament_moved', 'tournaments', v_note, p_now);
  perform app.notify(v_partner, 'tournament_moved', 'tournaments', v_note, p_now);
  perform app.offer_next(v_source.id, p_now);
  perform app.sync_tournament_summary(v_source.tournament_id);
  perform app.audit(p_user, 'move_registration', 'tournament_registration', v_reg.id::text,
    to_jsonb(v_before), to_jsonb(v_reg), p_now);
  return v_reg;
end $$;
