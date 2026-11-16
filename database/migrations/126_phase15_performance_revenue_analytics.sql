-- Phase 15 (part 2): client performance telemetry + revenue-readiness analytics.
-- Additive only.

create table if not exists public.client_performance_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references public.users(id) on delete set null,
  metric text not null check (metric in ('app_start', 'first_frame', 'feed_load')),
  value_ms integer not null check (value_ms between 0 and 120000),
  platform text not null default 'unknown'
    check (platform in ('android', 'ios', 'web', 'macos', 'windows', 'linux', 'unknown')),
  app_version text,
  route text,
  created_at timestamptz not null default now()
);

create index if not exists idx_client_perf_metric_created
  on public.client_performance_events (metric, created_at desc);
create index if not exists idx_client_perf_created
  on public.client_performance_events (created_at);
create index if not exists idx_client_perf_user_created
  on public.client_performance_events (user_id, created_at desc);

alter table public.client_performance_events enable row level security;
revoke all on public.client_performance_events from anon, authenticated;

drop policy if exists client_perf_select_admin on public.client_performance_events;
create policy client_perf_select_admin on public.client_performance_events
  for select to authenticated using (public.is_admin_or_mod());

-- Write path: authenticated only, validated, capped at 120 samples per user per hour.
create or replace function public.track_performance_metric(
  p_metric text,
  p_value_ms integer,
  p_platform text default 'unknown',
  p_app_version text default null,
  p_route text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if p_metric not in ('app_start', 'first_frame', 'feed_load') then
    return;
  end if;
  if p_value_ms is null or p_value_ms < 0 or p_value_ms > 120000 then
    return;
  end if;
  if (select count(*) from public.client_performance_events
       where user_id = auth.uid() and created_at > now() - interval '1 hour') >= 120 then
    return;
  end if;

  insert into public.client_performance_events (user_id, metric, value_ms, platform, app_version, route)
  values (
    auth.uid(),
    p_metric,
    p_value_ms,
    case when p_platform in ('android', 'ios', 'web', 'macos', 'windows', 'linux') then p_platform else 'unknown' end,
    left(p_app_version, 40),
    left(p_route, 80)
  );
end;
$$;

revoke all on function public.track_performance_metric(text, integer, text, text, text) from public, anon;
grant execute on function public.track_performance_metric(text, integer, text, text, text) to authenticated;

-- Retention helper (not scheduled automatically): drops samples older than 90 days.
create or replace function public.purge_old_performance_events()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare n integer;
begin
  perform public.ensure_admin_or_mod();
  delete from public.client_performance_events where created_at < now() - interval '90 days';
  get diagnostics n = row_count;
  return n;
end;
$$;
revoke all on function public.purge_old_performance_events() from public, anon;
grant execute on function public.purge_old_performance_events() to authenticated;

-- Percentiles per metric / platform and a daily p75 series.
create or replace function public.admin_performance_analytics(p_days int default 14)
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
    'samples', (select count(*) from public.client_performance_events where created_at >= v_since),
    'by_metric', coalesce((
      select jsonb_agg(jsonb_build_object(
        'metric', metric, 'count', n, 'avg_ms', avg_ms, 'p50_ms', p50, 'p75_ms', p75, 'p95_ms', p95) order by metric)
      from (
        select metric,
               count(*) as n,
               round(avg(value_ms))::int as avg_ms,
               round(percentile_cont(0.5) within group (order by value_ms))::int as p50,
               round(percentile_cont(0.75) within group (order by value_ms))::int as p75,
               round(percentile_cont(0.95) within group (order by value_ms))::int as p95
        from public.client_performance_events
        where created_at >= v_since
        group by metric
      ) t), '[]'::jsonb),
    'by_platform', coalesce((
      select jsonb_agg(jsonb_build_object(
        'metric', metric, 'platform', platform, 'count', n, 'p75_ms', p75) order by metric, platform)
      from (
        select metric, platform, count(*) as n,
               round(percentile_cont(0.75) within group (order by value_ms))::int as p75
        from public.client_performance_events
        where created_at >= v_since
        group by metric, platform
      ) t), '[]'::jsonb),
    'daily_p75', coalesce((
      select jsonb_agg(jsonb_build_object('date', d, 'metric', metric, 'p75_ms', p75) order by d, metric)
      from (
        select (created_at at time zone 'utc')::date as d, metric,
               round(percentile_cont(0.75) within group (order by value_ms))::int as p75
        from public.client_performance_events
        where created_at >= v_since
        group by 1, metric
      ) t), '[]'::jsonb)
  );
