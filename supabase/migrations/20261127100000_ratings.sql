-- Milestone 7a, part 1: ratings 1.00-7.00 for the rated sports (padel and
-- tennis), the starting-rating questionnaire, "My sports", the 1-5 level
-- derived from the rating, and rating ranges on games and Game Requests
-- (design 2026-11-27-actra-m7-competitive §5.1-§5.3).
--
-- Additive: a new server-only table, new columns, widened checks, new
-- functions. The replaced functions keep their signatures (`create or
-- replace`, so their grants stay); each is copied from the latest migration
-- that defined it, named above it.

-- ---------------------------------------------------------------------------
-- The rated sports are padel and tennis (design §5.1). Flagged here, before
-- the policies and the backfill below rely on the flag, so a live database
-- whose rows are not flagged yet still gets ratings. No-op where a row does
-- not exist or is flagged already; tests/ratings.test.mjs runs the statement
-- between the markers.
-- ---------------------------------------------------------------------------

-- rated-sports:start
update public.sports set competitive_rating = true where id in ('padel', 'tennis') and not competitive_rating;
-- rated-sports:end

-- ---------------------------------------------------------------------------
-- Tables and columns
-- ---------------------------------------------------------------------------

-- The current rating per player and rated sport. Only database functions
-- write it. rated_games counts the confirmed results behind it; source says
-- where the starting value came from.
create table public.player_ratings (
  user_id uuid not null references public.profiles (id) on delete cascade,
  sport_id text not null references public.sports (id),
  rating numeric(3, 2) not null check (rating between 1 and 7),
  rated_games integer not null default 0 check (rated_games >= 0),
  source text not null check (source in ('questionnaire', 'level', 'first_result')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (user_id, sport_id)
);

alter table public.player_ratings enable row level security;
revoke all on table public.player_ratings from anon, authenticated;
grant all on table public.player_ratings to service_role;

-- Rated sports carry a rating range next to the whole-number one, which is
-- derived from it (old builds keep reading min_level / max_level).
alter table public.games
  add column min_rating numeric(3, 2),
  add column max_rating numeric(3, 2),
  add constraint games_rating_range check (
    (min_rating is null and max_rating is null)
    or (min_rating >= 1 and min_rating <= max_rating and max_rating <= 7));

alter table public.game_requests
  add column min_rating numeric(3, 2),
  add column max_rating numeric(3, 2),
  add constraint game_requests_rating_range check (
    (min_rating is null and max_rating is null)
    or (min_rating >= 1 and min_rating <= max_rating and max_rating <= 7));

-- The new notification categories. The check was declared inline, so look
-- its name up instead of assuming it (as 20261125100000_tournaments.sql does).
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
  check (category in ('bookings', 'venue', 'games', 'requests', 'invites', 'tournaments', 'ratings', 'teams'));

-- Clients keep writing levels for simple sports only; the level of a rated
-- sport follows the rating (app.sync_level). Replaces the write policies of
-- 20261122100100_profiles.sql. No app function here: clients cannot use
-- schema app.
drop policy "players add their own levels" on public.player_levels;
drop policy "players change their own levels" on public.player_levels;
drop policy "players remove their own levels" on public.player_levels;
create policy "players add their own levels" on public.player_levels for insert to authenticated
  with check (user_id = (select auth.uid())
    and exists (select 1 from public.sports s where s.id = player_levels.sport_id and not s.competitive_rating));
create policy "players change their own levels" on public.player_levels for update to authenticated
  using (user_id = (select auth.uid())
    and exists (select 1 from public.sports s where s.id = player_levels.sport_id and not s.competitive_rating))
  with check (user_id = (select auth.uid())
    and exists (select 1 from public.sports s where s.id = player_levels.sport_id and not s.competitive_rating));
create policy "players remove their own levels" on public.player_levels for delete to authenticated
  using (user_id = (select auth.uid())
    and exists (select 1 from public.sports s where s.id = player_levels.sport_id and not s.competitive_rating));

-- ---------------------------------------------------------------------------
-- Rating helpers
-- ---------------------------------------------------------------------------

-- Every tuning number of the rating system, in one place (the app mirrors
-- them in RatingRules, app/lib/domain/competitive.dart).
create function app.rating_const(p_name text) returns numeric
language plpgsql immutable
set search_path = ''
as $$
begin
  return case p_name
    when 'k_provisional' then 0.30
    when 'k_established' then 0.12
    when 'provisional_games' then 10
    when 'margin_min' then 0.75
    when 'margin_span' then 0.50
    when 'questionnaire_cap' then 5.00
    when 'unrated_default' then 2.50
    when 'min' then 1.00
    when 'max' then 7.00
  end;
end $$;

create function app.is_rated_sport(p_sport_id text) returns boolean
language sql stable
set search_path = ''
as $$
  select coalesce((select s.competitive_rating from public.sports s where s.id = p_sport_id), false)
$$;

-- Five answers, each 0-3: years played, how often, competition, two skill
-- questions. Points per answer, added to the minimum and capped: the top of
-- the scale has to be earned in results.
create function app.questionnaire_rating(p_answers integer[]) returns numeric
language plpgsql immutable
set search_path = ''
as $$
declare
  c_points constant numeric[] := '{{0, 0.3, 0.6, 0.8}, {0, 0.2, 0.4, 0.6}, {0, 0.4, 0.8, 1.2}, {0, 0.3, 0.6, 0.7}, {0, 0.3, 0.6, 0.7}}';
  v_answer integer;
  v_sum numeric := 0;
begin
  if p_answers is null or array_ndims(p_answers) <> 1 or cardinality(p_answers) <> 5 then
    raise exception 'invalid_argument';
  end if;
  for i in 1..5 loop
    v_answer := p_answers[array_lower(p_answers, 1) + i - 1];
    if v_answer is null or v_answer not between 0 and 3 then raise exception 'invalid_argument'; end if;
    v_sum := v_sum + c_points[i][v_answer + 1];
  end loop;
  return round(least(app.rating_const('questionnaire_cap'), app.rating_const('min') + v_sum), 2);
end $$;

-- The rating used for level checks: a player who never answered counts as
-- the minimum (design §5.2).
create function app.effective_rating(p_user uuid, p_sport_id text) returns numeric
language sql
set search_path = ''
as $$
  select coalesce(
    (select r.rating from public.player_ratings r where r.user_id = p_user and r.sport_id = p_sport_id),
    app.rating_const('min'))
$$;

-- {"rating", "provisional", "rated_games"}, or null without a rating.
create function app.rating_json(p_user uuid, p_sport_id text) returns jsonb
language sql
set search_path = ''
as $$
  select jsonb_build_object(
    'rating', r.rating,
    'provisional', r.rated_games < app.rating_const('provisional_games'),
    'rated_games', r.rated_games)
  from public.player_ratings r where r.user_id = p_user and r.sport_id = p_sport_id
$$;

-- Keeps the 1-5 level of a rated sport in step with the rating: its whole
-- part, capped at 5. Nothing happens without a rating.
create function app.sync_level(p_user uuid, p_sport_id text) returns void
language sql
set search_path = ''
as $$
  insert into public.player_levels (user_id, sport_id, level)
  select r.user_id, r.sport_id, least(5, floor(r.rating))::integer
  from public.player_ratings r where r.user_id = p_user and r.sport_id = p_sport_id
  on conflict (user_id, sport_id) do update set level = excluded.level;
$$;

-- The rating range of a new game or request in a rated sport: from the JSON
-- when it names one (both ends, numbers 1-7, min <= max), else converted from
-- the level range an old build sends (2-4 -> 2.00-4.99, top level 5 -> 7.00).
-- Both null for a simple sport, whatever the JSON says.
create function app.rating_range(
  p_sport_id text, p_spec jsonb, p_min_level integer, p_max_level integer,
  out min_rating numeric, out max_rating numeric)
language plpgsql
set search_path = ''
as $$
begin
  if not app.is_rated_sport(p_sport_id) then return; end if;

  if p_spec->>'min_rating' is null and p_spec->>'max_rating' is null then
    min_rating := p_min_level;
    max_rating := case when p_max_level = 5 then app.rating_const('max') else p_max_level + 0.99 end;
    return;
  end if;

  if jsonb_typeof(p_spec->'min_rating') is distinct from 'number'
     or jsonb_typeof(p_spec->'max_rating') is distinct from 'number' then
    raise exception 'invalid_argument';
  end if;
  begin
    -- Checked as stored (numeric(3,2)).
    min_rating := round((p_spec->>'min_rating')::numeric, 2);
    max_rating := round((p_spec->>'max_rating')::numeric, 2);
  exception when numeric_value_out_of_range then
    raise exception 'invalid_argument';
  end;
  if min_rating < app.rating_const('min') or max_rating > app.rating_const('max') or min_rating > max_rating then
    raise exception 'invalid_argument';
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- One-off backfill. Players who already have a level in a rated sport start
-- at that level plus 0.5 (provisional, may still answer the questionnaire);
-- games and requests in a rated sport get a rating range from their level
-- range. Idempotent; tests/ratings.test.mjs runs the block between the
-- markers on seeded rows.
-- ---------------------------------------------------------------------------

-- backfill:start
insert into public.player_ratings (user_id, sport_id, rating, rated_games, source, created_at, updated_at)
select l.user_id, l.sport_id, l.level + 0.5, 0, 'level', now(), now()
from public.player_levels l
join public.sports s on s.id = l.sport_id and s.competitive_rating
on conflict (user_id, sport_id) do nothing;
update public.games g
set min_rating = g.min_level,
    max_rating = case when g.max_level = 5 then 7.00 else g.max_level + 0.99 end
from public.sports s
where s.id = g.sport_id and s.competitive_rating and g.min_rating is null;
update public.game_requests r
set min_rating = r.min_level,
    max_rating = case when r.max_level = 5 then 7.00 else r.max_level + 0.99 end
from public.sports s
where s.id = r.sport_id and s.competitive_rating and r.min_rating is null;
-- backfill:end

-- ---------------------------------------------------------------------------
-- My sports
-- ---------------------------------------------------------------------------

-- A simple sport takes a level 1-5. A rated sport takes the five answers,
-- until its first rated game; after that the rating is kept and only the
-- level row comes back (answers are ignored).
create function app.set_my_sport(p_user uuid, p_sport_id text, p_level integer, p_answers integer[], p_now timestamptz)
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_sport public.sports;
  v_rated_games integer;
begin
  if p_user is null then raise exception 'not_authenticated'; end if;
  select s.* into v_sport from public.sports s where s.id = p_sport_id and s.active;
  if not found then raise exception 'invalid_argument'; end if;

  if not v_sport.competitive_rating then
    if p_level is null or p_level not between 1 and 5 or p_answers is not null then
      raise exception 'invalid_argument';
    end if;
    insert into public.player_levels (user_id, sport_id, level) values (p_user, p_sport_id, p_level)
    on conflict (user_id, sport_id) do update set level = excluded.level;
    return;
  end if;

  if p_level is not null then raise exception 'invalid_argument'; end if;
  select r.rated_games into v_rated_games from public.player_ratings r
  where r.user_id = p_user and r.sport_id = p_sport_id
  for update;
  if coalesce(v_rated_games, 0) = 0 then
    -- The where clause keeps a rating that a result reached meanwhile.
    insert into public.player_ratings as pr (user_id, sport_id, rating, rated_games, source, created_at, updated_at)
    values (p_user, p_sport_id, app.questionnaire_rating(p_answers), 0, 'questionnaire', p_now, p_now)
    on conflict (user_id, sport_id) do update
      set rating = excluded.rating, source = excluded.source, updated_at = excluded.updated_at
      where pr.rated_games = 0;
  end if;
  perform app.sync_level(p_user, p_sport_id);
end $$;

-- Removes the level only: a rating stays and comes back with the sport.
create function app.remove_my_sport(p_user uuid, p_sport_id text) returns void
language plpgsql
set search_path = ''
as $$
begin
  if p_user is null then raise exception 'not_authenticated'; end if;
  delete from public.player_levels l where l.user_id = p_user and l.sport_id = p_sport_id;
end $$;

-- The sports the player has ticked, in catalogue order. Rated sports carry
-- the rating; simple ones have null rating, provisional and rated_games.
create function app.my_sports(p_user uuid) returns jsonb
language sql
set search_path = ''
as $$
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'sport_id', l.sport_id,
      'level', l.level,
      'rating', r.rating,
      'provisional', case when s.competitive_rating
        then coalesce(r.rated_games, 0) < app.rating_const('provisional_games') end,
      'rated_games', case when s.competitive_rating then coalesce(r.rated_games, 0) end,
      'can_retake', s.competitive_rating and coalesce(r.rated_games, 0) = 0)
    order by s.sort_order, s.id), '[]'::jsonb)
  from public.player_levels l
  join public.sports s on s.id = l.sport_id
  left join public.player_ratings r on r.user_id = l.user_id and r.sport_id = l.sport_id
  where l.user_id = p_user
