-- Tournament brackets (Milestone 8a, part 3): scores, advancement, group
-- standings and withdrawals (design §7.1, §7.3-§7.6, §14a.3-§14a.9).
--
-- Additive only: new functions, and functions copied from their latest
-- definitions (draw_json from 20261128100000_draws.sql, tournament_bracket
-- from 20261128110000_schedule.sql, delete_account from
-- 20261127130000_teams.sql).
--
-- Lock order (20261128100000_draws.sql): the tournament advisory lock, the
-- category row, its draw row, then every match of the category in (stage,
-- round, position) order, then the registration row, then bookings (a
-- released block). Score entry and withdrawal lock all of the category's
-- matches up front, since advancing can touch any later round.
--
-- How a knockout settles. A match's winner goes to the next match (round
-- r + 1, position (p + 1) / 2; odd positions are side a). A side that will
-- never come is "empty": a bye, a match with no winner (`none`), or a
-- withdrawn entry. A match with one empty side and the other known is done
-- at once for the known side (`bye` in the first round, where only byes are
-- empty, `walkover` later); with both empty it is done with no winner
-- (`none`) and its own next side becomes empty. So every match ends `done`
-- however many entries withdraw.

-- ---------------------------------------------------------------------------
-- Helpers. Not stable: each must see rows written earlier in the same call.
-- ---------------------------------------------------------------------------

-- Every match of the category, locked in the global order.
create function app.lock_matches(p_category_id uuid) returns void
language plpgsql
set search_path = ''
as $$
begin
  perform 1 from public.tournament_matches m
  where m.category_id = p_category_id
  order by m.stage, m.round, m.position, m.id
  for update;
end $$;

-- The entry that won a done match, or null (a draw, no winner).
create function app.match_winner_entry(m public.tournament_matches) returns uuid
language sql immutable
set search_path = ''
as $$ select case m.winner when 'a' then m.side_a when 'b' then m.side_b end $$;

create function app.entry_withdrawn(p_registration_id uuid) returns boolean
language sql
set search_path = ''
as $$
  select coalesce((select e.withdrawn_at is not null from public.tournament_draw_entries e
                   where e.registration_id = p_registration_id), false)
$$;

-- A match that will not be played: before its start, its calendar block is
-- released and its court and time are cleared, so it never counts as a
-- player's busy slot. From its start on the court was used: both stay.
create function app.match_not_played(p_match_id uuid, p_now timestamptz) returns void
language plpgsql
set search_path = ''
as $$
begin
  if exists (select 1 from public.tournament_matches m where m.id = p_match_id and m.starts_at > p_now) then
    perform app.release_match_block(p_match_id);
    update public.tournament_matches m set court_id = null, starts_at = null where m.id = p_match_id;
  end if;
end $$;

-- Puts what a knockout match produced into its side of the next match: the
-- winner; an empty side when it is done without one (or its winner has
-- withdrawn); nothing yet (an unknown side) while it is not done. Then
-- settles the next match. Nothing for a group match or the final.
create function app.place_winner(p_match_id uuid, p_now timestamptz) returns void
language plpgsql
set search_path = ''
as $$
declare
  v_match public.tournament_matches;
  v_next public.tournament_matches;
  v_entry uuid;
  v_empty boolean := false;
begin
  select m.* into v_match from public.tournament_matches m where m.id = p_match_id;
  if not found or v_match.stage <> 'knockout' then return; end if;
  select m.* into v_next from public.tournament_matches m
  where m.category_id = v_match.category_id and m.stage = 'knockout'
    and m.round = v_match.round + 1 and m.position = (v_match.position + 1) / 2;
  if not found then return; end if;

  if v_match.status = 'done' then
    v_entry := app.match_winner_entry(v_match);
    if v_entry is null or app.entry_withdrawn(v_entry) then
      v_entry := null;
      v_empty := true;
    end if;
  end if;

  if v_match.position % 2 = 1 then
    if v_next.side_a is not distinct from v_entry and v_next.a_empty = v_empty then return; end if;
    update public.tournament_matches m set side_a = v_entry, a_empty = v_empty where m.id = v_next.id;
  else
    if v_next.side_b is not distinct from v_entry and v_next.b_empty = v_empty then return; end if;
    update public.tournament_matches m set side_b = v_entry, b_empty = v_empty where m.id = v_next.id;
  end if;
  perform app.settle_match(v_next.id, p_now);
end $$;

-- Recomputes the state of a knockout match nobody has scored (not done, or
-- done as a bye or with no winner) from its sides, as the header describes,
-- and passes any change on to the next match.
create function app.settle_match(p_match_id uuid, p_now timestamptz) returns void
language plpgsql
set search_path = ''
as $$
declare
  v_match public.tournament_matches;
  v_status text;
  v_outcome text;
  v_winner text;
begin
  select m.* into v_match from public.tournament_matches m where m.id = p_match_id;
  if not found or v_match.stage <> 'knockout' then return; end if;
  if v_match.status = 'done' and v_match.outcome not in ('bye', 'none') then return; end if;

  if v_match.a_empty and v_match.b_empty then
    v_status := 'done'; v_outcome := 'none'; v_winner := null;
  elsif v_match.a_empty and v_match.side_b is not null then
    v_status := 'done'; v_outcome := case when v_match.round = 1 then 'bye' else 'walkover' end; v_winner := 'b';
  elsif v_match.b_empty and v_match.side_a is not null then
    v_status := 'done'; v_outcome := case when v_match.round = 1 then 'bye' else 'walkover' end; v_winner := 'a';
  elsif v_match.side_a is not null and v_match.side_b is not null then
    v_status := 'ready'; v_outcome := null; v_winner := null;
  else
    v_status := 'waiting'; v_outcome := null; v_winner := null;
  end if;

  if v_status = v_match.status and v_outcome is not distinct from v_match.outcome
     and v_winner is not distinct from v_match.winner then
    return;
  end if;
  update public.tournament_matches m
  set status = v_status, outcome = v_outcome, winner = v_winner, sets = null, scored_by = null,
      scored_at = case when v_status = 'done' then p_now end
  where m.id = v_match.id;
  if v_status = 'done' then perform app.match_not_played(v_match.id, p_now); end if;
  perform app.place_winner(v_match.id, p_now);
end $$;

