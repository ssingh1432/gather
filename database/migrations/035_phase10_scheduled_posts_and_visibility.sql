-- Phase 10 Steps 10 & 13: scheduled posts + expanded post visibility levels.
--
-- STEP 10 — SCHEDULED POSTS
-- Stores the full post payload (same shape as post_drafts, minus the
-- draft-only fields) plus a target publish time + IANA timezone. A
-- pg_cron job runs every minute, finds due rows, and inserts the real
-- post — following the exact pattern already used for account-deletion
-- purging (see 019_scheduled_account_deletion_purge.sql): a SECURITY
-- DEFINER function called directly by pg_cron, no HTTP/service-role key
-- involved. The user can edit or cancel a scheduled post any time before
-- it fires because the source of truth (scheduled_posts row) isn't
-- touched until publish time.
--
-- STEP 13 — EXPANDED VISIBILITY
-- Previous levels (010_post_visibility.sql): public / friends / only_me,
-- where "friends" actually meant "followers" (checked user_follows) and
-- "only_me" meant private. We keep that behavior but rename it correctly
-- and add the two levels that were missing: a real mutual/close-friends
-- tier (backed by the existing close_friends table used by
-- close_friends_screen.dart) and a community-only tier (backed by
-- community_memberships). "unlisted" is new: readable via direct link
-- exactly like public, but never surfaced in feed/discovery listings.
--
-- Existing data migration: 'friends' -> 'followers' (same semantics,
-- correct name), 'only_me' -> 'private' (same semantics, correct name).
-- 'friends' is repurposed going forward to mean the close-friends list.

begin;

-- ===========================================================================
-- STEP 13 — Visibility levels
-- ===========================================================================

-- 1. Rename existing values to their correct semantic names before
--    widening the constraint, so no row is ever in a state the old
--    constraint would reject.
update public.posts set visibility = 'followers' where visibility = 'friends';
update public.posts set visibility = 'private' where visibility = 'only_me';

alter table public.posts drop constraint if exists posts_visibility_check;
alter table public.posts
  add constraint posts_visibility_check
  check (visibility in ('public', 'followers', 'friends', 'community', 'private', 'unlisted'));

comment on column public.posts.visibility is
  'Who can see this post. public: subject to existing private-account/follow gating. followers: author''s followers + author. friends: author''s close_friends list + author. community: members of posts.community_id + author. private: author only. unlisted: same reach as public but excluded from feed/search/discovery, reachable only via direct link.';

-- 2. Replace the SELECT policy with all six branches.
drop policy if exists posts_select_visible_beta on public.posts;

create policy posts_select_visible_beta on public.posts
for select
using (
  current_user_has_beta_access()
  and is_removed = false
  and (author_id = auth.uid() or not users_are_blocked(auth.uid(), author_id))
  and (
    author_id = auth.uid()
    or (
      visibility in ('public', 'unlisted')
      and can_view_author_posts(auth.uid(), author_id)
    )
    or (
      visibility = 'followers'
      and exists (
        select 1 from public.user_follows uf
        where uf.follower_id = auth.uid() and uf.following_id = author_id
      )
    )
    or (
      visibility = 'friends'
      and exists (
        select 1 from public.close_friends cf
        where cf.user_id = author_id and cf.friend_id = auth.uid()
      )
    )
    or (
      visibility = 'community'
      and post_id_visible_via_community(community_id, auth.uid())
    )
  )
);

