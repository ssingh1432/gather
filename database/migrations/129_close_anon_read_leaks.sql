-- 129: found by the 2026-11-18 live audit of anon-readable tables.
--
-- anon holds SELECT on several tables; RLS is the only guard. Three policies
-- let signed-out users read data:
--   * post_downloads_select  using (true)  -> anyone could list who downloaded what
--   * story_views_select     using (true)  -> anyone could see who viewed whose story
--   * stories_select         (PUBLIC role)  -> non-expired stories readable without sign-in
-- Fix: authenticated only, and scope rows like the equivalent likes/media policies.
--   * downloads: visible only for posts the caller can already see (posts RLS applies
--     inside the subquery). The "who downloaded" list is an app feature (downloadersOf).
--   * story views: the viewer, the story author, or staff.

alter policy post_downloads_select on public.post_downloads
  to authenticated
  using (exists (select 1 from public.posts p where p.id = post_downloads.post_id));

alter policy story_views_select on public.story_views
  to authenticated
  using (
    viewer_id = auth.uid()
    or exists (select 1 from public.stories s where s.id = story_views.story_id and s.author_id = auth.uid())
    or public.is_admin_or_mod()
  );

alter policy stories_select on public.stories to authenticated;

-- community-media had no MIME allowlist (only a 5 MB cap). The client uploads
-- compressed images only (community avatars/covers, event covers).
update storage.buckets
   set allowed_mime_types = array['image/jpeg','image/png','image/webp','image/gif']
 where id = 'community-media' and allowed_mime_types is null;

comment on table public.page_post_view_events is 'Deny-all to API clients by design (RLS on, no policies). Written only by the SECURITY DEFINER view-recording RPC (migration 084).';
