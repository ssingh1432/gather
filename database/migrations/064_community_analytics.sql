-- 064_community_analytics.sql
-- Step 13: Community Analytics (member growth, DAU, retention, popular
-- posts, moderator activity, community health)
--
-- All analytics RPCs are SECURITY DEFINER + explicitly gated by the new
-- `view_analytics` permission (same pattern as get_community_report_queue
-- in migration 058), rather than SECURITY INVOKER + RLS, because these
-- return aggregates across all members' activity — not per-row data an
-- individual member could already see via normal RLS — so the
-- authorization check has to happen inside the function itself.

begin;

-- ---------------------------------------------------------------------------
-- 0. New permission: view_analytics (owner/admin by default via the
--    existing cross-join pattern in migration 052; also grant moderator,
--    since community health/reports volume informs moderation decisions).
-- ---------------------------------------------------------------------------
insert into public.community_permissions (key, label, description) values
  ('view_analytics', 'View analytics', 'View member growth, activity, retention, popular posts, and moderator activity for the community.')
on conflict (key) do nothing;

insert into public.community_role_permissions (role, permission_key, allowed)
select r.role, 'view_analytics', true
from (values ('owner'), ('admin')) as r(role)
on conflict (role, permission_key) do nothing;

insert into public.community_role_permissions (role, permission_key, allowed) values
  ('moderator', 'view_analytics', true)
on conflict (role, permission_key) do nothing;

-- ---------------------------------------------------------------------------
-- 1. Membership join/leave event log — community_memberships rows are
--    hard-deleted on leave, so without this a growth chart could never
--    show leaves, only current totals. Historical leaves before this
--    migration aren't recoverable; growth charts before today will show
--    joins only for the "leaves" series, which is documented in the RPC.
-- ---------------------------------------------------------------------------
create table if not exists public.community_membership_events (
  id uuid primary key default gen_random_uuid(),
  community_id uuid not null references public.communities(id) on delete cascade,
  user_id uuid not null references public.users(id) on delete cascade,
  event_type text not null check (event_type in ('joined', 'left')),
  created_at timestamptz not null default now()
);

create index if not exists idx_community_membership_events_community_date on public.community_membership_events(community_id, created_at);

grant select on public.community_membership_events to authenticated;
alter table public.community_membership_events enable row level security;

drop policy if exists community_membership_events_read on public.community_membership_events;
create policy community_membership_events_read on public.community_membership_events
  for select using (public.current_user_community_permission(community_id, 'view_analytics') or public.is_admin_or_mod());

-- No insert/update/delete policy for regular users — these rows are only
-- ever written by the triggers below (SECURITY DEFINER), never directly.

create or replace function public.log_membership_joined()
returns trigger
language plpgsql
security definer
set search_path = 'public'
as $$
begin
  insert into public.community_membership_events (community_id, user_id, event_type)
  values (new.community_id, new.user_id, 'joined');
  return new;
end;
$$;

create or replace function public.log_membership_left()
returns trigger
language plpgsql
security definer
set search_path = 'public'
as $$
begin
  insert into public.community_membership_events (community_id, user_id, event_type)
  values (old.community_id, old.user_id, 'left');
  return old;
end;
$$;

drop trigger if exists trg_membership_joined on public.community_memberships;
create trigger trg_membership_joined
  after insert on public.community_memberships
  for each row execute function public.log_membership_joined();

drop trigger if exists trg_membership_left on public.community_memberships;
create trigger trg_membership_left
  after delete on public.community_memberships
  for each row execute function public.log_membership_left();

-- Backfill "joined" events for existing memberships so the growth chart
-- has full history from day one (leaves before this migration are not
-- recoverable and are simply absent, not misrepresented as zero).
insert into public.community_membership_events (community_id, user_id, event_type, created_at)
select community_id, user_id, 'joined', created_at
from public.community_memberships m
where not exists (
  select 1 from public.community_membership_events e
  where e.community_id = m.community_id and e.user_id = m.user_id and e.event_type = 'joined'
);

-- ---------------------------------------------------------------------------
-- 2. Member growth — daily joins/leaves/net over a date range.
-- ---------------------------------------------------------------------------
create or replace function public.community_member_growth(p_community_id uuid, days_back integer default 30)
returns table (day date, joins bigint, leaves bigint, net bigint)
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
    select generate_series(current_date - (days_back - 1), current_date, interval '1 day')::date as day
  ),
  daily as (
    select e.created_at::date as day,
           count(*) filter (where e.event_type = 'joined') as joins,
           count(*) filter (where e.event_type = 'left') as leaves
    from public.community_membership_events e
    where e.community_id = p_community_id
      and e.created_at >= current_date - (days_back - 1)
    group by e.created_at::date
  )
  select d.day, coalesce(daily.joins, 0), coalesce(daily.leaves, 0), coalesce(daily.joins, 0) - coalesce(daily.leaves, 0)
  from days d
  left join daily on daily.day = d.day
  order by d.day;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Daily Active Members — distinct members who posted, commented,
