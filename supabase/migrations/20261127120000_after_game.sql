-- Milestone 7b: after a game — thumbs up/down, "didn't show up" reports with
-- their majority rule, abuse reports, the sportsmanship summary and the admin
-- review (design 2026-11-27-actra-m7-competitive §6).
--
-- Additive: new server-only tables and functions. app.game_json and
-- app.delete_account are copied from 20261127110000_scores.sql,
-- app.complete_games from the same file, app.player_json from
-- 20261127100000_ratings.sql; every signature stays.
--
-- Lock order: a no-show report locks the game row, then (if the reported
-- player is in the game's result) the match_results row; never a
-- player_ratings row (the same game -> result order as app.enter_score).

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------

-- One thumbs up or down per voter per player per game. Anonymous: only the
-- voter's own votes are ever shown back (game_json), others see a summary.
create table public.game_votes (
  game_id uuid not null references public.games (id) on delete cascade,
  voter_id uuid not null references public.profiles (id) on delete cascade,
  target_id uuid not null references public.profiles (id) on delete cascade,
  up boolean not null,
  updated_at timestamptz not null,
  primary key (game_id, voter_id, target_id)
);

create index game_votes_target on public.game_votes (target_id);
create index game_votes_voter on public.game_votes (voter_id);

create table public.game_no_show_reports (
  game_id uuid not null references public.games (id) on delete cascade,
  reporter_id uuid not null references public.profiles (id) on delete cascade,
  target_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null,
  primary key (game_id, reporter_id, target_id)
);

create index game_no_show_reports_target on public.game_no_show_reports (game_id, target_id);
create index game_no_show_reports_reporter on public.game_no_show_reports (reporter_id);

create table public.abuse_reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references public.profiles (id) on delete cascade,
  target_id uuid not null references public.profiles (id) on delete cascade,
  -- The report stays when its game goes.
  game_id uuid references public.games (id) on delete set null,
  reason text not null check (reason in ('language', 'aggression', 'false_score', 'other')),
  details text check (char_length(details) <= 500),
  status text not null default 'open' check (status in ('open', 'closed')),
  admin_note text check (char_length(admin_note) <= 500),
  closed_by uuid references public.profiles (id) on delete set null,
  closed_at timestamptz,
  created_at timestamptz not null
);

-- One open report per reporter per player per game (or without a game).
create unique index abuse_reports_open_once on public.abuse_reports
  (reporter_id, target_id, coalesce(game_id, '00000000-0000-0000-0000-000000000000'::uuid))
  where status = 'open';
create index abuse_reports_open on public.abuse_reports (created_at) where status = 'open';

alter table public.game_votes enable row level security;
alter table public.game_no_show_reports enable row level security;
alter table public.abuse_reports enable row level security;
revoke all on table public.game_votes, public.game_no_show_reports, public.abuse_reports from anon, authenticated;
grant all on table public.game_votes, public.game_no_show_reports, public.abuse_reports to service_role;

-- ---------------------------------------------------------------------------
-- Votes and no-show reports
-- ---------------------------------------------------------------------------

-- A live caller (not_authenticated otherwise), and a target who is another
-- live participant of p_game, a game that was not cancelled and has ended
-- (not_found otherwise), no later than p_open_for after its end
-- (score_closed after).
create function app.check_after_game(
  p_user uuid, p_game public.games, p_target uuid, p_open_for interval, p_now timestamptz) returns void
language plpgsql
set search_path = ''
as $$
begin
  if p_user is null or not exists (select 1 from public.profiles p where p.id = p_user and p.deleted_at is null) then
    raise exception 'not_authenticated';
  end if;
  if p_game.id is null or p_game.status = 'cancelled' or p_now < upper(p_game.during)
     or p_target is null or p_target = p_user
     or not exists (select 1 from public.profiles p where p.id = p_target and p.deleted_at is null)
     or (select count(*) from public.game_participants gp
         where gp.game_id = p_game.id and gp.user_id in (p_user, p_target)) <> 2 then
    raise exception 'not_found';
  end if;
  if p_now >= upper(p_game.during) + p_open_for then raise exception 'score_closed'; end if;
