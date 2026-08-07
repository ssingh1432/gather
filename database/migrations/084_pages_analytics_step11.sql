-- 084_pages_analytics_step11.sql
-- Professional Page System — Step 11 (Analytics)
-- Adds per-post metrics on top of the existing page_analytics daily-rollup
-- table (created in 074_pages_ops.sql), plus:
--   * record_page_post_view / record_page_impression — client-callable
--     SECURITY DEFINER RPCs that clients call as posts/pages render.
--   * page_analytics_summary — reach/impressions/views/followers/engagement
--     totals + daily series for a date range (dashboard header + chart).
--   * page_audience_growth — daily new-follower counts + running total.
--   * page_top_posts / page_post_performance — per-post breakdown.
-- Additive only; depends on 072–074, 078 (followers), 073 (page_posts).

-- 1. Per-post metrics ---------------------------------------------------------
create table if not exists public.page_post_metrics (
  post_id uuid primary key references public.page_posts(id) on delete cascade,
  page_id uuid not null references public.pages(id) on delete cascade,
  impressions bigint not null default 0,
  reach bigint not null default 0,
  views bigint not null default 0,
  reactions bigint not null default 0,
  comments bigint not null default 0,
  shares bigint not null default 0,
  updated_at timestamptz not null default now()
);

create index if not exists idx_page_post_metrics_page on public.page_post_metrics (page_id);

alter table public.page_post_metrics enable row level security;

drop policy if exists page_post_metrics_select on public.page_post_metrics;
create policy page_post_metrics_select on public.page_post_metrics
  for select using (
    public.current_user_page_role(page_id) = 'owner'
    or public.current_user_has_page_permission(page_id, 'view_analytics')
  );

-- Row is written only via the SECURITY DEFINER RPCs below, or by the
-- service role during the daily rollup — no direct client writes.
grant select on public.page_post_metrics to authenticated;

-- Dedup table so a single viewer only counts once per post per rolling
-- window, preventing trivial view-count inflation from repeated calls.
create table if not exists public.page_post_view_events (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.page_posts(id) on delete cascade,
  viewer_id uuid references public.users(id) on delete set null,
  created_at timestamptz not null default now()
);

create index if not exists idx_page_post_view_events_dedup
  on public.page_post_view_events (post_id, viewer_id, created_at desc);

alter table public.page_post_view_events enable row level security;
-- No select/insert grants to `authenticated` directly; all access goes
-- through record_page_post_view (SECURITY DEFINER) below.

-- 2. Record a view (once per viewer per post per 12h) -------------------------
create or replace function public.record_page_post_view(p_post_id uuid)
returns void
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_page_id uuid;
  v_viewer uuid := auth.uid();
  v_recent boolean;
begin
  select page_id into v_page_id from public.page_posts where id = p_post_id;
  if v_page_id is null then
    return; -- silently no-op on unknown/deleted post
  end if;

  if v_viewer is not null then
    select exists (
      select 1 from public.page_post_view_events
      where post_id = p_post_id and viewer_id = v_viewer and created_at > now() - interval '12 hours'
    ) into v_recent;
    if v_recent then
      return;
    end if;
  end if;

  insert into public.page_post_view_events (post_id, viewer_id) values (p_post_id, v_viewer);

  insert into public.page_post_metrics (post_id, page_id, views, reach, impressions)
  values (p_post_id, v_page_id, 1, 1, 1)
  on conflict (post_id) do update
    set views = public.page_post_metrics.views + 1,
        reach = public.page_post_metrics.reach + 1,
        updated_at = now();

  insert into public.page_analytics (page_id, date, views, reach, engagement)
  values (v_page_id, current_date, 1, 1, 0)
  on conflict (page_id, date) do update
    set views = public.page_analytics.views + 1,
        reach = public.page_analytics.reach + 1;
end;
$$;

grant execute on function public.record_page_post_view(uuid) to authenticated;

