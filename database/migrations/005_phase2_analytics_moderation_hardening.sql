-- Phase 2: analytics, rate-limit guards, block enforcement, and auditable moderation actions.
-- These changes are additive or policy/function replacements; no existing columns are removed.

create table if not exists public.analytics_events (
  id uuid primary key default gen_random_uuid(),
  event_name text not null check (event_name in (
    'user_signed_up',
    'user_logged_in',
    'post_created',
    'comment_created',
    'community_joined',
    'daily_active_user'
  )),
  user_id uuid not null references public.users(id) on delete cascade,
  post_id uuid references public.posts(id) on delete set null,
  community_id uuid references public.communities(id) on delete set null,
  metadata jsonb not null default '{}'::jsonb,
  occurred_at timestamptz not null default now(),
  event_date date not null default ((now() at time zone 'utc')::date),
  created_at timestamptz not null default now()
);

create index if not exists idx_analytics_events_user_occurred
  on public.analytics_events(user_id, occurred_at desc);
create index if not exists idx_analytics_events_name_occurred
  on public.analytics_events(event_name, occurred_at desc);

alter table public.analytics_events enable row level security;

-- Analytics is write-only for normal users. Admin/moderator reads keep operational reporting in Supabase.
drop policy if exists analytics_insert_self on public.analytics_events;
create policy analytics_insert_self on public.analytics_events
for insert with check (user_id = auth.uid());

drop policy if exists analytics_select_admin on public.analytics_events;
create policy analytics_select_admin on public.analytics_events
for select using (public.is_admin_or_mod());

create or replace function public.track_analytics_event(
  event_name text,
  post_id uuid default null,
  community_id uuid default null,
  metadata jsonb default '{}'::jsonb
)
returns void
language plpgsql
security invoker
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  insert into public.analytics_events(event_name, user_id, post_id, community_id, metadata)
  values ($1, auth.uid(), $2, $3, coalesce($4, '{}'::jsonb));
end;
$$;

grant execute on function public.track_analytics_event(text, uuid, uuid, jsonb) to authenticated;

-- One DAU event per UTC day per user. The client can call this often without creating duplicates.
create unique index if not exists idx_analytics_daily_active_once
  on public.analytics_events(user_id, event_date)
  where event_name = 'daily_active_user';

create or replace function public.track_daily_active_user()
returns void
language plpgsql
security invoker
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  insert into public.analytics_events(event_name, user_id)
  values ('daily_active_user', auth.uid())
  on conflict (user_id, event_date)
  where event_name = 'daily_active_user'
  do nothing;
end;
$$;

grant execute on function public.track_daily_active_user() to authenticated;

create or replace function public.current_user_is_active()
returns boolean
language sql
stable
set search_path = public
as $$
  select exists (
    select 1
    from public.users u
    where u.id = auth.uid()
      and u.status = 'active'
  );
$$;

create or replace function public.users_are_blocked(left_user uuid, right_user uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.user_blocks ub
    where (ub.blocker_id = $1 and ub.blocked_id = $2)
       or (ub.blocker_id = $2 and ub.blocked_id = $1)
  );
$$;

-- Centralized server-side guard for post creation. Prevents suspended/banned users and throttles direct API abuse.
create or replace function public.guard_post_create()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.author_id <> auth.uid() then
    raise exception 'Cannot create posts for another user' using errcode = '42501';
  end if;

  if not public.current_user_is_active() then
    raise exception 'Account is not allowed to create posts' using errcode = '42501';
  end if;

  if (
    select count(*)
    from public.posts p
    where p.author_id = new.author_id
      and p.created_at > now() - interval '1 hour'
  ) >= 10 then
    raise exception 'Post rate limit exceeded' using errcode = 'P0001';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_guard_post_create on public.posts;
create trigger trg_guard_post_create
before insert on public.posts
for each row execute function public.guard_post_create();

-- Comments are guarded against rate-limit abuse, removed posts, and either side of a user block.
create or replace function public.guard_comment_create()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  post_author uuid;
begin
  if new.user_id <> auth.uid() then
    raise exception 'Cannot comment for another user' using errcode = '42501';
  end if;

  if not public.current_user_is_active() then
    raise exception 'Account is not allowed to comment' using errcode = '42501';
  end if;

  select p.author_id into post_author
  from public.posts p
  where p.id = new.post_id
    and p.is_removed = false;

  if post_author is null then
    raise exception 'Cannot comment on removed or missing post' using errcode = 'P0001';
  end if;

  if public.users_are_blocked(new.user_id, post_author) then
    raise exception 'Cannot interact with this post' using errcode = '42501';
  end if;

  if (
    select count(*)
    from public.post_comments c
    where c.user_id = new.user_id
      and c.created_at > now() - interval '1 hour'
  ) >= 60 then
    raise exception 'Comment rate limit exceeded' using errcode = 'P0001';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_guard_comment_create on public.post_comments;
