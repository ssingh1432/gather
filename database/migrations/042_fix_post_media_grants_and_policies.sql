-- Migration 042: fix post_media so photo/video/audio/document attachments
-- can actually be added to a post.
--
-- Root cause: public.post_media has only ever had SELECT grants/policies
-- (005_phase2, 006_phase4, 026_phase8). No migration ever granted INSERT/
-- UPDATE/DELETE to `authenticated`, and no RLS policy ever existed for
-- those operations either. `PostRepository.addPostMedia` (client) does a
-- delete-then-insert into this table for every image/video/audio/document
-- attached to a post, so every non-text post has been failing at either
-- the table-grant layer or the RLS layer since post_media was introduced.
-- Plain text-only posts never touch post_media, which is why they're the
-- one post type that has kept working.
--
-- Table privileges (same pattern/rationale as migration 041).
grant select, insert, delete on public.post_media to authenticated;

-- Belt-and-braces: make sure RLS is actually on (it must already be,
-- since the existing SELECT policies would be no-ops otherwise, but this
-- is a no-op if so and cheap insurance if not).
alter table public.post_media enable row level security;

-- Only the owner of the parent post may attach/remove media on it, and
-- only while the post itself is still active (mirrors posts_update_owner
-- semantics from migration 005) — no editing media on a removed post.
drop policy if exists media_insert_owner on public.post_media;
create policy media_insert_owner on public.post_media for insert
with check (
  exists (
    select 1 from public.posts p
    where p.id = post_id
      and p.author_id = auth.uid()
      and p.is_removed = false
  )
);

drop policy if exists media_delete_owner on public.post_media;
create policy media_delete_owner on public.post_media for delete
using (
  exists (
    select 1 from public.posts p
    where p.id = post_id
      and p.author_id = auth.uid()
      and p.is_removed = false
  )
);
