-- Phase 12 Step 2 regression test plan (authenticated test users A and B; one admin).
--
-- Username
-- 1. A: update users set username='hacked' where id=A        -> MUST FAIL "Use change_username()".
-- 2. A: change_username('Bad Name') / ('ab') / ('admin')     -> MUST FAIL (format / reserved).
-- 3. A: change_username('a_new_name')                         -> MUST PASS; username_history row; security_events 'username_changed'.
-- 4. A: change_username('another_one') immediately           -> MUST FAIL (30-day cooldown).
-- 5. B: change_username('a_new_name')                         -> MUST FAIL taken.
-- 6. B: change_username(<A's old name>) within 90 days        -> MUST FAIL not available.
-- 7. Admin: update users set username=... for A               -> MUST PASS (admin bypass).
--
-- Verification
-- 8. A: update users set is_verified=true                     -> MUST FAIL.
-- 9. A: insert user_verification_requests(status='approved')  -> MUST FAIL (RLS).
-- 10. A: insert pending request twice                         -> second MUST FAIL.
-- 11. Admin: update request set status='approved'             -> users.is_verified=true, verified_at set, admin_audit_log row.
-- 12. Admin: set status back to 'rejected'                    -> users.is_verified=false.
-- 13. B: select from storage.objects where bucket_id='verification-docs' and path is A's -> MUST return nothing.
--
-- Links
-- 14. A: insert 6th link -> MUST FAIL; insert url 'javascript:alert(1)' -> MUST FAIL (check constraint).
-- 15. B (not following, A private) select A's links -> MUST return none; blocked user -> none.
--
-- Badges
-- 16. A: insert into user_badges -> MUST FAIL (no grant). A: admin_award_badge(...) -> MUST FAIL.
-- 17. Admin: admin_award_badge(A,'creator') -> PASS + audit row; admin_revoke_badge -> PASS.
--
-- Theme
-- 18. A: update users set profile_theme='neon' -> MUST FAIL check; 'ocean' -> PASS.
select proname from pg_proc
where pronamespace='public'::regnamespace
  and proname in ('change_username','validate_username','admin_award_badge','admin_revoke_badge',
                  'guard_profile_identity_columns','apply_verification_decision');
