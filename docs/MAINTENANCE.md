# Gather — Maintenance Guide

## Scheduled jobs (pg_cron)
| Job | Schedule (UTC) | Function |
|---|---|---|
| publish-scheduled-posts | every minute | `publish_scheduled_posts` |
| publish-scheduled-page-posts | every minute | `publish_scheduled_page_posts` |
| send-event-reminders | every 15 min | `send_event_reminders` |
| send-page-event-reminders | every 15 min | `send_page_event_reminders` |
| backup-integrity-heartbeat | 02:00 daily | `run_backup_heartbeat` |
| purge-expired-account-deletions | 03:00 daily | `purge_expired_account_deletions` |
Check `cron.job_run_details` for failures weekly. Cron functions must not be executable by `anon`/`authenticated` (migration 040).

## Routine
- Weekly: Supabase advisors (security/performance), slow queries, storage growth, failed cron runs.
- Monthly: dependency updates (`flutter pub outdated`), rotate secrets/PATs, restore-test a backup, prune old `security_events`/login attempts per retention policy.
- Quarterly: RLS/GRANT audit, legal documents review, accessibility pass.

## Backups
Supabase managed backups plus the heartbeat in `backup_log`. A restore drill should be documented and rehearsed on staging. **Verify** the project's plan includes PITR.

## Incidents
1. Contain (disable feature flag/revoke key/suspend account). 2. Preserve logs (`security_events`, `admin_audit_log`). 3. Fix via migration/PR. 4. Record outcome. For personal-data breaches, assess notification obligations under Nepal's Privacy Act 2075 with legal counsel.

## Data retention
Account deletion: grace period then purge by cron. Define and publish retention for security logs, login attempts, evidence, and legal records (**Gap** — policy values not codified in repo).
