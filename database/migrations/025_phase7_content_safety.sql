-- Phase 7 (User Safety) — Part 2: Sensitive content warnings, Safe search,
-- Child safety mode, Anti-spam (duplicate content), Fake account detection
-- signals, Mass-reporting protection.
--
-- Filter offensive language is intentionally NOT re-implemented here — it
-- already exists in full from Phase 6 (keyword_filters +
-- auto_moderate_post_block/flag + auto_moderate_comment_block/flag in
-- 022_phase6_community_moderation.sql). This migration seeds it with a
-- starter word list instead of rebuilding it.

-- 1. Sensitive content warnings -----------------------------------------
alter table public.posts add column if not exists is_sensitive boolean not null default false;

-- 2. Safe search + Child safety mode ------------------------------------
alter table public.users add column if not exists safe_search_enabled boolean not null default true;
alter table public.users add column if not exists child_safety_mode boolean not null default false;

-- Child safety mode is a floor, not a toggle someone can quietly work
-- around from the same settings screen: turning it on forces safe search
-- on and tightens message privacy, and it can't be loosened again while
-- child safety mode stays on.
create or replace function public.enforce_child_safety_mode()
returns trigger
language plpgsql
as $$
begin
  if new.child_safety_mode then
    new.safe_search_enabled := true;
    if new.message_privacy = 'everyone' then
      new.message_privacy := 'friends';
    end if;
  end if;

  if new.child_safety_mode and not new.safe_search_enabled then
    raise exception 'Safe search cannot be disabled while child safety mode is on' using errcode = 'P0001';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_enforce_child_safety_mode on public.users;
create trigger trg_enforce_child_safety_mode
before update of child_safety_mode, safe_search_enabled, message_privacy on public.users
for each row execute function public.enforce_child_safety_mode();

-- Feed RPCs gain an is_sensitive output column and, for viewers with safe
-- search effectively on (their own toggle, or forced on by child safety
-- mode), sensitive posts are excluded outright rather than blurred —
-- everyone else still gets them, rendered behind a tap-to-reveal gate
-- client-side.
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
  author_avatar_url text,
  image_url text,
  location text,
  feeling text,
  tags text[],
  like_count bigint,
  comment_count bigint,
  share_count integer,
  is_liked boolean,
  is_bookmarked boolean,
  reply_to_post_id uuid,
  reply_to_author_username text,
  reply_to_author_avatar_url text,
  reply_to_text_content text,
  reply_to_image_url text,
  reply_to_created_at timestamptz,
  reply_to_removed boolean,
  is_sensitive boolean
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
    p.is_sensitive
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
  author_avatar_url text,
  image_url text,
  location text,
  feeling text,
  tags text[],
  like_count bigint,
  comment_count bigint,
  share_count integer,
  is_liked boolean,
  is_bookmarked boolean,
  reply_to_post_id uuid,
  reply_to_author_username text,
  reply_to_author_avatar_url text,
  reply_to_text_content text,
  reply_to_image_url text,
  reply_to_created_at timestamptz,
  reply_to_removed boolean,
  is_sensitive boolean
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
    u.profile_photo_url as author_avatar_url,
    pm.media_url as image_url,
    p.location,
    p.feeling,
    p.tags,
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
    (p.reply_to_post_id is not null and rp.id is null) as reply_to_removed,
    p.is_sensitive
  from public.posts p
  join public.users u on u.id = p.author_id
  left join lateral (select coalesce($2, auth.uid()) as viewer_id) viewer on true
  left join lateral (
    select safe_search_enabled, child_safety_mode
    from public.users
    where id = viewer.viewer_id
  ) vu on true
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
      not p.is_sensitive
      or vu.safe_search_enabled is null
      or not (coalesce(vu.safe_search_enabled, true) or coalesce(vu.child_safety_mode, false))
    )
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

-- 3. Anti-spam: duplicate-content detection -------------------------------
-- Layers on top of the existing per-window post-count rate limit (005 /
-- 007): blocks posting the exact same non-empty text twice in a short
-- window, the classic copy-paste spam pattern that a pure count limit
-- doesn't catch.
create or replace function public.guard_duplicate_post_content()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if coalesce(trim(new.text_content), '') = '' then
    return new;
  end if;

  if exists (
    select 1
    from public.posts p
    where p.author_id = new.author_id
      and p.text_content = new.text_content
      and p.is_removed = false
      and p.created_at > now() - interval '10 minutes'
  ) then
    raise exception 'Duplicate post detected — please wait before reposting the same content' using errcode = 'P0001';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_guard_duplicate_post_content on public.posts;
create trigger trg_guard_duplicate_post_content
before insert on public.posts
for each row execute function public.guard_duplicate_post_content();