create trigger trg_guard_comment_create
before insert on public.post_comments
for each row execute function public.guard_comment_create();

-- Reports are rate-limited and validated server-side so direct inserts cannot spam moderators.
create or replace function public.guard_report_create()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  target_author uuid;
begin
  if new.reporter_id <> auth.uid() then
    raise exception 'Cannot report for another user' using errcode = '42501';
  end if;

  if not public.current_user_is_active() then
    raise exception 'Account is not allowed to report' using errcode = '42501';
  end if;

  if (
    select count(*)
    from public.reports r
    where r.reporter_id = new.reporter_id
      and r.created_at > now() - interval '1 day'
  ) >= 20 then
    raise exception 'Report rate limit exceeded' using errcode = 'P0001';
  end if;

  if new.target_type = 'post' then
    select p.author_id into target_author
    from public.posts p
    where p.id = new.target_post_id
      and p.is_removed = false;
  else
    target_author := new.target_user_id;
  end if;

  if target_author is null then
    raise exception 'Report target does not exist' using errcode = 'P0001';
  end if;

  if public.users_are_blocked(new.reporter_id, target_author) then
    raise exception 'Cannot report this target' using errcode = '42501';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_guard_report_create on public.reports;
create trigger trg_guard_report_create
before insert on public.reports
for each row execute function public.guard_report_create();

-- Extra interaction guard for likes/bookmarks/follows. This closes direct API paths not covered by UI checks.
create or replace function public.guard_post_interaction()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  actor_id uuid;
  post_author uuid;
begin
  actor_id := coalesce(new.user_id, auth.uid());

  if actor_id <> auth.uid() then
    raise exception 'Cannot interact for another user' using errcode = '42501';
  end if;

  if not public.current_user_is_active() then
    raise exception 'Account is not allowed to interact' using errcode = '42501';
  end if;

  select p.author_id into post_author
  from public.posts p
  where p.id = new.post_id
    and p.is_removed = false;

  if post_author is null or public.users_are_blocked(actor_id, post_author) then
    raise exception 'Cannot interact with this post' using errcode = '42501';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_guard_like_create on public.post_likes;
create trigger trg_guard_like_create
before insert on public.post_likes
for each row execute function public.guard_post_interaction();

drop trigger if exists trg_guard_bookmark_create on public.bookmarks;
create trigger trg_guard_bookmark_create
before insert on public.bookmarks
for each row execute function public.guard_post_interaction();

create or replace function public.guard_follow_create()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.follower_id <> auth.uid() then
    raise exception 'Cannot follow for another user' using errcode = '42501';
  end if;

  if not public.current_user_is_active() then
    raise exception 'Account is not allowed to follow' using errcode = '42501';
  end if;

  if public.users_are_blocked(new.follower_id, new.following_id) then
    raise exception 'Cannot follow this user' using errcode = '42501';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_guard_follow_create on public.user_follows;
create trigger trg_guard_follow_create
before insert on public.user_follows
for each row execute function public.guard_follow_create();

-- Tighten existing RLS so blocked relationships cannot be used to read or write social content directly.
drop policy if exists posts_select_all on public.posts;
create policy posts_select_visible on public.posts for select using (
  is_removed = false
  and (
    auth.uid() is null
    or author_id = auth.uid()
    or not public.users_are_blocked(auth.uid(), author_id)
  )
);

drop policy if exists posts_insert_self on public.posts;
create policy posts_insert_self_active on public.posts for insert with check (
  author_id = auth.uid()
  and public.current_user_is_active()
);

drop policy if exists likes_select_all on public.post_likes;
create policy likes_select_visible on public.post_likes for select using (
  auth.uid() is null
  or user_id = auth.uid()
  or exists (
    select 1 from public.posts p
    where p.id = post_id
      and p.is_removed = false
      and not public.users_are_blocked(auth.uid(), p.author_id)
  )
);

drop policy if exists likes_insert_self on public.post_likes;
create policy likes_insert_self_allowed on public.post_likes for insert with check (
  user_id = auth.uid()
  and public.current_user_is_active()
  and exists (
    select 1 from public.posts p
    where p.id = post_id
      and p.is_removed = false
      and not public.users_are_blocked(auth.uid(), p.author_id)
  )
);

drop policy if exists bookmarks_insert_self on public.bookmarks;
create policy bookmarks_insert_self_allowed on public.bookmarks for insert with check (
  user_id = auth.uid()
  and public.current_user_is_active()
  and exists (
    select 1 from public.posts p
    where p.id = post_id
      and p.is_removed = false
      and not public.users_are_blocked(auth.uid(), p.author_id)
  )
);

