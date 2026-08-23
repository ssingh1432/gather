-- Page Monetization update-hardening regression checks.
-- Execute in a controlled authenticated test environment.
--
-- Expected behavior:
-- 1. User with manage_settings but without manage_monetization cannot set
--    monetization_enabled=true or monetization_status='approved'.
-- 2. User with manage_monetization cannot activate monetization unless the
--    Page is published, has >=100 followers, and is >=30 days old.
-- 3. An eligible manage_monetization user can activate monetization through
--    the existing Page Manage flow.
-- 4. Disabling monetization remains allowed through the existing Page settings
--    path; this migration does not expand or alter that behavior.
-- 5. Ordinary Page settings updates remain unaffected.
--
-- Structural verification:
select tgname, pg_get_triggerdef(oid)
from pg_trigger
where tgrelid = 'public.pages'::regclass
  and not tgisinternal
  and tgname = 'trg_guard_page_monetization_update';
