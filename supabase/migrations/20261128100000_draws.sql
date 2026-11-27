-- Tournament brackets (Milestone 8a, part 1): organisers, draws and seeding
-- (design §5, §6, §14a).
--
-- Additive only: new tables, one trigger on tournament_registrations and new
-- functions. As elsewhere, the rules live in the private `app` schema and
-- take the acting user and the clock; the `public` wrappers pass auth.uid()
-- and now().
--
-- Lock order, everywhere (extends 20261125100000_tournaments.sql):
-- pg_advisory_xact_lock(hashtext('tournament:' || tournament_id)) first, then
-- the category row, then its tournament_draws row, then matches in (stage,
-- round, position) order, then registration rows, then bookings, then
-- match_results, then the tournament row last. Every draw call takes the
-- category row lock before touching the draw, so it is serialised with
-- every registration path (which already takes the category lock first);
-- the trigger below writes tournament_draws only under that lock.
--
-- A draw's matches are always rebuilt as a whole from its stored entries
-- (seeds and groups) by app.build_matches: making, swapping and redoing a
-- draw all go through it.

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------

create table public.tournament_organizers (
  tournament_id uuid not null references public.tournaments (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  added_by uuid references public.profiles (id) on delete set null,
  added_at timestamptz not null default now(),
  primary key (tournament_id, user_id)
);
create index tournament_organizers_user_idx on public.tournament_organizers (user_id);

-- One draw per category. `locked` becomes true at the first publish and
-- stays (a redo keeps the category locked, §14a.7). `outdated`: a draft
-- whose registered entries changed after it was made (§14a.7).
create table public.tournament_draws (
  category_id uuid primary key references public.tournament_categories (id) on delete cascade,
  format text not null check (format in ('knockout', 'groups')),
  group_size integer check (group_size in (3, 4)),
  advance integer check (advance in (1, 2)),
  status text not null default 'draft' check (status in ('draft', 'published')),
  locked boolean not null default false,
  outdated boolean not null default false,
  made_by uuid references public.profiles (id) on delete set null,
  made_at timestamptz not null default now(),
  published_at timestamptz,
  -- Set by score entry (Task 3): after it the draw is final.
  first_score_at timestamptz,
  constraint tournament_draws_shape check (
    (format = 'knockout' and group_size is null and advance is null)
    or (format = 'groups' and group_size is not null and advance is not null))
);

create table public.tournament_groups (
  id uuid primary key default gen_random_uuid(),
  category_id uuid not null references public.tournament_categories (id) on delete cascade,
  label text not null,
  sort_order integer not null,
  unique (category_id, label)
);

-- The entries of a draw: the category's registered entries when it was made.
-- Seeds are unique per category; checked at the end of each statement, so a
-- swap can exchange two seeds in one update.
create table public.tournament_draw_entries (
  registration_id uuid primary key references public.tournament_registrations (id) on delete cascade,
  category_id uuid not null references public.tournament_categories (id) on delete cascade,
  seed integer not null check (seed >= 1),
  strength numeric not null,
  group_id uuid references public.tournament_groups (id) on delete cascade,
  -- Set by the organiser's withdraw (Task 3).
  withdrawn_at timestamptz,
  constraint tournament_draw_entries_seed unique (category_id, seed) deferrable initially immediate
);
create index tournament_draw_entries_group_idx on public.tournament_draw_entries (group_id);

-- One match. Sides are registrations; an empty side (`a_empty`/`b_empty`) is
-- a bracket slot nobody fills (a bye). Later knockout rounds exist from the
-- start as `waiting` rows. Registrations are never hard-deleted by the
-- product; side_a/side_b only go null if a profile is.
create table public.tournament_matches (
  id uuid primary key default gen_random_uuid(),
  category_id uuid not null references public.tournament_categories (id) on delete cascade,
  stage text not null check (stage in ('group', 'knockout')),
  group_id uuid references public.tournament_groups (id) on delete cascade,
  round integer not null check (round >= 1),
  position integer not null check (position >= 1),
  side_a uuid references public.tournament_registrations (id) on delete set null,
  side_b uuid references public.tournament_registrations (id) on delete set null,
  a_empty boolean not null default false,
  b_empty boolean not null default false,
  status text not null default 'waiting' check (status in ('waiting', 'ready', 'done')),
  outcome text check (outcome in ('played', 'walkover', 'retired', 'decider', 'bye', 'none')),
  winner text check (winner in ('a', 'b', 'draw')),
  sets jsonb,
  court_id uuid references public.courts (id) on delete set null,
  starts_at timestamptz,
  place_note text check (char_length(place_note) <= 100),
  scored_by uuid references public.profiles (id) on delete set null,
  scored_at timestamptz,
  constraint tournament_matches_slot unique (category_id, stage, group_id, round, position),
  constraint tournament_matches_stage_group check ((stage = 'group') = (group_id is not null))
);
-- The unique constraint above treats a null group_id as distinct, so it does
-- not cover knockout rows; this does.
create unique index tournament_matches_knockout_slot on public.tournament_matches (category_id, round, position)
  where stage = 'knockout';
create index tournament_matches_side_a_idx on public.tournament_matches (side_a);
create index tournament_matches_side_b_idx on public.tournament_matches (side_b);
create index tournament_matches_court_idx on public.tournament_matches (court_id);

-- No client access at all: everything goes through the functions.
alter table public.tournament_organizers enable row level security;
alter table public.tournament_draws enable row level security;
alter table public.tournament_groups enable row level security;
alter table public.tournament_draw_entries enable row level security;
alter table public.tournament_matches enable row level security;
revoke all on table public.tournament_organizers, public.tournament_draws, public.tournament_groups,
  public.tournament_draw_entries, public.tournament_matches
  from public, anon, authenticated;
grant all on table public.tournament_organizers, public.tournament_draws, public.tournament_groups,
  public.tournament_draw_entries, public.tournament_matches
  to service_role;

-- ---------------------------------------------------------------------------
-- Organisers
-- ---------------------------------------------------------------------------

-- Never null: false for a missing user or tournament (an admin passes either way).
create function app.is_organizer(p_user uuid, p_tournament_id uuid) returns boolean
language sql stable
set search_path = ''
as $$
  select p_user is not null and (
    app.is_admin(p_user)
    or exists (select 1 from public.tournament_organizers o where o.tournament_id = p_tournament_id and o.user_id = p_user))
$$;

create function app.require_organizer(p_user uuid, p_tournament_id uuid) returns void
language plpgsql stable
set search_path = ''
as $$
begin
  if not app.is_organizer(p_user, p_tournament_id) then raise exception 'not_allowed'; end if;
end $$;

-- [{"id", "name"}] by name.
create function app.organizers_json(p_tournament_id uuid) returns jsonb
language sql
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'name', p.full_name) order by p.full_name, p.id), '[]'::jsonb)
  from public.tournament_organizers o
  join public.profiles p on p.id = o.user_id
  where o.tournament_id = p_tournament_id
