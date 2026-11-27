-- Tournament brackets (Milestone 8a, part 2): the match schedule and its
-- calendar blocks (design §7.2, §14a.1, §14a.2).
--
-- Additive only: one new column on bookings, new functions, and guards added
-- to functions copied from their latest definitions.
--
-- A scheduled match at a venue holds one slot of one court: a `block` row in
-- bookings linked by tournament_match_id. Releasing it deletes the row (the
-- link is unique, so a cancelled leftover would stand in the way of the next
-- one); deleting the match (a redo) deletes it through the foreign key.
--
-- Lock order (20261128100000_draws.sql): the tournament advisory lock, the
-- category rows (id order), their draw rows, the matches, then the court
-- locks app.hold_slots takes (app.lock_court_for_write) and the bookings.
-- Every check across categories (a player busy elsewhere) runs under the
-- tournament lock, so two organisers cannot both pass it.

alter table public.bookings
  add column tournament_match_id uuid unique references public.tournament_matches (id) on delete cascade,
  add constraint bookings_match_on_blocks check (tournament_match_id is null or source = 'block');

-- ---------------------------------------------------------------------------
-- Helpers. Not stable: each must see rows written earlier in the same call.
-- ---------------------------------------------------------------------------

-- The instants a match takes: one slot of its court. Without a court (a
-- tournament without a venue) a match has no length: the single instant it
-- starts, so two such matches overlap only when they start together.
create function app.match_span(m public.tournament_matches) returns tstzrange
language sql
set search_path = ''
as $$
  select case
    when m.starts_at is null then null
    when m.court_id is null then tstzrange(m.starts_at, m.starts_at, '[]')
    else (select tstzrange(m.starts_at, m.starts_at + make_interval(mins => c.slot_minutes), '[)')
          from public.courts c where c.id = m.court_id)
  end
$$;

-- Every player of the match's known sides.
create function app.match_players(m public.tournament_matches) returns uuid[]
language sql
set search_path = ''
as $$
  select coalesce(app.entry_players(m.side_a), '{}') || coalesce(app.entry_players(m.side_b), '{}')
$$;

-- True when one of p_players is in another scheduled match of the
-- tournament, in any category, whose time overlaps p_span.
create function app.players_busy(p_match_id uuid, p_tournament_id uuid, p_players uuid[], p_span tstzrange) returns boolean
language sql
set search_path = ''
as $$
  select p_span is not null and cardinality(p_players) > 0 and exists (
    select 1
    from public.tournament_matches o
    join public.tournament_categories c on c.id = o.category_id
    where c.tournament_id = p_tournament_id
      and o.id <> p_match_id
      and o.starts_at is not null
      and app.match_span(o) && p_span
      and app.match_players(o) && p_players)
$$;

-- Deletes the match's calendar block, if it has one.
create function app.release_match_block(p_match_id uuid) returns void
language sql
set search_path = ''
as $$ delete from public.bookings b where b.tournament_match_id = p_match_id $$;

-- Inserts the match's block. The caller holds the court's lock
-- (app.lock_court_for_write) and turns an exclusion violation into
-- slot_taken or a skipped slot.
create function app.insert_match_block(p_match_id uuid, p_court_id uuid, p_span tstzrange, p_now timestamptz) returns void
language sql
set search_path = ''
as $$
  insert into public.bookings (
    user_id, venue_id, court_id, during, utc_offset_minutes, slot_count, total_price, currency,
    status, source, block_reason, tournament_match_id, created_at, confirmed_at)
  select null, c.venue_id, c.id, p_span, ci.utc_offset_minutes, 1, 0, ci.currency,
    'confirmed', 'block', left('Tournament: ' || coalesce(t.title_uz, t.title_ru, t.title_en, t.title_kk), 200),
    p_match_id, p_now, p_now
  from public.courts c
  join public.venues v on v.id = c.venue_id
  join public.cities ci on ci.id = v.city_id
  cross join public.tournament_matches m
  join public.tournament_categories tc on tc.id = m.category_id
  join public.tournaments t on t.id = tc.tournament_id
  where c.id = p_court_id and m.id = p_match_id
$$;

-- match_scheduled to every player of the match's known sides.
create function app.notify_match_scheduled(p_match_id uuid, p_now timestamptz) returns void
language plpgsql
set search_path = ''
as $$
declare
  v_match public.tournament_matches;
  v_tournament_id uuid;
  v_payload jsonb;
  v_player uuid;
