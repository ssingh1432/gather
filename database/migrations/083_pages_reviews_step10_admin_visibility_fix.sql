-- 083_pages_reviews_step10_admin_visibility_fix.sql
-- Professional Page System — Step 10 follow-up.
--
-- Bug found while wiring the admin review-reports queue: page_reviews_select
-- (082) let a reviewer, the reviewed page's own team, or anyone see a
-- *published* review — but never granted site moderators visibility into a
-- *hidden* review. That's invisible in the common case (most reported
-- reviews are still published when reported) but breaks the admin queue
-- whenever a page team hides a review before/while it's under formal
-- report, since is_admin_or_mod() couldn't see it to embed via
-- page_review_reports -> page_reviews in Supabase's PostgREST join.
--
-- get_page_reviews and get_page_rating_breakdown are SECURITY DEFINER RPCs
-- and unaffected by this — this only fixes direct table selects (used by
-- the admin queue's embedded `review:page_reviews(...)` select).

drop policy if exists page_reviews_select on public.page_reviews;
create policy page_reviews_select on public.page_reviews
  for select using (
    status = 'published'
    or user_id = auth.uid()
    or public.current_user_page_role(page_id) = 'owner'
    or public.current_user_has_page_permission(page_id, 'manage_reviews')
    or public.is_admin_or_mod()
  );