$$;

-- What every tournament notification of this milestone carries besides its
-- own keys (category_id is null when there is no category).
create function app.tournament_note(p_tournament_id uuid, p_category_id uuid) returns jsonb
language sql stable
set search_path = ''
as $$
  select jsonb_build_object(
    'tournament_id', t.id,
    'category_id', p_category_id,
    'title', jsonb_build_object('uz', t.title_uz, 'ru', t.title_ru, 'en', t.title_en),
    'category_name', (select jsonb_build_object('uz', c.name_uz, 'ru', c.name_ru, 'en', c.name_en)
                      from public.tournament_categories c where c.id = p_category_id))
  from public.tournaments t
  where t.id = p_tournament_id
$$;

-- Adds or removes an organiser. The person is told when the list changes.
create function app.admin_set_organizer(p_user uuid, p_tournament_id uuid, p_target uuid, p_add boolean, p_now timestamptz)
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_changed integer;
begin
  perform app.require_admin(p_user);
  if p_add is null then raise exception 'invalid_argument'; end if;
  if not exists (select 1 from public.tournaments t where t.id = p_tournament_id) then raise exception 'not_found'; end if;
  if not exists (select 1 from public.profiles p where p.id = p_target) then raise exception 'not_found'; end if;

  if p_add then
    insert into public.tournament_organizers (tournament_id, user_id, added_by, added_at)
    values (p_tournament_id, p_target, p_user, p_now)
    on conflict do nothing;
  else
    delete from public.tournament_organizers o where o.tournament_id = p_tournament_id and o.user_id = p_target;
  end if;
  get diagnostics v_changed = row_count;

  if v_changed > 0 then
    perform app.notify(p_target, case when p_add then 'organizer_added' else 'organizer_removed' end, 'tournaments',
      app.tournament_note(p_tournament_id, null), p_now);
  end if;
  perform app.audit(p_user, case when p_add then 'add_organizer' else 'remove_organizer' end, 'tournament',
    p_tournament_id::text, null, jsonb_build_object('user_id', p_target, 'add', p_add), p_now);
end $$;

-- The organiser list, for the admin's tournament editor.
create function app.tournament_organizers(p_user uuid, p_tournament_id uuid) returns jsonb
language plpgsql
set search_path = ''
as $$
begin
  perform app.require_admin(p_user);
  if not exists (select 1 from public.tournaments t where t.id = p_tournament_id) then raise exception 'not_found'; end if;
  return app.organizers_json(p_tournament_id);
