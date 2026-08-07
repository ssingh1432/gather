-- 081_pages_reviews_step10_enum.sql
-- Professional Page System — Step 10 (Reviews): new enum values only.
-- Split into its own committed migration before 082 uses them, same
-- reason/pattern as 066, 077, 079 (Postgres won't let a new enum value be
-- referenced in the same transaction that added it).

begin;

alter type public.notification_type add value if not exists 'page_review_received';
alter type public.notification_type add value if not exists 'page_review_response';

commit;