begin
  select m.* into v_match from public.tournament_matches m where m.id = p_match_id;
  select c.tournament_id into v_tournament_id from public.tournament_categories c where c.id = v_match.category_id;
  v_payload := app.tournament_note(v_tournament_id, v_match.category_id) || jsonb_build_object(
    'match_id', v_match.id,
    'starts_at', app.match_json(v_match) -> 'starts_at',
    'court_id', v_match.court_id,
    'court_name', app.match_json(v_match) -> 'court_name',
    'place_note', v_match.place_note);
  for v_player in select distinct x from unnest(app.match_players(v_match)) x loop
    perform app.notify(v_player, 'match_scheduled', 'tournaments', v_payload, p_now);
  end loop;
end $$;

-- ---------------------------------------------------------------------------
-- JSON (redefined from 20261128100000_draws.sql)
-- ---------------------------------------------------------------------------

-- Sides are registration ids; starts_at and ends_at are venue wall-clock
-- time, as in game JSON. ends_at is null without a court. clash: a player of
-- a known side is in another scheduled match of the tournament at an
-- overlapping time (advancing can cause it; the organiser moves the match).
create or replace function app.match_json(m public.tournament_matches) returns jsonb
language sql
set search_path = ''
as $$
  select jsonb_build_object(
    'id', m.id,
    'stage', m.stage,
    'group_id', m.group_id,
    'round', m.round,
    'position', m.position,
    'side_a', m.side_a,
    'side_b', m.side_b,
    'a_empty', m.a_empty,
    'b_empty', m.b_empty,
    'status', m.status,
    'outcome', m.outcome,
    'winner', m.winner,
    'sets', m.sets,
    'court_id', m.court_id,
    'court_name', (select jsonb_build_object('uz', c.name_uz, 'ru', c.name_ru, 'kk', c.name_kk, 'en', c.name_en)
                   from public.courts c where c.id = m.court_id),
    'starts_at', case when m.starts_at is not null then app.to_local(m.starts_at, app.tournament_offset(t)) end,
    'ends_at', case when m.starts_at is not null and m.court_id is not null
                 then app.to_local(upper(app.match_span(m)), app.tournament_offset(t)) end,
    'place_note', m.place_note,
    'clash', m.starts_at is not null and app.players_busy(m.id, t.id, app.match_players(m), app.match_span(m)))
  from public.tournament_categories tc
  join public.tournaments t on t.id = tc.tournament_id
  where tc.id = m.category_id
$$;

-- {"organizer", "draws": [draw_json ...], "courts": [...]}: the draws the
-- caller may see, in category order; for organisers, the active courts of
-- the tournament's venue (empty for everyone else). A hidden tournament
-- exists only for its organisers.
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
      where t.id = p_tournament_id and c.active) else '[]'::jsonb end);
end $$;

-- ---------------------------------------------------------------------------
-- Scheduling (organisers and admins)
-- ---------------------------------------------------------------------------

-- Sets, moves or (p_starts_at null) clears a match's court and time. At a
-- venue: an active court of the venue, one of its slots that day, on the
-- tournament's dates; the old block is released and a new one inserted.
-- Without a venue: no court, a place note of up to 100 characters, no
-- block. Refused when a player of either side is busy elsewhere in the
-- tournament then (player_busy) or the slot is booked or blocked
-- (slot_taken). The players are told when the time or court changes.
create function app.schedule_match(
  p_user uuid, p_match_id uuid, p_court_id uuid, p_starts_at timestamp, p_place_note text, p_now timestamptz)
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_match public.tournament_matches;
  v_draw public.tournament_draws;
  v_tournament public.tournaments;
  v_court public.courts;
  v_note text := nullif(btrim(p_place_note), '');
  v_start timestamptz;
  v_span tstzrange;
  v_changed boolean;
