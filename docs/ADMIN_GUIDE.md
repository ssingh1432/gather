# Gather — Admin Guide

Access: users with `role = 'admin'`. Moderators see a subset based on `moderator_permissions`.
Admin dashboard sections (`admin_dashboard_screen.dart`): Overview, Users, Posts, Communities, Audit Log, Platform Analytics, Security, Storage, Realtime Status, System Health, Backup Status, Moderator Management, Role Management, Permissions, Announcements, Notifications, Settings. Legal and moderation queues have their own screens (Legal dashboard, Moderation).

## Daily
1. **Overview / System Health / Backup Status** — anything red? Backup heartbeat (cron) should be recent.
2. **Moderation queue** — oldest first (see MODERATOR_GUIDE.md).
3. **Legal dashboard** — new complaints and data requests; assign yourself.
4. **Security** — recent login failures, new-device events.

## Roles & permissions
- Promote/demote in **Role Management**. Only admins can grant admin/moderator; the last admin cannot be demoted.
- **Permissions** tab sets per-moderator capabilities (e.g. `view_security`). Grant least privilege.
- Every change is written to the **Audit Log**.

## Users
Search, view status (`active`, `suspended`, `banned`, `pending_deletion`), strikes, verification, badges.
Actions: warn, strike (auto-escalates 3→3-day suspension, 5→14-day, 7+→ban), suspend, ban, reinstate. Reinstating does not clear strikes. Award/revoke badges. Approve verification requests (sets `is_verified`).

## Content
Posts tab: hide/remove, view **edit history** and restore text to a prior version.

## Communications
- **Announcements / Admin broadcast**: `admin_send_broadcast(title, body, audience)` creates notifications → push + email via dispatch function.
- **Notifications** tab shows delivery stats.

## Legal & data requests (Nepal)
Frameworks are data: ETA 2063, Privacy Act 2075, Social Media Directive, Other. To add a future law: `insert into legal_frameworks (code, name, description)`.
Complaint lifecycle starts at `submitted`; record resolution notes and assignee. Data requests start at `received`. Keep evidence and timestamps; do not delete complaint rows.
Account deletion: user request → `pending_deletion` → 14-day grace → automatic purge. Data export: signed link valid 7 days.

## Analytics
Platform Analytics tab: DAU/MAU, activity series, retention cohorts, engagement, moderation analytics, uploads, crash analytics, performance, revenue readiness.

## Do not
Run SQL changes directly on production (use migrations); share the service-role key; post tokens in chat; edit audit tables.