$$;

-- ---------------------------------------------------------------------------
-- JSON
-- ---------------------------------------------------------------------------

-- Redefined from 20261126110000_launch.sql: the rating range, and each
-- participant's and requester's rating (null in simple sports).
create or replace function app.game_json(g public.games, p_user uuid) returns jsonb
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
    'min_rating', g.min_rating,
    'max_rating', g.max_rating,
    'price_per_player', g.price_per_player,
    'booking_id', g.booking_id,
    'note', g.note,
    -- '' only for a deleted host's meeting point (delete_account).
    'meeting_point', nullif(g.meeting_point, ''),
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
                  'rating', rt.rating,
                  'provisional', rt.rated_games < app.rating_const('provisional_games'),
                  'reliability', app.reliability(p.user_id, now()))
                || app.deleted_json(p.user_id)
                order by (p.user_id = g.host_id) desc, p.joined_at, p.user_id)
       from public.game_participants p
       join public.profiles pr on pr.id = p.user_id
       left join public.player_levels l on l.user_id = p.user_id and l.sport_id = g.sport_id
       left join public.player_ratings rt on rt.user_id = p.user_id and rt.sport_id = g.sport_id
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
                     'rating', rt.rating,
                     'provisional', rt.rated_games < app.rating_const('provisional_games'),
                     'reliability', app.reliability(r.user_id, now()),
                     'created_at', r.created_at)
                   || app.deleted_json(r.user_id)
                   order by r.created_at, r.id)
          from public.game_join_requests r
          join public.profiles pr on pr.id = r.user_id
          left join public.player_levels l on l.user_id = r.user_id and l.sport_id = g.sport_id
          left join public.player_ratings rt on rt.user_id = r.user_id and rt.sport_id = g.sport_id
          where r.game_id = g.id and r.status = 'pending'),
         '[]'::jsonb))
     else '{}'::jsonb end
