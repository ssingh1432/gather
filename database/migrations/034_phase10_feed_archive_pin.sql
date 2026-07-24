-- Phase 10 Steps 14/15: exclude archived posts from the home feed, surface
-- pinned posts at the top, and return content_type/is_pinned/edited_at/
-- edit_count so the client can render polls/events and edit/pin badges
-- from the home feed RPC (not just the direct-query public/profile feeds).
--
-- Return signature changed (new output columns), so this drops and
-- recreates the function rather than CREATE OR REPLACE.

DROP FUNCTION IF EXISTS public.get_home_feed(uuid, integer, integer);

CREATE FUNCTION public.get_home_feed(user_id uuid, page_size integer DEFAULT 20, page_offset integer DEFAULT 0)
 RETURNS TABLE(id uuid, author_id uuid, community_id uuid, text_content text, created_at timestamp with time zone, author_username text, author_avatar_url text, image_url text, location text, feeling text, tags text[], like_count bigint, comment_count bigint, share_count integer, is_liked boolean, is_bookmarked boolean, reply_to_post_id uuid, reply_to_author_username text, reply_to_author_avatar_url text, reply_to_text_content text, reply_to_image_url text, reply_to_created_at timestamp with time zone, reply_to_removed boolean, is_sensitive boolean, content_type text, is_pinned boolean, edited_at timestamp with time zone, edit_count integer)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  select
    p.id,
    p.author_id,
    p.community_id,
    p.text_content,
    p.created_at,
    u.username as author_username,
    u.profile_photo_url as author_avatar_url,
    pm.media_url as image_url,
    p.location,
    p.feeling,
    p.tags,
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
    p.is_sensitive,
    p.content_type,
    p.is_pinned,
    p.edited_at,
    p.edit_count
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
  left join public.posts rp on rp.id = p.reply_to_post_id and rp.is_removed = false
  left join public.users ru on ru.id = rp.author_id
  left join lateral (
    select media_url
    from public.post_media
    where post_id = rp.id
    order by created_at asc
    limit 1
  ) rpm on true
  join public.users viewer_row on viewer_row.id = $1
  where $1 = auth.uid()
    and p.is_removed = false
    and p.archived_at is null
    and not exists (
      select 1
      from public.user_blocks ub
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
  order by p.is_pinned desc, p.created_at desc, p.id desc
  limit least(greatest(coalesce($2, 20), 1), 100)
  offset greatest(coalesce($3, 0), 0);
$function$;

grant execute on function public.get_home_feed(uuid, integer, integer) to authenticated;
