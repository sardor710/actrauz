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
