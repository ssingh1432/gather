-- Phase 8 (Batch 8.2): Security / Storage / Realtime Status / System
-- Health / Backup Status. All admin-only (is_admin_or_mod()), all read via
-- SECURITY DEFINER functions rather than granting direct table access,
-- consistent with existing patterns (see admin_overview_stats,
-- log_security_event).

-- ---------------------------------------------------------------------
-- Security: recent failed-login rollup. auth_login_attempts has no direct
-- grants (see migration 012) by design, so this is the only way to see it.
-- ---------------------------------------------------------------------
create or replace function public.admin_recent_login_failures(p_hours integer default 24)
returns table (email text, failure_count bigint, last_failure timestamptz)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.is_admin_or_mod() then
    raise exception 'not authorized';
  end if;

  return query
  select a.email, count(*) as failure_count, max(a.created_at) as last_failure
  from public.auth_login_attempts a
  where a.success = false and a.created_at > now() - (p_hours || ' hours')::interval
  group by a.email
  order by failure_count desc, last_failure desc
  limit 50;
end;
$$;

grant execute on function public.admin_recent_login_failures(integer) to authenticated;

-- ---------------------------------------------------------------------
-- Storage: per-bucket object count + total size. Supersedes
-- admin_storage_usage() from 026_phase8_admin_backend_baseline.sql (same
-- purpose, same authorization, but this version also surfaces
-- public/private and the per-file size limit, which the Storage tab
-- needs). Nothing in the app calls admin_storage_usage() yet, so it's
-- safe to drop outright rather than leave two near-duplicate functions
-- around.
-- ---------------------------------------------------------------------
drop function if exists public.admin_storage_usage();

create or replace function public.admin_storage_stats()
returns table (bucket_id text, is_public boolean, file_size_limit bigint, object_count bigint, total_bytes numeric)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.is_admin_or_mod() then
    raise exception 'not authorized';
  end if;

  return query
  select
    b.id as bucket_id,
    b.public as is_public,
    b.file_size_limit,
    coalesce(count(o.id), 0) as object_count,
    coalesce(sum((o.metadata->>'size')::numeric), 0) as total_bytes
  from storage.buckets b
  left join storage.objects o on o.bucket_id = b.id
  group by b.id, b.public, b.file_size_limit
  order by b.id;
end;
$$;

grant execute on function public.admin_storage_stats() to authenticated;

-- ---------------------------------------------------------------------
-- Realtime Status: which tables are actually enabled on the
-- supabase_realtime publication, so the panel reflects real config
-- instead of an assumption.
-- ---------------------------------------------------------------------
create or replace function public.admin_realtime_tables()
returns table (schema_name text, table_name text)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.is_admin_or_mod() then
    raise exception 'not authorized';
  end if;

  return query
  select schemaname, tablename
  from pg_publication_tables
  where pubname = 'supabase_realtime'
  order by tablename;
end;
$$;

grant execute on function public.admin_realtime_tables() to authenticated;

-- ---------------------------------------------------------------------
-- System Health: backlog counts across every review/processing queue in
-- one round trip, plus the DB's own clock (client measures round-trip
-- latency against this).
-- ---------------------------------------------------------------------
create or replace function public.admin_system_health()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  result jsonb;
begin
  if not public.is_admin_or_mod() then
    raise exception 'not authorized';
  end if;

  select jsonb_build_object(
    'server_time', now(),
    'pending_appeals', (select count(*) from public.moderation_appeals where status = 'pending'),
    'pending_media_review', (select count(*) from public.media_moderation_flags where status = 'pending'),
    'flagged_media', (select count(*) from public.media_moderation_flags where status = 'flagged'),
    'pending_verifications', (select count(*) from public.user_verification_requests where status = 'pending'),
    'account_deletions_awaiting_purge', (
      select count(*) from public.account_deletion_requests
      where status = 'pending' and scheduled_purge_at <= now()
    ),
    'account_deletions_in_grace_period', (
      select count(*) from public.account_deletion_requests
      where status = 'pending' and scheduled_purge_at > now()
    )
  ) into result;

  return result;
end;
$$;

grant execute on function public.admin_system_health() to authenticated;

-- ---------------------------------------------------------------------
-- Backup Status. Supabase manages actual point-in-time/daily platform
-- backups outside of Postgres itself (project settings, not something a
-- client can or should read — doing so would require a Management API
-- service key, which must never live in client code). What we CAN do
-- from inside the database is run a scheduled integrity heartbeat: a
-- daily snapshot of core-table row counts, so a sudden unexplained drop
-- shows up here as an early warning sign between platform backups.
-- ---------------------------------------------------------------------
create table if not exists public.backup_log (
  id bigint generated always as identity primary key,
  run_at timestamptz not null default now(),
  status text not null default 'ok' check (status in ('ok', 'error')),
  row_counts jsonb not null default '{}'::jsonb,
  error text
);

create index if not exists idx_backup_log_run_at on public.backup_log (run_at desc);

alter table public.backup_log enable row level security;
revoke all on public.backup_log from anon, authenticated;

create policy "Admins can read backup log"
  on public.backup_log for select
  to authenticated
  using (public.is_admin_or_mod());

create or replace function public.run_backup_heartbeat()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  counts jsonb;
begin
  select jsonb_build_object(
    'users', (select count(*) from public.users),
    'posts', (select count(*) from public.posts),
    'communities', (select count(*) from public.communities),
    'reports', (select count(*) from public.reports)
  ) into counts;

  insert into public.backup_log (status, row_counts) values ('ok', counts);
exception when others then
  insert into public.backup_log (status, row_counts, error) values ('error', '{}'::jsonb, sqlerrm);
end;
$$;

revoke all on function public.run_backup_heartbeat() from anon, authenticated;

select cron.schedule(
  'backup-integrity-heartbeat',
  '0 2 * * *', -- daily at 02:00 UTC, ahead of the 03:00 purge job
  $$select public.run_backup_heartbeat();$$
);

-- Seed one row now so the Backup Status tab isn't empty before tomorrow's
-- first scheduled run.
select public.run_backup_heartbeat();
