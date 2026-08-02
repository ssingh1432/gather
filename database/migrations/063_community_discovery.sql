-- 063_community_discovery.sql
-- Step 12: Discovery (trending, suggested, categories, search,
-- recommendations, recently active, nearby-future-ready, verified filter)
--
-- Categories, tags, and a plain substring name search already existed
-- (migration 057-ish) — this migration adds what was still missing:
-- activity tracking for "recently active", velocity-based trending,
-- personalized suggestions, typo-tolerant trigram search, and
-- future-ready lat/lng columns + a haversine nearby RPC (no PostGIS
-- required, since Gather doesn't need spatial indexing at this scale yet).

begin;

set local search_path to public, extensions;

-- ---------------------------------------------------------------------------
-- 1. Recently Active tracking
-- ---------------------------------------------------------------------------
alter table public.communities
  add column if not exists last_activity_at timestamptz not null default now();

create index if not exists idx_communities_last_activity on public.communities(last_activity_at desc);

create or replace function public.touch_community_activity()
returns trigger
language plpgsql
security definer
set search_path = 'public'
as $$
begin
  update public.communities set last_activity_at = now() where id = new.community_id;
  return new;
end;
$$;

drop trigger if exists trg_posts_touch_community_activity on public.posts;
create trigger trg_posts_touch_community_activity
  after insert on public.posts
  for each row
  when (new.community_id is not null)
  execute function public.touch_community_activity();

drop trigger if exists trg_chat_touch_community_activity on public.community_chat_messages;
create trigger trg_chat_touch_community_activity
  after insert on public.community_chat_messages
  for each row execute function public.touch_community_activity();

-- ---------------------------------------------------------------------------
-- 2. Future-ready location (Nearby)
-- ---------------------------------------------------------------------------
alter table public.communities
  add column if not exists latitude double precision,
  add column if not exists longitude double precision;

alter table public.communities
  drop constraint if exists communities_latitude_chk,
  drop constraint if exists communities_longitude_chk;
alter table public.communities
  add constraint communities_latitude_chk check (latitude is null or latitude between -90 and 90),
  add constraint communities_longitude_chk check (longitude is null or longitude between -180 and 180);

create index if not exists idx_communities_geo on public.communities(latitude, longitude) where latitude is not null and longitude is not null;

-- ---------------------------------------------------------------------------
-- 3. Trending — recent post + join velocity, not just raw member_count
-- ---------------------------------------------------------------------------
create or replace function public.trending_communities(days_back integer default 7, result_limit integer default 20)
returns setof public.communities
language sql
stable
security invoker
set search_path = 'public'
as $$
  select c.*
  from public.communities c
  left join lateral (
    select count(*) as recent_posts
    from public.posts p
    where p.community_id = c.id
      and p.is_removed = false
      and p.created_at > now() - make_interval(days => days_back)
  ) rp on true
  left join lateral (
    select count(*) as recent_joins
    from public.community_memberships m
    where m.community_id = c.id
      and m.created_at > now() - make_interval(days => days_back)
  ) rj on true
  order by (rp.recent_posts * 2 + rj.recent_joins * 3) desc, c.member_count desc, c.name asc
  limit result_limit;
$$;

-- ---------------------------------------------------------------------------
-- 4. Suggested — same category as communities the user already belongs to,
--    excluding ones already joined. Runs SECURITY INVOKER so normal RLS on
--    `communities` and `community_memberships` applies automatically —
--    private communities the caller can't see are never suggested.
-- ---------------------------------------------------------------------------
create or replace function public.suggested_communities_for_user(p_user_id uuid, result_limit integer default 10)
returns setof public.communities
language sql
stable
security invoker
set search_path = 'public'
as $$
  with my_categories as (
    select distinct c.category_id
    from public.community_memberships m
    join public.communities c on c.id = m.community_id
    where m.user_id = p_user_id and c.category_id is not null
  ),
  already_joined as (
    select community_id from public.community_memberships where user_id = p_user_id
  )
  select c.*
  from public.communities c
  where c.category_id in (select category_id from my_categories)
    and c.id not in (select community_id from already_joined)
  order by c.member_count desc, c.last_activity_at desc
  limit result_limit;
$$;

-- ---------------------------------------------------------------------------
-- 5. Typo-tolerant search (pg_trgm, already enabled — used by post search)
-- ---------------------------------------------------------------------------
create index if not exists idx_communities_name_trgm on public.communities using gin (name extensions.gin_trgm_ops);
create index if not exists idx_communities_description_trgm on public.communities using gin (description extensions.gin_trgm_ops);

create or replace function public.search_communities(p_query text, result_limit integer default 20)
returns setof public.communities
language sql
stable
security invoker
set search_path = 'public, extensions'
as $$
  select c.*
  from public.communities c
  where p_query = '' or c.name operator(extensions.%) p_query or c.description operator(extensions.%) p_query or c.name ilike '%' || p_query || '%'
  order by
    case when p_query = '' then 0 else greatest(extensions.similarity(c.name, p_query), extensions.similarity(coalesce(c.description, ''), p_query)) end desc,
    c.member_count desc
  limit result_limit;
$$;

-- ---------------------------------------------------------------------------
-- 6. Nearby (future-ready) — haversine distance, no PostGIS dependency
-- ---------------------------------------------------------------------------
create or replace function public.nearby_communities(p_lat double precision, p_lng double precision, p_radius_km double precision default 50, result_limit integer default 20)
returns table (community public.communities, distance_km double precision)
language sql
stable
security invoker
set search_path = 'public'
as $$
  with distances as (
    select
      c as community,
      6371 * acos(
        least(1.0, greatest(-1.0,
          cos(radians(p_lat)) * cos(radians(c.latitude)) * cos(radians(c.longitude) - radians(p_lng))
          + sin(radians(p_lat)) * sin(radians(c.latitude))
        ))
      ) as distance_km
    from public.communities c
    where c.latitude is not null and c.longitude is not null
  )
  select community, distance_km
  from distances
  where distance_km <= p_radius_km
  order by distance_km asc
  limit result_limit;
$$;

grant execute on function public.trending_communities(integer, integer) to authenticated;
grant execute on function public.suggested_communities_for_user(uuid, integer) to authenticated;
grant execute on function public.search_communities(text, integer) to authenticated;
grant execute on function public.nearby_communities(double precision, double precision, double precision, integer) to authenticated;

commit;