-- A score as stored, checked: a rated sport's M7 sets, or for any other
-- sport exactly one pair of whole numbers 0-99 (invalid_argument otherwise;
-- checked before any cast).
create function app.match_sets(p_sets jsonb, p_rated boolean) returns jsonb
language plpgsql immutable
set search_path = ''
as $$
declare
  v_pair jsonb;
  v_value jsonb;
begin
  if p_rated then return app.whole_sets(p_sets); end if;
  if p_sets is null or jsonb_typeof(p_sets) <> 'array' or jsonb_array_length(p_sets) <> 1 then
    raise exception 'invalid_argument';
  end if;
  v_pair := p_sets -> 0;
  if jsonb_typeof(v_pair) <> 'array' or jsonb_array_length(v_pair) <> 2 then raise exception 'invalid_argument'; end if;
  for v_value in select e from jsonb_array_elements(v_pair) e loop
    if jsonb_typeof(v_value) <> 'number'
       or (v_value #>> '{}')::numeric not between 0 and 99
       or (v_value #>> '{}')::numeric <> trunc((v_value #>> '{}')::numeric) then
      raise exception 'invalid_argument';
    end if;
  end loop;
  return jsonb_build_array(jsonb_build_array((v_pair ->> 0)::numeric::integer, (v_pair ->> 1)::numeric::integer));
end $$;

-- ---------------------------------------------------------------------------
-- Group standings (§7.6, §14a.5)
-- ---------------------------------------------------------------------------

-- One row per entry of the group, in place order. Points: win 2, draw 1,
-- loss 0, a walkover counts as a win or loss. Sets and games come from
-- played and retired matches only. Order: withdrawn entries last; points;
-- head-to-head (points from the matches among the entries level on points);
-- set difference; game difference; seed.
create function app.group_table(p_group_id uuid)
returns table (
  registration_id uuid, seed integer, withdrawn boolean, played integer, won integer, drawn integer, lost integer,
  points integer, sets_for integer, sets_against integer, games_for integer, games_against integer, place integer)
language sql
set search_path = ''
as $$
  with entries as (
    select e.registration_id, e.seed, e.withdrawn_at is not null as withdrawn
    from public.tournament_draw_entries e where e.group_id = p_group_id
  ),
  sides as (
    select x.reg, x.opp, m.outcome,
      case when m.winner = 'draw' then 1 when m.winner = x.side then 2 else 0 end as pts,
      case when m.winner = 'draw' then 'd' when m.winner = x.side then 'w' else 'l' end as res,
      case when m.outcome in ('played', 'retired') then m.sets end as sets,
      x.mine, x.theirs
    from public.tournament_matches m
    cross join lateral (values (m.side_a, m.side_b, 'a', 0, 1), (m.side_b, m.side_a, 'b', 1, 0)) x (reg, opp, side, mine, theirs)
    where m.group_id = p_group_id and m.status = 'done' and m.winner is not null
  ),
  totals as (
    select e.registration_id, e.seed, e.withdrawn,
      count(s.reg)::integer as played,
      count(s.reg) filter (where s.res = 'w')::integer as won,
      count(s.reg) filter (where s.res = 'd')::integer as drawn,
      count(s.reg) filter (where s.res = 'l')::integer as lost,
      coalesce(sum(s.pts), 0)::integer as points,
      coalesce(sum((select count(*) from jsonb_array_elements(s.sets) g where (g ->> s.mine)::integer > (g ->> s.theirs)::integer)), 0)::integer as sets_for,
      coalesce(sum((select count(*) from jsonb_array_elements(s.sets) g where (g ->> s.theirs)::integer > (g ->> s.mine)::integer)), 0)::integer as sets_against,
      coalesce(sum((select sum((g ->> s.mine)::integer) from jsonb_array_elements(s.sets) g)), 0)::integer as games_for,
      coalesce(sum((select sum((g ->> s.theirs)::integer) from jsonb_array_elements(s.sets) g)), 0)::integer as games_against
    from entries e
    left join sides s on s.reg = e.registration_id
    group by e.registration_id, e.seed, e.withdrawn
  ),
  ranked as (
    select t.*,
      coalesce((select sum(s.pts) from sides s join totals o on o.registration_id = s.opp
                where s.reg = t.registration_id and o.points = t.points and not o.withdrawn), 0) as h2h
    from totals t
  )
  select r.registration_id, r.seed, r.withdrawn, r.played, r.won, r.drawn, r.lost, r.points,
    r.sets_for, r.sets_against, r.games_for, r.games_against,
    row_number() over (order by r.withdrawn, r.points desc, r.h2h desc, r.sets_for - r.sets_against desc,
      r.games_for - r.games_against desc, r.seed)::integer as place
  from ranked r
  order by place
$$;

-- [{"registration_id", "played", "won", "drawn", "lost", "points",
-- "sets_for", "sets_against", "games_for", "games_against", "place",
-- "advancing", "withdrawn"}] in place order. advancing: within the places
-- that go through (the draw's advance count) and not withdrawn.
create function app.group_standings(p_group_id uuid) returns jsonb
language sql
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
      'registration_id', t.registration_id,
      'played', t.played,
      'won', t.won,
      'drawn', t.drawn,
      'lost', t.lost,
      'points', t.points,
      'sets_for', t.sets_for,
      'sets_against', t.sets_against,
      'games_for', t.games_for,
      'games_against', t.games_against,
      'place', t.place,
      'advancing', t.place <= coalesce(d.advance, 0) and not t.withdrawn,
      'withdrawn', t.withdrawn) order by t.place), '[]'::jsonb)
  from app.group_table(p_group_id) t
  cross join public.tournament_groups g
  left join public.tournament_draws d on d.category_id = g.category_id
  where g.id = p_group_id
$$;

-- ---------------------------------------------------------------------------
-- From the groups into the knockout (§7.3, §14a.6)
-- ---------------------------------------------------------------------------