begin
  select m.* into v_match from public.tournament_matches m where m.id = p_match_id;
  if not found then raise exception 'not_found'; end if;
  v_draw := app.lock_draw(p_user, v_match.category_id);
  if v_draw.category_id is null or v_draw.status <> 'published' then raise exception 'not_found'; end if;
  -- Locked now; a redo that got in first has deleted it.
  select m.* into v_match from public.tournament_matches m where m.id = p_match_id for update;
  if not found then raise exception 'not_found'; end if;
  if v_match.status = 'done' then raise exception 'invalid_argument'; end if;
  select t.* into v_tournament
  from public.tournament_categories c join public.tournaments t on t.id = c.tournament_id
  where c.id = v_match.category_id;

  if p_starts_at is null then
    perform app.release_match_block(v_match.id);
    update public.tournament_matches m set court_id = null, starts_at = null, place_note = null
    where m.id = v_match.id;
    perform app.audit(p_user, 'schedule_match', 'tournament_match', v_match.id::text,
      jsonb_build_object('court_id', v_match.court_id, 'starts_at', v_match.starts_at), null, p_now);
    return;
  end if;

  if p_starts_at::date < v_tournament.starts_on or p_starts_at::date > v_tournament.ends_on then
    raise exception 'invalid_argument';
  end if;
  if char_length(v_note) > 100 then raise exception 'invalid_argument'; end if;
  v_start := app.to_instant(p_starts_at, app.tournament_offset(v_tournament));

  if v_tournament.venue_id is null then
    if p_court_id is not null then raise exception 'invalid_argument'; end if;
    v_span := tstzrange(v_start, v_start, '[]');
  else
    select c.* into v_court
    from public.courts c join public.venues v on v.id = c.venue_id
    where c.id = p_court_id and c.venue_id = v_tournament.venue_id and c.active and v.active;
    if not found then raise exception 'invalid_argument'; end if;
    if not exists (select 1 from app.court_slots(p_court_id, p_starts_at::date) s where s.starts_local = p_starts_at) then
      raise exception 'invalid_argument';
    end if;
    v_span := tstzrange(v_start, v_start + make_interval(mins => v_court.slot_minutes), '[)');
  end if;

  if app.players_busy(v_match.id, v_tournament.id, app.match_players(v_match), v_span) then
    raise exception 'player_busy';
  end if;

  v_changed := v_match.starts_at is distinct from v_start or v_match.court_id is distinct from p_court_id;

  -- Released and inserted again even when unchanged, so a block released
  -- meanwhile (a hidden tournament) comes back.
  perform app.release_match_block(v_match.id);
  if v_court.id is not null then
    perform app.lock_court_for_write(v_court.id, p_now);
    begin
      perform app.insert_match_block(v_match.id, v_court.id, v_span, p_now);
    exception when exclusion_violation or deadlock_detected then
      raise exception 'slot_taken';
    end;
  end if;

  update public.tournament_matches m set court_id = p_court_id, starts_at = v_start, place_note = v_note
  where m.id = v_match.id;

  if v_changed then perform app.notify_match_scheduled(v_match.id, p_now); end if;
  perform app.audit(p_user, 'schedule_match', 'tournament_match', v_match.id::text,
    jsonb_build_object('court_id', v_match.court_id, 'starts_at', v_match.starts_at),
    jsonb_build_object('court_id', p_court_id, 'starts_at', v_start, 'place_note', v_note), p_now);
end $$;

-- Places one match of "fill the day" in the earliest slot that fits (time,
-- then court in p_court_ids order) from p_from on p_day: free on the court;
-- no player of a known side busy; after both feeder matches end when they
-- are scheduled; a first knockout round after the category's scheduled
-- group matches; with p_gap, a free slot between an entry's group matches.
-- The caller holds the locks. True when placed.
create function app.place_match(
  p_match_id uuid, p_tournament public.tournaments, p_court_ids uuid[], p_day date, p_from time, p_gap boolean,
  p_now timestamptz)
returns boolean
language plpgsql
set search_path = ''
as $$
declare
  v_match public.tournament_matches;
  v_offset integer := app.tournament_offset(p_tournament);
  v_players uuid[];
  v_slot record;
  v_span tstzrange;
  v_gap interval;
