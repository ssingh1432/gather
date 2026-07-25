-- Phase 10 Step 17: Search integration.
--
-- Replaces the ILIKE-only text search (search_screen.dart's `.or(...)`) with
-- a proper search_posts RPC that supports every facet Step 17 asks for:
-- text, hashtag, @mention, media type, author, community, and date range,
-- plus sort order. It's SECURITY INVOKER (no "security definer"), so the
-- existing posts_select_visible_beta RLS policy still applies underneath
-- it exactly like it does for direct table queries — search never leaks a
-- post the searcher couldn't otherwise see.
--
-- pg_trgm backs ILIKE '%q%' with a real index instead of a sequential
-- scan; without it every keystroke search does a full table scan of
-- posts.text_content.

begin;

create extension if not exists pg_trgm with schema extensions;

create index if not exists idx_posts_text_content_trgm
  on public.posts using gin (text_content extensions.gin_trgm_ops);

create index if not exists idx_users_username_trgm
  on public.users using gin (username extensions.gin_trgm_ops);

create or replace function public.search_posts(
  viewer_id uuid,
  q text default null,               -- free text, matched against text_content
  p_tag text default null,           -- hashtag, without the leading '#'
  p_mentioned_username text default null,
  p_author_username text default null,
  p_community_id uuid default null,
  p_media_type text default null,    -- 'image' | 'video' | 'audio' | 'document' | null (any)
  p_date_from timestamptz default null,
  p_date_to timestamptz default null,
  p_sort text default 'recent',      -- 'recent' | 'popular'
  page_size integer default 20,
  page_offset integer default 0
)
returns table(
  id uuid, author_id uuid, community_id uuid, text_content text, created_at timestamptz,
  author_username text, author_avatar_url text, image_url text, media_type text,
  tags text[], like_count bigint, comment_count bigint, visibility text
)
language sql
stable
security invoker
set search_path to 'public'
as $function$
  select
    p.id, p.author_id, p.community_id, p.text_content, p.created_at,
    u.username as author_username, u.profile_photo_url as author_avatar_url,
    pm.media_url as image_url, pm.media_type::text as media_type,
    p.tags,
    coalesce(likes.like_count, 0) as like_count,
    coalesce(comments.comment_count, 0) as comment_count,
    p.visibility
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
  where p.is_removed = false
    and (viewer_id is null or viewer_id = auth.uid())
    and p.archived_at is null
    and (p.author_id = viewer_id or p.visibility <> 'unlisted') -- keep unlisted out of search, same as feed
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
$function$;

grant execute on function public.search_posts(uuid, text, text, text, text, uuid, text, timestamptz, timestamptz, text, integer, integer) to authenticated, anon;

commit;
