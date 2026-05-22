-- Gather MVP schema (Flutter + Supabase)

create extension if not exists pgcrypto;

create type public.user_role as enum ('user','moderator','admin');
create type public.user_status as enum ('active','banned');
create type public.notification_type as enum ('new_follower','post_like','post_comment');
create type public.report_target_type as enum ('user','post');
create type public.report_status as enum ('open','reviewing','resolved','dismissed');
create type public.media_type as enum ('image','video');

create table public.users (
  id uuid primary key references auth.users(id) on delete cascade,
  username text unique not null,
  bio text default '',
  profile_photo_url text,
  role public.user_role not null default 'user',
  status public.user_status not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.communities (
  id uuid primary key default gen_random_uuid(),
  name text unique not null,
  description text not null default '',
  image_url text,
  created_by uuid not null references public.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.community_memberships (
  user_id uuid not null references public.users(id) on delete cascade,
  community_id uuid not null references public.communities(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key(user_id, community_id)
);

create table public.posts (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null references public.users(id) on delete cascade,
  community_id uuid references public.communities(id) on delete set null,
  text_content text,
  is_removed boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.post_media (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.posts(id) on delete cascade,
  media_type public.media_type not null default 'image',
  media_url text not null,
  created_at timestamptz not null default now()
);

create table public.post_likes (
  user_id uuid not null references public.users(id) on delete cascade,
  post_id uuid not null references public.posts(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key(user_id, post_id)
);

create table public.post_comments (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.posts(id) on delete cascade,
  user_id uuid not null references public.users(id) on delete cascade,
  content text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.user_follows (
  follower_id uuid not null references public.users(id) on delete cascade,
  following_id uuid not null references public.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key(follower_id, following_id),
  check (follower_id <> following_id)
);

create table public.bookmarks (
  user_id uuid not null references public.users(id) on delete cascade,
  post_id uuid not null references public.posts(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key(user_id, post_id)
);

create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  recipient_id uuid not null references public.users(id) on delete cascade,
  actor_id uuid references public.users(id) on delete set null,
  post_id uuid references public.posts(id) on delete set null,
  type public.notification_type not null,
  is_read boolean not null default false,
  created_at timestamptz not null default now()
);

create table public.reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references public.users(id) on delete cascade,
  target_type public.report_target_type not null,
  target_user_id uuid references public.users(id) on delete cascade,
  target_post_id uuid references public.posts(id) on delete cascade,
  reason text not null,
  status public.report_status not null default 'open',
  reviewed_by uuid references public.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (
    (target_type = 'user' and target_user_id is not null and target_post_id is null) or
    (target_type = 'post' and target_post_id is not null and target_user_id is null)
  )
);

create table public.user_blocks (
  blocker_id uuid not null references public.users(id) on delete cascade,
  blocked_id uuid not null references public.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key(blocker_id, blocked_id),
  check (blocker_id <> blocked_id)
);

create index idx_posts_created_at on public.posts(created_at desc);
create index idx_posts_author_created on public.posts(author_id, created_at desc);
create index idx_posts_community_created on public.posts(community_id, created_at desc);
create index idx_comments_post_created on public.post_comments(post_id, created_at desc);
create index idx_notifications_recipient_read on public.notifications(recipient_id, is_read, created_at desc);

create or replace function public.is_admin_or_mod() returns boolean language sql stable as $$
  select exists (
    select 1 from public.users u
    where u.id = auth.uid() and u.role in ('admin','moderator')
  );
$$;

create or replace function public.touch_updated_at() returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger trg_users_touch before update on public.users
for each row execute function public.touch_updated_at();
create trigger trg_communities_touch before update on public.communities
for each row execute function public.touch_updated_at();
create trigger trg_posts_touch before update on public.posts
for each row execute function public.touch_updated_at();
create trigger trg_comments_touch before update on public.post_comments
for each row execute function public.touch_updated_at();
create trigger trg_reports_touch before update on public.reports
for each row execute function public.touch_updated_at();

create or replace function public.create_notification_on_follow() returns trigger language plpgsql as $$
begin
  insert into public.notifications(recipient_id, actor_id, type)
  values (new.following_id, new.follower_id, 'new_follower');
  return new;
end;
$$;

create or replace function public.create_notification_on_like() returns trigger language plpgsql as $$
declare post_author uuid;
begin
  select author_id into post_author from public.posts where id = new.post_id;
  if post_author is not null and post_author <> new.user_id then
    insert into public.notifications(recipient_id, actor_id, post_id, type)
    values (post_author, new.user_id, new.post_id, 'post_like');
  end if;
  return new;
end;
$$;

create or replace function public.create_notification_on_comment() returns trigger language plpgsql as $$
declare post_author uuid;
begin
  select author_id into post_author from public.posts where id = new.post_id;
  if post_author is not null and post_author <> new.user_id then
    insert into public.notifications(recipient_id, actor_id, post_id, type)
    values (post_author, new.user_id, new.post_id, 'post_comment');
  end if;
  return new;
end;
$$;

create trigger trg_follow_notify after insert on public.user_follows
for each row execute function public.create_notification_on_follow();
create trigger trg_like_notify after insert on public.post_likes
for each row execute function public.create_notification_on_like();
create trigger trg_comment_notify after insert on public.post_comments
for each row execute function public.create_notification_on_comment();

alter table public.users enable row level security;
alter table public.communities enable row level security;
alter table public.community_memberships enable row level security;
alter table public.posts enable row level security;
alter table public.post_media enable row level security;
alter table public.post_likes enable row level security;
alter table public.post_comments enable row level security;
alter table public.user_follows enable row level security;
alter table public.bookmarks enable row level security;
alter table public.notifications enable row level security;
alter table public.reports enable row level security;
alter table public.user_blocks enable row level security;

create policy users_select_all on public.users for select using (true);
create policy users_update_self on public.users for update using (id = auth.uid()) with check (id = auth.uid());
create policy users_admin_update on public.users for update using (public.is_admin_or_mod()) with check (public.is_admin_or_mod());

create policy communities_select_all on public.communities for select using (true);
create policy communities_insert_auth on public.communities for insert with check (auth.uid() = created_by);
create policy communities_update_owner_or_admin on public.communities for update using (created_by = auth.uid() or public.is_admin_or_mod()) with check (created_by = auth.uid() or public.is_admin_or_mod());

create policy memberships_select_own on public.community_memberships for select using (user_id = auth.uid() or public.is_admin_or_mod());
create policy memberships_insert_self on public.community_memberships for insert with check (user_id = auth.uid());
create policy memberships_delete_self on public.community_memberships for delete using (user_id = auth.uid() or public.is_admin_or_mod());

create policy posts_select_all on public.posts for select using (is_removed = false);
create policy posts_insert_self on public.posts for insert with check (author_id = auth.uid());
create policy posts_update_owner_or_admin on public.posts for update using (author_id = auth.uid() or public.is_admin_or_mod()) with check (author_id = auth.uid() or public.is_admin_or_mod());
create policy posts_delete_owner_or_admin on public.posts for delete using (author_id = auth.uid() or public.is_admin_or_mod());

create policy media_select_all on public.post_media for select using (true);
create policy media_insert_post_owner on public.post_media for insert with check (
  exists(select 1 from public.posts p where p.id = post_id and p.author_id = auth.uid())
);
create policy media_delete_owner_or_admin on public.post_media for delete using (
  public.is_admin_or_mod() or exists(select 1 from public.posts p where p.id = post_id and p.author_id = auth.uid())
);

create policy likes_select_all on public.post_likes for select using (true);
create policy likes_insert_self on public.post_likes for insert with check (user_id = auth.uid());
create policy likes_delete_self on public.post_likes for delete using (user_id = auth.uid() or public.is_admin_or_mod());

create policy comments_select_all on public.post_comments for select using (true);
create policy comments_insert_self on public.post_comments for insert with check (user_id = auth.uid());
create policy comments_update_self on public.post_comments for update using (user_id = auth.uid() or public.is_admin_or_mod()) with check (user_id = auth.uid() or public.is_admin_or_mod());
create policy comments_delete_self on public.post_comments for delete using (user_id = auth.uid() or public.is_admin_or_mod());

create policy follows_select_all on public.user_follows for select using (true);
create policy follows_insert_self on public.user_follows for insert with check (follower_id = auth.uid());
create policy follows_delete_self on public.user_follows for delete using (follower_id = auth.uid() or public.is_admin_or_mod());

create policy bookmarks_select_self on public.bookmarks for select using (user_id = auth.uid());
create policy bookmarks_insert_self on public.bookmarks for insert with check (user_id = auth.uid());
create policy bookmarks_delete_self on public.bookmarks for delete using (user_id = auth.uid());

create policy notifications_select_self on public.notifications for select using (recipient_id = auth.uid());
create policy notifications_update_self on public.notifications for update using (recipient_id = auth.uid()) with check (recipient_id = auth.uid());

create policy reports_insert_self on public.reports for insert with check (reporter_id = auth.uid());
create policy reports_select_self_or_admin on public.reports for select using (reporter_id = auth.uid() or public.is_admin_or_mod());
create policy reports_update_admin on public.reports for update using (public.is_admin_or_mod()) with check (public.is_admin_or_mod());

create policy blocks_select_self on public.user_blocks for select using (blocker_id = auth.uid());
create policy blocks_insert_self on public.user_blocks for insert with check (blocker_id = auth.uid());
create policy blocks_delete_self on public.user_blocks for delete using (blocker_id = auth.uid() or public.is_admin_or_mod());
