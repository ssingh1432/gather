-- 107_pages_rich_visitor_posts.sql
-- Professional Page System — Stage 8 (rich visitor posts + engagement)
--
-- This migration was applied directly against the live database (via the
-- Supabase SQL editor, outside the normal Claude Code session) before it
-- was captured in git. This file reconciles the repo's migration history
-- with what is actually live: it adds media/event support to visitor
-- posts and a like/comment/share engagement layer, matching the shape
-- `page_posts.media` already uses. Every statement is written to be safe
-- to re-run against the already-migrated database.

-- ── page_visitor_posts: content type, media, and optional event ──────────
alter table public.page_visitor_posts
  add column if not exists content_type text not null default 'text',
  add column if not exists media jsonb not null default '[]'::jsonb,
  add column if not exists event_id uuid references public.page_events(id) on delete set null;

do $$ begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'page_visitor_posts_content_type_check'
      and conrelid = 'public.page_visitor_posts'::regclass
  ) then
    alter table public.page_visitor_posts add constraint page_visitor_posts_content_type_check
      check (content_type in ('text', 'image', 'video', 'document', 'event'));
  end if;
end $$;

-- NOTE: as originally applied, this migration also tightened
-- page_visitor_posts_content_check to require non-empty content/media/
-- event_id at INSERT time. That directly conflicts with the storage
-- bucket policies below, which require the post row to already exist
-- before a media file can be uploaded — making a caption-less
-- image/video/document post impossible to create. See
-- 109_fix_page_visitor_post_media_upload_ordering.sql, which replaces
-- that constraint with a length-only check and is included in this
-- migration sequence rather than repeated here.

-- ── Likes ──────────────────────────────────────────────────────────────
create table if not exists public.page_visitor_post_likes (
  post_id uuid not null references public.page_visitor_posts(id) on delete cascade,
  user_id uuid not null references public.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (post_id, user_id)
);

alter table public.page_visitor_post_likes enable row level security;

drop policy if exists page_visitor_post_likes_select on public.page_visitor_post_likes;
create policy page_visitor_post_likes_select on public.page_visitor_post_likes
for select using (
  exists (select 1 from public.page_visitor_posts p where p.id = page_visitor_post_likes.post_id and p.status = 'published')
);

drop policy if exists page_visitor_post_likes_insert on public.page_visitor_post_likes;
create policy page_visitor_post_likes_insert on public.page_visitor_post_likes
for insert with check (
  user_id = auth.uid()
  and exists (
    select 1 from public.page_visitor_posts p
    join public.page_followers f on f.page_id = p.page_id and f.user_id = auth.uid()
    where p.id = page_visitor_post_likes.post_id and p.status = 'published'
  )
);

drop policy if exists page_visitor_post_likes_delete on public.page_visitor_post_likes;
create policy page_visitor_post_likes_delete on public.page_visitor_post_likes
for delete using (
  user_id = auth.uid()
  or current_user_has_page_permission(
       (select p.page_id from public.page_visitor_posts p where p.id = page_visitor_post_likes.post_id),
       'manage_content'
     )
);

