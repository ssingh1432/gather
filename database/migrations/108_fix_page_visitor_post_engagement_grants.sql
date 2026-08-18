-- 108_fix_page_visitor_post_engagement_grants.sql
-- Professional Page System — Stage 8 (rich visitor posts + engagement), bugfix
--
-- 107_pages_rich_visitor_posts.sql created page_visitor_post_likes,
-- page_visitor_post_comments, and page_visitor_post_shares with RLS
-- policies but no table-level GRANTs. Postgres checks table-level GRANT
-- before RLS is ever evaluated, so every request from the app failed with
-- 42501 "permission denied for table page_visitor_post_likes" — this is
-- the same missing-GRANT bug class that previously blocked post_media
-- uploads (see reconcile_post_media_upload_check.sql). RLS policies alone
-- do not grant access.
--
-- Applied live via apply_migration on 2026-08-18; this file brings the
-- repo's migration history back in sync with the database.

grant select, insert, update, delete on public.page_visitor_post_comments to authenticated;
grant select, insert, delete on public.page_visitor_post_likes to authenticated;
grant select, insert on public.page_visitor_post_shares to authenticated;