$$;

-- Redefined from 20261126110000_launch.sql: the rating range, and each
-- interested player's rating (null in simple sports).
create or replace function app.game_request_json(r public.game_requests, p_user uuid) returns jsonb
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
    'min_rating', r.min_rating,
    'max_rating', r.max_rating,
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
                  'rating', rt.rating,
                  'provisional', rt.rated_games < app.rating_const('provisional_games'),
                  'reliability', app.reliability(i.user_id, now()))
                || app.deleted_json(i.user_id)
                order by i.created_at, i.user_id)
       from public.game_request_interest i
       join public.profiles pr on pr.id = i.user_id
       left join public.player_levels l on l.user_id = i.user_id and l.sport_id = r.sport_id
       left join public.player_ratings rt on rt.user_id = i.user_id and rt.sport_id = r.sport_id
       where i.request_id = r.id),
      '[]'::jsonb),
    'interested_count', (select count(*) from public.game_request_interest i where i.request_id = r.id),
    'my_status', case
      when p_user is null then null
      when r.host_id = p_user then 'host'
      when exists (select 1 from public.game_request_interest i where i.request_id = r.id and i.user_id = p_user)
        then 'interested'
    end)
  || app.deleted_json(r.host_id, 'host_deleted')
$$;

-- Redefined from 20261126110000_launch.sql: `ratings` per rated sport the
-- player has ticked (a kept rating of a removed sport is not shown, as its
-- level is not).
create or replace function app.player_json(pr public.profiles) returns jsonb
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
    'ratings', coalesce(
      (select jsonb_object_agg(r.sport_id, app.rating_json(r.user_id, r.sport_id))
       from public.player_ratings r
       join public.player_levels l on l.user_id = r.user_id and l.sport_id = r.sport_id
       where r.user_id = pr.id),
      '{}'::jsonb),
    'reliability', app.reliability(pr.id, now()),
    'games_played', (
      select count(*) from public.game_participants gp
      join public.games g on g.id = gp.game_id
      where gp.user_id = pr.id and g.completed_at is not null))
  || case when pr.deleted_at is not null then jsonb_build_object('deleted', true) else '{}'::jsonb end