-- Once every group match of a groups draw is done, and while the knockout
-- has nothing but byes settled, (re)places the qualifiers in its first
-- round: all group winners first, ordered by points per match, set
-- difference per match, game difference per match, then seed; then the
-- runners-up the same way. Qualifier k takes seed k's slot (seed_order);
-- seeds beyond the qualifiers are byes. A lower qualifier in the same half
-- as a better one from its group swaps with the nearest-ranked runner-up of
-- another group in the other half whose own group-mate is not in this half.
-- A withdrawn entry that would qualify (its group has too few others)
-- leaves its slot empty. Courts and times already set stay.
create function app.fill_knockout(p_category_id uuid, p_now timestamptz) returns void
language plpgsql
set search_path = ''
as $$
declare
  v_draw public.tournament_draws;
  v_groups integer;
  v_count integer;
  v_size integer;
  v_order integer[];
  v_quals uuid[];
  v_qgroup uuid[];
  v_slot integer[];      -- slot of qualifier k
  v_rank integer[];      -- the qualifier at each slot, null for a bye
  v_half integer;
  v_best integer;
  v_best_distance integer;
  v_tmp integer;
  v_conflict boolean;
  v_match public.tournament_matches;
  v_a uuid;
  v_b uuid;
  r record;
  i integer;
  k integer;
  c integer;
begin
  select d.* into v_draw from public.tournament_draws d where d.category_id = p_category_id;
  if v_draw.format is distinct from 'groups' then return; end if;
  if exists (select 1 from public.tournament_matches m
             where m.category_id = p_category_id and m.stage = 'group' and m.status <> 'done') then
    return;
  end if;
  select count(*)::integer into v_groups from public.tournament_groups g where g.category_id = p_category_id;
  v_count := v_groups * v_draw.advance;
  if v_count < 2 then return; end if;
  if exists (select 1 from public.tournament_matches m
             where m.category_id = p_category_id and m.stage = 'knockout' and m.outcome is not null and m.outcome <> 'bye') then
    return;
  end if;

  -- The qualifiers in rank order.
  v_quals := '{}';
  v_qgroup := '{}';
  for r in
    select t.registration_id, t.withdrawn, g.id as group_id
    from public.tournament_groups g
    cross join lateral app.group_table(g.id) t
    where g.category_id = p_category_id and t.place <= v_draw.advance
    order by t.place, t.withdrawn,
      t.points::numeric / nullif(t.played, 0) desc nulls last,
      (t.sets_for - t.sets_against)::numeric / nullif(t.played, 0) desc nulls last,
      (t.games_for - t.games_against)::numeric / nullif(t.played, 0) desc nulls last,
      t.seed, g.sort_order
  loop
    v_quals := v_quals || case when r.withdrawn then null::uuid else r.registration_id end;
    v_qgroup := v_qgroup || r.group_id;
  end loop;

  v_size := app.bracket_size(v_count);
  v_order := app.seed_order(v_size);
  -- slot (1-based, in bracket order) of each seed, and of each qualifier.
  v_slot := array_fill(0, array[v_count]);
  for i in 1..v_size loop
    if v_order[i] <= v_count then v_slot[v_order[i]] := i; end if;
  end loop;

  -- Same-group pairs apart where possible.
  for k in 1..v_count loop
    v_half := case when v_slot[k] <= v_size / 2 then 1 else 2 end;
    v_conflict := false;
    for c in 1..(k - 1) loop
      if v_qgroup[c] = v_qgroup[k] and (case when v_slot[c] <= v_size / 2 then 1 else 2 end) = v_half then
        v_conflict := true;
      end if;
    end loop;
    continue when not v_conflict;
    v_best := null;
    v_best_distance := null;
    for c in (v_groups + 1)..v_count loop
      continue when c = k or v_qgroup[c] = v_qgroup[k];
      continue when (case when v_slot[c] <= v_size / 2 then 1 else 2 end) = v_half;
      -- c moves into this half: its own group-mate must not be here.
      continue when exists (
        select 1 from generate_series(1, v_count) o
        where o <> c and o <> k and v_qgroup[o] = v_qgroup[c]
          and (case when v_slot[o] <= v_size / 2 then 1 else 2 end) = v_half);
      if v_best is null or abs(c - k) < v_best_distance or (abs(c - k) = v_best_distance and c > v_best) then
        v_best := c;
        v_best_distance := abs(c - k);
      end if;
    end loop;
    if v_best is not null then
      v_tmp := v_slot[k];
      v_slot[k] := v_slot[v_best];
      v_slot[v_best] := v_tmp;
    end if;
  end loop;

  v_rank := array_fill(null::integer, array[v_size]);
  for k in 1..v_count loop v_rank[v_slot[k]] := k; end loop;

  -- Start the knockout afresh, keeping courts and times.
  update public.tournament_matches m
  set side_a = null, side_b = null, a_empty = false, b_empty = false,
      status = 'waiting', outcome = null, winner = null, sets = null, scored_by = null, scored_at = null
  where m.category_id = p_category_id and m.stage = 'knockout';
  for i in 1..(v_size / 2) loop
    v_a := case when v_rank[2 * i - 1] is not null then v_quals[v_rank[2 * i - 1]] end;
    v_b := case when v_rank[2 * i] is not null then v_quals[v_rank[2 * i]] end;
    update public.tournament_matches m
    set side_a = v_a, side_b = v_b, a_empty = v_a is null, b_empty = v_b is null
    where m.category_id = p_category_id and m.stage = 'knockout' and m.round = 1 and m.position = i;
  end loop;
  for v_match in
    select m.* from public.tournament_matches m
    where m.category_id = p_category_id and m.stage = 'knockout' and m.round = 1
    order by m.position
  loop
    perform app.settle_match(v_match.id, p_now);
  end loop;
end $$;

-- ---------------------------------------------------------------------------
-- The category's result
-- ---------------------------------------------------------------------------

-- {"winner", "runner_up", "finished"} of a published draw: the final's
-- winner and the other finalist; for a single group with one advancing, the
-- first two places once every group match is done. finished: the final (or
-- the group) is done. Registration ids or null.
create function app.category_result(p_category_id uuid) returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  v_draw public.tournament_draws;
  v_final public.tournament_matches;
  v_first uuid;
  v_second uuid;
