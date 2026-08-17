-- 106_pages_analytics_access_denied.sql
-- Professional Page System — Stage 7 (Insights UX audit)
--
-- Bug found during audit: page_analytics_summary / page_audience_growth /
-- page_top_posts (084_pages_analytics_step11.sql) embed the
-- `view_analytics` permission check inside their WHERE clause. That means
-- a caller WITHOUT the permission never gets an error — the query simply
-- returns zero rows. The Flutter screen (page_analytics_screen.dart) has
-- an `_accessDenied` branch that is only reachable by catching an
-- exception containing "permission"/"denied"/"Not authorized", so it was
-- dead code for Pages: an unauthorized viewer saw "No data yet" instead
-- of "Analytics not available", which is misleading and inconsistent
-- with the equivalent Community analytics RPCs (community_health_score,
-- 065_community_analytics_fix_day_ambiguity.sql), which correctly
-- `raise exception` up front.
--
-- Fix: add the same explicit up-front authorization check to all three
-- Page analytics RPCs. Return signatures are unchanged (CREATE OR REPLACE
-- is safe here), so no dependent code needs to change. Table/RLS grants
-- from 084 are untouched — this migration only tightens the three
-- functions' own logic.

create or replace function public.page_analytics_summary(p_page_id uuid, days_back integer default 30)
returns table (
  day date,
  reach integer,
  impressions integer,
  views integer,
  new_followers integer,
  engagement integer
)
language plpgsql
stable
security definer
set search_path = 'public'
as $$
begin
  if not (
    public.current_user_page_role(p_page_id) = 'owner'
    or public.current_user_has_page_permission(p_page_id, 'view_analytics')
  ) then
    raise exception 'Not authorized to view this page''s analytics';
  end if;

  return query
    select pa.date as day, pa.reach, pa.impressions, pa.views, pa.new_followers, pa.engagement
    from public.page_analytics pa
    where pa.page_id = p_page_id
      and pa.date >= current_date - days_back
    order by pa.date asc;
end;
$$;

grant execute on function public.page_analytics_summary(uuid, integer) to authenticated;

create or replace function public.page_audience_growth(p_page_id uuid, days_back integer default 30)
returns table (
  day date,
  new_followers integer,
  total_followers bigint
)
language plpgsql
stable
security definer
set search_path = 'public'
as $$
begin
  if not (
    public.current_user_page_role(p_page_id) = 'owner'
    or public.current_user_has_page_permission(p_page_id, 'view_analytics')
  ) then
    raise exception 'Not authorized to view this page''s analytics';
  end if;

  return query
    with daily as (
      select pa.date as day, pa.new_followers
      from public.page_analytics pa
      where pa.page_id = p_page_id
        and pa.date >= current_date - days_back
    )
    select d.day, d.new_followers,
      sum(d.new_followers) over (order by d.day asc) as total_followers
    from daily d
    order by d.day asc;
end;
$$;

grant execute on function public.page_audience_growth(uuid, integer) to authenticated;

create or replace function public.page_top_posts(p_page_id uuid, days_back integer default 30, result_limit integer default 10)
returns table (
  post_id uuid,
  content text,
  created_at timestamptz,
  impressions bigint,
  reach bigint,
  views bigint,
  reactions bigint,
  comments bigint,
  shares bigint,
  engagement_score bigint
)
language plpgsql
stable
security definer
set search_path = 'public'
as $$
begin
  if not (
    public.current_user_page_role(p_page_id) = 'owner'
    or public.current_user_has_page_permission(p_page_id, 'view_analytics')
  ) then
    raise exception 'Not authorized to view this page''s analytics';
  end if;

  return query
    select pp.id as post_id, pp.content, pp.created_at,
      coalesce(ppm.impressions, 0), coalesce(ppm.reach, 0), coalesce(ppm.views, 0),
      coalesce(ppm.reactions, 0), coalesce(ppm.comments, 0), coalesce(ppm.shares, 0),
      coalesce(ppm.reactions, 0) + coalesce(ppm.comments, 0) * 2 + coalesce(ppm.shares, 0) * 3 as engagement_score
    from public.page_posts pp
    left join public.page_post_metrics ppm on ppm.post_id = pp.id
    where pp.page_id = p_page_id
      and pp.created_at >= now() - (days_back || ' days')::interval
    order by engagement_score desc, pp.created_at desc
    limit result_limit;
end;
$$;

grant execute on function public.page_top_posts(uuid, integer, integer) to authenticated;
