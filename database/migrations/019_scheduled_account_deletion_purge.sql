-- Phase 3 follow-up: the scheduled purge job for account_deletion_requests
-- past their grace period. Runs entirely in Postgres via pg_cron calling a
-- SECURITY DEFINER function directly — deliberately NOT an HTTP call to an
-- edge function, so no service-role key ever needs to live in a migration
-- file or cron job definition. Deleting the auth.users row cascades to
-- public.users (ON DELETE CASCADE, see users_id_fkey) and from there to all
-- owned data via the existing FK cascade chain.

create extension if not exists pg_cron with schema extensions;

create or replace function public.purge_expired_account_deletions()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  r record;
begin
  for r in
    select id, user_id
    from public.account_deletion_requests
    where status = 'pending' and scheduled_purge_at <= now()
  loop
    begin
      delete from auth.users where id = r.user_id;

      update public.account_deletion_requests
      set status = 'completed', completed_at = now()
      where id = r.id;
    exception when others then
      -- Don't let one bad row block the rest of the batch. Leave it
      -- 'pending' so the next run retries it, and record why it failed.
      update public.account_deletion_requests
      set reason = left(coalesce(reason, '') || ' [purge failed ' || now()::text || ': ' || sqlerrm || ']', 2000)
      where id = r.id;
    end;
  end loop;
end;
$$;

-- No grants to anon/authenticated — this only ever runs as the cron job
-- owner (postgres), never called by a client.
revoke all on function public.purge_expired_account_deletions() from anon, authenticated;

select cron.schedule(
  'purge-expired-account-deletions',
  '0 3 * * *', -- daily at 03:00 UTC
  $$select public.purge_expired_account_deletions();$$
);
