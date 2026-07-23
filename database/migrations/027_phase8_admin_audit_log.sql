-- Phase 8 (Batch 8.1): Admin panel foundation — general-purpose admin
-- audit log. Distinct from `moderation_actions` (which only covers
-- report-driven mod actions): this covers ANY admin-panel action
-- (role changes, community actions, settings changes, announcements,
-- etc.) so the whole panel has one consistent trail to show under
-- "Audit Logs". Admin-only read (stricter than is_admin_or_mod(), which
-- also allows moderators) since this can contain sensitive metadata.

create table if not exists public.admin_audit_log (
  id bigint generated always as identity primary key,
  admin_id uuid references auth.users(id) on delete set null,
  action text not null,
  target_type text,
  target_id text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists idx_admin_audit_log_created
  on public.admin_audit_log (created_at desc);
create index if not exists idx_admin_audit_log_admin_created
  on public.admin_audit_log (admin_id, created_at desc);
create index if not exists idx_admin_audit_log_target
  on public.admin_audit_log (target_type, target_id);

alter table public.admin_audit_log enable row level security;
revoke all on public.admin_audit_log from anon, authenticated;

-- Admins only (not moderators) — mirrors the "role: admin" check used by
-- role/permission-sensitive panel sections.
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.users where id = auth.uid() and role = 'admin'
  );
$$;

grant execute on function public.is_admin() to authenticated;

create policy "Admins can read audit log"
  on public.admin_audit_log for select
  to authenticated
  using (public.is_admin());

create or replace function public.log_admin_action(
  p_action text,
  p_target_type text default null,
  p_target_id text default null,
  p_metadata jsonb default '{}'::jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin_or_mod() then
    raise exception 'not authorized';
  end if;

  insert into public.admin_audit_log (admin_id, action, target_type, target_id, metadata)
  values (auth.uid(), p_action, p_target_type, p_target_id, coalesce(p_metadata, '{}'::jsonb));
end;
$$;

grant execute on function public.log_admin_action(text, text, text, jsonb) to authenticated;

-- admin_overview_stats() already exists (see 026_phase8_admin_backend_baseline.sql,
-- applied directly to prod before this file was written) with a richer set
-- of fields than a fresh version would have had. Extend it in place with
-- the two 7-day trend fields the Overview tab also wants, rather than
-- clobbering the existing ones.
create or replace function public.admin_overview_stats()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  result jsonb;
begin
  perform public.ensure_admin_or_mod();

  select jsonb_build_object(
    'total_users', (select count(*) from public.users),
    'active_users', (select count(*) from public.users where status = 'active'),
    'suspended_users', (select count(*) from public.users where status = 'suspended'),
    'banned_users', (select count(*) from public.users where status = 'banned'),
    'total_posts', (select count(*) from public.posts where is_removed = false),
    'removed_posts', (select count(*) from public.posts where is_removed = true),
    'total_communities', (select count(*) from public.communities),
    'open_reports', (select count(*) from public.reports where status = 'open'),
    'pending_legal_complaints', (select count(*) from public.legal_complaints where status = 'submitted'),
    'pending_data_requests', (
      (select count(*) from public.legal_data_requests where status = 'received') +
      (select count(*) from public.data_export_requests where status = 'pending')
    ),
    'pending_deletion_requests', (select count(*) from public.account_deletion_requests where status = 'pending'),
    'pending_verification_requests', (select count(*) from public.user_verification_requests where status = 'pending'),
    'open_appeals', (select count(*) from public.moderation_appeals where status = 'pending'),
    'coordinated_report_targets', (select count(*) from public.coordinated_report_signals),
    'new_users_7d', (select count(*) from public.users where created_at > now() - interval '7 days'),
    'new_posts_7d', (select count(*) from public.posts where created_at > now() - interval '7 days' and is_removed = false)
  ) into result;

  return result;
end;
$$;

grant execute on function public.admin_overview_stats() to authenticated;