begin
  select d.* into v_draw from public.tournament_draws d where d.category_id = p_category_id;
  if not found or v_draw.status <> 'published' then
    return jsonb_build_object('winner', null, 'runner_up', null, 'finished', false);
  end if;

  select m.* into v_final from public.tournament_matches m
  where m.category_id = p_category_id and m.stage = 'knockout'
  order by m.round desc, m.position
  limit 1;
  if found then
    if v_final.status <> 'done' then
      return jsonb_build_object('winner', null, 'runner_up', null, 'finished', false);
    end if;
    return jsonb_build_object(
      'winner', app.match_winner_entry(v_final),
      'runner_up', case v_final.winner when 'a' then v_final.side_b when 'b' then v_final.side_a end,
      'finished', true);
  end if;

  -- One group, one advancing: the group decides.
  if not exists (select 1 from public.tournament_matches m where m.category_id = p_category_id and m.stage = 'group')
     or exists (select 1 from public.tournament_matches m
                where m.category_id = p_category_id and m.stage = 'group' and m.status <> 'done') then
    return jsonb_build_object('winner', null, 'runner_up', null, 'finished', false);
  end if;
  select t.registration_id into v_first
  from public.tournament_groups g cross join lateral app.group_table(g.id) t
  where g.category_id = p_category_id and t.place = 1 and not t.withdrawn;
  select t.registration_id into v_second
  from public.tournament_groups g cross join lateral app.group_table(g.id) t
  where g.category_id = p_category_id and t.place = 2 and not t.withdrawn;
  return jsonb_build_object('winner', v_first, 'runner_up', v_second, 'finished', true);
end $$;

-- category_won to the players of the category's winner when the winner is
-- new (p_before: the winner before this change).
create function app.announce_winner(p_category_id uuid, p_before uuid, p_now timestamptz) returns void
language plpgsql
set search_path = ''
as $$
declare
  v_winner uuid := (app.category_result(p_category_id) ->> 'winner')::uuid;
  v_tournament_id uuid;
  v_player uuid;
begin
  if v_winner is null or v_winner is not distinct from p_before then return; end if;
  select c.tournament_id into v_tournament_id from public.tournament_categories c where c.id = p_category_id;
  foreach v_player in array app.entry_players(v_winner) loop
    perform app.notify(v_player, 'category_won', 'tournaments',
      app.tournament_note(v_tournament_id, p_category_id) || jsonb_build_object('registration_id', v_winner), p_now);
  end loop;
end $$;

-- match_result about p_match_id to every player of p_players.
create function app.notify_match_result(p_match_id uuid, p_players uuid[], p_correction boolean, p_now timestamptz) returns void
language plpgsql
set search_path = ''
as $$
declare
  v_match public.tournament_matches;
  v_payload jsonb;
  v_player uuid;
begin
  select m.* into v_match from public.tournament_matches m where m.id = p_match_id;
  v_payload := app.tournament_note((select c.tournament_id from public.tournament_categories c where c.id = v_match.category_id),
      v_match.category_id)
    || jsonb_build_object(
      'match_id', v_match.id,
      'side_a', v_match.side_a,
      'side_b', v_match.side_b,
      'outcome', v_match.outcome,
      'winner', v_match.winner,
      'sets', v_match.sets,
      'correction', p_correction);
  for v_player in select distinct x from unnest(p_players) x where x is not null loop
    perform app.notify(v_player, 'match_result', 'tournaments', v_payload, p_now);
  end loop;
end $$;

-- ---------------------------------------------------------------------------
-- Score entry (§7.3, §7.4, §14a.4, §14a.8)
-- ---------------------------------------------------------------------------

-- Task 4 (ratings) fills this in. Called at the end of every score entry or
-- correction with the match as it was before.
create function app.after_match_scored(p_match_id uuid, p_previous public.tournament_matches, p_now timestamptz)
returns void
language plpgsql
set search_path = ''
as $$
begin
  null;
end $$;

-- Enters or corrects a match's result. The match must be in a published
-- draw with both sides known (not_found). Outcomes: played (rated sport: M7
-- sets, winner by score_winner; other sports: one pair 0-99, the higher
-- wins, level is a draw); decider (a level pair in a knockout match of a
-- sport without sets, the organiser names the winner); walkover (winner
-- named, no score; before the start the block is released); retired (winner
-- named, the score so far). A draw in a knockout match: draw_not_allowed.
-- A correction is refused (next_match_played) once the match that depends
-- on it has a score: for a knockout match the next match, for a group match
-- any knockout match of the category (a bye aside). An organiser who plays
-- may score their own match (§14a.8).
create function app.enter_match_score(
  p_user uuid, p_match_id uuid, p_outcome text, p_winner text, p_sets jsonb, p_now timestamptz)
returns void
language plpgsql
set search_path = ''
as $$
declare
  c_scored constant text[] := array['played', 'walkover', 'retired', 'decider'];
  v_match public.tournament_matches;
  v_previous public.tournament_matches;
  v_draw public.tournament_draws;
  v_sport text;
  v_rated boolean;
  v_sets jsonb;
  v_winner text;
  v_next public.tournament_matches;
  v_correction boolean;
  v_won_before uuid;
  v_entry uuid;
