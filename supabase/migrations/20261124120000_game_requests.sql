-- Game Requests ("looking for players") and finding players (Milestone 4c;
-- product spec §9.2, §9.4).
--
-- A player posts a time window and an area, other players tap "I'm in", and
-- the poster later turns the request into a real game, which takes the
-- interested players in the order they tapped while spots remain.
-- Additive: new tables and functions; the reminders job is rescheduled under
-- its own name to also expire requests.

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------

create table public.game_requests (
  id uuid primary key default gen_random_uuid(),
  sport_id text not null references public.sports (id),
  city_id text not null references public.cities (id),
  host_id uuid not null references public.profiles (id) on delete cascade,
  -- The time window the poster can play in, as an instant range.
  during tstzrange not null,
  utc_offset_minutes integer not null,
  area text,
  venue_id uuid references public.venues (id),
  -- Other players wanted; the poster is not counted.
  players_needed integer not null check (players_needed between 1 and 29),
  min_level integer not null default 1 check (min_level between 1 and 5),
  max_level integer not null default 5 check (max_level between 1 and 5),
  note text,
  status text not null default 'open' check (status in ('open', 'converted', 'expired', 'cancelled')),
  game_id uuid references public.games (id) on delete set null,
  created_at timestamptz not null default now(),
  constraint game_requests_levels check (min_level <= max_level)
);
create index game_requests_city_idx on public.game_requests (city_id, status);
create index game_requests_host_idx on public.game_requests (host_id);

