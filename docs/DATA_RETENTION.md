# Gather — Data Retention Policy (DRAFT)

**Status: PROPOSED. Needs owner approval and review by Nepali legal counsel before publishing or enforcing.** Values below are conservative starting points, not legal advice. Only the rows marked "Enforced" are implemented in code today.

| Data | Proposed retention | Enforced today |
|---|---|---|
| Account data after deletion request | Grace period, then purge | Yes — `request_account_deletion` + daily `purge_expired_account_deletions` (03:00 UTC) |
| Client performance events | 90 days | Yes — migration 126 |
| Login attempts (`auth_login_attempts`) | 30 days (lockout only needs 15 minutes) | No |
| Security events (`security_events`) | 12 months | No |
| Admin audit log (`admin_audit_log`) | 24 months | No |
| Moderation actions, appeals, evidence | 24 months after case closed; child-safety/legal-hold evidence kept until released | No |
| Legal complaints and data requests | 5 years or as counsel advises | No |
| Consent records | For the life of the account + 24 months (proof of consent) | No |
| Notifications | 90 days read / 12 months unread | No |
| Data-export files | 7 days after generation | Verify |
| Backups | Per Supabase plan; deleted data may persist in backups until they rotate | n/a |

## Rules
- A legal hold (open complaint, law-enforcement request) overrides every row above.
- Deletion of a user's account must still keep what the law requires (e.g. audit and legal records), anonymised where possible.
- When a row is approved, implement it as a pg_cron job in a numbered migration and update the "Enforced" column.
