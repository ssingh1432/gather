-- Phase 4: closed-beta access control, beta feedback capture, lightweight error visibility,
-- drop-off analytics signals, and admin review utilities.
-- Beta-only objects are isolated behind beta_* names so they can be removed after validation.

-- Extend analytics event allowlist with beta validation funnel signals.
alter table public.analytics_events
  drop constraint if exists analytics_events_event_name_check;

alter table public.analytics_events
  add constraint analytics_events_event_name_check check (event_name in (
    'user_signed_up',
    'user_logged_in',
    'post_created',
    'comment_created',
    'community_joined',
    'daily_active_user',
    'signup_started',
    'first_action_completed',
    'feed_viewed',
    'feed_no_interaction',
    'post_creation_started',
    'post_creation_abandoned'
  ));

create table if not exists public.beta_access_allowlist (
  id uuid primary key default gen_random_uuid(),
  email text not null unique check (email = lower(email)),
  invited_by uuid references public.users(id) on delete set null,
  invited_community text,
  user_id uuid unique references public.users(id) on delete set null,
  claimed_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists idx_beta_access_allowlist_email
  on public.beta_access_allowlist(email);
create index if not exists idx_beta_access_allowlist_user
  on public.beta_access_allowlist(user_id);

alter table public.beta_access_allowlist enable row level security;

drop policy if exists beta_access_select_admin on public.beta_access_allowlist;
create policy beta_access_select_admin on public.beta_access_allowlist
for select using (public.is_admin_or_mod());

drop policy if exists beta_access_manage_admin on public.beta_access_allowlist;
create policy beta_access_manage_admin on public.beta_access_allowlist
for all using (public.is_admin_or_mod()) with check (public.is_admin_or_mod());

create or replace function public.beta_email_allowed(email text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.beta_access_allowlist b
    where b.email = lower(trim($1))
      and (b.user_id is null or b.user_id = auth.uid())
  );
$$;

grant execute on function public.beta_email_allowed(text) to anon, authenticated;

create or replace function public.current_user_has_beta_access()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.beta_access_allowlist b
    join public.users u on u.id = auth.uid()
    where b.email = lower(u.email)
      and (b.user_id is null or b.user_id = auth.uid())
  ) or public.is_admin_or_mod();
$$;

grant execute on function public.current_user_has_beta_access() to authenticated;

create or replace function public.claim_beta_access_for_current_user()
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  current_email text;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select lower(email) into current_email from public.users where id = auth.uid();
  if current_email is null then
    return false;
  end if;

  update public.beta_access_allowlist
  set user_id = auth.uid(), claimed_at = coalesce(claimed_at, now())
  where email = current_email
    and (user_id is null or user_id = auth.uid());

  return public.current_user_has_beta_access();
end;
$$;

grant execute on function public.claim_beta_access_for_current_user() to authenticated;

create type public.beta_feedback_kind as enum ('bug','general','feature_request');
create type public.beta_feedback_tag as enum ('bug','ux','feature_request');
create type public.beta_feedback_status as enum ('open','resolved','ignored');

