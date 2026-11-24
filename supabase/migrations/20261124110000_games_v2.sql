-- Games for every sport type (Milestone 4b): booked courts, place-only
-- venues and map meeting points; requests to join, invites, host tools and
-- invite-only visibility (product spec §9.1, §14).
--
-- Additive: new columns and tables; the M2 functions that change shape are
-- replaced. app.join_game and app.leave_game gain the clock argument (for
-- reliability and notifications), and app.game_json gains the viewing player,
-- so their old versions are dropped. The four M2 public wrappers keep their
-- signatures (`create or replace`, grants restated below).
-- Players no longer read the game tables directly: every read goes through
-- the functions, which apply visibility.

-- ---------------------------------------------------------------------------
-- Columns
-- ---------------------------------------------------------------------------

alter table public.games
  alter column venue_id drop not null,
  add column kind text not null default 'booked' check (kind in ('booked', 'place', 'map_point')),
  add column visibility text not null default 'public' check (visibility in ('public', 'invite_only')),
  add column meeting_point text,
  add column meeting_lat double precision,
  add column meeting_lng double precision,
  add column distance_km numeric(5, 1),
  add column pace text,
  add column reminded_at timestamptz,
  add column completed_at timestamptz,
  add constraint games_venue_for_venue_kinds check (kind not in ('booked', 'place') or venue_id is not null),
  add constraint games_meeting_point_for_map_point check (kind <> 'map_point' or meeting_point is not null);

create index games_booking_idx on public.games (booking_id) where booking_id is not null;

-- ---------------------------------------------------------------------------
-- Requests to join and invites
-- ---------------------------------------------------------------------------

