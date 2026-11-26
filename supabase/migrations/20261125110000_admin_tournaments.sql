-- Admin tournament manager and admin dashboard (Milestone 5b).
--
-- Same conventions as 20261123120000_admin.sql: rules in the private `app`
-- schema taking the acting user and the clock, thin `public` wrappers at the
-- end. Every function calls app.require_admin (not_allowed) before reading
-- anything; every write adds exactly one audit_log row with before/after.
-- Save payloads go through app.clean_payload: an unknown key is refused.
--
-- Locking order, as in 20261125100000_tournaments.sql: category rows first
-- (several in id order), then registration rows, then the tournament row
-- (app.sync_tournament_summary, or an explicit lock taken last). Creating a
-- category locks the tournament first, as it holds no other lock yet (see
-- admin_save_category). offer_next
-- runs before sync_tournament_summary. Functions that count (add, move,
-- offer next, cap change, delete) sweep the category first, so an expired
-- offer or invite never holds a spot or blocks anyone.
--
-- Additive only: new functions, and app.offer_next redefined with the same
-- signature and behaviour on top of app.offer_spots, which admin_offer_next
-- also uses after the deadline.

-- ---------------------------------------------------------------------------
-- Offers: one loop for the automatic path and the admin's
-- ---------------------------------------------------------------------------

-- While the category has room, the first confirmed waitlisted entry is
-- offered the spot for 24 hours; the offer holds the spot. Unconfirmed pairs
-- are skipped. The automatic path (p_admin false) does nothing once the
-- deadline has passed and clamps the offer to the deadline. The admin's
-- (p_admin true) also works after the deadline, when the offer runs a full
-- 24 hours (claim_offer does not check the deadline). Nothing on an inactive
-- tournament. Returns how many entries were offered.
create function app.offer_spots(p_category_id uuid, p_now timestamptz, p_admin boolean) returns integer
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
  if not v_tournament.active or (not p_admin and p_now >= v_deadline) then return 0; end if;

  loop
    exit when app.category_counted(p_category_id) >= v_category.cap;
    update public.tournament_registrations r
    set status = 'offered',
        offer_expires_at = case when p_now < v_deadline then least(p_now + interval '24 hours', v_deadline)
                                else p_now + interval '24 hours' end
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

-- Same signature and behaviour as in 20261125100000_tournaments.sql.
create or replace function app.offer_next(p_category_id uuid, p_now timestamptz) returns integer
language plpgsql
set search_path = ''
as $$
begin
  return app.offer_spots(p_category_id, p_now, false);
end $$;

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

-- 'YYYY-MM-DD', a real date, or invalid_argument.
create function app.admin_date(p_text text) returns date
language plpgsql immutable
set search_path = ''
as $$
begin
  if p_text is null or p_text !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'invalid_argument'; end if;
  return p_text::date;
exception when datetime_field_overflow or invalid_datetime_format then
  raise exception 'invalid_argument';
end $$;

-- Wall-clock 'YYYY-MM-DDTHH:MM[:SS]', or invalid_argument.
create function app.admin_timestamp(p_text text) returns timestamp
language plpgsql immutable
set search_path = ''
as $$
begin
  if p_text is null or p_text !~ '^\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}(:\d{2})?$' then raise exception 'invalid_argument'; end if;
  return p_text::timestamp;
exception when datetime_field_overflow or invalid_datetime_format then
  raise exception 'invalid_argument';
end $$;

-- The keys a category payload may carry (app.clean_payload kinds).
create function app.category_spec() returns jsonb
language sql immutable
set search_path = ''
as $$
  select '{
    "id": "uuid", "tournament_id": "uuid",
    "name_uz": "text", "name_ru": "text", "name_en": "text",
    "kind": "string", "gender": "string", "min_level": "int", "max_level": "int",
    "fee": "int", "cap": "int", "waitlist_enabled": "bool", "sort_order": "int"}'::jsonb
$$;

