-- Tournament brackets (Milestone 8a, part 4): tournament matches move
-- ratings (design §8.2, §8.3, §9).
--
-- A played match in a rated sport writes an M7 result (match_results with
-- tournament_match_id instead of game_id), entered by the scorer, and
-- app.apply_result confirms it in the same transaction, so it is never
-- pending or disputed outside it: player confirm/dispute, auto-confirm,
-- admin review and no-show flags never reach it. A correction reverses the
-- old result (app.reverse_result, the subtraction M7's admin void did) and,
-- if the new outcome is played, writes and applies a new one. Walkovers,
-- retirements, byes and matches without a winner move nothing.
--
-- Additive apart from match_results.game_id becoming nullable (0 live rows
-- with a tournament match; existing game results keep their game_id).
-- Functions copied from their latest definitions: apply_result, result_note
-- and result_json from 20261127110000_scores.sql, admin_resolve_score from
-- 20261127120000_after_game.sql, after_match_scored (a no-op) from
-- 20261128120000_match_scores.sql.
--
-- Lock order: score entry already holds the tournament lock, the category,
-- its draw and its matches (20261128120000_match_scores.sql); then the
-- match_results row, then its players' player_ratings rows in user_id order
-- (M7's order).

-- ---------------------------------------------------------------------------
-- Schema
-- ---------------------------------------------------------------------------

alter table public.match_results alter column game_id drop not null;
alter table public.match_results
  add column tournament_match_id uuid references public.tournament_matches (id) on delete cascade;
alter table public.match_results
  add constraint match_results_one_source check (num_nonnulls(game_id, tournament_match_id) = 1);
-- One result in force per match; corrections leave the old ones void.
create unique index match_results_tournament_match on public.match_results (tournament_match_id)
  where status <> 'void';

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

-- The sport of a result: its game's, or its tournament's.
create function app.result_sport(r public.match_results) returns text
language sql stable
set search_path = ''
as $$
  select coalesce(
    (select g.sport_id from public.games g where g.id = r.game_id),
    (select t.sport_id
     from public.tournament_matches m
     join public.tournament_categories c on c.id = m.category_id
     join public.tournaments t on t.id = c.tournament_id
     where m.id = r.tournament_match_id))
$$;

-- Takes a result out of force and leaves it void: a confirmed one has each
-- player's stored change taken off their current rating (within the
-- bounds), one rated game fewer, and its rating events deleted. A pending
-- or disputed one only becomes void. Nobody is told here; the caller does.
create function app.reverse_result(p_result_id uuid, p_now timestamptz) returns void
language plpgsql
set search_path = ''
as $$
declare
  v_result public.match_results;
  v_sport text;
  v_event record;
begin
  select r.* into v_result from public.match_results r where r.id = p_result_id for update;
  if not found or v_result.status = 'void' then return; end if;
  if v_result.status = 'confirmed' then
    v_sport := app.result_sport(v_result);
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
end $$;

-- Redefined from 20261127110000_scores.sql. A game's result as before; a
-- tournament result: {"tournament_id", "category_id", "match_id",
-- "title_uz", "title_ru", "title_kk", "title_en", "result_id"}, so a notice
-- opens the tournament page.
create or replace function app.result_note(r public.match_results) returns jsonb
language sql
set search_path = ''
as $$
  select app.game_note(g) || jsonb_build_object('result_id', r.id)
  from public.games g where g.id = r.game_id
  union all
  select jsonb_build_object(
    'tournament_id', t.id,
    'category_id', m.category_id,
    'match_id', m.id,
    'title_uz', t.title_uz,
    'title_ru', t.title_ru,
    'title_kk', t.title_kk,
    'title_en', t.title_en,
    'result_id', r.id)
  from public.tournament_matches m
  join public.tournament_categories c on c.id = m.category_id
  join public.tournaments t on t.id = c.tournament_id
  where m.id = r.tournament_match_id
$$;

-- Redefined from 20261127110000_scores.sql: adds "tournament_match_id"
-- (null for a game's result). Unchanged otherwise:
-- {"id", "status", "sets", "winner", "entered_by", "side_a", "side_b",
-- "confirmed_by", "dispute_reason", "flagged_no_show"} and, once confirmed,
-- "changes": {user_id: {"old", "new"}}.
create or replace function app.result_json(r public.match_results) returns jsonb
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
    'flagged_no_show', r.flagged_no_show,
    'tournament_match_id', r.tournament_match_id)
  || case when r.status = 'confirmed' then jsonb_build_object('changes', coalesce(
       (select jsonb_object_agg(e.user_id, jsonb_build_object('old', e.old_rating, 'new', e.new_rating))
        from public.rating_events e where e.result_id = r.id),
       '{}'::jsonb))
     else '{}'::jsonb end
$$;

-- ---------------------------------------------------------------------------
-- M7 functions with the sport from app.result_sport
-- ---------------------------------------------------------------------------

-- Redefined from 20261127110000_scores.sql: the sport through
-- app.result_sport (a game's or a tournament's). Unchanged otherwise:
-- Moves the ratings of a pending or disputed result and confirms it; does
-- nothing in any other state. A player without a rating first gets the
-- average of those who have one (capped), or the default if nobody has.
-- A result that cannot be applied (app.result_unplayable: a deleted account
-- among its players, or a side left empty or uneven) becomes void instead
-- (no events, no rating rows) and the remaining players hear.
create or replace function app.apply_result(p_result_id uuid, p_now timestamptz) returns void
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
  -- The margin factor as a fraction (numerator / denominator), so the change
  -- is divided once, last (controller ruling R16).
  v_margin_num numeric;
  v_margin_den numeric;
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
  v_sport := app.result_sport(v_result);

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

  -- Exactly a half for equal sides, so an exact half of a change stays exact.
  v_expected_a := case when v_rating_a = v_rating_b then 0.5
                       else 1 / (1 + power(10::numeric, v_rating_b - v_rating_a)) end;
  v_actual_a := case v_result.winner when 'a' then 1 when 'b' then 0 else 0.5 end;

  select sum((s ->> 0)::integer), sum((s ->> 1)::integer) into v_games_a, v_games_b
  from jsonb_array_elements(v_result.sets) s;
  -- margin = margin_min + margin_span × max(0, won − lost) / (won + lost),
  -- kept as margin_min × (won + lost) + margin_span × max(0, won − lost)
  -- over (won + lost); 1 for a draw. won + lost > 0 (no set is 0-0).
  if v_result.winner = 'draw' then
    v_margin_num := 1;
    v_margin_den := 1;
  else
    v_won := case v_result.winner when 'a' then v_games_a else v_games_b end;
    v_lost := case v_result.winner when 'a' then v_games_b else v_games_a end;
    v_margin_num := app.rating_const('margin_min') * (v_won + v_lost)
      + app.rating_const('margin_span') * greatest(0, v_won - v_lost);
    v_margin_den := v_won + v_lost;
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
      v_player.rating + round(v_k * v_margin_num * (v_actual - v_expected) / v_margin_den, 2)));
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

