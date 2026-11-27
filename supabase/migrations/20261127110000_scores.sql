-- Milestone 7a, part 2: match scores in rated sports, confirmation and
-- disputes, the rating maths and admin resolution (design
-- 2026-11-27-actra-m7-competitive §5.4-§5.6), then the leaderboard, past
-- games, the finished-game notice, the roster freeze and account deletion
-- for the new tables (§5.4, §5.7, §5.8).
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
    if (v_set ->> 0)::numeric = 0 and (v_set ->> 1)::numeric = 0 then raise exception 'invalid_argument'; end if;
  end loop;
end $$;

-- The sets checked and rewritten as whole numbers ([[6.0, 4]] -> [[6, 4]]),
-- as they are stored: everything that reads stored sets casts to integer.
create function app.whole_sets(p_sets jsonb) returns jsonb
language plpgsql immutable
set search_path = ''
as $$
begin
  perform app.check_sets(p_sets);
  return (select jsonb_agg(jsonb_build_array((s ->> 0)::numeric::integer, (s ->> 1)::numeric::integer) order by n)
          from jsonb_array_elements(p_sets) with ordinality as t (s, n));
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
  v_sets jsonb;
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
        <> cardinality(v_players)
     -- A deleted account stays a participant of past games but plays no more results.
     or exists (select 1 from public.profiles pr where pr.id = any (v_players) and pr.deleted_at is not null) then
    raise exception 'invalid_argument';
  end if;
  v_sets := app.whole_sets(p_sets);
  v_winner := app.score_winner(v_sets);

  select r.* into v_result from public.match_results r where r.game_id = p_game_id for update;
  if not found then
    insert into public.match_results (game_id, entered_by, status, sets, winner, entered_at, confirm_deadline)
    values (p_game_id, p_user, 'pending', v_sets, v_winner, p_now, p_now + c_confirm_within)
    returning * into v_result;
  elsif v_result.status <> 'pending' then
    raise exception 'already_exists';
  elsif v_result.entered_by <> p_user then
    raise exception 'not_allowed';
  else
    update public.match_results r
    set sets = v_sets, winner = v_winner, entered_at = p_now, confirm_deadline = p_now + c_confirm_within
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

-- True when a result cannot be applied: a deleted account among its players,
-- or players that are no longer 1 against 1 or 2 against 2 (an account
-- removed by hand takes its match_result_players row with it).
create function app.result_unplayable(p_result_id uuid) returns boolean
language sql
set search_path = ''
as $$
  select exists (select 1 from public.match_result_players p
                 join public.profiles pr on pr.id = p.user_id
                 where p.result_id = p_result_id and pr.deleted_at is not null)
      or (select count(*) filter (where p.side = 'a') <> count(*) filter (where p.side = 'b')
                 or count(*) not in (2, 4)
          from public.match_result_players p where p.result_id = p_result_id)
$$;

-- Moves the ratings of a pending or disputed result and confirms it; does
-- nothing in any other state. A player without a rating first gets the
-- average of those who have one (capped), or the default if nobody has.
-- A result that cannot be applied (app.result_unplayable: a deleted account
-- among its players, or a side left empty or uneven) becomes void instead
-- (no events, no rating rows) and the remaining players hear.
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
  if app.result_unplayable(p_result_id) then
    update public.match_results r set status = 'void' where r.id = p_result_id returning * into v_result;
    perform app.notify(p.user_id, 'score_resolved', 'ratings',
      app.result_note(v_result) || jsonb_build_object('action', 'void'), p_now)
    from public.match_result_players p
    join public.profiles pr on pr.id = p.user_id
    where p.result_id = p_result_id and pr.deleted_at is null;
    return;
  end if;
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
  -- Never reached after the check above; a null here would turn into a
  -- rating of 1.00 through greatest(), so refuse rather than write it.
  if v_rating_a is null or v_rating_b is null then raise exception 'invalid_result'; end if;

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
    if v_new is null then raise exception 'invalid_result'; end if;

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
-- It touches several results, so it takes every lock up front in the global
-- order, as a single confirm does for one result:
--   1. the due result rows (skip locked: a result another call holds right
--      now is left to that call, or to the next run);
--   2. the starting ratings of players who have none, in one insert ordered
--      by user_id (each from the first of its results, as app.apply_result
--      would compute it), so apply_result later inserts nothing;
--   3. all their players' rating rows, in one statement ordered by user_id.
-- app.apply_result then finds every lock already held. Steps 2 and 3 leave
-- out the results that cannot be applied (app.result_unplayable: a deleted
-- account among their players, or a side left empty or uneven), which
-- apply_result voids without touching any rating.
create function app.auto_confirm_scores(p_now timestamptz) returns integer
language plpgsql
set search_path = ''
as $$
declare
  v_ids uuid[];
  v_rated uuid[];
  v_id uuid;
