-- Milestone 7c: teams — creating and editing a team, joining (open or by
-- the captain's approval), invites, leaving, removing members, handing over
-- the captain role, deleting, admin removal, the team JSON and lists
-- (design 2026-11-27-actra-m7-competitive §7), and team games (at the end).
--
-- Additive: new server-only tables and functions. app.player_json and
-- app.delete_account are copied from 20261127120000_after_game.sql; the game
-- functions redefined in the team games part say where they come from. Every
-- signature stays.
--
-- Lock order: every function that changes a team locks its row first
-- (for update), then the member, request and invite rows. Two functions
-- lock a profile row (for no key update, before any team row): create_team,
-- so one player's creations take turns, and delete_account.

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------

create table public.teams (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(btrim(name)) between 3 and 40),
  sport_id text not null references public.sports (id),
  city_id text not null references public.cities (id),
  description text check (char_length(description) <= 500),
  join_policy text not null check (join_policy in ('open', 'approval')),
  -- 0-7: which colour the app puts behind the team's initials.
  color_seed integer not null default 0,
  captain_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now()
);

-- A name is free once per city and sport, whatever its case and spaces.
create unique index teams_name_idx on public.teams (city_id, sport_id, lower(btrim(name)));
create index teams_captain_idx on public.teams (captain_id);

