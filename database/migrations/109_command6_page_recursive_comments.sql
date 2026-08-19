-- COMMAND 6 — Page visitor post recursive comments
-- Page-only schema extension. Existing non-Page comments are untouched.

alter table public.page_visitor_post_comments
  add column if not exists parent_comment_id uuid null
    references public.page_visitor_post_comments(id) on delete cascade;

create index if not exists idx_page_visitor_post_comments_parent
  on public.page_visitor_post_comments(post_id, parent_comment_id, created_at);
