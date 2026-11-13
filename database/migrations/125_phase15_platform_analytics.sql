-- Phase 15: platform-wide analytics (DAU / MAU / retention / engagement /
-- moderation / uploads / crashes). Read-only, admin/moderator-gated RPCs on top
-- of existing tables; no existing objects are altered or removed.
--
-- DAU source of truth: analytics_events rows with event_name = 'daily_active_user'
-- (one row per user per UTC day, enforced by idx_analytics_daily_active_once).

create index if not exists idx_analytics_dau_date_user
  on public.analytics_events (event_date, user_id)
  where event_name = 'daily_active_user';

create index if not exists idx_analytics_events_name_date
  on public.analytics_events (event_name, event_date);

create index if not exists idx_users_created_at on public.users (created_at);
create index if not exists idx_posts_created_at on public.posts (created_at);
create index if not exists idx_post_comments_created_at on public.post_comments (created_at);
create index if not exists idx_post_likes_created_at on public.post_likes (created_at);
create index if not exists idx_reports_created_at on public.reports (created_at);

-- ---------------------------------------------------------------------------
-- Headline KPIs
-- ---------------------------------------------------------------------------
create or replace function public.admin_platform_kpis()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
#variable_conflict use_column
declare
  v_today date := (now() at time zone 'utc')::date;
  v_dau bigint; v_dau_prev bigint; v_wau bigint; v_mau bigint; v_mau_prev bigint;
  v_new_30 bigint; v_new_prev_30 bigint; v_total bigint;
