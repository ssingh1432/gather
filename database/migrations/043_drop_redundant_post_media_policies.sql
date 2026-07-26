-- Migration 043: cleanup only, no functional change.
--
-- 042 originally created media_insert_owner / media_delete_owner as new
-- policies, written from the (mistaken) grep-based conclusion that
-- post_media had no insert/delete RLS policies at all. Turned out
-- media_insert_post_owner and media_delete_owner_or_admin already existed
-- live on the database — just never committed to this repo's migration
-- history — and are functionally equivalent (the delete one is actually
-- better: it includes an admin/mod override). This drops the duplicates
-- rather than leaving two permissive policies doing the same job.
drop policy if exists media_insert_owner on public.post_media;
drop policy if exists media_delete_owner on public.post_media;
