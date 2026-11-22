-- Available Games: place and time already fixed (product spec §9.1).
-- Rules are the ones in app/lib/domain/games.dart.

create table public.games (
  id uuid primary key default gen_random_uuid(),
  sport_id text not null references public.sports (id),
  city_id text not null references public.cities (id),
  venue_id uuid not null references public.venues (id),
  host_id uuid not null references public.profiles (id),
  booking_id uuid references public.bookings (id),
  during tstzrange not null,
  utc_offset_minutes integer not null,
  -- Total spots, the host included.
  spots integer not null check (spots > 0),
  min_level integer not null default 1 check (min_level between 1 and 5),
  max_level integer not null default 5 check (max_level between 1 and 5),
  price_per_player integer check (price_per_player is null or price_per_player >= 0),
  note text,
  status text not null default 'open' check (status in ('open', 'cancelled')),
  created_at timestamptz not null default now(),
  constraint games_levels check (min_level <= max_level)
);
create index games_city_idx on public.games (city_id, status);

create table public.game_participants (
  game_id uuid not null references public.games (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (game_id, user_id)
);
create index game_participants_user_idx on public.game_participants (user_id);

alter table public.games enable row level security;
alter table public.game_participants enable row level security;
revoke all on table public.games, public.game_participants from anon, authenticated;
grant all on table public.games, public.game_participants to service_role;
-- Read-only for players; joining and leaving go through the functions below.
grant select on table public.games, public.game_participants to authenticated;
create policy "signed-in players see games" on public.games for select to authenticated using (true);
create policy "signed-in players see who is playing" on public.game_participants for select to authenticated using (true);

-- A game as the app receives it. The host is listed first, then the others
-- in the order they joined. Not marked stable on purpose: it must see a
-- participant added by join_game earlier in the same statement.
create function app.game_json(g public.games) returns jsonb
language sql
set search_path = ''
as $$
  select jsonb_build_object(
    'id', g.id,
    'sport_id', g.sport_id,
    'city_id', g.city_id,
    'venue_id', g.venue_id,
    'host_id', g.host_id,
    'starts_local', app.to_local(lower(g.during), g.utc_offset_minutes),
    'ends_local', app.to_local(upper(g.during), g.utc_offset_minutes),
    'spots', g.spots,
    'min_level', g.min_level,
    'max_level', g.max_level,
    'price_per_player', g.price_per_player,
    'booking_id', g.booking_id,
    'note', g.note,
    'participant_ids', coalesce(
      (select jsonb_agg(p.user_id order by (p.user_id = g.host_id) desc, p.joined_at, p.user_id)
       from public.game_participants p where p.game_id = g.id),
      '[]'::jsonb))
$$;

-- One-tap join for players inside the level range. A player with no level
-- for the sport counts as a beginner (level 1).
create function app.join_game(p_user uuid, p_game_id uuid) returns public.games
language plpgsql
set search_path = ''
as $$
declare
  v_game public.games;
  v_level integer;
begin
  if p_user is null then raise exception 'not_authenticated'; end if;

  -- The row lock makes simultaneous joins take turns, so the last spot goes
  -- to exactly one player.
  select g.* into v_game from public.games g where g.id = p_game_id and g.status = 'open' for update;
  if not found then raise exception 'not_found'; end if;

  if exists (select 1 from public.game_participants p where p.game_id = p_game_id and p.user_id = p_user) then
    raise exception 'already_joined';
  end if;
  if (select count(*) from public.game_participants p where p.game_id = p_game_id) >= v_game.spots then
    raise exception 'full';
  end if;

  select coalesce((select l.level from public.player_levels l
                   where l.user_id = p_user and l.sport_id = v_game.sport_id), 1) into v_level;
  if v_level < v_game.min_level or v_level > v_game.max_level then
    raise exception 'level_out_of_range';
  end if;

  insert into public.game_participants (game_id, user_id) values (p_game_id, p_user);
  return v_game;
end $$;

create function app.leave_game(p_user uuid, p_game_id uuid) returns public.games
language plpgsql
set search_path = ''
as $$
declare
  v_game public.games;
begin
  if p_user is null then raise exception 'not_authenticated'; end if;

  select g.* into v_game from public.games g where g.id = p_game_id for update;
  if not found then raise exception 'not_found'; end if;
  if v_game.host_id = p_user then raise exception 'host_cannot_leave'; end if;

  delete from public.game_participants p where p.game_id = p_game_id and p.user_id = p_user;
  if not found then raise exception 'not_participant'; end if;
  return v_game;
end $$;

-- Open games in the city that have not started, plus full ones the player
-- is in; earliest first.
create function app.list_games(p_user uuid, p_city_id text, p_now timestamptz) returns setof jsonb
language sql
set search_path = ''
as $$
  select app.game_json(g)
  from public.games g
  where g.city_id = p_city_id
    and g.status = 'open'
    and lower(g.during) > p_now
    and ((select count(*) from public.game_participants p where p.game_id = g.id) < g.spots
         or exists (select 1 from public.game_participants p where p.game_id = g.id and p.user_id = p_user))
  order by lower(g.during), g.id
$$;

-- What the app calls.

create function public.list_games(p_city_id text) returns setof jsonb
language sql security definer
set search_path = ''
as $$ select app.list_games((select auth.uid()), p_city_id, now()) $$;

create function public.get_game(p_game_id uuid) returns jsonb
language sql security definer
set search_path = ''
as $$ select app.game_json(g) from public.games g where g.id = p_game_id $$;

create function public.join_game(p_game_id uuid) returns jsonb
language sql security definer
set search_path = ''
as $$ select app.game_json(app.join_game((select auth.uid()), p_game_id)) $$;

create function public.leave_game(p_game_id uuid) returns jsonb
language sql security definer
set search_path = ''
as $$ select app.game_json(app.leave_game((select auth.uid()), p_game_id)) $$;

revoke all on function
  public.list_games(text), public.get_game(uuid), public.join_game(uuid), public.leave_game(uuid)
from public, anon, authenticated;
grant execute on function
  public.list_games(text), public.get_game(uuid), public.join_game(uuid), public.leave_game(uuid)
to authenticated, service_role;
