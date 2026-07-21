-- One-time backfill for existing accounts caught by the bug fixed in
-- 020_auto_record_signup_consent: they ticked "I agree" during signup (the
-- checkbox blocks the signUp() call otherwise) but the client never
-- recorded it because they went through the email-confirmation path.
--
-- Applied live via Supabase MCP on 2026-07-21 (affected 4 accounts at the
-- time). Safe to re-run — it only inserts rows that don't already exist.
insert into public.consent_records (user_id, consent_type, policy_version, granted, metadata)
select u.id, t.consent_type, '2026-07-19', true, jsonb_build_object('source', 'backfill_020a')
from public.users u
cross join (values ('privacy_policy'), ('terms_of_service')) as t(consent_type)
where not exists (
  select 1 from public.consent_records c
  where c.user_id = u.id and c.consent_type = t.consent_type and c.granted = true
);
