-- 011_mention_ids_and_action_bar.sql
-- Adds mentioned_user_ids to the feed RPCs so the "with @a, @b" line in
-- the feed can link each tagged person to their profile (previously only
-- mentioned_usernames — text — was returned, with no id to navigate to).
-- get_community_feed also gains mentioned_usernames/mentioned_user_ids,
-- which it was missing entirely (tags never showed on community posts).

drop function if exists public.get_home_feed(uuid, integer, integer);

create function public.get_home_feed(user_id uuid, page_size integer DEFAULT 20, page_offset integer DEFAULT 0)
 returns table(id uuid, author_id uuid, community_id uuid, text_content text, created_at timestamp with time zone, author_username text, author_avatar_url text, author_ads_eligible boolean, image_url text, media_type text, location text, location_lat double precision, location_lng double precision, feeling text, tags text[], mentioned_usernames text[], mentioned_user_ids uuid[], reply_count integer, like_count bigint, comment_count bigint, share_count integer, view_count integer, download_count integer, link_preview_url text, link_preview_title text, link_preview_description text, link_preview_image_url text, link_preview_site_name text, is_liked boolean, is_bookmarked boolean, reply_to_post_id uuid, reply_to_author_username text, reply_to_author_avatar_url text, reply_to_text_content text, reply_to_image_url text, reply_to_created_at timestamp with time zone, reply_to_removed boolean)
 language sql
 stable
 set search_path to 'public'
as $function$
  select
    p.id, p.author_id, p.community_id, p.text_content, p.created_at,
    u.username as author_username,
    u.profile_photo_url as author_avatar_url,
    (u.monetization_status = 'approved' and u.monetization_opt_in) as author_ads_eligible,
    pm.media_url as image_url,
    pm.media_type::text as media_type,
    p.location, p.location_lat, p.location_lng, p.feeling, p.tags,
    p.mentioned_usernames, p.mentioned_user_ids, p.reply_count,
    coalesce(likes.like_count, 0) as like_count,
    coalesce(comments.comment_count, 0) as comment_count,
    p.share_count,
    p.view_count,
    p.download_count_cached as download_count,
    p.link_preview_url, p.link_preview_title, p.link_preview_description,
    p.link_preview_image_url, p.link_preview_site_name,
    (pl.user_id is not null) as is_liked,
    (b.user_id is not null) as is_bookmarked,
    p.reply_to_post_id,
    ru.username as reply_to_author_username,
    ru.profile_photo_url as reply_to_author_avatar_url,
    rp.text_content as reply_to_text_content,
    rpm.media_url as reply_to_image_url,
    rp.created_at as reply_to_created_at,
    (p.reply_to_post_id is not null and rp.id is null) as reply_to_removed
  from public.posts p
  join public.users u on u.id = p.author_id
  left join lateral (
    select media_url, media_type from public.post_media where post_id = p.id order by created_at asc limit 1
  ) pm on true
  left join lateral (
    select count(*) as like_count from public.post_likes where post_id = p.id
  ) likes on true
  left join lateral (
    select count(*) as comment_count from public.post_comments where post_id = p.id
  ) comments on true
  left join public.post_likes pl on pl.post_id = p.id and pl.user_id = $1
  left join public.bookmarks b on b.post_id = p.id and b.user_id = $1
  left join public.posts rp on rp.id = p.reply_to_post_id and rp.is_removed = false
  left join public.users ru on ru.id = rp.author_id
  left join lateral (
    select media_url from public.post_media where post_id = rp.id order by created_at asc limit 1
  ) rpm on true
  where $1 = auth.uid()
    and p.is_removed = false
    and not exists (
      select 1 from public.user_blocks ub
      where (ub.blocker_id = $1 and ub.blocked_id = p.author_id)
         or (ub.blocker_id = p.author_id and ub.blocked_id = $1)
    )
    and (
      p.author_id = $1
      or exists (select 1 from public.user_follows uf where uf.follower_id = $1 and uf.following_id = p.author_id)
      or exists (select 1 from public.community_memberships cm where cm.user_id = $1 and cm.community_id = p.community_id)
    )
  order by p.created_at desc, p.id desc
  limit least(greatest(coalesce($2, 20), 1), 100)
  offset greatest(coalesce($3, 0), 0);
$function$;

drop function if exists public.get_community_feed(uuid, uuid, integer, integer);

create function public.get_community_feed(community_id uuid, user_id uuid DEFAULT NULL::uuid, page_size integer DEFAULT 20, page_offset integer DEFAULT 0)
 returns table(id uuid, author_id uuid, community_id uuid, text_content text, created_at timestamp with time zone, author_username text, author_avatar_url text, image_url text, media_type text, location text, feeling text, tags text[], mentioned_usernames text[], mentioned_user_ids uuid[], like_count bigint, comment_count bigint, share_count integer, is_liked boolean, is_bookmarked boolean, reply_to_post_id uuid, reply_to_author_username text, reply_to_author_avatar_url text, reply_to_text_content text, reply_to_image_url text, reply_to_created_at timestamp with time zone, reply_to_removed boolean)
 language sql
 stable
 set search_path to 'public'
as $function$
  select
    p.id,
    p.author_id,
    p.community_id,
    p.text_content,
    p.created_at,
    u.username as author_username,
    u.profile_photo_url as author_avatar_url,
    pm.media_url as image_url,
    pm.media_type::text as media_type,
    p.location,
    p.feeling,
    p.tags,
    p.mentioned_usernames,
    p.mentioned_user_ids,
    coalesce(likes.like_count, 0) as like_count,
    coalesce(comments.comment_count, 0) as comment_count,
    p.share_count,
    (viewer.viewer_id is not null and pl.user_id is not null) as is_liked,
    (viewer.viewer_id is not null and b.user_id is not null) as is_bookmarked,
    p.reply_to_post_id,
    ru.username as reply_to_author_username,
    ru.profile_photo_url as reply_to_author_avatar_url,
    rp.text_content as reply_to_text_content,
    rpm.media_url as reply_to_image_url,
    rp.created_at as reply_to_created_at,
    (p.reply_to_post_id is not null and rp.id is null) as reply_to_removed
  from public.posts p
  join public.users u on u.id = p.author_id
  left join lateral (select coalesce($2, auth.uid()) as viewer_id) viewer on true
  left join lateral (
    select media_url, media_type
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
  left join public.posts rp on rp.id = p.reply_to_post_id and rp.is_removed = false
  left join public.users ru on ru.id = rp.author_id
  left join lateral (
    select media_url
    from public.post_media
    where post_id = rp.id
    order by created_at asc
    limit 1
  ) rpm on true
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
$function$;
