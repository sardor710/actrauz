-- M6 launch changes. Additive: create-or-replace only, no signature changes.

-- ---------------------------------------------------------------------------
-- Games and Game Requests at a hidden (inactive) venue stay out of the public
-- lists. The venue row is already hidden by RLS; this keeps the feeds from
-- pointing at it. What a player hosts, plays in or is invited to still shows
-- (their own games), and games without a venue are unaffected.
-- ---------------------------------------------------------------------------

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
       and g.visibility = 'public'
       and (g.venue_id is null
            or exists (select 1 from public.venues v where v.id = g.venue_id and v.active))
       and ((select count(*) from public.game_participants p where p.game_id = g.id) < g.spots
            or exists (select 1 from public.game_participants p where p.game_id = g.id and p.user_id = p_user)))
      or (p_user is not null and (
        g.host_id = p_user
        or exists (select 1 from public.game_participants p where p.game_id = g.id and p.user_id = p_user)
        or exists (select 1 from public.game_invites i
                   where i.game_id = g.id and i.user_id = p_user and i.status = 'pending'))))
  order by lower(g.during), g.id
$$;

create or replace function app.list_game_requests(p_user uuid, p_city_id text, p_now timestamptz) returns setof jsonb
language sql
set search_path = ''
as $$
  select app.game_request_json(r, p_user)
  from public.game_requests r
  where r.status = 'open'
    and upper(r.during) > p_now
    and ((r.city_id = p_city_id
          and (r.venue_id is null
               or exists (select 1 from public.venues v where v.id = r.venue_id and v.active)))
         or (p_user is not null and r.host_id = p_user))
  order by lower(r.during), r.id
$$;

-- ---------------------------------------------------------------------------
-- Account deletion (both app stores require it in the app). Bookings, games
-- and registrations reference profiles without cascading, and owners need
-- their booking history, so an account is scrubbed and closed rather than
-- deleted: everything still to come is cancelled the usual way (the other
-- people get their usual notifications), personal rows are deleted, and the
-- profile keeps only its id, its history and deleted_at. The auth user is
-- renamed and banned by the delete-account edge function afterwards.
-- ---------------------------------------------------------------------------

-- null = a live account.
alter table public.profiles add column deleted_at timestamptz;

-- Other players see that an account is gone (the app shows a placeholder
-- name). Added to the column grants of 20261124100000_community_core.sql:25;
-- the private settings columns stay private.
grant select (deleted_at) on table public.profiles to authenticated;

-- Redefined from 20261122100100_profiles.sql: a deleted account's session,
-- still valid until it expires, cannot write a name or a city back.
alter policy "players edit their own profile" on public.profiles
  using (id = (select auth.uid()) and deleted_at is null)
  with check (id = (select auth.uid()) and deleted_at is null);

-- Redefined from 20261124100000_community_core.sql: a deleted account gets
-- no notifications.
create or replace function app.notify(p_user uuid, p_kind text, p_category text, p_payload jsonb, p_now timestamptz)
returns void
language plpgsql
set search_path = ''
as $$
begin
  if p_user is null then return; end if;
  insert into public.notifications (user_id, kind, category, payload, created_at)
  select p.id, p_kind, p_category, coalesce(p_payload, '{}'), p_now
  from public.profiles p
  where p.id = p_user and p.deleted_at is null and not (p_category = any (p.muted_categories));
end $$;

-- Redefined from 20261124120000_game_requests.sql: deleted players are not
-- found by Find players.
create or replace function app.list_players(
  p_user uuid, p_city_id text, p_sport_id text, p_min_level integer, p_max_level integer,
  p_query text, p_limit integer) returns setof jsonb
language sql
set search_path = ''
as $$
  select app.player_json(pr)
  from public.profiles pr
  where pr.city_id = p_city_id
    and pr.deleted_at is null
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

-- Redefined from 20261124110000_games_v2.sql: a deleted player cannot be
-- invited (not_found, as for an unknown id).
create or replace function app.invite_to_game(p_user uuid, p_game_id uuid, p_invitee uuid, p_now timestamptz) returns public.games
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
  if not exists (select 1 from public.profiles p where p.id = p_invitee and p.deleted_at is null) then
    raise exception 'not_found';
  end if;
  if exists (select 1 from public.game_participants p where p.game_id = p_game_id and p.user_id = p_invitee) then
    raise exception 'already_joined';
  end if;

  -- Inviting a player the host removed earlier lets them back in.
  delete from public.game_join_requests r
  where r.game_id = p_game_id and r.user_id = p_invitee and r.status = 'removed';

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