begin
  select array_agg(t.id order by t.id) into v_ids
  from (select r.id from public.match_results r
        where r.status = 'pending' and r.confirm_deadline <= p_now
        order by r.id
        for update skip locked) t;
  if v_ids is null then return 0; end if;
  select coalesce(array_agg(i), '{}') into v_rated
  from unnest(v_ids) i
  where not app.result_unplayable(i);

  insert into public.player_ratings (user_id, sport_id, rating, rated_games, source, created_at, updated_at)
  select s.user_id, s.sport_id, s.rating, 0, 'first_result', p_now, p_now
  from (
    select distinct on (p.user_id, g.sport_id)
      p.user_id, g.sport_id,
      least(coalesce(
        (select round(avg(pr.rating), 2) from public.match_result_players q
         join public.player_ratings pr on pr.user_id = q.user_id and pr.sport_id = g.sport_id
         where q.result_id = p.result_id),
        app.rating_const('unrated_default')), app.rating_const('questionnaire_cap')) as rating
    from public.match_result_players p
    join public.match_results r on r.id = p.result_id
    join public.games g on g.id = r.game_id
    where p.result_id = any (v_rated)
      and not exists (select 1 from public.player_ratings x where x.user_id = p.user_id and x.sport_id = g.sport_id)
    order by p.user_id, g.sport_id, p.result_id) s
  order by s.user_id, s.sport_id
  on conflict (user_id, sport_id) do nothing;

  perform 1 from public.player_ratings pr
  where exists (select 1 from public.match_result_players p
                join public.match_results r on r.id = p.result_id
                join public.games g on g.id = r.game_id
                where p.result_id = any (v_rated) and p.user_id = pr.user_id and g.sport_id = pr.sport_id)
  order by pr.user_id, pr.sport_id
  for update;

  foreach v_id in array v_ids loop
    perform app.apply_result(v_id, p_now);
  end loop;
  return cardinality(v_ids);
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
  v_sets jsonb;
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
      v_sets := app.whole_sets(p_sets);
      update public.match_results r set sets = v_sets, winner = app.score_winner(v_sets) where r.id = p_result_id;
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

  -- A confirm that apply_result turned into a void (app.result_unplayable)
  -- is audited as one; apply_result has already told the players.
  if p_action in ('confirm', 'correct') and v_result.status = 'void' then
    perform app.audit(p_user, 'score_void', 'match_result', p_result_id::text,
      to_jsonb(v_before), to_jsonb(v_result), p_now);
    return;
  end if;
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

-- ---------------------------------------------------------------------------
-- Leaderboard and past games (design §5.7, §5.8)
-- ---------------------------------------------------------------------------

