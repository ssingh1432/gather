-- Page Reviews update-integrity regression test plan.
--
-- Run in an authenticated test environment with two test users and two Pages.
-- This is intentionally a SQL test script rather than an application change.
-- Expected result for each attempted identity mutation: exception
-- 'page review identity cannot be changed'.
--
-- 1. Reviewer updates their own review and changes page_id -> MUST FAIL.
-- 2. Reviewer updates their own review and changes user_id -> MUST FAIL.
-- 3. Reviewer updates rating/body without changing identity -> MUST PASS
--    subject to normal Page Reviews eligibility/RLS rules.
-- 4. Page team moderation updates status without changing identity -> MUST
--    PASS subject to manage_reviews RLS.
-- 5. Owner response updates without changing identity -> MUST PASS through
--    the existing Page Reviews authorization path.
--
-- Verify after deployment that page_reviews(page_id,user_id) remains unique.
select conname, pg_get_constraintdef(oid)
from pg_constraint
where conrelid = 'public.page_reviews'::regclass
  and conname in ('page_reviews_one_per_user', 'page_reviews_page_id_user_id_key');
