-- 085_pages_discovery_step12.sql
-- Professional Page System — Step 12 (Discovery)
-- Mirrors 063_community_discovery.sql's approach for the equivalent
-- Community feature: typo-tolerant trigram search, categories, a
-- future-ready lat/lng + haversine nearby RPC (no PostGIS dependency),
-- suggested (based on the caller's existing follows), trending (recent
-- follower growth from page_analytics, Step 11), and a verified directory.
-- All RPCs are SECURITY DEFINER, so each re-applies the same visibility
-- rule as the `pages_select` RLS policy (published, not soft-deleted)
-- since RLS itself is bypassed inside a SECURITY DEFINER function.
-- pg_trgm functions/operator classes live in the `extensions` schema on
-- this project, so they're referenced with an explicit `extensions.`
-- prefix rather than relying on search_path (confirmed against
-- 072_pages_core_schema.sql's existing `extensions.gin_trgm_ops` index and
-- 063's `extensions.similarity(...)` calls).

-- idx_pages_name_trgm / idx_pages_username_trgm already exist from
-- 072_pages_core_schema.sql; only description search is new here.
create index if not exists idx_pages_description_trgm on public.pages using gin (description extensions.gin_trgm_ops);
create index if not exists idx_pages_country on public.pages (country) where deleted_at is null;
create index if not exists idx_pages_category on public.pages (category_id) where deleted_at is null;

-- Future-ready geo columns (mirrors communities.latitude/longitude from
-- 063_community_discovery.sql) — nullable, no UI sets them yet.
alter table public.pages
  add column if not exists latitude double precision,
  add column if not exists longitude double precision;

alter table public.pages
  drop constraint if exists pages_latitude_chk,
  drop constraint if exists pages_longitude_chk;

alter table public.pages
  add constraint pages_latitude_chk check (latitude is null or latitude between -90 and 90),
  add constraint pages_longitude_chk check (longitude is null or longitude between -180 and 180);

create index if not exists idx_pages_geo on public.pages (latitude, longitude) where latitude is not null and longitude is not null;

-- 1. Search --------------------------------------------------------------
create or replace function public.page_search(
  p_query text default null,
  p_category_id uuid default null,
  p_page_type text default null,
  p_verified_only boolean default false,
  result_limit integer default 20,
  result_offset integer default 0
)
returns table (
  id uuid, username text, name text, page_type text, category_id uuid,
  description text, logo_url text, cover_url text, country text, location text,
  verification_status text, follower_count integer, rating_avg numeric, rating_count integer,
  relevance real
)
language sql
stable
security definer
set search_path = 'public'
as $$
  select p.id, p.username, p.name, p.page_type, p.category_id, p.description,
    p.logo_url, p.cover_url, p.country, p.location, p.verification_status,
    p.follower_count, p.rating_avg, p.rating_count,
    case when p_query is null or p_query = '' then 0
      else greatest(extensions.similarity(p.name, p_query), extensions.similarity(coalesce(p.description, ''), p_query))
    end as relevance
  from public.pages p
  where p.deleted_at is null
    and p.status = 'published'
    and (
      p_query is null or p_query = ''
      or p.name ilike '%' || p_query || '%'
      or extensions.similarity(p.name, p_query) > 0.15
      or extensions.similarity(coalesce(p.description, ''), p_query) > 0.15
    )
    and (p_category_id is null or p.category_id = p_category_id)
    and (p_page_type is null or p.page_type = p_page_type)
    and (not p_verified_only or p.verification_status = 'verified')
  order by (case when p_query is null or p_query = '' then 0 else 1 end) desc, relevance desc, p.follower_count desc
  limit result_limit offset result_offset;
$$;

grant execute on function public.page_search(text, uuid, text, boolean, integer, integer) to authenticated;

-- 2. Categories (with live page counts) -----------------------------------
create or replace function public.page_categories_list()
returns table (id uuid, name text, slug text, icon text, page_count bigint)
language sql
stable
security definer
set search_path = 'public'
as $$
  select c.id, c.name, c.slug, c.icon,
    count(p.id) filter (where p.deleted_at is null and p.status = 'published') as page_count
  from public.page_categories c
  left join public.pages p on p.category_id = c.id
  group by c.id, c.name, c.slug, c.icon
  order by page_count desc, c.name asc;
$$;

grant execute on function public.page_categories_list() to authenticated;

-- 3. Nearby — haversine distance against the new lat/lng columns, plus a
--    text-based fallback (country/location) for pages that haven't set
--    coordinates yet, since no UI currently captures them. -----------------
create or replace function public.page_nearby_geo(p_lat double precision, p_lng double precision, p_radius_km double precision default 50, result_limit integer default 20)
returns table (
  id uuid, username text, name text, page_type text, logo_url text, cover_url text,
  follower_count integer, rating_avg numeric, verification_status text, distance_km double precision
)
language sql
stable
security definer
set search_path = 'public'
as $$
  with distances as (
    select
      p.*,
      6371 * acos(
        least(1.0, greatest(-1.0,
          cos(radians(p_lat)) * cos(radians(p.latitude)) * cos(radians(p.longitude) - radians(p_lng))
          + sin(radians(p_lat)) * sin(radians(p.latitude))
        ))
      ) as distance_km
    from public.pages p
    where p.latitude is not null and p.longitude is not null
      and p.deleted_at is null and p.status = 'published'
  )
  select id, username, name, page_type, logo_url, cover_url, follower_count, rating_avg, verification_status, distance_km
  from distances
  where distance_km <= p_radius_km
  order by distance_km asc
  limit result_limit;
$$;

grant execute on function public.page_nearby_geo(double precision, double precision, double precision, integer) to authenticated;

create or replace function public.page_nearby(
  p_country text default null,
  p_location text default null,
  result_limit integer default 20
)
returns table (
  id uuid, username text, name text, page_type text, logo_url text, cover_url text,
  country text, location text, follower_count integer, rating_avg numeric, verification_status text
)
language sql
stable
security definer
set search_path = 'public'
as $$
  select p.id, p.username, p.name, p.page_type, p.logo_url, p.cover_url,
    p.country, p.location, p.follower_count, p.rating_avg, p.verification_status
  from public.pages p
  where p.deleted_at is null
    and p.status = 'published'
    and (
      (p_location is not null and p.location ilike '%' || p_location || '%')
      or (p_country is not null and p.country = p_country)
    )
  order by
    (case when p_location is not null and p.location ilike '%' || p_location || '%' then 0 else 1 end),
    p.follower_count desc
  limit result_limit;
$$;

grant execute on function public.page_nearby(text, text, integer) to authenticated;

-- 4. Suggested (categories/types the caller already follows, excluding
--    pages they already follow) ---------------------------------------------
create or replace function public.page_suggested(result_limit integer default 10)
returns table (
  id uuid, username text, name text, page_type text, category_id uuid, logo_url text,
  cover_url text, follower_count integer, rating_avg numeric, verification_status text, match_reason text
)
language sql
stable
security definer
set search_path = 'public'
as $$
  with my_follows as (
    select page_id from public.page_followers where user_id = auth.uid()
  ),
  my_categories as (
    select distinct p.category_id, p.page_type from public.pages p
    join my_follows f on f.page_id = p.id
    where p.category_id is not null or p.page_type is not null
  )
  select p.id, p.username, p.name, p.page_type, p.category_id, p.logo_url, p.cover_url,
    p.follower_count, p.rating_avg, p.verification_status,
    case when p.category_id in (select category_id from my_categories where category_id is not null)
      then 'Similar to pages you follow' else 'Popular on Gather' end as match_reason
  from public.pages p
  where p.deleted_at is null
    and p.status = 'published'
    and p.id not in (select page_id from my_follows)
    and auth.uid() is not null
  order by
    (case when p.category_id in (select category_id from my_categories where category_id is not null)
          or p.page_type in (select page_type from my_categories where page_type is not null)
      then 0 else 1 end),
    p.follower_count desc,
    coalesce(p.rating_avg, 0) desc
  limit result_limit;
$$;

grant execute on function public.page_suggested(integer) to authenticated;

-- 5. Trending (highest net new followers in the trailing window, per
--    Step 11's page_analytics daily rollups) --------------------------------
create or replace function public.page_trending(days_back integer default 7, result_limit integer default 10)
returns table (
  id uuid, username text, name text, page_type text, logo_url text, cover_url text,
  follower_count integer, rating_avg numeric, verification_status text, growth integer
)
language sql
stable
security definer
set search_path = 'public'
as $$
  select p.id, p.username, p.name, p.page_type, p.logo_url, p.cover_url,
    p.follower_count, p.rating_avg, p.verification_status,
    coalesce(g.growth, 0) as growth
  from public.pages p
  join lateral (
    select sum(pa.new_followers)::integer as growth
    from public.page_analytics pa
    where pa.page_id = p.id and pa.date >= current_date - days_back
  ) g on true
  where p.deleted_at is null
    and p.status = 'published'
    and coalesce(g.growth, 0) > 0
  order by g.growth desc, p.follower_count desc
  limit result_limit;
$$;

grant execute on function public.page_trending(integer, integer) to authenticated;

-- 6. Verified pages directory -------------------------------------------------
create or replace function public.page_verified_list(result_limit integer default 20, result_offset integer default 0)
returns table (
  id uuid, username text, name text, page_type text, category_id uuid, logo_url text,
  cover_url text, follower_count integer, rating_avg numeric
)
language sql
stable
security definer
set search_path = 'public'
as $$
  select p.id, p.username, p.name, p.page_type, p.category_id, p.logo_url, p.cover_url,
    p.follower_count, p.rating_avg
  from public.pages p
  where p.deleted_at is null
    and p.status = 'published'
    and p.verification_status = 'verified'
  order by p.follower_count desc
  limit result_limit offset result_offset;
$$;

grant execute on function public.page_verified_list(integer, integer) to authenticated;
