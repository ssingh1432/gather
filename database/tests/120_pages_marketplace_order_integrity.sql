-- Page Marketplace order integrity regression checks.
-- Run in an authenticated Page-team test environment.
-- Expected: identity/financial mutations fail; legitimate status/shipping
-- updates remain subject to the existing manage_monetization RLS policy.
--
-- Cases:
-- 1. Change page_id -> MUST FAIL.
-- 2. Change item_id -> MUST FAIL.
-- 3. Change buyer_id -> MUST FAIL.
-- 4. Change quantity -> MUST FAIL.
-- 5. Change amount_cents -> MUST FAIL.
-- 6. Change currency -> MUST FAIL.
-- 7. Change created_at -> MUST FAIL.
-- 8. Change status/shipping_info only -> MUST remain permitted for an
--    authorized Page monetization manager.
select tgname, pg_get_triggerdef(oid)
from pg_trigger
where tgrelid = 'public.page_marketplace_orders'::regclass
  and not tgisinternal
order by tgname;
