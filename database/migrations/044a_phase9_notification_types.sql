-- Phase 9: Notifications — Step A (enum values only).
--
-- Must run in its own transaction and commit before 044b, which uses these
-- values in trigger functions — same two-transaction rule as 038a/038b
-- (Postgres won't let a new enum value be read in the same transaction
-- that added it).
--
-- New types, one per Phase 9 requirement not already covered by the
-- existing set (new_follower, post_like, post_comment, community_post,
-- post_reply, mention, scheduled_post_published, post_repost, poll_vote,
-- event_reminder):
--   security_alert   - password/email/phone changed, other account-security
--                       events (fed by security_events, see 044b).
--   login_alert      - sign-in from a device/browser we haven't seen before.
--   moderation_alert - a moderation_actions row landed on this user
--                       (warning, suspension, ban, strike, post removed).
--   appeal_update     - status change on a moderation_appeals or
--                       user_appeals row the person filed.
--   report_update     - a report the person filed was resolved/dismissed.
--   admin_broadcast   - a system-wide message sent by an admin.

begin;

alter type public.notification_type add value if not exists 'security_alert';
alter type public.notification_type add value if not exists 'login_alert';
alter type public.notification_type add value if not exists 'moderation_alert';
alter type public.notification_type add value if not exists 'appeal_update';
alter type public.notification_type add value if not exists 'report_update';
alter type public.notification_type add value if not exists 'admin_broadcast';

commit;