end $$;

-- Active tournaments the player is a named organiser of, earliest first.
create function app.my_organized_tournaments(p_user uuid) returns jsonb
language sql
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
      'id', t.id,
      'title_uz', t.title_uz,
      'title_ru', t.title_ru,
      'title_en', t.title_en,
      'starts_on', t.starts_on,
      'ends_on', t.ends_on,
      'city_id', t.city_id,
      'sport_id', t.sport_id) order by t.starts_on, t.id), '[]'::jsonb)
  from public.tournaments t
  join public.tournament_organizers o on o.tournament_id = t.id and o.user_id = p_user
  where t.active
$$;

-- The entry list as the admin participants list shows it (names, phones),
-- for organisers and admins.
create function app.organizer_entries(p_user uuid, p_tournament_id uuid) returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  v_result jsonb;
begin
  perform app.require_organizer(p_user, p_tournament_id);
  if not exists (select 1 from public.tournaments t where t.id = p_tournament_id) then raise exception 'not_found'; end if;
  select coalesce(jsonb_agg(x.j order by x.ord), '[]'::jsonb) into v_result
  from (
    select app.admin_registration_json(r) as j,
      row_number() over (order by c.sort_order, c.created_at, c.id,
        case r.status when 'registered' then 0 when 'offered' then 1 when 'pending_partner' then 2 when 'waitlisted' then 3 else 4 end,
        r.waitlist_position nulls first, r.created_at, r.id) as ord
    from public.tournament_registrations r
    join public.tournament_categories c on c.id = r.category_id
    where c.tournament_id = p_tournament_id
  ) x;
  return v_result;
end $$;

-- ---------------------------------------------------------------------------
-- Draw helpers
-- ---------------------------------------------------------------------------

-- The players of an entry: the registrant, then the partner.
create function app.entry_players(p_registration_id uuid) returns uuid[]
language sql stable
set search_path = ''
as $$
  select array_remove(array[r.user_id, r.partner_id], null)
  from public.tournament_registrations r where r.id = p_registration_id
$$;

-- Seeding strength (§6.3): a rated sport's effective rating, otherwise the
-- player's level (0 without one); pairs: the average of the two.
create function app.entry_strength(r public.tournament_registrations, p_sport_id text) returns numeric
language plpgsql
set search_path = ''
as $$
declare
  v_rated boolean := app.is_rated_sport(p_sport_id);
  v_total numeric := 0;
  v_count integer := 0;
  v_player uuid;
begin
  foreach v_player in array array_remove(array[r.user_id, r.partner_id], null) loop
    v_total := v_total + case when v_rated then app.effective_rating(v_player, p_sport_id)
      else coalesce((select l.level from public.player_levels l where l.user_id = v_player and l.sport_id = p_sport_id), 0) end;
    v_count := v_count + 1;
  end loop;
  return round(v_total / greatest(v_count, 1), 2);
end $$;

-- The smallest power of two at or above p_n (at least 2).
create function app.bracket_size(p_n integer) returns integer
language plpgsql immutable
set search_path = ''
as $$
declare
  v_size integer := 2;
begin
  while v_size < p_n loop v_size := v_size * 2; end loop;
  return v_size;
end $$;

-- Seeds in bracket slot order: [1, 2], and each doubling maps every s to
-- [s, 2*len + 1 - s] (4 -> [1,4,2,3], 8 -> [1,8,4,5,2,7,3,6]).
create function app.seed_order(p_size integer) returns integer[]
language plpgsql immutable
set search_path = ''
as $$
declare
  v_order integer[] := array[1, 2];
  v_next integer[];
  v_len integer;
  v_seed integer;
begin
  while cardinality(v_order) < p_size loop
    v_len := cardinality(v_order);
    v_next := '{}';
    foreach v_seed in array v_order loop
      v_next := v_next || array[v_seed, 2 * v_len + 1 - v_seed];
    end loop;
    v_order := v_next;
  end loop;
  return v_order;
end $$;

-- Group labels: A..Z, then AA, AB, ...
create function app.group_label(p_index integer) returns text
language sql immutable
set search_path = ''
as $$
  select case when p_index <= 26 then chr(64 + p_index)
    else chr(64 + (p_index - 1) / 26) || chr(65 + (p_index - 1) % 26) end
$$;

-- The knockout rows of a category: rounds 1..log2(S) for p_count entries.
-- p_regs[seed] is the entry of each seed (a knockout draw): round 1 is
-- filled, a match with one empty side is a bye whose winner moves on, and
-- matches with both sides known are ready. p_regs null (the knockout after
-- groups): every row waits for its qualifiers; slots whose qualifier seed is
-- beyond p_count are only marked empty (Task 3 settles them as byes).
create function app.build_knockout(p_category_id uuid, p_count integer, p_regs uuid[]) returns void
language plpgsql
set search_path = ''
as $$
declare
  v_size integer := app.bracket_size(p_count);
  v_order integer[] := app.seed_order(v_size);
  v_rounds integer := 0;
  v_matches integer;
  v_seed_a integer;
  v_seed_b integer;
  v_winner uuid;
