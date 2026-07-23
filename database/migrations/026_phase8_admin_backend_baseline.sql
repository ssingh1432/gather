-- Phase 8 baseline — retroactive record only.
--
-- This exact migration was already applied directly to the live database
-- (name: phase8_admin_backend, version 20260722121735) in an earlier
-- session, but never got committed to this repo's migration history. It's
-- added here now, verbatim, purely so:
--   1. A fresh environment restored from these files ends up with the same
--      schema the live DB actually has.
--   2. Nobody re-derives/duplicates this logic from scratch not knowing it
--      already exists (which is exactly what almost happened with
--      admin_overview_stats and admin_storage_usage below — see 027/028
--      for how that got reconciled instead of clobbered).
--
-- Every statement is create-or-replace / create-if-not-exists, so re-running
-- this file against the live DB is a safe no-op.

drop policy if exists posts_select_admin_all on public.posts;
create policy posts_select_admin_all on public.posts for select using (public.is_admin_or_mod());

drop policy if exists media_select_admin_all on public.post_media;
create policy media_select_admin_all on public.post_media for select using (public.is_admin_or_mod());

create table if not exists public.announcements (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  body text not null,
  severity text not null default 'info' check (severity in ('info', 'warning', 'critical')),
  is_active boolean not null default true,
  created_by uuid references public.users(id) on delete set null,
  created_at timestamptz not null default now(),
  expires_at timestamptz
);

create index if not exists idx_announcements_active on public.announcements (is_active, created_at desc);

alter table public.announcements enable row level security;
revoke all on public.announcements from anon, authenticated;
grant select on public.announcements to anon, authenticated;
grant insert, update, delete on public.announcements to authenticated;

drop policy if exists "Anyone can read active announcements" on public.announcements;
create policy "Anyone can read active announcements"
  on public.announcements for select
  to anon, authenticated
  using (is_active and (expires_at is null or expires_at > now()));

drop policy if exists "Admins manage announcements" on public.announcements;
create policy "Admins manage announcements"
  on public.announcements for all
  to authenticated
  using (public.is_admin_or_mod())
  with check (public.is_admin_or_mod());

drop policy if exists "Admins read all announcements" on public.announcements;
create policy "Admins read all announcements"
  on public.announcements for select
  to authenticated
  using (public.is_admin_or_mod());

create or replace function public.set_user_role(target_user_id uuid, new_role text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_current_role text;
  v_admin_count integer;
begin
  if not public.is_admin_or_mod() then
    raise exception 'Only admins can change roles' using errcode = '42501';
  end if;

  if new_role not in ('user', 'moderator', 'admin') then
    raise exception 'Invalid role: %', new_role using errcode = '22023';
  end if;

  if new_role in ('admin', 'moderator') and not exists (
    select 1 from public.users where id = auth.uid() and role = 'admin'
  ) then
    raise exception 'Only admins can grant moderator or admin roles' using errcode = '42501';
  end if;

  select role into v_current_role from public.users where id = target_user_id;
  if v_current_role is null then
    raise exception 'User not found' using errcode = 'P0002';
  end if;

  if v_current_role = 'admin' and new_role <> 'admin' then
    select count(*) into v_admin_count from public.users where role = 'admin';
    if v_admin_count <= 1 then
      raise exception 'Cannot remove the last remaining admin' using errcode = 'P0001';
    end if;
  end if;

  update public.users set role = new_role where id = target_user_id;
end;
$$;

grant execute on function public.set_user_role(uuid, text) to authenticated;

-- NOTE: admin_storage_usage() and this first version of admin_overview_stats()
-- are both superseded in 027/028 (extended in place via create-or-replace,
-- not dropped-and-recreated, so nothing that already depends on them breaks).
create or replace function public.admin_storage_usage()
returns table (bucket_id text, object_count bigint, total_bytes bigint)
language sql
stable
security definer
set search_path = public
as $$
  select
    o.bucket_id,
    count(*) as object_count,
    coalesce(sum((o.metadata->>'size')::bigint), 0) as total_bytes
  from storage.objects o
  where public.is_admin_or_mod()
  group by o.bucket_id
  order by total_bytes desc;
$$;

grant execute on function public.admin_storage_usage() to authenticated;

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
    'coordinated_report_targets', (select count(*) from public.coordinated_report_signals)
  ) into result;

  return result;
end;
$$;

grant execute on function public.admin_overview_stats() to authenticated;
