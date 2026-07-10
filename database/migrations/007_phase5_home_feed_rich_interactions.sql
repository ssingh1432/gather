-- Phase 5: rich, highly-interactive home feed.
-- Adds post metadata (location, feeling, tags), quote/reply-to-post support,
-- threaded comment replies, and a lightweight share log + share_count.

-- ---------------------------------------------------------------------
-- posts: rich metadata + quote/reply-to-post + share_count
-- ---------------------------------------------------------------------
alter table public.posts
  add column if not exists location text,
  add column if not exists feeling text,
  add column if not exists tags text[] not null default '{}',
  add column if not exists reply_to_post_id uuid references public.posts(id) on delete set null,
  add column if not exists share_count integer not null default 0;

comment on column public.posts.location is 'Free-text place tagged on the post, e.g. Kathmandu, Nepal';
comment on column public.posts.feeling is 'Optional "feeling/activity" label, e.g. "happy", "excited"';
comment on column public.posts.tags is 'Free-text hashtag-style tags without the leading #';
comment on column public.posts.reply_to_post_id is 'Set when this post is a quote/reply-share of another post';

create index if not exists idx_posts_reply_to_post_id on public.posts(reply_to_post_id) where reply_to_post_id is not null;
create index if not exists idx_posts_tags on public.posts using gin(tags);

-- guard_post_create() already forbids posting for another user / rate-limits;
-- additionally make sure a quoted post is real and not removed at insert time.
create or replace function public.guard_post_create()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.author_id <> auth.uid() then
    raise exception 'Cannot create posts for another user' using errcode = '42501';
  end if;

  if not public.current_user_is_active() then
    raise exception 'Account is not allowed to create posts' using errcode = '42501';
  end if;

  if new.reply_to_post_id is not null and not exists (
    select 1 from public.posts p where p.id = new.reply_to_post_id and p.is_removed = false
  ) then
    raise exception 'Cannot share a removed or missing post' using errcode = 'P0001';
  end if;

  if (
    select count(*)
    from public.posts p
    where p.author_id = new.author_id
      and p.created_at > now() - interval '1 hour'
  ) >= 10 then
    raise exception 'Post rate limit exceeded' using errcode = 'P0001';
  end if;

  return new;
end;
$$;

-- ---------------------------------------------------------------------
-- post_comments: threaded replies
-- ---------------------------------------------------------------------
alter table public.post_comments
  add column if not exists parent_comment_id uuid references public.post_comments(id) on delete cascade,
  add column if not exists reply_count integer not null default 0;

create index if not exists idx_post_comments_parent_comment_id on public.post_comments(parent_comment_id);

create or replace function public.guard_comment_create()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  post_author uuid;
  parent_post_id uuid;
begin
  if new.user_id <> auth.uid() then
    raise exception 'Cannot comment for another user' using errcode = '42501';
  end if;

  if not public.current_user_is_active() then
    raise exception 'Account is not allowed to comment' using errcode = '42501';
  end if;

  select p.author_id into post_author
  from public.posts p
  where p.id = new.post_id
    and p.is_removed = false;

  if post_author is null then
    raise exception 'Cannot comment on removed or missing post' using errcode = 'P0001';
  end if;

  if public.users_are_blocked(new.user_id, post_author) then
    raise exception 'Cannot interact with this post' using errcode = '42501';
  end if;

  if new.parent_comment_id is not null then
    select c.post_id into parent_post_id
    from public.post_comments c
    where c.id = new.parent_comment_id;

    if parent_post_id is null or parent_post_id <> new.post_id then
      raise exception 'Reply must target a comment on the same post' using errcode = 'P0001';
    end if;
  end if;

  if (
    select count(*)
    from public.post_comments c
    where c.user_id = new.user_id
      and c.created_at > now() - interval '1 hour'
  ) >= 60 then
    raise exception 'Comment rate limit exceeded' using errcode = 'P0001';
  end if;

  return new;
end;
$$;

create or replace function public.maintain_comment_reply_count()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    if new.parent_comment_id is not null then
      update public.post_comments set reply_count = reply_count + 1 where id = new.parent_comment_id;
    end if;
    return new;
  elsif tg_op = 'DELETE' then
    if old.parent_comment_id is not null then
      update public.post_comments set reply_count = greatest(reply_count - 1, 0) where id = old.parent_comment_id;
    end if;
    return old;
  end if;
  return null;
end;
$$;

drop trigger if exists trg_comment_reply_count on public.post_comments;
create trigger trg_comment_reply_count
  after insert or delete on public.post_comments
  for each row execute function public.maintain_comment_reply_count();

-- ---------------------------------------------------------------------
-- post_shares: append-only share log backing posts.share_count
-- ---------------------------------------------------------------------
create table if not exists public.post_shares (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.posts(id) on delete cascade,
  user_id uuid not null references public.users(id) on delete cascade,
  target text not null default 'external',
  created_at timestamptz not null default now()
);

comment on column public.post_shares.target is 'Where the share went: external (system share sheet/copy link) or feed (quote-shared as a new post)';

create index if not exists idx_post_shares_post_id on public.post_shares(post_id);
create index if not exists idx_post_shares_user_id on public.post_shares(user_id);

alter table public.post_shares enable row level security;

drop policy if exists shares_select_visible_beta on public.post_shares;
create policy shares_select_visible_beta on public.post_shares
  for select
  using (
    current_user_has_beta_access()
    and (
      user_id = auth.uid()
      or exists (
        select 1 from public.posts p
        where p.id = post_shares.post_id
          and p.is_removed = false
          and (p.author_id = auth.uid() or not users_are_blocked(auth.uid(), p.author_id))
      )
    )
  );

drop policy if exists shares_insert_self_allowed_beta on public.post_shares;
create policy shares_insert_self_allowed_beta on public.post_shares
  for insert
  with check (
    user_id = auth.uid()
    and current_user_is_active()
    and current_user_has_beta_access()
    and exists (
      select 1 from public.posts p
      where p.id = post_shares.post_id
        and p.is_removed = false
        and not users_are_blocked(auth.uid(), p.author_id)
    )
  );

create or replace function public.maintain_post_share_count()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.posts set share_count = share_count + 1 where id = new.post_id;
  return new;
end;
$$;

drop trigger if exists trg_post_share_count on public.post_shares;
create trigger trg_post_share_count
  after insert on public.post_shares
  for each row execute function public.maintain_post_share_count();

grant select, insert on public.post_shares to authenticated;

-- ---------------------------------------------------------------------
-- get_home_feed / get_community_feed: return the richer post shape,
-- including author avatar and an embedded preview of the quoted post.
-- ---------------------------------------------------------------------
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
  reply_to_removed boolean
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
    (p.reply_to_post_id is not null and rp.id is null) as reply_to_removed
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
  reply_to_removed boolean
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
    (p.reply_to_post_id is not null and rp.id is null) as reply_to_removed
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
$$;

grant execute on function public.get_home_feed(uuid, integer, integer) to authenticated;
grant execute on function public.get_community_feed(uuid, uuid, integer, integer) to anon, authenticated;
