-- Admin functions (product spec §4, §12; Milestone 3c): venues, courts,
-- owner assignment, sports, banners and the audit log reader.
--
-- Same conventions as owner.sql: rules in the private `app` schema taking the
-- acting user (and the time, for writes), thin `public` security-definer
-- wrappers at the end. Every function refuses anyone not in app_admins with
-- not_allowed before reading anything; every write adds one audit_log row.
-- Save payloads are checked key by key: an unknown key is refused, never
-- ignored, so a typo cannot silently drop a field.

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

create function app.require_admin(p_user uuid) returns void
language plpgsql stable
set search_path = ''
as $$
begin
  if p_user is null or not app.is_admin(p_user) then raise exception 'not_allowed'; end if;
end $$;

-- Checks a save payload against p_spec ({ key: kind }) and returns it
-- cleaned. Kinds:
--   text       string or null, trimmed, '' -> null, at most 200 characters
--   long_text  the same, at most 2000
--   phone      the same, but null -> '' (the column is not null)
--   string     non-empty string, trimmed, at most 200
--   bool       true or false
--   int        a whole number
--   uuid       a uuid string
--   strings    an array of strings
-- Anything else, or a key not in p_spec, is invalid_argument.
create function app.clean_payload(p_payload jsonb, p_spec jsonb) returns jsonb
language plpgsql immutable
set search_path = ''
as $$
declare
  v_key text;
  v_value jsonb;
  v_kind text;
  v_text text;
  v_number numeric;
  v_element jsonb;
  v_out jsonb := '{}'::jsonb;