-- A new category's defaults (an insert of a whole record skips the column
-- defaults). kind and cap stay null: the payload must give them.
create function app.new_category(p_tournament_id uuid, p_sort_order integer, p_now timestamptz)
returns public.tournament_categories
language plpgsql
set search_path = ''
as $$
declare
  v public.tournament_categories;
begin
  v.id := gen_random_uuid();
  v.tournament_id := p_tournament_id;
  v.gender := 'open';
  v.min_level := 1;
  v.max_level := 5;
  v.fee := 0;
  v.waitlist_enabled := true;
  v.sort_order := p_sort_order;
  v.created_at := p_now;
  return v;
end $$;

-- Applies a cleaned payload (id and tournament_id are the caller's business)
-- and checks the result, raising invalid_argument before any constraint
-- would.
create function app.apply_category(p_row public.tournament_categories, p_patch jsonb)
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
     or coalesce(v.name_uz, v.name_ru, v.name_en) is null then
    raise exception 'invalid_argument';
  end if;
  return v;
end $$;

-- An entry as the admin screens receive it: the player's view plus phones,
-- the paid instant, the override flag and the raw waitlist position.
create function app.admin_registration_json(r public.tournament_registrations) returns jsonb
language sql
set search_path = ''
as $$
  select app.registration_json(r) || jsonb_build_object(
    'registrant', (select jsonb_build_object('id', p.id, 'name', p.full_name, 'phone', pc.phone)
                   from public.profiles p left join public.profile_contacts pc on pc.user_id = p.id
                   where p.id = r.user_id),
    'partner', case when r.partner_id is null then null else
      (select jsonb_build_object('id', p.id, 'name', p.full_name, 'phone', pc.phone)
       from public.profiles p left join public.profile_contacts pc on pc.user_id = p.id
       where p.id = r.partner_id) end,
    'paid_at', r.paid_at,
    'admin_override', r.admin_override,
    'waitlist_position', r.waitlist_position)
$$;

-- ---------------------------------------------------------------------------
-- Tournaments
-- ---------------------------------------------------------------------------

-- Every tournament, active or not, latest start first (the table has no
-- creation time), as tournament_json shows it plus how many categories and
-- live entries it has.
create function app.admin_list_tournaments(p_user uuid, p_now timestamptz) returns setof jsonb
language plpgsql
set search_path = ''
as $$
begin
  perform app.require_admin(p_user);
  return query
  select app.tournament_json(t, null, p_now) || jsonb_build_object(
    'category_count', (select count(*) from public.tournament_categories c where c.tournament_id = t.id),
    'registration_count', (select count(*) from public.tournament_registrations r
                           join public.tournament_categories c on c.id = r.category_id
                           where c.tournament_id = t.id
                             and r.status in ('pending_partner', 'registered', 'waitlisted', 'offered')))
  from public.tournaments t
  order by t.starts_on desc, t.id;
end $$;

-- No `id` = create, otherwise update the keys given. On create, `categories`
-- (a non-empty array of category payloads without id/tournament_id) makes
-- those categories; without it the tournament gets one open singles
-- category (fee 0, cap 16), so it can take registrations at once.
-- registration_deadline_local is venue wall-clock time; null or missing on
-- create means 00:00 on starts_on. It must not be after the end of ends_on.
-- The summary columns (min_fee, max_fee, slots_total, slots_filled) are
-- never written here: app.sync_tournament_summary keeps them.
create function app.admin_save_tournament(p_user uuid, p_tournament jsonb, p_now timestamptz) returns uuid
language plpgsql
set search_path = ''
as $$
declare
  c_spec constant jsonb := '{
    "id": "uuid", "city_id": "string", "sport_id": "string", "venue_id": "text",
    "title_uz": "text", "title_ru": "text", "title_en": "text",
    "description_uz": "long_text", "description_ru": "long_text", "description_en": "long_text",
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
  if coalesce(v_row.title_uz, v_row.title_ru, v_row.title_en) is null then raise exception 'invalid_argument'; end if;
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
      title_uz = v_row.title_uz, title_ru = v_row.title_ru, title_en = v_row.title_en,
      description_uz = v_row.description_uz, description_ru = v_row.description_ru, description_en = v_row.description_en,
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
-- Categories
-- ---------------------------------------------------------------------------

-- No `id` = create (tournament_id, kind and cap required; placed last),
-- otherwise update the keys given. A category never moves to another
-- tournament; its cap never goes below its counted entries
-- (invalid_argument); its kind is fixed once it has live entries
-- (has_registrations). Raising the cap offers the freed spots to the
-- waitlist (until the deadline). Fees already taken stay as they were.
create function app.admin_save_category(p_user uuid, p_category jsonb, p_now timestamptz) returns uuid
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
      name_uz = v_row.name_uz, name_ru = v_row.name_ru, name_en = v_row.name_en,
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

-- Only a category no registration has ever been in, finished ones included
-- (has_registrations): registration history is never deleted, as the
-- foreign key's `on delete restrict` intends. Never a tournament's last
-- category (invalid_argument: every tournament keeps one).
create function app.admin_delete_category(p_user uuid, p_category_id uuid, p_now timestamptz) returns void
language plpgsql
set search_path = ''
as $$
declare
  v_category public.tournament_categories;
begin
  perform app.require_admin(p_user);
  select c.* into v_category from public.tournament_categories c where c.id = p_category_id for update;
  if not found then raise exception 'not_found'; end if;
  -- The category row lock keeps new entries out while this runs.
  if exists (select 1 from public.tournament_registrations r where r.category_id = v_category.id) then
    raise exception 'has_registrations';
  end if;
  -- The tournament row (taken last) makes two deletes of its last two
  -- categories take turns, so one of them sees the other's.
  perform 1 from public.tournaments t where t.id = v_category.tournament_id for update;
  if not exists (select 1 from public.tournament_categories c
                 where c.tournament_id = v_category.tournament_id and c.id <> v_category.id) then
    raise exception 'invalid_argument';
  end if;

  delete from public.tournament_categories c where c.id = v_category.id;
  perform app.sync_tournament_summary(v_category.tournament_id);
  perform app.audit(p_user, 'delete_category', 'tournament_category', v_category.id::text,
    to_jsonb(v_category), null, p_now);
end $$;

-- ---------------------------------------------------------------------------
-- Registrations
-- ---------------------------------------------------------------------------

-- Every entry of the tournament, any state, with phones: by category, then
-- counted entries, pending pairs, the waitlist in order, finished ones.
create function app.admin_list_registrations(p_user uuid, p_tournament_id uuid) returns setof jsonb
language plpgsql
set search_path = ''
as $$
begin
  perform app.require_admin(p_user);
  if not exists (select 1 from public.tournaments t where t.id = p_tournament_id) then raise exception 'not_found'; end if;
  return query
  select app.admin_registration_json(r)
  from public.tournament_registrations r
  join public.tournament_categories c on c.id = r.category_id
  where c.tournament_id = p_tournament_id
  order by c.sort_order, c.created_at, c.id,
    case r.status when 'registered' then 0 when 'offered' then 1 when 'pending_partner' then 2 when 'waitlisted' then 3 else 4 end,
    r.waitlist_position nulls first, r.created_at, r.id;
end $$;

-- Registered entries only (not_markable otherwise). Marking an already paid
-- entry keeps its first paid time.
create function app.admin_set_paid(p_user uuid, p_registration_id uuid, p_paid boolean, p_now timestamptz)
returns public.tournament_registrations
language plpgsql
set search_path = ''
as $$
declare
  v_reg public.tournament_registrations;
  v_before public.tournament_registrations;
begin
  perform app.require_admin(p_user);
  if p_paid is null then raise exception 'invalid_argument'; end if;
  v_reg := app.lock_registration(p_registration_id);
  if v_reg.id is null then raise exception 'not_found'; end if;
  if v_reg.status <> 'registered' then raise exception 'not_markable'; end if;
  v_before := v_reg;
  update public.tournament_registrations r
  set paid_at = case when p_paid then coalesce(r.paid_at, p_now) end
  where r.id = v_reg.id
  returning * into v_reg;
  perform app.audit(p_user, 'set_registration_paid', 'tournament_registration', v_reg.id::text,
    to_jsonb(v_before), to_jsonb(v_reg), p_now);
  return v_reg;
end $$;

-- Any live entry (also a waitlisted one: this is admin_remove_waitlisted)
-- becomes removed, at any time. The registrant and the named partner
-- (confirmed, or still holding the invite) are told; expired entries are
-- settled, then a spot it held goes to the waitlist (until the deadline).
create function app.admin_remove_registration(p_user uuid, p_registration_id uuid, p_now timestamptz)
returns public.tournament_registrations
language plpgsql
set search_path = ''
as $$
declare
  v_reg public.tournament_registrations;
  v_before public.tournament_registrations;
  v_note jsonb;
begin
  perform app.require_admin(p_user);
  v_reg := app.lock_registration(p_registration_id);
  if v_reg.id is null or v_reg.status not in ('pending_partner', 'registered', 'waitlisted', 'offered') then
    raise exception 'not_found';
  end if;
  v_before := v_reg;
  update public.tournament_registrations r set status = 'removed', cancelled_at = p_now
  where r.id = v_reg.id returning * into v_reg;

  v_note := app.registration_note(v_reg);
  perform app.notify(v_reg.user_id, 'tournament_removed', 'tournaments', v_note, p_now);
  -- A pending invitee is told too, so the invite does not linger.
  perform app.notify(v_reg.partner_id, 'tournament_removed', 'tournaments', v_note, p_now);
  perform app.sweep_category(v_reg.category_id, p_now);
  if v_before.status in ('registered', 'offered') then perform app.offer_next(v_reg.category_id, p_now); end if;
  perform app.sync_tournament_summary((select c.tournament_id from public.tournament_categories c where c.id = v_reg.category_id));
  perform app.audit(p_user, 'remove_registration', 'tournament_registration', v_reg.id::text,
    to_jsonb(v_before), to_jsonb(v_reg), p_now);
  return v_reg;
end $$;

-- A registered entry to another category of the same tournament and kind
-- (invalid_argument otherwise), with its locked fee, bypassing the target's
-- level range but never its cap (full). Both categories are locked in id
-- order before the entry. The players are told; the freed spot goes to the
-- source's waitlist (until the deadline).
create function app.admin_move_registration(p_user uuid, p_registration_id uuid, p_category_id uuid, p_now timestamptz)
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
    jsonb_build_object('uz', v_source.name_uz, 'ru', v_source.name_ru, 'en', v_source.name_en));
  perform app.notify(v_reg.user_id, 'tournament_moved', 'tournaments', v_note, p_now);
  perform app.notify(v_partner, 'tournament_moved', 'tournaments', v_note, p_now);
  perform app.offer_next(v_source.id, p_now);
  perform app.sync_tournament_summary(v_source.tournament_id);
  perform app.audit(p_user, 'move_registration', 'tournament_registration', v_reg.id::text,
    to_jsonb(v_before), to_jsonb(v_reg), p_now);
  return v_reg;
