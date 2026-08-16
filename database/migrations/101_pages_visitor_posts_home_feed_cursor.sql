-- 101_pages_visitor_posts_home_feed_cursor.sql
-- Pages-only integration: published visitor posts from followed pages (or the
-- viewer's own Page posts) are eligible for the authenticated Home feed.
-- Visitor posts remain in page_visitor_posts for Page moderation; they are not
-- copied into public.posts.

create or replace function public.get_home_feed_cursor(
  user_id uuid,
  page_size integer default 20,
  cursor_is_pinned boolean default null,
  cursor_created_at timestamptz default null,
  cursor_id uuid default null
)
returns table(
  id uuid, author_id uuid, community_id uuid, text_content text, created_at timestamptz,
  author_username text, author_avatar_url text, image_url text, location text, feeling text,
  tags text[], mentioned_user_ids uuid[], mentioned_usernames text[],
  like_count bigint, comment_count bigint, share_count integer, is_liked boolean,
  is_bookmarked boolean, is_following boolean, reply_to_post_id uuid, reply_to_author_username text,
  reply_to_author_avatar_url text, reply_to_text_content text, reply_to_image_url text,
  reply_to_created_at timestamptz, reply_to_removed boolean, is_sensitive boolean,
  content_type text, is_pinned boolean, edited_at timestamptz, edit_count integer, visibility text,
  media_items jsonb
)
language sql stable
set search_path to 'public'
as $$
  with feed_rows as (
    select
      p.id, p.author_id, p.community_id, p.text_content, p.created_at,
      u.username as author_username, u.profile_photo_url as author_avatar_url,
      pm.media_url as image_url, p.location, p.feeling, p.tags,
      p.mentioned_user_ids, p.mentioned_usernames,
      coalesce(likes.like_count, 0)::bigint as like_count,
      coalesce(comments.comment_count, 0)::bigint as comment_count,
      p.share_count,
      (pl.user_id is not null) as is_liked,
      (b.user_id is not null) as is_bookmarked,
      (p.author_id <> $1 and fol.follower_id is not null) as is_following,
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
    left join lateral (select media_url from public.post_media where post_id = p.id order by created_at asc limit 1) pm on true
    left join lateral (
      select jsonb_agg(jsonb_build_object('media_url', m.media_url, 'media_type', m.media_type) order by m.created_at asc) as media_items
      from public.post_media m where m.post_id = p.id
    ) pmall on true
    left join lateral (select count(*) as like_count from public.post_likes where post_id = p.id) likes on true
    left join lateral (select count(*) as comment_count from public.post_comments where post_id = p.id) comments on true
    left join public.post_likes pl on pl.post_id = p.id and pl.user_id = $1
    left join public.bookmarks b on b.post_id = p.id and b.user_id = $1
    left join public.user_follows fol on fol.follower_id = $1 and fol.following_id = p.author_id
    left join public.posts rp on rp.id = p.reply_to_post_id and rp.is_removed = false and rp.publish_status = 'published'
    left join public.users ru on ru.id = rp.author_id
    left join lateral (select media_url from public.post_media where post_id = rp.id order by created_at asc limit 1) rpm on true
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
      and (not p.is_sensitive or not (viewer_row.safe_search_enabled or viewer_row.child_safety_mode))
      and (
        p.author_id = $1
        or exists (select 1 from public.user_follows uf where uf.follower_id = $1 and uf.following_id = p.author_id)
        or exists (select 1 from public.community_memberships cm where cm.user_id = $1 and cm.community_id = p.community_id)
      )

    union all

    select
      vp.id,
      vp.author_id,
      null::uuid as community_id,
      vp.content as text_content,
      vp.created_at,
      u.username as author_username,
      u.profile_photo_url as author_avatar_url,
      null::text as image_url,
      ('Posted on ' || pg.name)::text as location,
      null::text as feeling,
      '{}'::text[] as tags,
      '{}'::uuid[] as mentioned_user_ids,
      '{}'::text[] as mentioned_usernames,
      0::bigint as like_count,
      0::bigint as comment_count,
      0::integer as share_count,
      false as is_liked,
      false as is_bookmarked,
      false as is_following,
      null::uuid as reply_to_post_id,
      null::text as reply_to_author_username,
      null::text as reply_to_author_avatar_url,
      null::text as reply_to_text_content,
      null::text as reply_to_image_url,
      null::timestamptz as reply_to_created_at,
      false as reply_to_removed,
      false as is_sensitive,
      'text'::text as content_type,
      false as is_pinned,
      null::timestamptz as edited_at,
      0::integer as edit_count,
      'public'::text as visibility,
      '[]'::jsonb as media_items
    from public.page_visitor_posts vp
    join public.pages pg on pg.id = vp.page_id
    join public.users u on u.id = vp.author_id
    where $1 = auth.uid()
      and vp.status = 'published'
      and pg.status = 'published'
      and pg.deleted_at is null
      and (
        vp.author_id = $1
        or exists (select 1 from public.page_followers pf where pf.page_id = vp.page_id and pf.user_id = $1)
        or public.current_user_has_page_permission(vp.page_id, 'manage_content')
      )
      and not exists (
        select 1 from public.user_blocks ub
        where (ub.blocker_id = $1 and ub.blocked_id = vp.author_id)
           or (ub.blocker_id = vp.author_id and ub.blocked_id = $1)
      )
  )
  select *
  from feed_rows
  where ($3 is null and $4 is null and $5 is null)
     or row(is_pinned, created_at, id) < row($3, $4, $5)
  order by is_pinned desc, created_at desc, id desc
  limit least(greatest(coalesce($2, 20), 1), 100);
$$;

grant execute on function public.get_home_feed_cursor(uuid, integer, boolean, timestamptz, uuid) to authenticated;
