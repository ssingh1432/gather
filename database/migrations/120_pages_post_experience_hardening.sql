-- Professional Pages: finish Page-authored post Home Feed engagement and reporting.
-- Page-only. Personal/community post tables are untouched.

create table if not exists public.page_post_reports (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.page_posts(id) on delete cascade,
  reporter_id uuid not null references public.users(id) on delete cascade,
  category text not null,
  reason text,
  status text not null default 'pending' check (status in ('pending','reviewed','dismissed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (post_id, reporter_id)
);

create index if not exists idx_page_post_reports_post on public.page_post_reports(post_id, created_at desc);

alter table public.page_post_reports enable row level security;

drop policy if exists page_post_reports_insert on public.page_post_reports;
create policy page_post_reports_insert on public.page_post_reports
  for insert with check (
    auth.uid() = reporter_id
    and exists (
      select 1 from public.page_posts pp
      join public.pages pg on pg.id = pp.page_id
      where pp.id = post_id
        and pp.status = 'published' and pp.deleted_at is null
        and pg.status = 'published' and pg.deleted_at is null
    )
  );

drop policy if exists page_post_reports_select_own on public.page_post_reports;
create policy page_post_reports_select_own on public.page_post_reports
  for select using (auth.uid() = reporter_id);

grant select, insert on public.page_post_reports to authenticated;

-- Update the already-installed Home Feed function without copying or changing
-- the personal/community branches. The replacement is intentionally scoped to
-- the Page-owner hard-coded engagement projection from migration 117.
do $$
declare
  v_def text;
  v_old text := $$PAGE_OWNER_ENGAGEMENT_PLACEHOLDER$$;
  v_new text := $$PAGE_OWNER_ENGAGEMENT_REPLACEMENT$$;
begin
  select pg_get_functiondef('public.get_home_feed_cursor(uuid,integer,boolean,timestamptz,uuid)'::regprocedure)
    into v_def;

  v_def := replace(
    v_def,
    '0::bigint as like_count, 0::bigint as comment_count, 0::integer as share_count,\n      false as is_liked, false as is_bookmarked, false as is_following,',
    'coalesce((select count(*) from public.page_post_likes ppl where ppl.post_id = pp.id), 0)::bigint as like_count,\n      coalesce((select count(*) from public.page_post_comments ppc where ppc.post_id = pp.id), 0)::bigint as comment_count,\n      coalesce((select count(*) from public.page_post_shares pps where pps.post_id = pp.id), 0)::integer as share_count,\n      exists (select 1 from public.page_post_likes ppl_me where ppl_me.post_id = pp.id and ppl_me.user_id = $1) as is_liked, false as is_bookmarked, false as is_following,'
  );

  if v_def is null or position('page_post_likes' in v_def) = 0 then
    raise exception 'Expected Page-owner Home Feed branch was not found; refusing to modify the function';
  end if;

  execute v_def;
end $$;