end $$;

-- Registers a player (and, for pairs, the partner, confirmed at once) in a
-- category of an active tournament, bypassing the level range, the deadline
-- and the reliability block, never the cap (full). admin_override = true.
create function app.admin_add_registration(
  p_user uuid, p_category_id uuid, p_user_id uuid, p_partner_id uuid, p_now timestamptz)
returns public.tournament_registrations
language plpgsql
set search_path = ''
as $$
declare
  v_category public.tournament_categories;
  v_tournament public.tournaments;
  v_reg public.tournament_registrations;
  v_note jsonb;
begin
  perform app.require_admin(p_user);
  v_category := app.lock_category(p_category_id);
  select t.* into v_tournament from public.tournaments t where t.id = v_category.tournament_id;

  if p_user_id is null
     or (v_category.kind = 'singles' and p_partner_id is not null)
     or (v_category.kind = 'pairs' and (p_partner_id is null or p_partner_id = p_user_id)) then
    raise exception 'invalid_argument';
  end if;
  if not exists (select 1 from public.profiles p where p.id = p_user_id)
     or (p_partner_id is not null and not exists (select 1 from public.profiles p where p.id = p_partner_id)) then
    raise exception 'not_found';
  end if;

  perform app.sweep_category(v_category.id, p_now);
  if app.live_in_category(v_category.id, p_user_id, null) then raise exception 'already_registered'; end if;
  if p_partner_id is not null and app.live_in_category(v_category.id, p_partner_id, null) then
    raise exception 'partner_unavailable';
  end if;
  if app.category_counted(v_category.id) >= v_category.cap then raise exception 'full'; end if;

  begin
    insert into public.tournament_registrations (
      category_id, user_id, partner_id, partner_confirmed, status, fee, currency, created_at, decided_at, admin_override)
    values (
      v_category.id, p_user_id, p_partner_id, true, 'registered', v_category.fee,
      (select ci.currency from public.cities ci where ci.id = v_tournament.city_id),
      p_now, p_now, true)
    returning * into v_reg;
  exception when unique_violation then
    raise exception 'already_registered';
  end;

  v_note := app.registration_note(v_reg);
  perform app.notify(p_user_id, 'tournament_registered', 'tournaments', v_note, p_now);
  perform app.notify(p_partner_id, 'tournament_registered', 'tournaments', v_note, p_now);
  perform app.sync_tournament_summary(v_tournament.id);
  perform app.audit(p_user, 'add_registration', 'tournament_registration', v_reg.id::text, null, to_jsonb(v_reg), p_now);
  return v_reg;
