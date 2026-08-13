-- Migration 096: persist the pending post id on the draft row so a
-- publish that's interrupted by an app kill/crash (not just an
-- in-session retry) can resume the SAME post instead of creating a
-- second one.
--
-- _pendingPostId in create_post_screen.dart previously lived only in
-- Dart State, so it survived same-session retries (createPost() is
-- skipped via `??=` on a second _publish() call) but not an app
-- restart. The server-side duplicate guard (guard_duplicate_post_content)
-- does not help here: it explicitly returns early for empty
-- text_content, i.e. it provides zero protection for a media-only post
-- (the single most common post-with-attachment case) — see its
-- definition. And even for text posts, it only matches identical
-- text_content within a 10-minute window, so a retry where the user
-- edited their text before tapping Publish again would still slip past
-- it. Storing pending_post_id closes both gaps by letting the composer
-- resume the exact same row rather than relying on content matching.
alter table public.post_drafts
  add column if not exists pending_post_id uuid references public.posts(id) on delete set null;
