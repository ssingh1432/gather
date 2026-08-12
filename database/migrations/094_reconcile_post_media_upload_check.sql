-- Migration 094: reconcile can_upload_post_media() with what was actually
-- applied live on 2026-08-12, and remove the debug-only side effect that
-- shipped with it.
--
-- Context (see the post-publishing root-cause investigation):
-- Two migrations were applied directly to production on 2026-08-12 and
-- were never committed to this repo:
--   fix_post_media_storage_insert_policy_security_definer
--   temp_debug_post_media_upload_check
--
-- The first made can_upload_post_media() (the storage RLS check function
-- backing the "Users can upload post-media for their own posts" policy on
-- storage.objects) SECURITY DEFINER with search_path pinned to `public`
-- and fully schema-qualified table references. That part is legitimate
-- and is reconciled here.
--
-- The second had it also INSERT a row into public._debug_post_media_upload_check
-- on every single check — including `current_setting('request.jwt.claims',
-- true)`, i.e. the caller's raw JWT claims — into a table with row-level
-- security disabled. That must not stay in production: it logs sensitive
-- token contents to a table nothing governs, on every media upload
-- attempt from every user. This migration keeps the SECURITY DEFINER fix
-- and drops the debug logging and the table entirely.
create or replace function public.can_upload_post_media(p_post_id uuid)
returns boolean
language plpgsql
stable security definer
set search_path = public
as $$
declare
  v_post_exists boolean;
  v_sched_exists boolean;
begin
  v_post_exists := exists (
    select 1 from public.posts p
    where p.id = p_post_id and p.author_id = auth.uid()
  );
  v_sched_exists := exists (
    select 1 from public.scheduled_posts sp
    where sp.id = p_post_id and sp.user_id = auth.uid()
  );
  return v_post_exists or v_sched_exists;
end;
$$;

drop table if exists public._debug_post_media_upload_check;
