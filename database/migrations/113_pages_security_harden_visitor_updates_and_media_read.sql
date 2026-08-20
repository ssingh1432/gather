-- Harden Professional Pages visitor-post updates and media read access.
--
-- Visitor authors may edit their content, but may not change ownership,
-- Page association, or moderation state. Page staff retain moderation access.
-- Published Page/visitor-post media is readable through authenticated
-- Storage API access; upload/update/delete remain protected by existing
-- Page/author policies.

create or replace function public.guard_page_visitor_post_update()
returns trigger
language plpgsql
as $$
begin
  if auth.uid() is not null
     and not current_user_has_page_permission(old.page_id, 'manage_content')
     and old.author_id = auth.uid() then
    if new.page_id is distinct from old.page_id
       or new.author_id is distinct from old.author_id
       or new.status is distinct from old.status
       or new.reviewed_by is distinct from old.reviewed_by
       or new.reviewed_at is distinct from old.reviewed_at then
      raise exception 'Visitor post ownership, Page association, or moderation fields cannot be changed by the author';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_guard_page_visitor_post_update on public.page_visitor_posts;
create trigger trg_guard_page_visitor_post_update
before update on public.page_visitor_posts
for each row
execute function public.guard_page_visitor_post_update();

drop policy if exists page_visitor_posts_update on public.page_visitor_posts;
create policy page_visitor_posts_update
on public.page_visitor_posts
for update
to authenticated
using (
  author_id = auth.uid()
  or current_user_has_page_permission(page_id, 'manage_content')
)
with check (
  author_id = auth.uid()
  or current_user_has_page_permission(page_id, 'manage_content')
);

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
      and p.status = 'published'
  )
);

drop policy if exists "Page staff can view media" on storage.objects;
create policy "Page staff can view media"
on storage.objects
for select
to authenticated
using (
  (bucket_id = 'page-media' and public.can_manage_page_media(((storage.foldername(name))[1])::uuid))
  or
  (
    bucket_id = 'page-media'
    and (storage.foldername(name))[2] = 'posts'
    and exists (
      select 1
      from public.page_posts p
      where p.id = ((storage.foldername(name))[3])::uuid
        and p.page_id = ((storage.foldername(name))[1])::uuid
        and p.status = 'published'
        and p.deleted_at is null
    )
  )
);
