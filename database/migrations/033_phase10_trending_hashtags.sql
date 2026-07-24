-- Phase 10 Step 6: trending hashtags
-- Unnests posts.tags over a recent window and returns the most-used tags.
-- security definer so it can read across all public posts consistently
-- regardless of the caller's own visibility, matching how tags already
-- behave as a public discovery surface (tag chips link to /search).

create or replace function public.trending_hashtags(days_back int default 7, result_limit int default 15)
returns table (tag text, post_count bigint)
language sql
security definer
set search_path = public
stable
as $$
  select unnest(tags) as tag, count(*) as post_count
  from public.posts
  where created_at > now() - make_interval(days => days_back)
    and is_removed = false
    and visibility = 'public'
    and array_length(tags, 1) > 0
  group by tag
  order by post_count desc, tag asc
  limit result_limit;
$$;

grant execute on function public.trending_hashtags(int, int) to authenticated, anon;