drop policy if exists comments_select_all on public.post_comments;
create policy comments_select_visible on public.post_comments for select using (
  auth.uid() is null
  or user_id = auth.uid()
  or exists (
    select 1 from public.posts p
    where p.id = post_id
      and p.is_removed = false
      and not public.users_are_blocked(auth.uid(), p.author_id)
      and not public.users_are_blocked(auth.uid(), user_id)
  )
);

drop policy if exists comments_insert_self on public.post_comments;
create policy comments_insert_self_allowed on public.post_comments for insert with check (
  user_id = auth.uid()
  and public.current_user_is_active()
  and exists (
    select 1 from public.posts p
    where p.id = post_id
      and p.is_removed = false
      and not public.users_are_blocked(auth.uid(), p.author_id)
  )
);

drop policy if exists reports_insert_self on public.reports;
create policy reports_insert_self_active on public.reports for insert with check (
  reporter_id = auth.uid()
  and public.current_user_is_active()
);

create table if not exists public.moderation_actions (
  id uuid primary key default gen_random_uuid(),
  action text not null check (action in ('report_resolved','post_soft_removed','user_suspended')),
  admin_id uuid not null references public.users(id) on delete restrict,
  report_id uuid references public.reports(id) on delete set null,
  post_id uuid references public.posts(id) on delete set null,
  target_user_id uuid references public.users(id) on delete set null,
  note text,
  created_at timestamptz not null default now()
);

create index if not exists idx_moderation_actions_created
  on public.moderation_actions(created_at desc);
create index if not exists idx_moderation_actions_admin_created
  on public.moderation_actions(admin_id, created_at desc);

alter table public.moderation_actions enable row level security;

drop policy if exists moderation_actions_select_admin on public.moderation_actions;
create policy moderation_actions_select_admin on public.moderation_actions
for select using (public.is_admin_or_mod());

create or replace function public.ensure_admin_or_mod()
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  admin_user uuid;
begin
  admin_user := auth.uid();
  if admin_user is null or not public.is_admin_or_mod() then
    raise exception 'Admin or moderator required' using errcode = '42501';
  end if;
  return admin_user;
end;
$$;

create or replace function public.resolve_report(report_id uuid, note text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  admin_user uuid;
begin
  admin_user := public.ensure_admin_or_mod();

  update public.reports
  set status = 'resolved', reviewed_by = admin_user
  where id = $1;

  insert into public.moderation_actions(action, admin_id, report_id, note)
  values ('report_resolved', admin_user, $1, $2);
end;
$$;

create or replace function public.soft_remove_post(post_id uuid, report_id uuid default null, note text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  admin_user uuid;
begin
  admin_user := public.ensure_admin_or_mod();

  update public.posts
  set is_removed = true
  where id = $1;

  insert into public.moderation_actions(action, admin_id, report_id, post_id, note)
  values ('post_soft_removed', admin_user, $2, $1, $3);
end;
$$;

create or replace function public.suspend_user(target_user_id uuid, report_id uuid default null, note text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  admin_user uuid;
begin
  admin_user := public.ensure_admin_or_mod();

  update public.users
  set status = 'suspended'
  where id = $1;

  insert into public.moderation_actions(action, admin_id, report_id, target_user_id, note)
  values ('user_suspended', admin_user, $2, $1, $3);
end;
$$;

grant execute on function public.resolve_report(uuid, text) to authenticated;
grant execute on function public.soft_remove_post(uuid, uuid, text) to authenticated;
grant execute on function public.suspend_user(uuid, uuid, text) to authenticated;

-- Users may edit profile/token fields, but cannot self-restore status or escalate role through direct API updates.
create or replace function public.guard_user_update()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if public.is_admin_or_mod() then
    return new;
  end if;

  if old.id <> auth.uid() or new.id <> old.id then
    raise exception 'Cannot update this user' using errcode = '42501';
  end if;

  if new.role is distinct from old.role or new.status is distinct from old.status then
    raise exception 'Cannot change role or status' using errcode = '42501';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_guard_user_update on public.users;
create trigger trg_guard_user_update
before update on public.users
for each row execute function public.guard_user_update();

-- Post owners can edit only active, non-removed posts; moderators/admins own soft-removal state.
drop policy if exists posts_update_owner_or_admin on public.posts;
create policy posts_update_owner_or_admin on public.posts for update using (
  public.is_admin_or_mod()
  or (author_id = auth.uid() and is_removed = false)
) with check (
  public.is_admin_or_mod()
  or (author_id = auth.uid() and is_removed = false)
);

-- Media visibility follows the parent post visibility so blocked/removed content cannot be fetched directly.
drop policy if exists media_select_all on public.post_media;
create policy media_select_visible on public.post_media for select using (
  exists (
    select 1 from public.posts p
    where p.id = post_id
      and p.is_removed = false
      and (
        auth.uid() is null
        or p.author_id = auth.uid()
        or not public.users_are_blocked(auth.uid(), p.author_id)
      )
  )
);
