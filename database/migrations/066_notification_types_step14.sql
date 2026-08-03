-- 066_notification_types_step14.sql
-- Step 14: Community Notifications — new enum values only.
--
-- These must be committed in their own transaction before any trigger
-- function can reference them (Postgres does not allow a new enum value
-- to be used in the same transaction that added it). Migration 067 adds
-- the actual triggers.
--
-- community_invite already existed in the enum from earlier work but had
-- no DB trigger wired to it yet — 067 fixes that too.

begin;

alter type public.notification_type add value if not exists 'community_join_request';
alter type public.notification_type add value if not exists 'community_join_update';
alter type public.notification_type add value if not exists 'community_role_changed';
alter type public.notification_type add value if not exists 'community_warning';
alter type public.notification_type add value if not exists 'community_ban';
alter type public.notification_type add value if not exists 'community_announcement';
alter type public.notification_type add value if not exists 'community_event_created';

commit;