begin
  select m.* into v_match from public.tournament_matches m where m.id = p_match_id;
  v_players := app.match_players(v_match);

  for v_slot in
    select s.starts_local, x.id as court_id, c.slot_minutes
    from unnest(p_court_ids) with ordinality x (id, ord)
    join public.courts c on c.id = x.id
    cross join lateral app.court_slots(x.id, p_day) s
    where s.starts_local >= p_day + p_from
    order by s.starts_local, x.ord
  loop
    v_span := tstzrange(app.to_instant(v_slot.starts_local, v_offset),
      app.to_instant(v_slot.starts_local, v_offset) + make_interval(mins => v_slot.slot_minutes), '[)');
    v_gap := make_interval(mins => v_slot.slot_minutes);

    continue when exists (
      select 1 from public.bookings b
      where b.court_id = v_slot.court_id and b.during && v_span
        and b.status in ('held', 'confirmed', 'completed', 'paid', 'no_show', 'unverified'));
    continue when app.players_busy(v_match.id, p_tournament.id, v_players, v_span);
    continue when v_match.stage = 'knockout' and v_match.round > 1 and exists (
      select 1 from public.tournament_matches f
      where f.category_id = v_match.category_id and f.stage = 'knockout' and f.round = v_match.round - 1
        and f.position in (2 * v_match.position - 1, 2 * v_match.position)
        and f.starts_at is not null and upper(app.match_span(f)) > lower(v_span));
    continue when v_match.stage = 'knockout' and v_match.round = 1 and exists (
      select 1 from public.tournament_matches g
      where g.category_id = v_match.category_id and g.stage = 'group'
        and g.starts_at is not null and upper(app.match_span(g)) > lower(v_span));
    continue when p_gap and v_match.stage = 'group' and exists (
      select 1 from public.tournament_matches o
      where o.category_id = v_match.category_id and o.stage = 'group' and o.id <> v_match.id
        and o.starts_at is not null
        and (o.side_a in (v_match.side_a, v_match.side_b) or o.side_b in (v_match.side_a, v_match.side_b))
        and tstzrange(lower(v_span) - v_gap, upper(v_span) + v_gap, '[)') && app.match_span(o));

    begin
      perform app.insert_match_block(v_match.id, v_slot.court_id, v_span, p_now);
      update public.tournament_matches m set court_id = v_slot.court_id, starts_at = lower(v_span), place_note = null
      where m.id = v_match.id;
      perform app.notify_match_scheduled(v_match.id, p_now);
      return true;
    exception when exclusion_violation or deadlock_detected then
      -- Taken after all: try the next slot.
      null;
    end;
  end loop;
  return false;
end $$;

-- "Fill the day" (§7.2, §14a.2): lays the unscheduled matches of the ticked
-- categories (null: all) with a published draw into free slots of the
-- chosen courts on p_day from p_from. Group matches of every category first,
-- round by round (keeping a free slot between an entry's matches, then,
-- for those that did not fit, without it), then knockout rounds in order.
-- Returns {"scheduled": n, "unscheduled": [match ids that did not fit]}.
create function app.fill_day(
  p_user uuid, p_tournament_id uuid, p_day date, p_court_ids uuid[], p_from time, p_category_ids uuid[],
  p_now timestamptz)
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  v_tournament public.tournaments;
  v_categories uuid[];
  v_court uuid;
  v_id uuid;
  v_retry uuid[] := '{}';
  v_unscheduled uuid[] := '{}';
  v_scheduled integer := 0;