end $$;

-- Offers the category's free spots to the waitlist now, also after the
-- deadline (then each offer runs 24 hours). full when there is no free spot
-- once expired entries are settled; otherwise how many were offered (0 when
-- nobody confirmed is waiting).
create function app.admin_offer_next(p_user uuid, p_category_id uuid, p_now timestamptz) returns integer
language plpgsql
set search_path = ''
as $$
declare
  v_category public.tournament_categories;
  v_filled integer;
  v_count integer;
begin
  perform app.require_admin(p_user);
  select c.* into v_category from public.tournament_categories c where c.id = p_category_id for update;
  if not found then raise exception 'not_found'; end if;
  perform app.sweep_category(v_category.id, p_now);
  v_filled := app.category_counted(v_category.id);
  if v_filled >= v_category.cap then raise exception 'full'; end if;
  v_count := app.offer_spots(v_category.id, p_now, true);
  perform app.audit(p_user, 'offer_next', 'tournament_category', v_category.id::text,
    jsonb_build_object('filled', v_filled),
    jsonb_build_object('filled', app.category_counted(v_category.id), 'offered', v_count), p_now);
  return v_count;
end $$;

-- ---------------------------------------------------------------------------
-- Dashboard
-- ---------------------------------------------------------------------------

-- One city, or every city when p_city_id is null; p_from..p_to inclusive,
-- at most 366 days, as local dates (each row in its own city's offset).
--   users: total; active_30d (last_seen_at within 30 days, or the last
--     sign-in when the app never reported one); new today, in the last 7
--     days (today included) and this calendar month, by the city-local date
--     of the profile's creation (a profile without a city: UTC). Not bound
--     to the period.
--   revenue: one row per currency with money in the period, never summed
--     across currencies. venues: as app.owner_dashboard's revenue_paid,
--     sum(total_price) of paid app and walk-in bookings by the venue-local
--     date of their start. tournaments: sum(fee) of registered entries with
--     paid_at, by the city-local date of paid_at (a cancelled or removed
--     entry is not revenue).
--   counts: bookings created in the period, app and walk-in, in any state
--     they are in now, cancelled ones included (only holds still running or
--     released without confirming are left out, as they never became
--     bookings; blocks are not bookings); games created (cancelled ones
--     included); tournament entries created (any state).
create function app.admin_dashboard(p_user uuid, p_city_id text, p_from date, p_to date, p_now timestamptz)
returns jsonb
language plpgsql stable
set search_path = ''
as $$
declare
  c_max_days constant integer := 366;
  v_window tstzrange;
  v_users jsonb;
  v_revenue jsonb;
  v_counts jsonb;
begin
  perform app.require_admin(p_user);
  if p_city_id is not null and not exists (select 1 from public.cities ci where ci.id = p_city_id) then
    raise exception 'not_found';
  end if;
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from + 1 > c_max_days then
    raise exception 'invalid_argument';
  end if;
  -- Two days of slack each side covers any city offset; the exact local
  -- day test follows.
  v_window := tstzrange(app.to_instant((p_from - 2)::timestamp, 0), app.to_instant((p_to + 3)::timestamp, 0));

  with people as (
    select p.created_at, coalesce(p.last_seen_at, u.last_sign_in_at) as active_at,
           coalesce(ci.utc_offset_minutes, 0) as off
    from public.profiles p
    left join auth.users u on u.id = p.id
    left join public.cities ci on ci.id = p.city_id
    where p_city_id is null or p.city_id = p_city_id
  ), dated as (
    select active_at, app.to_local(created_at, off)::date as created_on, app.to_local(p_now, off)::date as today
    from people
  )
  select jsonb_build_object(
    'total', count(*),
    'active_30d', count(*) filter (where active_at > p_now - interval '30 days'),
    'new_today', count(*) filter (where created_on = today),
    'new_7d', count(*) filter (where created_on > today - 7 and created_on <= today),
    'new_month', count(*) filter (where date_trunc('month', created_on) = date_trunc('month', today) and created_on <= today))
  into v_users
  from dated;

  with venue_revenue as (
    select b.currency, sum(b.total_price) as amount
    from public.bookings b
    join public.venues v on v.id = b.venue_id
    where b.status = 'paid' and b.source in ('app', 'walk_in')
      and (p_city_id is null or v.city_id = p_city_id)
      and b.during && v_window
      and app.to_local(lower(b.during), b.utc_offset_minutes)::date between p_from and p_to
    group by b.currency
  ), tournament_revenue as (
    select r.currency, sum(r.fee) as amount
    from public.tournament_registrations r
    join public.tournament_categories c on c.id = r.category_id
    join public.tournaments t on t.id = c.tournament_id
    join public.cities ci on ci.id = t.city_id
    where r.status = 'registered' and r.paid_at is not null
      and (p_city_id is null or t.city_id = p_city_id)
      and r.paid_at <@ v_window
      and app.to_local(r.paid_at, ci.utc_offset_minutes)::date between p_from and p_to
    group by r.currency
  ), currencies as (
    select currency from venue_revenue union select currency from tournament_revenue
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'currency', x.currency,
      'venues', coalesce(vr.amount, 0),
      'tournaments', coalesce(tr.amount, 0))
    order by x.currency), '[]'::jsonb)
  into v_revenue
  from currencies x
  left join venue_revenue vr on vr.currency = x.currency
  left join tournament_revenue tr on tr.currency = x.currency;

  select jsonb_build_object(
    -- Every booking made in the period, cancelled ones included.
    'bookings', (
      select count(*) from public.bookings b
      join public.venues v on v.id = b.venue_id
      where b.source in ('app', 'walk_in') and b.status not in ('held', 'released')
        and (p_city_id is null or v.city_id = p_city_id)
        and b.created_at <@ v_window
        and app.to_local(b.created_at, b.utc_offset_minutes)::date between p_from and p_to),
    'games', (
      select count(*) from public.games g
      where (p_city_id is null or g.city_id = p_city_id)
        and g.created_at <@ v_window
        and app.to_local(g.created_at, g.utc_offset_minutes)::date between p_from and p_to),
    'registrations', (
      select count(*) from public.tournament_registrations r
      join public.tournament_categories c on c.id = r.category_id
      join public.tournaments t on t.id = c.tournament_id
      join public.cities ci on ci.id = t.city_id
      where (p_city_id is null or t.city_id = p_city_id)
        and r.created_at <@ v_window
        and app.to_local(r.created_at, ci.utc_offset_minutes)::date between p_from and p_to))
  into v_counts;

  return jsonb_build_object('users', v_users, 'revenue', v_revenue, 'counts', v_counts);
