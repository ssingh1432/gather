-- Phase 10 Step 19: Notifications.
--
-- IMPORTANT BUGFIX FIRST: migration 035 (Step 10) inserts a
-- 'scheduled_post_published' notification, but notification_type never
-- had that value — every scheduled post publish would have thrown an
-- invalid-enum-value error, which publish_scheduled_posts()'s per-row
-- exception handler would catch and mark the whole row 'failed' *and
-- roll back the post insert that had already succeeded in the same
-- iteration*. In other words: no scheduled post would ever have actually
-- gone out. Caught here before it shipped to a real user.
--
-- Audit findings (Step 19 proper): notifications_screen.dart already has
-- UI cases for 'post_reply' and 'mention', but nothing in the database
-- ever inserted those types — the triggers were never written. Same for
-- reposts, poll votes, and event reminders. This migration adds all of
-- it. community_post already fires for every post in a community
-- (including content_type='announcement' ones), so that one line item
-- doesn't need new plumbing.

begin;

alter type public.notification_type add value if not exists 'scheduled_post_published';
alter type public.notification_type add value if not exists 'post_repost';
alter type public.notification_type add value if not exists 'poll_vote';
alter type public.notification_type add value if not exists 'event_reminder';

commit;