-- {"rows": [{"position", "id", "name", "rating", "provisional",
-- "rated_games"}], "me": {same keys} | null}. Rows: players of the city with
-- at least one confirmed result in the sport, not deleted, not hidden from
-- search, best first (rating, then rated games, then id), at most p_limit.
-- me: the caller with their place among those players and themselves (so a
-- hidden caller still sees it); null unless the caller's own city is
-- p_city_id and they have a confirmed result in the sport.
create function app.leaderboard(p_user uuid, p_sport_id text, p_city_id text, p_limit integer) returns jsonb
language sql
set search_path = ''
as $$
  with listed as (
    select r.user_id, p.full_name, r.rating, r.rated_games
    from public.player_ratings r
    join public.profiles p on p.id = r.user_id
    where r.sport_id = p_sport_id and r.rated_games >= 1
      and p.city_id = p_city_id and p.deleted_at is null and not p.hidden_from_search
  ),
  ranked as (
    select l.*, row_number() over (order by l.rating desc, l.rated_games desc, l.user_id) as position
    from listed l
  ),
  me as (
    select r.user_id, p.full_name, r.rating, r.rated_games,
           1 + (select count(*) from listed l
                where l.user_id <> r.user_id
                  and (l.rating > r.rating
                       or (l.rating = r.rating and l.rated_games > r.rated_games)
                       or (l.rating = r.rating and l.rated_games = r.rated_games and l.user_id < r.user_id))) as position
    from public.player_ratings r
    join public.profiles p on p.id = r.user_id
    where r.user_id = p_user and r.sport_id = p_sport_id and r.rated_games >= 1
      and p.city_id = p_city_id and p.deleted_at is null
  )
  select jsonb_build_object(
    'rows', coalesce(
      (select jsonb_agg(
                jsonb_build_object(
                  'position', k.position,
                  'id', k.user_id,
                  'name', k.full_name,
                  'rating', k.rating,
                  'provisional', k.rated_games < app.rating_const('provisional_games'),
                  'rated_games', k.rated_games)
                order by k.position)
       from (select * from ranked order by position limit p_limit) k),
      '[]'::jsonb),
    'me', (select jsonb_build_object(
                    'position', m.position,
                    'id', m.user_id,
                    'name', m.full_name,
                    'rating', m.rating,
                    'provisional', m.rated_games < app.rating_const('provisional_games'),
                    'rated_games', m.rated_games)
           from me m))
$$;

-- The player's games (as a participant) that ended in the last 30 days and
-- were not cancelled, the most recent end first, as app.game_json.
create function app.my_past_games(p_user uuid, p_now timestamptz) returns setof jsonb
language sql
set search_path = ''
as $$
  select app.game_json(g, p_user)
  from public.games g
  where g.status <> 'cancelled'
    and upper(g.during) <= p_now
    and upper(g.during) > p_now - interval '30 days'
    and exists (select 1 from public.game_participants p where p.game_id = g.id and p.user_id = p_user)
  order by upper(g.during) desc, g.id
$$;

-- ---------------------------------------------------------------------------
-- Roster freeze, the finished-game notice, the job (design §5.4, §5.8)
-- ---------------------------------------------------------------------------

-- Redefined from 20261124110000_games_v2.sql: once a game has started nobody
-- leaves it (not_found), so nobody steps out of a result. Leaving inside six
-- hours of the start of a game that is still on counts as a late
-- cancellation.
create or replace function app.leave_game(p_user uuid, p_game_id uuid, p_now timestamptz) returns public.games
language plpgsql
set search_path = ''
as $$
declare
  c_free_window constant interval := interval '6 hours';
  v_game public.games;
begin
  if p_user is null then raise exception 'not_authenticated'; end if;

  select g.* into v_game from public.games g where g.id = p_game_id for update;
  if not found or lower(v_game.during) <= p_now then raise exception 'not_found'; end if;
  if v_game.host_id = p_user then raise exception 'host_cannot_leave'; end if;

  delete from public.game_participants p where p.game_id = p_game_id and p.user_id = p_user;
  if not found then raise exception 'not_participant'; end if;

  if v_game.status = 'open' and v_game.completed_at is null then
    if lower(v_game.during) - p_now < c_free_window then
      perform app.reliability_event(p_user, 'late_cancel', v_game.id::text, p_now);
    end if;
    perform app.notify(v_game.host_id, 'game_left', 'games',
      app.game_note(v_game) || jsonb_build_object('actor_name', (select p.full_name from public.profiles p where p.id = p_user)),
      p_now);
  end if;
  return v_game;
