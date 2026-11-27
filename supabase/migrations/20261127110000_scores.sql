-- Milestone 7a, part 2: match scores in rated sports, confirmation and
-- disputes, the rating maths and admin resolution (design
-- 2026-11-27-actra-m7-competitive §5.4-§5.6).
--
-- Additive: new server-only tables and functions. app.game_json keeps its
-- signature (copied from 20261127100000_ratings.sql) and gains `result`.
--
-- Lock order, everywhere: the match_results row first, then the result's
-- players' player_ratings rows in user_id order.

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------

-- One result per game. sets: [[games of side a, games of side b], ...].
create table public.match_results (
  id uuid primary key default gen_random_uuid(),
  game_id uuid not null unique references public.games (id) on delete cascade,
  entered_by uuid not null references public.profiles (id) on delete cascade,
  status text not null default 'pending' check (status in ('pending', 'confirmed', 'disputed', 'void')),
  sets jsonb not null,
  winner text not null check (winner in ('a', 'b', 'draw')),
  entered_at timestamptz not null,
  confirm_deadline timestamptz not null,
  confirmed_at timestamptz,
  -- References only: losing either account must not delete the result.
  dispute_by uuid references public.profiles (id) on delete set null,
  dispute_reason text,
  flagged_no_show boolean not null default false,
  resolved_by uuid references public.profiles (id) on delete set null,
  resolved_at timestamptz
);

create index match_results_pending on public.match_results (confirm_deadline) where status = 'pending';

create table public.match_result_players (
  result_id uuid not null references public.match_results (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  side text not null check (side in ('a', 'b')),
  confirmed_at timestamptz,
  primary key (result_id, user_id)
);

create index match_result_players_user on public.match_result_players (user_id);

-- One row per player per confirmed result; removed when an admin voids it.
create table public.rating_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  sport_id text not null references public.sports (id),
  result_id uuid not null references public.match_results (id) on delete cascade,
  old_rating numeric(3, 2) not null,
  new_rating numeric(3, 2) not null,
  delta numeric(3, 2) not null,
  created_at timestamptz not null,
  unique (result_id, user_id)
);

create index rating_events_user on public.rating_events (user_id, sport_id, created_at);

alter table public.match_results enable row level security;
alter table public.match_result_players enable row level security;
alter table public.rating_events enable row level security;
revoke all on table public.match_results, public.match_result_players, public.rating_events from anon, authenticated;
grant all on table public.match_results, public.match_result_players, public.rating_events to service_role;

-- ---------------------------------------------------------------------------
-- Scores
-- ---------------------------------------------------------------------------

-- 1-5 sets, each a pair of whole numbers 0-30, never [0, 0]. Anything else
-- raises invalid_argument (checked before any cast).
create function app.check_sets(p_sets jsonb) returns void
language plpgsql immutable
set search_path = ''
as $$
declare
  v_set jsonb;
  v_games jsonb;
