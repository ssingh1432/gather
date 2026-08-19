-- 114_pages_visitor_post_authority.sql
-- COMMAND 3 follow-up: visitor posts are for normal followers, not Page
-- managers. This prevents Page owners/admins/staff from creating a visitor
-- post whose author_id would equal a Page management identity.

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
      select 1 from public.pages p
      where p.id = new.page_id
        and p.status = 'published'
        and p.deleted_at is null
        and p.allow_visitor_posts = true
    ) then
      raise exception 'Visitor posts are not enabled for this Page.';
    end if;

    if public.current_user_has_page_permission(new.page_id, 'manage_content') then
      raise exception 'Page managers must publish Page-authored posts.';
    end if;

    if not exists (
      select 1 from public.page_followers f
      where f.page_id = new.page_id and f.user_id = auth.uid()
    ) then
      raise exception 'You must follow this Page before posting.';
    end if;

    new.author_id := auth.uid();

    if exists (
      select 1 from public.pages p
      where p.id = new.page_id and p.visitor_posts_require_approval = true
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

drop policy if exists page_visitor_posts_insert on public.page_visitor_posts;
create policy page_visitor_posts_insert on public.page_visitor_posts
  for insert with check (
    author_id = auth.uid()
    and not public.current_user_has_page_permission(page_id, 'manage_content')
    and exists (
      select 1 from public.pages p
      where p.id = page_id
        and p.status = 'published'
        and p.deleted_at is null
        and p.allow_visitor_posts = true
    )
    and exists (
      select 1 from public.page_followers f
      where f.page_id = page_id and f.user_id = auth.uid()
    )
  );
