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

-- Update the installed Home Feed function in place. Only the Page-owner
-- engagement projection is replaced; personal/community branches remain byte-for-byte intact.
do $migration$
declare
  v_def text;
begin
  select pg_get_functiondef('public.get_home_feed_cursor(uuid,integer,boolean,timestamptz,uuid)'::regprocedure)
    into v_def;

  v_def := replace(
    v_def,
    $old$0::bigint as like_count, 0::bigint as comment_count, 0::integer as share_count,
      false as is_liked, false as is_bookmarked, false as is_following,$old$,
    $new$coalesce((select count(*) from public.page_post_likes ppl where ppl.post_id = pp.id), 0)::bigint as like_count,
      coalesce((select count(*) from public.page_post_comments ppc where ppc.post_id = pp.id), 0)::bigint as comment_count,
      coalesce((select count(*) from public.page_post_shares pps where pps.post_id = pp.id), 0)::integer as share_count,
      exists (select 1 from public.page_post_likes ppl_me where ppl_me.post_id = pp.id and ppl_me.user_id = $1) as is_liked, false as is_bookmarked, false as is_following,$new$
  );

  if v_def is null or position('page_post_likes' in v_def) = 0 then
    raise exception 'Expected Page-owner Home Feed branch was not found; refusing to modify the function';
  end if;

  execute v_def;
end
$migration$;