end;
$$;

-- Payment pipeline / monetization readiness. Amounts are in minor units (paisa).
create or replace function public.admin_revenue_readiness(p_days int default 30)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
#variable_conflict use_column
declare
  v_days int := least(greatest(coalesce(p_days, 30), 1), 365);
  v_since timestamptz := now() - make_interval(days => v_days);
  v_init bigint; v_done bigint;
begin
  perform public.ensure_admin_or_mod();

  select count(*), count(*) filter (where status = 'completed')
    into v_init, v_done
    from public.page_payment_transactions where created_at >= v_since;

  return jsonb_build_object(
    'window_days', v_days,
    'currency', 'NPR',
    'payments_initiated', v_init,
    'payments_completed', v_done,
    'payments_failed', (select count(*) from public.page_payment_transactions
                         where created_at >= v_since and status in ('failed', 'cancelled')),
    'payments_pending', (select count(*) from public.page_payment_transactions
                          where created_at >= v_since and status = 'pending'),
    'payments_pending_over_24h', (select count(*) from public.page_payment_transactions
                                   where status = 'pending' and created_at < now() - interval '24 hours'),
    'completed_amount_cents', (select coalesce(sum(amount_cents), 0) from public.page_payment_transactions
                                where created_at >= v_since and status = 'completed'),
    'conversion_pct', case when v_init = 0 then 0 else round(100.0 * v_done / v_init, 1) end,
    'by_purpose', coalesce((
      select jsonb_object_agg(purpose, jsonb_build_object('initiated', n, 'completed', c, 'completed_amount_cents', amt))
      from (
        select purpose, count(*) as n,
               count(*) filter (where status = 'completed') as c,
               coalesce(sum(amount_cents) filter (where status = 'completed'), 0) as amt
        from public.page_payment_transactions where created_at >= v_since group by purpose) t), '{}'::jsonb),
    'by_gateway', coalesce((
      select jsonb_object_agg(gateway, jsonb_build_object('initiated', n, 'completed', c))
      from (
        select gateway, count(*) as n, count(*) filter (where status = 'completed') as c
        from public.page_payment_transactions where created_at >= v_since group by gateway) t), '{}'::jsonb),
    'subscribers_by_status', coalesce((
      select jsonb_object_agg(s, n) from (
        select status as s, count(*) as n from public.page_subscribers group by status) t), '{}'::jsonb),
    'orders_by_status', coalesce((
      select jsonb_object_agg(s, n) from (
        select status as s, count(*) as n from public.page_marketplace_orders
         where created_at >= v_since group by status) t), '{}'::jsonb),
    'donations_by_status', coalesce((
      select jsonb_object_agg(s, n) from (
        select status as s, count(*) as n from public.page_donations
         where created_at >= v_since group by status) t), '{}'::jsonb),
    'campaigns_by_status', coalesce((
      select jsonb_object_agg(s, n) from (
        select status as s, count(*) as n from public.page_ad_campaigns group by status) t), '{}'::jsonb),
    'creator_ad_impressions', (select count(*) from public.creator_ad_impressions where created_at >= v_since),
    'monetization_opt_in_users', (select count(*) from public.users where monetization_opt_in),
    'monetization_status', coalesce((
      select jsonb_object_agg(s, n) from (
        select coalesce(monetization_status::text, 'none') as s, count(*) as n
          from public.users group by 1) t), '{}'::jsonb)
  );
end;
$$;

do $$
declare f text;
begin
  foreach f in array array['admin_performance_analytics(int)', 'admin_revenue_readiness(int)'] loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $$;