$$;

-- ---------------------------------------------------------------------------
-- Games and requests with rating ranges
-- ---------------------------------------------------------------------------

-- Redefined from 20261124110000_games_v2.sql: a rated sport stores a rating
-- range (app.rating_range) and derives the whole-number range from it.
create or replace function app.create_game(p_user uuid, p_game jsonb, p_now timestamptz) returns public.games
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
  v_min_rating numeric;
  v_max_rating numeric;
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

  select rr.min_rating, rr.max_rating into v_min_rating, v_max_rating
  from app.rating_range(v_sport.id, p_game, v_min, v_max) rr;
  if v_min_rating is not null then
    v_min := least(5, floor(v_min_rating))::integer;
    v_max := least(5, floor(v_max_rating))::integer;
  end if;

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
    min_rating, max_rating,
    price_per_player, note, kind, visibility, meeting_point, meeting_lat, meeting_lng, distance_km, pace, created_at,
    reminded_at)
  values (
    v_sport.id, v_city_id, v_venue_id, p_user, v_booking_id, v_during, v_offset, v_spots, v_min, v_max,
    v_min_rating, v_max_rating,
    v_price, v_note, v_kind, v_visibility, v_meeting, v_lat, v_lng, v_distance, v_pace, p_now,
    -- Created inside the reminder window (send_reminders: at most 2 h ahead):
    -- the host just made it, so no reminder follows straight away.
    case when lower(v_during) <= p_now + interval '2 hours' then p_now end)
  returning * into v_game;

  insert into public.game_participants (game_id, user_id, joined_at) values (v_game.id, p_user, p_now);
  return v_game;