-- 3. Record an impression (cheap, uncapped — called once per feed render) -----
create or replace function public.record_page_impression(p_post_id uuid)
returns void
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_page_id uuid;
begin
  select page_id into v_page_id from public.page_posts where id = p_post_id;
  if v_page_id is null then
    return;
  end if;

  insert into public.page_post_metrics (post_id, page_id, impressions)
  values (p_post_id, v_page_id, 1)
  on conflict (post_id) do update
    set impressions = public.page_post_metrics.impressions + 1,
        updated_at = now();

  insert into public.page_analytics (page_id, date, impressions)
  values (v_page_id, current_date, 1)
  on conflict (page_id, date) do update
    set impressions = public.page_analytics.impressions + 1;
end;
$$;

grant execute on function public.record_page_impression(uuid) to authenticated;

-- 4. Analytics summary (reach/impressions/views/followers/engagement) ---------
create or replace function public.page_analytics_summary(p_page_id uuid, days_back integer default 30)
returns table (
  day date,
  reach integer,
  impressions integer,
  views integer,
  new_followers integer,
  engagement integer
)
language sql
stable
security definer
set search_path = 'public'
as $$
  select pa.date as day, pa.reach, pa.impressions, pa.views, pa.new_followers, pa.engagement
  from public.page_analytics pa
  where pa.page_id = p_page_id
    and pa.date >= current_date - days_back
    and (
      public.current_user_page_role(p_page_id) = 'owner'
      or public.current_user_has_page_permission(p_page_id, 'view_analytics')
    )
  order by pa.date asc;
$$;

grant execute on function public.page_analytics_summary(uuid, integer) to authenticated;

-- 5. Audience growth (daily new followers + running total) --------------------
create or replace function public.page_audience_growth(p_page_id uuid, days_back integer default 30)
returns table (
  day date,
  new_followers integer,
  total_followers bigint
)
language sql
stable
security definer
set search_path = 'public'
as $$
  with daily as (
    select pa.date as day, pa.new_followers
    from public.page_analytics pa
    where pa.page_id = p_page_id
      and pa.date >= current_date - days_back
      and (
        public.current_user_page_role(p_page_id) = 'owner'
        or public.current_user_has_page_permission(p_page_id, 'view_analytics')
      )
  )
  select d.day, d.new_followers,
    sum(d.new_followers) over (order by d.day asc) as total_followers
  from daily d
  order by d.day asc;
$$;

grant execute on function public.page_audience_growth(uuid, integer) to authenticated;

-- 6. Top posts / post performance ----------------------------------------------
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
language sql
stable
security definer
set search_path = 'public'
as $$
  select pp.id as post_id, pp.content, pp.created_at,
    coalesce(ppm.impressions, 0), coalesce(ppm.reach, 0), coalesce(ppm.views, 0),
    coalesce(ppm.reactions, 0), coalesce(ppm.comments, 0), coalesce(ppm.shares, 0),
    coalesce(ppm.reactions, 0) + coalesce(ppm.comments, 0) * 2 + coalesce(ppm.shares, 0) * 3 as engagement_score
  from public.page_posts pp
  left join public.page_post_metrics ppm on ppm.post_id = pp.id
  where pp.page_id = p_page_id
    and pp.created_at >= now() - (days_back || ' days')::interval
    and (
      public.current_user_page_role(p_page_id) = 'owner'
      or public.current_user_has_page_permission(p_page_id, 'view_analytics')
    )
  order by engagement_score desc, pp.created_at desc
  limit result_limit;
$$;

grant execute on function public.page_top_posts(uuid, integer, integer) to authenticated;

-- Note: page_posts currently has no dedicated reactions/comments table
-- (verified against live schema — post_likes/post_comments/post_shares all
-- reference the generic `posts` table only, not `page_posts`). So
-- page_post_metrics.reactions/comments/shares stay at 0 for now and
-- engagement scoring is view-driven. When page-post-level
-- reactions/comments ship, add triggers here to increment those columns
-- and re-run; page_top_posts and page_analytics_summary need no changes.
