-- 054a_community_invites_notification_type.sql
-- Must run in its own transaction and commit before 054b, which uses this
-- value inside a trigger/function body — same two-transaction rule as
-- 038a/038b and 044a/044b (Postgres won't let a new enum value be read in
-- the same transaction that added it).

begin;

alter type public.notification_type add value if not exists 'community_invite';

commit;