begin
  if p_sets is null or jsonb_typeof(p_sets) <> 'array' or jsonb_array_length(p_sets) not between 1 and 5 then
    raise exception 'invalid_argument';
  end if;
  for v_set in select e from jsonb_array_elements(p_sets) e loop
    if jsonb_typeof(v_set) <> 'array' or jsonb_array_length(v_set) <> 2 then raise exception 'invalid_argument'; end if;
    for v_games in select e from jsonb_array_elements(v_set) e loop
      if jsonb_typeof(v_games) <> 'number'
         or (v_games #>> '{}')::numeric not between 0 and 30
         or (v_games #>> '{}')::numeric <> trunc((v_games #>> '{}')::numeric) then
        raise exception 'invalid_argument';
      end if;
    end loop;
    if (v_set ->> 0)::integer = 0 and (v_set ->> 1)::integer = 0 then raise exception 'invalid_argument'; end if;
  end loop;
end $$;

-- More sets won; equal sets -> more games; equal -> draw. Sets already checked.
create function app.score_winner(p_sets jsonb) returns text
language sql immutable
set search_path = ''
as $$
  select case
    when sets_a > sets_b then 'a'
    when sets_b > sets_a then 'b'
    when games_a > games_b then 'a'
    when games_b > games_a then 'b'
    else 'draw'
  end
  from (
    select count(*) filter (where (s ->> 0)::integer > (s ->> 1)::integer) as sets_a,
           count(*) filter (where (s ->> 1)::integer > (s ->> 0)::integer) as sets_b,
           sum((s ->> 0)::integer) as games_a,
           sum((s ->> 1)::integer) as games_b
    from jsonb_array_elements(p_sets) s) t
$$;

-- What notices about a result carry.
create function app.result_note(r public.match_results) returns jsonb
language sql
set search_path = ''
as $$
  select app.game_note(g) || jsonb_build_object('result_id', r.id)
  from public.games g where g.id = r.game_id
$$;

-- {"id", "status", "sets", "winner", "entered_by", "side_a", "side_b",
-- "confirmed_by", "dispute_reason", "flagged_no_show"} and, once confirmed,
-- "changes": {user_id: {"old", "new"}}.
create function app.result_json(r public.match_results) returns jsonb
language sql
set search_path = ''
as $$
  select jsonb_build_object(
    'id', r.id,
    'status', r.status,
    'sets', r.sets,
    'winner', r.winner,
    'entered_by', r.entered_by,
    'side_a', coalesce((select jsonb_agg(p.user_id order by p.user_id) from public.match_result_players p
                        where p.result_id = r.id and p.side = 'a'), '[]'::jsonb),
    'side_b', coalesce((select jsonb_agg(p.user_id order by p.user_id) from public.match_result_players p
                        where p.result_id = r.id and p.side = 'b'), '[]'::jsonb),
    'confirmed_by', coalesce((select jsonb_agg(p.user_id order by p.confirmed_at, p.user_id) from public.match_result_players p
                              where p.result_id = r.id and p.confirmed_at is not null), '[]'::jsonb),
    'dispute_reason', r.dispute_reason,
    'flagged_no_show', r.flagged_no_show)
  || case when r.status = 'confirmed' then jsonb_build_object('changes', coalesce(
       (select jsonb_object_agg(e.user_id, jsonb_build_object('old', e.old_rating, 'new', e.new_rating))
        from public.rating_events e where e.result_id = r.id),
       '{}'::jsonb))
     else '{}'::jsonb end
$$;

-- The host enters (or, 24 hours after the end, any participant), from the end
-- of the game until 7 days after it. Whoever entered a pending score may
-- correct it: the players and sets are replaced, confirmations cleared and
-- the 24 hours start again.
create function app.enter_score(
  p_user uuid, p_game_id uuid, p_side_a uuid[], p_side_b uuid[], p_sets jsonb, p_now timestamptz)
returns public.match_results
language plpgsql
set search_path = ''
as $$
declare
  c_open_for constant interval := interval '7 days';
  c_host_only constant interval := interval '24 hours';
  c_confirm_within constant interval := interval '24 hours';

  v_game public.games;
  v_players uuid[];
  v_result public.match_results;
  v_winner text;
begin
  if p_user is null then raise exception 'not_authenticated'; end if;

  select g.* into v_game from public.games g where g.id = p_game_id for update;
  if not found or v_game.status = 'cancelled' or not app.is_rated_sport(v_game.sport_id)
     or not exists (select 1 from public.game_participants p where p.game_id = p_game_id and p.user_id = p_user) then
    raise exception 'not_found';
  end if;
  if p_now < upper(v_game.during) or p_now >= upper(v_game.during) + c_open_for then
    raise exception 'score_closed';
  end if;
  if v_game.host_id <> p_user and p_now < upper(v_game.during) + c_host_only then
    raise exception 'not_allowed';
  end if;

  -- 1 against 1 or 2 against 2, distinct participants, the caller among them.
  if p_side_a is null or p_side_b is null
     or coalesce(array_ndims(p_side_a), 0) <> 1 or coalesce(array_ndims(p_side_b), 0) <> 1
     or cardinality(p_side_a) not in (1, 2) or cardinality(p_side_a) <> cardinality(p_side_b) then
    raise exception 'invalid_argument';
  end if;
  v_players := p_side_a || p_side_b;
  if array_position(v_players, null) is not null
     or (select count(distinct u) from unnest(v_players) u) <> cardinality(v_players)
     or not (p_user = any (v_players))
     or (select count(*) from public.game_participants p where p.game_id = p_game_id and p.user_id = any (v_players))
        <> cardinality(v_players) then
    raise exception 'invalid_argument';
  end if;
  perform app.check_sets(p_sets);
  v_winner := app.score_winner(p_sets);

  select r.* into v_result from public.match_results r where r.game_id = p_game_id for update;
  if not found then
    insert into public.match_results (game_id, entered_by, status, sets, winner, entered_at, confirm_deadline)
    values (p_game_id, p_user, 'pending', p_sets, v_winner, p_now, p_now + c_confirm_within)
    returning * into v_result;
  elsif v_result.status <> 'pending' then
    raise exception 'already_exists';
  elsif v_result.entered_by <> p_user then
    raise exception 'not_allowed';
  else
    update public.match_results r
    set sets = p_sets, winner = v_winner, entered_at = p_now, confirm_deadline = p_now + c_confirm_within
    where r.id = v_result.id
    returning * into v_result;
    delete from public.match_result_players p where p.result_id = v_result.id;
  end if;

  insert into public.match_result_players (result_id, user_id, side)
  select v_result.id, u, 'a' from unnest(p_side_a) u
  union all
  select v_result.id, u, 'b' from unnest(p_side_b) u;

  perform app.notify(p.user_id, 'score_entered', 'ratings', app.result_note(v_result), p_now)
  from public.match_result_players p
  where p.result_id = v_result.id and p.user_id <> p_user;
  return v_result;
end $$;

-- Moves the ratings of a pending or disputed result and confirms it; does
-- nothing in any other state. A player without a rating first gets the
-- average of those who have one (capped), or the default if nobody has.
create function app.apply_result(p_result_id uuid, p_now timestamptz) returns void
language plpgsql
set search_path = ''
as $$
declare
  v_result public.match_results;
  v_sport text;
  v_start numeric;
  v_rating_a numeric;
  v_rating_b numeric;
  v_expected_a numeric;
  v_actual_a numeric;
  v_games_a integer;
  v_games_b integer;
  v_won integer;
  v_lost integer;
  v_margin numeric;
  v_player record;
  v_k numeric;
  v_actual numeric;
  v_expected numeric;
  v_new numeric;
begin
  select r.* into v_result from public.match_results r where r.id = p_result_id for update;
  if not found or v_result.status not in ('pending', 'disputed') then return; end if;
  select g.sport_id into v_sport from public.games g where g.id = v_result.game_id;

  -- Starting ratings for the players who have none.
  select round(avg(pr.rating), 2) into v_start
  from public.match_result_players p
  join public.player_ratings pr on pr.user_id = p.user_id and pr.sport_id = v_sport
  where p.result_id = p_result_id;
  -- (least() skips nulls, so the default must come first.)
  v_start := least(coalesce(v_start, app.rating_const('unrated_default')), app.rating_const('questionnaire_cap'));
  insert into public.player_ratings (user_id, sport_id, rating, rated_games, source, created_at, updated_at)
  select p.user_id, v_sport, v_start, 0, 'first_result', p_now, p_now
  from public.match_result_players p
  where p.result_id = p_result_id
  order by p.user_id
  on conflict (user_id, sport_id) do nothing;

  -- Two results sharing a player take turns here; ratings are read after.
  perform 1 from public.player_ratings pr
  where pr.sport_id = v_sport
    and pr.user_id in (select p.user_id from public.match_result_players p where p.result_id = p_result_id)
  order by pr.user_id
  for update;

  select avg(pr.rating) filter (where p.side = 'a'), avg(pr.rating) filter (where p.side = 'b')
  into v_rating_a, v_rating_b
  from public.match_result_players p
  join public.player_ratings pr on pr.user_id = p.user_id and pr.sport_id = v_sport
  where p.result_id = p_result_id;

  v_expected_a := 1 / (1 + power(10::numeric, v_rating_b - v_rating_a));
  v_actual_a := case v_result.winner when 'a' then 1 when 'b' then 0 else 0.5 end;

  select sum((s ->> 0)::integer), sum((s ->> 1)::integer) into v_games_a, v_games_b
  from jsonb_array_elements(v_result.sets) s;
  if v_result.winner = 'draw' then
    v_margin := 1.0;
  else
    v_won := case v_result.winner when 'a' then v_games_a else v_games_b end;
    v_lost := case v_result.winner when 'a' then v_games_b else v_games_a end;
    v_margin := app.rating_const('margin_min')
      + app.rating_const('margin_span') * greatest(0, (v_won - v_lost)::numeric / (v_won + v_lost));
  end if;

  for v_player in
    select p.user_id, p.side, pr.rating, pr.rated_games
    from public.match_result_players p
    join public.player_ratings pr on pr.user_id = p.user_id and pr.sport_id = v_sport
    where p.result_id = p_result_id
    order by p.user_id
  loop
    v_k := case when v_player.rated_games < app.rating_const('provisional_games')
                then app.rating_const('k_provisional') else app.rating_const('k_established') end;
    v_actual := case when v_player.side = 'a' then v_actual_a else 1 - v_actual_a end;
    v_expected := case when v_player.side = 'a' then v_expected_a else 1 - v_expected_a end;
    v_new := least(app.rating_const('max'), greatest(app.rating_const('min'),
      v_player.rating + round(v_k * v_margin * (v_actual - v_expected), 2)));

    insert into public.rating_events (user_id, sport_id, result_id, old_rating, new_rating, delta, created_at)
    values (v_player.user_id, v_sport, p_result_id, v_player.rating, v_new, v_new - v_player.rating, p_now);
    update public.player_ratings pr
    set rating = v_new, rated_games = pr.rated_games + 1, updated_at = p_now
    where pr.user_id = v_player.user_id and pr.sport_id = v_sport;
    perform app.sync_level(v_player.user_id, v_sport);
    perform app.notify(v_player.user_id, 'rating_updated', 'ratings',
      app.result_note(v_result) || jsonb_build_object('old', v_player.rating, 'new', v_new), p_now);
  end loop;

  update public.match_results r set status = 'confirmed', confirmed_at = p_now where r.id = p_result_id;
end $$;

-- A player in the result, other than whoever entered it, confirms. A
-- confirmation from the other side than the enterer's confirms the result.
create function app.confirm_score(p_user uuid, p_result_id uuid, p_now timestamptz) returns public.match_results
language plpgsql
set search_path = ''
as $$
declare
  v_result public.match_results;
  v_side text;
begin
  if p_user is null then raise exception 'not_authenticated'; end if;
  select r.* into v_result from public.match_results r where r.id = p_result_id for update;
  if not found or v_result.status <> 'pending' or v_result.entered_by = p_user then raise exception 'not_found'; end if;
  update public.match_result_players p set confirmed_at = coalesce(p.confirmed_at, p_now)
  where p.result_id = p_result_id and p.user_id = p_user
  returning p.side into v_side;
  if v_side is null then raise exception 'not_found'; end if;

  if v_side <> (select p.side from public.match_result_players p
                where p.result_id = p_result_id and p.user_id = v_result.entered_by) then
    perform app.apply_result(p_result_id, p_now);
  end if;
  select r.* into v_result from public.match_results r where r.id = p_result_id;
  return v_result;
end $$;

-- Any player in a pending result freezes it for an admin (§6.4).
create function app.dispute_score(p_user uuid, p_result_id uuid, p_reason text, p_now timestamptz)
returns public.match_results
language plpgsql
set search_path = ''
as $$
declare
  v_result public.match_results;
begin
  if p_user is null then raise exception 'not_authenticated'; end if;
  select r.* into v_result from public.match_results r where r.id = p_result_id for update;
  if not found or v_result.status <> 'pending'
     or not exists (select 1 from public.match_result_players p where p.result_id = p_result_id and p.user_id = p_user) then
    raise exception 'not_found';
  end if;
  update public.match_results r
  set status = 'disputed', dispute_by = p_user, dispute_reason = left(nullif(btrim(p_reason), ''), 300)
  where r.id = p_result_id
  returning * into v_result;

  perform app.notify(p.user_id, 'score_disputed', 'ratings', app.result_note(v_result), p_now)
  from public.match_result_players p
  where p.result_id = p_result_id and p.user_id <> p_user;
  return v_result;
end $$;

-- Confirms every pending result whose 24 hours are over; returns how many.
-- A result another call holds right now is left to that call (or the next
-- run), so this never waits on a player's confirmation.
create function app.auto_confirm_scores(p_now timestamptz) returns integer
language plpgsql
set search_path = ''
as $$
declare
  v_id uuid;
  v_count integer := 0;
begin
  for v_id in
    select r.id from public.match_results r
    where r.status = 'pending' and r.confirm_deadline <= p_now
    order by r.confirm_deadline, r.id
  loop
    perform 1 from public.match_results r
    where r.id = v_id and r.status = 'pending' and r.confirm_deadline <= p_now
    for update skip locked;
    if found then
      perform app.apply_result(v_id, p_now);
      v_count := v_count + 1;
    end if;
  end loop;
  return v_count;
end $$;

-- confirm: a disputed result as entered. correct: a disputed result with the
-- admin's sets. void: a pending, disputed or confirmed result; a confirmed
-- one has each player's change taken off their current rating. Each is
-- audited and the players are told.
create function app.admin_resolve_score(
  p_user uuid, p_result_id uuid, p_action text, p_sets jsonb, p_now timestamptz) returns void
language plpgsql
set search_path = ''
as $$
declare
  v_result public.match_results;
  v_before public.match_results;
  v_sport text;
  v_event record;
begin
  perform app.require_admin(p_user);
  if p_action is null or p_action not in ('confirm', 'correct', 'void') then raise exception 'invalid_argument'; end if;

  select r.* into v_result from public.match_results r where r.id = p_result_id for update;
  if not found then raise exception 'not_found'; end if;
  v_before := v_result;

  if p_action in ('confirm', 'correct') then
    if v_result.status <> 'disputed' then raise exception 'not_found'; end if;
    if p_action = 'correct' then
      perform app.check_sets(p_sets);
      update public.match_results r set sets = p_sets, winner = app.score_winner(p_sets) where r.id = p_result_id;
    end if;
    perform app.apply_result(p_result_id, p_now);
  else
    if v_result.status not in ('pending', 'disputed', 'confirmed') then raise exception 'not_found'; end if;
    if v_result.status = 'confirmed' then
      select g.sport_id into v_sport from public.games g where g.id = v_result.game_id;
      perform 1 from public.player_ratings pr
      where pr.sport_id = v_sport
        and pr.user_id in (select e.user_id from public.rating_events e where e.result_id = p_result_id)
      order by pr.user_id
      for update;
      for v_event in
        select e.user_id, e.delta from public.rating_events e where e.result_id = p_result_id order by e.user_id
      loop
        update public.player_ratings pr
        set rating = least(app.rating_const('max'), greatest(app.rating_const('min'), pr.rating - v_event.delta)),
            rated_games = greatest(0, pr.rated_games - 1),
            updated_at = p_now
        where pr.user_id = v_event.user_id and pr.sport_id = v_sport;
        perform app.sync_level(v_event.user_id, v_sport);
      end loop;
      delete from public.rating_events e where e.result_id = p_result_id;
    end if;
    update public.match_results r set status = 'void' where r.id = p_result_id;
  end if;

  update public.match_results r set resolved_by = p_user, resolved_at = p_now
  where r.id = p_result_id
  returning * into v_result;

  perform app.audit(p_user, 'score_' || p_action, 'match_result', p_result_id::text,
    to_jsonb(v_before), to_jsonb(v_result), p_now);
  perform app.notify(p.user_id, 'score_resolved', 'ratings',
    app.result_note(v_result) || jsonb_build_object('action', p_action), p_now)
  from public.match_result_players p
  where p.result_id = p_result_id;
end $$;

-- ---------------------------------------------------------------------------
-- JSON
-- ---------------------------------------------------------------------------

-- Redefined from 20261127100000_ratings.sql: `result` (null, or
-- app.result_json).
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
      '[]'::jsonb),
    'result', (select app.result_json(mr) from public.match_results mr where mr.game_id = g.id))
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