-- Redefined from 20261125100000_tournaments.sql: a deleted player cannot be
-- named as a tournament partner (register and join_waitlist).
create or replace function app.check_entry(
  p_user uuid, c public.tournament_categories, t public.tournaments, p_partner_id uuid, p_now timestamptz)
returns void
language plpgsql
set search_path = ''
as $$
begin
  perform app.require_reliable(p_user, p_now);
  if p_now >= app.tournament_deadline(t) then raise exception 'deadline_passed'; end if;

  if c.kind = 'singles' and p_partner_id is not null then raise exception 'invalid_argument'; end if;
  if c.kind = 'pairs' then
    if p_partner_id is null or p_partner_id = p_user then raise exception 'invalid_argument'; end if;
    if not exists (select 1 from public.profiles p where p.id = p_partner_id and p.deleted_at is null) then
      raise exception 'not_found';
    end if;
  end if;

  if app.player_level(p_user, t.sport_id) not between c.min_level and c.max_level
     or (p_partner_id is not null and app.player_level(p_partner_id, t.sport_id) not between c.min_level and c.max_level) then
    raise exception 'level_out_of_range';
  end if;

  if app.live_in_category(c.id, p_user, null) then raise exception 'already_registered'; end if;
  if p_partner_id is not null and app.live_in_category(c.id, p_partner_id, null) then
    raise exception 'partner_unavailable';
  end if;
end $$;

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

-- For the delete-account edge function, which runs with the service role
-- after checking the player's JWT. Never callable by players directly.
create or replace function public.delete_account_service(p_user uuid) returns void
language sql security definer
set search_path = ''
as $$ select app.delete_account(p_user, now()) $$;

revoke all on function public.delete_account_service(uuid) from public, anon, authenticated;
grant execute on function public.delete_account_service(uuid) to service_role;

-- ---------------------------------------------------------------------------
-- A deleted player in someone else's history (past games, an owner's
-- bookings, tournament lists) shows as "Deleted player" in the app. Their
-- name is null by then, but a null name alone means a sign-up that was never
-- finished, so the JSON that names other players says it outright: a person
-- object gets `deleted: true`, and the two flat rows get `customer_deleted`
-- (an owner's booking) and `host_deleted` (a Game Request). The key is there
-- only when true, so every existing shape is unchanged for live players.
-- Notification payloads need nothing: their actor_name is written when the
-- actor acts, and a deleted account no longer acts.
-- ---------------------------------------------------------------------------

-- `{p_key: true}` for a deleted account, `{}` otherwise (also for null).
create function app.deleted_json(p_user uuid, p_key text default 'deleted') returns jsonb
language sql stable
set search_path = ''
as $$
  select case when exists (select 1 from public.profiles p where p.id = p_user and p.deleted_at is not null)
    then jsonb_build_object(p_key, true) else '{}'::jsonb end
$$;

-- Redefined from 20261124110000_games_v2.sql: participants and join
-- requests carry `deleted`, and a scrubbed meeting point ('') is null.
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
                  'reliability', app.reliability(p.user_id, now()))
                || app.deleted_json(p.user_id)
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
                   || app.deleted_json(r.user_id)
                   order by r.created_at, r.id)
          from public.game_join_requests r
          join public.profiles pr on pr.id = r.user_id
          left join public.player_levels l on l.user_id = r.user_id and l.sport_id = g.sport_id
          where r.game_id = g.id and r.status = 'pending'),
         '[]'::jsonb))
     else '{}'::jsonb end
$$;

-- Redefined from 20261124120000_game_requests.sql: interested players carry
-- `deleted`, the request `host_deleted`.
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
                || app.deleted_json(i.user_id)
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
  || app.deleted_json(r.host_id, 'host_deleted')
$$;

-- Redefined from 20261124120000_game_requests.sql: carries `deleted`.
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
    'reliability', app.reliability(pr.id, now()),
    'games_played', (
      select count(*) from public.game_participants gp
      join public.games g on g.id = gp.game_id
      where gp.user_id = pr.id and g.completed_at is not null))
  || case when pr.deleted_at is not null then jsonb_build_object('deleted', true) else '{}'::jsonb end
$$;

-- Redefined from 20261123100000_owner.sql: an app booking by a deleted
-- player carries `customer_deleted` (walk-ins and blocks never do).
create or replace function app.owner_booking_json(b public.bookings) returns jsonb
language sql stable
set search_path = ''
as $$
  select app.booking_json(b) || jsonb_build_object(
    -- Never say whether a walk-in's phone matched an account.
    'user_id', case when b.source = 'walk_in' then null else b.user_id end,
    'source', b.source,
    'walk_in_payment', b.walk_in_payment,
    'customer_name', case b.source
      when 'walk_in' then b.guest_name
      when 'app' then (select p.full_name from public.profiles p where p.id = b.user_id)
    end,
    'customer_phone', case b.source
      when 'walk_in' then b.guest_phone
      when 'app' then (select c.phone from public.profile_contacts c where c.user_id = b.user_id)
    end,
    'reason', case when b.source = 'block' then b.block_reason end)
  || case when b.source = 'app' then app.deleted_json(b.user_id, 'customer_deleted') else '{}'::jsonb end