begin
  while (1 << v_rounds) < v_size loop v_rounds := v_rounds + 1; end loop;
  for r in 1..v_rounds loop
    v_matches := v_size >> r;
    for p in 1..v_matches loop
      insert into public.tournament_matches (category_id, stage, group_id, round, position, status)
      values (p_category_id, 'knockout', null, r, p, 'waiting');
    end loop;
  end loop;

  for p in 1..(v_size / 2) loop
    v_seed_a := v_order[2 * p - 1];
    v_seed_b := v_order[2 * p];
    update public.tournament_matches m
    set a_empty = v_seed_a > p_count,
        b_empty = v_seed_b > p_count,
        side_a = case when p_regs is not null and v_seed_a <= p_count then p_regs[v_seed_a] end,
        side_b = case when p_regs is not null and v_seed_b <= p_count then p_regs[v_seed_b] end
    where m.category_id = p_category_id and m.stage = 'knockout' and m.round = 1 and m.position = p;

    -- A bye: done at once, its winner placed in the next match.
    if p_regs is not null and (v_seed_a > p_count or v_seed_b > p_count) then
      v_winner := p_regs[least(v_seed_a, v_seed_b)];
      update public.tournament_matches m
      set status = 'done', outcome = 'bye', winner = case when v_seed_b > p_count then 'a' else 'b' end
      where m.category_id = p_category_id and m.stage = 'knockout' and m.round = 1 and m.position = p;
      if v_rounds > 1 then
        update public.tournament_matches m
        set side_a = case when p % 2 = 1 then v_winner else m.side_a end,
            side_b = case when p % 2 = 0 then v_winner else m.side_b end
        where m.category_id = p_category_id and m.stage = 'knockout' and m.round = 2 and m.position = (p + 1) / 2;
      end if;
    end if;
  end loop;

  update public.tournament_matches m set status = 'ready'
  where m.category_id = p_category_id and m.stage = 'knockout' and m.status = 'waiting'
    and m.side_a is not null and m.side_b is not null;
end $$;

-- Rebuilds every match of the category from its draw and draw entries.
create function app.build_matches(p_category_id uuid) returns void
language plpgsql
set search_path = ''
as $$
declare
  v_draw public.tournament_draws;
  v_regs uuid[];
  v_group public.tournament_groups;
  v_members uuid[];
  v_size integer;
  v_position integer;
  v_groups integer;
begin
  select d.* into v_draw from public.tournament_draws d where d.category_id = p_category_id;
  delete from public.tournament_matches m where m.category_id = p_category_id;

  if v_draw.format = 'knockout' then
    select array_agg(e.registration_id order by e.seed) into v_regs
    from public.tournament_draw_entries e where e.category_id = p_category_id;
    perform app.build_knockout(p_category_id, cardinality(v_regs), v_regs);
    return;
  end if;

  -- Groups: a round robin per group by the circle method (a dummy, null,
  -- for an odd size: whoever meets it sits the round out).
  for v_group in
    select g.* from public.tournament_groups g where g.category_id = p_category_id order by g.sort_order
  loop
    select array_agg(e.registration_id order by e.seed) into v_members
    from public.tournament_draw_entries e where e.group_id = v_group.id;
    if v_members is null then continue; end if;
    if cardinality(v_members) % 2 = 1 then v_members := array_append(v_members, null::uuid); end if;
    v_size := cardinality(v_members);
    for r in 1..(v_size - 1) loop
      v_position := 0;
      for i in 1..(v_size / 2) loop
        if v_members[i] is not null and v_members[v_size + 1 - i] is not null then
          v_position := v_position + 1;
          insert into public.tournament_matches (category_id, stage, group_id, round, position, side_a, side_b, status)
          values (p_category_id, 'group', v_group.id, r, v_position, v_members[i], v_members[v_size + 1 - i], 'ready');
        end if;
      end loop;
      -- Keep the first, rotate the rest one place.
      v_members := array[v_members[1], v_members[v_size]] || v_members[2:v_size - 1];
    end loop;
  end loop;

  -- The knockout after the groups: Q qualifiers; one group with one
  -- advancing has none (the group winner wins the category).
  select count(*)::integer into v_groups from public.tournament_groups g where g.category_id = p_category_id;
  if v_groups * v_draw.advance >= 2 then
    perform app.build_knockout(p_category_id, v_groups * v_draw.advance, null);
  end if;