-- Small helper so the community-only branch above stays readable and can
-- be reused by other RLS policies/RPCs that need the same check.
create or replace function public.post_id_visible_via_community(p_community_id uuid, p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select p_community_id is not null and exists (
    select 1 from public.community_memberships cm
    where cm.community_id = p_community_id and cm.user_id = p_user_id
  );
$$;
revoke all on function public.post_id_visible_via_community(uuid, uuid) from anon, authenticated;
grant execute on function public.post_id_visible_via_community(uuid, uuid) to authenticated;

-- 3. Keep unlisted posts out of feed listings (RLS above still lets
--    anyone with the direct link/post id read them, matching public
--    reach; this just stops them appearing in browsed/algorithmic
--    surfaces). get_home_feed is invoker-rights (RLS still applies on
--    top), so this only tightens what already-visible rows show up in.
drop function if exists public.get_home_feed(uuid, integer, integer);

create function public.get_home_feed(user_id uuid, page_size integer default 20, page_offset integer default 0)
returns table(id uuid, author_id uuid, community_id uuid, text_content text, created_at timestamp with time zone, author_username text, author_avatar_url text, image_url text, location text, feeling text, tags text[], like_count bigint, comment_count bigint, share_count integer, is_liked boolean, is_bookmarked boolean, reply_to_post_id uuid, reply_to_author_username text, reply_to_author_avatar_url text, reply_to_text_content text, reply_to_image_url text, reply_to_created_at timestamp with time zone, reply_to_removed boolean, is_sensitive boolean, content_type text, is_pinned boolean, edited_at timestamp with time zone, edit_count integer, visibility text)
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
    p.edit_count,
    p.visibility
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
$function$;

grant execute on function public.get_home_feed(uuid, integer, integer) to authenticated;

-- ===========================================================================
-- STEP 10 — Scheduled posts
-- ===========================================================================

create table if not exists public.scheduled_posts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  community_id uuid references public.communities(id),
  text_content text not null default '',
  media jsonb not null default '[]'::jsonb,
  tags text[] not null default '{}',
  visibility text not null default 'public'
    check (visibility in ('public', 'followers', 'friends', 'community', 'private', 'unlisted')),
  content_type text not null default 'text',
  location text,
  location_lat double precision,
  location_lng double precision,
  feeling text,
  reply_to_post_id uuid references public.posts(id),
  -- The moment this should be published, always stored in UTC (timestamptz
  -- normalizes on write). client_timezone is kept purely for display
  -- ("scheduled for 9:00 AM NPT") since timestamptz alone can't round-trip
  -- the user's original local time expression.
  scheduled_at timestamptz not null,
  client_timezone text not null default 'Asia/Kathmandu',
  status text not null default 'pending'
    check (status in ('pending', 'published', 'cancelled', 'failed')),
  failure_reason text,
  published_post_id uuid references public.posts(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint scheduled_posts_future_at check (scheduled_at > created_at - interval '1 minute')
);

create index if not exists idx_scheduled_posts_user on public.scheduled_posts (user_id, scheduled_at);
create index if not exists idx_scheduled_posts_due on public.scheduled_posts (scheduled_at) where status = 'pending';

alter table public.scheduled_posts enable row level security;

create policy scheduled_posts_owner_all on public.scheduled_posts
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Owner can only edit/cancel while still pending (once published/cancelled/
-- failed the row is history, not editable).
create or replace function public.enforce_scheduled_post_editable()
returns trigger
language plpgsql
as $$
begin
  if TG_OP = 'UPDATE' and old.status <> 'pending' and new.status = old.status then
    raise exception 'Cannot edit a scheduled post that is no longer pending (status: %)', old.status;
  end if;
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists trg_scheduled_posts_editable on public.scheduled_posts;
create trigger trg_scheduled_posts_editable
  before update on public.scheduled_posts
  for each row execute function public.enforce_scheduled_post_editable();

-- Publishes every due row. Runs as the row owner's identity is irrelevant
-- here (SECURITY DEFINER, only ever invoked by pg_cron as postgres) —
-- inserts are attributed via author_id in the payload, not auth.uid().
create or replace function public.publish_scheduled_posts()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  r record;
  new_post_id uuid;
  media_item jsonb;
begin
  for r in
    select * from public.scheduled_posts
    where status = 'pending' and scheduled_at <= now()
    order by scheduled_at asc
    limit 200 -- bounded per run so one huge backlog can't block the minutely job
  loop
    begin
      insert into public.posts (
        author_id, community_id, text_content, tags, visibility,
        content_type, location, location_lat, location_lng, feeling,
        reply_to_post_id
      ) values (
        r.user_id, r.community_id, r.text_content, r.tags, r.visibility,
        r.content_type, r.location, r.location_lat, r.location_lng, r.feeling,
        r.reply_to_post_id
      )
      returning id into new_post_id;

      if jsonb_array_length(r.media) > 0 then
        for media_item in select * from jsonb_array_elements(r.media)
        loop
          insert into public.post_media (post_id, media_url, thumbnail_url, media_type)
          values (
            new_post_id,
            media_item->>'media_url',
            media_item->>'thumbnail_url',
            coalesce(media_item->>'media_type', 'image')
          );
        end loop;
      end if;

      update public.scheduled_posts
      set status = 'published', published_post_id = new_post_id
      where id = r.id;

      insert into public.notifications (recipient_id, actor_id, post_id, type)
      values (r.user_id, r.user_id, new_post_id, 'scheduled_post_published');
    exception when others then
      -- Don't let one bad row (e.g. a since-deleted community) block the
      -- rest of the batch; mark it failed with the reason instead of
      -- retrying forever.
      update public.scheduled_posts
      set status = 'failed', failure_reason = left(sqlerrm, 500)
      where id = r.id;
    end;
  end loop;
end;
$$;

revoke all on function public.publish_scheduled_posts() from anon, authenticated;

select cron.schedule(
  'publish-scheduled-posts',
  '* * * * *', -- every minute
  $$select public.publish_scheduled_posts();$$
);

commit;
