-- Milestone 7c: teams — creating and editing a team, joining (open or by
-- the captain's approval), invites, leaving, removing members, handing over
-- the captain role, deleting, admin removal, the team JSON and lists
-- (design 2026-11-27-actra-m7-competitive §7). Team games come later.
--
-- Additive: new server-only tables and functions. app.player_json and
-- app.delete_account are copied from 20261127120000_after_game.sql; every
-- signature stays.
--
-- Lock order: every function that changes a team locks its row first
-- (for update), then the member, request and invite rows. Profiles are only
-- read, never locked here.

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
  -- limit holds (the same lock delete_account takes).
  perform 1 from public.profiles p where p.id = p_user for no key update;
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
    -- Team games come with the next migration.
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
    -- Team games come with the next migration.
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

  -- Teams (design §7). They touch only team rows and notifications.
  perform 1 from public.teams t
  where t.captain_id = p_user
     or t.id in (select m.team_id from public.team_members m where m.user_id = p_user)
     or t.id in (select r.team_id from public.team_join_requests r where r.user_id = p_user and r.status = 'pending')
     or t.id in (select i.team_id from public.team_invites i where i.user_id = p_user and i.status = 'pending')
  order by t.id
  for update;
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