end $$;

-- Thumbs up (true) or down (false) for another participant, changeable for
-- 7 days after the end; null removes the vote.
create function app.vote_player(p_user uuid, p_game_id uuid, p_target uuid, p_up boolean, p_now timestamptz)
returns void
language plpgsql
set search_path = ''
as $$
declare
  c_open_for constant interval := interval '7 days';
  v_game public.games;
begin
  select g.* into v_game from public.games g where g.id = p_game_id;
  perform app.check_after_game(p_user, v_game, p_target, c_open_for, p_now);
  if p_up is null then
    delete from public.game_votes v where v.game_id = p_game_id and v.voter_id = p_user and v.target_id = p_target;
  else
    insert into public.game_votes (game_id, voter_id, target_id, up, updated_at)
    values (p_game_id, p_user, p_target, p_up, p_now)
    on conflict (game_id, voter_id, target_id) do update set up = excluded.up, updated_at = excluded.updated_at;
  end if;
end $$;

-- Applies the majority rule to one reported player of a game whose row the
-- caller has locked. Majority: more than half of the other participants,
-- and at least two of them, have reported the player.
--
-- Reached, and not yet recorded for this game: the player gets the no_show
-- reliability event (ref = the game id) in place of their game_completed
-- credit, and hears (no_show_recorded). Not for a player who joined after
-- the start (no credit either, app.complete_games), and not for a host the
-- venue already marked no-show for the game's booking. Then, if the player
-- is in the game's result: a pending one is frozen as disputed for the
-- admin (reason no_show; the players hear, as for a player's dispute), a
-- confirmed one is flagged. Nothing is voided here.
--
-- Lost again: the game's no_show event goes and, if there was one, the
-- game_completed credit comes back (once the game has been completed, else
-- app.complete_games gives it). A result already disputed stays disputed.
create function app.recount_no_show(p_game public.games, p_target uuid, p_now timestamptz) returns void
language plpgsql
set search_path = ''
as $$
declare
  v_reporters integer;
  v_others integer;
  v_on_time boolean;
  v_result public.match_results;
begin
  select count(*) into v_reporters
  from public.game_no_show_reports r where r.game_id = p_game.id and r.target_id = p_target;
  select count(*) - 1 into v_others from public.game_participants gp where gp.game_id = p_game.id;
  v_on_time := exists (select 1 from public.game_participants gp
                       where gp.game_id = p_game.id and gp.user_id = p_target and gp.joined_at < lower(p_game.during));

  if v_reporters * 2 > v_others and v_reporters >= 2 then
    if not v_on_time or exists (select 1 from public.reliability_events e
                                where e.user_id = p_target and e.kind = 'no_show' and e.ref = p_game.id::text) then
      return;
    end if;

    if not (p_target = p_game.host_id and p_game.booking_id is not null
            and exists (select 1 from public.reliability_events e
                        where e.user_id = p_target and e.kind = 'no_show' and e.ref = p_game.booking_id::text)) then
      perform app.reliability_event(p_target, 'no_show', p_game.id::text, p_now);
      delete from public.reliability_events e
      where e.user_id = p_target and e.kind = 'game_completed' and e.ref = p_game.id::text;
      perform app.notify(p_target, 'no_show_recorded', 'games', app.game_note(p_game), p_now);
    end if;

    -- The result row is locked, and its state read, before it changes.
    select r.* into v_result from public.match_results r
    where r.game_id = p_game.id
      and exists (select 1 from public.match_result_players mp where mp.result_id = r.id and mp.user_id = p_target)
    for update;
    if not found then return; end if;
    if v_result.status = 'pending' then
      update public.match_results r set status = 'disputed', dispute_reason = 'no_show'
      where r.id = v_result.id
      returning * into v_result;
      perform app.notify(mp.user_id, 'score_disputed', 'ratings', app.result_note(v_result), p_now)
      from public.match_result_players mp
      where mp.result_id = v_result.id;
    elsif v_result.status = 'confirmed' and not v_result.flagged_no_show then
      update public.match_results r set flagged_no_show = true where r.id = v_result.id;
    end if;
  else
    delete from public.reliability_events e
    where e.user_id = p_target and e.kind = 'no_show' and e.ref = p_game.id::text;
    if found and v_on_time and p_game.completed_at is not null then
      perform app.reliability_event(p_target, 'game_completed', p_game.id::text, p_now);
    end if;
  end if;
end $$;

-- Marks (true) or unmarks (false) another participant as not having shown
-- up, for 48 hours after the end, then recounts that player. The game row
-- is locked first, so two reports at once are counted one after the other.
create function app.report_no_show(p_user uuid, p_game_id uuid, p_target uuid, p_reported boolean, p_now timestamptz)
returns void
language plpgsql
set search_path = ''
as $$
declare
  c_open_for constant interval := interval '48 hours';
  v_game public.games;
begin
  select g.* into v_game from public.games g where g.id = p_game_id for update;
  perform app.check_after_game(p_user, v_game, p_target, c_open_for, p_now);
  if p_reported is null then raise exception 'invalid_argument'; end if;
  if p_reported then
    insert into public.game_no_show_reports (game_id, reporter_id, target_id, created_at)
    values (p_game_id, p_user, p_target, p_now)
    on conflict (game_id, reporter_id, target_id) do nothing;
  else
    delete from public.game_no_show_reports r
    where r.game_id = p_game_id and r.reporter_id = p_user and r.target_id = p_target;
  end if;
  perform app.recount_no_show(v_game, p_target, p_now);
end $$;

-- ---------------------------------------------------------------------------
-- Abuse reports and the sportsmanship summary
-- ---------------------------------------------------------------------------

-- Reports another live player, optionally about a game both played in.
-- Details are trimmed (empty -> null), at most 500 characters. One open
-- report per reporter, player and game (already_exists). Nothing happens
-- automatically and the reported player is told nothing (design §6.3).
create function app.report_player(
  p_user uuid, p_target uuid, p_game_id uuid, p_reason text, p_details text, p_now timestamptz) returns uuid
language plpgsql
set search_path = ''
as $$
declare
  v_details text := nullif(btrim(p_details), '');
  v_id uuid;
begin
  if p_user is null or not exists (select 1 from public.profiles p where p.id = p_user and p.deleted_at is null) then
    raise exception 'not_authenticated';
  end if;
  if p_reason is null or p_reason not in ('language', 'aggression', 'false_score', 'other')
     or char_length(v_details) > 500 or p_target = p_user then
    raise exception 'invalid_argument';
  end if;
  if not exists (select 1 from public.profiles p where p.id = p_target and p.deleted_at is null)
     or (p_game_id is not null
         and (select count(*) from public.game_participants gp
              where gp.game_id = p_game_id and gp.user_id in (p_user, p_target)) <> 2) then
    raise exception 'not_found';
  end if;

  begin
    insert into public.abuse_reports (reporter_id, target_id, game_id, reason, details, created_at)
    values (p_user, p_target, p_game_id, p_reason, v_details, p_now)
    returning id into v_id;
  exception when unique_violation then
    raise exception 'already_exists';
  end;
  return v_id;
end $$;

-- {"votes": thumbs received, "percent": share of thumbs up, 0-100, or null
-- while there are fewer than 5 votes (design §6.1)}.
create function app.sportsmanship(p_user uuid) returns jsonb
language sql stable
set search_path = ''
as $$
  select jsonb_build_object(
    'votes', count(*),
    'percent', case when count(*) >= 5 then round(100.0 * count(*) filter (where v.up) / count(*))::integer end)
  from public.game_votes v
  where v.target_id = p_user
$$;

-- ---------------------------------------------------------------------------
-- Admin review (design §6.4)
-- ---------------------------------------------------------------------------

-- {"disputes": [{"result", "game", "players": [{"id", "name", "side"}],
-- "disputed_by_name"}], "reports": [{"id", "reporter_id", "reporter_name",
-- "target_id", "target_name", "game_id", "game", "result", "reason",
-- "details", "created_at"}], "counts": {"disputes", "reports"}}.
-- Disputes: disputed results, and confirmed ones flagged by a no-show
-- majority, oldest entry first. Reports: the open ones, oldest first; a
-- report's game is app.game_note and its result app.result_json of that
-- game's result (null without a game), so a false-score report can lead to
-- voiding a confirmed result.
create function app.admin_review(p_user uuid) returns jsonb
language plpgsql
set search_path = ''
as $$
begin
  perform app.require_admin(p_user);
  return (
    with disputes as (
      select r.* from public.match_results r
      where r.status = 'disputed' or (r.status = 'confirmed' and r.flagged_no_show)
    ),
    reports as (
      select a.* from public.abuse_reports a where a.status = 'open'
    )
    select jsonb_build_object(
      'disputes', coalesce(
        (select jsonb_agg(
                  jsonb_build_object(
                    'result', app.result_json(d),
                    'game', app.game_note(g),
                    'players', (select jsonb_agg(jsonb_build_object('id', mp.user_id, 'name', pr.full_name, 'side', mp.side)
                                                 order by mp.side, mp.user_id)
                                from public.match_result_players mp
                                join public.profiles pr on pr.id = mp.user_id
                                where mp.result_id = d.id),
                    'disputed_by_name', (select pr.full_name from public.profiles pr where pr.id = d.dispute_by))
                  order by d.entered_at, d.id)
         from disputes d
         join public.games g on g.id = d.game_id),
        '[]'::jsonb),
      'reports', coalesce(
        (select jsonb_agg(
                  jsonb_build_object(
                    'id', a.id,
                    'reporter_id', a.reporter_id,
                    'reporter_name', reporter.full_name,
                    'target_id', a.target_id,
                    'target_name', target.full_name,
                    'game_id', a.game_id,
                    'game', case when g.id is not null then app.game_note(g) end,
                    'result', (select app.result_json(mr) from public.match_results mr where mr.game_id = a.game_id),
                    'reason', a.reason,
                    'details', a.details,
                    'created_at', a.created_at)
                  order by a.created_at, a.id)
         from reports a
         join public.profiles reporter on reporter.id = a.reporter_id
         join public.profiles target on target.id = a.target_id
         left join public.games g on g.id = a.game_id),
        '[]'::jsonb),
      'counts', jsonb_build_object(
        'disputes', (select count(*) from disputes),
        'reports', (select count(*) from reports)))
  );
end $$;

-- Closes an open report with an optional note (trimmed, at most 500
-- characters), audited as report_closed.
create function app.admin_close_report(p_user uuid, p_report_id uuid, p_note text, p_now timestamptz) returns void
language plpgsql
set search_path = ''
as $$
declare
  v_note text := nullif(btrim(p_note), '');
  v_before public.abuse_reports;
  v_after public.abuse_reports;
begin
  perform app.require_admin(p_user);
  if char_length(v_note) > 500 then raise exception 'invalid_argument'; end if;
  select a.* into v_before from public.abuse_reports a where a.id = p_report_id for update;
  if not found or v_before.status <> 'open' then raise exception 'not_found'; end if;
  update public.abuse_reports a
  set status = 'closed', admin_note = v_note, closed_by = p_user, closed_at = p_now
  where a.id = p_report_id
  returning * into v_after;
  perform app.audit(p_user, 'report_closed', 'abuse_report', p_report_id::text, to_jsonb(v_before), to_jsonb(v_after), p_now);
end $$;

-- ---------------------------------------------------------------------------
-- JSON
-- ---------------------------------------------------------------------------

-- Redefined from 20261127110000_scores.sql: `after_game` for a participant
-- of a game that has ended and was not cancelled: {"votes": {target_id:
-- up}, "no_shows": [target_id]}, the caller's own entries only. The app
-- works out the 7-day and 48-hour windows from ends_local; the server
-- enforces them.
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
  || case when p_user is not null and g.status <> 'cancelled' and upper(g.during) <= now()
               and exists (select 1 from public.game_participants p where p.game_id = g.id and p.user_id = p_user) then
       jsonb_build_object('after_game', jsonb_build_object(
         'votes', coalesce(
           (select jsonb_object_agg(v.target_id, v.up)
            from public.game_votes v where v.game_id = g.id and v.voter_id = p_user),
           '{}'::jsonb),
         'no_shows', coalesce(
           (select jsonb_agg(r.target_id order by r.target_id)
            from public.game_no_show_reports r where r.game_id = g.id and r.reporter_id = p_user),
           '[]'::jsonb)))
     else '{}'::jsonb end
$$;

-- Redefined from 20261127100000_ratings.sql: `sportsmanship`
-- (app.sportsmanship).
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
      where gp.user_id = pr.id and g.completed_at is not null),
    'sportsmanship', app.sportsmanship(pr.id))
  || case when pr.deleted_at is not null then jsonb_build_object('deleted', true) else '{}'::jsonb end
