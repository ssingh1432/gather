-- 086_pages_notifications_enum_step13.sql
-- Professional Page System — Step 13 (Notifications), part 1 of 2.
-- Enum additions only — per this project's established pattern, new enum
-- values must land in their own committed migration before any function or
-- trigger references them (ALTER TYPE ... ADD VALUE cannot be used in the
-- same transaction as a statement that reads the new value).
alter type public.notification_type add value if not exists 'page_new_event';
alter type public.notification_type add value if not exists 'page_event_reminder';
alter type public.notification_type add value if not exists 'page_verification_updated';