-- The captain has a row too.
create table public.team_members (
  team_id uuid not null references public.teams (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (team_id, user_id)
);
create index team_members_user_idx on public.team_members (user_id);

create table public.team_join_requests (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null references public.teams (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  status text not null default 'pending' check (status in ('pending', 'approved', 'declined', 'withdrawn')),
  created_at timestamptz not null default now(),
  decided_at timestamptz
);
-- At most one open request per player and team; old ones stay as history.
create unique index team_join_requests_pending_idx on public.team_join_requests (team_id, user_id) where status = 'pending';
create index team_join_requests_user_idx on public.team_join_requests (user_id);

create table public.team_invites (
  team_id uuid not null references public.teams (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  invited_by uuid not null references public.profiles (id) on delete cascade,
  status text not null default 'pending' check (status in ('pending', 'accepted', 'declined')),
  created_at timestamptz not null default now(),
  primary key (team_id, user_id)
);
create index team_invites_user_idx on public.team_invites (user_id);

alter table public.teams enable row level security;
alter table public.team_members enable row level security;
alter table public.team_join_requests enable row level security;
alter table public.team_invites enable row level security;
revoke all on table public.teams, public.team_members, public.team_join_requests, public.team_invites from anon, authenticated;
grant all on table public.teams, public.team_members, public.team_join_requests, public.team_invites to service_role;

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

-- A caller with a live account (not_authenticated otherwise).
create function app.require_live_player(p_user uuid) returns void
language plpgsql
set search_path = ''
as $$
begin
  if p_user is null or not exists (select 1 from public.profiles p where p.id = p_user and p.deleted_at is null) then
    raise exception 'not_authenticated';
  end if;
end $$;

-- Locks and returns the team (not_found when missing); with p_captain, the
-- caller must be its captain (not_allowed otherwise).
create function app.lock_team(p_user uuid, p_team_id uuid, p_captain boolean) returns public.teams
language plpgsql
set search_path = ''
as $$
declare
  v_team public.teams;
begin
  select t.* into v_team from public.teams t where t.id = p_team_id for update;
  if not found then raise exception 'not_found'; end if;
  if p_captain and v_team.captain_id <> p_user then raise exception 'not_allowed'; end if;
  return v_team;
end $$;

-- {"team_id", "team_name", "actor_name"}: the payload of every team notice.
create function app.team_note(t public.teams, p_actor uuid) returns jsonb
language sql stable
set search_path = ''
as $$
  select jsonb_build_object(
    'team_id', t.id,
    'team_name', t.name,
    'actor_name', (select p.full_name from public.profiles p where p.id = p_actor))
$$;

-- Validated name, description and join policy of a new or edited team, from
-- p_team over p_current (null for a new team): a key that is absent keeps
-- the current value. invalid_argument for a name of fewer than 3 or more
-- than 40 characters after trimming, a description over 500 characters, or
-- a policy other than open or approval.
create function app.team_fields(p_team jsonb, p_current public.teams) returns public.teams
language plpgsql
set search_path = ''
as $$
declare
  v_team public.teams := p_current;
begin
  if p_team is null or jsonb_typeof(p_team) <> 'object' then raise exception 'invalid_argument'; end if;
  if p_current.id is null or p_team ? 'name' then
    v_team.name := btrim(p_team->>'name');
  end if;
  if p_current.id is null or p_team ? 'description' then
    v_team.description := nullif(btrim(p_team->>'description'), '');
  end if;
  if p_current.id is null or p_team ? 'join_policy' then
    v_team.join_policy := p_team->>'join_policy';
  end if;
  if v_team.name is null or char_length(v_team.name) not between 3 and 40
     or char_length(v_team.description) > 500
     or v_team.join_policy is null or v_team.join_policy not in ('open', 'approval') then
    raise exception 'invalid_argument';
  end if;
  return v_team;
end $$;

-- Makes a player a member of a team whose row the caller has locked, and
-- settles their pending request (approved) and pending invite (accepted).
create function app.add_team_member(p_team public.teams, p_member uuid, p_now timestamptz) returns void
language plpgsql
set search_path = ''
as $$
begin
  insert into public.team_members (team_id, user_id, joined_at) values (p_team.id, p_member, p_now);
  update public.team_join_requests r set status = 'approved', decided_at = p_now
  where r.team_id = p_team.id and r.user_id = p_member and r.status = 'pending';
  update public.team_invites i set status = 'accepted'
  where i.team_id = p_team.id and i.user_id = p_member and i.status = 'pending';
end $$;

-- Tells every member but p_actor that the team is going, then deletes it
-- (the members, requests and invites go with it).
create function app.drop_team(p_team public.teams, p_actor uuid, p_now timestamptz) returns void
language plpgsql
set search_path = ''
as $$
begin
  perform app.notify(m.user_id, 'team_deleted', 'teams', app.team_note(p_team, p_actor), p_now)
  from public.team_members m
  where m.team_id = p_team.id and m.user_id is distinct from p_actor;
  delete from public.teams t where t.id = p_team.id;
end $$;

-- ---------------------------------------------------------------------------
-- Creating, editing, deleting
-- ---------------------------------------------------------------------------

-- Keys name, sport_id (an active sport), city_id (a known city),
-- description, join_policy. A player captains at most 5 teams (team_limit);
-- the name is free in that city and sport (already_exists). The creator
-- becomes captain and member.
create function app.create_team(p_user uuid, p_team jsonb, p_now timestamptz) returns public.teams
language plpgsql
set search_path = ''
as $$
declare
  c_max_captained constant integer := 5;
  v_team public.teams;
begin
  perform app.require_live_player(p_user);
  v_team := app.team_fields(p_team, null);
  v_team.sport_id := p_team->>'sport_id';
  v_team.city_id := p_team->>'city_id';
  if not exists (select 1 from public.sports s where s.id = v_team.sport_id and s.active)
     or not exists (select 1 from public.cities c where c.id = v_team.city_id) then
    raise exception 'invalid_argument';
  end if;

  -- The profile lock makes two creations by one player take turns, so the
  -- limit holds (the same lock delete_account takes). Checked again under
  -- the lock: an account deleted meanwhile captains nothing new.
  perform 1 from public.profiles p where p.id = p_user and p.deleted_at is null for no key update;
  if not found then raise exception 'not_authenticated'; end if;
  if (select count(*) from public.teams t where t.captain_id = p_user) >= c_max_captained then
    raise exception 'team_limit';
  end if;

  v_team.id := gen_random_uuid();
  v_team.color_seed := get_byte(uuid_send(v_team.id), 15) % 8;
  begin
    insert into public.teams (id, name, sport_id, city_id, description, join_policy, color_seed, captain_id, created_at)
    values (v_team.id, v_team.name, v_team.sport_id, v_team.city_id, v_team.description, v_team.join_policy,
            v_team.color_seed, p_user, p_now)
    returning * into v_team;
  exception when unique_violation then
    raise exception 'already_exists';
  end;
  insert into public.team_members (team_id, user_id, joined_at) values (v_team.id, p_user, p_now);
  return v_team;
end $$;

-- name, description and join_policy only; an absent key stays as it is.
-- Pending requests stay when a team opens up: the captain still decides them.
create function app.update_team(p_user uuid, p_team_id uuid, p_team jsonb, p_now timestamptz) returns public.teams
language plpgsql
set search_path = ''
as $$
declare
  v_team public.teams;
begin
  perform app.require_live_player(p_user);
  v_team := app.team_fields(p_team, app.lock_team(p_user, p_team_id, true));
  begin
    update public.teams t
    set name = v_team.name, description = v_team.description, join_policy = v_team.join_policy
    where t.id = p_team_id
    returning * into v_team;
  exception when unique_violation then
    raise exception 'already_exists';
  end;
  return v_team;
end $$;

create function app.delete_team(p_user uuid, p_team_id uuid, p_now timestamptz) returns void
language plpgsql
set search_path = ''
as $$
begin
  perform app.require_live_player(p_user);
  perform app.drop_team(app.lock_team(p_user, p_team_id, true), p_user, p_now);
end $$;

-- Audited as team_deleted with the team row as `before`.
create function app.admin_delete_team(p_user uuid, p_team_id uuid, p_now timestamptz) returns void
language plpgsql
set search_path = ''
as $$
declare
  v_team public.teams;
begin
  perform app.require_admin(p_user);
  v_team := app.lock_team(p_user, p_team_id, false);
  perform app.drop_team(v_team, p_user, p_now);
  perform app.audit(p_user, 'team_deleted', 'team', p_team_id::text, to_jsonb(v_team), null, p_now);
end $$;

-- ---------------------------------------------------------------------------
-- Joining and leaving
-- ---------------------------------------------------------------------------

-- An open team, or a team that invited the player: a member at once (the
-- invite is accepted). An approval team: a pending request, and the captain
-- hears (team_join_request).
create function app.join_team(p_user uuid, p_team_id uuid, p_now timestamptz) returns public.teams
language plpgsql
set search_path = ''
as $$
declare
  v_team public.teams;
begin
  perform app.require_live_player(p_user);
  v_team := app.lock_team(p_user, p_team_id, false);
  if exists (select 1 from public.team_members m where m.team_id = p_team_id and m.user_id = p_user) then
    raise exception 'already_joined';
  end if;

  if v_team.join_policy = 'open'
     or exists (select 1 from public.team_invites i
                where i.team_id = p_team_id and i.user_id = p_user and i.status = 'pending') then
    perform app.add_team_member(v_team, p_user, p_now);
    return v_team;
  end if;

  begin
    insert into public.team_join_requests (team_id, user_id, created_at) values (p_team_id, p_user, p_now);
  exception when unique_violation then
    raise exception 'already_requested';
  end;
  perform app.notify(v_team.captain_id, 'team_join_request', 'teams', app.team_note(v_team, p_user), p_now);
  return v_team;
end $$;

-- A member leaves; the captain hands the role over first (captain_cannot_leave).
create function app.leave_team(p_user uuid, p_team_id uuid, p_now timestamptz) returns void
language plpgsql
set search_path = ''
as $$
declare
  v_team public.teams;
begin
  perform app.require_live_player(p_user);
  v_team := app.lock_team(p_user, p_team_id, false);
  if v_team.captain_id = p_user then raise exception 'captain_cannot_leave'; end if;
  delete from public.team_members m where m.team_id = p_team_id and m.user_id = p_user;
  if not found then raise exception 'not_found'; end if;
end $$;

-- The requester takes back a pending request.
create function app.withdraw_team_request(p_user uuid, p_request_id uuid) returns void
language plpgsql
set search_path = ''
as $$
begin
  if p_user is null then raise exception 'not_authenticated'; end if;
  update public.team_join_requests r set status = 'withdrawn', decided_at = now()
  where r.id = p_request_id and r.user_id = p_user and r.status = 'pending';
  if not found then raise exception 'not_found'; end if;
end $$;

-- The captain approves (the player becomes a member) or declines a pending
-- request; the player hears either way. A deleted account is never approved.
create function app.decide_team_request(p_user uuid, p_request_id uuid, p_approve boolean, p_now timestamptz)
returns public.teams
language plpgsql
set search_path = ''
as $$
declare
  v_team public.teams;
  v_request public.team_join_requests;
begin
  perform app.require_live_player(p_user);
  if p_approve is null then raise exception 'invalid_argument'; end if;

  -- Team first, then the request (the order everywhere).
  v_team := app.lock_team(p_user, (select r.team_id from public.team_join_requests r where r.id = p_request_id), true);
  select r.* into v_request from public.team_join_requests r where r.id = p_request_id for update;
  if v_request.status <> 'pending' then raise exception 'not_found'; end if;

  if p_approve then
    if not exists (select 1 from public.profiles p where p.id = v_request.user_id and p.deleted_at is null) then
      raise exception 'not_found';
    end if;
    if exists (select 1 from public.team_members m where m.team_id = v_team.id and m.user_id = v_request.user_id) then
      raise exception 'already_joined';
    end if;
    perform app.add_team_member(v_team, v_request.user_id, p_now);
    perform app.notify(v_request.user_id, 'team_join_approved', 'teams', app.team_note(v_team, p_user), p_now);
  else
    update public.team_join_requests r set status = 'declined', decided_at = p_now where r.id = p_request_id;
    perform app.notify(v_request.user_id, 'team_join_declined', 'teams', app.team_note(v_team, p_user), p_now);
  end if;
  return v_team;
end $$;

-- ---------------------------------------------------------------------------
-- Captain tools and invites
-- ---------------------------------------------------------------------------

-- The captain takes a member out (team_removed); not the captain
-- (invalid_argument).
create function app.remove_team_member(p_user uuid, p_team_id uuid, p_member uuid, p_now timestamptz)
returns public.teams
language plpgsql
set search_path = ''
as $$
declare
  v_team public.teams;
begin
  perform app.require_live_player(p_user);
  v_team := app.lock_team(p_user, p_team_id, true);
  if p_member = v_team.captain_id then raise exception 'invalid_argument'; end if;
  delete from public.team_members m where m.team_id = p_team_id and m.user_id = p_member;
  if not found then raise exception 'not_found'; end if;
  perform app.notify(p_member, 'team_removed', 'teams', app.team_note(v_team, p_user), p_now);
  return v_team;
end $$;

-- Invites a live player who is not a member (already_joined) and not the
-- caller (invalid_argument). Inviting again reopens a declined or used
-- invite; while one is open, nothing new is sent.
create function app.invite_to_team(p_user uuid, p_team_id uuid, p_invitee uuid, p_now timestamptz) returns void
language plpgsql
set search_path = ''
as $$
declare
  v_team public.teams;
  v_previous text;
begin
  perform app.require_live_player(p_user);
  v_team := app.lock_team(p_user, p_team_id, true);
  if p_invitee = p_user then raise exception 'invalid_argument'; end if;
  if p_invitee is null
     or not exists (select 1 from public.profiles p where p.id = p_invitee and p.deleted_at is null) then
    raise exception 'not_found';
  end if;
  if exists (select 1 from public.team_members m where m.team_id = p_team_id and m.user_id = p_invitee) then
    raise exception 'already_joined';
  end if;

  select i.status into v_previous from public.team_invites i where i.team_id = p_team_id and i.user_id = p_invitee;
  insert into public.team_invites (team_id, user_id, invited_by, status, created_at)
  values (p_team_id, p_invitee, p_user, 'pending', p_now)
  on conflict (team_id, user_id) do update
    set status = 'pending', invited_by = excluded.invited_by, created_at = excluded.created_at;
  if v_previous is distinct from 'pending' then
    perform app.notify(p_invitee, 'team_invite', 'teams', app.team_note(v_team, p_user), p_now);
  end if;
end $$;

-- The invited player accepts (a member, whatever the join policy) or
-- declines their pending invite (not_found without one).
create function app.respond_team_invite(p_user uuid, p_team_id uuid, p_accept boolean, p_now timestamptz)
returns public.teams
language plpgsql
set search_path = ''
as $$
declare
  v_team public.teams;
begin
  perform app.require_live_player(p_user);
  if p_accept is null then raise exception 'invalid_argument'; end if;
  v_team := app.lock_team(p_user, p_team_id, false);
  perform 1 from public.team_invites i
  where i.team_id = p_team_id and i.user_id = p_user and i.status = 'pending'
  for update;
  if not found then raise exception 'not_found'; end if;

  if p_accept then
    perform app.add_team_member(v_team, p_user, p_now);
  else
    update public.team_invites i set status = 'declined' where i.team_id = p_team_id and i.user_id = p_user;
  end if;
  return v_team;
end $$;

-- Hands the captain role to another member (not_found otherwise); the new
-- captain hears (team_captain). The 5-team limit applies to creating only.
create function app.transfer_captain(p_user uuid, p_team_id uuid, p_member uuid, p_now timestamptz)
returns public.teams
language plpgsql
set search_path = ''
as $$
declare
  v_team public.teams;
begin
  perform app.require_live_player(p_user);
  v_team := app.lock_team(p_user, p_team_id, true);
  if p_member = p_user then raise exception 'invalid_argument'; end if;
  if not exists (select 1 from public.team_members m
                 join public.profiles p on p.id = m.user_id and p.deleted_at is null
                 where m.team_id = p_team_id and m.user_id = p_member) then
    raise exception 'not_found';
  end if;
  update public.teams t set captain_id = p_member where t.id = p_team_id returning * into v_team;
  perform app.notify(p_member, 'team_captain', 'teams', app.team_note(v_team, p_user), p_now);
  return v_team;
end $$;

-- ---------------------------------------------------------------------------
-- JSON
-- ---------------------------------------------------------------------------

-- {"id", "name", "sport_id", "city_id", "description", "join_policy",
-- "color_seed", "captain_id", "member_count", "upcoming_games", "my_status"
-- (captain, member, invited, requested or null), "my_request_id"}.
create function app.team_summary_json(t public.teams, p_user uuid) returns jsonb
language sql
set search_path = ''
as $$
  select jsonb_build_object(
    'id', t.id,
    'name', t.name,
    'sport_id', t.sport_id,
    'city_id', t.city_id,
    'description', t.description,
    'join_policy', t.join_policy,
    'color_seed', t.color_seed,
    'captain_id', t.captain_id,
    'member_count', (select count(*) from public.team_members m where m.team_id = t.id),
    -- Redefined with the team games below.
    'upcoming_games', 0,
    'my_status', case
      when p_user is null then null
      when t.captain_id = p_user then 'captain'
      when exists (select 1 from public.team_members m where m.team_id = t.id and m.user_id = p_user) then 'member'
      when exists (select 1 from public.team_invites i
                   where i.team_id = t.id and i.user_id = p_user and i.status = 'pending') then 'invited'
      when exists (select 1 from public.team_join_requests r
                   where r.team_id = t.id and r.user_id = p_user and r.status = 'pending') then 'requested'
    end,
    'my_request_id', case when p_user is null then null else
      (select r.id from public.team_join_requests r
       where r.team_id = t.id and r.user_id = p_user and r.status = 'pending') end)
$$;

-- The summary plus "members" (captain first, then by joining), "games" and,
-- for the captain only, the pending "requests". A member's level is their
-- player_levels row in the team's sport, rating and provisional come from
-- app.rating_json (null outside rated sports).
create function app.team_json(t public.teams, p_user uuid) returns jsonb
language sql
set search_path = ''
as $$
  select app.team_summary_json(t, p_user)
  || jsonb_build_object(
    'members', coalesce(
      (select jsonb_agg(
                jsonb_build_object(
                  'id', m.user_id,
                  'name', pr.full_name,
                  'level', l.level,
                  'rating', app.rating_json(m.user_id, t.sport_id)->'rating',
                  'provisional', app.rating_json(m.user_id, t.sport_id)->'provisional',
                  'reliability', app.reliability(m.user_id, now()),
                  'captain', m.user_id = t.captain_id)
                || app.deleted_json(m.user_id)
                order by (m.user_id = t.captain_id) desc, m.joined_at, m.user_id)
       from public.team_members m
       join public.profiles pr on pr.id = m.user_id
       left join public.player_levels l on l.user_id = m.user_id and l.sport_id = t.sport_id
       where m.team_id = t.id),
      '[]'::jsonb),
    -- Redefined with the team games below.
    'games', '[]'::jsonb)
  || case when p_user is not null and p_user = t.captain_id then
       jsonb_build_object('requests', coalesce(
         (select jsonb_agg(
                   jsonb_build_object(
                     'id', r.id,
                     'user_id', r.user_id,
                     'name', pr.full_name,
                     'level', l.level,
                     'rating', app.rating_json(r.user_id, t.sport_id)->'rating',
                     'reliability', app.reliability(r.user_id, now()),
                     'created_at', r.created_at)
                   order by r.created_at, r.id)
          from public.team_join_requests r
          join public.profiles pr on pr.id = r.user_id
          left join public.player_levels l on l.user_id = r.user_id and l.sport_id = t.sport_id
          where r.team_id = t.id and r.status = 'pending'),
         '[]'::jsonb))
     else '{}'::jsonb end
$$;

-- The caller's teams (any city) first, then the other teams of the city;
-- each group by member count, largest first, then name. Summaries.
create function app.list_teams(p_user uuid, p_city_id text) returns setof jsonb
language sql
set search_path = ''
as $$
  select app.team_summary_json(t, p_user)
  from public.teams t
  cross join lateral (
    select exists (select 1 from public.team_members m where m.team_id = t.id and m.user_id = p_user) as mine,
           (select count(*) from public.team_members m where m.team_id = t.id) as members) x
  where t.city_id = p_city_id or x.mine
  order by x.mine desc, x.members desc, lower(t.name), t.id
$$;

-- Redefined from 20261127120000_after_game.sql: `teams`, the player's teams
-- [{"id", "name", "sport_id"}] by name.
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
    'sportsmanship', app.sportsmanship(pr.id),
    'teams', coalesce(
      (select jsonb_agg(jsonb_build_object('id', t.id, 'name', t.name, 'sport_id', t.sport_id) order by lower(t.name), t.id)
       from public.team_members m
       join public.teams t on t.id = m.team_id
       where m.user_id = pr.id),
      '[]'::jsonb))
  || case when pr.deleted_at is not null then jsonb_build_object('deleted', true) else '{}'::jsonb end
$$;

-- ---------------------------------------------------------------------------
-- Deleting an account (design §3: delete_account covers every new table)
-- ---------------------------------------------------------------------------

-- Redefined from 20261127120000_after_game.sql: teams (design §7). Each
-- team the player captains goes to the other live member who joined first
-- (team_captain), or is deleted when no one is left; then the player's
-- memberships, requests and invites go. Every team involved is locked first,
-- in id order, so a captain's call on one of them waits or is waited for.
--
-- From 20261127120000_after_game.sql: the player's votes go; their
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
--
-- Lock order (the one the other functions use: booking -> game -> result ->
-- rating rows; team -> its games): the profile; every team involved, in id
-- order; bookings (each with its games), then the booking notes; the games
-- the player hosts or joined, then their game notes; Game Requests;
-- tournament categories and entries; the team hand-over or removal (which
-- writes the removed teams' games); the games the player reported a no-show
-- in, in id order, with their results; the player's results in id order;
-- their rating rows. No booking is locked after a game, and no game after a
-- result.
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
-- What the app calls. Calls that return a team return app.team_json.
-- ---------------------------------------------------------------------------

create function public.create_team(p_team jsonb) returns jsonb
language sql security definer
set search_path = ''
as $$ select app.team_json(app.create_team((select auth.uid()), p_team, now()), (select auth.uid())) $$;

create function public.update_team(p_team_id uuid, p_team jsonb) returns jsonb
language sql security definer
set search_path = ''
as $$ select app.team_json(app.update_team((select auth.uid()), p_team_id, p_team, now()), (select auth.uid())) $$;

create function public.delete_team(p_team_id uuid) returns void
language sql security definer
set search_path = ''
as $$ select app.delete_team((select auth.uid()), p_team_id, now()) $$;

create function public.join_team(p_team_id uuid) returns jsonb
language sql security definer
set search_path = ''
as $$ select app.team_json(app.join_team((select auth.uid()), p_team_id, now()), (select auth.uid())) $$;

create function public.leave_team(p_team_id uuid) returns void
language sql security definer
set search_path = ''
as $$ select app.leave_team((select auth.uid()), p_team_id, now()) $$;

create function public.withdraw_team_request(p_request_id uuid) returns void
language sql security definer
set search_path = ''
as $$ select app.withdraw_team_request((select auth.uid()), p_request_id) $$;

create function public.decide_team_request(p_request_id uuid, p_approve boolean) returns jsonb
language sql security definer
set search_path = ''
as $$ select app.team_json(app.decide_team_request((select auth.uid()), p_request_id, p_approve, now()), (select auth.uid())) $$;

create function public.remove_team_member(p_team_id uuid, p_member uuid) returns jsonb
language sql security definer
set search_path = ''
as $$ select app.team_json(app.remove_team_member((select auth.uid()), p_team_id, p_member, now()), (select auth.uid())) $$;

create function public.invite_to_team(p_team_id uuid, p_invitee uuid) returns void
language sql security definer
set search_path = ''
as $$ select app.invite_to_team((select auth.uid()), p_team_id, p_invitee, now()) $$;

create function public.respond_team_invite(p_team_id uuid, p_accept boolean) returns jsonb
language sql security definer
set search_path = ''
as $$ select app.team_json(app.respond_team_invite((select auth.uid()), p_team_id, p_accept, now()), (select auth.uid())) $$;

create function public.transfer_captain(p_team_id uuid, p_member uuid) returns jsonb
language sql security definer
set search_path = ''
as $$ select app.team_json(app.transfer_captain((select auth.uid()), p_team_id, p_member, now()), (select auth.uid())) $$;

-- null when the team does not exist.
create function public.get_team(p_team_id uuid) returns jsonb
language sql security definer
set search_path = ''
as $$ select app.team_json(t, (select auth.uid())) from public.teams t where t.id = p_team_id $$;

create function public.list_teams(p_city_id text) returns setof jsonb
language sql security definer
set search_path = ''
as $$ select app.list_teams((select auth.uid()), p_city_id) $$;

create function public.admin_delete_team(p_team_id uuid) returns void
language sql security definer
set search_path = ''
as $$ select app.admin_delete_team((select auth.uid()), p_team_id, now()) $$;

revoke all on function
  public.create_team(jsonb),
  public.update_team(uuid, jsonb),
  public.delete_team(uuid),
  public.join_team(uuid),
  public.leave_team(uuid),
  public.withdraw_team_request(uuid),
  public.decide_team_request(uuid, boolean),
  public.remove_team_member(uuid, uuid),
  public.invite_to_team(uuid, uuid),
  public.respond_team_invite(uuid, boolean),
  public.transfer_captain(uuid, uuid),
  public.get_team(uuid),
  public.list_teams(text),
  public.admin_delete_team(uuid)
from public, anon, authenticated;

grant execute on function
  public.create_team(jsonb),
  public.update_team(uuid, jsonb),
  public.delete_team(uuid),
  public.join_team(uuid),
  public.leave_team(uuid),
  public.withdraw_team_request(uuid),
  public.decide_team_request(uuid, boolean),
  public.remove_team_member(uuid, uuid),
  public.invite_to_team(uuid, uuid),
  public.respond_team_invite(uuid, boolean),
  public.transfer_captain(uuid, uuid),
  public.get_team(uuid),
  public.list_teams(text),
  public.admin_delete_team(uuid)
to authenticated, service_role;

-- ===========================================================================
-- Team games (design §7): the captain posts a game for the team; members are
-- told (team_game_posted), see it and join it; it may open to everyone a set
-- number of hours before the start. Stored and shown as invite_only, so a
-- build made before M7 reads a team game as an invite-only game (design §3).
-- ===========================================================================

-- A deleted team leaves its games as ordinary invite-only games. public_from
-- stays on the row, but every rule reads it only while team_id is set
-- (app.team_game_open), so no delete path has to clear it.
alter table public.games
  add column team_id uuid references public.teams (id) on delete set null,
  add column public_from timestamptz;
create index games_team_idx on public.games (team_id) where team_id is not null;

-- The team part of who may see and join a game: a team game is open to the
-- team's members (but not one the host removed from it), and to everyone
-- from public_from on. False for a game without a team (never null). Not
-- stable, like app.can_see_game.
create function app.team_game_open(p_user uuid, g public.games, p_now timestamptz) returns boolean
language sql
set search_path = ''
as $$
  select g.team_id is not null
    and (coalesce(g.public_from <= p_now, false)
         or (p_user is not null
             and exists (select 1 from public.team_members m where m.team_id = g.team_id and m.user_id = p_user)
             and not app.removed_from_game(g.id, p_user)))
$$;

-- Redefined from 20261124110000_games_v2.sql as an overload with a clock:
-- public games, team games open to the player (app.team_game_open), and
-- invite-only ones the player is part of: host, participant, invited
-- (whatever the answer) or has asked to join.
-- Not stable: it must see rows written earlier in the same statement.
create function app.can_see_game(p_user uuid, g public.games, p_now timestamptz) returns boolean
language sql
set search_path = ''
as $$
  select g.visibility = 'public'
    or app.team_game_open(p_user, g, p_now)
    or (p_user is not null and (
      g.host_id = p_user
      or exists (select 1 from public.game_participants p where p.game_id = g.id and p.user_id = p_user)
      or exists (select 1 from public.game_invites i where i.game_id = g.id and i.user_id = p_user)
      or exists (select 1 from public.game_join_requests r where r.game_id = g.id and r.user_id = p_user)))
$$;

-- The form without a clock (public.get_game) asks at now().
create or replace function app.can_see_game(p_user uuid, g public.games) returns boolean
language sql
set search_path = ''
as $$ select app.can_see_game(p_user, g, now()) $$;

-- Redefined from 20261127100000_ratings.sql: `team_id` and
-- `open_hours_before` (null, 12, 24 or 48; only with team_id). A team game:
-- the caller captains the team (not_found for an unknown team, not_allowed
-- otherwise), the team's sport and city are the game's (invalid_argument),
-- the game is stored invite_only whatever was asked, public_from is the
-- start less open_hours_before, and every other member hears
-- (team_game_posted). The team row is locked after the booking.
-- (delete_account takes its player's teams before their bookings; the two
-- meet only when that player creates a team game while their own account is
-- being deleted, and a deadlock there aborts one call, which the client
-- retries.)
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
  v_team_id uuid;
  v_open_hours integer;
  v_team public.teams;
  v_public_from timestamptz;
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
    v_team_id := (p_game->>'team_id')::uuid;
    v_open_hours := (p_game->>'open_hours_before')::integer;
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
     or (v_distance is not null and (v_distance <= 0 or v_distance >= 10000))
     or (v_open_hours is not null and (v_team_id is null or v_open_hours not in (12, 24, 48))) then
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

  if v_team_id is not null then
    v_team := app.lock_team(p_user, v_team_id, true);
    if v_team.sport_id <> v_sport.id or v_team.city_id is distinct from v_city_id then
      raise exception 'invalid_argument';
    end if;
    -- Old builds read a team game as invite-only (design §3).
    v_visibility := 'invite_only';
    v_public_from := lower(v_during) - make_interval(hours => v_open_hours);
  end if;

  insert into public.games (
    sport_id, city_id, venue_id, host_id, booking_id, during, utc_offset_minutes, spots, min_level, max_level,
    min_rating, max_rating,
    price_per_player, note, kind, visibility, meeting_point, meeting_lat, meeting_lng, distance_km, pace, created_at,
    reminded_at, team_id, public_from)
  values (
    v_sport.id, v_city_id, v_venue_id, p_user, v_booking_id, v_during, v_offset, v_spots, v_min, v_max,
    v_min_rating, v_max_rating,
    v_price, v_note, v_kind, v_visibility, v_meeting, v_lat, v_lng, v_distance, v_pace, p_now,
    -- Created inside the reminder window (send_reminders: at most 2 h ahead):
    -- the host just made it, so no reminder follows straight away.
    case when lower(v_during) <= p_now + interval '2 hours' then p_now end,
    v_team_id, v_public_from)
  returning * into v_game;

  insert into public.game_participants (game_id, user_id, joined_at) values (v_game.id, p_user, p_now);

  if v_team_id is not null then
    perform app.notify(m.user_id, 'team_game_posted', 'teams',
      app.game_note(v_game) || jsonb_build_object('team_id', v_team.id, 'team_name', v_team.name), p_now)
    from public.team_members m
    where m.team_id = v_team.id and m.user_id <> p_user;
  end if;
  return v_game;
end $$;

-- Redefined from 20261127100000_ratings.sql: a team game open to the player
-- (app.team_game_open: a member, or anyone from public_from on) is joined as
-- a public game, with the level or rating check; an invite still opens any
-- invite-only game and skips the check.
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
  if v_game.visibility = 'invite_only' and not v_invited and not app.team_game_open(p_user, v_game, p_now) then
    raise exception 'not_found';
  end if;
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

-- Redefined from 20261124110000_games_v2.sql: visibility at p_now
-- (app.can_see_game with a clock), so a team game takes requests from its
-- members, and from everyone once it is open.
create or replace function app.request_to_join(p_user uuid, p_game_id uuid, p_now timestamptz) returns public.game_join_requests
language plpgsql
set search_path = ''
as $$
declare
  v_game public.games;
  v_request public.game_join_requests;
begin
  if p_user is null then raise exception 'not_authenticated'; end if;
  perform app.require_reliable(p_user, p_now);

  select g.* into v_game from public.games g where g.id = p_game_id for update;
  if not found or not app.can_see_game(p_user, v_game, p_now) or v_game.status <> 'open' or lower(v_game.during) <= p_now
     or app.removed_from_game(p_game_id, p_user) then
    raise exception 'not_found';
  end if;
  if exists (select 1 from public.game_participants p where p.game_id = p_game_id and p.user_id = p_user) then
    raise exception 'already_joined';
  end if;
  if exists (select 1 from public.game_join_requests r
             where r.game_id = p_game_id and r.user_id = p_user and r.status = 'pending') then
    raise exception 'already_requested';
  end if;
  if (select count(*) from public.game_participants p where p.game_id = p_game_id) >= v_game.spots then
    raise exception 'full';
  end if;

  begin
    insert into public.game_join_requests (game_id, user_id, created_at)
    values (p_game_id, p_user, p_now)
    returning * into v_request;
  exception when unique_violation then
    raise exception 'already_requested';
  end;

  perform app.notify(v_game.host_id, 'join_request', 'games',
    app.game_note(v_game) || jsonb_build_object(
      'request_id', v_request.id,
      'actor_name', (select p.full_name from public.profiles p where p.id = p_user)),
    p_now);
  return v_request;
end $$;

-- Redefined from 20261126110000_launch.sql: a team game that is open to
-- everyone (public_from passed) is listed like a public game (its city, an
-- active venue, spots left), and the team's members always see its games.
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
       and (g.visibility = 'public' or app.team_game_open(p_user, g, p_now))
       and (g.venue_id is null
            or exists (select 1 from public.venues v where v.id = g.venue_id and v.active))
       and ((select count(*) from public.game_participants p where p.game_id = g.id) < g.spots
            or exists (select 1 from public.game_participants p where p.game_id = g.id and p.user_id = p_user)))
      or (p_user is not null and (
        g.host_id = p_user
        or exists (select 1 from public.game_participants p where p.game_id = g.id and p.user_id = p_user)
        or exists (select 1 from public.game_invites i
                   where i.game_id = g.id and i.user_id = p_user and i.status = 'pending')
        or (exists (select 1 from public.team_members m where m.team_id = g.team_id and m.user_id = p_user)
            -- A member the host removed is closed out, as join_game does.
            and not app.removed_from_game(g.id, p_user)))))
  order by lower(g.during), g.id
$$;

-- Redefined from 20261127120000_after_game.sql: `team` ({"id", "name"}, null
-- for an ordinary game) and `public_from_local` (local time the team game
-- opens to everyone, formatted like starts_local; null when it never does or
-- has no team any more). visibility stays as stored: invite_only for a team
-- game, even once it is open to everyone.
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
    'team', (select jsonb_build_object('id', t.id, 'name', t.name) from public.teams t where t.id = g.team_id),
    'public_from_local', case when g.team_id is not null then app.to_local(g.public_from, g.utc_offset_minutes) end,
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
    -- Someone outside the game sees the score, not a dispute's details.
    'result', (select app.result_json(mr)
                      - case when p_user is not null
                                  and exists (select 1 from public.game_participants p
                                              where p.game_id = g.id and p.user_id = p_user)
                             then '{}'::text[] else array['dispute_reason', 'flagged_no_show'] end
               from public.match_results mr where mr.game_id = g.id))
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