$$;

-- ---------------------------------------------------------------------------
-- The finished-game job
-- ---------------------------------------------------------------------------

-- Redefined from 20261127110000_scores.sql: no game_completed credit for a
-- participant a no-show majority was already recorded against (reports can
-- come in before the job has run). Otherwise unchanged: a game that ended
-- with at least two players sends every participant `game_finished`
-- (category games; can_score: true for the host of a game in a rated sport,
-- who enters the score). Open games that have ended: marked completed. A
-- game that ended with at least two players gives one game_completed event
-- to each participant who joined before it started (no credit for solo
-- games or late joiners). Returns how many games were completed.
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
          and not exists (select 1 from public.reliability_events e
                          where e.user_id = p.user_id and e.kind = 'no_show' and e.ref = v_game.id::text)
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

-- ---------------------------------------------------------------------------
-- Deleting an account (design §3: delete_account covers every new table)
-- ---------------------------------------------------------------------------

-- Redefined from 20261127110000_scores.sql: the player's votes go; their
-- no-show reports go and each player they reported is recounted (a majority
-- that needed them is undone, whenever the account is deleted); their open
-- abuse reports are closed and the details they wrote on any report are
-- removed. Votes, no-show reports and abuse reports about them stay.
--
-- From 20261127110000_scores.sql: the player's pending and
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
  v_game public.games;
  v_target uuid;
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
-- What the app calls. Votes and no-show reports return the game afterwards.
-- ---------------------------------------------------------------------------

