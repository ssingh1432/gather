-- Phase 12 Step 1 regression test plan (run as authenticated test users A and B).
--
-- Devices
-- 1. A: select register_device(repeat('a',32), 'Test phone', 'android')  -> is_new = true, trusted = false.
-- 2. A: same call again                                                  -> is_new = false.
-- 3. A: select register_device('short', 'x', 'android')                  -> MUST FAIL invalid_device_id.
-- 4. B: select * from user_devices                                       -> MUST return none of A's rows.
-- 5. B: insert/update/delete on user_devices directly                    -> MUST FAIL (no grants).
-- 6. A (no 2FA): set_device_trust(repeat('a',32), true, 30); is_device_trusted(...) -> true.
-- 7. A: set_device_trust(..., true, 9999) -> trusted_until capped at ~90 days.
-- 8. A: revoke_device(<id>); is_device_trusted(...) -> false; list_my_devices().revoked = true.
-- 9. A: register_device again on a revoked device -> is_new = true, trust cleared.
-- 10. security_events contains new_device_login / device_trusted / device_revoked rows for A.
--
-- Step-up (A with a verified TOTP factor)
-- 11. Session at aal1: set_device_trust / revoke_device -> MUST FAIL mfa_required.
-- 12. After challengeAndVerify (aal2): same calls -> MUST PASS.
--
-- Anonymous
-- 13. anon: every function above -> MUST FAIL (no execute grant).
select proname, prosecdef
from pg_proc
where pronamespace = 'public'::regnamespace
  and proname in ('register_device','list_my_devices','is_device_trusted',
                  'set_device_trust','revoke_device','require_aal2_if_enrolled');
