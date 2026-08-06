-- 079_pages_messaging_step9_enum.sql
-- Professional Page System — Step 9 (Messaging): new enum values only.
-- Split into its own committed migration before 080 uses them, same
-- reason/pattern as 066 and 077.

begin;

alter type public.notification_type add value if not exists 'page_message_received';
alter type public.notification_type add value if not exists 'page_message_reply';

commit;
