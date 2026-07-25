-- Phase 10 Step 16: Feed optimization.
--
-- 1. Missing index: post_media(post_id) had ONLY the primary key (id) —
--    every single feed row (home feed, public feed, profile grid, post
--    detail, replies) does `select ... from post_media where post_id = X
--    order by created_at asc limit 1`, which was a full scan of
--    post_media per row with no way to avoid it. This is the single
--    highest-value index in this migration.
--
-- 2. Cursor-based (keyset) pagination for the home feed. The existing
--    get_home_feed(user_id, page_size, page_offset) uses OFFSET, which
--    has two real problems at scale: (a) Postgres still has to walk and
--    discard every skipped row, so cost grows linearly with how deep the
--    user has scrolled, and (b) if a new post is inserted while the user
--    is scrolling, everything below it shifts by one position, which
--    reliably produces skipped or duplicated rows across pages. Keyset
--    pagination fixes both: instead of "skip N rows", the client sends
--    the (is_pinned, created_at, id) of the last row it saw, and the
--    query resumes exactly after that row using an indexed row
--    comparison — O(page_size) regardless of depth, and immune to
--    concurrent inserts because it never renumbers existing rows.
--    get_home_feed(...) is kept as-is (nothing else calls it besides the
--    now-unused homeFeedProvider), get_home_feed_cursor is new and is
--    what the client switches to.

begin;

create index if not exists idx_post_media_post_created on public.post_media (post_id, created_at asc);

-- Supports the keyset WHERE clause below: row comparison on
-- (is_pinned, created_at, id) needs an index with exactly that column
-- order to avoid a sort.
create index if not exists idx_posts_pinned_created_id on public.posts (is_pinned desc, created_at desc, id desc);

create or replace function public.get_home_feed_cursor(
  user_id uuid,
  page_size integer default 20,
  cursor_is_pinned boolean default null,
  cursor_created_at timestamptz default null,
  cursor_id uuid default null
)
returns table(id uuid, author_id uuid, community_id uuid, text_content text, created_at timestamp with time zone, author_username text, author_avatar_url text, image_url text, location text, feeling text, tags text[], like_count bigint, comment_count bigint, share_count integer, is_liked boolean, is_bookmarked boolean, reply_to_post_id uuid, reply_to_author_username text, reply_to_author_avatar_url text, reply_to_text_content text, reply_to_image_url text, reply_to_created_at timestamp with time zone, reply_to_removed boolean, is_sensitive boolean, content_type text, is_pinned boolean, edited_at timestamp with time zone, edit_count integer, visibility text)
language sql
stable
set search_path to 'public'
as $function$
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
    p.is_sensitive, p.content_type, p.is_pinned, p.edited_at, p.edit_count, p.visibility
  from public.posts p
  join public.users u on u.id = p.author_id
  left join lateral (
    select media_url from public.post_media where post_id = p.id order by created_at asc limit 1
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
  join public.users viewer_row on viewer_row.id = $1
  where $1 = auth.uid()
    and p.is_removed = false
    and p.archived_at is null
    and (p.author_id = $1 or p.visibility <> 'unlisted')
    and (
      -- No cursor => first page, no keyset filter.
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
$function$;

grant execute on function public.get_home_feed_cursor(uuid, integer, boolean, timestamptz, uuid) to authenticated;

comment on column public.posts.scheduled_for is
  'Unused legacy column, predates the scheduled_posts table (migration 035) — no app code reads or writes it. Left in place rather than dropped to avoid touching data outside a reviewed cleanup migration; do not build new features against it.';

commit;