begin
  select t.* into v_tournament from public.tournaments t where t.id = p_tournament_id;
  if not found then raise exception 'not_found'; end if;
  perform app.require_organizer(p_user, p_tournament_id);
  perform pg_advisory_xact_lock(hashtext('tournament:' || p_tournament_id::text));

  if v_tournament.venue_id is null or p_day is null or p_from is null
     or p_day < v_tournament.starts_on or p_day > v_tournament.ends_on
     or coalesce(cardinality(p_court_ids), 0) = 0
     or exists (select 1 from unnest(p_court_ids) x (id) group by x.id having count(*) > 1)
     or exists (
       select 1 from unnest(p_court_ids) x (id)
       where not exists (
         select 1 from public.courts c join public.venues v on v.id = c.venue_id
         where c.id = x.id and c.venue_id = v_tournament.venue_id and c.active and v.active))
     or exists (
       select 1 from unnest(p_category_ids) x (id)
       where not exists (
         select 1 from public.tournament_categories c where c.id = x.id and c.tournament_id = p_tournament_id)) then
    raise exception 'invalid_argument';
  end if;

  -- The categories in id order, then their draws; only published ones count.
  perform 1 from public.tournament_categories c
  where c.tournament_id = p_tournament_id and (p_category_ids is null or c.id = any (p_category_ids))
  order by c.id for update;
  select coalesce(array_agg(d.category_id order by d.category_id), '{}') into v_categories
  from (
    select d.category_id, d.status from public.tournament_draws d
    join public.tournament_categories c on c.id = d.category_id
    where c.tournament_id = p_tournament_id and (p_category_ids is null or c.id = any (p_category_ids))
    order by d.category_id for update of d
  ) d
  where d.status = 'published';

  perform 1 from public.tournament_matches m
  where m.category_id = any (v_categories)
  order by m.stage, m.round, m.position for update;

  -- The courts, one at a time in id order, as app.hold_slots takes them.
  for v_court in select distinct x from unnest(p_court_ids) x order by x loop
    perform app.lock_court_for_write(v_court, p_now);
  end loop;

  -- Group matches: with the gap first, then the ones left without it.
  for v_id in
    select m.id
    from public.tournament_matches m
    join public.tournament_categories c on c.id = m.category_id
    join public.tournament_groups g on g.id = m.group_id
    where m.category_id = any (v_categories) and m.stage = 'group'
      and m.starts_at is null and m.status in ('waiting', 'ready') and m.outcome is null
    order by m.round, c.sort_order, c.created_at, c.id, g.sort_order, m.position
  loop
    if app.place_match(v_id, v_tournament, p_court_ids, p_day, p_from, true, p_now) then
      v_scheduled := v_scheduled + 1;
    else
      v_retry := v_retry || v_id;
    end if;
  end loop;
  foreach v_id in array v_retry loop
    if app.place_match(v_id, v_tournament, p_court_ids, p_day, p_from, false, p_now) then
      v_scheduled := v_scheduled + 1;
    else
      v_unscheduled := v_unscheduled || v_id;
    end if;
  end loop;

  -- Knockout matches; a slot nobody fills (a bye still to settle) is no match.
  for v_id in
    select m.id
    from public.tournament_matches m
    join public.tournament_categories c on c.id = m.category_id
    where m.category_id = any (v_categories) and m.stage = 'knockout'
      and m.starts_at is null and m.status in ('waiting', 'ready') and m.outcome is null
      and not m.a_empty and not m.b_empty
    order by m.round, c.sort_order, c.created_at, c.id, m.position
  loop
    if app.place_match(v_id, v_tournament, p_court_ids, p_day, p_from, false, p_now) then
      v_scheduled := v_scheduled + 1;
    else
      v_unscheduled := v_unscheduled || v_id;
    end if;
  end loop;

  perform app.audit(p_user, 'fill_day', 'tournament', p_tournament_id::text, null,
    jsonb_build_object('day', p_day, 'court_ids', to_jsonb(p_court_ids), 'from', p_from,
      'category_ids', to_jsonb(p_category_ids), 'scheduled', v_scheduled), p_now);
  return jsonb_build_object('scheduled', v_scheduled, 'unscheduled', to_jsonb(v_unscheduled));
end $$;

-- ---------------------------------------------------------------------------
-- Owners: tournament blocks in the calendar, and they cannot cancel them
-- ---------------------------------------------------------------------------

-- Redefined from 20261124110000_games_v2.sql: a tournament match's block is
-- the organiser's to move or clear (tournament_block).
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
  if v_before.tournament_match_id is not null then raise exception 'tournament_block'; end if;
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

-- Redefined from 20261123100000_owner.sql: a slot covered by a tournament
-- block also carries "tournament": {"title", "match_id"}.
create or replace function app.owner_calendar(p_user uuid, p_court_id uuid, p_from date, p_days integer, p_now timestamptz)
returns jsonb
language plpgsql stable
set search_path = ''
as $$
declare
  v_offset integer;
  v_range tstzrange;
  v_slots jsonb;
  v_bookings jsonb;
