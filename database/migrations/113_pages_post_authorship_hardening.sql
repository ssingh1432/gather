-- 113_pages_post_authorship_hardening.sql
-- COMMAND 3: Professional Pages post authorship correctness.
-- Page-only. Keeps page_posts and page_visitor_posts as separate Page post
-- types; no duplicate authorship columns or identity tables are introduced.

-- Page-authored posts: the authenticated user is the author recorded by the
-- database. RLS still requires manage_content, so assigning the identity does
-- not grant Page permissions.
create or replace function public.prepare_page_post_author()
returns trigger
language plpgsql
security definer
set search_path = 'public'
as $$
begin
  if tg_op = 'INSERT' then
    if auth.uid() is null then
      raise exception 'Authentication is required to create a Page post.';
    end if;
    new.author_id := auth.uid();
  end if;
  return new;
end;
$$;

drop trigger if exists trg_prepare_page_post_author on public.page_posts;
create trigger trg_prepare_page_post_author
  before insert on public.page_posts
  for each row execute function public.prepare_page_post_author();

-- Visitor-authored posts: the database owns author_id. The destination Page
-- and follower requirement are also checked server-side. This prevents a
-- client from impersonating another Gather user or the Page owner.
create or replace function public.prepare_page_visitor_post()
returns trigger
language plpgsql
security definer
set search_path = 'public'
as $$
begin
  if tg_op = 'INSERT' then
    if auth.uid() is null then
      raise exception 'Authentication is required to post on a Page.';
    end if;

    if not exists (
      select 1
      from public.pages p
      where p.id = new.page_id
        and p.status = 'published'
        and p.deleted_at is null
        and p.allow_visitor_posts = true
    ) then
      raise exception 'Visitor posts are not enabled for this Page.';
    end if;

    if not exists (
      select 1
      from public.page_followers f
      where f.page_id = new.page_id
        and f.user_id = auth.uid()
    ) then
      raise exception 'You must follow this Page before posting.';
    end if;

    -- Never trust Flutter/client supplied identity. auth.uid() is authoritative.
    new.author_id := auth.uid();

    if exists (
      select 1
      from public.pages p
      where p.id = new.page_id
        and p.visitor_posts_require_approval = true
    ) then
      new.status := 'pending';
    else
      new.status := 'published';
    end if;
  end if;

  if tg_op = 'UPDATE' and new.page_id is distinct from old.page_id then
    raise exception 'A visitor post cannot be moved to a different Page.';
  end if;

  if tg_op = 'UPDATE' and new.author_id is distinct from old.author_id then
    raise exception 'A visitor post cannot be reassigned to a different author.';
  end if;

  if tg_op = 'UPDATE'
     and new.status is distinct from old.status
     and not public.current_user_has_page_permission(new.page_id, 'manage_content') then
    raise exception 'Only Page staff can moderate visitor posts.';
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

-- Keep the RLS rules explicit: Page posts require Page content-management
-- permission; visitor posts require the authenticated author, destination
-- Page, visitor-post setting, and existing follower requirement.
drop policy if exists page_posts_insert on public.page_posts;
create policy page_posts_insert on public.page_posts
  for insert with check (
    author_id = auth.uid()
    and public.current_user_has_page_permission(page_id, 'manage_content')
  );

drop policy if exists page_visitor_posts_insert on public.page_visitor_posts;
create policy page_visitor_posts_insert on public.page_visitor_posts
  for insert with check (
    author_id = auth.uid()
    and exists (
      select 1
      from public.pages p
      where p.id = page_id
        and p.status = 'published'
        and p.deleted_at is null
        and p.allow_visitor_posts = true
    )
    and exists (
      select 1
      from public.page_followers f
      where f.page_id = page_id
        and f.user_id = auth.uid()
    )
  );