begin
  perform public.ensure_admin_or_mod();

  select count(*) into v_dau from public.analytics_events
   where event_name = 'daily_active_user' and event_date = v_today;
  select count(*) into v_dau_prev from public.analytics_events
   where event_name = 'daily_active_user' and event_date = v_today - 1;
  select count(distinct user_id) into v_wau from public.analytics_events
   where event_name = 'daily_active_user' and event_date between v_today - 6 and v_today;
  select count(distinct user_id) into v_mau from public.analytics_events
   where event_name = 'daily_active_user' and event_date between v_today - 29 and v_today;
  select count(distinct user_id) into v_mau_prev from public.analytics_events
   where event_name = 'daily_active_user' and event_date between v_today - 59 and v_today - 30;

  select count(*) into v_total from public.users;
  select count(*) into v_new_30 from public.users
   where (created_at at time zone 'utc')::date between v_today - 29 and v_today;
  select count(*) into v_new_prev_30 from public.users
   where (created_at at time zone 'utc')::date between v_today - 59 and v_today - 30;

  return jsonb_build_object(
    'as_of', now(),
    'dau', v_dau,
    'dau_yesterday', v_dau_prev,
    'wau', v_wau,
    'mau', v_mau,
    'mau_previous_30d', v_mau_prev,
    'stickiness_pct', case when v_mau = 0 then 0 else round(100.0 * v_dau / v_mau, 1) end,
    'total_users', v_total,
    'new_users_today', (select count(*) from public.users where (created_at at time zone 'utc')::date = v_today),
    'new_users_7d', (select count(*) from public.users where (created_at at time zone 'utc')::date between v_today - 6 and v_today),
    'new_users_30d', v_new_30,
    'new_users_previous_30d', v_new_prev_30,
    'user_growth_pct_30d', case when v_new_prev_30 = 0 then null
                                else round(100.0 * (v_new_30 - v_new_prev_30) / v_new_prev_30, 1) end,
    'posts_24h', (select count(*) from public.posts where created_at > now() - interval '24 hours' and is_removed = false),
    'comments_24h', (select count(*) from public.post_comments where created_at > now() - interval '24 hours'),
    'likes_24h', (select count(*) from public.post_likes where created_at > now() - interval '24 hours')
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Daily time series: DAU, rolling 30-day MAU, growth and content activity
-- ---------------------------------------------------------------------------
create or replace function public.admin_activity_series(p_days int default 30)
returns table (
  activity_date date,
  dau bigint,
  mau_rolling bigint,
  new_users bigint,
  post_count bigint,
  comment_count bigint,
  like_count bigint,
  report_count bigint
)
language plpgsql
stable
security definer
set search_path = public
as $$
#variable_conflict use_column
declare
  v_days int := least(greatest(coalesce(p_days, 30), 1), 180);
  v_today date := (now() at time zone 'utc')::date;
begin
  perform public.ensure_admin_or_mod();

  return query
  select
    d.d,
    (select count(*) from public.analytics_events e
      where e.event_name = 'daily_active_user' and e.event_date = d.d),
    (select count(distinct e.user_id) from public.analytics_events e
      where e.event_name = 'daily_active_user' and e.event_date between d.d - 29 and d.d),
    (select count(*) from public.users u where (u.created_at at time zone 'utc')::date = d.d),
    (select count(*) from public.posts p
      where (p.created_at at time zone 'utc')::date = d.d and p.is_removed = false),
    (select count(*) from public.post_comments c where (c.created_at at time zone 'utc')::date = d.d),
    (select count(*) from public.post_likes l where (l.created_at at time zone 'utc')::date = d.d),
    (select count(*) from public.reports r where (r.created_at at time zone 'utc')::date = d.d)
  from (
    select generate_series(v_today - (v_days - 1), v_today, interval '1 day')::date as d
  ) d
  order by d.d;
end;
$$;

-- ---------------------------------------------------------------------------
-- Weekly signup cohorts with classic day-1 / day-7 / day-30 retention.
-- A user is "retained on day N" if they have a daily_active_user event exactly
-- N days after signup. Only users whose day N has already passed are eligible,
-- so recent cohorts are not penalised.
-- ---------------------------------------------------------------------------
create or replace function public.admin_retention_cohorts(p_weeks int default 8)
returns table (
  cohort_week date,
  cohort_size bigint,
  d1_eligible bigint,
  d1_retained bigint,
  d7_eligible bigint,
  d7_retained bigint,
  d30_eligible bigint,
  d30_retained bigint
)
language plpgsql
stable
security definer
set search_path = public
as $$
#variable_conflict use_column
declare
  v_weeks int := least(greatest(coalesce(p_weeks, 8), 1), 52);
  v_today date := (now() at time zone 'utc')::date;
begin
  perform public.ensure_admin_or_mod();

  return query
  with cohort as (
    select u.id,
           (u.created_at at time zone 'utc')::date as signup_date,
           date_trunc('week', u.created_at at time zone 'utc')::date as wk
    from public.users u
    where (u.created_at at time zone 'utc')::date >= v_today - (v_weeks * 7)
  )
  select
    c.wk,
    count(*)::bigint,
    count(*) filter (where c.signup_date + 1 <= v_today)::bigint,
    count(*) filter (where c.signup_date + 1 <= v_today and exists (
      select 1 from public.analytics_events e
       where e.user_id = c.id and e.event_name = 'daily_active_user'
         and e.event_date = c.signup_date + 1))::bigint,
    count(*) filter (where c.signup_date + 7 <= v_today)::bigint,
    count(*) filter (where c.signup_date + 7 <= v_today and exists (
      select 1 from public.analytics_events e
       where e.user_id = c.id and e.event_name = 'daily_active_user'
         and e.event_date = c.signup_date + 7))::bigint,
    count(*) filter (where c.signup_date + 30 <= v_today)::bigint,
    count(*) filter (where c.signup_date + 30 <= v_today and exists (
      select 1 from public.analytics_events e
       where e.user_id = c.id and e.event_name = 'daily_active_user'
         and e.event_date = c.signup_date + 30))::bigint
  from cohort c
  group by c.wk
  order by c.wk desc;
end;
$$;

-- ---------------------------------------------------------------------------
-- Engagement summary over a window
-- ---------------------------------------------------------------------------
create or replace function public.admin_engagement_summary(p_days int default 30)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
#variable_conflict use_column
declare
  v_days int := least(greatest(coalesce(p_days, 30), 1), 180);
  v_since timestamptz := now() - make_interval(days => v_days);
  v_active bigint; v_engaged bigint; v_posts bigint; v_comments bigint; v_likes bigint;
begin
  perform public.ensure_admin_or_mod();

  select count(distinct user_id) into v_active from public.analytics_events
   where event_name = 'daily_active_user'
     and event_date >= ((now() at time zone 'utc')::date - (v_days - 1));

  select count(*) into v_posts from public.posts where created_at >= v_since and is_removed = false;
  select count(*) into v_comments from public.post_comments where created_at >= v_since;
  select count(*) into v_likes from public.post_likes where created_at >= v_since;

  select count(*) into v_engaged from (
    select author_id as uid from public.posts where created_at >= v_since and is_removed = false
    union
    select user_id from public.post_comments where created_at >= v_since
    union
    select user_id from public.post_likes where created_at >= v_since
  ) x;

  return jsonb_build_object(
    'window_days', v_days,
    'active_users', v_active,
    'engaged_users', v_engaged,
    'engagement_rate_pct', case when v_active = 0 then 0 else round(100.0 * v_engaged / v_active, 1) end,
    'posts', v_posts,
    'comments', v_comments,
    'likes', v_likes,
    'actions_per_active_user', case when v_active = 0 then 0
                                    else round((v_posts + v_comments + v_likes)::numeric / v_active, 2) end,
    'feed_views', (select count(*) from public.analytics_events
                    where event_name = 'feed_viewed' and occurred_at >= v_since),
    'feed_no_interaction', (select count(*) from public.analytics_events
                             where event_name = 'feed_no_interaction' and occurred_at >= v_since),
    'post_creation_started', (select count(*) from public.analytics_events
                               where event_name = 'post_creation_started' and occurred_at >= v_since),
    'post_creation_abandoned', (select count(*) from public.analytics_events
                                 where event_name = 'post_creation_abandoned' and occurred_at >= v_since),
    'users_by_platform', coalesce((
      select jsonb_object_agg(platform, n) from (
        select coalesce(metadata->>'platform', 'unknown') as platform,
               count(distinct user_id) as n
        from public.analytics_events
        where occurred_at >= v_since and metadata ? 'platform'
        group by 1
      ) p
    ), '{}'::jsonb)
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Moderation analytics over a window
-- ---------------------------------------------------------------------------
create or replace function public.admin_moderation_analytics(p_days int default 30)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
#variable_conflict use_column
declare
  v_days int := least(greatest(coalesce(p_days, 30), 1), 180);
  v_since timestamptz := now() - make_interval(days => v_days);
begin
  perform public.ensure_admin_or_mod();

  return jsonb_build_object(
    'window_days', v_days,
    'reports_total', (select count(*) from public.reports where created_at >= v_since),
    'reports_open', (select count(*) from public.reports where status::text = 'open'),
    'reports_automated', (select count(*) from public.reports where created_at >= v_since and is_automated),
    'reports_by_status', coalesce((
      select jsonb_object_agg(s, n) from (
        select status::text as s, count(*) as n from public.reports
         where created_at >= v_since group by 1) t), '{}'::jsonb),
    'reports_by_category', coalesce((
      select jsonb_object_agg(c, n) from (
        select coalesce(category::text, 'uncategorized') as c, count(*) as n from public.reports
         where created_at >= v_since group by 1) t), '{}'::jsonb),
    'actions_by_type', coalesce((
      select jsonb_object_agg(a, n) from (
        select action as a, count(*) as n from public.moderation_actions
         where created_at >= v_since group by 1) t), '{}'::jsonb),
    'appeals_by_status', coalesce((
      select jsonb_object_agg(s, n) from (
        select status as s, count(*) as n from public.moderation_appeals
         where created_at >= v_since group by 1) t), '{}'::jsonb),
    'avg_appeal_review_hours', (
      select round(avg(extract(epoch from (reviewed_at - created_at)) / 3600.0)::numeric, 1)
        from public.moderation_appeals
       where reviewed_at is not null and created_at >= v_since),
    'posts_removed', (select count(*) from public.posts where is_removed and updated_at >= v_since)
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Uploads per day (storage.objects), all buckets
-- ---------------------------------------------------------------------------
create or replace function public.admin_uploads_series(p_days int default 30)
returns table (
  upload_date date,
  upload_count bigint,
  upload_bytes bigint
)
language plpgsql
stable
security definer
set search_path = public
as $$
#variable_conflict use_column
declare
  v_days int := least(greatest(coalesce(p_days, 30), 1), 180);
  v_today date := (now() at time zone 'utc')::date;
begin
  perform public.ensure_admin_or_mod();

  return query
  select d.d,
         coalesce(count(o.id), 0)::bigint,
         coalesce(sum((o.metadata->>'size')::bigint), 0)::bigint
  from (select generate_series(v_today - (v_days - 1), v_today, interval '1 day')::date as d) d
  left join storage.objects o
         on (o.created_at at time zone 'utc')::date = d.d
  group by d.d
  order by d.d;
end;
$$;

-- ---------------------------------------------------------------------------
-- Crash / error analytics from beta_error_logs
-- ---------------------------------------------------------------------------
create or replace function public.admin_crash_analytics(p_days int default 14)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
#variable_conflict use_column
declare
  v_days int := least(greatest(coalesce(p_days, 14), 1), 90);
  v_since timestamptz := now() - make_interval(days => v_days);
begin
  perform public.ensure_admin_or_mod();

  return jsonb_build_object(
    'window_days', v_days,
    'total_errors', (select count(*) from public.beta_error_logs where created_at >= v_since),
    'affected_users', (select count(distinct user_id) from public.beta_error_logs
                        where created_at >= v_since and user_id is not null),
    'by_platform', coalesce((
      select jsonb_object_agg(p, n) from (
        select coalesce(platform, 'unknown') as p, count(*) as n
          from public.beta_error_logs where created_at >= v_since group by 1) t), '{}'::jsonb),
    'by_version', coalesce((
      select jsonb_object_agg(v, n) from (
        select coalesce(app_version, 'unknown') as v, count(*) as n
          from public.beta_error_logs where created_at >= v_since group by 1) t), '{}'::jsonb),
    'top_errors', coalesce((
      select jsonb_agg(jsonb_build_object('message', m, 'count', n, 'users', u) order by n desc) from (
        select left(coalesce(message, error_message, 'unknown'), 160) as m,
               count(*) as n, count(distinct user_id) as u
          from public.beta_error_logs where created_at >= v_since
         group by 1 order by n desc limit 10) t), '[]'::jsonb),
    'daily', coalesce((
      select jsonb_agg(jsonb_build_object('date', d, 'count', n) order by d) from (
        select (created_at at time zone 'utc')::date as d, count(*) as n
          from public.beta_error_logs where created_at >= v_since group by 1) t), '[]'::jsonb)
  );
end;
$$;

-- Lock down execution: authenticated callers only; each function re-checks role.
do $$
declare f text;
begin
  foreach f in array array[
    'admin_platform_kpis()',
    'admin_activity_series(int)',
    'admin_retention_cohorts(int)',
    'admin_engagement_summary(int)',
    'admin_moderation_analytics(int)',
    'admin_uploads_series(int)',
    'admin_crash_analytics(int)'
  ] loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $$;
