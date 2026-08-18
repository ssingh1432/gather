-- Page-only visitor media upload fix.
-- Supabase Storage can require SELECT on storage.objects to return the newly
-- inserted object metadata from an upload. Keep metadata access restricted to
-- the visitor who owns the post or Page staff with manage_content permission.
-- Public bucket access still controls public file delivery; this policy does
-- not grant upload, update, or delete permissions.

drop policy if exists page_visitor_post_media_select on storage.objects;
create policy page_visitor_post_media_select
on storage.objects
for select
to authenticated
using (
  bucket_id = 'page-visitor-media'
  and exists (
    select 1
    from public.page_visitor_posts p
    where p.id = ((storage.foldername(name))[2])::uuid
      and (
        p.author_id = auth.uid()
        or current_user_has_page_permission(p.page_id, 'manage_content')
      )
  )
);