-- Redefined from above: `upcoming_games` counts the team's games that have
-- not started and are not cancelled (all of them, whoever asks).
create or replace function app.team_summary_json(t public.teams, p_user uuid) returns jsonb
language sql
set search_path = ''
as $$
  select jsonb_build_object(
    'id', t.id,
    'name', t.name,
    'sport_id', t.sport_id,
    'city_id', t.city_id,
    'description', t.description,
    'join_policy', t.join_policy,
    'color_seed', t.color_seed,
    'captain_id', t.captain_id,
    'member_count', (select count(*) from public.team_members m where m.team_id = t.id),
    'upcoming_games', (select count(*) from public.games g
                       where g.team_id = t.id and g.status <> 'cancelled' and lower(g.during) > now()),
    'my_status', case
      when p_user is null then null
      when t.captain_id = p_user then 'captain'
      when exists (select 1 from public.team_members m where m.team_id = t.id and m.user_id = p_user) then 'member'
      when exists (select 1 from public.team_invites i
                   where i.team_id = t.id and i.user_id = p_user and i.status = 'pending') then 'invited'
      when exists (select 1 from public.team_join_requests r
                   where r.team_id = t.id and r.user_id = p_user and r.status = 'pending') then 'requested'
    end,
    'my_request_id', case when p_user is null then null else
      (select r.id from public.team_join_requests r
       where r.team_id = t.id and r.user_id = p_user and r.status = 'pending') end)
