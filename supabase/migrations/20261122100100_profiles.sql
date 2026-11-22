-- People: players, their contact details, levels, venue owners, and the
-- one-time tokens used by Telegram sign-in.

-- What other players may see. No phone number here.
create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  -- null until the player finishes first sign-in.
  full_name text,
  city_id text references public.cities (id),
  language text check (language in ('uz', 'ru', 'en')),
  terms_accepted_at timestamptz,
  created_at timestamptz not null default now()
);

-- The phone number is the account's identity: one account per phone
-- (product spec §7.1). Written only by the sign-in function.
create table public.profile_contacts (
  user_id uuid primary key references public.profiles (id) on delete cascade,
  phone text not null unique check (phone ~ '^\+[0-9]{7,15}$'),
  telegram_user_id bigint unique,
  created_at timestamptz not null default now()
);

-- Self-selected level 1-5 per sport (product spec §8.1).
create table public.player_levels (
  user_id uuid not null references public.profiles (id) on delete cascade,
  sport_id text not null references public.sports (id),
  level integer not null check (level between 1 and 5),
  primary key (user_id, sport_id)
);

-- A venue can have several owners with equal rights (product spec §4).
create table public.venue_owners (
  venue_id uuid not null references public.venues (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (venue_id, user_id)
);

-- One sign-in attempt. `token` travels through the Telegram deep link;
-- the poll secret stays on the device that started the attempt and only its
-- hash is stored.
create table public.login_tokens (
  token text primary key,
  poll_secret_hash text not null,
  language text not null default 'ru' check (language in ('uz', 'ru', 'en')),
  status text not null default 'pending' check (status in ('pending', 'awaiting_contact', 'verified', 'claimed')),
  telegram_user_id bigint,
  chat_id bigint,
  phone text,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null
);
create index login_tokens_telegram_idx on public.login_tokens (telegram_user_id, status);

alter table public.profiles enable row level security;
alter table public.profile_contacts enable row level security;
alter table public.player_levels enable row level security;
alter table public.venue_owners enable row level security;
alter table public.login_tokens enable row level security;

revoke all on table public.profiles, public.profile_contacts, public.player_levels, public.venue_owners, public.login_tokens
  from anon, authenticated;
grant all on table public.profiles, public.profile_contacts, public.player_levels, public.venue_owners, public.login_tokens
  to service_role;

-- Profiles: every signed-in player can see names; each edits only their own.
grant select on table public.profiles to authenticated;
grant insert (id, full_name, city_id, language, terms_accepted_at) on table public.profiles to authenticated;
grant update (full_name, city_id, language, terms_accepted_at) on table public.profiles to authenticated;
create policy "signed-in players see profiles" on public.profiles for select to authenticated using (true);
create policy "players create their own profile" on public.profiles for insert to authenticated
  with check (id = (select auth.uid()));
create policy "players edit their own profile" on public.profiles for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));

-- Contacts: only your own.
grant select on table public.profile_contacts to authenticated;
create policy "players see their own phone" on public.profile_contacts for select to authenticated
  using (user_id = (select auth.uid()));

-- Levels: visible to signed-in players, edited by their owner.
grant select, insert, update, delete on table public.player_levels to authenticated;
create policy "signed-in players see levels" on public.player_levels for select to authenticated using (true);
create policy "players add their own levels" on public.player_levels for insert to authenticated
  with check (user_id = (select auth.uid()));
create policy "players change their own levels" on public.player_levels for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy "players remove their own levels" on public.player_levels for delete to authenticated
  using (user_id = (select auth.uid()));

-- Owner assignments: you can see which venues you own.
grant select on table public.venue_owners to authenticated;
create policy "owners see their own assignments" on public.venue_owners for select to authenticated
  using (user_id = (select auth.uid()));

-- login_tokens: no policy and no grant. Only the sign-in function, which
-- runs with the service role, can touch it.
