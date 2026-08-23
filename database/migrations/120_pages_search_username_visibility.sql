-- 120_pages_search_username_visibility.sql
-- Professional Pages — Search integrity hardening.
--
-- Confirmed defect: page_search() searched Page name/description but not the
-- Page username. A direct search for an existing published Page username could
-- therefore return no Page when the username was not present in its name or
-- description.
--
-- Scope: Professional Pages search only. No generic/community/personal search
-- behavior is changed.

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
      else greatest(
        extensions.similarity(p.username, p_query),
        extensions.similarity(p.name, p_query),
        extensions.similarity(coalesce(p.description, ''), p_query)
      )
    end as relevance
  from public.pages p
  where p.deleted_at is null
    and p.status = 'published'
    and (
      p_query is null or p_query = ''
      or p.username ilike '%' || p_query || '%'
      or p.name ilike '%' || p_query || '%'
      or extensions.similarity(p.username, p_query) > 0.15
      or extensions.similarity(p.name, p_query) > 0.15
      or extensions.similarity(coalesce(p.description, ''), p_query) > 0.15
    )
    and (p_category_id is null or p.category_id = p_category_id)
    and (p_page_type is null or p.page_type = p_page_type)
    and (not p_verified_only or p.verification_status = 'verified')
  order by (case when p_query is null or p_query = '' then 0 else 1 end) desc,
    relevance desc, p.follower_count desc
  limit result_limit offset result_offset;
$$;

grant execute on function public.page_search(text, uuid, text, boolean, integer, integer) to authenticated;