--    liked, or chatted in the community on a given day.
-- ---------------------------------------------------------------------------
create or replace function public.community_daily_active_members(p_community_id uuid, days_back integer default 30)
returns table (day date, active_members bigint)
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
    select generate_series(current_date - (days_back - 1), current_date, interval '1 day')::date as day
  ),
  activity as (
    select p.author_id as user_id, p.created_at::date as day
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
    select day, count(distinct user_id) as active_members
    from activity
    group by day
  )
  select d.day, coalesce(daily.active_members, 0)
  from days d
  left join daily on daily.day = d.day
  order by d.day;
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. Retention — of members who joined in a cohort window, what % were
--    active (per the same signal as #3) in the last 7 days.
-- ---------------------------------------------------------------------------
create or replace function public.community_retention(p_community_id uuid)
returns table (cohort text, cohort_size bigint, retained_count bigint, retention_pct numeric)
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
  with recent_activity as (
    select distinct user_id from (
      select author_id as user_id from public.posts where community_id = p_community_id and created_at >= now() - interval '7 days'
      union
      select sender_id from public.community_chat_messages where community_id = p_community_id and created_at >= now() - interval '7 days'
      union
      select pc.user_id from public.post_comments pc join public.posts p on p.id = pc.post_id
        where p.community_id = p_community_id and pc.created_at >= now() - interval '7 days'
      union
      select pl.user_id from public.post_likes pl join public.posts p on p.id = pl.post_id
        where p.community_id = p_community_id and pl.created_at >= now() - interval '7 days'
    ) a
  ),
  cohorts as (
    select
      case
        when m.created_at >= now() - interval '30 days' then 'Joined last 30 days'
        when m.created_at >= now() - interval '90 days' then 'Joined 31-90 days ago'
        else 'Joined 90+ days ago'
      end as cohort,
      m.user_id
    from public.community_memberships m
    where m.community_id = p_community_id
  )
  select
    c.cohort,
    count(*) as cohort_size,
    count(*) filter (where ra.user_id is not null) as retained_count,
    round(100.0 * count(*) filter (where ra.user_id is not null) / greatest(count(*), 1), 1) as retention_pct
  from cohorts c
  left join recent_activity ra on ra.user_id = c.user_id
  group by c.cohort
  order by c.cohort;
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. Popular posts — engagement-weighted, within a window.
-- ---------------------------------------------------------------------------
create or replace function public.community_popular_posts(p_community_id uuid, days_back integer default 30, result_limit integer default 10)
returns table (
  post_id uuid,
  text_content text,
  author_id uuid,
  created_at timestamptz,
  view_count integer,
  reply_count integer,
  like_count bigint,
  engagement_score numeric
)
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
  select
    p.id, p.text_content, p.author_id, p.created_at,
    coalesce(p.view_count, 0),
    coalesce(p.reply_count, 0),
    coalesce(l.like_count, 0),
    coalesce(p.view_count, 0) * 1.0 + coalesce(p.reply_count, 0) * 3.0 + coalesce(l.like_count, 0) * 2.0 as engagement_score
  from public.posts p
  left join lateral (
    select count(*) as like_count from public.post_likes pl where pl.post_id = p.id
  ) l on true
  where p.community_id = p_community_id
    and p.is_removed = false
    and p.created_at >= now() - make_interval(days => days_back)
  order by engagement_score desc
  limit result_limit;
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. Moderator activity — from the existing community audit log.
-- ---------------------------------------------------------------------------
create or replace function public.community_moderator_activity(p_community_id uuid, days_back integer default 30)
returns table (actor_id uuid, username text, action_count bigint, last_action_at timestamptz)
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
  select l.actor_id, u.username, count(*), max(l.created_at)
  from public.community_audit_logs l
  left join public.users u on u.id = l.actor_id
  where l.community_id = p_community_id
    and l.created_at >= now() - make_interval(days => days_back)
    and l.actor_id is not null
  group by l.actor_id, u.username
  order by count(*) desc;
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. Community health — a transparent, documented composite score (0-100).
--    Formula (each component capped 0-100, then averaged):
--      * engagement:  min(100, (DAU today / member_count) * 500)   -- 20% active members/day -> 100
--      * momentum:    min(100, (posts in last 7d) * 5)             -- 20 posts/week -> 100
--      * retention:   the "Joined last 30 days" retention_pct as-is
--      * report_load: 100 - min(100, open_reports * 10)            -- 10+ open reports -> 0
--    health_score = average of the four components that have data
--    (report_load and retention always have data; engagement/momentum
--    are 0 for a brand-new community with no activity yet, which is
--    the honest answer, not a missing value).
-- ---------------------------------------------------------------------------
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

  select active_members into v_dau_today from public.community_daily_active_members(p_community_id, 1) order by day desc limit 1;
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
grant execute on function public.community_retention(uuid) to authenticated;
grant execute on function public.community_popular_posts(uuid, integer, integer) to authenticated;
grant execute on function public.community_moderator_activity(uuid, integer) to authenticated;
grant execute on function public.community_health_score(uuid) to authenticated;

commit;