end $$;

-- ---------------------------------------------------------------------------
-- What the app calls. Each runs as the signed-in user at the real time.
-- Registration calls return the entry as the admin screens see it (phones).
-- ---------------------------------------------------------------------------

create function public.admin_save_tournament(p_tournament jsonb) returns uuid
language sql security definer
set search_path = ''
as $$ select app.admin_save_tournament((select auth.uid()), p_tournament, now()) $$;

create function public.admin_save_category(p_category jsonb) returns uuid
language sql security definer
set search_path = ''
as $$ select app.admin_save_category((select auth.uid()), p_category, now()) $$;

create function public.admin_delete_category(p_category_id uuid) returns void
language sql security definer
set search_path = ''
as $$ select app.admin_delete_category((select auth.uid()), p_category_id, now()) $$;

create function public.admin_list_tournaments() returns setof jsonb
language sql security definer
set search_path = ''
as $$ select * from app.admin_list_tournaments((select auth.uid()), now()) $$;

create function public.admin_list_registrations(p_tournament_id uuid) returns setof jsonb
language sql security definer
set search_path = ''
as $$ select * from app.admin_list_registrations((select auth.uid()), p_tournament_id) $$;

create function public.admin_set_paid(p_registration_id uuid, p_paid boolean) returns jsonb
language sql security definer
set search_path = ''
as $$ select app.admin_registration_json(app.admin_set_paid((select auth.uid()), p_registration_id, p_paid, now())) $$;