create function public.vote_player(p_game_id uuid, p_target uuid, p_up boolean) returns jsonb
language sql security definer
set search_path = ''
as $$
  select app.vote_player((select auth.uid()), p_game_id, p_target, p_up, now());
  select app.game_json(g, (select auth.uid())) from public.games g where g.id = p_game_id;
$$;

create function public.report_no_show(p_game_id uuid, p_target uuid, p_reported boolean) returns jsonb
language sql security definer
set search_path = ''
as $$
  select app.report_no_show((select auth.uid()), p_game_id, p_target, p_reported, now());
  select app.game_json(g, (select auth.uid())) from public.games g where g.id = p_game_id;
$$;

create function public.report_player(
  p_target uuid, p_game_id uuid default null, p_reason text default 'other', p_details text default null) returns void
language sql security definer
set search_path = ''
as $$ select app.report_player((select auth.uid()), p_target, p_game_id, p_reason, p_details, now()) $$;

create function public.admin_review() returns jsonb
language sql security definer
set search_path = ''
as $$ select app.admin_review((select auth.uid())) $$;

create function public.admin_close_report(p_report_id uuid, p_note text default null) returns void
language sql security definer
set search_path = ''
as $$ select app.admin_close_report((select auth.uid()), p_report_id, p_note, now()) $$;

revoke all on function
  public.vote_player(uuid, uuid, boolean),
  public.report_no_show(uuid, uuid, boolean),
  public.report_player(uuid, uuid, text, text),
  public.admin_review(),
  public.admin_close_report(uuid, text)
from public, anon, authenticated;

grant execute on function
  public.vote_player(uuid, uuid, boolean),
  public.report_no_show(uuid, uuid, boolean),
  public.report_player(uuid, uuid, text, text),
  public.admin_review(),
  public.admin_close_report(uuid, text)
to authenticated, service_role;
