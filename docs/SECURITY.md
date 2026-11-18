# Gather — Security Documentation

## Threat model (summary)
Untrusted client, public Supabase anon key, user-generated content (text, media, links), payments, minors possibly present, regulated market (Nepal).

## Controls in place (verified in repo)
| Area | Control | Where |
|---|---|---|
| Auth | Email verification, password reset, Google sign-in, TOTP 2FA with AAL2 step-up (`require_aal2_if_enrolled`) | auth-email fn, mig. 122 |
| Passwords | ≥8 chars, upper + lower + digit (client); Supabase Auth enforces its own minimum | `password_validator.dart` |
| Brute force | 5 failed logins / 15 min lockout per email, table has no client grants | mig. 012 |
| Devices | Device registry, trusted devices (cap ~90 days), revoke, new-device security event | mig. 122 |
| Authorization | RLS on tables; `SECURITY DEFINER` RPCs with explicit `raise exception` checks; immutable ownership columns | mig. 005, 026, 039, Pages 113/116 |
| Roles | user / moderator / admin; moderator permissions via `has_permission()`; last admin cannot be demoted | mig. 026, 029 |
| Rate limits | Post creation (10/hour), scheduled posts, reports, DM/chat guards | mig. 021, 039, 060 |
| Content safety | Keyword filters (posts, polls, events, communities), sensitive flag, restrict/hide comments, anti-spam, mass-report protection | mig. 021–025, 046 |
| Uploads | Bucket MIME + size allowlists; `post_media.scan_status` and `posts.ai_moderation_status` hook points (no scanner wired yet) | mig. 008, 032, DATABASE.md §6 |
| SSRF | link-preview blocks private/internal targets | link-preview fn |
| Secrets | Only anon key on client. Service-role, Resend, FCM, eSewa, webhook secrets are function secrets / GitHub secrets | functions, CI |
| Payments | eSewa HMAC-SHA256 signing server-side; order integrity hardening | esewa-payment, mig. 120 |
| Messaging | Client-side DM encryption (`dm_crypto`, `cryptography` package) | mig. 124 |
| Audit | `security_events`, `admin_audit_log`, `moderation_actions` | mig. 013, 027, 005 |
| Privilege hygiene | pg_cron functions revoked from PUBLIC; table grants explicit | mig. 040, 041 |
| Transport | HTTPS via Nginx on eiquoab.xyz and Supabase | deployment |

## Known gaps (do not hide these from auditors)
1. **No malware / CSAM scanner** — hooks exist, nothing calls a scanner. Required before wide launch.
2. **Media URLs are not access-controlled per post visibility** (DATABASE.md §9).
3. **page_roles RLS** — policies and grants existed but no migration enabled RLS; fixed by migration 127. Confirm live state first (see MIGRATION_GUIDE.md).
4. **Security headers** (CSP, HSTS, X-Frame-Options, Referrer-Policy) — verify in the Nginx config; not managed in this repo.
5. **CSRF**: API uses bearer JWTs, not cookies, so classic CSRF does not apply; confirm no cookie-auth endpoints exist.
6. **Dependency/secret scanning** is not in CI yet (see Recommended CI additions).
7. Duplicate numeric migration prefixes (104–120) rely on alphabetical order; avoid adding more.

## Secret handling rules
- Never paste tokens into chats, issues, or commits. GitHub PATs and Supabase tokens: single-use, minimal scope, rotate after each session.
- `.env` is bundled as a Flutter asset → treat everything in it as public (anon key, client IDs only).
- Function secrets are set in Supabase (`supabase secrets set`), never in git.

## Incident response (short)
1. Contain: suspend account / revoke device / disable function / rotate secret.
2. Preserve: export `security_events`, `admin_audit_log`, relevant `moderation_evidence`.
3. Assess scope with audit tables; notify affected users and, where legally required, the authority.
4. Fix with a numbered migration + test; record in this file.

## Recommended CI additions
`gitleaks` secret scan, `flutter pub outdated`/OSV dependency scan, `scripts/lint_migrations.py` (added), Supabase `get_advisors` (security) review after each migration batch.
