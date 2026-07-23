-- Phase 8 (Batch 8.4): Announcements, admin Notifications, Data Requests,
-- Settings.
--
-- Announcements: already has a full table + RLS (see
-- 026_phase8_admin_backend_baseline.sql) — this batch only adds the
-- Flutter CRUD UI, no new SQL needed.
--
-- Data Requests: already fully covered by legal_data_requests +
-- AdminLegalDashboardScreen's "Legal data requests" tab — this batch just
-- points the nav item at it, no new SQL needed.
--
-- Settings: already has app_config (key/value, admin-write RLS already in
-- place) — this batch only adds the Flutter editor UI, no new SQL needed.
--
-- Notifications: the notifications table is intentionally locked to
-- self-read-only (who liked/followed/commented on what is private
-- activity data — see notifications_select_self_beta policy). Rather than
-- widen that to admin-read-all (a real privacy regression for a feature
-- that doesn't need per-user detail), this adds one aggregate-only
-- SECURITY DEFINER function: counts and type breakdown, never individual
-- rows, recipients, or actors.
create or replace function public.admin_notification_stats()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  result jsonb;
begin
  if not public.has_permission('view_analytics') then
    raise exception 'not authorized';
  end if;

  select jsonb_build_object(
    'total', (select count(*) from public.notifications),
    'unread', (select count(*) from public.notifications where is_read = false),
    'last_24h', (select count(*) from public.notifications where created_at > now() - interval '24 hours'),
    'by_type', (
      select coalesce(jsonb_object_agg(type, cnt), '{}'::jsonb)
      from (select type::text, count(*) as cnt from public.notifications group by type) t
    )
  ) into result;

  return result;
end;
$$;

grant execute on function public.admin_notification_stats() to authenticated;
