# Gather — Security Documentation

Scope: what is implemented in the repository today. Items marked **Gap** or **Verify** are not confirmed in code and should be checked before launch.

## 1. Authentication & sessions
- Supabase Auth (email/password, Google Sign-In). Google sign-in intentionally bypasses the closed-beta email allowlist (product decision).
- **Login lockout:** `check_login_lockout(email)` blocks sign-in after **5 failed attempts in 15 minutes** (migration 012); attempts recorded by `record_login_attempt`; failures visible to admins via `admin_recent_login_failures`.
- **MFA:** `mfa_service.dart`; `require_aal2_if_enrolled` enforces AAL2 for enrolled users (migration 122).
- **Devices:** `user_devices`, `register_device`, `list_my_devices`, `revoke_device`, `set_device_trust`, `is_device_trusted`.
- Secrets: only the Supabase URL and anon key are in the client `.env`; service-role keys must live only in Edge Function/CI secrets.

## 2. Authorization
- RLS on all tables; admin/moderator checks via `is_admin()` and `has_permission(key)`.
- Moderator permission keys (`moderator_permissions`): `manage_users`, `manage_posts`, `manage_communities`, `manage_reports`, `manage_media`, `manage_legal`, `manage_announcements`, `view_analytics`, `view_security`. Table is not directly readable by clients; managed through `grant_moderator_permission` / `revoke_moderator_permission`.
- Role changes: `set_user_role` (audited).
- Pages/communities: immutable `page_id`/`author_id` after creation, explicit `raise exception` checks in analytics RPCs.

## 3. Abuse protection
- Rate limits in triggers (posts, reports, community actions); `guard_report_create` plus mass-reporting protection.
- Keyword filters (`check_keyword_filters`, `auto_moderate_*`), media moderation queue (`queue_media_moderation`, `record_media_moderation_result`).
- Anti-spam and fake-account detection (migration 025).

## 4. Data protection
- Consent records (`consent_records`), signup consent auto-recorded (migration 020).
- Account deletion with grace period (`request_account_deletion`, `cancel_account_deletion`, daily `purge_expired_account_deletions`).
- Data export via `data-export` Edge Function and `request_data_export`.
- DM text E2EE (`dm_user_keys`); voice/media encryption is **Verify**.
- Local sensitive storage: `secure_local_storage.dart`.

## 5. Storage
- Per-bucket MIME and size allowlists plus storage policies. Missing SELECT policies previously broke upserts (fixed for all five original buckets). Re-audit any new bucket for SELECT/INSERT/UPDATE/DELETE policies.
- Virus-scan hook: moderation queue exists; actual scanner integration is **Gap/Verify**.

## 6. Logging & audit
- `security_events` (security), `admin_audit_log` (admin actions), `moderation_actions`, `content_removal_actions`.
- Admin views: `admin_system_health`, `admin_storage_stats`, `admin_realtime_tables`.

## 7. Known risks / open items
1. **PAT hygiene:** GitHub tokens have been shared in plaintext. Rotate after every session; prefer short-lived fine-grained tokens.
2. **Migration drift:** direct `execute_sql` changes diverge live DB from repo. Use `apply_migration` or the CI step.
3. ~~CI migrate step no-ops without `SUPABASE_ACCESS_TOKEN`~~ — now fails the job (the secret is configured).
4. Analyzer warnings are ratcheted: CI fails if the count exceeds `flutter_app/analysis_warning_baseline.txt`.
5. HTTPS/HSTS/CSP headers depend on the VPS Nginx config, not the repo — **Verify**.
6. No automated RLS regression suite beyond the few SQL tests in `database/tests/`.

## 8. Supabase advisor findings (security, 2026-11-17)
| Finding | Status |
|---|---|
| `function_search_path_mutable` (7 functions) | Fixed in migration 127 |
| `log_security_event` callable by anon with arbitrary data | Constrained in migration 127 (anon may only log `password_reset_requested`; event-type format and 4 KB metadata cap) |
| `rls_enabled_no_policy`: `allowed_beta_emails`, `auth_login_attempts`, `page_post_view_events`, `repo_migrations` | Intentional deny-all (access only via SECURITY DEFINER functions/service role) |
| `anon_security_definer_function_executable` (20) | Mostly intentional (login lockout/attempt, RLS helper predicates, `trending_hashtags`). Re-review each before revoking: RLS policies evaluate helpers as the calling role |
| `authenticated_security_definer_function_executable` (172) | By design (RPC API); each function must do its own authorization check |
| `auth_allow_anonymous_sign_ins` (policies without `TO authenticated`) | Advisory. Low risk while anonymous sign-ins are disabled; tighten policies with explicit `TO authenticated` over time |
| `auth_leaked_password_protection` disabled | **Open — dashboard setting** (Auth > Providers > Email; may require Pro plan) |

**Open item — webhook secret:** the `notification-dispatch` database-webhook trigger on `public.notifications` stores a service-role JWT and a short, guessable shared secret (`x-webhook-secret`) in its definition. Replace the shared secret with a long random value (update both the webhook header and the Edge Function secret). The service-role JWT in the trigger can only be changed by rotating the project JWT secret/keys; keep it out of repo snapshots (the baseline generator documents this).

## 9. Penetration-test checklist (manual)
- Anonymous access: call each table/RPC as `anon`; expect denial except intended public reads.
- Cross-user access: user A reading/updating user B's rows (profile, DMs, devices, drafts, exports).
- Privilege escalation: non-admin calling `set_user_role`, `ban_user`, `grant_moderator_permission`.
- Storage: upload disallowed MIME/oversize; read private buckets unauthenticated.
- Lockout bypass: vary email case/whitespace; confirm lowercase/trim normalisation.
- Realtime: subscribe to other users' DM/notification channels.
- Edge Functions: call without JWT, with another user's JWT.