end $$;

-- Makes the draw's entries, groups and matches afresh from the category's
-- registered entries, with the format already on its tournament_draws row.
create function app.build_draw(p_category_id uuid) returns void
language plpgsql
set search_path = ''
as $$
declare
  v_draw public.tournament_draws;
  v_sport text;
  v_n integer;
  v_groups integer;
begin
  select d.* into v_draw from public.tournament_draws d where d.category_id = p_category_id;
  select t.sport_id into v_sport from public.tournament_categories c
  join public.tournaments t on t.id = c.tournament_id where c.id = p_category_id;

  select count(*)::integer into v_n from public.tournament_registrations r
  where r.category_id = p_category_id and r.status = 'registered';
  if v_n < 2 or (v_draw.format = 'groups' and v_n < 3) then raise exception 'too_few_entries'; end if;

  delete from public.tournament_matches m where m.category_id = p_category_id;
  delete from public.tournament_draw_entries e where e.category_id = p_category_id;
  delete from public.tournament_groups g where g.category_id = p_category_id;

  -- Strongest first; ties broken at random.
  insert into public.tournament_draw_entries (registration_id, category_id, seed, strength)
  select x.id, p_category_id, row_number() over (order by x.strength desc, random())::integer, x.strength
  from (
    select r.id, app.entry_strength(r, v_sport) as strength
    from public.tournament_registrations r
    where r.category_id = p_category_id and r.status = 'registered'
  ) x;

  if v_draw.format = 'groups' then
    -- As many groups as the size asks for, fewer while the smallest would
    -- have under three; sizes then differ by at most one.
    v_groups := ceil(v_n::numeric / v_draw.group_size)::integer;
    while v_groups > 1 and v_n / v_groups < 3 loop v_groups := v_groups - 1; end loop;

    insert into public.tournament_groups (category_id, label, sort_order)
    select p_category_id, app.group_label(i), i from generate_series(1, v_groups) i;

    -- Snake: seeds 1..G to A..G, then G..A, and so on.
    update public.tournament_draw_entries e
    set group_id = g.id
    from public.tournament_groups g
    where e.category_id = p_category_id and g.category_id = p_category_id
      and g.sort_order = case when ((e.seed - 1) / v_groups) % 2 = 0
                           then (e.seed - 1) % v_groups + 1
                           else v_groups - (e.seed - 1) % v_groups end;
  end if;

  perform app.build_matches(p_category_id);
end $$;

-- For the draw calls: the organiser check on the category's tournament, then
-- the locks in order (tournament advisory lock, category row, draw row).
-- Returns the draw row, or a row of nulls when there is none.
create function app.lock_draw(p_user uuid, p_category_id uuid) returns public.tournament_draws
language plpgsql
set search_path = ''
as $$
declare
  v_tournament_id uuid;
  v_draw public.tournament_draws;
begin
  select c.tournament_id into v_tournament_id from public.tournament_categories c where c.id = p_category_id;
  if not found then raise exception 'not_found'; end if;
  perform app.require_organizer(p_user, v_tournament_id);
  perform pg_advisory_xact_lock(hashtext('tournament:' || v_tournament_id::text));
  perform 1 from public.tournament_categories c where c.id = p_category_id for update;
  select d.* into v_draw from public.tournament_draws d where d.category_id = p_category_id for update;
  return v_draw;
end $$;

-- Every player of the draw's entries.
create function app.draw_players(p_category_id uuid) returns uuid[]
language sql
set search_path = ''
as $$
  select coalesce(array_agg(distinct p), '{}')
  from public.tournament_draw_entries e
  cross join lateral unnest(app.entry_players(e.registration_id)) p
  where e.category_id = p_category_id
$$;

-- ---------------------------------------------------------------------------
-- JSON. Not stable: each must see rows written earlier in the same call.
-- ---------------------------------------------------------------------------

-- Sides are registration ids; starts_at is venue wall-clock time, as in
-- game JSON.
create function app.match_json(m public.tournament_matches) returns jsonb
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
    'starts_at', case when m.starts_at is not null then
      (select app.to_local(m.starts_at, app.tournament_offset(t))
       from public.tournament_categories c join public.tournaments t on t.id = c.tournament_id
       where c.id = m.category_id) end,
    'place_note', m.place_note)
$$;

-- The category's draw; null when there is none, or for anyone but an
-- organiser while it is a draft.
create function app.draw_json(p_category_id uuid, p_user uuid) returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  v_draw public.tournament_draws;
  v_tournament_id uuid;
