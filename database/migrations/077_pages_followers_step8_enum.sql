-- 077_pages_followers_step8_enum.sql
-- Professional Page System — Step 8 (Followers): new enum values only.
--
-- Postgres does not allow a new enum value to be used in the same
-- transaction that added it, so these are split into their own migration,
-- committed before 078 adds the triggers/functions that reference them.
-- Same pattern as 066_notification_types_step14.sql.

begin;

alter type public.notification_type add value if not exists 'page_new_follower';
alter type public.notification_type add value if not exists 'page_new_post';
alter type public.notification_type add value if not exists 'page_follow_invite';

commit;
