-- 100_pages_visitor_posts_and_rules.sql
-- Pages-only UX completion: public visitor posts + owner moderation/rules.
-- Additive. Does not alter any non-Page tables or features.

alter table public.pages
  add column if not exists allow_visitor_posts boolean not null default true,
  add column if not exists visitor_posts_require_approval boolean not null default false;

create table if not exists public.page_rules (
  id uuid primary key default gen_random_uuid(),
  page_id uuid not null references public.pages(id) on delete cascade,
  title text not null check (char_length(title) between 1 and 120),
  body text not null check (char_length(body) between 1 and 2000),
  sort_order integer not null default 0,
  active boolean not null default true,
  created_by uuid references public.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_page_rules_page on public.page_rules(page_id, sort_order) where active;

create table if not exists public.page_visitor_posts (
  id uuid primary key default gen_random_uuid(),
  page_id uuid not null references public.pages(id) on delete cascade,
  author_id uuid not null references public.users(id) on delete cascade,
  content text not null check (char_length(trim(content)) between 1 and 5000),
  status text not null default 'published'
    check (status in ('pending','published','hidden','removed')),
  reviewed_by uuid references public.users(id) on delete set null,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_page_visitor_posts_page on public.page_visitor_posts(page_id, created_at desc) where status = 'published';
create index if not exists idx_page_visitor_posts_pending on public.page_visitor_posts(page_id, created_at desc) where status = 'pending';
create index if not exists idx_page_visitor_posts_author on public.page_visitor_posts(author_id, created_at desc);

alter table public.page_rules enable row level security;
alter table public.page_visitor_posts enable row level security;

drop policy if exists page_rules_select on public.page_rules;
create policy page_rules_select on public.page_rules
  for select using (
    active and exists (
      select 1 from public.pages p
      where p.id = page_id and p.status = 'published' and p.deleted_at is null
    )
  );

drop policy if exists page_rules_manage on public.page_rules;
create policy page_rules_manage on public.page_rules
  for all using (public.current_user_has_page_permission(page_id, 'manage_settings'))
  with check (public.current_user_has_page_permission(page_id, 'manage_settings'));

grant select, insert, update, delete on public.page_rules to authenticated;

drop policy if exists page_visitor_posts_select on public.page_visitor_posts;
create policy page_visitor_posts_select on public.page_visitor_posts
  for select using (
    (
      status = 'published'
      and exists (
        select 1 from public.pages p
        where p.id = page_id and p.status = 'published' and p.deleted_at is null
      )
    )
    or author_id = auth.uid()
    or public.current_user_has_page_permission(page_id, 'manage_content')
  );

drop policy if exists page_visitor_posts_insert on public.page_visitor_posts;
create policy page_visitor_posts_insert on public.page_visitor_posts
  for insert with check (
    author_id = auth.uid()
    and exists (
      select 1 from public.pages p
      where p.id = page_id
        and p.status = 'published'
        and p.deleted_at is null
        and p.allow_visitor_posts = true
    )
  );

drop policy if exists page_visitor_posts_update on public.page_visitor_posts;
create policy page_visitor_posts_update on public.page_visitor_posts
  for update using (
    author_id = auth.uid()
    or public.current_user_has_page_permission(page_id, 'manage_content')
  ) with check (
    author_id = auth.uid()
    or public.current_user_has_page_permission(page_id, 'manage_content')
  );

drop policy if exists page_visitor_posts_delete on public.page_visitor_posts;
create policy page_visitor_posts_delete on public.page_visitor_posts
  for delete using (
    author_id = auth.uid()
    or public.current_user_has_page_permission(page_id, 'manage_content')
  );

grant select, insert, update, delete on public.page_visitor_posts to authenticated;

create or replace function public.prepare_page_visitor_post()
returns trigger
language plpgsql
security definer
set search_path = 'public'
as $$
begin
  if tg_op = 'INSERT' then
    if not exists (
      select 1 from public.pages p
      where p.id = new.page_id
        and p.status = 'published'
        and p.deleted_at is null
        and p.allow_visitor_posts = true
    ) then
      raise exception 'Visitor posts are not enabled for this page.';
    end if;
    if exists (
      select 1 from public.pages p
      where p.id = new.page_id and p.visitor_posts_require_approval = true
    ) then
      new.status := 'pending';
    else
      new.status := 'published';
    end if;
  end if;

  if tg_op = 'UPDATE'
     and new.status is distinct from old.status
     and not public.current_user_has_page_permission(new.page_id, 'manage_content') then
    raise exception 'Only page staff can moderate visitor posts.';
  end if;

  if tg_op = 'UPDATE'
     and public.current_user_has_page_permission(new.page_id, 'manage_content')
     and new.status is distinct from old.status then
    new.reviewed_by := auth.uid();
    new.reviewed_at := now();
  end if;

  return new;
end;
$$;

drop trigger if exists trg_prepare_page_visitor_post on public.page_visitor_posts;
create trigger trg_prepare_page_visitor_post
  before insert or update on public.page_visitor_posts
  for each row execute function public.prepare_page_visitor_post();

drop trigger if exists trg_page_rules_touch_updated_at on public.page_rules;
create trigger trg_page_rules_touch_updated_at
  before update on public.page_rules
  for each row execute function public.touch_updated_at();

drop trigger if exists trg_page_visitor_posts_touch_updated_at on public.page_visitor_posts;
create trigger trg_page_visitor_posts_touch_updated_at
  before update on public.page_visitor_posts
  for each row execute function public.touch_updated_at();