begin
  select d.* into v_draw from public.tournament_draws d where d.category_id = p_category_id;
  if not found then return null; end if;
  select c.tournament_id into v_tournament_id from public.tournament_categories c where c.id = p_category_id;
  if v_draw.status <> 'published' and not app.is_organizer(p_user, v_tournament_id) then return null; end if;

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
      select coalesce(jsonb_agg(jsonb_build_object('id', g.id, 'label', g.label) order by g.sort_order), '[]'::jsonb)
      from public.tournament_groups g where g.category_id = p_category_id),
    'matches', (
      select coalesce(jsonb_agg(app.match_json(m) order by m.stage, m.round, g.sort_order nulls first, m.position), '[]'::jsonb)
      from public.tournament_matches m
      left join public.tournament_groups g on g.id = m.group_id
      where m.category_id = p_category_id));
end $$;

-- {"organizer", "draws": [draw_json ...]}: the draws the caller may see, in
-- category order. A hidden tournament exists only for its organisers.
create function app.tournament_bracket(p_user uuid, p_tournament_id uuid) returns jsonb
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
      where x.j is not null));
end $$;

-- ---------------------------------------------------------------------------
-- Draw calls (organisers and admins)
-- ---------------------------------------------------------------------------

-- Makes, or makes again, the category's draft draw from its registered
-- entries. Refused once published (a redo is the way back).
create function app.make_draw(
  p_user uuid, p_category_id uuid, p_format text, p_group_size integer, p_advance integer, p_now timestamptz)
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_draw public.tournament_draws;
begin
  v_draw := app.lock_draw(p_user, p_category_id);
  if v_draw.status = 'published' then raise exception 'draw_published'; end if;
  if p_format = 'knockout' then
    p_group_size := null;
    p_advance := null;
  elsif p_format = 'groups' then
    if p_group_size is null or p_group_size not in (3, 4) or p_advance is null or p_advance not in (1, 2) then
      raise exception 'invalid_argument';
    end if;
  else
    raise exception 'invalid_argument';
  end if;

  -- Updated in place, so a category locked by an earlier publish stays locked.
  insert into public.tournament_draws (category_id, format, group_size, advance, status, outdated, made_by, made_at)
  values (p_category_id, p_format, p_group_size, p_advance, 'draft', false, p_user, p_now)
  on conflict (category_id) do update
  set format = excluded.format, group_size = excluded.group_size, advance = excluded.advance,
      status = 'draft', outdated = false, made_by = excluded.made_by, made_at = excluded.made_at,
      first_score_at = null;

  perform app.build_draw(p_category_id);
  perform app.audit(p_user, 'make_draw', 'tournament_category', p_category_id::text, null,
    jsonb_build_object('format', p_format, 'group_size', p_group_size, 'advance', p_advance), p_now);
end $$;

-- Swaps two entries of a draft: their seeds (knockout) or their groups
-- (groups), then rebuilds the matches.
create function app.swap_draw_entries(
  p_user uuid, p_category_id uuid, p_registration_a uuid, p_registration_b uuid, p_now timestamptz)
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_draw public.tournament_draws;
  v_a public.tournament_draw_entries;
  v_b public.tournament_draw_entries;
begin
  v_draw := app.lock_draw(p_user, p_category_id);
  if v_draw.category_id is null then raise exception 'not_found'; end if;
  if v_draw.status = 'published' then raise exception 'draw_published'; end if;
  if p_registration_a is null or p_registration_b is null or p_registration_a = p_registration_b then
    raise exception 'invalid_argument';
  end if;
  select e.* into v_a from public.tournament_draw_entries e
  where e.registration_id = p_registration_a and e.category_id = p_category_id;
  if not found then raise exception 'not_found'; end if;
  select e.* into v_b from public.tournament_draw_entries e
  where e.registration_id = p_registration_b and e.category_id = p_category_id;
  if not found then raise exception 'not_found'; end if;

  if v_draw.format = 'knockout' then
    update public.tournament_draw_entries e
    set seed = case when e.registration_id = v_a.registration_id then v_b.seed else v_a.seed end
    where e.registration_id in (v_a.registration_id, v_b.registration_id);
  else
    update public.tournament_draw_entries e
    set group_id = case when e.registration_id = v_a.registration_id then v_b.group_id else v_a.group_id end
    where e.registration_id in (v_a.registration_id, v_b.registration_id);
  end if;

  perform app.build_matches(p_category_id);
  perform app.audit(p_user, 'swap_draw_entries', 'tournament_category', p_category_id::text, null,
    jsonb_build_object('registration_a', p_registration_a, 'registration_b', p_registration_b), p_now);
end $$;

-- Shows the draft to everyone and locks the category's entries for good.
-- Open waitlist offers and the waitlist lapse (§14a.7).
create function app.publish_draw(p_user uuid, p_category_id uuid, p_now timestamptz) returns void
language plpgsql
set search_path = ''
as $$
declare
  v_draw public.tournament_draws;
  v_tournament_id uuid;
  v_reg public.tournament_registrations;
  v_previous text;
  v_player uuid;
