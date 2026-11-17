# Gather — Admin Guide

## Access
Admins are users with role admin (`is_admin()`); set via `set_user_role` (audited). Admin screens: Admin Dashboard, Moderation, Legal Dashboard, Platform Analytics.

## Dashboard areas
- **Overview** — `admin_overview_stats`: users, posts, reports.
- **Users** — suspend/ban/reinstate, role changes, verification requests.
- **Moderation** — report queue, actions, appeals (see MODERATOR_GUIDE.md).
- **Legal** — complaints (`legal_complaints`), legal data requests (`legal_data_requests`), content removal actions.
- **Security** — recent login failures, security events (needs `view_security`).
- **System** — `admin_system_health`, storage stats/usage, realtime tables, backup heartbeat (`backup_log`).
- **Announcements / notifications** — broadcast to users (needs `manage_announcements`).
- **Analytics** — DAU/MAU/retention/performance/revenue readiness (needs `view_analytics`).

## Managing moderators
Grant or revoke individual permissions with `grant_moderator_permission` / `revoke_moderator_permission`. Keys: `manage_users`, `manage_posts`, `manage_communities`, `manage_reports`, `manage_media`, `manage_legal`, `manage_announcements`, `view_analytics`, `view_security`. Grant least privilege; review `admin_moderator_activity` periodically.

## Routine tasks
| Cadence | Task |
|---|---|
| Daily | Clear report queue; check legal complaints nearing deadlines; check `backup_log` heartbeat |
| Weekly | Review security events and login failures; review moderator activity |
| Monthly | Review keyword filters; review storage usage; rotate tokens/secrets |

## Legal requests
Log every complaint/data request in the Legal Dashboard, record status changes, never act off-platform (e-mail/phone) without recording it. Content removals go through the removal workflow so `content_removal_actions` and `admin_audit_log` stay complete.

## Safety rules
- Don't use SQL console edits for moderation actions; use RPCs so they are audited.
- Never share service-role keys or PATs in chat/tickets.