begin
  select m.* into v_match from public.tournament_matches m where m.id = p_match_id;
  if not found then raise exception 'not_found'; end if;
  v_draw := app.lock_draw(p_user, v_match.category_id);
  if v_draw.category_id is null or v_draw.status <> 'published' then raise exception 'not_found'; end if;
  perform app.lock_matches(v_match.category_id);
  -- Read again under the locks: a redo or another entry may have got in first.
  select m.* into v_previous from public.tournament_matches m where m.id = p_match_id;
  if not found or v_previous.side_a is null or v_previous.side_b is null
     or v_previous.outcome in ('bye', 'none') then
    raise exception 'not_found';
  end if;
  select t.sport_id into v_sport
  from public.tournament_categories c join public.tournaments t on t.id = c.tournament_id
  where c.id = v_previous.category_id;
  v_rated := app.is_rated_sport(v_sport);

  if p_outcome = 'played' then
    v_sets := app.match_sets(p_sets, v_rated);
    if v_rated then
      v_winner := app.score_winner(v_sets);
    else
      v_winner := case
        when (v_sets #>> '{0,0}')::integer > (v_sets #>> '{0,1}')::integer then 'a'
        when (v_sets #>> '{0,0}')::integer < (v_sets #>> '{0,1}')::integer then 'b'
        else 'draw' end;
    end if;
  elsif p_outcome = 'decider' then
    if v_rated or v_previous.stage <> 'knockout' or p_winner is null or p_winner not in ('a', 'b') then
      raise exception 'invalid_argument';
    end if;
    v_sets := app.match_sets(p_sets, false);
    if (v_sets #>> '{0,0}')::integer <> (v_sets #>> '{0,1}')::integer then raise exception 'invalid_argument'; end if;
    v_winner := p_winner;
  elsif p_outcome = 'walkover' then
    if p_winner is null or p_winner not in ('a', 'b') then raise exception 'invalid_argument'; end if;
    v_sets := null;
    v_winner := p_winner;
  elsif p_outcome = 'retired' then
    if p_winner is null or p_winner not in ('a', 'b') then raise exception 'invalid_argument'; end if;
    v_sets := app.match_sets(p_sets, v_rated);
    v_winner := p_winner;
  else
    raise exception 'invalid_argument';
  end if;
  if v_winner = 'draw' and v_previous.stage = 'knockout' then raise exception 'draw_not_allowed'; end if;

  -- A withdrawn entry wins nothing it had not already won.
  v_entry := case v_winner when 'a' then v_previous.side_a when 'b' then v_previous.side_b end;
  if v_entry is not null and app.entry_withdrawn(v_entry)
     and (v_previous.status <> 'done' or v_previous.winner is distinct from v_winner) then
    raise exception 'invalid_argument';
  end if;

  v_correction := v_previous.status = 'done';
  if v_correction then
    if v_previous.stage = 'knockout' then
      select m.* into v_next from public.tournament_matches m
      where m.category_id = v_previous.category_id and m.stage = 'knockout'
        and m.round = v_previous.round + 1 and m.position = (v_previous.position + 1) / 2;
      if found and v_next.outcome = any (c_scored) then raise exception 'next_match_played'; end if;
    elsif exists (select 1 from public.tournament_matches m
                  where m.category_id = v_previous.category_id and m.stage = 'knockout'
                    and m.outcome is not null and m.outcome <> 'bye') then
      raise exception 'next_match_played';
    end if;
  end if;

  v_won_before := (app.category_result(v_previous.category_id) ->> 'winner')::uuid;

  update public.tournament_matches m
  set status = 'done', outcome = p_outcome, winner = v_winner, sets = v_sets, scored_by = p_user, scored_at = p_now
  where m.id = p_match_id
  returning * into v_match;
  if p_outcome = 'walkover' then perform app.match_not_played(v_match.id, p_now); end if;
  update public.tournament_draws d set first_score_at = p_now
  where d.category_id = v_match.category_id and d.first_score_at is null;

  if v_match.stage = 'knockout' then
    v_entry := case when v_previous.status = 'done' then app.match_winner_entry(v_previous) end;
    if app.match_winner_entry(v_match) is distinct from v_entry then
      perform app.place_winner(v_match.id, p_now);
      -- The next match's players hear that their opponent changed.
      if v_correction then
        select m.* into v_next from public.tournament_matches m
        where m.category_id = v_match.category_id and m.stage = 'knockout'
          and m.round = v_match.round + 1 and m.position = (v_match.position + 1) / 2;
        if found then
          perform app.notify_match_result(v_match.id,
            array(select x from unnest(app.match_players(v_next)) x
                  where not (x = any (app.match_players(v_match)))),
            true, p_now);
        end if;
      end if;
    end if;
  else
    perform app.fill_knockout(v_match.category_id, p_now);
  end if;

  perform app.notify_match_result(v_match.id, app.match_players(v_match), v_correction, p_now);
  perform app.announce_winner(v_match.category_id, v_won_before, p_now);
  perform app.audit(p_user, 'enter_match_score', 'tournament_match', v_match.id::text,
    case when v_correction then jsonb_build_object('outcome', v_previous.outcome, 'winner', v_previous.winner, 'sets', v_previous.sets) end,
    jsonb_build_object('outcome', v_match.outcome, 'winner', v_match.winner, 'sets', v_match.sets), p_now);
  perform app.after_match_scored(v_match.id, v_previous, p_now);
end $$;

-- ---------------------------------------------------------------------------
-- Withdrawals (§7.5, §14a.3)
-- ---------------------------------------------------------------------------

-- Withdraws a registered entry of a locked category (published, or a draft
-- after a redo; not_found otherwise). The caller holds the tournament lock,
-- the category row and the draw row. The registration becomes removed
-- (admin_override) through the entry lock. In a draft that is all (the lock
-- trigger marks the draft out of date). In a published draw: every unplayed
-- match of the entry with the other side known is a walkover for that side
-- (before its start the block is released); otherwise the entry's side
-- becomes empty and the match settles when the other side arrives. A
-- knockout walkover the entry won over another withdrawn entry becomes a
-- match with no winner. Played matches stay. Once the category is finished
-- nothing in the draw changes (an account deleted later keeps the result).
create function app.withdraw_locked(p_actor uuid, p_registration_id uuid, p_category_id uuid, p_now timestamptz)
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_draw public.tournament_draws;
  v_reg public.tournament_registrations;
  v_before public.tournament_registrations;
  v_tournament_id uuid;
  v_setting text;
  v_won_before uuid;
  v_finished boolean;
  v_groups_done boolean;
  v_match public.tournament_matches;
  v_id uuid;
  v_player uuid;
begin
  select d.* into v_draw from public.tournament_draws d where d.category_id = p_category_id;
  if not found or not v_draw.locked then raise exception 'not_found'; end if;
  perform app.lock_matches(p_category_id);
  select r.* into v_reg from public.tournament_registrations r
  where r.id = p_registration_id and r.category_id = p_category_id
  for update;
  if not found or v_reg.status <> 'registered' then raise exception 'not_found'; end if;
  v_before := v_reg;
  select c.tournament_id into v_tournament_id from public.tournament_categories c where c.id = p_category_id;
  v_won_before := (app.category_result(p_category_id) ->> 'winner')::uuid;
  v_finished := (app.category_result(p_category_id) ->> 'finished')::boolean;
  v_groups_done := not exists (select 1 from public.tournament_matches m
                               where m.category_id = p_category_id and m.stage = 'group' and m.status <> 'done');

  -- The lock trigger refuses this change; let it through, then put the flag
  -- back as publish_draw does.
  v_setting := current_setting('actra.draw_override', true);
  perform set_config('actra.draw_override', 'on', true);
  update public.tournament_registrations r set status = 'removed', admin_override = true, cancelled_at = p_now
  where r.id = v_reg.id returning * into v_reg;
  perform set_config('actra.draw_override', coalesce(v_setting, ''), true);

  -- A finished category keeps its result: the entry only leaves.
  if v_draw.status = 'published' and not v_finished then
    update public.tournament_draw_entries e set withdrawn_at = p_now where e.registration_id = v_reg.id;

    -- Both sides of a knockout match withdrawn: no winner, and the next
    -- match is a walkover for whoever reaches it.
    for v_match in
      select m.* from public.tournament_matches m
      where m.category_id = p_category_id and m.stage = 'knockout' and m.status = 'done' and m.outcome = 'walkover'
        and app.match_winner_entry(m) = v_reg.id
        and app.entry_withdrawn(case m.winner when 'a' then m.side_b else m.side_a end)
        and exists (select 1 from public.tournament_matches n
                    where n.category_id = m.category_id and n.stage = 'knockout' and n.round = m.round + 1
                      and n.position = (m.position + 1) / 2 and n.status <> 'done')
      order by m.round, m.position
    loop
      update public.tournament_matches m set outcome = 'none', winner = null, scored_by = p_actor, scored_at = p_now
      where m.id = v_match.id;
      perform app.place_winner(v_match.id, p_now);
    end loop;

    for v_id in
      select m.id from public.tournament_matches m
      where m.category_id = p_category_id and m.status <> 'done' and v_reg.id in (m.side_a, m.side_b)
      order by m.stage, m.round, m.position, m.id
    loop
      -- Read again: settling an earlier one may have moved it on.
      select m.* into v_match from public.tournament_matches m where m.id = v_id;
      continue when v_match.status = 'done'
        or (v_reg.id is distinct from v_match.side_a and v_reg.id is distinct from v_match.side_b);
      if (case when v_match.side_a = v_reg.id then v_match.side_b else v_match.side_a end) is not null then
        update public.tournament_matches m
        set status = 'done', outcome = 'walkover', winner = case when v_match.side_a = v_reg.id then 'b' else 'a' end,
            sets = null, scored_by = p_actor, scored_at = p_now
        where m.id = v_match.id;
        perform app.match_not_played(v_match.id, p_now);
        perform app.place_winner(v_match.id, p_now);
      else
        update public.tournament_matches m
        set side_a = case when m.side_a is not distinct from v_reg.id then null else m.side_a end,
            a_empty = m.a_empty or m.side_a is not distinct from v_reg.id,
            side_b = case when m.side_b is not distinct from v_reg.id then null else m.side_b end,
            b_empty = m.b_empty or m.side_b is not distinct from v_reg.id
        where m.id = v_match.id;
        perform app.settle_match(v_match.id, p_now);
      end if;
    end loop;

    -- The walkovers may have finished the groups.
    if not v_groups_done then perform app.fill_knockout(p_category_id, p_now); end if;
  end if;

  foreach v_player in array app.entry_players(v_reg.id) loop
    perform app.notify(v_player, 'entry_withdrawn', 'tournaments',
      app.tournament_note(v_tournament_id, p_category_id) || jsonb_build_object('registration_id', v_reg.id), p_now);
  end loop;
  perform app.announce_winner(p_category_id, v_won_before, p_now);
  perform app.audit(p_actor, 'withdraw_entry', 'tournament_registration', v_reg.id::text,
    to_jsonb(v_before), to_jsonb(v_reg), p_now);
  -- The tournament row last.
  perform app.sync_tournament_summary(v_tournament_id);
end $$;

-- The organiser's withdraw.
create function app.withdraw_entry(p_user uuid, p_registration_id uuid, p_now timestamptz) returns void
language plpgsql
set search_path = ''
as $$
declare
  v_category_id uuid;
begin
  select r.category_id into v_category_id from public.tournament_registrations r where r.id = p_registration_id;
  if not found then raise exception 'not_found'; end if;
  perform app.lock_draw(p_user, v_category_id);
  perform app.withdraw_locked(p_user, p_registration_id, v_category_id, p_now);
end $$;

-- The same without the organiser check, for account deletion.
create function app.withdraw_entry_service(p_registration_id uuid, p_now timestamptz) returns void
language plpgsql
set search_path = ''
as $$
declare
  v_category_id uuid;
  v_tournament_id uuid;
begin
  select r.category_id, c.tournament_id into v_category_id, v_tournament_id
  from public.tournament_registrations r join public.tournament_categories c on c.id = r.category_id
  where r.id = p_registration_id;
  if not found then raise exception 'not_found'; end if;
  perform pg_advisory_xact_lock(hashtext('tournament:' || v_tournament_id::text));
  perform 1 from public.tournament_categories c where c.id = v_category_id for update;
  perform 1 from public.tournament_draws d where d.category_id = v_category_id for update;
  perform app.withdraw_locked(null, p_registration_id, v_category_id, p_now);
end $$;

-- ---------------------------------------------------------------------------
-- JSON (redefined)
-- ---------------------------------------------------------------------------

-- Redefined from 20261128100000_draws.sql: groups[].standings, "winner",
-- "runner_up" (registration ids or null) and "finished".
create or replace function app.draw_json(p_category_id uuid, p_user uuid) returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  v_draw public.tournament_draws;
  v_tournament_id uuid;
  v_result jsonb;
begin
  select d.* into v_draw from public.tournament_draws d where d.category_id = p_category_id;
  if not found then return null; end if;
  select c.tournament_id into v_tournament_id from public.tournament_categories c where c.id = p_category_id;
  if v_draw.status <> 'published' and not app.is_organizer(p_user, v_tournament_id) then return null; end if;
  v_result := app.category_result(p_category_id);

  return jsonb_build_object(
    'category_id', v_draw.category_id,
    'format', v_draw.format,
    'group_size', v_draw.group_size,
    'advance', v_draw.advance,
    'status', v_draw.status,
    'outdated', v_draw.outdated,
    'entries', (
      select coalesce(jsonb_agg(jsonb_build_object(
          'registration_id', e.registration_id,
          'seed', e.seed,
          'strength', e.strength,
          'group_id', e.group_id,
          'withdrawn', e.withdrawn_at is not null,
          'players', (select coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'name', p.full_name) order by x.ord), '[]'::jsonb)
                      from unnest(app.entry_players(e.registration_id)) with ordinality x (id, ord)
                      join public.profiles p on p.id = x.id)) order by e.seed), '[]'::jsonb)
      from public.tournament_draw_entries e where e.category_id = p_category_id),
    'groups', (
      select coalesce(jsonb_agg(jsonb_build_object(
          'id', g.id,
          'label', g.label,
          'standings', app.group_standings(g.id)) order by g.sort_order), '[]'::jsonb)
      from public.tournament_groups g where g.category_id = p_category_id),
    'matches', (
      select coalesce(jsonb_agg(app.match_json(m) order by m.stage, m.round, g.sort_order nulls first, m.position), '[]'::jsonb)
      from public.tournament_matches m
      left join public.tournament_groups g on g.id = m.group_id
      where m.category_id = p_category_id),
    'winner', v_result -> 'winner',
    'runner_up', v_result -> 'runner_up',
    'finished', v_result -> 'finished');
