-- 065_community_analytics_fix_day_ambiguity.sql
-- Fixes a bug found during manual verification of migration 064:
-- community_member_growth and community_daily_active_members both used
-- `day` as both the RETURNS TABLE output column name and a CTE column
-- alias inside the function body, which PL/pgSQL correctly rejects as
-- ambiguous. Renamed the output column to `activity_date` in both, and
-- updated community_health_score's internal call site to match.

begin;

drop function if exists public.community_member_growth(uuid, integer);
drop function if exists public.community_daily_active_members(uuid, integer);
drop function if exists public.community_health_score(uuid);

create or replace function public.community_member_growth(p_community_id uuid, days_back integer default 30)
returns table (activity_date date, joins bigint, leaves bigint, net bigint)
language plpgsql
stable
security definer
set search_path = 'public'
as $$
begin
  if not (current_user_community_permission(p_community_id, 'view_analytics') or is_admin_or_mod()) then
    raise exception 'Not authorized to view this community''s analytics';
  end if;

  return query
  with days as (
    select generate_series(current_date - (days_back - 1), current_date, interval '1 day')::date as d
  ),
  daily as (
    select e.created_at::date as d,
           count(*) filter (where e.event_type = 'joined') as joins,
           count(*) filter (where e.event_type = 'left') as leaves
    from public.community_membership_events e
    where e.community_id = p_community_id
      and e.created_at >= current_date - (days_back - 1)
    group by e.created_at::date
  )
  select days.d, coalesce(daily.joins, 0), coalesce(daily.leaves, 0), coalesce(daily.joins, 0) - coalesce(daily.leaves, 0)
  from days
  left join daily on daily.d = days.d
  order by days.d;
end;
$$;

create or replace function public.community_daily_active_members(p_community_id uuid, days_back integer default 30)
returns table (activity_date date, active_members bigint)
language plpgsql
stable
security definer
set search_path = 'public'
as $$
begin
  if not (current_user_community_permission(p_community_id, 'view_analytics') or is_admin_or_mod()) then
    raise exception 'Not authorized to view this community''s analytics';
  end if;

  return query
  with days as (
    select generate_series(current_date - (days_back - 1), current_date, interval '1 day')::date as d
  ),
  activity as (
    select p.author_id as user_id, p.created_at::date as d
    from public.posts p
    where p.community_id = p_community_id and p.created_at >= current_date - (days_back - 1)
    union all
    select cm.sender_id, cm.created_at::date
    from public.community_chat_messages cm
    where cm.community_id = p_community_id and cm.created_at >= current_date - (days_back - 1)
    union all
    select pc.user_id, pc.created_at::date
    from public.post_comments pc
    join public.posts p on p.id = pc.post_id
    where p.community_id = p_community_id and pc.created_at >= current_date - (days_back - 1)
    union all
    select pl.user_id, pl.created_at::date
    from public.post_likes pl
    join public.posts p on p.id = pl.post_id
    where p.community_id = p_community_id and pl.created_at >= current_date - (days_back - 1)
  ),
  daily as (
    select d, count(distinct user_id) as active_members
    from activity
    group by d
  )
  select days.d, coalesce(daily.active_members, 0)
  from days
  left join daily on daily.d = days.d
  order by days.d;
end;
$$;

create or replace function public.community_health_score(p_community_id uuid)
returns table (
  health_score numeric,
  dau_today bigint,
  posts_last_7d bigint,
  retention_pct_30d numeric,
  open_reports bigint,
  member_count integer
)
language plpgsql
stable
security definer
set search_path = 'public'
as $$
declare
  v_dau_today bigint;
  v_posts_7d bigint;
  v_retention numeric;
  v_open_reports bigint;
  v_member_count integer;
  v_engagement numeric;
  v_momentum numeric;
  v_report_load numeric;
begin
  if not (current_user_community_permission(p_community_id, 'view_analytics') or is_admin_or_mod()) then
    raise exception 'Not authorized to view this community''s analytics';
  end if;

  select active_members into v_dau_today from public.community_daily_active_members(p_community_id, 1) order by activity_date desc limit 1;
  v_dau_today := coalesce(v_dau_today, 0);

  select count(*) into v_posts_7d from public.posts where community_id = p_community_id and is_removed = false and created_at >= now() - interval '7 days';

  select retention_pct into v_retention from public.community_retention(p_community_id) where cohort = 'Joined last 30 days';
  v_retention := coalesce(v_retention, 0);

  select count(*) into v_open_reports
  from public.reports r join public.posts p on p.id = r.target_post_id
  where p.community_id = p_community_id and r.status::text = 'open';

  select c.member_count into v_member_count from public.communities c where c.id = p_community_id;
  v_member_count := coalesce(v_member_count, 0);

  v_engagement := least(100, (v_dau_today::numeric / greatest(v_member_count, 1)) * 500);
  v_momentum := least(100, v_posts_7d * 5);
  v_report_load := 100 - least(100, v_open_reports * 10);

  return query select
    round((v_engagement + v_momentum + v_retention + v_report_load) / 4.0, 1),
    v_dau_today, v_posts_7d, v_retention, v_open_reports, v_member_count;
end;
$$;

grant execute on function public.community_member_growth(uuid, integer) to authenticated;
grant execute on function public.community_daily_active_members(uuid, integer) to authenticated;
grant execute on function public.community_health_score(uuid) to authenticated;

commit;