begin
  v_draw := app.lock_draw(p_user, p_category_id);
  if v_draw.category_id is null then raise exception 'not_found'; end if;
  if v_draw.status = 'published' then raise exception 'draw_published'; end if;
  if v_draw.outdated then raise exception 'draw_outdated'; end if;
  select c.tournament_id into v_tournament_id from public.tournament_categories c where c.id = p_category_id;

  update public.tournament_draws d set status = 'published', locked = true, published_at = p_now
  where d.category_id = p_category_id;

  -- The lock trigger refuses these status changes; let them through, then
  -- put the flag back so nothing later in the transaction slips past it.
  v_previous := current_setting('actra.draw_override', true);
  perform set_config('actra.draw_override', 'on', true);
  for v_reg in
    update public.tournament_registrations r set status = 'lapsed', decided_at = p_now
    where r.category_id = p_category_id and r.status in ('offered', 'waitlisted')
    returning r.*
  loop
    foreach v_player in array app.entry_players(v_reg.id) loop
      perform app.notify(v_player, 'waitlist_closed', 'tournaments',
        app.tournament_note(v_tournament_id, p_category_id) || jsonb_build_object('registration_id', v_reg.id), p_now);
    end loop;
  end loop;
  perform set_config('actra.draw_override', coalesce(v_previous, ''), true);

  foreach v_player in array app.draw_players(p_category_id) loop
    perform app.notify(v_player, 'draw_published', 'tournaments', app.tournament_note(v_tournament_id, p_category_id), p_now);
  end loop;

  perform app.audit(p_user, 'publish_draw', 'tournament_category', p_category_id::text, null, null, p_now);
  -- Offered entries counted toward the summary. The tournament row last.
  perform app.sync_tournament_summary(v_tournament_id);
end $$;