create table if not exists public.beta_feedback (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users(id) on delete cascade,
  kind public.beta_feedback_kind not null,
  tag public.beta_feedback_tag,
  status public.beta_feedback_status not null default 'open',
  message text not null check (char_length(trim(message)) between 3 and 4000),
  app_version text not null,
  platform text not null check (platform in ('android','ios','web','macos','windows','linux','unknown')),
  session_id uuid,
  admin_notes text,
  reviewed_by uuid references public.users(id) on delete set null,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_beta_feedback_status_created
  on public.beta_feedback(status, created_at desc);
create index if not exists idx_beta_feedback_user_created
  on public.beta_feedback(user_id, created_at desc);

alter table public.beta_feedback enable row level security;

drop policy if exists beta_feedback_insert_self on public.beta_feedback;
create policy beta_feedback_insert_self on public.beta_feedback
for insert with check (user_id = auth.uid() and public.current_user_has_beta_access());

drop policy if exists beta_feedback_select_self_or_admin on public.beta_feedback;
create policy beta_feedback_select_self_or_admin on public.beta_feedback
for select using (user_id = auth.uid() or public.is_admin_or_mod());

drop policy if exists beta_feedback_update_admin on public.beta_feedback;
create policy beta_feedback_update_admin on public.beta_feedback
for update using (public.is_admin_or_mod()) with check (public.is_admin_or_mod());

create trigger trg_beta_feedback_touch before update on public.beta_feedback
for each row execute function public.touch_updated_at();

create table if not exists public.beta_error_logs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references public.users(id) on delete set null,
  session_id uuid,
  message text not null,
  stack_trace text,
  context text,
  app_version text not null,
  platform text not null check (platform in ('android','ios','web','macos','windows','linux','unknown')),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists idx_beta_error_logs_created
  on public.beta_error_logs(created_at desc);
create index if not exists idx_beta_error_logs_user_created
  on public.beta_error_logs(user_id, created_at desc);

alter table public.beta_error_logs enable row level security;

drop policy if exists beta_error_logs_insert_beta on public.beta_error_logs;
create policy beta_error_logs_insert_beta on public.beta_error_logs
for insert with check (user_id = auth.uid() and public.current_user_has_beta_access());

drop policy if exists beta_error_logs_select_admin on public.beta_error_logs;
create policy beta_error_logs_select_admin on public.beta_error_logs
for select using (public.is_admin_or_mod());

create or replace function public.review_beta_feedback(
  feedback_id uuid,
  feedback_tag public.beta_feedback_tag,
  feedback_status public.beta_feedback_status,
  notes text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  admin_user uuid;
begin
  admin_user := public.ensure_admin_or_mod();

  update public.beta_feedback
  set tag = feedback_tag,
      status = feedback_status,
      admin_notes = notes,
      reviewed_by = admin_user,
      reviewed_at = now()
  where id = feedback_id;
end;
$$;

grant execute on function public.review_beta_feedback(uuid, public.beta_feedback_tag, public.beta_feedback_status, text) to authenticated;

-- Enforce closed-beta access server-side by tightening direct data access policies.
drop policy if exists users_select_all on public.users;
create policy users_select_beta on public.users for select using (
  id = auth.uid() or public.current_user_has_beta_access()
);

drop policy if exists communities_select_all on public.communities;
create policy communities_select_beta on public.communities for select using (public.current_user_has_beta_access());

drop policy if exists communities_insert_auth on public.communities;
create policy communities_insert_beta on public.communities for insert with check (
  auth.uid() = created_by and public.current_user_has_beta_access()
);

drop policy if exists memberships_select_own on public.community_memberships;
create policy memberships_select_beta on public.community_memberships for select using (
  public.current_user_has_beta_access() and (user_id = auth.uid() or public.is_admin_or_mod())
);

drop policy if exists memberships_insert_self on public.community_memberships;
create policy memberships_insert_beta on public.community_memberships for insert with check (
  user_id = auth.uid() and public.current_user_has_beta_access()
);

drop policy if exists posts_select_visible on public.posts;
create policy posts_select_visible_beta on public.posts for select using (
  public.current_user_has_beta_access()
  and is_removed = false
  and (
    author_id = auth.uid()
    or not public.users_are_blocked(auth.uid(), author_id)
  )
);

drop policy if exists posts_insert_self_active on public.posts;
create policy posts_insert_self_active_beta on public.posts for insert with check (
  author_id = auth.uid()
  and public.current_user_is_active()
  and public.current_user_has_beta_access()
);

drop policy if exists media_select_visible on public.post_media;
create policy media_select_visible_beta on public.post_media for select using (
  public.current_user_has_beta_access()
  and exists (
    select 1 from public.posts p
    where p.id = post_id
      and p.is_removed = false
      and (p.author_id = auth.uid() or not public.users_are_blocked(auth.uid(), p.author_id))
  )
);

-- Guards close direct write bypasses even if a future policy is accidentally loosened.
create or replace function public.guard_beta_access()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.current_user_has_beta_access() then
    raise exception 'Closed beta access required' using errcode = '42501';
  end if;
  return new;
end;
$$;

create trigger trg_guard_beta_post_create
before insert on public.posts
for each row execute function public.guard_beta_access();

create trigger trg_guard_beta_comment_create
before insert on public.post_comments
for each row execute function public.guard_beta_access();

create trigger trg_guard_beta_like_create
before insert on public.post_likes
for each row execute function public.guard_beta_access();

create trigger trg_guard_beta_bookmark_create
before insert on public.bookmarks
for each row execute function public.guard_beta_access();

-- Allow invited users to create their profile row after Supabase Auth signup; the
-- allowlist check keeps profile creation beta-gated server-side.
drop policy if exists users_insert_self_beta on public.users;
create policy users_insert_self_beta on public.users for insert with check (
  id = auth.uid()
  and public.beta_email_allowed(email)
);

drop policy if exists likes_select_visible on public.post_likes;
create policy likes_select_visible_beta on public.post_likes for select using (
  public.current_user_has_beta_access()
  and (
    user_id = auth.uid()
    or exists (
      select 1 from public.posts p
      where p.id = post_id
        and p.is_removed = false
        and (p.author_id = auth.uid() or not public.users_are_blocked(auth.uid(), p.author_id))
    )
  )
);

drop policy if exists likes_insert_self_allowed on public.post_likes;
create policy likes_insert_self_allowed_beta on public.post_likes for insert with check (
  user_id = auth.uid()
  and public.current_user_is_active()
  and public.current_user_has_beta_access()
  and exists (
    select 1 from public.posts p
    where p.id = post_id
      and p.is_removed = false
      and not public.users_are_blocked(auth.uid(), p.author_id)
  )
);

drop policy if exists comments_select_visible on public.post_comments;
create policy comments_select_visible_beta on public.post_comments for select using (
  public.current_user_has_beta_access()
  and (
    user_id = auth.uid()
    or exists (
      select 1 from public.posts p
      where p.id = post_id
        and p.is_removed = false
        and not public.users_are_blocked(auth.uid(), p.author_id)
        and not public.users_are_blocked(auth.uid(), user_id)
    )
  )
);

drop policy if exists comments_insert_self_allowed on public.post_comments;
create policy comments_insert_self_allowed_beta on public.post_comments for insert with check (
  user_id = auth.uid()
  and public.current_user_is_active()
  and public.current_user_has_beta_access()
  and exists (
    select 1 from public.posts p
    where p.id = post_id
      and p.is_removed = false
      and not public.users_are_blocked(auth.uid(), p.author_id)
  )
);

drop policy if exists bookmarks_select_self on public.bookmarks;
create policy bookmarks_select_self_beta on public.bookmarks for select using (
  user_id = auth.uid() and public.current_user_has_beta_access()
);

drop policy if exists bookmarks_insert_self_allowed on public.bookmarks;
create policy bookmarks_insert_self_allowed_beta on public.bookmarks for insert with check (
  user_id = auth.uid()
  and public.current_user_is_active()
  and public.current_user_has_beta_access()
  and exists (
    select 1 from public.posts p
    where p.id = post_id
      and p.is_removed = false
      and not public.users_are_blocked(auth.uid(), p.author_id)
  )
);

drop policy if exists follows_select_all on public.user_follows;
create policy follows_select_beta on public.user_follows for select using (public.current_user_has_beta_access());

drop policy if exists follows_insert_self on public.user_follows;
drop policy if exists follows_insert_self_allowed on public.user_follows;
create policy follows_insert_self_allowed_beta on public.user_follows for insert with check (
  follower_id = auth.uid()
  and public.current_user_is_active()
  and public.current_user_has_beta_access()
  and not public.users_are_blocked(follower_id, following_id)
);

drop policy if exists notifications_select_self on public.notifications;
create policy notifications_select_self_beta on public.notifications for select using (
  recipient_id = auth.uid() and public.current_user_has_beta_access()
);

drop policy if exists reports_insert_self_active on public.reports;
create policy reports_insert_self_active_beta on public.reports for insert with check (
  reporter_id = auth.uid()
  and public.current_user_is_active()
  and public.current_user_has_beta_access()
);

drop policy if exists posts_update_owner_or_admin on public.posts;
create policy posts_update_owner_or_admin_beta on public.posts for update using (
  public.is_admin_or_mod()
  or (author_id = auth.uid() and is_removed = false and public.current_user_has_beta_access())
) with check (
  public.is_admin_or_mod()
  or (author_id = auth.uid() and is_removed = false and public.current_user_has_beta_access())
);

drop policy if exists posts_delete_owner_or_admin on public.posts;
create policy posts_delete_owner_or_admin_beta on public.posts for delete using (
  public.is_admin_or_mod()
  or (author_id = auth.uid() and public.current_user_has_beta_access())
);

drop policy if exists comments_update_self on public.post_comments;
create policy comments_update_self_beta on public.post_comments for update using (
  public.is_admin_or_mod()
  or (user_id = auth.uid() and public.current_user_has_beta_access())
) with check (
  public.is_admin_or_mod()
  or (user_id = auth.uid() and public.current_user_has_beta_access())
);

drop policy if exists comments_delete_self on public.post_comments;
create policy comments_delete_self_beta on public.post_comments for delete using (
  public.is_admin_or_mod()
  or (user_id = auth.uid() and public.current_user_has_beta_access())
);

drop policy if exists likes_delete_self on public.post_likes;
create policy likes_delete_self_beta on public.post_likes for delete using (
  public.is_admin_or_mod()
  or (user_id = auth.uid() and public.current_user_has_beta_access())
);

drop policy if exists bookmarks_delete_self on public.bookmarks;
create policy bookmarks_delete_self_beta on public.bookmarks for delete using (
  public.is_admin_or_mod()
  or (user_id = auth.uid() and public.current_user_has_beta_access())
);

drop policy if exists memberships_delete_self on public.community_memberships;
create policy memberships_delete_self_beta on public.community_memberships for delete using (
  public.is_admin_or_mod()
  or (user_id = auth.uid() and public.current_user_has_beta_access())
);

drop policy if exists follows_delete_self on public.user_follows;
create policy follows_delete_self_beta on public.user_follows for delete using (
  public.is_admin_or_mod()
  or (follower_id = auth.uid() and public.current_user_has_beta_access())
);

drop policy if exists notifications_update_self on public.notifications;
create policy notifications_update_self_beta on public.notifications for update using (
  recipient_id = auth.uid() and public.current_user_has_beta_access()
) with check (
  recipient_id = auth.uid() and public.current_user_has_beta_access()
);

drop policy if exists users_update_self on public.users;
create policy users_update_self_beta on public.users for update using (
  id = auth.uid() and public.current_user_has_beta_access()
) with check (
  id = auth.uid() and public.current_user_has_beta_access()
);