end $$;

-- Redefined from 20261128110000_schedule.sql: "my_next_match" (the caller's
-- first match still to play in a published draw, by start time, then group
-- before knockout, round and position: match_json plus "category_id", or
-- null) and "finished" (every category of the tournament has a published
-- draw that is finished).
create or replace function app.tournament_bracket(p_user uuid, p_tournament_id uuid) returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  v_organizer boolean := app.is_organizer(p_user, p_tournament_id);
begin
  if not exists (select 1 from public.tournaments t where t.id = p_tournament_id and (t.active or v_organizer)) then
    raise exception 'not_found';
  end if;
  return jsonb_build_object(
    'organizer', v_organizer,
    'draws', (
      select coalesce(jsonb_agg(x.j order by x.sort_order, x.created_at, x.id), '[]'::jsonb)
      from (
        select app.draw_json(c.id, p_user) as j, c.sort_order, c.created_at, c.id
        from public.tournament_categories c where c.tournament_id = p_tournament_id
      ) x
      where x.j is not null),
    'courts', case when v_organizer then (
      select coalesce(jsonb_agg(jsonb_build_object(
          'id', c.id,
          'name', jsonb_build_object('uz', c.name_uz, 'ru', c.name_ru, 'kk', c.name_kk, 'en', c.name_en),
          'slot_minutes', c.slot_minutes) order by c.sort_order, c.id), '[]'::jsonb)
      from public.tournaments t
      join public.courts c on c.venue_id = t.venue_id
      where t.id = p_tournament_id and c.active) else '[]'::jsonb end,
    'my_next_match', (
      select app.match_json(m) || jsonb_build_object('category_id', m.category_id)
      from public.tournament_matches m
      join public.tournament_categories c on c.id = m.category_id
      join public.tournament_draws d on d.category_id = m.category_id and d.status = 'published'
      where c.tournament_id = p_tournament_id and m.status <> 'done'
        and exists (select 1 from public.tournament_registrations r
                    where r.id in (m.side_a, m.side_b) and p_user in (r.user_id, r.partner_id))
      order by m.starts_at nulls last, m.stage, m.round, c.sort_order, c.created_at, c.id, m.position
      limit 1),
    'finished', (
      select count(*) > 0 and bool_and((app.category_result(c.id) ->> 'finished')::boolean)
      from public.tournament_categories c
      where c.tournament_id = p_tournament_id));