end $$;

-- Redefined from 20261124110000_games_v2.sql: a game that ended with at least
-- two players also sends every participant `game_finished` (category games;
-- can_score: true for the host of a game in a rated sport, who enters the
-- score). Open games that have ended: marked completed. A game that ended
-- with at least two players gives one game_completed event to each
-- participant who joined before it started (no credit for solo games or late
-- joiners). Returns how many games were completed.
create or replace function app.complete_games(p_now timestamptz) returns integer
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
      perform app.notify(p.user_id, 'game_finished', 'games',
        app.game_note(v_game) || jsonb_build_object(
          'can_score', p.user_id = v_game.host_id and app.is_rated_sport(v_game.sport_id)),
        p_now)
      from public.game_participants p
      where p.game_id = v_game.id;
    end if;
    v_count := v_count + 1;
  end loop;
  return v_count;
end $$;

-- The reminders job also confirms scores after 24 hours (scheduling by the
-- same name replaces the command; the four existing calls stay).
do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron;
    execute $job$
      select cron.schedule(
        'actra-send-reminders',
        '*/10 * * * *',
        'select app.send_reminders(now()), app.complete_games(now()), app.expire_game_requests(now()), app.expire_tournament_entries(now()), app.auto_confirm_scores(now())')
    $job$;
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- Deleting an account (design §3: delete_account covers every new table)
-- ---------------------------------------------------------------------------

-- Redefined from 20261126110000_launch.sql: the player's pending and
-- disputed results become void (the other players hear), and their rating
-- events and ratings go; confirmed results and the other players' rating
-- changes stay. Games are still left only before they start, so the roster
-- freeze never refuses here.
--
-- Scrubs and closes the account. Admins cannot delete themselves
-- (admin_account): another admin removes the role first. A second call does
-- nothing. Each step selects exactly the rows the normal function accepts,
-- so none of them raises (a change made by someone else in between aborts
-- the whole call, and the client retries). Where a timing rule would refuse
-- (a registration after its deadline, or an entry the player is only invited
-- to) the same change is made directly, with the same notifications. What has started or
-- ended (bookings, games, tournaments that have started) stays as anonymous
-- history, without the player's own notes.
create or replace function app.delete_account(p_user uuid, p_now timestamptz) returns void
language plpgsql
set search_path = ''
as $$
declare
  c_live constant text[] := array['pending_partner', 'registered', 'waitlisted', 'offered'];
  v_profile public.profiles;
  v_phone text;
  v_id uuid;
  v_reg public.tournament_registrations;
  v_tournament public.tournaments;
  v_counted boolean;
  v_other uuid;
  v_result public.match_results;