end $$;

-- Redefined from 20261124110000_games_v2.sql: a game with a rating range
-- checks the player's rating (app.effective_rating) instead of the level.
-- One-tap join for players inside the range (a player with no level for the
-- sport counts as level 1). An invite opens an invite-only game and skips
-- the check.
create or replace function app.join_game(p_user uuid, p_game_id uuid, p_now timestamptz) returns public.games
language plpgsql
set search_path = ''
as $$
declare
  v_game public.games;
  v_invited boolean;
  v_level integer;
  v_rating numeric;
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
  -- Removed by the host: the game is closed to them until they are invited.
  if app.removed_from_game(p_game_id, p_user) then raise exception 'not_found'; end if;

  if exists (select 1 from public.game_participants p where p.game_id = p_game_id and p.user_id = p_user) then
    raise exception 'already_joined';
  end if;
  if (select count(*) from public.game_participants p where p.game_id = p_game_id) >= v_game.spots then
    raise exception 'full';
  end if;

  if not v_invited then
    if v_game.min_rating is not null then
      v_rating := app.effective_rating(p_user, v_game.sport_id);
      if v_rating < v_game.min_rating or v_rating > v_game.max_rating then
        raise exception 'level_out_of_range';
      end if;
    else
      select coalesce((select l.level from public.player_levels l
                       where l.user_id = p_user and l.sport_id = v_game.sport_id), 1) into v_level;
      if v_level < v_game.min_level or v_level > v_game.max_level then
        raise exception 'level_out_of_range';
      end if;
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

-- Redefined from 20261124120000_game_requests.sql: rating range as in
-- app.create_game.
create or replace function app.create_game_request(p_user uuid, p_request jsonb, p_now timestamptz)
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
  v_min_rating numeric;
  v_max_rating numeric;
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

  select rr.min_rating, rr.max_rating into v_min_rating, v_max_rating
  from app.rating_range(v_sport.id, p_request, v_min, v_max) rr;
  if v_min_rating is not null then
    v_min := least(5, floor(v_min_rating))::integer;
    v_max := least(5, floor(v_max_rating))::integer;
  end if;

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
    min_level, max_level, min_rating, max_rating, note, created_at)
  values (
    v_sport.id, v_city_id, p_user,
    tstzrange(app.to_instant(v_starts, v_offset), app.to_instant(v_ends, v_offset), '[)'),
    v_offset, nullif(btrim(p_request->>'area'), ''), v_venue_id, v_needed,
    v_min, v_max, v_min_rating, v_max_rating, nullif(btrim(p_request->>'note'), ''), p_now)
  returning * into v_request;
  return v_request;
end $$;