begin
  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then raise exception 'invalid_argument'; end if;
  for v_key, v_value in select e.key, e.value from jsonb_each(p_payload) e loop
    v_kind := p_spec ->> v_key;
    if v_kind is null then raise exception 'invalid_argument'; end if;
    case
      when v_kind in ('text', 'long_text', 'phone') then
        if jsonb_typeof(v_value) = 'null' then
          v_text := null;
        elsif jsonb_typeof(v_value) = 'string' then
          v_text := nullif(btrim(v_value #>> '{}'), '');
        else
          raise exception 'invalid_argument';
        end if;
        if char_length(v_text) > 200 and (v_kind <> 'long_text' or char_length(v_text) > 2000) then
          raise exception 'invalid_argument';
        end if;
        v_out := v_out || jsonb_build_object(v_key, case when v_kind = 'phone' then coalesce(v_text, '') else v_text end);
      when v_kind = 'string' then
        if jsonb_typeof(v_value) <> 'string' then raise exception 'invalid_argument'; end if;
        v_text := nullif(btrim(v_value #>> '{}'), '');
        if v_text is null or char_length(v_text) > 200 then raise exception 'invalid_argument'; end if;
        v_out := v_out || jsonb_build_object(v_key, v_text);
      when v_kind = 'bool' then
        if jsonb_typeof(v_value) <> 'boolean' then raise exception 'invalid_argument'; end if;
        v_out := v_out || jsonb_build_object(v_key, v_value);
      when v_kind = 'int' then
        if jsonb_typeof(v_value) <> 'number' then raise exception 'invalid_argument'; end if;
        v_number := (v_value #>> '{}')::numeric;
        if v_number <> trunc(v_number) or v_number < -2147483648 or v_number > 2147483647 then
          raise exception 'invalid_argument';
        end if;
        v_out := v_out || jsonb_build_object(v_key, v_number::integer);
      when v_kind = 'uuid' then
        if jsonb_typeof(v_value) <> 'string'
           or (v_value #>> '{}') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
          raise exception 'invalid_argument';
        end if;
        v_out := v_out || jsonb_build_object(v_key, lower(v_value #>> '{}'));
      when v_kind = 'strings' then
        if jsonb_typeof(v_value) <> 'array' then raise exception 'invalid_argument'; end if;
        for v_element in select e from jsonb_array_elements(v_value) e loop
          if jsonb_typeof(v_element) <> 'string' then raise exception 'invalid_argument'; end if;
        end loop;
        v_out := v_out || jsonb_build_object(v_key, v_value);
      else
        raise exception 'invalid_argument';
    end case;
  end loop;
  return v_out;
end $$;

-- A venue's seven days as stored: a weekday with no row is closed.
create function app.venue_week_json(p_venue_id uuid) returns jsonb
language sql stable
set search_path = ''
as $$
  select jsonb_agg(jsonb_build_object(
      'weekday', d.weekday,
      'closed', coalesce(h.closed, true),
      'open_minute', coalesce(h.open_minute, 0),
      'close_minute', coalesce(h.close_minute, 0))
    order by d.weekday)
  from generate_series(1, 7) d (weekday)
  left join public.working_hours h on h.venue_id = p_venue_id and h.weekday = d.weekday
$$;

create function app.price_rules_json(p_court_id uuid) returns jsonb
language sql stable
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
      'weekdays', to_jsonb(r.weekdays), 'from_minute', r.from_minute, 'to_minute', r.to_minute, 'price', r.price)
    order by r.sort_order, r.id), '[]'::jsonb)
  from public.price_rules r
  where r.court_id = p_court_id
$$;

-- ---------------------------------------------------------------------------
-- Venues and courts
-- ---------------------------------------------------------------------------

-- Every venue, active or not, newest first, with its courts, hours and owners.
create function app.admin_list_venues(p_user uuid) returns setof jsonb
language plpgsql stable
set search_path = ''
as $$
begin
  perform app.require_admin(p_user);
  return query
  select to_jsonb(v) || jsonb_build_object(
    'courts', coalesce((
      select jsonb_agg(to_jsonb(c) || jsonb_build_object(
          'hours', app.hours_json(null, c.id),
          'price_rules', app.price_rules_json(c.id))
        order by c.sort_order, c.id)
      from public.courts c where c.venue_id = v.id), '[]'::jsonb),
    'hours', app.venue_week_json(v.id),
    'owners', coalesce((
      select jsonb_agg(jsonb_build_object('user_id', o.user_id, 'full_name', p.full_name, 'phone', pc.phone)
        order by p.full_name, o.user_id)
      from public.venue_owners o
      join public.profiles p on p.id = o.user_id
      left join public.profile_contacts pc on pc.user_id = o.user_id
      where o.venue_id = v.id), '[]'::jsonb))
  from public.venues v
  order by v.created_at desc, v.id;
end $$;

-- No `id` = create (open 08:00-22:00 every day), otherwise update the keys given.
create function app.admin_save_venue(p_user uuid, p_venue jsonb, p_now timestamptz) returns uuid
language plpgsql
set search_path = ''
as $$
declare
  c_spec constant jsonb := '{
    "id": "uuid", "city_id": "string",
    "name_uz": "text", "name_ru": "text", "name_en": "text",
    "description_uz": "long_text", "description_ru": "long_text", "description_en": "long_text",
    "address_uz": "text", "address_ru": "text", "address_en": "text",
    "district_uz": "text", "district_ru": "text", "district_en": "text",
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
  if coalesce(v_row.name_uz, v_row.name_ru, v_row.name_en) is null then raise exception 'invalid_argument'; end if;

  if v_creating then
    insert into public.venues select (v_row).*;
    insert into public.working_hours (venue_id, weekday, open_minute, close_minute)
    select v_row.id, d, 480, 1320 from generate_series(1, 7) d;
  else
    update public.venues v set
      city_id = v_row.city_id,
      name_uz = v_row.name_uz, name_ru = v_row.name_ru, name_en = v_row.name_en,
      description_uz = v_row.description_uz, description_ru = v_row.description_ru, description_en = v_row.description_en,
      address_uz = v_row.address_uz, address_ru = v_row.address_ru, address_en = v_row.address_en,
      district_uz = v_row.district_uz, district_ru = v_row.district_ru, district_en = v_row.district_en,
      phone = v_row.phone, amenities = v_row.amenities, active = v_row.active
    where v.id = v_row.id
    returning * into v_row;
  end if;

  perform app.audit(p_user, case when v_creating then 'create_venue' else 'update_venue' end, 'venue', v_row.id::text,
    case when v_creating then null else to_jsonb(v_before) end, to_jsonb(v_row), p_now);
  return v_row.id;
end $$;

-- No `id` = create (placed after the venue's courts), otherwise update the
-- keys given. A court cannot move to another venue.
create function app.admin_save_court(p_user uuid, p_court jsonb, p_now timestamptz) returns uuid
language plpgsql
set search_path = ''
as $$
declare
  c_spec constant jsonb := '{
    "id": "uuid", "venue_id": "uuid", "sport_id": "string",
    "name_uz": "text", "name_ru": "text", "name_en": "text",
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
  if coalesce(v_row.name_uz, v_row.name_ru, v_row.name_en) is null then raise exception 'invalid_argument'; end if;

  if v_creating then
    insert into public.courts select (v_row).*;
  else
    update public.courts c set
      sport_id = v_row.sport_id,
      name_uz = v_row.name_uz, name_ru = v_row.name_ru, name_en = v_row.name_en,
      slot_minutes = v_row.slot_minutes, base_price = v_row.base_price,
      indoor = v_row.indoor, active = v_row.active
    where c.id = v_row.id
    returning * into v_row;
  end if;

  perform app.audit(p_user, case when v_creating then 'create_court' else 'update_court' end, 'court', v_row.id::text,
    case when v_creating then null else to_jsonb(v_before) end, to_jsonb(v_row), p_now);
  return v_row.id;
end $$;

-- A copy right after the original: same venue, sport, slot length, prices,
-- price rules and hour overrides; each name gets " 2".
create function app.admin_duplicate_court(p_user uuid, p_court_id uuid, p_now timestamptz) returns uuid
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

-- Only a court no booking row has ever referenced; otherwise deactivate it.
create function app.admin_delete_court(p_user uuid, p_court_id uuid, p_now timestamptz) returns void
language plpgsql
set search_path = ''
as $$
declare
  v_court public.courts;
begin
  perform app.require_admin(p_user);
  select c.* into v_court from public.courts c where c.id = p_court_id for update;
  if not found then raise exception 'not_found'; end if;
  if exists (select 1 from public.bookings b where b.court_id = p_court_id) then raise exception 'has_bookings'; end if;

  delete from public.courts c where c.id = p_court_id;
  perform app.audit(p_user, 'delete_court', 'court', p_court_id::text, to_jsonb(v_court), null, p_now);
end $$;

-- Only a venue no booking or tournament references; otherwise deactivate it.
-- Its courts, hours, rules and owner assignments go with it.
create function app.admin_delete_venue(p_user uuid, p_venue_id uuid, p_now timestamptz) returns void
language plpgsql
set search_path = ''
as $$
declare
  v_venue public.venues;
begin
  perform app.require_admin(p_user);
  select v.* into v_venue from public.venues v where v.id = p_venue_id for update;
  if not found then raise exception 'not_found'; end if;
  if exists (select 1 from public.bookings b where b.venue_id = p_venue_id)
     or exists (select 1 from public.tournaments t where t.venue_id = p_venue_id) then
    raise exception 'has_bookings';
  end if;

  delete from public.venues v where v.id = p_venue_id;
  perform app.audit(p_user, 'delete_venue', 'venue', p_venue_id::text, to_jsonb(v_venue), null, p_now);
end $$;

-- ---------------------------------------------------------------------------
-- Owners
-- ---------------------------------------------------------------------------

-- Name (case-insensitive substring) or phone (digit substring); at most 20.
create function app.admin_search_users(p_user uuid, p_query text) returns setof jsonb
language plpgsql stable
set search_path = ''
as $$
declare
  v_query text := btrim(coalesce(p_query, ''));
  v_pattern text;
  v_digits text;
begin
  perform app.require_admin(p_user);
  if char_length(v_query) < 2 then return; end if;
  v_query := left(v_query, 100);
  v_pattern := '%' || replace(replace(replace(v_query, '\', '\\'), '%', '\%'), '_', '\_') || '%';
  v_digits := regexp_replace(v_query, '[^0-9]', '', 'g');

  return query
  select jsonb_build_object('user_id', p.id, 'full_name', p.full_name, 'phone', pc.phone)
  from public.profiles p
  left join public.profile_contacts pc on pc.user_id = p.id
  where p.full_name ilike v_pattern
     or (char_length(v_digits) >= 2 and regexp_replace(pc.phone, '[^0-9]', '', 'g') like '%' || v_digits || '%')
  order by p.full_name nulls last, p.id
  limit 20;
end $$;

create function app.admin_set_owner(p_user uuid, p_venue_id uuid, p_user_id uuid, p_assigned boolean, p_now timestamptz)
returns void
language plpgsql
set search_path = ''
as $$
begin
  perform app.require_admin(p_user);
  if p_assigned is null then raise exception 'invalid_argument'; end if;
  if not exists (select 1 from public.venues v where v.id = p_venue_id) then raise exception 'not_found'; end if;
  if not exists (select 1 from public.profiles p where p.id = p_user_id) then raise exception 'not_found'; end if;

  if p_assigned then
    insert into public.venue_owners (venue_id, user_id, created_at) values (p_venue_id, p_user_id, p_now)
    on conflict do nothing;
  else
    delete from public.venue_owners o where o.venue_id = p_venue_id and o.user_id = p_user_id;
  end if;

  perform app.audit(p_user, case when p_assigned then 'assign_owner' else 'remove_owner' end, 'venue', p_venue_id::text,
    null, jsonb_build_object('user_id', p_user_id, 'assigned', p_assigned), p_now);
end $$;

-- ---------------------------------------------------------------------------
-- Sports
-- ---------------------------------------------------------------------------

create function app.admin_list_sports(p_user uuid) returns setof jsonb
language plpgsql stable
set search_path = ''
as $$
begin
  perform app.require_admin(p_user);
  return query select to_jsonb(s) from public.sports s order by s.sort_order, s.id;
end $$;

create function app.admin_save_sport(p_user uuid, p_sport jsonb, p_create boolean, p_now timestamptz) returns text
language plpgsql
set search_path = ''
as $$
declare
  c_spec constant jsonb := '{
    "id": "string", "name_uz": "text", "name_ru": "text", "name_en": "text", "icon_key": "string",
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
  if coalesce(v_row.name_uz, v_row.name_ru, v_row.name_en) is null then raise exception 'invalid_argument'; end if;

  if p_create then
    if exists (select 1 from public.sports s where s.id = v_row.id) then raise exception 'already_exists'; end if;
    insert into public.sports select (v_row).*;
  else
    update public.sports s set
      name_uz = v_row.name_uz, name_ru = v_row.name_ru, name_en = v_row.name_en,
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
-- Banners
-- ---------------------------------------------------------------------------

create function app.admin_list_banners(p_user uuid) returns setof jsonb
language plpgsql stable
set search_path = ''
as $$
begin
  perform app.require_admin(p_user);
  return query select to_jsonb(b) from public.banners b order by b.sort_order, b.id;
end $$;

create function app.admin_save_banner(p_user uuid, p_banner jsonb, p_now timestamptz) returns uuid
language plpgsql
set search_path = ''
as $$
declare
  c_spec constant jsonb := '{
    "id": "uuid", "city_id": "text",
    "title_uz": "text", "title_ru": "text", "title_en": "text",
    "subtitle_uz": "text", "subtitle_ru": "text", "subtitle_en": "text",
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
  if coalesce(v_row.title_uz, v_row.title_ru, v_row.title_en) is null then raise exception 'invalid_argument'; end if;

  if v_creating then
    insert into public.banners select (v_row).*;
  else
    update public.banners b set
      city_id = v_row.city_id,
      title_uz = v_row.title_uz, title_ru = v_row.title_ru, title_en = v_row.title_en,
      subtitle_uz = v_row.subtitle_uz, subtitle_ru = v_row.subtitle_ru, subtitle_en = v_row.subtitle_en,
      url = v_row.url, sort_order = v_row.sort_order, active = v_row.active
    where b.id = v_row.id
    returning * into v_row;
  end if;

  perform app.audit(p_user, case when v_creating then 'create_banner' else 'update_banner' end, 'banner', v_row.id::text,
    case when v_creating then null else to_jsonb(v_before) end, to_jsonb(v_row), p_now);
  return v_row.id;
end $$;

create function app.admin_delete_banner(p_user uuid, p_banner_id uuid, p_now timestamptz) returns void
language plpgsql
set search_path = ''
as $$
declare
  v_banner public.banners;
begin
  perform app.require_admin(p_user);
  delete from public.banners b where b.id = p_banner_id returning * into v_banner;
  if not found then raise exception 'not_found'; end if;
  perform app.audit(p_user, 'delete_banner', 'banner', p_banner_id::text, to_jsonb(v_banner), null, p_now);
end $$;

-- ---------------------------------------------------------------------------
-- Audit log
-- ---------------------------------------------------------------------------

-- Newest first, p_limit (1-100) entries older than p_before (null = newest).
create function app.admin_audit_log(p_user uuid, p_limit integer, p_before timestamptz) returns setof jsonb
language plpgsql stable
set search_path = ''
as $$
begin
  perform app.require_admin(p_user);
  if p_limit is null or p_limit < 1 or p_limit > 100 then raise exception 'invalid_argument'; end if;
  return query
  select jsonb_build_object(
    'id', a.id::text,
    'created_at', a.created_at,
    'actor_name', p.full_name,
    'action', a.action,
    'entity', a.entity,
    'entity_id', a.entity_id,
    'before', a.before,
    'after', a.after)
  from public.audit_log a
  left join public.profiles p on p.id = a.actor_id
  where p_before is null or a.created_at < p_before
  order by a.created_at desc, a.id desc
  limit p_limit;
end $$;

create index audit_log_created_idx on public.audit_log (created_at desc, id desc);

-- ---------------------------------------------------------------------------
-- What the app calls. Each runs as the signed-in user at the real time.
-- ---------------------------------------------------------------------------

create function public.am_i_admin() returns boolean
language sql stable security definer
set search_path = ''
as $$ select app.is_admin((select auth.uid())) $$;

create function public.admin_list_venues() returns setof jsonb
language sql stable security definer
set search_path = ''
as $$ select * from app.admin_list_venues((select auth.uid())) $$;

create function public.admin_save_venue(p_venue jsonb) returns uuid
language sql security definer
set search_path = ''
as $$ select app.admin_save_venue((select auth.uid()), p_venue, now()) $$;

create function public.admin_save_court(p_court jsonb) returns uuid
language sql security definer
set search_path = ''
as $$ select app.admin_save_court((select auth.uid()), p_court, now()) $$;

create function public.admin_duplicate_court(p_court_id uuid) returns uuid
language sql security definer
set search_path = ''
as $$ select app.admin_duplicate_court((select auth.uid()), p_court_id, now()) $$;

create function public.admin_delete_court(p_court_id uuid) returns void
language sql security definer
set search_path = ''
as $$ select app.admin_delete_court((select auth.uid()), p_court_id, now()) $$;

create function public.admin_delete_venue(p_venue_id uuid) returns void
language sql security definer
set search_path = ''
as $$ select app.admin_delete_venue((select auth.uid()), p_venue_id, now()) $$;

create function public.admin_search_users(p_query text) returns setof jsonb
language sql stable security definer
set search_path = ''
as $$ select * from app.admin_search_users((select auth.uid()), p_query) $$;

create function public.admin_set_owner(p_venue_id uuid, p_user_id uuid, p_assigned boolean) returns void
language sql security definer
set search_path = ''
as $$ select app.admin_set_owner((select auth.uid()), p_venue_id, p_user_id, p_assigned, now()) $$;

create function public.admin_list_sports() returns setof jsonb
language sql stable security definer
set search_path = ''
as $$ select * from app.admin_list_sports((select auth.uid())) $$;

create function public.admin_save_sport(p_sport jsonb, p_create boolean) returns text
language sql security definer
set search_path = ''
as $$ select app.admin_save_sport((select auth.uid()), p_sport, p_create, now()) $$;

create function public.admin_list_banners() returns setof jsonb
language sql stable security definer
set search_path = ''
as $$ select * from app.admin_list_banners((select auth.uid())) $$;

create function public.admin_save_banner(p_banner jsonb) returns uuid
language sql security definer
set search_path = ''
as $$ select app.admin_save_banner((select auth.uid()), p_banner, now()) $$;

create function public.admin_delete_banner(p_banner_id uuid) returns void
language sql security definer
set search_path = ''
as $$ select app.admin_delete_banner((select auth.uid()), p_banner_id, now()) $$;

create function public.admin_audit_log(p_limit integer, p_before timestamptz) returns setof jsonb
language sql stable security definer
set search_path = ''
as $$ select * from app.admin_audit_log((select auth.uid()), p_limit, p_before) $$;

revoke all on function
  public.am_i_admin(),
  public.admin_list_venues(),
  public.admin_save_venue(jsonb),
  public.admin_save_court(jsonb),
  public.admin_duplicate_court(uuid),
  public.admin_delete_court(uuid),
  public.admin_delete_venue(uuid),
  public.admin_search_users(text),
  public.admin_set_owner(uuid, uuid, boolean),
  public.admin_list_sports(),
  public.admin_save_sport(jsonb, boolean),
  public.admin_list_banners(),
  public.admin_save_banner(jsonb),
  public.admin_delete_banner(uuid),
  public.admin_audit_log(integer, timestamptz)
from public, anon, authenticated;

grant execute on function
  public.am_i_admin(),
  public.admin_list_venues(),
  public.admin_save_venue(jsonb),
  public.admin_save_court(jsonb),
  public.admin_duplicate_court(uuid),
  public.admin_delete_court(uuid),
  public.admin_delete_venue(uuid),
  public.admin_search_users(text),
  public.admin_set_owner(uuid, uuid, boolean),
  public.admin_list_sports(),
  public.admin_save_sport(jsonb, boolean),
  public.admin_list_banners(),
  public.admin_save_banner(jsonb),
  public.admin_delete_banner(uuid),
  public.admin_audit_log(integer, timestamptz)
to authenticated, service_role;