$$;

-- Redefined from 20261126100000_kazakh.sql: registrant and partner carry
-- `deleted`.
create or replace function app.registration_json(r public.tournament_registrations) returns jsonb
language sql
set search_path = ''
as $$
  select jsonb_build_object(
    'id', r.id,
    'tournament_id', c.tournament_id,
    'category_id', r.category_id,
    'category_name', jsonb_build_object('uz', c.name_uz, 'ru', c.name_ru, 'kk', c.name_kk, 'en', c.name_en),
    'kind', c.kind,
    'status', r.status,
    'registrant', jsonb_build_object('id', r.user_id, 'name', (select p.full_name from public.profiles p where p.id = r.user_id))
      || app.deleted_json(r.user_id),
    'partner', case when r.partner_id is null then null else
      jsonb_build_object('id', r.partner_id, 'name', (select p.full_name from public.profiles p where p.id = r.partner_id))
      || app.deleted_json(r.partner_id) end,
    'partner_confirmed', r.partner_confirmed,
    'fee', r.fee,
    'currency', r.currency,
    'paid', r.paid_at is not null,
    'partner_expires_local', app.to_local(r.partner_expires_at, app.tournament_offset(t)),
    'offer_expires_local', app.to_local(r.offer_expires_at, app.tournament_offset(t)),
    -- 1 = next in line, among entries that can be offered a spot (singles,
    -- and pairs whose partner confirmed); null for a pair still waiting on
    -- its partner.
    'waitlist_place', case when r.status = 'waitlisted' and r.partner_confirmed then
      (select count(*) from public.tournament_registrations w
       where w.category_id = r.category_id and w.status = 'waitlisted' and w.partner_confirmed
         and (w.waitlist_position, w.id) <= (r.waitlist_position, r.id)) end,
    'created_at', r.created_at)
  from public.tournament_categories c
  join public.tournaments t on t.id = c.tournament_id
  where c.id = r.category_id
$$;

-- Redefined from 20261125110000_admin_tournaments.sql: it replaces
-- registrant and partner with its own objects, so they carry `deleted` here
-- too.
create or replace function app.admin_registration_json(r public.tournament_registrations) returns jsonb
language sql
set search_path = ''
as $$
  select app.registration_json(r) || jsonb_build_object(
    'registrant', (select jsonb_build_object('id', p.id, 'name', p.full_name, 'phone', pc.phone)
                          || app.deleted_json(p.id)
                   from public.profiles p left join public.profile_contacts pc on pc.user_id = p.id
                   where p.id = r.user_id),
    'partner', case when r.partner_id is null then null else
      (select jsonb_build_object('id', p.id, 'name', p.full_name, 'phone', pc.phone)
              || app.deleted_json(p.id)
       from public.profiles p left join public.profile_contacts pc on pc.user_id = p.id
       where p.id = r.partner_id) end,
    'paid_at', r.paid_at,
    'admin_override', r.admin_override,
    'waitlist_position', r.waitlist_position)
$$;

-- ---------------------------------------------------------------------------
-- Redefined from 20261126100000_kazakh.sql: the default "Open" category a
-- tournament gets when it is created without categories has its Kazakh name.
-- ---------------------------------------------------------------------------

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
    update public.tournaments t set
      city_id = v_row.city_id, sport_id = v_row.sport_id, venue_id = v_row.venue_id,
      title_uz = v_row.title_uz, title_ru = v_row.title_ru, title_kk = v_row.title_kk, title_en = v_row.title_en,
      description_uz = v_row.description_uz, description_ru = v_row.description_ru, description_kk = v_row.description_kk, description_en = v_row.description_en,
      starts_on = v_row.starts_on, ends_on = v_row.ends_on, registration_deadline = v_row.registration_deadline,
      cover_url = v_row.cover_url, color_seed = v_row.color_seed, active = v_row.active
    where t.id = v_row.id
    returning * into v_row;
    v_after := to_jsonb(v_row);
  end if;

  perform app.audit(p_user, case when v_creating then 'create_tournament' else 'update_tournament' end, 'tournament',
    v_row.id::text, case when v_creating then null else to_jsonb(v_before) end, v_after, p_now);
  return v_row.id;
end $$;
