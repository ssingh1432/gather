-- Reconciliation: "Page staff can view media" (SELECT on storage.objects
-- for the page-media bucket) already exists on the live database but was
-- never captured in a tracked migration — likely added directly while
-- debugging the page logo/cover upload path (page-media uses
-- `upsert: true`, which needs SELECT in addition to INSERT/UPDATE to
-- resolve whether an object already exists at that path).
--
-- Without this file, a fresh environment built purely from migrations
-- (e.g. a Supabase branch) would be missing this policy even though
-- production has it — the exact kind of drift the project's migration
-- discipline exists to prevent. This migration only makes the tracked
-- schema match what's already live; it changes no behavior in production.
drop policy if exists "Page staff can view media" on storage.objects;
create policy "Page staff can view media" on storage.objects
  for select using (
    bucket_id = 'page-media'
    and public.can_manage_page_media(((storage.foldername(name))[1])::uuid)
  );