-- ---------------------------------------------------------------------------
-- What the app calls. The score calls return the game afterwards.
-- ---------------------------------------------------------------------------

create function public.enter_score(p_game_id uuid, p_side_a uuid[], p_side_b uuid[], p_sets jsonb) returns jsonb
language sql security definer
set search_path = ''
as $$
  select app.enter_score((select auth.uid()), p_game_id, p_side_a, p_side_b, p_sets, now());
  select app.game_json(g, (select auth.uid())) from public.games g where g.id = p_game_id;
$$;

create function public.confirm_score(p_result_id uuid) returns jsonb
language sql security definer
set search_path = ''
as $$
  select app.confirm_score((select auth.uid()), p_result_id, now());
  select app.game_json(g, (select auth.uid()))
  from public.match_results r join public.games g on g.id = r.game_id
  where r.id = p_result_id;
$$;

create function public.dispute_score(p_result_id uuid, p_reason text default null) returns jsonb
language sql security definer
set search_path = ''
as $$
  select app.dispute_score((select auth.uid()), p_result_id, p_reason, now());
  select app.game_json(g, (select auth.uid()))
  from public.match_results r join public.games g on g.id = r.game_id
  where r.id = p_result_id;
$$;

create function public.admin_resolve_score(p_result_id uuid, p_action text, p_sets jsonb default null) returns void
language sql security definer
set search_path = ''
as $$ select app.admin_resolve_score((select auth.uid()), p_result_id, p_action, p_sets, now()) $$;

revoke all on function
  public.enter_score(uuid, uuid[], uuid[], jsonb),
  public.confirm_score(uuid),
  public.dispute_score(uuid, text),
  public.admin_resolve_score(uuid, text, jsonb)
from public, anon, authenticated;

grant execute on function
  public.enter_score(uuid, uuid[], uuid[], jsonb),
  public.confirm_score(uuid),
  public.dispute_score(uuid, text),
  public.admin_resolve_score(uuid, text, jsonb)
to authenticated, service_role;