-- Redefined from 20261124120000_game_requests.sql: the request's rating
-- range goes into the game.
-- p_place: booking_id, or venue_id, or meeting_point (+ meeting_lat/lng);
-- optional spots (default 1 + players_needed), starts_local/ends_local for
-- place-only sports (default: the request's window), and visibility, pace,
-- distance_km. A place with none of the three keys falls back to the
-- request's own venue, if it has one. The game is made by app.create_game
-- (same checks as any game), then, holding the game's row lock, the
-- interested players are added in the order they tapped while spots remain.
create or replace function app.convert_game_request(p_user uuid, p_request_id uuid, p_place jsonb, p_now timestamptz)
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
    || case when v_request.min_rating is not null
         then jsonb_build_object('min_rating', v_request.min_rating, 'max_rating', v_request.max_rating)
         else '{}'::jsonb end
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
    -- A player blocked since tapping is told, but not added (as join_game
    -- would refuse them).
    if v_count < v_game.spots
       and app.reliability(v_user, p_now)->>'badge' <> 'blocked'
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
-- Finding players by rating
-- ---------------------------------------------------------------------------

-- As app.list_players (20261126110000_launch.sql), filtered on the rating in
-- a rated sport (no rating counts as the minimum).
create function app.list_players_rated(
  p_user uuid, p_city_id text, p_sport_id text, p_min_rating numeric, p_max_rating numeric,
  p_query text, p_limit integer) returns setof jsonb
language plpgsql
set search_path = ''
as $$
begin
  if not app.is_rated_sport(p_sport_id) then raise exception 'invalid_argument'; end if;
  return query
  select app.player_json(pr)
  from public.profiles pr
  where pr.city_id = p_city_id
    and pr.deleted_at is null
    and not pr.hidden_from_search
    and pr.id is distinct from p_user
    and (nullif(btrim(p_query), '') is null
         or pr.full_name ilike '%' || replace(replace(replace(btrim(p_query), '\', '\\'), '%', '\%'), '_', '\_') || '%')
    and app.effective_rating(pr.id, p_sport_id)
        between coalesce(p_min_rating, app.rating_const('min')) and coalesce(p_max_rating, app.rating_const('max'))
  order by pr.full_name, pr.id
  limit least(greatest(coalesce(p_limit, 50), 1), 100);
end $$;

-- ---------------------------------------------------------------------------
-- app.admin_save_sport (from 20261126100000_kazakh.sql): the rating switch
-- is fixed. New sports get simple levels; an update keeps the stored value,
-- whatever the payload says (rating another sport needs its own
-- questionnaire and scores: an engineering change, design §5.1).
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
    v_row.default_players := 2;
    v_row.sort_order := 0;
    v_row.active := true;
  else
    select s.* into v_row from public.sports s where s.id = v_patch ->> 'id' for update;
    if not found then raise exception 'not_found'; end if;
    v_before := v_row;
  end if;
  v_row := jsonb_populate_record(v_row, v_patch);
  v_row.competitive_rating := case when p_create then false else v_before.competitive_rating end;

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
-- Settings: set_settings, redefined from 20261125100000_tournaments.sql with
-- the new categories. Same signature, so its grants stay.
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
    where m is null
       or m not in ('bookings', 'venue', 'games', 'requests', 'invites', 'tournaments', 'ratings', 'teams')) then
    raise exception 'invalid_argument';
  end if;
  update public.profiles p
  set muted_categories = case when p_muted is null then p.muted_categories
        else coalesce((select array_agg(distinct m order by m) from unnest(p_muted) m), '{}') end,
      hidden_from_search = coalesce(p_hidden, p.hidden_from_search)
  where p.id = v_user;
end $$;

-- ---------------------------------------------------------------------------
-- What the app calls
-- ---------------------------------------------------------------------------

create function public.my_sports() returns jsonb
language sql security definer
set search_path = ''
as $$ select app.my_sports((select auth.uid())) $$;

-- Both return the player's sports afterwards.
create function public.set_my_sport(p_sport_id text, p_level integer default null, p_answers integer[] default null)
returns jsonb
language sql security definer
set search_path = ''
as $$
  select app.set_my_sport((select auth.uid()), p_sport_id, p_level, p_answers, now());
  select app.my_sports((select auth.uid()));
$$;

create function public.remove_my_sport(p_sport_id text) returns jsonb
language sql security definer
set search_path = ''
as $$
  select app.remove_my_sport((select auth.uid()), p_sport_id);
  select app.my_sports((select auth.uid()));
$$;

create function public.list_players_rated(
  p_city_id text, p_sport_id text, p_min_rating numeric, p_max_rating numeric,
  p_query text default null, p_limit integer default 50) returns setof jsonb
language sql security definer
set search_path = ''
as $$ select app.list_players_rated((select auth.uid()), p_city_id, p_sport_id, p_min_rating, p_max_rating, p_query, p_limit) $$;

revoke all on function
  public.my_sports(),
  public.set_my_sport(text, integer, integer[]),
  public.remove_my_sport(text),
  public.list_players_rated(text, text, numeric, numeric, text, integer)
from public, anon, authenticated;

grant execute on function
  public.my_sports(),
  public.set_my_sport(text, integer, integer[]),
  public.remove_my_sport(text),
  public.list_players_rated(text, text, numeric, numeric, text, integer)
to authenticated, service_role;
