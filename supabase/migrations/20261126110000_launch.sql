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
-- ended (bookings, games, past tournaments) stays as anonymous history.
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
  -- not ended. Every category involved is locked first, in id order, before
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
      and t.ends_on >= app.to_local(p_now, app.tournament_offset(t))::date
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