end $$;

-- The caller's matches in published draws of active tournaments (byes and
-- matches without a winner left out): those still to play first, by start
-- time, then the finished ones, latest first. Each is match_json plus
-- "tournament_id", "category_id" and the tournament's titles.
create function app.my_tournament_matches(p_user uuid) returns jsonb
language sql
set search_path = ''
as $$
  select coalesce(jsonb_agg(app.match_json(m) || jsonb_build_object(
      'tournament_id', t.id,
      'category_id', m.category_id,
      'title_uz', t.title_uz,
      'title_ru', t.title_ru,
      'title_kk', t.title_kk,
      'title_en', t.title_en)
    order by m.status = 'done', case when m.status <> 'done' then m.starts_at end nulls last, t.starts_on,
      m.scored_at desc, m.stage, m.round, m.position, m.id), '[]'::jsonb)
  from public.tournament_matches m
  join public.tournament_categories c on c.id = m.category_id
  join public.tournaments t on t.id = c.tournament_id
  join public.tournament_draws d on d.category_id = m.category_id and d.status = 'published'
  where p_user is not null and t.active
    and m.outcome is distinct from 'bye' and m.outcome is distinct from 'none'
    and exists (select 1 from public.tournament_registrations r
                where r.id in (m.side_a, m.side_b) and p_user in (r.user_id, r.partner_id))
$$;

-- ---------------------------------------------------------------------------
-- Deleting an account
-- ---------------------------------------------------------------------------

-- Redefined from 20261127130000_teams.sql (§7.5, §14a.9): before the
-- bookings and the cancel-registrations step, the player's entries in
-- locked categories are withdrawn (app.withdraw_entry_service), so the
-- deletion is never refused with draw_published. Everything else as there.
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
  v_game public.games;
  v_target uuid;
  v_team public.teams;