begin
  perform app.require_court_manager(p_user, p_court_id);
  if p_from is null or p_days is null or p_days < 1 or p_days > 14 then raise exception 'invalid_argument'; end if;

  select ci.utc_offset_minutes into v_offset
  from public.courts c
  join public.venues v on v.id = c.venue_id
  join public.cities ci on ci.id = v.city_id
  where c.id = p_court_id;

  v_range := tstzrange(
    app.to_instant(p_from::timestamp, v_offset), app.to_instant((p_from + p_days)::timestamp, v_offset), '[)');

  with active as (
    select b as bk, b.id, b.source, b.during, b.tournament_match_id
    from public.bookings b
    where b.court_id = p_court_id
      and b.during && v_range
      and (b.status in ('confirmed', 'completed', 'paid', 'no_show', 'unverified')
           or (b.status = 'held' and b.hold_expires_at > p_now))
  ),
  slots as (
    select s.starts_local, s.ends_local, s.price
    from generate_series(0, p_days - 1) d (n)
    cross join lateral app.court_slots(p_court_id, p_from + d.n) s
  )
  select
    coalesce((
      select jsonb_agg(jsonb_build_object(
          'starts_local', s.starts_local,
          'ends_local', s.ends_local,
          'price', s.price,
          'state', case
            when cover.id is not null then case when cover.source = 'block' then 'blocked' else 'booked' end
            when app.to_instant(s.ends_local, v_offset) <= p_now then 'past'
            else 'free'
          end,
          'booking_id', cover.id)
          || case when cover.tournament_match_id is null then '{}'::jsonb else jsonb_build_object('tournament', (
               select jsonb_build_object(
                 'title', jsonb_build_object('uz', t.title_uz, 'ru', t.title_ru, 'kk', t.title_kk, 'en', t.title_en),
                 'match_id', m.id)
               from public.tournament_matches m
               join public.tournament_categories c on c.id = m.category_id
               join public.tournaments t on t.id = c.tournament_id
               where m.id = cover.tournament_match_id)) end
        order by s.starts_local)
      from slots s
      left join lateral (
        select a.id, a.source, a.tournament_match_id from active a
        where a.during && tstzrange(app.to_instant(s.starts_local, v_offset), app.to_instant(s.ends_local, v_offset))
        order by lower(a.during)
        limit 1
      ) cover on true), '[]'::jsonb),
    coalesce((
      select jsonb_agg(app.owner_booking_json(a.bk) order by lower(a.during), a.id)
      from active a), '[]'::jsonb)
  into v_slots, v_bookings;

  return jsonb_build_object('slots', v_slots, 'bookings', v_bookings);
end $$;

-- ---------------------------------------------------------------------------
-- Admin edits after a draw exists (§14a.1)
-- ---------------------------------------------------------------------------

-- Redefined from 20261126110000_launch.sql: an edit takes the tournament's
-- advisory lock before its row, as scheduling does. Once a category has a
-- draw, the sport and venue stay (draw_exists) and the dates must keep every
-- scheduled match (matches_outside_dates). Hiding the tournament releases
-- the blocks of its unplayed matches.
create or replace function app.admin_save_tournament(p_user uuid, p_tournament jsonb, p_now timestamptz) returns uuid
language plpgsql
set search_path = ''
as $$
declare
  c_spec constant jsonb := '{
    "id": "uuid", "city_id": "string", "sport_id": "string", "venue_id": "text",
    "title_uz": "text", "title_ru": "text", "title_kk": "text", "title_en": "text",
    "description_uz": "long_text", "description_ru": "long_text", "description_kk": "long_text", "description_en": "long_text",
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
    perform pg_advisory_xact_lock(hashtext('tournament:' || ((v_patch ->> 'id')::uuid)::text));
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
  if coalesce(v_row.title_uz, v_row.title_ru, v_row.title_en, v_row.title_kk) is null then raise exception 'invalid_argument'; end if;
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
        tournament_id, name_uz, name_ru, name_kk, name_en, kind, gender, min_level, max_level, fee, cap, created_at)
      values (v_row.id, 'Ochiq', 'Открытая', 'Ашық', 'Open', 'singles', 'open', 1, 5, 0, 16, p_now);
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
    -- A draw (draft or published) is made for this sport at this venue.
    if (v_row.sport_id <> v_before.sport_id or v_row.venue_id is distinct from v_before.venue_id) and exists (
      select 1 from public.tournament_draws d
      join public.tournament_categories c on c.id = d.category_id
      where c.tournament_id = v_row.id) then
      raise exception 'draw_exists';
    end if;
    if (v_row.starts_on <> v_before.starts_on or v_row.ends_on <> v_before.ends_on or v_row.city_id <> v_before.city_id)
       and exists (
         select 1 from public.tournament_matches m
         join public.tournament_categories c on c.id = m.category_id
         where c.tournament_id = v_row.id and m.starts_at is not null
           and app.to_local(m.starts_at, v_offset)::date not between v_row.starts_on and v_row.ends_on) then
      raise exception 'matches_outside_dates';
    end if;
    update public.tournaments t set
      city_id = v_row.city_id, sport_id = v_row.sport_id, venue_id = v_row.venue_id,
      title_uz = v_row.title_uz, title_ru = v_row.title_ru, title_kk = v_row.title_kk, title_en = v_row.title_en,
      description_uz = v_row.description_uz, description_ru = v_row.description_ru, description_kk = v_row.description_kk, description_en = v_row.description_en,
      starts_on = v_row.starts_on, ends_on = v_row.ends_on, registration_deadline = v_row.registration_deadline,
      cover_url = v_row.cover_url, color_seed = v_row.color_seed, active = v_row.active
    where t.id = v_row.id
    returning * into v_row;
    v_after := to_jsonb(v_row);
    -- Hidden: the venue gets back the slots of every match not yet played.
    if v_before.active and not v_row.active then
      delete from public.bookings b
      using public.tournament_matches m, public.tournament_categories c
      where b.tournament_match_id = m.id and m.category_id = c.id and c.tournament_id = v_row.id
        and m.status <> 'done';
    end if;
  end if;

  perform app.audit(p_user, case when v_creating then 'create_tournament' else 'update_tournament' end, 'tournament',
    v_row.id::text, case when v_creating then null else to_jsonb(v_before) end, v_after, p_now);
  return v_row.id;