-- Redefined from 20261127120000_after_game.sql: the void branch is
-- app.reverse_result (which finds the sport through app.result_sport).
-- Unchanged otherwise:
-- keep: a confirmed result flagged by a no-show majority: the flag is
-- cleared and the result stays in force; audited as score_keep, no rating
-- changes, nobody is told.
-- confirm: a disputed result as entered. correct: a disputed result with the
-- admin's sets. void: a pending, disputed or confirmed result; a confirmed
-- one has each player's change taken off their current rating. Each is
-- audited and the players are told.
create or replace function app.admin_resolve_score(
  p_user uuid, p_result_id uuid, p_action text, p_sets jsonb, p_now timestamptz) returns void
language plpgsql
set search_path = ''
as $$
declare
  v_result public.match_results;
  v_before public.match_results;
  v_sets jsonb;
begin
  perform app.require_admin(p_user);
  if p_action is null or p_action not in ('confirm', 'correct', 'void', 'keep') then raise exception 'invalid_argument'; end if;

  select r.* into v_result from public.match_results r where r.id = p_result_id for update;
  if not found then raise exception 'not_found'; end if;
  v_before := v_result;

  if p_action = 'keep' then
    if v_result.status <> 'confirmed' or not v_result.flagged_no_show then raise exception 'not_found'; end if;
    update public.match_results r set flagged_no_show = false, resolved_by = p_user, resolved_at = p_now
    where r.id = p_result_id
    returning * into v_result;
    perform app.audit(p_user, 'score_keep', 'match_result', p_result_id::text,
      to_jsonb(v_before), to_jsonb(v_result), p_now);
    return;
  end if;

  if p_action in ('confirm', 'correct') then
    if v_result.status <> 'disputed' then raise exception 'not_found'; end if;
    if p_action = 'correct' then
      v_sets := app.whole_sets(p_sets);
      update public.match_results r set sets = v_sets, winner = app.score_winner(v_sets) where r.id = p_result_id;
    end if;
    perform app.apply_result(p_result_id, p_now);
  else
    if v_result.status not in ('pending', 'disputed', 'confirmed') then raise exception 'not_found'; end if;
    perform app.reverse_result(p_result_id, p_now);
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
-- The score-entry hook
-- ---------------------------------------------------------------------------

-- Redefined from 20261128120000_match_scores.sql (a no-op there). Called at
-- the end of every score entry or correction, under the category's locks.
-- Rated sports only: the result in force for the match (if any) is
-- reversed; then, if the match is now played, a result is written (the
-- scorer as entered_by, the entries' registrant and partner as the sides,
-- the match's sets and winner) and applied at once.
create or replace function app.after_match_scored(p_match_id uuid, p_previous public.tournament_matches, p_now timestamptz)
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_match public.tournament_matches;
  v_sport text;
  v_id uuid;
begin
  select m.* into v_match from public.tournament_matches m where m.id = p_match_id;
  if not found then return; end if;
  select t.sport_id into v_sport
  from public.tournament_categories c join public.tournaments t on t.id = c.tournament_id
  where c.id = v_match.category_id;
  if not app.is_rated_sport(v_sport) then return; end if;

  for v_id in
    select r.id from public.match_results r
    where r.tournament_match_id = p_match_id and r.status <> 'void'
    order by r.id
  loop
    perform app.reverse_result(v_id, p_now);
  end loop;

  if v_match.outcome = 'played' then
    insert into public.match_results (tournament_match_id, entered_by, status, sets, winner, entered_at, confirm_deadline)
    values (p_match_id, v_match.scored_by, 'pending', v_match.sets, v_match.winner, p_now, p_now)
    returning id into v_id;
    insert into public.match_result_players (result_id, user_id, side)
    select v_id, u, 'a' from unnest(app.entry_players(v_match.side_a)) u
    union all
    select v_id, u, 'b' from unnest(app.entry_players(v_match.side_b)) u;
    perform app.apply_result(v_id, p_now);
  end if;
end $$;
