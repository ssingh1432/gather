-- Phase 1: push notification token support, community-post notifications,
-- and backend-owned feed assembly.

alter type public.notification_type add value if not exists 'community_post';

alter table public.users
  add column if not exists fcm_token text,
  add column if not exists fcm_token_updated_at timestamptz;

create index if not exists idx_users_fcm_token_present
  on public.users (fcm_token_updated_at desc)
  where fcm_token is not null;

create index if not exists idx_memberships_community_user
  on public.community_memberships(community_id, user_id);
create index if not exists idx_likes_post_user
  on public.post_likes(post_id, user_id);
create index if not exists idx_bookmarks_post_user
  on public.bookmarks(post_id, user_id);

create or replace function public.get_home_feed(
  user_id uuid,
  page_size integer default 20,
  page_offset integer default 0
)
returns table (
  id uuid,
  author_id uuid,
  community_id uuid,
  text_content text,
  created_at timestamptz,
  author_username text,
  image_url text,
  like_count bigint,
  comment_count bigint,
  is_liked boolean,
  is_bookmarked boolean
)
language sql
stable
security invoker
set search_path = public
as $$
  select
    p.id,
    p.author_id,
    p.community_id,
    p.text_content,
    p.created_at,
    u.username as author_username,
    pm.media_url as image_url,
    coalesce(likes.like_count, 0) as like_count,
    coalesce(comments.comment_count, 0) as comment_count,
    (pl.user_id is not null) as is_liked,
    (b.user_id is not null) as is_bookmarked
  from public.posts p
  join public.users u on u.id = p.author_id
  left join lateral (
    select media_url
    from public.post_media
    where post_id = p.id
    order by created_at asc
    limit 1
  ) pm on true
  left join lateral (
    select count(*) as like_count
    from public.post_likes
    where post_id = p.id
  ) likes on true
  left join lateral (
    select count(*) as comment_count
    from public.post_comments
    where post_id = p.id
  ) comments on true
  left join public.post_likes pl on pl.post_id = p.id and pl.user_id = $1
  left join public.bookmarks b on b.post_id = p.id and b.user_id = $1
  where $1 = auth.uid()
    and p.is_removed = false
    and not exists (
      select 1
      from public.user_blocks ub
      where (ub.blocker_id = $1 and ub.blocked_id = p.author_id)
         or (ub.blocker_id = p.author_id and ub.blocked_id = $1)
    )
    and (
      p.author_id = $1
      or exists (
        select 1
        from public.user_follows uf
        where uf.follower_id = $1
          and uf.following_id = p.author_id
      )
      or exists (
        select 1
        from public.community_memberships cm
        where cm.user_id = $1
          and cm.community_id = p.community_id
      )
    )
  order by p.created_at desc, p.id desc
  limit least(greatest(coalesce($2, 20), 1), 100)
  offset greatest(coalesce($3, 0), 0);
$$;

create or replace function public.get_community_feed(
  community_id uuid,
  user_id uuid default null,
  page_size integer default 20,
  page_offset integer default 0
)
returns table (
  id uuid,
  author_id uuid,
  community_id uuid,
  text_content text,
  created_at timestamptz,
  author_username text,
  image_url text,
  like_count bigint,
  comment_count bigint,
  is_liked boolean,
  is_bookmarked boolean
)
language sql
stable
security invoker
set search_path = public
as $$
  select
    p.id,
    p.author_id,
    p.community_id,
    p.text_content,
    p.created_at,
    u.username as author_username,
    pm.media_url as image_url,
    coalesce(likes.like_count, 0) as like_count,
    coalesce(comments.comment_count, 0) as comment_count,
    (viewer.viewer_id is not null and pl.user_id is not null) as is_liked,
    (viewer.viewer_id is not null and b.user_id is not null) as is_bookmarked
  from public.posts p
  join public.users u on u.id = p.author_id
  left join lateral (select coalesce($2, auth.uid()) as viewer_id) viewer on true
  left join lateral (
    select media_url
    from public.post_media
    where post_id = p.id
    order by created_at asc
    limit 1
  ) pm on true
  left join lateral (
    select count(*) as like_count
    from public.post_likes
    where post_id = p.id
  ) likes on true
  left join lateral (
    select count(*) as comment_count
    from public.post_comments
    where post_id = p.id
  ) comments on true
  left join public.post_likes pl on pl.post_id = p.id and pl.user_id = viewer.viewer_id
  left join public.bookmarks b on b.post_id = p.id and b.user_id = viewer.viewer_id
  where p.community_id = $1
    and p.is_removed = false
    and ($2 is null or $2 = auth.uid())
    and (
      viewer.viewer_id is null
      or not exists (
        select 1
        from public.user_blocks ub
        where (ub.blocker_id = viewer.viewer_id and ub.blocked_id = p.author_id)
           or (ub.blocker_id = p.author_id and ub.blocked_id = viewer.viewer_id)
      )
    )
  order by p.created_at desc, p.id desc
  limit least(greatest(coalesce($3, 20), 1), 100)
  offset greatest(coalesce($4, 0), 0);
$$;

grant execute on function public.get_home_feed(uuid, integer, integer) to authenticated;
grant execute on function public.get_community_feed(uuid, uuid, integer, integer) to anon, authenticated;
