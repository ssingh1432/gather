-- 070_fix_rsvp_write_visibility_gap.sql
-- Step 16 Testing — security test found a real gap: FK constraints
-- validate that a referenced row EXISTS, not that it's RLS-visible to the
-- current user. event_occurrence_rsvps_own_write's WITH CHECK only
-- required user_id = auth.uid(), with no check that the occurrence_id
-- being RSVP'd to is one the user can actually see. Verified live: a
-- non-member of a secret test community could not SELECT a target
-- occurrence (RLS composed correctly there, transitively, via
-- event_occurrences -> events -> communities), but COULD still INSERT an
-- RSVP row referencing that same occurrence_id. Fixed by adding the same
-- visibility check explicitly to the WITH CHECK clause. (The read side
-- was re-verified and is NOT a bug — Postgres composes RLS transitively
-- through referenced tables' own policies correctly there.)

begin;

drop policy if exists event_occurrence_rsvps_own_write on public.event_occurrence_rsvps;
create policy event_occurrence_rsvps_own_write on public.event_occurrence_rsvps
  for all using (user_id = auth.uid())
  with check (
    user_id = auth.uid()
    and exists (select 1 from public.event_occurrences o where o.id = event_occurrence_rsvps.occurrence_id)
  );

commit;