$$;

-- Redefined from above: `games`, the team's games that have not started and
-- are not cancelled, soonest first, as app.game_json; only those the caller
-- may see (public.get_team answers anyone signed in).
create or replace function app.team_json(t public.teams, p_user uuid) returns jsonb
language sql
set search_path = ''
as $$
  select app.team_summary_json(t, p_user)
  || jsonb_build_object(
    'members', coalesce(
      (select jsonb_agg(
                jsonb_build_object(
                  'id', m.user_id,
                  'name', pr.full_name,
                  'level', l.level,
                  'rating', app.rating_json(m.user_id, t.sport_id)->'rating',
                  'provisional', app.rating_json(m.user_id, t.sport_id)->'provisional',
                  'reliability', app.reliability(m.user_id, now()),
                  'captain', m.user_id = t.captain_id)
                || app.deleted_json(m.user_id)
                order by (m.user_id = t.captain_id) desc, m.joined_at, m.user_id)
       from public.team_members m
       join public.profiles pr on pr.id = m.user_id
       left join public.player_levels l on l.user_id = m.user_id and l.sport_id = t.sport_id
       where m.team_id = t.id),
      '[]'::jsonb),
    'games', coalesce(
      (select jsonb_agg(app.game_json(g, p_user) order by lower(g.during), g.id)
       from public.games g
       where g.team_id = t.id and g.status <> 'cancelled' and lower(g.during) > now()
         and app.can_see_game(p_user, g, now())),
      '[]'::jsonb))
  || case when p_user is not null and p_user = t.captain_id then
       jsonb_build_object('requests', coalesce(
         (select jsonb_agg(
                   jsonb_build_object(
                     'id', r.id,
                     'user_id', r.user_id,
                     'name', pr.full_name,
                     'level', l.level,
                     'rating', app.rating_json(r.user_id, t.sport_id)->'rating',
                     'provisional', app.rating_json(r.user_id, t.sport_id)->'provisional',
                     'reliability', app.reliability(r.user_id, now()),
                     'created_at', r.created_at)
                   order by r.created_at, r.id)
          from public.team_join_requests r
          join public.profiles pr on pr.id = r.user_id
          left join public.player_levels l on l.user_id = r.user_id and l.sport_id = t.sport_id
          where r.team_id = t.id and r.status = 'pending'),
         '[]'::jsonb))
     else '{}'::jsonb end
$$;

-- Redefined from 20261127120000_after_game.sql: `teams`, the summaries of
-- every team (as app.team_summary_json for the admin), newest first, at most
-- 200, for the removal list.
create or replace function app.admin_review(p_user uuid) returns jsonb
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
    ),
    all_teams as (
      select t.* from public.teams t order by t.created_at desc, t.id desc limit 200
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
      'teams', coalesce(
        (select jsonb_agg(app.team_summary_json(t, p_user) order by t.created_at desc, t.id desc) from all_teams t),
        '[]'::jsonb),
      'counts', jsonb_build_object(
        'disputes', (select count(*) from disputes),
        'reports', (select count(*) from reports)))
  );
end $$;