create table public.game_join_requests (
  id uuid primary key default gen_random_uuid(),
  game_id uuid not null references public.games (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  status text not null default 'pending' check (status in ('pending', 'approved', 'declined', 'withdrawn')),
  created_at timestamptz not null default now(),
  decided_at timestamptz
);
-- At most one open request per player and game; old ones stay as history.
create unique index game_join_requests_pending_idx on public.game_join_requests (game_id, user_id) where status = 'pending';
create index game_join_requests_user_idx on public.game_join_requests (user_id);

create table public.game_invites (
  game_id uuid not null references public.games (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  invited_by uuid not null references public.profiles (id) on delete cascade,
  status text not null default 'pending' check (status in ('pending', 'accepted', 'declined')),
  created_at timestamptz not null default now(),
  primary key (game_id, user_id)
);
create index game_invites_user_idx on public.game_invites (user_id);

alter table public.game_join_requests enable row level security;
alter table public.game_invites enable row level security;
revoke all on table public.game_join_requests, public.game_invites from anon, authenticated;
grant all on table public.game_join_requests, public.game_invites to service_role;

-- Invite-only games must not leak through the tables: functions only.
revoke select on table public.games, public.game_participants from authenticated;
drop policy "signed-in players see games" on public.games;
drop policy "signed-in players see who is playing" on public.game_participants;

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

-- What every game notification carries.
create function app.game_note(g public.games) returns jsonb
language sql stable
set search_path = ''
as $$
  select jsonb_build_object(
    'game_id', g.id,
    'sport_id', g.sport_id,
    'starts_local', app.to_local(lower(g.during), g.utc_offset_minutes))
$$;

-- Public games, and invite-only ones the player is part of: host,
-- participant, invited (whatever the answer) or has asked to join.
-- Not stable: it must see rows written earlier in the same statement.
create function app.can_see_game(p_user uuid, g public.games) returns boolean
language sql
set search_path = ''
as $$
  select g.visibility = 'public'
    or (p_user is not null and (
      g.host_id = p_user
      or exists (select 1 from public.game_participants p where p.game_id = g.id and p.user_id = p_user)
      or exists (select 1 from public.game_invites i where i.game_id = g.id and i.user_id = p_user)
      or exists (select 1 from public.game_join_requests r where r.game_id = g.id and r.user_id = p_user)))
$$;

-- Notifies every participant but p_except; returns how many were addressed.
create function app.notify_game(g public.games, p_kind text, p_except uuid, p_now timestamptz) returns integer
language plpgsql
set search_path = ''
as $$
declare
  v_user uuid;
  v_count integer := 0;
begin
  for v_user in
    select p.user_id from public.game_participants p
    where p.game_id = g.id and p.user_id is distinct from p_except
  loop
    perform app.notify(v_user, p_kind, 'games', app.game_note(g), p_now);
    v_count := v_count + 1;
  end loop;
  return v_count;
end $$;

-- Called right after a player was added: when that filled the game, the
-- others hear it is full (the player who filled it does not).
create function app.notify_if_full(g public.games, p_filler uuid, p_now timestamptz) returns void
language plpgsql
set search_path = ''
as $$
begin
  if (select count(*) from public.game_participants p where p.game_id = g.id) >= g.spots then
    perform app.notify_game(g, 'game_full', p_filler, p_now);
  end if;
end $$;

-- A player became a participant: their open invite is accepted and any open
-- request is closed, so the host's list and my_status stay true.
create function app.close_pending_for(p_game_id uuid, p_user uuid, p_now timestamptz) returns void
language sql
set search_path = ''
as $$
  update public.game_invites i set status = 'accepted'
  where i.game_id = p_game_id and i.user_id = p_user and i.status = 'pending';
  update public.game_join_requests r set status = 'approved', decided_at = p_now
  where r.game_id = p_game_id and r.user_id = p_user and r.status = 'pending';
$$;

-- ---------------------------------------------------------------------------
-- The game as the app receives it, for one viewing player
-- ---------------------------------------------------------------------------

drop function app.game_json(public.games);
drop function app.join_game(uuid, uuid);
drop function app.leave_game(uuid, uuid);

-- The host first, then the others in the order they joined. Reliability is
-- as of now(): the function has no clock argument. Not stable on purpose:
-- it must see a participant added earlier in the same statement. Pending
-- requests go to the host only. Never a phone number.
create function app.game_json(g public.games, p_user uuid) returns jsonb
language sql
set search_path = ''
as $$
  select jsonb_build_object(
    'id', g.id,
    'sport_id', g.sport_id,
    'city_id', g.city_id,
    'venue_id', g.venue_id,
    'host_id', g.host_id,
    'kind', g.kind,
    'visibility', g.visibility,
    'status', g.status,
    'starts_local', app.to_local(lower(g.during), g.utc_offset_minutes),
    'ends_local', app.to_local(upper(g.during), g.utc_offset_minutes),
    'spots', g.spots,
    'min_level', g.min_level,
    'max_level', g.max_level,
    'price_per_player', g.price_per_player,
    'booking_id', g.booking_id,
    'note', g.note,
    'meeting_point', g.meeting_point,
    'meeting_lat', g.meeting_lat,
    'meeting_lng', g.meeting_lng,
    'distance_km', g.distance_km,
    'pace', g.pace,
    'my_status', case
      when p_user is null then null
      when g.host_id = p_user then 'host'
      when exists (select 1 from public.game_participants p where p.game_id = g.id and p.user_id = p_user) then 'participant'
      when exists (select 1 from public.game_invites i
                   where i.game_id = g.id and i.user_id = p_user and i.status = 'pending') then 'invited'
      when exists (select 1 from public.game_join_requests r
                   where r.game_id = g.id and r.user_id = p_user and r.status = 'pending') then 'requested'
    end,
    -- What a requester needs to withdraw: their own pending request.
    'my_request_id', case when p_user is null then null else
      (select r.id from public.game_join_requests r
       where r.game_id = g.id and r.user_id = p_user and r.status = 'pending') end,
    'participant_ids', coalesce(
      (select jsonb_agg(p.user_id order by (p.user_id = g.host_id) desc, p.joined_at, p.user_id)
       from public.game_participants p where p.game_id = g.id),
      '[]'::jsonb),
    'participants', coalesce(
      (select jsonb_agg(
                jsonb_build_object(
                  'id', p.user_id,
                  'name', pr.full_name,
                  'level', l.level,
                  'reliability', app.reliability(p.user_id, now()))
                order by (p.user_id = g.host_id) desc, p.joined_at, p.user_id)
       from public.game_participants p
       join public.profiles pr on pr.id = p.user_id
       left join public.player_levels l on l.user_id = p.user_id and l.sport_id = g.sport_id
       where p.game_id = g.id),
      '[]'::jsonb))
  || case when p_user is not null and p_user = g.host_id then
       jsonb_build_object('join_requests', coalesce(
         (select jsonb_agg(
                   jsonb_build_object(
                     'id', r.id,
                     'user_id', r.user_id,
                     'name', pr.full_name,
                     'level', l.level,
                     'reliability', app.reliability(r.user_id, now()),
                     'created_at', r.created_at)
                   order by r.created_at, r.id)
          from public.game_join_requests r
          join public.profiles pr on pr.id = r.user_id
          left join public.player_levels l on l.user_id = r.user_id and l.sport_id = g.sport_id
          where r.game_id = g.id and r.status = 'pending'),
         '[]'::jsonb))
     else '{}'::jsonb end
$$;

-- ---------------------------------------------------------------------------
-- Creating a game
-- ---------------------------------------------------------------------------

-- Bookable sports sit on the host's own confirmed app booking (time, venue,
-- city and price from it). Place-only sports take a venue (kind `place`) or a
-- meeting point (kind `map_point`, in the host's city) and their own times.
create function app.create_game(p_user uuid, p_game jsonb, p_now timestamptz) returns public.games
language plpgsql
set search_path = ''
as $$
declare
  c_max_days_ahead constant integer := 14;
  c_max_duration constant interval := interval '12 hours';

  v_sport public.sports;
  v_spots integer;
  v_min integer;
  v_max integer;
  v_visibility text;
  v_note text;
  v_distance numeric;
  v_pace text;
  v_booking_id uuid;
  v_venue_id uuid;
  v_meeting text;
  v_lat double precision;
  v_lng double precision;
  v_starts timestamp;
  v_ends timestamp;
  v_booking public.bookings;
  v_kind text;
  v_city_id text;
  v_offset integer;
  v_during tstzrange;
  v_price integer;
  v_game public.games;
begin
  if p_user is null then raise exception 'not_authenticated'; end if;
  perform app.require_reliable(p_user, p_now);
  if p_game is null or jsonb_typeof(p_game) <> 'object' then raise exception 'invalid_argument'; end if;

  begin
    v_spots := (p_game->>'spots')::integer;
    v_min := coalesce((p_game->>'min_level')::integer, 1);
    v_max := coalesce((p_game->>'max_level')::integer, 5);
    v_distance := (p_game->>'distance_km')::numeric;
    v_lat := (p_game->>'meeting_lat')::double precision;
    v_lng := (p_game->>'meeting_lng')::double precision;
    v_booking_id := (p_game->>'booking_id')::uuid;
    v_venue_id := (p_game->>'venue_id')::uuid;
    v_starts := (p_game->>'starts_local')::timestamp;
    v_ends := (p_game->>'ends_local')::timestamp;
  exception when invalid_text_representation or invalid_datetime_format or datetime_field_overflow
                 or numeric_value_out_of_range then
    raise exception 'invalid_argument';
  end;
  v_visibility := coalesce(p_game->>'visibility', 'public');
  v_note := nullif(btrim(p_game->>'note'), '');
  v_pace := nullif(btrim(p_game->>'pace'), '');
  -- Checked as stored (numeric(5,1)), so 9999.95 is refused here, not by the column.
  v_distance := round(v_distance, 1);

  if v_spots is null or v_spots not between 2 and 30
     or v_min not between 1 and 5 or v_max not between 1 and 5 or v_min > v_max
     or v_visibility not in ('public', 'invite_only')
     or (v_distance is not null and (v_distance <= 0 or v_distance >= 10000)) then
    raise exception 'invalid_argument';
  end if;

  select s.* into v_sport from public.sports s where s.id = p_game->>'sport_id' and s.active;
  if not found then raise exception 'not_found'; end if;

  if v_sport.bookable then
    if v_booking_id is null then raise exception 'booking_not_usable'; end if;
    -- The lock makes two simultaneous games on one booking take turns.
    select b.* into v_booking from public.bookings b where b.id = v_booking_id for update;
    if not found
       or v_booking.user_id is distinct from p_user
       or v_booking.source <> 'app'
       or v_booking.status <> 'confirmed'
       or lower(v_booking.during) <= p_now
       or (select c.sport_id from public.courts c where c.id = v_booking.court_id) <> v_sport.id then
      raise exception 'booking_not_usable';
    end if;
    if exists (select 1 from public.games g where g.booking_id = v_booking.id and g.status = 'open') then
      raise exception 'game_exists';
    end if;

    v_kind := 'booked';
    v_venue_id := v_booking.venue_id;
    select v.city_id into v_city_id from public.venues v where v.id = v_booking.venue_id;
    v_offset := v_booking.utc_offset_minutes;
    v_during := v_booking.during;
    v_price := ceil(v_booking.total_price::numeric / v_spots)::integer;
    v_meeting := null;
    v_lat := null;
    v_lng := null;
  else
    if v_venue_id is not null then
      select v.city_id into v_city_id from public.venues v where v.id = v_venue_id and v.active;
      if not found then raise exception 'not_found'; end if;
      v_kind := 'place';
      v_meeting := null;
      v_lat := null;
      v_lng := null;
    else
      v_meeting := nullif(btrim(p_game->>'meeting_point'), '');
      if v_meeting is null
         or (v_lat is null) <> (v_lng is null)
         or v_lat not between -90 and 90
         or v_lng not between -180 and 180 then
        raise exception 'invalid_argument';
      end if;
      select p.city_id into v_city_id from public.profiles p where p.id = p_user;
      -- A meeting point needs the player's city to be listed anywhere.
      if v_city_id is null then raise exception 'invalid_argument'; end if;
      v_kind := 'map_point';
    end if;

    select ci.utc_offset_minutes into v_offset from public.cities ci where ci.id = v_city_id;
    if v_starts is null or v_ends is null then raise exception 'invalid_argument'; end if;
    if app.to_instant(v_starts, v_offset) <= p_now then raise exception 'in_past'; end if;
    if v_starts::date - app.to_local(p_now, v_offset)::date > c_max_days_ahead then
      raise exception 'too_far_ahead';
    end if;
    if v_ends <= v_starts or v_ends - v_starts > c_max_duration then raise exception 'invalid_argument'; end if;
    v_during := tstzrange(app.to_instant(v_starts, v_offset), app.to_instant(v_ends, v_offset), '[)');
    v_price := null;
    v_booking_id := null;
  end if;

  insert into public.games (
    sport_id, city_id, venue_id, host_id, booking_id, during, utc_offset_minutes, spots, min_level, max_level,
    price_per_player, note, kind, visibility, meeting_point, meeting_lat, meeting_lng, distance_km, pace, created_at)
  values (
    v_sport.id, v_city_id, v_venue_id, p_user, v_booking_id, v_during, v_offset, v_spots, v_min, v_max,
    v_price, v_note, v_kind, v_visibility, v_meeting, v_lat, v_lng, v_distance, v_pace, p_now)
  returning * into v_game;

  insert into public.game_participants (game_id, user_id, joined_at) values (v_game.id, p_user, p_now);
  return v_game;
end $$;

-- ---------------------------------------------------------------------------
-- Joining and leaving
-- ---------------------------------------------------------------------------

-- One-tap join for players inside the level range (a player with no level
-- for the sport counts as level 1). An invite opens an invite-only game and
-- skips the level check.
create function app.join_game(p_user uuid, p_game_id uuid, p_now timestamptz) returns public.games
language plpgsql
set search_path = ''
as $$
declare
  v_game public.games;
  v_invited boolean;
  v_level integer;
begin
  if p_user is null then raise exception 'not_authenticated'; end if;
  perform app.require_reliable(p_user, p_now);

  -- The row lock makes simultaneous joins and approvals take turns, so the
  -- last spot goes to exactly one player.
  select g.* into v_game from public.games g where g.id = p_game_id and g.status = 'open' for update;
  -- A game that has started takes nobody new, invited or not.
  if not found or lower(v_game.during) <= p_now then raise exception 'not_found'; end if;

  v_invited := exists (select 1 from public.game_invites i
                       where i.game_id = p_game_id and i.user_id = p_user and i.status = 'pending');
  if v_game.visibility = 'invite_only' and not v_invited then raise exception 'not_found'; end if;

  if exists (select 1 from public.game_participants p where p.game_id = p_game_id and p.user_id = p_user) then
    raise exception 'already_joined';
  end if;
  if (select count(*) from public.game_participants p where p.game_id = p_game_id) >= v_game.spots then
    raise exception 'full';
  end if;

  if not v_invited then
    select coalesce((select l.level from public.player_levels l
                     where l.user_id = p_user and l.sport_id = v_game.sport_id), 1) into v_level;
    if v_level < v_game.min_level or v_level > v_game.max_level then
      raise exception 'level_out_of_range';
    end if;
  end if;

  insert into public.game_participants (game_id, user_id, joined_at) values (p_game_id, p_user, p_now);
  perform app.close_pending_for(p_game_id, p_user, p_now);

  perform app.notify(v_game.host_id, 'game_joined', 'games',
    app.game_note(v_game) || jsonb_build_object('actor_name', (select p.full_name from public.profiles p where p.id = p_user)),
    p_now);
  perform app.notify_if_full(v_game, p_user, p_now);
  return v_game;
end $$;

-- Leaving inside six hours of the start of a game that is still on counts
-- as a late cancellation.
create function app.leave_game(p_user uuid, p_game_id uuid, p_now timestamptz) returns public.games
language plpgsql
set search_path = ''
as $$
declare
  c_free_window constant interval := interval '6 hours';
  v_game public.games;
begin
  if p_user is null then raise exception 'not_authenticated'; end if;

  select g.* into v_game from public.games g where g.id = p_game_id for update;
  if not found then raise exception 'not_found'; end if;
  if v_game.host_id = p_user then raise exception 'host_cannot_leave'; end if;

  delete from public.game_participants p where p.game_id = p_game_id and p.user_id = p_user;
  if not found then raise exception 'not_participant'; end if;

  if v_game.status = 'open' and v_game.completed_at is null and upper(v_game.during) > p_now then
    if lower(v_game.during) - p_now < c_free_window then
      perform app.reliability_event(p_user, 'late_cancel', v_game.id::text, p_now);
    end if;
    perform app.notify(v_game.host_id, 'game_left', 'games',
      app.game_note(v_game) || jsonb_build_object('actor_name', (select p.full_name from public.profiles p where p.id = p_user)),
      p_now);
  end if;
  return v_game;
end $$;

-- ---------------------------------------------------------------------------
-- Requests to join
-- ---------------------------------------------------------------------------

create function app.request_to_join(p_user uuid, p_game_id uuid, p_now timestamptz) returns public.game_join_requests
language plpgsql
set search_path = ''
as $$
declare
  v_game public.games;
  v_request public.game_join_requests;
begin
  if p_user is null then raise exception 'not_authenticated'; end if;
  perform app.require_reliable(p_user, p_now);

  select g.* into v_game from public.games g where g.id = p_game_id for update;
  if not found or not app.can_see_game(p_user, v_game) or v_game.status <> 'open' or lower(v_game.during) <= p_now then
    raise exception 'not_found';
  end if;
  if exists (select 1 from public.game_participants p where p.game_id = p_game_id and p.user_id = p_user) then
    raise exception 'already_joined';
  end if;
  if exists (select 1 from public.game_join_requests r
             where r.game_id = p_game_id and r.user_id = p_user and r.status = 'pending') then
    raise exception 'already_requested';
  end if;
  if (select count(*) from public.game_participants p where p.game_id = p_game_id) >= v_game.spots then
    raise exception 'full';
  end if;

  begin
    insert into public.game_join_requests (game_id, user_id, created_at)
    values (p_game_id, p_user, p_now)
    returning * into v_request;
  exception when unique_violation then
    raise exception 'already_requested';
  end;

  perform app.notify(v_game.host_id, 'join_request', 'games',
    app.game_note(v_game) || jsonb_build_object(
      'request_id', v_request.id,
      'actor_name', (select p.full_name from public.profiles p where p.id = p_user)),
    p_now);
  return v_request;
end $$;

-- The requester takes back a pending request. Returns the game.
create function app.withdraw_join_request(p_user uuid, p_request_id uuid) returns public.games
language plpgsql
set search_path = ''
as $$
declare
  v_game_id uuid;
begin
  if p_user is null then raise exception 'not_authenticated'; end if;
  update public.game_join_requests r set status = 'withdrawn', decided_at = now()
  where r.id = p_request_id and r.user_id = p_user and r.status = 'pending'
  returning r.game_id into v_game_id;
  if not found then raise exception 'not_found'; end if;
  return (select g from public.games g where g.id = v_game_id);
end $$;

create function app.decide_join_request(p_user uuid, p_request_id uuid, p_approve boolean, p_now timestamptz)
returns public.games
language plpgsql
set search_path = ''
as $$
declare
  v_game_id uuid;
  v_game public.games;
  v_request public.game_join_requests;
begin
  if p_user is null then raise exception 'not_authenticated'; end if;
  if p_approve is null then raise exception 'invalid_argument'; end if;

  select r.game_id into v_game_id from public.game_join_requests r where r.id = p_request_id;
  if not found then raise exception 'not_found'; end if;

  -- Game first, then the request: the same order as join_game, so an
  -- approval and a join for the last spot take turns.
  select g.* into v_game from public.games g where g.id = v_game_id for update;
  if not found or v_game.host_id <> p_user then raise exception 'not_found'; end if;
  select r.* into v_request from public.game_join_requests r where r.id = p_request_id for update;
  if v_request.status <> 'pending' then raise exception 'not_found'; end if;

  if p_approve then
    if v_game.status <> 'open' or lower(v_game.during) <= p_now then raise exception 'not_found'; end if;
    if exists (select 1 from public.game_participants p
               where p.game_id = v_game.id and p.user_id = v_request.user_id) then
      raise exception 'already_joined';
    end if;
    if (select count(*) from public.game_participants p where p.game_id = v_game.id) >= v_game.spots then
      raise exception 'full';
    end if;
    -- The requester may have been blocked since asking.
    perform app.require_reliable(v_request.user_id, p_now);

    insert into public.game_participants (game_id, user_id, joined_at) values (v_game.id, v_request.user_id, p_now);
    perform app.close_pending_for(v_game.id, v_request.user_id, p_now);
    perform app.notify(v_request.user_id, 'join_approved', 'games', app.game_note(v_game), p_now);
    perform app.notify_if_full(v_game, v_request.user_id, p_now);
  else
    update public.game_join_requests r set status = 'declined', decided_at = p_now where r.id = p_request_id;
    perform app.notify(v_request.user_id, 'join_declined', 'games', app.game_note(v_game), p_now);
  end if;
  return v_game;
end $$;

-- ---------------------------------------------------------------------------
-- Invites
-- ---------------------------------------------------------------------------

create function app.invite_to_game(p_user uuid, p_game_id uuid, p_invitee uuid, p_now timestamptz) returns public.games
language plpgsql
set search_path = ''
as $$
declare
  v_game public.games;
  v_previous text;
begin
  if p_user is null then raise exception 'not_authenticated'; end if;

  select g.* into v_game from public.games g where g.id = p_game_id for update;
  if not found or v_game.host_id <> p_user or v_game.status <> 'open' or lower(v_game.during) <= p_now then
    raise exception 'not_found';
  end if;
  if not exists (select 1 from public.profiles p where p.id = p_invitee) then raise exception 'not_found'; end if;
  if exists (select 1 from public.game_participants p where p.game_id = p_game_id and p.user_id = p_invitee) then
    raise exception 'already_joined';
  end if;

  select i.status into v_previous from public.game_invites i where i.game_id = p_game_id and i.user_id = p_invitee;
  insert into public.game_invites (game_id, user_id, invited_by, status, created_at)
  values (p_game_id, p_invitee, p_user, 'pending', p_now)
  on conflict (game_id, user_id) do update
    set status = 'pending', invited_by = excluded.invited_by, created_at = excluded.created_at;

  -- Inviting again while the invite is still open sends nothing new.
  if v_previous is distinct from 'pending' then
    perform app.notify(p_invitee, 'game_invite', 'invites',
      app.game_note(v_game) || jsonb_build_object('actor_name', (select p.full_name from public.profiles p where p.id = p_user)),
      p_now);
  end if;
  return v_game;
end $$;

create function app.decline_invite(p_user uuid, p_game_id uuid) returns public.games
language plpgsql
set search_path = ''
as $$
begin
  if p_user is null then raise exception 'not_authenticated'; end if;
  update public.game_invites i set status = 'declined'
  where i.game_id = p_game_id and i.user_id = p_user and i.status = 'pending';
  if not found then raise exception 'not_found'; end if;
  return (select g from public.games g where g.id = p_game_id);
end $$;

-- ---------------------------------------------------------------------------
-- Host tools
-- ---------------------------------------------------------------------------

-- No reliability event: the host chose this, not the player.
create function app.host_remove_participant(p_user uuid, p_game_id uuid, p_member uuid, p_now timestamptz)
returns public.games
language plpgsql
set search_path = ''
as $$
declare
  v_game public.games;
begin
  if p_user is null then raise exception 'not_authenticated'; end if;
  select g.* into v_game from public.games g where g.id = p_game_id for update;
  if not found or v_game.host_id <> p_user or v_game.status <> 'open' or lower(v_game.during) <= p_now then
    raise exception 'not_found';
  end if;
  if p_member = p_user then raise exception 'host_cannot_leave'; end if;

  delete from public.game_participants p where p.game_id = p_game_id and p.user_id = p_member;
  if not found then raise exception 'not_participant'; end if;

  perform app.notify(p_member, 'game_removed', 'games', app.game_note(v_game), p_now);
  return v_game;
end $$;

-- A null argument leaves that field as it is; a blank note clears it.
create function app.host_update_game(p_user uuid, p_game_id uuid, p_note text, p_spots integer, p_now timestamptz)
returns public.games
language plpgsql
set search_path = ''
as $$
declare
  v_game public.games;
  v_note text;
  v_spots integer;
begin
  if p_user is null then raise exception 'not_authenticated'; end if;
  select g.* into v_game from public.games g where g.id = p_game_id for update;
  if not found or v_game.host_id <> p_user or v_game.status <> 'open' or lower(v_game.during) <= p_now then
    raise exception 'not_found';
  end if;
  if p_spots is not null and (
       p_spots < 2 or p_spots > 30
       or p_spots < (select count(*) from public.game_participants p where p.game_id = p_game_id)) then
    raise exception 'invalid_argument';
  end if;

  v_note := case when p_note is null then v_game.note else nullif(btrim(p_note), '') end;
  v_spots := coalesce(p_spots, v_game.spots);
  if v_note is not distinct from v_game.note and v_spots = v_game.spots then return v_game; end if;

  update public.games g
  set note = v_note,
      spots = v_spots,
      price_per_player = case
        when g.booking_id is null then g.price_per_player
        else (select ceil(b.total_price::numeric / v_spots)::integer from public.bookings b where b.id = g.booking_id)
      end
  where g.id = p_game_id
  returning * into v_game;

  perform app.notify_game(v_game, 'game_changed', p_user, p_now);
  return v_game;
end $$;

-- Cancels the game; with p_cancel_booking also the host's court booking
-- under it, by the player rules (a late cancellation counts against them).
create function app.host_cancel_game(p_user uuid, p_game_id uuid, p_cancel_booking boolean, p_now timestamptz)
returns public.games
language plpgsql
set search_path = ''
as $$
declare
  v_game public.games;
begin
  if p_user is null then raise exception 'not_authenticated'; end if;
  select g.* into v_game from public.games g where g.id = p_game_id;
  if not found or v_game.host_id <> p_user then raise exception 'not_found'; end if;

  -- Booking before game, the order cancel_booking and owner_cancel_booking
  -- use, so a venue cancelling at the same moment cannot deadlock with us.
  if coalesce(p_cancel_booking, false) and v_game.booking_id is not null then
    perform 1 from public.bookings b where b.id = v_game.booking_id for update;
  end if;
  select g.* into v_game from public.games g where g.id = p_game_id for update;
  if v_game.status <> 'open' or v_game.completed_at is not null then raise exception 'not_found'; end if;
  -- Once it has started the game is happening (or was a no-show): too late.
  if lower(v_game.during) <= p_now then raise exception 'not_cancellable'; end if;

  update public.games g set status = 'cancelled' where g.id = p_game_id returning * into v_game;
  perform app.notify_game(v_game, 'game_cancelled', p_user, p_now);

  -- After the game is cancelled, so cancel_games_for_booking finds nothing
  -- left to cancel and nobody hears twice.
  if coalesce(p_cancel_booking, false) and exists (
       select 1 from public.bookings b
       where b.id = v_game.booking_id and b.user_id = p_user and b.source = 'app'
         and b.status = 'confirmed' and lower(b.during) > p_now) then
    perform app.cancel_booking(p_user, v_game.booking_id, p_now);
  end if;
  return v_game;
end $$;

-- Every open game on a booking that is no longer happening: cancelled, and
-- its participants told (except whoever cancelled).
create function app.cancel_games_for_booking(p_booking_id uuid, p_actor uuid, p_now timestamptz) returns void
language plpgsql
set search_path = ''
as $$
declare
  v_game public.games;
begin
  for v_game in
    update public.games g set status = 'cancelled'
    where g.booking_id = p_booking_id and g.status = 'open'
    returning g.*
  loop
    perform app.notify_game(v_game, 'game_cancelled', p_actor, p_now);
  end loop;
end $$;

-- ---------------------------------------------------------------------------
-- Booking cancellations, redefined from Task 1 (community_core.sql) with
-- its hooks kept, now also cancelling the games on the booking.
-- ---------------------------------------------------------------------------

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
  perform app.cancel_games_for_booking(v_booking.id, p_user, p_now);
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
  -- The games on it are off too; nobody's reliability changes.
  perform app.cancel_games_for_booking(v_after.id, p_user, p_now);
  return v_after;
end $$;

-- ---------------------------------------------------------------------------
-- Discovery
-- ---------------------------------------------------------------------------

-- In the city: games the player may see that are open, have not started and
-- are not full unless the player is in them. Anywhere: every upcoming open
-- game the player hosts, plays in or is invited to. Earliest first.
create or replace function app.list_games(p_user uuid, p_city_id text, p_now timestamptz) returns setof jsonb
language sql
set search_path = ''
as $$
  select app.game_json(g, p_user)
  from public.games g
  where g.status = 'open'
    and lower(g.during) > p_now
    and (
      (g.city_id = p_city_id
       and app.can_see_game(p_user, g)
       and ((select count(*) from public.game_participants p where p.game_id = g.id) < g.spots
            or exists (select 1 from public.game_participants p where p.game_id = g.id and p.user_id = p_user)))
      or (p_user is not null and (
        g.host_id = p_user
        or exists (select 1 from public.game_participants p where p.game_id = g.id and p.user_id = p_user)
        or exists (select 1 from public.game_invites i
                   where i.game_id = g.id and i.user_id = p_user and i.status = 'pending'))))
  order by lower(g.during), g.id
$$;

-- ---------------------------------------------------------------------------
-- Reliability, redefined from Task 1: positive credit in the window counts
-- for at most +20, so it cannot be banked against no-shows. Badges unchanged.
-- ---------------------------------------------------------------------------

create or replace function app.reliability(p_user uuid, p_now timestamptz) returns jsonb
language plpgsql stable
set search_path = ''
as $$
declare
  c_max_credit constant integer := 20;
  v_positive integer;
  v_negative integer;
  v_ever integer;
  v_score integer;
begin
  select coalesce(sum(e.delta) filter (where e.created_at > p_now - interval '90 days' and e.delta > 0), 0),
         coalesce(sum(e.delta) filter (where e.created_at > p_now - interval '90 days' and e.delta < 0), 0),
         count(*)
    into v_positive, v_negative, v_ever
  from public.reliability_events e where e.user_id = p_user;
  v_score := greatest(0, least(100, 80 + least(v_positive, c_max_credit) + v_negative));
  return jsonb_build_object(
    'score', v_score,
    'badge', case
      when v_score >= 70 and v_ever < 3 then 'new'
      when v_score >= 70 then 'reliable'
      when v_score >= 50 then 'limited'
      else 'blocked'
    end);
end $$;

-- ---------------------------------------------------------------------------
-- Scheduled work
-- ---------------------------------------------------------------------------

-- Two hours before: confirmed app bookings (Task 1) and open games.
create or replace function app.send_reminders(p_now timestamptz) returns integer
language plpgsql
set search_path = ''
as $$
declare
  v_booking public.bookings;
  v_game public.games;
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

  for v_game in
    update public.games g set reminded_at = p_now
    where g.status = 'open' and g.completed_at is null and g.reminded_at is null
      and lower(g.during) > p_now and lower(g.during) <= p_now + interval '2 hours'
    returning g.*
  loop
    v_count := v_count + app.notify_game(v_game, 'game_reminder', null, p_now);
  end loop;
  return v_count;
end $$;

-- Open games that have ended: marked completed. A game that ended with at
-- least two players gives one game_completed event to each participant who
-- joined before it started (no credit for solo games or late joiners).
-- Returns how many games were completed.
create function app.complete_games(p_now timestamptz) returns integer
language plpgsql
set search_path = ''
as $$
declare
  v_game public.games;
  v_user uuid;
  v_count integer := 0;
begin
  for v_game in
    update public.games g set completed_at = p_now
    where g.status = 'open' and g.completed_at is null and upper(g.during) <= p_now
    returning g.*
  loop
    if (select count(*) from public.game_participants p where p.game_id = v_game.id) >= 2 then
      for v_user in
        select p.user_id from public.game_participants p
        where p.game_id = v_game.id and p.joined_at < lower(v_game.during)
      loop
        perform app.reliability_event(v_user, 'game_completed', v_game.id::text, p_now);
      end loop;
    end if;
    v_count := v_count + 1;
  end loop;
  return v_count;
end $$;

-- The reminders job also completes games (scheduling by the same name
-- replaces the command).
do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron;
    execute $job$
      select cron.schedule(
        'actra-send-reminders',
        '*/10 * * * *',
        'select app.send_reminders(now()), app.complete_games(now())')
    $job$;
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- What the app calls
-- ---------------------------------------------------------------------------

create or replace function public.list_games(p_city_id text) returns setof jsonb
language sql security definer
set search_path = ''
as $$ select app.list_games((select auth.uid()), p_city_id, now()) $$;

-- null when the game does not exist or the player may not see it.
create or replace function public.get_game(p_game_id uuid) returns jsonb
language sql security definer
set search_path = ''
as $$
  select app.game_json(g, (select auth.uid()))
  from public.games g
  where g.id = p_game_id and app.can_see_game((select auth.uid()), g)
$$;

create or replace function public.join_game(p_game_id uuid) returns jsonb
language sql security definer
set search_path = ''
as $$ select app.game_json(app.join_game((select auth.uid()), p_game_id, now()), (select auth.uid())) $$;

create or replace function public.leave_game(p_game_id uuid) returns jsonb
language sql security definer
set search_path = ''
as $$ select app.game_json(app.leave_game((select auth.uid()), p_game_id, now()), (select auth.uid())) $$;

create function public.create_game(p_game jsonb) returns jsonb
language sql security definer
set search_path = ''
as $$ select app.game_json(app.create_game((select auth.uid()), p_game, now()), (select auth.uid())) $$;

-- Returns the game, now with my_status 'requested'.
create function public.request_to_join(p_game_id uuid) returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  v_user uuid := (select auth.uid());
  v_request public.game_join_requests;
begin
  v_request := app.request_to_join(v_user, p_game_id, now());
  return (select app.game_json(g, v_user) from public.games g where g.id = v_request.game_id);
end $$;

create function public.withdraw_join_request(p_request_id uuid) returns jsonb
language sql security definer
set search_path = ''
as $$ select app.game_json(app.withdraw_join_request((select auth.uid()), p_request_id), (select auth.uid())) $$;

create function public.decide_join_request(p_request_id uuid, p_approve boolean) returns jsonb
language sql security definer
set search_path = ''
as $$ select app.game_json(app.decide_join_request((select auth.uid()), p_request_id, p_approve, now()), (select auth.uid())) $$;

create function public.invite_to_game(p_game_id uuid, p_user_id uuid) returns jsonb
language sql security definer
set search_path = ''
as $$ select app.game_json(app.invite_to_game((select auth.uid()), p_game_id, p_user_id, now()), (select auth.uid())) $$;

create function public.decline_invite(p_game_id uuid) returns jsonb
language sql security definer
set search_path = ''
as $$ select app.game_json(app.decline_invite((select auth.uid()), p_game_id), (select auth.uid())) $$;

create function public.host_remove_participant(p_game_id uuid, p_user_id uuid) returns jsonb
language sql security definer
set search_path = ''
as $$ select app.game_json(app.host_remove_participant((select auth.uid()), p_game_id, p_user_id, now()), (select auth.uid())) $$;

create function public.host_update_game(p_game_id uuid, p_note text, p_spots integer) returns jsonb
language sql security definer
set search_path = ''
as $$ select app.game_json(app.host_update_game((select auth.uid()), p_game_id, p_note, p_spots, now()), (select auth.uid())) $$;

create function public.host_cancel_game(p_game_id uuid, p_cancel_booking boolean) returns jsonb
language sql security definer
set search_path = ''
as $$ select app.game_json(app.host_cancel_game((select auth.uid()), p_game_id, p_cancel_booking, now()), (select auth.uid())) $$;

revoke all on function
  public.list_games(text),
  public.get_game(uuid),
  public.join_game(uuid),
  public.leave_game(uuid),
  public.create_game(jsonb),
  public.request_to_join(uuid),
  public.withdraw_join_request(uuid),
  public.decide_join_request(uuid, boolean),
  public.invite_to_game(uuid, uuid),
  public.decline_invite(uuid),
  public.host_remove_participant(uuid, uuid),
  public.host_update_game(uuid, text, integer),
  public.host_cancel_game(uuid, boolean)
from public, anon, authenticated;

grant execute on function
  public.list_games(text),
  public.get_game(uuid),
  public.join_game(uuid),
  public.leave_game(uuid),
  public.create_game(jsonb),
  public.request_to_join(uuid),
  public.withdraw_join_request(uuid),
  public.decide_join_request(uuid, boolean),
  public.invite_to_game(uuid, uuid),
  public.decline_invite(uuid),
  public.host_remove_participant(uuid, uuid),
  public.host_update_game(uuid, text, integer),
  public.host_cancel_game(uuid, boolean)
to authenticated, service_role;