create table public.game_request_interest (
  request_id uuid not null references public.game_requests (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (request_id, user_id)
);
create index game_request_interest_user_idx on public.game_request_interest (user_id);

-- No client table access: everything goes through the functions.
alter table public.game_requests enable row level security;
alter table public.game_request_interest enable row level security;
revoke all on table public.game_requests, public.game_request_interest from anon, authenticated;
grant all on table public.game_requests, public.game_request_interest to service_role;

-- ---------------------------------------------------------------------------
-- JSON
-- ---------------------------------------------------------------------------

-- What every request notification carries besides its own keys.
create function app.request_note(r public.game_requests) returns jsonb
language sql stable
set search_path = ''
as $$
  select jsonb_build_object(
    'request_id', r.id,
    'sport_id', r.sport_id,
    'starts_local', app.to_local(lower(r.during), r.utc_offset_minutes))
$$;

-- A request as the app receives it; the interested players in the order they
-- tapped. Not stable: it must see rows written earlier in the same statement.
create function app.game_request_json(r public.game_requests, p_user uuid) returns jsonb
language sql
set search_path = ''
as $$
  select jsonb_build_object(
    'id', r.id,
    'sport_id', r.sport_id,
    'city_id', r.city_id,
    'host_id', r.host_id,
    'host_name', (select h.full_name from public.profiles h where h.id = r.host_id),
    'venue_id', r.venue_id,
    'area', r.area,
    'starts_local', app.to_local(lower(r.during), r.utc_offset_minutes),
    'ends_local', app.to_local(upper(r.during), r.utc_offset_minutes),
    'players_needed', r.players_needed,
    'min_level', r.min_level,
    'max_level', r.max_level,
    'note', r.note,
    'status', r.status,
    'game_id', r.game_id,
    'created_at', r.created_at,
    'interested', coalesce(
      (select jsonb_agg(
                jsonb_build_object(
                  'id', i.user_id,
                  'name', pr.full_name,
                  'level', l.level,
                  'reliability', app.reliability(i.user_id, now()))
                order by i.created_at, i.user_id)
       from public.game_request_interest i
       join public.profiles pr on pr.id = i.user_id
       left join public.player_levels l on l.user_id = i.user_id and l.sport_id = r.sport_id
       where i.request_id = r.id),
      '[]'::jsonb),
    'interested_count', (select count(*) from public.game_request_interest i where i.request_id = r.id),
    'my_status', case
      when p_user is null then null
      when r.host_id = p_user then 'host'
      when exists (select 1 from public.game_request_interest i where i.request_id = r.id and i.user_id = p_user)
        then 'interested'
    end)
$$;

-- ---------------------------------------------------------------------------
-- Posting, interest, cancelling
-- ---------------------------------------------------------------------------

create function app.create_game_request(p_user uuid, p_request jsonb, p_now timestamptz)
returns public.game_requests
language plpgsql
set search_path = ''
as $$
declare
  c_max_days_ahead constant integer := 14;
  c_max_duration constant interval := interval '12 hours';

  v_sport public.sports;
  v_needed integer;
  v_min integer;
  v_max integer;
  v_venue_id uuid;
  v_starts timestamp;
  v_ends timestamp;
  v_city_id text;
  v_offset integer;
  v_request public.game_requests;
begin
  if p_user is null then raise exception 'not_authenticated'; end if;
  perform app.require_reliable(p_user, p_now);
  if p_request is null or jsonb_typeof(p_request) <> 'object' then raise exception 'invalid_argument'; end if;

  begin
    v_needed := (p_request->>'players_needed')::integer;
    v_min := coalesce((p_request->>'min_level')::integer, 1);
    v_max := coalesce((p_request->>'max_level')::integer, 5);
    v_venue_id := (p_request->>'venue_id')::uuid;
    v_starts := (p_request->>'starts_local')::timestamp;
    v_ends := (p_request->>'ends_local')::timestamp;
  exception when invalid_text_representation or invalid_datetime_format or datetime_field_overflow
                 or numeric_value_out_of_range then
    raise exception 'invalid_argument';
  end;

  if v_needed is null or v_needed not between 1 and 29
     or v_min not between 1 and 5 or v_max not between 1 and 5 or v_min > v_max
     or v_starts is null or v_ends is null then
    raise exception 'invalid_argument';
  end if;

  select s.* into v_sport from public.sports s where s.id = p_request->>'sport_id' and s.active;
  if not found then raise exception 'not_found'; end if;

  if v_venue_id is not null then
    select v.city_id into v_city_id from public.venues v where v.id = v_venue_id and v.active;
    if not found then raise exception 'not_found'; end if;
  else
    select p.city_id into v_city_id from public.profiles p where p.id = p_user;
    if v_city_id is null then raise exception 'invalid_argument'; end if;
  end if;
  select ci.utc_offset_minutes into v_offset from public.cities ci where ci.id = v_city_id;

  if app.to_instant(v_starts, v_offset) <= p_now then raise exception 'in_past'; end if;
  if v_starts::date - app.to_local(p_now, v_offset)::date > c_max_days_ahead then
    raise exception 'too_far_ahead';
  end if;
  if v_ends <= v_starts or v_ends - v_starts > c_max_duration then raise exception 'invalid_argument'; end if;

  insert into public.game_requests (
    sport_id, city_id, host_id, during, utc_offset_minutes, area, venue_id, players_needed,
    min_level, max_level, note, created_at)
  values (
    v_sport.id, v_city_id, p_user,
    tstzrange(app.to_instant(v_starts, v_offset), app.to_instant(v_ends, v_offset), '[)'),
    v_offset, nullif(btrim(p_request->>'area'), ''), v_venue_id, v_needed,
    v_min, v_max, nullif(btrim(p_request->>'note'), ''), p_now)
  returning * into v_request;
  return v_request;
end $$;

-- "I'm in". The request row lock makes this and a conversion take turns, so
-- nobody is added to a request that was just converted.
create function app.request_interest(p_user uuid, p_request_id uuid, p_now timestamptz)
returns public.game_requests
language plpgsql
set search_path = ''
as $$
declare
  v_request public.game_requests;
begin
  if p_user is null then raise exception 'not_authenticated'; end if;
  perform app.require_reliable(p_user, p_now);

  select r.* into v_request from public.game_requests r
  where r.id = p_request_id and r.status = 'open' and upper(r.during) > p_now
  for update;
  if not found then raise exception 'not_found'; end if;
  if v_request.host_id = p_user then raise exception 'invalid_argument'; end if;
  if exists (select 1 from public.game_request_interest i where i.request_id = p_request_id and i.user_id = p_user) then
    raise exception 'already_joined';
  end if;

  insert into public.game_request_interest (request_id, user_id, created_at) values (p_request_id, p_user, p_now);
  perform app.notify(v_request.host_id, 'request_interest', 'requests',
    app.request_note(v_request) || jsonb_build_object('actor_name', (select p.full_name from public.profiles p where p.id = p_user)),
    p_now);
  return v_request;
end $$;

create function app.withdraw_interest(p_user uuid, p_request_id uuid) returns public.game_requests
language plpgsql
set search_path = ''
as $$
declare
  v_request public.game_requests;
begin
  if p_user is null then raise exception 'not_authenticated'; end if;
  select r.* into v_request from public.game_requests r where r.id = p_request_id and r.status = 'open' for update;
  if not found then raise exception 'not_found'; end if;
  delete from public.game_request_interest i where i.request_id = p_request_id and i.user_id = p_user;
  if not found then raise exception 'not_found'; end if;
  return v_request;
end $$;

-- The poster only; anyone else sees the request as not theirs (not_found).
create function app.remove_interested(p_user uuid, p_request_id uuid, p_member uuid) returns public.game_requests
language plpgsql
set search_path = ''
as $$
declare
  v_request public.game_requests;
begin
  if p_user is null then raise exception 'not_authenticated'; end if;
  select r.* into v_request from public.game_requests r
  where r.id = p_request_id and r.host_id = p_user and r.status = 'open' for update;
  if not found then raise exception 'not_found'; end if;
  delete from public.game_request_interest i where i.request_id = p_request_id and i.user_id = p_member;
  if not found then raise exception 'not_found'; end if;
  return v_request;
end $$;

create function app.cancel_game_request(p_user uuid, p_request_id uuid) returns public.game_requests
language plpgsql
set search_path = ''
as $$
declare
  v_request public.game_requests;
begin
  if p_user is null then raise exception 'not_authenticated'; end if;
  update public.game_requests r set status = 'cancelled'
  where r.id = p_request_id and r.host_id = p_user and r.status = 'open'
  returning r.* into v_request;
  if not found then raise exception 'not_found'; end if;
  return v_request;
end $$;

-- ---------------------------------------------------------------------------
-- Converting a request into a game
-- ---------------------------------------------------------------------------

-- p_place: booking_id, or venue_id, or meeting_point (+ meeting_lat/lng);
-- optional spots (default 1 + players_needed), starts_local/ends_local for
-- place-only sports (default: the request's window), and visibility, pace,
-- distance_km. A place with none of the three keys falls back to the
-- request's own venue, if it has one. The game is made by app.create_game
-- (same checks as any game), then, holding the game's row lock, the
-- interested players are added in the order they tapped while spots remain.
create function app.convert_game_request(p_user uuid, p_request_id uuid, p_place jsonb, p_now timestamptz)
returns public.games
language plpgsql
set search_path = ''
as $$
declare
  v_request public.game_requests;
  v_place jsonb := coalesce(p_place, '{}'::jsonb);
  v_spec jsonb;
  v_game public.games;
  v_user uuid;
  v_count integer;
  v_added boolean;
begin
  if p_user is null then raise exception 'not_authenticated'; end if;
  if jsonb_typeof(v_place) <> 'object' then raise exception 'invalid_argument'; end if;

  select r.* into v_request from public.game_requests r
  where r.id = p_request_id and r.host_id = p_user and r.status = 'open' for update;
  if not found then raise exception 'not_found'; end if;

  v_spec := jsonb_build_object(
    'sport_id', v_request.sport_id,
    'min_level', v_request.min_level,
    'max_level', v_request.max_level,
    'note', v_request.note,
    'spots', coalesce(v_place->'spots', to_jsonb(1 + v_request.players_needed)),
    'starts_local', coalesce(v_place->'starts_local', to_jsonb(app.to_local(lower(v_request.during), v_request.utc_offset_minutes))),
    'ends_local', coalesce(v_place->'ends_local', to_jsonb(app.to_local(upper(v_request.during), v_request.utc_offset_minutes))))
    || (select coalesce(jsonb_object_agg(e.key, e.value), '{}'::jsonb)
        from jsonb_each(v_place) e
        where e.key in ('booking_id', 'venue_id', 'meeting_point', 'meeting_lat', 'meeting_lng',
                        'visibility', 'pace', 'distance_km'));
  if not (v_spec ? 'booking_id' or v_spec ? 'venue_id' or v_spec ? 'meeting_point') and v_request.venue_id is not null then
    v_spec := v_spec || jsonb_build_object('venue_id', v_request.venue_id);
  end if;

  v_game := app.create_game(p_user, v_spec, p_now);

  -- Every route that adds a participant takes the game's row lock first.
  select g.* into v_game from public.games g where g.id = v_game.id for update;

  select count(*) into v_count from public.game_participants p where p.game_id = v_game.id;
  for v_user in
    select i.user_id from public.game_request_interest i
    where i.request_id = p_request_id
    order by i.created_at, i.user_id
  loop
    v_added := false;
    if v_count < v_game.spots
       and not exists (select 1 from public.game_participants p where p.game_id = v_game.id and p.user_id = v_user) then
      insert into public.game_participants (game_id, user_id, joined_at) values (v_game.id, v_user, p_now);
      v_count := v_count + 1;
      v_added := true;
    end if;
    perform app.notify(v_user, 'request_converted', 'requests',
      app.request_note(v_request) || jsonb_build_object('game_id', v_game.id, 'added', v_added), p_now);
  end loop;

  update public.game_requests r set status = 'converted', game_id = v_game.id where r.id = p_request_id;
  return v_game;
end $$;

-- ---------------------------------------------------------------------------
-- Scheduled work and lists
-- ---------------------------------------------------------------------------

-- Open requests whose window has ended: expired, and the poster and the
-- interested players told once. Returns how many requests expired.
create function app.expire_game_requests(p_now timestamptz) returns integer
language plpgsql
set search_path = ''
as $$
declare
  v_request public.game_requests;
  v_user uuid;
  v_count integer := 0;
begin
  for v_request in
    update public.game_requests r set status = 'expired'
    where r.status = 'open' and upper(r.during) <= p_now
    returning r.*
  loop
    perform app.notify(v_request.host_id, 'request_expired', 'requests', app.request_note(v_request), p_now);
    for v_user in select i.user_id from public.game_request_interest i where i.request_id = v_request.id loop
      perform app.notify(v_user, 'request_expired', 'requests', app.request_note(v_request), p_now);
    end loop;
    v_count := v_count + 1;
  end loop;
  return v_count;
end $$;

-- The reminders job also expires requests (scheduling by the same name
-- replaces the command).
do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron;
    execute $job$
      select cron.schedule(
        'actra-send-reminders',
        '*/10 * * * *',
        'select app.send_reminders(now()), app.complete_games(now()), app.expire_game_requests(now())')
    $job$;
  end if;
end $$;

-- In the city: open requests whose window has not ended. Anywhere: the
-- player's own open ones. Earliest first.
create function app.list_game_requests(p_user uuid, p_city_id text, p_now timestamptz) returns setof jsonb
language sql
set search_path = ''
as $$
  select app.game_request_json(r, p_user)
  from public.game_requests r
  where r.status = 'open'
    and upper(r.during) > p_now
    and (r.city_id = p_city_id or (p_user is not null and r.host_id = p_user))
  order by lower(r.during), r.id
$$;

-- ---------------------------------------------------------------------------
-- Finding players
-- ---------------------------------------------------------------------------

-- A player as others see them: no phone, no contact details. games_played
-- counts the games the player took part in that have been completed.
create function app.player_json(pr public.profiles) returns jsonb
language sql
set search_path = ''
as $$
  select jsonb_build_object(
    'id', pr.id,
    'name', pr.full_name,
    'city_id', pr.city_id,
    'levels', coalesce(
      (select jsonb_object_agg(l.sport_id, l.level) from public.player_levels l where l.user_id = pr.id),
      '{}'::jsonb),
    'reliability', app.reliability(pr.id, now()),
    'games_played', (
      select count(*) from public.game_participants gp
      join public.games g on g.id = gp.game_id
      where gp.user_id = pr.id and g.completed_at is not null))
$$;

-- Players in the city who have not hidden themselves, not the caller, by
-- name and by level in one sport (no level row counts as 1). Name order.
create function app.list_players(
  p_user uuid, p_city_id text, p_sport_id text, p_min_level integer, p_max_level integer,
  p_query text, p_limit integer) returns setof jsonb
language sql
set search_path = ''
as $$
  select app.player_json(pr)
  from public.profiles pr
  where pr.city_id = p_city_id
    and not pr.hidden_from_search
    and pr.id is distinct from p_user
    and (nullif(btrim(p_query), '') is null
         or pr.full_name ilike '%' || replace(replace(replace(btrim(p_query), '\', '\\'), '%', '\%'), '_', '\_') || '%')
    and (p_sport_id is null
         or coalesce((select l.level from public.player_levels l where l.user_id = pr.id and l.sport_id = p_sport_id), 1)
            between coalesce(p_min_level, 1) and coalesce(p_max_level, 5))
  order by pr.full_name, pr.id
  limit least(greatest(coalesce(p_limit, 50), 1), 100)
$$;

-- Hidden players are only hidden from the list; their profile opens.
create function app.player_profile(p_user uuid, p_id uuid) returns jsonb
language sql
set search_path = ''
as $$
  select app.player_json(pr) from public.profiles pr where pr.id = p_id
$$;

-- ---------------------------------------------------------------------------
-- What the app calls
-- ---------------------------------------------------------------------------

create function public.create_game_request(p_request jsonb) returns jsonb
language sql security definer
set search_path = ''
as $$ select app.game_request_json(app.create_game_request((select auth.uid()), p_request, now()), (select auth.uid())) $$;

-- null when the request does not exist.
create function public.get_game_request(p_request_id uuid) returns jsonb
language sql security definer
set search_path = ''
as $$
  select app.game_request_json(r, (select auth.uid())) from public.game_requests r where r.id = p_request_id
$$;

create function public.list_game_requests(p_city_id text) returns setof jsonb
language sql security definer
set search_path = ''
as $$ select app.list_game_requests((select auth.uid()), p_city_id, now()) $$;

create function public.request_interest(p_request_id uuid) returns jsonb
language sql security definer
set search_path = ''
as $$ select app.game_request_json(app.request_interest((select auth.uid()), p_request_id, now()), (select auth.uid())) $$;

create function public.withdraw_interest(p_request_id uuid) returns jsonb
language sql security definer
set search_path = ''
as $$ select app.game_request_json(app.withdraw_interest((select auth.uid()), p_request_id), (select auth.uid())) $$;

create function public.remove_interested(p_request_id uuid, p_user_id uuid) returns jsonb
language sql security definer
set search_path = ''
as $$ select app.game_request_json(app.remove_interested((select auth.uid()), p_request_id, p_user_id), (select auth.uid())) $$;

create function public.cancel_game_request(p_request_id uuid) returns jsonb
language sql security definer
set search_path = ''
as $$ select app.game_request_json(app.cancel_game_request((select auth.uid()), p_request_id), (select auth.uid())) $$;

-- Returns the new game.
create function public.convert_game_request(p_request_id uuid, p_place jsonb) returns jsonb
language sql security definer
set search_path = ''
as $$ select app.game_json(app.convert_game_request((select auth.uid()), p_request_id, p_place, now()), (select auth.uid())) $$;

create function public.list_players(
  p_city_id text, p_sport_id text default null, p_min_level integer default 1, p_max_level integer default 5,
  p_query text default null, p_limit integer default 50) returns setof jsonb
language sql security definer
set search_path = ''
as $$ select app.list_players((select auth.uid()), p_city_id, p_sport_id, p_min_level, p_max_level, p_query, p_limit) $$;

create function public.player_profile(p_user_id uuid) returns jsonb
language sql security definer
set search_path = ''
as $$ select app.player_profile((select auth.uid()), p_user_id) $$;

revoke all on function
  public.create_game_request(jsonb),
  public.get_game_request(uuid),
  public.list_game_requests(text),
  public.request_interest(uuid),
  public.withdraw_interest(uuid),
  public.remove_interested(uuid, uuid),
  public.cancel_game_request(uuid),
  public.convert_game_request(uuid, jsonb),
  public.list_players(text, text, integer, integer, text, integer),
  public.player_profile(uuid)
from public, anon, authenticated;

grant execute on function
  public.create_game_request(jsonb),
  public.get_game_request(uuid),
  public.list_game_requests(text),
  public.request_interest(uuid),
  public.withdraw_interest(uuid),
  public.remove_interested(uuid, uuid),
  public.cancel_game_request(uuid),
  public.convert_game_request(uuid, jsonb),
  public.list_players(text, text, integer, integer, text, integer),
  public.player_profile(uuid)
to authenticated, service_role;
