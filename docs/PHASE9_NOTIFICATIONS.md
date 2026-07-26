# Phase 9 — Notifications

Honesty up front, same as Phase 10's testing doc: this sandbox has no
Flutter SDK, no device/emulator, and no Supabase CLI/dashboard session, so
none of this has run against the live project or through `flutter analyze`.
The DB migrations are plain SQL reviewed against the actual schema (column
names, existing triggers, and RLS/grant conventions were all read from the
live migration history before writing new ones — see the bugfix in 044b).
The edge function and Flutter changes are new code that needs your CI run
and a manual pass before it ships. Nothing here should be taken as "already
verified working."

## 1. What Phase 9 covers, and how

| Requirement | Mechanism |
|---|---|
| Push Notifications | `notification-dispatch` edge function → FCM HTTP v1 |
| Realtime Notifications | `notifications` table added to `supabase_realtime` publication (044b); `NotificationsScreen` subscribes |
| Email Notifications | Same edge function → Resend, for the categories in `EMAIL_TYPES` |
| Security Alerts | `security_events` insert trigger → `security_alert` (always on) |
| Login Alerts | `record_login_device()` RPC, called by the client after sign-in → `login_alert` (always on) |
| Moderation Alerts | `moderation_actions` insert trigger → `moderation_alert` |
| Appeal Updates | `moderation_appeals` / `user_appeals` status-change triggers → `appeal_update` |
| Report Updates | `reports` status-change trigger → `report_update` (to the reporter, not the reported user) |
| Mention Notifications | Already existed (038b) — untouched |
| Community Notifications | Already existed (003/038b) — untouched |
| Admin Broadcast | `admin_send_broadcast()` RPC → `admin_broadcast`, fanned out to every matching user; composer added to Admin Dashboard → Notifications tab |

Delivery is gated by `users.notification_settings` (jsonb, already existed
for in-app display; the edge function now also reads it to decide push/
email). Two new keys were added to the Settings screen: `moderation_alerts`
and `admin_broadcasts`. `security_alert`/`login_alert` are intentionally
**not** gated — shown in Settings as always-on, can't be disabled, same as
every major app's security-notification convention.

Social/engagement types (likes, comments, follows, mentions, community
posts) stay **push-only** — no email — to avoid turning email into a second
noisier feed. Security, login, moderation, appeal, and report updates get
both push and email, since those are the ones worth seeing even if the app
isn't opened for a few days.

## 2. Bug found and fixed while auditing for this phase

`moderation_actions.action` had a `check` constraint (migration 005)
allowing only `('report_resolved','post_soft_removed','user_suspended')`.
Migration 022 (Phase 6) added `issue_warning`/`add_strike`/`ban_user`/
`reinstate_user`, which insert `'warning_issued'`, `'strike_added'`,
`'user_banned'`, `'user_reinstated'` — none of which were in the allowed
list, and no later migration widened it. Every call to those four RPCs
should have been throwing a check-constraint violation since 022 shipped.
044b drops and recreates the constraint with the full set.

**Please check your production logs / Sentry (if wired) for
`moderation_actions_action_check` violations** — if this bug has been live,
there may be warnings/strikes/bans/reinstatements that admins believed
succeeded but silently rolled back. Worth a quick audit of the admin
moderation UI's error handling too, in case failures were being swallowed.

## 3. Manual setup required — cannot be done from a migration or from here

**Edge function secrets** (Supabase Dashboard → Edge Functions →
`notification-dispatch` → Secrets, or `supabase secrets set`):

- `FCM_SERVICE_ACCOUNT_JSON` — full Firebase service-account JSON, one line.
  Firebase Console → Project Settings → Service Accounts → Generate new
  private key. This is a secret credential — never commit it.
- `FCM_PROJECT_ID` — your Firebase project ID.
- `RESEND_API_KEY` — same one `auth-email` already uses, or a new one.
- `NOTIFICATION_WEBHOOK_SECRET` — any random string you generate; must
  match the header you set on the Database Webhook below.
- `NOTIFICATION_EMAIL_FROM` — optional, defaults to `Gather <noreply@eiquoab.xyz>`.

**Database Webhook** (Supabase Dashboard → Database → Webhooks → Create):
- Table: `public.notifications`
- Events: `INSERT` only
- Type: Edge Function → `notification-dispatch`
- HTTP Headers: add `x-webhook-secret: <same value as NOTIFICATION_WEBHOOK_SECRET>`

This is a dashboard-managed hook rather than a `pg_net` trigger in SQL,
same pattern as the existing `auth-email` Send Email Hook — deliberately
not hardcoded in a migration because the service role key / hook signing
Supabase manages for these is not something a migration file should carry.

**Deploy the function**: `supabase functions deploy notification-dispatch`
(needs Supabase CLI + project link, which this sandbox doesn't have).

## 4. Database changes

- `044a_phase9_notification_types.sql` — 6 new `notification_type` enum
  values, own transaction (same two-transaction rule as 038a/038b).
- `044b_phase9_notifications_delivery.sql` — the constraint bugfix above,
  `notifications.metadata jsonb`, Realtime enablement, `user_known_devices`,
  `admin_broadcasts`, 5 new trigger functions, `record_login_device()`,
  `admin_send_broadcast()`. All new tables have explicit `grant select to
  authenticated` — see migration 041 for why this project doesn't rely on
  default privileges.

Apply both, in order, same as any other migration pair in this repo.

## 5. What to test once secrets + webhook are wired up

- [ ] Trigger each notification type for real and confirm: in-app row
      appears instantly (Realtime) even with the screen already open,
      push arrives on a physical device/simulator with a valid FCM token,
      email arrives for the 5 `EMAIL_TYPES` and does **not** arrive for
      likes/comments/follows/mentions/community posts.
- [ ] Toggle `moderation_alerts` and `admin_broadcasts` off in Settings,
      confirm push stops for those categories, confirm security/login
      alerts still arrive regardless (they're not gated).
- [ ] Sign in from a genuinely new device (or clear secure storage) and
      confirm exactly one `login_alert` fires, not one per sign-in.
- [ ] Trigger `issue_warning`/`add_strike`/`ban_user`/`reinstate_user`
      end-to-end and confirm no constraint violation (the 044b bugfix) and
      that the target user gets a `moderation_alert`.
- [ ] Resolve a report and confirm the *reporter* (not the reported user)
      gets `report_update`.
- [ ] Change a `moderation_appeals` or `user_appeals` row's status and
      confirm the appellant gets `appeal_update` — but not on the initial
      `pending`/`submitted` insert, only on the status change.
- [ ] Send an admin broadcast to each audience (`all`/`moderators`/
      `admins`) from the Admin Dashboard composer, confirm recipient count
      matches expectations and only matching-role users got notified.
- [ ] Revoke/expire an FCM token on device and confirm the edge function
      clears `users.fcm_token` on the resulting `UNREGISTERED` response
      instead of retrying forever.
- [ ] `flutter analyze` + `flutter test` via CI, as always.
