-- 050_community_media_storage_bucket_and_policies.sql
insert into storage.buckets (id, name, public, file_size_limit)
values ('community-media', 'community-media', true, 5242880) -- 5MB
on conflict (id) do nothing;

-- Path convention: {community_id}/icon or {community_id}/banner
-- Only that community's owner/admin (or a site admin/mod) may write.
create or replace function public.is_community_owner_or_admin(p_community_id uuid)
returns boolean
language sql
stable
security definer
set search_path = 'public'
as $$
  select
    is_admin_or_mod()
    or exists (
      select 1 from public.community_memberships m
      where m.community_id = p_community_id
        and m.user_id = auth.uid()
        and m.role in ('owner','admin')
    );
$$;

grant execute on function public.is_community_owner_or_admin(uuid) to authenticated;

drop policy if exists "Community owners can upload media" on storage.objects;
create policy "Community owners can upload media" on storage.objects
  for insert with check (
    bucket_id = 'community-media'
    and public.is_community_owner_or_admin(((storage.foldername(name))[1])::uuid)
  );

drop policy if exists "Community owners can update media" on storage.objects;
create policy "Community owners can update media" on storage.objects
  for update using (
    bucket_id = 'community-media'
    and public.is_community_owner_or_admin(((storage.foldername(name))[1])::uuid)
  );

drop policy if exists "Community owners can delete media" on storage.objects;
create policy "Community owners can delete media" on storage.objects
  for delete using (
    bucket_id = 'community-media'
    and public.is_community_owner_or_admin(((storage.foldername(name))[1])::uuid)
  );
