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

-- Lightweight admin-facing counts used by the dashboard Overview tab.
-- Kept as a single function so the UI does one round trip instead of
-- five separate count queries.
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
  if not public.is_admin_or_mod() then
    raise exception 'not authorized';
  end if;

  select jsonb_build_object(
    'total_users', (select count(*) from public.users),
    'total_posts', (select count(*) from public.posts where is_removed = false),
    'total_communities', (select count(*) from public.communities),
    'open_reports', (select count(*) from public.reports where status = 'open'),
    'suspended_users', (select count(*) from public.users where suspended_until is not null and suspended_until > now()),
    'new_users_7d', (select count(*) from public.users where created_at > now() - interval '7 days'),
    'new_posts_7d', (select count(*) from public.posts where created_at > now() - interval '7 days' and is_removed = false)
  ) into result;

  return result;
end;
$$;

grant execute on function public.admin_overview_stats() to authenticated;
