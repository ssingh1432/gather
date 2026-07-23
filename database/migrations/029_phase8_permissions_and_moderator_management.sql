-- Phase 8 (Batch 8.3): Moderator Management, Role Management, Permissions.
--
-- Scope note: the existing app-wide authorization model is a 3-tier role
-- (user/moderator/admin) checked via is_admin_or_mod() across ~20 already
-- shipped, working moderation functions (suspend_user, soft_remove_post,
-- resolve_report, etc — Phases 2/6/7). Retrofitting all of those to a full
-- granular-permission model in one pass would be a large, risky change to
-- functionality real moderators already depend on today, with no way to
-- test it before this session ends. Deliberately NOT doing that here.
--
-- What this migration adds instead: an additive permission-flags layer
-- (moderator_permissions) that admins can grant per moderator. It's fully
-- enforced on the admin-ops-visibility cluster this phase added itself
-- (Security/Storage/Realtime/System Health/Backup Status — brand new,
-- nobody depends on the old blanket access yet), and available for the
-- Permissions tab to manage. Existing moderators are auto-granted every
-- permission below so nobody currently working loses access today.
-- Extending enforcement into the older moderation functions is a
-- reasonable follow-up phase, done deliberately and tested, not bundled in.

create table if not exists public.moderator_permissions (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.users(id) on delete cascade,
  permission_key text not null check (permission_key in (
    'manage_users',
    'manage_posts',
    'manage_communities',
    'manage_reports',
    'manage_media',
    'manage_legal',
    'manage_announcements',
    'view_analytics',
    'view_security'
  )),
  granted_by uuid references public.users(id) on delete set null,
  granted_at timestamptz not null default now(),
  unique (user_id, permission_key)
);

create index if not exists idx_moderator_permissions_user on public.moderator_permissions (user_id);

alter table public.moderator_permissions enable row level security;
revoke all on public.moderator_permissions from anon, authenticated;

drop policy if exists "Admins read all permissions, mods read own" on public.moderator_permissions;
create policy "Admins read all permissions, mods read own"
  on public.moderator_permissions for select
  to authenticated
  using (public.is_admin() or user_id = auth.uid());

-- Admins always pass every check regardless of grants (role is the
-- ceiling; permissions only ever narrow what a *moderator* can do).
create or replace function public.has_permission(p_key text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    exists (select 1 from public.users where id = auth.uid() and role = 'admin')
    or exists (
      select 1 from public.moderator_permissions
      where user_id = auth.uid() and permission_key = p_key
    );
$$;

grant execute on function public.has_permission(text) to authenticated;

create or replace function public.grant_moderator_permission(target_user_id uuid, p_key text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'Only admins can grant permissions' using errcode = '42501';
  end if;
  if not exists (select 1 from public.users where id = target_user_id and role = 'moderator') then
    raise exception 'Target user is not a moderator' using errcode = '22023';
  end if;

  insert into public.moderator_permissions (user_id, permission_key, granted_by)
  values (target_user_id, p_key, auth.uid())
  on conflict (user_id, permission_key) do nothing;

  perform public.log_admin_action('grant_permission', 'user', target_user_id::text, jsonb_build_object('permission', p_key));
end;
$$;

grant execute on function public.grant_moderator_permission(uuid, text) to authenticated;

create or replace function public.revoke_moderator_permission(target_user_id uuid, p_key text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'Only admins can revoke permissions' using errcode = '42501';
  end if;

  delete from public.moderator_permissions where user_id = target_user_id and permission_key = p_key;

  perform public.log_admin_action('revoke_permission', 'user', target_user_id::text, jsonb_build_object('permission', p_key));
end;
$$;

grant execute on function public.revoke_moderator_permission(uuid, text) to authenticated;

-- Backward-compat bootstrap: every existing moderator keeps full access to
-- the ops-visibility cluster below, so today's moderators see no change.
insert into public.moderator_permissions (user_id, permission_key, granted_by)
select u.id, k.permission_key, u.id
from public.users u
cross join (values
  ('manage_users'), ('manage_posts'), ('manage_communities'), ('manage_reports'),
  ('manage_media'), ('manage_legal'), ('manage_announcements'),
  ('view_analytics'), ('view_security')
) as k(permission_key)
where u.role = 'moderator'
on conflict (user_id, permission_key) do nothing;

-- Retrofit only the brand-new ops-visibility cluster from Batch 8.2 (no
-- existing moderator workflow depends on these yet) to require
-- has_permission('view_security') instead of blanket is_admin_or_mod().
create or replace function public.admin_recent_login_failures(p_hours integer default 24)
returns table (email text, failure_count bigint, last_failure timestamptz)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.has_permission('view_security') then
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

create or replace function public.admin_storage_stats()
returns table (bucket_id text, is_public boolean, file_size_limit bigint, object_count bigint, total_bytes numeric)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.has_permission('view_security') then
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

create or replace function public.admin_realtime_tables()
returns table (schema_name text, table_name text)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.has_permission('view_security') then
    raise exception 'not authorized';
  end if;

  return query
  select schemaname, tablename
  from pg_publication_tables
  where pubname = 'supabase_realtime'
  order by tablename;
end;
$$;

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
  if not public.has_permission('view_security') then
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

drop policy if exists "Admins can read backup log" on public.backup_log;
create policy "Admins can read backup log"
  on public.backup_log for select
  to authenticated
  using (public.has_permission('view_security'));

drop policy if exists "Admins can read audit log" on public.admin_audit_log;
create policy "Admins can read audit log"
  on public.admin_audit_log for select
  to authenticated
  using (public.is_admin() or public.has_permission('view_security'));

-- ---------------------------------------------------------------------
-- Moderator Management: per-moderator activity summary in one round trip
-- (action counts from moderation_actions, admin-panel action counts from
-- admin_audit_log, last-active timestamp).
-- ---------------------------------------------------------------------
create or replace function public.admin_moderator_activity()
returns table (
  user_id uuid,
  username text,
  role text,
  moderation_action_count bigint,
  admin_action_count bigint,
  last_active timestamptz
)
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
    u.id as user_id,
    u.username,
    u.role::text,
    coalesce(ma.cnt, 0) as moderation_action_count,
    coalesce(aa.cnt, 0) as admin_action_count,
    greatest(ma.last_at, aa.last_at) as last_active
  from public.users u
  left join (
    select admin_id, count(*) as cnt, max(created_at) as last_at
    from public.moderation_actions group by admin_id
  ) ma on ma.admin_id = u.id
  left join (
    select admin_id, count(*) as cnt, max(created_at) as last_at
    from public.admin_audit_log group by admin_id
  ) aa on aa.admin_id = u.id
  where u.role in ('moderator', 'admin')
  order by u.role desc, greatest(coalesce(ma.last_at, 'epoch'::timestamptz), coalesce(aa.last_at, 'epoch'::timestamptz)) desc;
end;
$$;

grant execute on function public.admin_moderator_activity() to authenticated;