end $$;

-- Redefined from 20261126100000_kazakh.sql: the kind stays once the
-- category has a draw (draw_exists).
create or replace function app.admin_save_category(p_user uuid, p_category jsonb, p_now timestamptz) returns uuid
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
    if v_row.kind <> v_before.kind and exists (select 1 from public.tournament_draws d where d.category_id = v_row.id) then
      raise exception 'draw_exists';
    end if;
    if v_row.kind <> v_before.kind and exists (
      select 1 from public.tournament_registrations r
      where r.category_id = v_row.id and r.status in ('pending_partner', 'registered', 'waitlisted', 'offered')) then
      raise exception 'has_registrations';
    end if;
    update public.tournament_categories c set
      name_uz = v_row.name_uz, name_ru = v_row.name_ru, name_kk = v_row.name_kk, name_en = v_row.name_en,
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

-- Redefined from 20261125110000_admin_tournaments.sql: never a category with
-- a draw (draw_exists).
-- Only a category no registration has ever been in, finished ones included
-- (has_registrations): registration history is never deleted, as the
-- foreign key's `on delete restrict` intends. Never a tournament's last
-- category (invalid_argument: every tournament keeps one).
create or replace function app.admin_delete_category(p_user uuid, p_category_id uuid, p_now timestamptz) returns void
language plpgsql
set search_path = ''
as $$
declare
  v_category public.tournament_categories;
begin
  perform app.require_admin(p_user);
  select c.* into v_category from public.tournament_categories c where c.id = p_category_id for update;
  if not found then raise exception 'not_found'; end if;
  if exists (select 1 from public.tournament_draws d where d.category_id = v_category.id) then
    raise exception 'draw_exists';
  end if;
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
-- What the app calls. Each runs as the signed-in user at the real time.
-- ---------------------------------------------------------------------------

-- Returns the match afterwards.
create function public.schedule_match(
  p_match_id uuid, p_court_id uuid default null, p_starts_at timestamp default null, p_place_note text default null)
returns jsonb
language sql security definer
set search_path = ''
as $$
  select app.schedule_match((select auth.uid()), p_match_id, p_court_id, p_starts_at, p_place_note, now());
  select app.match_json(m) from public.tournament_matches m where m.id = p_match_id;
$$;

create function public.fill_day(
  p_tournament_id uuid, p_day date, p_court_ids uuid[], p_from time, p_category_ids uuid[] default null)
returns jsonb
language sql security definer
set search_path = ''
as $$ select app.fill_day((select auth.uid()), p_tournament_id, p_day, p_court_ids, p_from, p_category_ids, now()) $$;

revoke all on function
  public.schedule_match(uuid, uuid, timestamp, text),
  public.fill_day(uuid, date, uuid[], time, uuid[])
from public, anon, authenticated;

grant execute on function
  public.schedule_match(uuid, uuid, timestamp, text),
  public.fill_day(uuid, date, uuid[], time, uuid[])
to authenticated, service_role;
