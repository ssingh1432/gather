# Gather — Maintenance Guide

| Cadence | Task |
|---|---|
| Daily | CI status on main; System Health + Backup Status in admin; moderation and legal queues |
| Weekly | Review `security_events` and login failures; failed notification/email deliveries; storage growth; Supabase advisors (security + performance) |
| Monthly | Verify a backup restore on staging; rotate API keys/PATs; `flutter pub outdated`; dependency security review; review rate-limit thresholds; prune old analytics if size grows |
| Quarterly | Run the penetration checklist; privacy + legal audit (docs/testing); review policy text and bump `kPrivacyPolicyVersion` (update mig. 020 fallback too); load test |
| On Flutter/Supabase upgrade | Run full tests on all platforms; check deprecated plugin APIs; re-test Web and Android builds |

## Data retention (to confirm with counsel)
Account deletion: 14-day grace, then purge. Login attempts: pruned after 1 day. Data exports: link valid 7 days. Moderation evidence and audit logs: keep per legal retention decision (not yet formally set — decide and document).

## Backups
Supabase managed backups + the backup heartbeat cron (reports status in admin). Confirm PITR/retention on the plan in use. Test restores.

## Troubleshooting
| Symptom | Likely cause |
|---|---|
| `42501 permission denied` | missing table `grant` (grants are checked before RLS) |
| Feature works for admin only | RLS policy too narrow, or RPC missing grant |
| Migrations not applied after merge | `SUPABASE_ACCESS_TOKEN` secret missing → CI skipped step |
| Push not arriving | webhook secret mismatch, FCM service account, device token stale |
| Blank images in feed | non-image URL given to image widget |
| Auth emails missing | Send-Email hook secret, Resend domain, `AUTH_EMAIL_FROM` |