begin
  if p_user is null then raise exception 'not_authenticated'; end if;
  if app.is_admin(p_user) then raise exception 'admin_account'; end if;

  -- `no key update`: the rows below that reference the profile can still be
  -- written while it is held.
  select p.* into v_profile from public.profiles p where p.id = p_user for no key update;
  if not found or v_profile.deleted_at is not null then return; end if;

  -- Bookings first, then games: the lock order cancel_booking and
  -- host_cancel_game use. A booking's games are cancelled with it
  -- (cancel_games_for_booking), so their players hear once. Inside the late
  -- window cancel_booking does not refuse; it records a late cancellation.
  for v_id in
    select b.id from public.bookings b
    where b.user_id = p_user and b.source = 'app' and b.status = 'confirmed' and lower(b.during) > p_now
    order by b.id
  loop
    perform app.cancel_booking(p_user, v_id, p_now);
  end loop;
  for v_id in select b.id from public.bookings b where b.user_id = p_user and b.status = 'held' order by b.id loop
    perform app.release_hold(p_user, v_id);
  end loop;

  -- Games still to come that the player hosts (the participants hear), then
  -- the ones they joined (the host hears; leaving late is a late cancel, not
  -- a refusal).
  for v_id in
    select g.id from public.games g
    where g.host_id = p_user and g.status = 'open' and g.completed_at is null and lower(g.during) > p_now
    order by g.id
  loop
    perform app.host_cancel_game(p_user, v_id, false, p_now);
  end loop;
  for v_id in
    select g.id from public.game_participants gp
    join public.games g on g.id = gp.game_id
    where gp.user_id = p_user and g.host_id <> p_user
      and g.status = 'open' and g.completed_at is null and lower(g.during) > p_now
    order by g.id
  loop
    perform app.leave_game(p_user, v_id, p_now);
  end loop;
  for v_id in select r.id from public.game_join_requests r where r.user_id = p_user and r.status = 'pending' order by r.id loop
    perform app.withdraw_join_request(p_user, v_id);
  end loop;
  for v_id in select i.game_id from public.game_invites i where i.user_id = p_user and i.status = 'pending' order by i.game_id loop
    perform app.decline_invite(p_user, v_id);
  end loop;

  -- Game Requests: the player's open ones, and their "I'm in" on open ones.
  for v_id in select r.id from public.game_requests r where r.host_id = p_user and r.status = 'open' order by r.id loop
    perform app.cancel_game_request(p_user, v_id);
  end loop;
  for v_id in
    select i.request_id from public.game_request_interest i
    join public.game_requests r on r.id = i.request_id
    where i.user_id = p_user and r.status = 'open'
    order by i.request_id
  loop
    perform app.withdraw_interest(p_user, v_id);
  end loop;

  -- Live entries, as registrant or named partner, in tournaments that have
  -- not started yet (a tournament starting today in venue time has started;
  -- its entries stay as history). Every category involved is locked first, in id order, before
  -- any tournament row (as expire_tournament_entries does), so this never
  -- deadlocks with a player's call in one of them.
  perform 1 from public.tournament_categories c
  where c.id in (
    select r.category_id from public.tournament_registrations r
    where (r.user_id = p_user or r.partner_id = p_user) and r.status = any (c_live))
  order by c.id
  for update;
  for v_id in
    select r.id from public.tournament_registrations r
    join public.tournament_categories c on c.id = r.category_id
    join public.tournaments t on t.id = c.tournament_id
    where (r.user_id = p_user or r.partner_id = p_user)
      and r.status = any (c_live)
      and t.starts_on > app.to_local(p_now, app.tournament_offset(t))::date
    order by r.category_id, r.id
  loop
    v_reg := app.lock_registration(v_id);
    if v_reg.id is null then continue; end if;
    -- Expired invites and offers are settled the usual way first.
    perform app.sweep_category(v_reg.category_id, p_now);
    select r.* into v_reg from public.tournament_registrations r where r.id = v_id;
    if not (v_reg.status = any (c_live)) then continue; end if;
    select t.* into v_tournament from public.tournaments t
    join public.tournament_categories c on c.tournament_id = t.id
    where c.id = v_reg.category_id;

    if app.entry_member(v_reg, p_user) and v_tournament.active and p_now < app.tournament_deadline(v_tournament) then
      perform app.cancel_registration(p_user, v_reg.id, p_now);
    else
      -- What cancel_registration does, for the entries it refuses: after the
      -- deadline, in a hidden tournament, or a pair still waiting on this
      -- player as partner.
      v_counted := v_reg.status in ('registered', 'offered');
      update public.tournament_registrations r set status = 'cancelled', cancelled_at = p_now
      where r.id = v_reg.id returning * into v_reg;
      v_other := case when v_reg.user_id = p_user then v_reg.partner_id else v_reg.user_id end;
      if v_other is not null then
        perform app.notify(v_other, 'tournament_partner_cancelled', 'tournaments',
          app.registration_note(v_reg) || jsonb_build_object('actor_name', v_profile.full_name), p_now);
      end if;
      if v_counted then perform app.offer_next(v_reg.category_id, p_now); end if;
      perform app.sync_tournament_summary(v_tournament.id);
    end if;
  end loop;

  -- Results not yet confirmed that the player is in become void. Each result
  -- row is locked before it changes, and before the player's rating row
  -- below (the order score confirmation uses); one confirmed in between is
  -- left as it is.
  for v_id in
    select r.id from public.match_results r
    join public.match_result_players p on p.result_id = r.id
    where p.user_id = p_user and r.status in ('pending', 'disputed')
    order by r.id
  loop
    select r.* into v_result from public.match_results r where r.id = v_id for update;
    if v_result.status not in ('pending', 'disputed') then continue; end if;
    update public.match_results r set status = 'void' where r.id = v_id returning * into v_result;
    perform app.notify(p.user_id, 'score_resolved', 'ratings',
      app.result_note(v_result) || jsonb_build_object('action', 'void'), p_now)
    from public.match_result_players p
    where p.result_id = v_id and p.user_id <> p_user;
  end loop;
  -- The ratings first: an in-flight confirmation holds them until it has
  -- written its events, which the second delete then sees.
  delete from public.player_ratings r where r.user_id = p_user;
  delete from public.rating_events e where e.user_id = p_user;

  -- A venue left without an owner stays; an admin assigns a new one, and
  -- the audit log says which venue needs it.
  for v_id in select o.venue_id from public.venue_owners o where o.user_id = p_user order by o.venue_id loop
    if not exists (select 1 from public.venue_owners o where o.venue_id = v_id and o.user_id <> p_user) then
      perform app.audit(p_user, 'owner_account_deleted', 'venue', v_id::text, null, null, p_now);
    end if;
  end loop;

  -- Personal rows.
  select pc.phone into v_phone from public.profile_contacts pc where pc.user_id = p_user;
  delete from public.login_tokens t where t.phone = v_phone;
  delete from public.profile_contacts pc where pc.user_id = p_user;
  delete from public.player_levels l where l.user_id = p_user;
  delete from public.venue_owners o where o.user_id = p_user;
  delete from public.notifications n where n.user_id = p_user;
  delete from public.phone_lookups l where l.user_id = p_user;

  -- The player's own free text, on every row they wrote it on, past and
  -- future: booking notes (owners see them), notes and meeting points on the
  -- games they host, notes and areas on their Game Requests. A meeting-point
  -- game must keep a meeting point (games_meeting_point_for_map_point), so it
  -- gets '' there, which game_json shows as null. The map coordinates of the
  -- meeting point go too (they are nullable, no constraint ties them).
  update public.bookings b set note = null
  where b.user_id = p_user and b.source = 'app' and b.note is not null;
  update public.games g
  set note = null,
      meeting_point = case when g.kind = 'map_point' then '' end,
      meeting_lat = null,
      meeting_lng = null
  where g.host_id = p_user
    and (g.note is not null or g.meeting_point is not null or g.meeting_lat is not null or g.meeting_lng is not null);
  update public.game_requests r set note = null, area = null
  where r.host_id = p_user and (r.note is not null or r.area is not null);

  -- Last, so the notifications above still carry the player's name.
  update public.profiles p
  set full_name = null,
      city_id = null,
      language = null,
      muted_categories = '{}',
      hidden_from_search = true,
      last_seen_at = null,
      deleted_at = p_now
  where p.id = p_user;
end $$;

-- ---------------------------------------------------------------------------
-- What the app calls: the leaderboard (top 100) and past games.
-- ---------------------------------------------------------------------------

create function public.leaderboard(p_sport_id text, p_city_id text) returns jsonb
language sql security definer
set search_path = ''
as $$ select app.leaderboard((select auth.uid()), p_sport_id, p_city_id, 100) $$;

create function public.my_past_games() returns setof jsonb
language sql security definer
set search_path = ''
as $$ select app.my_past_games((select auth.uid()), now()) $$;

revoke all on function public.leaderboard(text, text), public.my_past_games() from public, anon, authenticated;
grant execute on function public.leaderboard(text, text), public.my_past_games() to authenticated, service_role;