begin
  if p_user is null then raise exception 'not_authenticated'; end if;
  if app.is_admin(p_user) then raise exception 'admin_account'; end if;

  -- `no key update`: the rows below that reference the profile can still be
  -- written while it is held.
  select p.* into v_profile from public.profiles p where p.id = p_user for no key update;
  if not found or v_profile.deleted_at is not null then return; end if;

  -- Every team involved is locked first, in id order: a team comes before
  -- its games (a hosted team game is cancelled below, and removing a team
  -- clears team_id on its games), so a captain's call on one of them waits
  -- or is waited for.
  perform 1 from public.teams t
  where t.captain_id = p_user
     or t.id in (select m.team_id from public.team_members m where m.user_id = p_user)
     or t.id in (select r.team_id from public.team_join_requests r where r.user_id = p_user and r.status = 'pending')
     or t.id in (select i.team_id from public.team_invites i where i.user_id = p_user and i.status = 'pending')
  order by t.id
  for update;

  -- Entries in a locked category (a published draw, or a draft after a
  -- redo), as registrant or confirmed partner, whatever the tournament's
  -- dates: withdrawn as the organiser's withdraw does (unplayed matches
  -- become walkovers, played ones stay), so the steps below never meet the
  -- entry lock. The tournament locks first, in id order, before any booking
  -- (the order scheduling and score entry use).
  for v_id in
    select distinct c.tournament_id
    from public.tournament_registrations r
    join public.tournament_categories c on c.id = r.category_id
    join public.tournament_draws d on d.category_id = r.category_id and d.locked
    where (r.user_id = p_user or (r.partner_id = p_user and r.partner_confirmed)) and r.status = 'registered'
    order by c.tournament_id
  loop
    perform pg_advisory_xact_lock(hashtext('tournament:' || v_id::text));
  end loop;
  -- Every category of the player's live entries next, in id order (the lock
  -- the cancel-registrations step below takes), so that no category is
  -- locked after a withdrawal has written its tournament row.
  perform 1 from public.tournament_categories c
  where c.id in (
    select r.category_id from public.tournament_registrations r
    where (r.user_id = p_user or r.partner_id = p_user) and r.status = any (c_live))
  order by c.id
  for update;
  for v_id in
    select r.id from public.tournament_registrations r
    join public.tournament_draws d on d.category_id = r.category_id and d.locked
    where (r.user_id = p_user or (r.partner_id = p_user and r.partner_confirmed)) and r.status = 'registered'
    order by r.category_id, r.id
  loop
    perform app.withdraw_entry_service(v_id, p_now);
  end loop;

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
  -- The player's own free text goes from every row they wrote it on, past
  -- and future, each kind right after its own step (no booking is locked
  -- after a game): booking notes here (owners see them).
  update public.bookings b set note = null
  where b.user_id = p_user and b.source = 'app' and b.note is not null;

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
  -- Notes and meeting points on the games they host. A meeting-point game
  -- must keep a meeting point (games_meeting_point_for_map_point), so it
  -- gets '' there, which game_json shows as null. The map coordinates of the
  -- meeting point go too (they are nullable, no constraint ties them).
  update public.games g
  set note = null,
      meeting_point = case when g.kind = 'map_point' then '' end,
      meeting_lat = null,
      meeting_lng = null
  where g.host_id = p_user
    and (g.note is not null or g.meeting_point is not null or g.meeting_lat is not null or g.meeting_lng is not null);

  -- Game Requests: the player's open ones, and their "I'm in" on open ones;
  -- then the notes and areas on all their requests.
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
  update public.game_requests r set note = null, area = null
  where r.host_id = p_user and (r.note is not null or r.area is not null);

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

  -- Teams (design §7), locked at the start. Before the after-game rows and
  -- the results: removing a team writes its games (team_id), and no game is
  -- locked after a result.
  for v_team in select t.* from public.teams t where t.captain_id = p_user order by t.id loop
    select m.user_id into v_other from public.team_members m
    join public.profiles p on p.id = m.user_id and p.deleted_at is null
    where m.team_id = v_team.id and m.user_id <> p_user
    order by m.joined_at, m.user_id
    limit 1;
    if found then
      update public.teams t set captain_id = v_other where t.id = v_team.id returning * into v_team;
      perform app.notify(v_other, 'team_captain', 'teams', app.team_note(v_team, p_user), p_now);
    else
      delete from public.teams t where t.id = v_team.id;
    end if;
  end loop;
  delete from public.team_members m where m.user_id = p_user;
  delete from public.team_join_requests r where r.user_id = p_user;
  delete from public.team_invites i where i.user_id = p_user;

  -- After-game rows (design §6). The games the player reported someone in
  -- are locked in id order before any result row (a recount may freeze a
  -- result, and report_no_show takes the game before the result).
  delete from public.game_votes v where v.voter_id = p_user;
  for v_game in
    select g.* from public.games g
    where g.id in (select r.game_id from public.game_no_show_reports r where r.reporter_id = p_user)
    order by g.id
    for update
  loop
    for v_target in
      delete from public.game_no_show_reports r
      where r.game_id = v_game.id and r.reporter_id = p_user
      returning r.target_id
    loop
      perform app.recount_no_show(v_game, v_target, p_now);
    end loop;
  end loop;
  update public.abuse_reports a set status = 'closed', closed_at = p_now
  where a.reporter_id = p_user and a.status = 'open';
  update public.abuse_reports a set details = null
  where a.reporter_id = p_user and a.details is not null;

  -- Results not yet confirmed that the player is in become void, and the
  -- reason the player gave on any result they disputed goes (whatever its
  -- status). Each result row is locked before it changes, in id order, and
  -- before the player's rating row below (the order score confirmation
  -- uses); one confirmed in between is left as it is.
  for v_id in
    select r.id from public.match_results r
    where r.dispute_by = p_user
       or (r.status in ('pending', 'disputed')
           and exists (select 1 from public.match_result_players p where p.result_id = r.id and p.user_id = p_user))
    order by r.id
  loop
    select r.* into v_result from public.match_results r where r.id = v_id for update;
    if v_result.dispute_by = p_user and v_result.dispute_reason is not null then
      update public.match_results r set dispute_reason = null where r.id = v_id returning * into v_result;
    end if;
    if v_result.status not in ('pending', 'disputed')
       or not exists (select 1 from public.match_result_players p where p.result_id = v_id and p.user_id = p_user) then
      continue;
    end if;
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
-- What the app calls. Each runs as the signed-in user at the real time.
-- ---------------------------------------------------------------------------

-- Returns the draw afterwards, as the caller sees it.
create function public.enter_match_score(
  p_match_id uuid, p_outcome text, p_winner text default null, p_sets jsonb default null) returns jsonb
language sql security definer
set search_path = ''
as $$
  select app.enter_match_score((select auth.uid()), p_match_id, p_outcome, p_winner, p_sets, now());
  select app.draw_json(m.category_id, (select auth.uid())) from public.tournament_matches m where m.id = p_match_id;
$$;

-- Returns the draw afterwards, as the caller sees it.
create function public.withdraw_entry(p_registration_id uuid) returns jsonb
language sql security definer
set search_path = ''
as $$
  select app.withdraw_entry((select auth.uid()), p_registration_id, now());
  select app.draw_json(r.category_id, (select auth.uid())) from public.tournament_registrations r where r.id = p_registration_id;
$$;

create function public.my_tournament_matches() returns jsonb
language sql security definer
set search_path = ''
as $$ select app.my_tournament_matches((select auth.uid())) $$;

revoke all on function
  public.enter_match_score(uuid, text, text, jsonb),
  public.withdraw_entry(uuid),
  public.my_tournament_matches()
from public, anon, authenticated;

grant execute on function
  public.enter_match_score(uuid, text, text, jsonb),
  public.withdraw_entry(uuid),
  public.my_tournament_matches()
to authenticated, service_role;
