-- Phase 10 Step 2: Extensible content architecture
-- Adds content_type to posts + dedicated tables for polls, events, drafts,
-- and edit history. Does not alter existing text/image/video post behavior.

begin;

-- 1. Content type classification on posts (backward compatible default)
alter table public.posts
  add column if not exists content_type text not null default 'text',
  add column if not exists is_pinned boolean not null default false,
  add column if not exists pinned_at timestamptz,
  add column if not exists archived_at timestamptz,
  add column if not exists edited_at timestamptz,
  add column if not exists edit_count int not null default 0;

alter table public.posts
  add constraint posts_content_type_check
  check (content_type in (
    'text','image','video','audio','document','poll','event',
    'repost','cross_post','announcement'
  ));

create index if not exists idx_posts_content_type on public.posts (content_type);
create index if not exists idx_posts_pinned on public.posts (is_pinned) where is_pinned = true;
create index if not exists idx_posts_archived on public.posts (archived_at) where archived_at is not null;

-- 2. Post edit history (admin-visible, append-only)
create table if not exists public.post_edit_history (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.posts(id) on delete cascade,
  editor_id uuid not null references auth.users(id),
  previous_text_content text,
  previous_media jsonb,
  edited_at timestamptz not null default now()
);
create index if not exists idx_post_edit_history_post on public.post_edit_history (post_id, edited_at desc);

alter table public.post_edit_history enable row level security;

create policy post_edit_history_owner_read on public.post_edit_history
  for select using (
    exists (select 1 from public.posts p where p.id = post_id and p.author_id = auth.uid())
  );

create policy post_edit_history_admin_read on public.post_edit_history
  for select using (public.is_admin_or_mod());

create policy post_edit_history_owner_insert on public.post_edit_history
  for insert with check (
    editor_id = auth.uid()
    and exists (select 1 from public.posts p where p.id = post_id and p.author_id = auth.uid())
  );

-- 3. Polls
create table if not exists public.polls (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.posts(id) on delete cascade,
  question text not null,
  allow_multiple boolean not null default false,
  is_anonymous boolean not null default true,
  expires_at timestamptz,
  closed_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.poll_options (
  id uuid primary key default gen_random_uuid(),
  poll_id uuid not null references public.polls(id) on delete cascade,
  option_text text not null,
  position int not null default 0
);
create index if not exists idx_poll_options_poll on public.poll_options (poll_id, position);

create table if not exists public.poll_votes (
  id uuid primary key default gen_random_uuid(),
  poll_id uuid not null references public.polls(id) on delete cascade,
  option_id uuid not null references public.poll_options(id) on delete cascade,
  user_id uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  unique (poll_id, option_id, user_id)
);
create index if not exists idx_poll_votes_poll_user on public.poll_votes (poll_id, user_id);

alter table public.polls enable row level security;
alter table public.poll_options enable row level security;
alter table public.poll_votes enable row level security;

create policy polls_read on public.polls for select using (
  exists (
    select 1 from public.posts p
    where p.id = post_id
      and (p.visibility = 'public' or p.author_id = auth.uid())
  )
);
create policy polls_owner_write on public.polls for all using (
  exists (select 1 from public.posts p where p.id = post_id and p.author_id = auth.uid())
);

create policy poll_options_read on public.poll_options for select using (
  exists (select 1 from public.polls pl where pl.id = poll_id)
);
create policy poll_options_owner_write on public.poll_options for all using (
  exists (
    select 1 from public.polls pl
    join public.posts p on p.id = pl.post_id
    where pl.id = poll_id and p.author_id = auth.uid()
  )
);

create policy poll_votes_read on public.poll_votes for select using (true);
create policy poll_votes_own_insert on public.poll_votes for insert with check (user_id = auth.uid());
create policy poll_votes_own_delete on public.poll_votes for delete using (user_id = auth.uid());

-- 4. Events
create table if not exists public.events (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.posts(id) on delete cascade,
  title text not null,
  description text,
  starts_at timestamptz not null,
  ends_at timestamptz,
  timezone text not null default 'Asia/Kathmandu',
  location_text text,
  location_lat double precision,
  location_lng double precision,
  online_url text,
  created_at timestamptz not null default now()
);

create table if not exists public.event_rsvps (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.events(id) on delete cascade,
  user_id uuid not null references auth.users(id),
  status text not null check (status in ('going','interested','not_going')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (event_id, user_id)
);
create index if not exists idx_event_rsvps_event on public.event_rsvps (event_id, status);

alter table public.events enable row level security;
alter table public.event_rsvps enable row level security;

create policy events_read on public.events for select using (
  exists (
    select 1 from public.posts p
    where p.id = post_id
      and (p.visibility = 'public' or p.author_id = auth.uid())
  )
);
create policy events_owner_write on public.events for all using (
  exists (select 1 from public.posts p where p.id = post_id and p.author_id = auth.uid())
);

create policy event_rsvps_read on public.event_rsvps for select using (true);
create policy event_rsvps_own_write on public.event_rsvps for all using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- 5. Drafts (separate from posts table; never appear in feed queries)
create table if not exists public.post_drafts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  community_id uuid references public.communities(id),
  text_content text not null default '',
  media jsonb not null default '[]'::jsonb,
  tags text[] not null default '{}',
  visibility text not null default 'public',
  content_type text not null default 'text',
  updated_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);
create index if not exists idx_post_drafts_user on public.post_drafts (user_id, updated_at desc);

alter table public.post_drafts enable row level security;

create policy post_drafts_owner_all on public.post_drafts for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());

commit;