-- ── Comments ───────────────────────────────────────────────────────────
create table if not exists public.page_visitor_post_comments (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.page_visitor_posts(id) on delete cascade,
  user_id uuid not null references public.users(id) on delete cascade,
  content text not null,
  is_hidden boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.page_visitor_post_comments enable row level security;

drop policy if exists page_visitor_post_comments_select on public.page_visitor_post_comments;
create policy page_visitor_post_comments_select on public.page_visitor_post_comments
for select using (
  exists (select 1 from public.page_visitor_posts p where p.id = page_visitor_post_comments.post_id and p.status = 'published')
  and (
    not is_hidden
    or user_id = auth.uid()
    or current_user_has_page_permission(
         (select p.page_id from public.page_visitor_posts p where p.id = page_visitor_post_comments.post_id),
         'manage_content'
       )
  )
);

drop policy if exists page_visitor_post_comments_insert on public.page_visitor_post_comments;
create policy page_visitor_post_comments_insert on public.page_visitor_post_comments
for insert with check (
  user_id = auth.uid()
  and exists (
    select 1 from public.page_visitor_posts p
    join public.page_followers f on f.page_id = p.page_id and f.user_id = auth.uid()
    where p.id = page_visitor_post_comments.post_id and p.status = 'published'
  )
);

drop policy if exists page_visitor_post_comments_delete on public.page_visitor_post_comments;
create policy page_visitor_post_comments_delete on public.page_visitor_post_comments
for delete using (
  user_id = auth.uid()
  or current_user_has_page_permission(
       (select p.page_id from public.page_visitor_posts p where p.id = page_visitor_post_comments.post_id),
       'manage_content'
     )
);

-- ── Shares ─────────────────────────────────────────────────────────────
create table if not exists public.page_visitor_post_shares (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.page_visitor_posts(id) on delete cascade,
  user_id uuid not null references public.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

alter table public.page_visitor_post_shares enable row level security;

drop policy if exists page_visitor_post_shares_select on public.page_visitor_post_shares;
create policy page_visitor_post_shares_select on public.page_visitor_post_shares
for select using (
  user_id = auth.uid()
  or exists (
    select 1 from public.page_visitor_posts p
    where p.id = page_visitor_post_shares.post_id and current_user_has_page_permission(p.page_id, 'view_analytics')
  )
);

drop policy if exists page_visitor_post_shares_insert on public.page_visitor_post_shares;
create policy page_visitor_post_shares_insert on public.page_visitor_post_shares
for insert with check (
  user_id = auth.uid()
  and exists (select 1 from public.page_visitor_posts p where p.id = page_visitor_post_shares.post_id and p.status = 'published')
);

-- ── Storage: visitor-post media attachments ───────────────────────────
-- Path convention: {page_id}/{post_id}/{filename}. The post row must
-- already exist (see 109_fix_page_visitor_post_media_upload_ordering.sql
-- for why insert order matters here).
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'page-visitor-media',
  'page-visitor-media',
  true,
  26214400,
  array[
    'image/jpeg', 'image/png', 'image/webp', 'image/gif',
    'video/mp4', 'video/quicktime', 'video/webm',
    'application/pdf', 'application/msword',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
  ]
)
on conflict (id) do nothing;

drop policy if exists page_visitor_post_media_insert on storage.objects;
create policy page_visitor_post_media_insert on storage.objects
for insert with check (
  bucket_id = 'page-visitor-media'
  and exists (
    select 1 from public.page_visitor_posts p
    join public.page_followers f on f.page_id = p.page_id and f.user_id = auth.uid()
    where p.id = ((storage.foldername(objects.name))[2])::uuid
      and p.page_id = ((storage.foldername(objects.name))[1])::uuid
      and p.author_id = auth.uid()
  )
);

drop policy if exists page_visitor_post_media_update on storage.objects;
create policy page_visitor_post_media_update on storage.objects
for update using (
  bucket_id = 'page-visitor-media'
  and exists (
    select 1 from public.page_visitor_posts p
    where p.id = ((storage.foldername(objects.name))[2])::uuid
      and (p.author_id = auth.uid() or current_user_has_page_permission(p.page_id, 'manage_content'))
  )
);

drop policy if exists page_visitor_post_media_delete on storage.objects;
create policy page_visitor_post_media_delete on storage.objects
for delete using (
  bucket_id = 'page-visitor-media'
  and exists (
    select 1 from public.page_visitor_posts p
    where p.id = ((storage.foldername(objects.name))[2])::uuid
      and (p.author_id = auth.uid() or current_user_has_page_permission(p.page_id, 'manage_content'))
  )
);
-- Bucket is public, so reads are served directly by the storage CDN and
-- don't need a SELECT policy on storage.objects.