-- 4. Fake account detection signals ---------------------------------------
-- Deliberately advisory, not automatic: returns a heuristic score per user
-- for moderators to review (Phase 8 admin dashboard), rather than
-- auto-suspending anyone off a false-positive-prone score alone.
create or replace function public.fake_account_signals(min_score integer default 3)
returns table (
  user_id uuid,
  username text,
  score integer,
  reasons text[],
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform public.ensure_admin_or_mod();

  return query
  select
    u.id,
    u.username,
    (
      (case when u.profile_photo_url is null then 2 else 0 end) +
      (case when coalesce(trim(u.bio), '') = '' then 1 else 0 end) +
      (case when not u.phone_verified then 1 else 0 end) +
      (case when u.created_at < now() - interval '3 days' and post_counts.n = 0 then 2 else 0 end) +
      (case when follow_counts.n > 50 and u.created_at > now() - interval '1 day' then 3 else 0 end)
    )::integer as score,
    array_remove(array[
      case when u.profile_photo_url is null then 'no_profile_photo' end,
      case when coalesce(trim(u.bio), '') = '' then 'empty_bio' end,
      case when not u.phone_verified then 'phone_unverified' end,
      case when u.created_at < now() - interval '3 days' and post_counts.n = 0 then 'no_posts_after_3_days' end,
      case when follow_counts.n > 50 and u.created_at > now() - interval '1 day' then 'mass_follow_burst' end
    ], null) as reasons,
    u.created_at
  from public.users u
  left join lateral (
    select count(*) as n from public.posts p where p.author_id = u.id and p.is_removed = false
  ) post_counts on true
  left join lateral (
    select count(*) as n from public.user_follows uf where uf.follower_id = u.id
  ) follow_counts on true
  where u.status = 'active'
  having (
    (case when u.profile_photo_url is null then 2 else 0 end) +
    (case when coalesce(trim(u.bio), '') = '' then 1 else 0 end) +
    (case when not u.phone_verified then 1 else 0 end) +
    (case when u.created_at < now() - interval '3 days' and post_counts.n = 0 then 2 else 0 end) +
    (case when follow_counts.n > 50 and u.created_at > now() - interval '1 day' then 3 else 0 end)
  ) >= min_score
  order by score desc, u.created_at desc
  limit 200;
end;
$$;

grant execute on function public.fake_account_signals(integer) to authenticated;

-- 5. Mass-reporting protection ---------------------------------------------
-- Stops a single reporter from padding the count against one target with
-- duplicate open reports (the daily rate limit in guard_report_create caps
-- volume across all targets, this caps it per-target).
create unique index if not exists uq_reports_open_reporter_post
  on public.reports (reporter_id, target_post_id)
  where status = 'open' and target_type = 'post' and not is_automated;

create unique index if not exists uq_reports_open_reporter_user
  on public.reports (reporter_id, target_user_id)
  where status = 'open' and target_type = 'user' and not is_automated;

-- Coordinated brigading (many distinct reporters hitting one target in a
-- short window) never auto-hides or auto-strikes anything in this schema —
-- add_strike/suspend_user/ban_user are exclusively moderator/admin-invoked.
-- This view just surfaces the pattern so a review queue can prioritize it,
-- instead of a spike in report count alone ever mattering.
create or replace view public.coordinated_report_signals as
select
  coalesce(target_post_id, target_user_id) as target_id,
  target_type,
  count(*) as report_count,
  count(distinct reporter_id) as distinct_reporters,
  min(created_at) as first_report_at,
  max(created_at) as last_report_at
from public.reports
where status = 'open'
  and created_at > now() - interval '24 hours'
group by coalesce(target_post_id, target_user_id), target_type
having count(*) >= 5
order by report_count desc;

grant select on public.coordinated_report_signals to authenticated;
alter view public.coordinated_report_signals set (security_invoker = true);

-- 6. Seed the offensive-language keyword filter (Phase 6 infra) ------------
-- A minimal, deliberately conservative starter list — obvious English
-- slurs/profanity at 'flag' severity so they route to moderator review
-- rather than silently vanishing on a false positive. Nepal-specific and
-- Nepali-script terms are left for moderators to add via
-- add_keyword_filter() once real moderation queue data shows what's
-- actually needed, rather than guessing a Nepali profanity list here.
insert into public.keyword_filters (keyword, category, severity)
values
  ('fuck', 'hate_speech', 'flag'),
  ('bitch', 'hate_speech', 'flag'),
  ('slut', 'hate_speech', 'flag'),
  ('whore', 'hate_speech', 'flag'),
  ('nigger', 'hate_speech', 'block'),
  ('retard', 'hate_speech', 'flag'),
  ('kill yourself', 'harassment', 'block'),
  ('kys', 'harassment', 'block')
on conflict (keyword) do nothing;
