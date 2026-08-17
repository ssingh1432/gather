-- 102_pages_visitor_posts_immutable_identity.sql
-- Pages-only fix: page_visitor_posts.page_id and author_id must never change
-- after creation.
--
-- Gap found during Stage 1 (visitor posts end-to-end) audit:
-- page_visitor_posts_update's WITH CHECK only requires
-- `author_id = auth.uid() OR current_user_has_page_permission(page_id, 'manage_content')`.
-- Because that first branch does not constrain page_id at all, any user who
-- authored a visitor post could UPDATE that row and set page_id to a
-- *different* page — including one where visitor posts are disabled, or one
-- unrelated to the original context — without ever going through the
-- page_visitor_posts_insert checks (allow_visitor_posts, page published,
-- etc.). The row would keep its existing 'published' status, so it could
-- appear as a legitimate visitor post on a Page that never opted in.
--
-- This migration closes the gap at the trigger level (defense in depth,
-- independent of which RLS branch let the UPDATE through): page_id and
-- author_id become immutable for the lifetime of a page_visitor_posts row.
-- There is no legitimate product reason to ever move a visitor post to a
-- different Page or reassign its author.

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

  if tg_op = 'UPDATE' and new.page_id is distinct from old.page_id then
    raise exception 'A visitor post cannot be moved to a different page.';
  end if;

  if tg_op = 'UPDATE' and new.author_id is distinct from old.author_id then
    raise exception 'A visitor post cannot be reassigned to a different author.';
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
