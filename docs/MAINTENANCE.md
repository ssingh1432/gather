# Gather — Maintenance Guide

| Cadence | Task |
|---|---|
| Daily | CI status on main; System Health + Backup Status in admin; moderation and legal queues |
| Weekly | Review `security_events` and login failures; failed notification/email deliveries; storage growth; Supabase advisors (security + performance) |
| Monthly | Verify a backup restore on staging; rotate API keys/PATs; `flutter pub outdated`; dependency security review; review rate-limit thresholds; prune old analytics if size grows |
| Quarterly | Run the penetration checklist; privacy + legal audit (docs/testing); review policy text and bump `kPrivacyPolicyVersion` (update mig. 020 fallback too); load test |
| On Flutter/Supabase upgrade | Run full tests on all platforms; check deprecated plugin APIs; re-test Web and Android builds |

## Data retention (to confirm with counsel)
Account deletion: 14-day grace, then purge. Login attempts: pruned after 1 day. Data exports: link valid 7 days.
**Automatic (cron `prune-operational-logs`, daily 03:30 UTC, migration 134):** `beta_error_logs` > 60 days, `analytics_events` > 400 days. Disable with `select cron.unschedule('prune-operational-logs');`; change periods with a new migration.
**Never pruned automatically (legal decision pending):** `security_events`, `admin_audit_log`, `moderation_actions`, `moderation_evidence`, `legal_*`, `copyright_*`, `media_scan_events`, consent records.

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

## Known issue: `package:flutter/material.dart` deprecation (Flutter 3.47+)
Analyzer (Flutter 3.50) reports ~133 `deprecated_member_use` infos: Material moved to `package:material_ui`. `flutter/material.dart` still works, nothing breaks today. Plan it as its own migration (mechanical import swap + dependency add), done on a branch with a full `flutter test` and Web/Android smoke run. CI prints the analyzer summary (`analyze-summary`, `analyze-by-rule`) as annotations on every run, so progress is visible.
## Known issue: Flutter 3.50 + Android
CI's APK job is pinned to Flutter 3.47.x. Flutter 3.50 (stable since 2026-11-09) fails the Android build with `NoSuchMethodError ApplicationExtension.getDefaultConfig()` because its Gradle plugin targets AGP 9 while `android/settings.gradle.kts` uses AGP 8.9.1 (Flutter 3.41 also fails differently, so do not pin lower). Web, analyze and tests run on current stable and pass. To unpin: migrate `android/` to AGP 9 + Gradle 9 (built-in Kotlin) on a branch and verify with a manual `workflow_dispatch` run.
