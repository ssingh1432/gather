-- Page follower rosters are an owner/analytics concern, not public data.
-- Followers must still be able to read their own follow row so the client
-- can load their followed Pages and preferences.
drop policy if exists page_followers_select on public.page_followers;

create policy page_followers_select
on public.page_followers
for select
to authenticated
using (
  user_id = auth.uid()
  or public.current_user_has_page_permission(page_id, 'view_analytics')
);
