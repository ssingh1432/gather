-- Migration 097: requirement #3 ("a partially-created post must not
-- accidentally appear as a normal completed post") and #14 (an RPC to
-- make "this post is genuinely done" a single, explicit, server-verified
-- step, since Storage uploads can't participate in a SQL transaction).
--
-- Until now, the moment createPost() succeeded, the row was immediately
-- visible in every feed/profile/search — including the seconds (or, on a
-- bad connection, much longer) it takes to upload and attach media. A
-- post with a slow video upload was fully public with no video for
-- however long that took. This adds an explicit publish_status so a
-- post is only visible once the composer has confirmed everything
-- succeeded, and a finalize_post() RPC that is the one place that
-- confirmation happens (defense in depth: even if a client bug marks a
-- post "done" while an attach genuinely failed, that's now one function
-- to audit rather than an implicit assumption spread across every feed
-- query).
--
-- Default 'published' so every existing row (and any insert that
-- doesn't know about this — admin tools, edge functions, etc.) keeps
-- behaving exactly as before; only the composer's createPost() opts a
-- new post into 'publishing' until finalize_post() is called.
alter table public.posts
  add column if not exists publish_status text not null default 'published'
    check (publish_status in ('publishing', 'published'));

create index if not exists idx_posts_publish_status on public.posts (publish_status) where publish_status = 'publishing';

create or replace function public.finalize_post(p_post_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.posts
  set publish_status = 'published'
  where id = p_post_id and author_id = auth.uid();

  if not found then
    raise exception 'post not found or not owned by caller' using errcode = 'P0001';
  end if;
end;
$$;

grant execute on function public.finalize_post(uuid) to authenticated;

-- Feed/profile/search reads: only ever show a post once it's finalized.
create or replace function public.get_home_feed(user_id uuid, page_size integer default 20, page_offset integer default 0)
returns table(
  id uuid, author_id uuid, community_id uuid, text_content text, created_at timestamptz,
  author_username text, author_avatar_url text, image_url text, location text, feeling text,
  tags text[], like_count bigint, comment_count bigint, share_count integer, is_liked boolean,
  is_bookmarked boolean, reply_to_post_id uuid, reply_to_author_username text,
  reply_to_author_avatar_url text, reply_to_text_content text, reply_to_image_url text,
  reply_to_created_at timestamptz, reply_to_removed boolean, is_sensitive boolean,
  content_type text, is_pinned boolean, edited_at timestamptz, edit_count integer, visibility text,
  media_items jsonb
)
language sql stable
set search_path to 'public'
as $$
  select
    p.id, p.author_id, p.community_id, p.text_content, p.created_at,
    u.username as author_username, u.profile_photo_url as author_avatar_url,
    pm.media_url as image_url, p.location, p.feeling, p.tags,
    coalesce(likes.like_count, 0) as like_count,
    coalesce(comments.comment_count, 0) as comment_count,
    p.share_count,
    (pl.user_id is not null) as is_liked,
    (b.user_id is not null) as is_bookmarked,
    p.reply_to_post_id,
    ru.username as reply_to_author_username,
    ru.profile_photo_url as reply_to_author_avatar_url,
    rp.text_content as reply_to_text_content,
    rpm.media_url as reply_to_image_url,
    rp.created_at as reply_to_created_at,
    (p.reply_to_post_id is not null and rp.id is null) as reply_to_removed,
    p.is_sensitive, p.content_type, p.is_pinned, p.edited_at, p.edit_count, p.visibility,
    coalesce(pmall.media_items, '[]'::jsonb) as media_items
  from public.posts p
  join public.users u on u.id = p.author_id
  left join lateral (
    select media_url from public.post_media where post_id = p.id order by created_at asc limit 1
  ) pm on true
  left join lateral (
    select jsonb_agg(jsonb_build_object('media_url', m.media_url, 'media_type', m.media_type) order by m.created_at asc) as media_items
    from public.post_media m where m.post_id = p.id
  ) pmall on true
  left join lateral (
    select count(*) as like_count from public.post_likes where post_id = p.id
  ) likes on true
  left join lateral (
    select count(*) as comment_count from public.post_comments where post_id = p.id
  ) comments on true
  left join public.post_likes pl on pl.post_id = p.id and pl.user_id = $1
  left join public.bookmarks b on b.post_id = p.id and b.user_id = $1
  left join public.posts rp on rp.id = p.reply_to_post_id and rp.is_removed = false and rp.publish_status = 'published'
  left join public.users ru on ru.id = rp.author_id
  left join lateral (
    select media_url from public.post_media where post_id = rp.id order by created_at asc limit 1
  ) rpm on true
  join public.users viewer_row on viewer_row.id = $1
  where $1 = auth.uid()
    and p.is_removed = false
    and p.archived_at is null
    and p.publish_status = 'published'
    and (p.author_id = $1 or p.visibility <> 'unlisted')
    and not exists (
      select 1 from public.user_blocks ub
      where (ub.blocker_id = $1 and ub.blocked_id = p.author_id)
         or (ub.blocker_id = p.author_id and ub.blocked_id = $1)
    )
    and (
      not p.is_sensitive
      or not (viewer_row.safe_search_enabled or viewer_row.child_safety_mode)
    )
    and (
      p.author_id = $1
      or exists (
        select 1 from public.user_follows uf
        where uf.follower_id = $1 and uf.following_id = p.author_id
      )
      or exists (
        select 1 from public.community_memberships cm
        where cm.user_id = $1 and cm.community_id = p.community_id
      )
    )
  order by p.is_pinned desc, p.created_at desc, p.id desc
  limit least(greatest(coalesce($2, 20), 1), 100)
  offset greatest(coalesce($3, 0), 0);
$$;

create or replace function public.get_home_feed_cursor(
  user_id uuid, page_size integer default 20, cursor_is_pinned boolean default null,
  cursor_created_at timestamptz default null, cursor_id uuid default null
)
returns table(
  id uuid, author_id uuid, community_id uuid, text_content text, created_at timestamptz,
  author_username text, author_avatar_url text, image_url text, location text, feeling text,
  tags text[], like_count bigint, comment_count bigint, share_count integer, is_liked boolean,
  is_bookmarked boolean, reply_to_post_id uuid, reply_to_author_username text,
  reply_to_author_avatar_url text, reply_to_text_content text, reply_to_image_url text,
  reply_to_created_at timestamptz, reply_to_removed boolean, is_sensitive boolean,
  content_type text, is_pinned boolean, edited_at timestamptz, edit_count integer, visibility text,
  media_items jsonb
)
language sql stable
set search_path to 'public'
as $$
  select
    p.id, p.author_id, p.community_id, p.text_content, p.created_at,
    u.username as author_username, u.profile_photo_url as author_avatar_url,
    pm.media_url as image_url, p.location, p.feeling, p.tags,
    coalesce(likes.like_count, 0) as like_count,
    coalesce(comments.comment_count, 0) as comment_count,
    p.share_count,
    (pl.user_id is not null) as is_liked,
    (b.user_id is not null) as is_bookmarked,
    p.reply_to_post_id,
    ru.username as reply_to_author_username,
    ru.profile_photo_url as reply_to_author_avatar_url,
    rp.text_content as reply_to_text_content,
    rpm.media_url as reply_to_image_url,
    rp.created_at as reply_to_created_at,
    (p.reply_to_post_id is not null and rp.id is null) as reply_to_removed,
    p.is_sensitive, p.content_type, p.is_pinned, p.edited_at, p.edit_count, p.visibility,
    coalesce(pmall.media_items, '[]'::jsonb) as media_items
  from public.posts p
  join public.users u on u.id = p.author_id
  left join lateral (
    select media_url from public.post_media where post_id = p.id order by created_at asc limit 1
  ) pm on true
  left join lateral (
    select jsonb_agg(jsonb_build_object('media_url', m.media_url, 'media_type', m.media_type) order by m.created_at asc) as media_items
    from public.post_media m where m.post_id = p.id
  ) pmall on true
  left join lateral (
    select count(*) as like_count from public.post_likes where post_id = p.id
  ) likes on true
  left join lateral (
    select count(*) as comment_count from public.post_comments where post_id = p.id
  ) comments on true
  left join public.post_likes pl on pl.post_id = p.id and pl.user_id = $1
  left join public.bookmarks b on b.post_id = p.id and b.user_id = $1
  left join public.posts rp on rp.id = p.reply_to_post_id and rp.is_removed = false and rp.publish_status = 'published'
  left join public.users ru on ru.id = rp.author_id
  left join lateral (
    select media_url from public.post_media where post_id = rp.id order by created_at asc limit 1
  ) rpm on true
  join public.users viewer_row on viewer_row.id = $1
  where $1 = auth.uid()
    and p.is_removed = false
    and p.archived_at is null
    and p.publish_status = 'published'
    and (p.author_id = $1 or p.visibility <> 'unlisted')
    and (
      ($3 is null and $4 is null and $5 is null)
      or row(p.is_pinned, p.created_at, p.id) < row($3, $4, $5)
    )
    and not exists (
      select 1 from public.user_blocks ub
      where (ub.blocker_id = $1 and ub.blocked_id = p.author_id)
         or (ub.blocker_id = p.author_id and ub.blocked_id = $1)
    )
    and (
      not p.is_sensitive
      or not (viewer_row.safe_search_enabled or viewer_row.child_safety_mode)
    )
    and (
      p.author_id = $1
      or exists (
        select 1 from public.user_follows uf
        where uf.follower_id = $1 and uf.following_id = p.author_id
      )
      or exists (
        select 1 from public.community_memberships cm
        where cm.user_id = $1 and cm.community_id = p.community_id
      )
    )
  order by p.is_pinned desc, p.created_at desc, p.id desc
  limit least(greatest(coalesce($2, 20), 1), 100);
$$;

create or replace function public.get_community_feed(community_id uuid, user_id uuid default null, page_size integer default 20, page_offset integer default 0)
returns table(
  id uuid, author_id uuid, community_id uuid, text_content text, created_at timestamptz,
  author_username text, author_avatar_url text, image_url text, location text, feeling text,
  tags text[], like_count bigint, comment_count bigint, share_count integer, is_liked boolean,
  is_bookmarked boolean, reply_to_post_id uuid, reply_to_author_username text,
  reply_to_author_avatar_url text, reply_to_text_content text, reply_to_image_url text,
  reply_to_created_at timestamptz, reply_to_removed boolean, is_sensitive boolean,
  media_items jsonb
)
language sql stable
set search_path to 'public'
as $$
  select
    p.id, p.author_id, p.community_id, p.text_content, p.created_at,
    u.username as author_username, u.profile_photo_url as author_avatar_url,
    pm.media_url as image_url, p.location, p.feeling, p.tags,
    coalesce(likes.like_count, 0) as like_count,
    coalesce(comments.comment_count, 0) as comment_count,
    p.share_count,
    (viewer.viewer_id is not null and pl.user_id is not null) as is_liked,
    (viewer.viewer_id is not null and b.user_id is not null) as is_bookmarked,
    p.reply_to_post_id, ru.username as reply_to_author_username,
    ru.profile_photo_url as reply_to_author_avatar_url, rp.text_content as reply_to_text_content,
    rpm.media_url as reply_to_image_url, rp.created_at as reply_to_created_at,
    (p.reply_to_post_id is not null and rp.id is null) as reply_to_removed,
    p.is_sensitive,
    coalesce(pmall.media_items, '[]'::jsonb) as media_items
  from public.posts p
  join public.users u on u.id = p.author_id
  join public.communities c on c.id = p.community_id
  left join lateral (select coalesce($2, auth.uid()) as viewer_id) viewer on true
  left join lateral (
    select safe_search_enabled, child_safety_mode
    from public.users where id = viewer.viewer_id
  ) vu on true
  left join lateral (
    select media_url from public.post_media where post_id = p.id order by created_at asc limit 1
  ) pm on true
  left join lateral (
    select jsonb_agg(jsonb_build_object('media_url', m.media_url, 'media_type', m.media_type) order by m.created_at asc) as media_items
    from public.post_media m where m.post_id = p.id
  ) pmall on true
  left join lateral (select count(*) as like_count from public.post_likes where post_id = p.id) likes on true
  left join lateral (select count(*) as comment_count from public.post_comments where post_id = p.id) comments on true
  left join public.post_likes pl on pl.post_id = p.id and pl.user_id = viewer.viewer_id
  left join public.bookmarks b on b.post_id = p.id and b.user_id = viewer.viewer_id
  left join public.posts rp on rp.id = p.reply_to_post_id and rp.is_removed = false and rp.publish_status = 'published'
  left join public.users ru on ru.id = rp.author_id
  left join lateral (
    select media_url from public.post_media where post_id = rp.id order by created_at asc limit 1
  ) rpm on true
  where p.community_id = $1
    and p.is_removed = false
    and p.publish_status = 'published'
    and ($2 is null or $2 = auth.uid())
    and (
      not p.is_sensitive
      or vu.safe_search_enabled is null
      or not (coalesce(vu.safe_search_enabled, true) or coalesce(vu.child_safety_mode, false))
    )
    and (
      viewer.viewer_id is null
      or not exists (
        select 1 from public.user_blocks ub
        where (ub.blocker_id = viewer.viewer_id and ub.blocked_id = p.author_id)
           or (ub.blocker_id = p.author_id and ub.blocked_id = viewer.viewer_id)
      )
    )
    and (
      c.visibility = 'public'
      or (
        viewer.viewer_id is not null
        and (
          exists (
            select 1 from public.community_memberships m
            where m.community_id = c.id and m.user_id = viewer.viewer_id
          )
          or exists (
            select 1 from public.users au where au.id = viewer.viewer_id and au.role in ('admin','moderator')
          )
        )
      )
    )
  order by p.created_at desc, p.id desc
  limit least(greatest(coalesce($3, 20), 1), 100)
  offset greatest(coalesce($4, 0), 0);
$$;

create or replace function public.search_posts(
  viewer_id uuid, q text default null, p_tag text default null, p_mentioned_username text default null,
  p_author_username text default null, p_community_id uuid default null, p_media_type text default null,
  p_date_from timestamptz default null, p_date_to timestamptz default null, p_sort text default 'recent',
  page_size integer default 20, page_offset integer default 0
)
returns table(
  id uuid, author_id uuid, community_id uuid, text_content text, created_at timestamptz,
  author_username text, author_avatar_url text, image_url text, media_type text, tags text[],
  like_count bigint, comment_count bigint, visibility text, media_items jsonb
)
language sql stable
set search_path to 'public'
as $$
  select
    p.id, p.author_id, p.community_id, p.text_content, p.created_at,
    u.username as author_username, u.profile_photo_url as author_avatar_url,
    pm.media_url as image_url, pm.media_type::text as media_type,
    p.tags,
    coalesce(likes.like_count, 0) as like_count,
    coalesce(comments.comment_count, 0) as comment_count,
    p.visibility,
    coalesce(pmall.media_items, '[]'::jsonb) as media_items
  from public.posts p
  join public.users u on u.id = p.author_id
  left join lateral (
    select media_url, media_type from public.post_media where post_id = p.id order by created_at asc limit 1
  ) pm on true
  left join lateral (
    select jsonb_agg(jsonb_build_object('media_url', m.media_url, 'media_type', m.media_type) order by m.created_at asc) as media_items
    from public.post_media m where m.post_id = p.id
  ) pmall on true
  left join lateral (
    select count(*) as like_count from public.post_likes where post_id = p.id
  ) likes on true
  left join lateral (
    select count(*) as comment_count from public.post_comments where post_id = p.id
  ) comments on true
  where p.is_removed = false
    and p.publish_status = 'published'
    and (viewer_id is null or viewer_id = auth.uid())
    and p.archived_at is null
    and (p.author_id = viewer_id or p.visibility <> 'unlisted')
    and (q is null or q = '' or p.text_content ilike '%' || q || '%')
    and (p_tag is null or p_tag = '' or p.tags @> array[p_tag])
    and (p_mentioned_username is null or p_mentioned_username = '' or p.mentioned_usernames @> array[p_mentioned_username])
    and (p_author_username is null or p_author_username = '' or u.username ilike p_author_username)
    and (p_community_id is null or p.community_id = p_community_id)
    and (p_media_type is null or p_media_type = '' or pm.media_type::text = p_media_type)
    and (p_date_from is null or p.created_at >= p_date_from)
    and (p_date_to is null or p.created_at <= p_date_to)
  order by
    case when p_sort = 'popular' then coalesce(likes.like_count, 0) end desc nulls last,
    p.created_at desc
  limit least(greatest(coalesce(page_size, 20), 1), 100)
  offset greatest(coalesce(page_offset, 0), 0);
$$;