create function public.admin_remove_registration(p_registration_id uuid) returns jsonb
language sql security definer
set search_path = ''
as $$ select app.admin_registration_json(app.admin_remove_registration((select auth.uid()), p_registration_id, now())) $$;

create function public.admin_move_registration(p_registration_id uuid, p_category_id uuid) returns jsonb
language sql security definer
set search_path = ''
as $$ select app.admin_registration_json(app.admin_move_registration((select auth.uid()), p_registration_id, p_category_id, now())) $$;

create function public.admin_add_registration(p_category_id uuid, p_user_id uuid, p_partner_id uuid default null) returns jsonb
language sql security definer
set search_path = ''
as $$ select app.admin_registration_json(app.admin_add_registration((select auth.uid()), p_category_id, p_user_id, p_partner_id, now())) $$;

create function public.admin_offer_next(p_category_id uuid) returns integer
language sql security definer
set search_path = ''
as $$ select app.admin_offer_next((select auth.uid()), p_category_id, now()) $$;

create function public.admin_dashboard(p_city_id text, p_from date, p_to date) returns jsonb
language sql stable security definer
set search_path = ''
as $$ select app.admin_dashboard((select auth.uid()), p_city_id, p_from, p_to, now()) $$;

revoke all on function
  public.admin_save_tournament(jsonb),
  public.admin_save_category(jsonb),
  public.admin_delete_category(uuid),
  public.admin_list_tournaments(),
  public.admin_list_registrations(uuid),
  public.admin_set_paid(uuid, boolean),
  public.admin_remove_registration(uuid),
  public.admin_move_registration(uuid, uuid),
  public.admin_add_registration(uuid, uuid, uuid),
  public.admin_offer_next(uuid),
  public.admin_dashboard(text, date, date)
from public, anon, authenticated;

grant execute on function
  public.admin_save_tournament(jsonb),
  public.admin_save_category(jsonb),
  public.admin_delete_category(uuid),
  public.admin_list_tournaments(),
  public.admin_list_registrations(uuid),
  public.admin_set_paid(uuid, boolean),
  public.admin_remove_registration(uuid),
  public.admin_move_registration(uuid, uuid),
  public.admin_add_registration(uuid, uuid, uuid),
  public.admin_offer_next(uuid),
  public.admin_dashboard(text, date, date)
to authenticated, service_role;
