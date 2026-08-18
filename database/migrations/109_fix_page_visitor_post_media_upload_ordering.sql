-- 109_fix_page_visitor_post_media_upload_ordering.sql
-- Professional Page System — rich visitor posts, bugfix
--
-- 107_pages_rich_visitor_posts.sql's page_visitor_posts_content_check
-- requires non-empty content, media, or event_id at INSERT time. But the
-- page-visitor-media storage bucket's own RLS policy requires a matching
-- page_visitor_posts row to already exist before it will accept an
-- upload (the post id is a storage path segment: {page_id}/{post_id}/...).
--
-- That's a deadlock for a caption-less image/video/document post: the
-- row must be created first with an empty `media` array (to learn its
-- id), but the check constraint forbids a row that is simultaneously
-- caption-less and media-less at that point. This affects both
-- page_visitor_post_composer_screen.dart's _submit() (creates the post
-- row, then uploads media, then updateMedia) and any other client using
-- the same two-phase flow — "must have text, media, or an event" needs
-- to be enforced client-side rather than at INSERT time.
--
-- Applied live via apply_migration on 2026-08-18; this file brings the
-- repo's migration history back in sync with the database.

alter table public.page_visitor_posts drop constraint if exists page_visitor_posts_content_check;
alter table public.page_visitor_posts add constraint page_visitor_posts_content_check
  check (char_length(trim(both from content)) <= 5000);