-- Throws a published draw away and makes it again, as a draft with the same
-- format, from the entries still registered. Not after the first score.
-- The category stays locked. Deleting the matches releases their calendar
-- blocks (Task 2's cascade).
create function app.redo_draw(p_user uuid, p_category_id uuid, p_now timestamptz) returns void
language plpgsql
set search_path = ''
as $$
declare
  v_draw public.tournament_draws;
  v_tournament_id uuid;
  v_players uuid[];
  v_player uuid;
begin
  v_draw := app.lock_draw(p_user, p_category_id);
  if v_draw.category_id is null then raise exception 'not_found'; end if;
  if v_draw.status <> 'published' then raise exception 'invalid_argument'; end if;
  if v_draw.first_score_at is not null then raise exception 'draw_final'; end if;
  select c.tournament_id into v_tournament_id from public.tournament_categories c where c.id = p_category_id;

  v_players := app.draw_players(p_category_id);
  update public.tournament_draws d
  set status = 'draft', outdated = false, made_by = p_user, made_at = p_now, published_at = null
  where d.category_id = p_category_id;
  perform app.build_draw(p_category_id);

  for v_player in select distinct x from unnest(v_players || app.draw_players(p_category_id)) x loop
    perform app.notify(v_player, 'draw_redone', 'tournaments', app.tournament_note(v_tournament_id, p_category_id), p_now);
  end loop;
  perform app.audit(p_user, 'redo_draw', 'tournament_category', p_category_id::text, null, null, p_now);
end $$;

-- ---------------------------------------------------------------------------
-- Entries and the draw: out-of-date drafts and the entry lock
-- ---------------------------------------------------------------------------

-- After a change of a registration's status or category:
-- * a draft whose registered entries change (an entry registered, no longer
--   registered, or moved while registered) is marked outdated (§14a.7);
-- * in a locked category (published once), refused with draw_published:
--   a new live entry; a status change from or to registered, or to
--   pending_partner, waitlisted or offered; moving a registered entry out or
--   a live entry in (§6.4). Expiring invites and offers to dead statuses and
--   paid_at changes stay allowed. The organiser's withdraw (Task 3) sets
--   actra.draw_override = 'on' locally to pass; drafts are still marked.
create function app.registration_draw_guard() returns trigger
language plpgsql
set search_path = ''
as $$
declare
  c_live constant text[] := array['pending_partner', 'registered', 'waitlisted', 'offered'];
  v_override boolean := coalesce(current_setting('actra.draw_override', true), '') = 'on';
  v_touched uuid[] := '{}';
  v_refuse boolean := false;
begin
  if tg_op = 'INSERT' then
    v_refuse := new.status = any (c_live)
      and exists (select 1 from public.tournament_draws d where d.category_id = new.category_id and d.locked);
    if new.status = 'registered' then v_touched := array[new.category_id]; end if;
  elsif new.category_id is distinct from old.category_id then
    v_refuse := (old.status = 'registered'
                 and exists (select 1 from public.tournament_draws d where d.category_id = old.category_id and d.locked))
             or (new.status = any (c_live)
                 and exists (select 1 from public.tournament_draws d where d.category_id = new.category_id and d.locked));
    if old.status = 'registered' then v_touched := v_touched || old.category_id; end if;
    if new.status = 'registered' then v_touched := v_touched || new.category_id; end if;
  elsif new.status is distinct from old.status then
    v_refuse := (old.status = 'registered' or new.status in ('registered', 'pending_partner', 'waitlisted', 'offered'))
      and exists (select 1 from public.tournament_draws d where d.category_id = new.category_id and d.locked);
    if old.status = 'registered' or new.status = 'registered' then v_touched := array[new.category_id]; end if;
  end if;

  if v_refuse and not v_override then raise exception 'draw_published'; end if;

  if cardinality(v_touched) > 0 then
    update public.tournament_draws d set outdated = true
    where d.category_id = any (v_touched) and d.status = 'draft' and not d.outdated;
  end if;
  return null;
end $$;

create trigger tournament_registrations_draw
after insert or update of status, category_id on public.tournament_registrations
for each row execute function app.registration_draw_guard();

-- ---------------------------------------------------------------------------
-- What the app calls. Each runs as the signed-in user at the real time.
-- ---------------------------------------------------------------------------

-- Returns the organiser list afterwards.
create function public.admin_set_organizer(p_tournament_id uuid, p_user_id uuid, p_add boolean) returns jsonb
language sql security definer
set search_path = ''
as $$
  select app.admin_set_organizer((select auth.uid()), p_tournament_id, p_user_id, p_add, now());
  select app.organizers_json(p_tournament_id);
$$;

create function public.tournament_organizers(p_tournament_id uuid) returns jsonb
language sql security definer
set search_path = ''
as $$ select app.tournament_organizers((select auth.uid()), p_tournament_id) $$;

-- The four draw calls return the draw as the caller sees it.
create function public.make_draw(
  p_category_id uuid, p_format text, p_group_size integer default null, p_advance integer default null) returns jsonb
language sql security definer
set search_path = ''
as $$
  select app.make_draw((select auth.uid()), p_category_id, p_format, p_group_size, p_advance, now());
  select app.draw_json(p_category_id, (select auth.uid()));
$$;

create function public.swap_draw_entries(p_category_id uuid, p_registration_a uuid, p_registration_b uuid) returns jsonb
language sql security definer
set search_path = ''
as $$
  select app.swap_draw_entries((select auth.uid()), p_category_id, p_registration_a, p_registration_b, now());
  select app.draw_json(p_category_id, (select auth.uid()));
$$;

create function public.publish_draw(p_category_id uuid) returns jsonb
language sql security definer
set search_path = ''
as $$
  select app.publish_draw((select auth.uid()), p_category_id, now());
  select app.draw_json(p_category_id, (select auth.uid()));
$$;

create function public.redo_draw(p_category_id uuid) returns jsonb
language sql security definer
set search_path = ''
as $$
  select app.redo_draw((select auth.uid()), p_category_id, now());
  select app.draw_json(p_category_id, (select auth.uid()));
$$;

create function public.tournament_bracket(p_tournament_id uuid) returns jsonb
language sql security definer
set search_path = ''
as $$ select app.tournament_bracket((select auth.uid()), p_tournament_id) $$;

create function public.my_organized_tournaments() returns jsonb
language sql security definer
set search_path = ''
as $$ select app.my_organized_tournaments((select auth.uid())) $$;

create function public.organizer_entries(p_tournament_id uuid) returns jsonb
language sql security definer
set search_path = ''
as $$ select app.organizer_entries((select auth.uid()), p_tournament_id) $$;

revoke all on function
  public.admin_set_organizer(uuid, uuid, boolean),
  public.tournament_organizers(uuid),
  public.make_draw(uuid, text, integer, integer),
  public.swap_draw_entries(uuid, uuid, uuid),
  public.publish_draw(uuid),
  public.redo_draw(uuid),
  public.tournament_bracket(uuid),
  public.my_organized_tournaments(),
  public.organizer_entries(uuid)
from public, anon, authenticated;

grant execute on function
  public.admin_set_organizer(uuid, uuid, boolean),
  public.tournament_organizers(uuid),
  public.make_draw(uuid, text, integer, integer),
  public.swap_draw_entries(uuid, uuid, uuid),
  public.publish_draw(uuid),
  public.redo_draw(uuid),
  public.tournament_bracket(uuid),
  public.my_organized_tournaments(),
  public.organizer_entries(uuid)
to authenticated, service_role;
