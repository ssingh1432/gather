-- 115_pages_visitor_post_follower_policy_qualification.sql
-- COMMAND 3 security correction: qualify page_id inside the follower EXISTS
-- so the RLS policy checks the destination Page, not merely any followed Page.

drop policy if exists page_visitor_posts_insert on public.page_visitor_posts;
create policy page_visitor_posts_insert on public.page_visitor_posts
  for insert with check (
    author_id = auth.uid()
    and not public.current_user_has_page_permission(page_id, 'manage_content')
    and exists (
      select 1 from public.pages p
      where p.id = page_visitor_posts.page_id
        and p.status = 'published'
        and p.deleted_at is null
        and p.allow_visitor_posts = true
    )
    and exists (
      select 1 from public.page_followers f
      where f.page_id = page_visitor_posts.page_id
        and f.user_id = auth.uid()
    )
  );
