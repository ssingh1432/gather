-- 049_phase_community_pages_roles_privacy.sql
-- Adds "page"-style richness to communities (visibility, category, rules,
-- banner, verified badge, cached member count), role-based membership
-- (owner/admin/moderator/member), a join-request workflow for private
-- communities, and closes a real privacy gap in get_community_feed (it
-- previously returned posts from a private community to any caller with no
-- membership check at all).

-- 1. Extend communities -------------------------------------------------
alter table public.communities
  add column if not exists visibility text not null default 'public'
    check (visibility in ('public','private')),
  add column if not exists category text,
  add column if not exists rules text,
  add column if not exists banner_url text,
  add column if not exists member_count integer not null default 0,
  add column if not exists is_verified boolean not null default false;

comment on column public.communities.visibility is 'public = listed and open to join; private = listed but requires an approved join request before content/feed is visible.';
comment on column public.communities.member_count is 'Denormalized count maintained by trg_community_membership_count. Do not write directly.';

-- 2. Extend community_memberships with roles ----------------------------
alter table public.community_memberships
  add column if not exists role text not null default 'member'
    check (role in ('owner','admin','moderator','member'));

-- Backfill: whoever created the community is its owner.
update public.community_memberships cm
set role = 'owner'
from public.communities c
where c.id = cm.community_id
  and c.created_by = cm.user_id
  and cm.role <> 'owner';

-- Backfill member_count from actual membership rows.
update public.communities c
set member_count = coalesce((select count(*) from public.community_memberships m where m.community_id = c.id), 0);

-- 3. Join requests for private communities -------------------------------
create table if not exists public.community_join_requests (
  id uuid primary key default gen_random_uuid(),
  community_id uuid not null references public.communities(id) on delete cascade,
  user_id uuid not null references public.users(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  message text,
  decided_by uuid references public.users(id) on delete set null,
  decided_at timestamptz,
  created_at timestamptz not null default now(),
  unique (community_id, user_id)
);

create index if not exists idx_community_join_requests_pending
  on public.community_join_requests (community_id, status);

alter table public.community_join_requests enable row level security;

drop policy if exists join_requests_select on public.community_join_requests;
create policy join_requests_select on public.community_join_requests
  for select using (
    user_id = auth.uid()
    or is_admin_or_mod()
    or exists (
      select 1 from public.community_memberships m
      where m.community_id = community_join_requests.community_id
        and m.user_id = auth.uid()
        and m.role in ('owner','admin','moderator')
    )
  );

drop policy if exists join_requests_insert on public.community_join_requests;
create policy join_requests_insert on public.community_join_requests
  for insert with check (user_id = auth.uid() and current_user_has_beta_access());

drop policy if exists join_requests_delete_own on public.community_join_requests;
create policy join_requests_delete_own on public.community_join_requests
  for delete using (user_id = auth.uid() and status = 'pending');

-- Decisions (approve/reject) go through decide_community_join_request()
-- below, not direct UPDATE, so there is no client-facing UPDATE policy.

-- 4. Maintain member_count automatically ---------------------------------
create or replace function public.trg_community_membership_count()
returns trigger
language plpgsql
security definer
set search_path = 'public'
as $$
begin
  if tg_op = 'INSERT' then
    update public.communities set member_count = member_count + 1 where id = new.community_id;
  elsif tg_op = 'DELETE' then
    update public.communities set member_count = greatest(member_count - 1, 0) where id = old.community_id;
  end if;
  return null;
end;
$$;

drop trigger if exists trg_community_membership_count on public.community_memberships;
create trigger trg_community_membership_count
after insert or delete on public.community_memberships
for each row execute function public.trg_community_membership_count();

-- 5. Auto-add the creator as owner ---------------------------------------
create or replace function public.trg_community_created_owner()
returns trigger
language plpgsql
security definer
set search_path = 'public'
as $$
begin
  insert into public.community_memberships (community_id, user_id, role)
  values (new.id, new.created_by, 'owner')
  on conflict (community_id, user_id) do update set role = 'owner';
  return new;
end;
$$;

drop trigger if exists trg_community_created_owner on public.communities;
create trigger trg_community_created_owner
after insert on public.communities
for each row execute function public.trg_community_created_owner();

-- 6. RLS: allow community members to see the member list, not just their
--    own row or global admins/mods. This was the actual bug preventing any
--    "view members" UI from working for a normal owner/admin.
drop policy if exists memberships_select_beta on public.community_memberships;
create policy memberships_select_members on public.community_memberships
  for select using (
    current_user_has_beta_access()
    and (
      user_id = auth.uid()
      or is_admin_or_mod()
      or exists (
        select 1 from public.community_memberships m2
        where m2.community_id = community_memberships.community_id
          and m2.user_id = auth.uid()
      )
    )
  );

-- Role changes (promote/demote/kick) go through the SECURITY DEFINER RPCs
-- below rather than a client UPDATE policy, so no memberships_update policy
-- is added here.

-- 7. Communities: allow owner/site-admin deletion -------------------------
drop policy if exists communities_delete_owner_or_admin on public.communities;
create policy communities_delete_owner_or_admin on public.communities
  for delete using (created_by = auth.uid() or is_admin_or_mod());

-- 8. Close the private-community privacy gap in get_community_feed -------
create or replace function public.get_community_feed(
  community_id uuid,
  user_id uuid default null,
  page_size integer default 20,
  page_offset integer default 0
)
returns table(
  id uuid, author_id uuid, community_id uuid, text_content text, created_at timestamptz,
  author_username text, author_avatar_url text, image_url text, location text, feeling text,
  tags text[], like_count bigint, comment_count bigint, share_count integer,
  is_liked boolean, is_bookmarked boolean, reply_to_post_id uuid,
  reply_to_author_username text, reply_to_author_avatar_url text, reply_to_text_content text,
  reply_to_image_url text, reply_to_created_at timestamptz, reply_to_removed boolean,
  is_sensitive boolean
)
language sql
stable
set search_path = 'public'
as $$
  select
    p.id, p.author_id, p.community_id, p.text_content, p.created_at,
    u.username as author_username, u.profile_photo_url as author_avatar_url,
    pm.media_url as image_url, p.location, p.feeling, p.tags,
    coalesce(likes.like_count, 0) as like_count,
    coalesce(comments.comment_count, 0) as comment_count,
    p.share_count,
    (viewer.viewer_id is not null and pl.user_id is not null) as is_liked,
    (viewer.viewer_id is not null and b.user_id is not null) as is_bookmarked,
    p.reply_to_post_id, ru.username as reply_to_author_username,
    ru.profile_photo_url as reply_to_author_avatar_url, rp.text_content as reply_to_text_content,
    rpm.media_url as reply_to_image_url, rp.created_at as reply_to_created_at,
    (p.reply_to_post_id is not null and rp.id is null) as reply_to_removed,
    p.is_sensitive
  from public.posts p
  join public.users u on u.id = p.author_id
  join public.communities c on c.id = p.community_id
  left join lateral (select coalesce($2, auth.uid()) as viewer_id) viewer on true
  left join lateral (
    select safe_search_enabled, child_safety_mode
    from public.users where id = viewer.viewer_id
  ) vu on true
  left join lateral (
    select media_url from public.post_media where post_id = p.id order by created_at asc limit 1
  ) pm on true
  left join lateral (select count(*) as like_count from public.post_likes where post_id = p.id) likes on true
  left join lateral (select count(*) as comment_count from public.post_comments where post_id = p.id) comments on true
  left join public.post_likes pl on pl.post_id = p.id and pl.user_id = viewer.viewer_id
  left join public.bookmarks b on b.post_id = p.id and b.user_id = viewer.viewer_id
  left join public.posts rp on rp.id = p.reply_to_post_id and rp.is_removed = false
  left join public.users ru on ru.id = rp.author_id
  left join lateral (
    select media_url from public.post_media where post_id = rp.id order by created_at asc limit 1
  ) rpm on true
  where p.community_id = $1
    and p.is_removed = false
    and ($2 is null or $2 = auth.uid())
    and (
      not p.is_sensitive
      or vu.safe_search_enabled is null
      or not (coalesce(vu.safe_search_enabled, true) or coalesce(vu.child_safety_mode, false))
    )
    and (
      viewer.viewer_id is null
      or not exists (
        select 1 from public.user_blocks ub
        where (ub.blocker_id = viewer.viewer_id and ub.blocked_id = p.author_id)
           or (ub.blocker_id = p.author_id and ub.blocked_id = viewer.viewer_id)
      )
    )
    and (
      -- Private-community gate: only members (any role) or site admin/mod
      -- can see posts once a community is marked private.
      c.visibility = 'public'
      or (
        viewer.viewer_id is not null
        and (
          exists (
            select 1 from public.community_memberships m
            where m.community_id = c.id and m.user_id = viewer.viewer_id
          )
          or exists (
            select 1 from public.users au where au.id = viewer.viewer_id and au.role in ('admin','moderator')
          )
        )
      )
    )
  order by p.created_at desc, p.id desc
  limit least(greatest(coalesce($3, 20), 1), 100)
  offset greatest(coalesce($4, 0), 0);
$$;

-- 9. RPC: join a public community, or file a join request for a private one
create or replace function public.request_join_community(p_community_id uuid, p_message text default null)
returns text
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_visibility text;
begin
  if not current_user_has_beta_access() then
    raise exception 'Beta access required';
  end if;

  select visibility into v_visibility from public.communities where id = p_community_id;
  if v_visibility is null then
    raise exception 'Community not found';
  end if;

  if v_visibility = 'public' then
    insert into public.community_memberships (community_id, user_id, role)
    values (p_community_id, auth.uid(), 'member')
    on conflict (community_id, user_id) do nothing;
    return 'joined';
  end if;

  -- Private: already a member?
  if exists (select 1 from public.community_memberships where community_id = p_community_id and user_id = auth.uid()) then
    return 'already_member';
  end if;

  insert into public.community_join_requests (community_id, user_id, message, status)
  values (p_community_id, auth.uid(), p_message, 'pending')
  on conflict (community_id, user_id)
  do update set status = 'pending', message = excluded.message, decided_by = null, decided_at = null, created_at = now()
  where community_join_requests.status = 'rejected';
  return 'requested';
end;
$$;

-- 10. RPC: approve/reject a join request (owner/admin/moderator of that
--     community, or a site admin/mod)
create or replace function public.decide_community_join_request(p_request_id uuid, p_approve boolean)
returns void
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_community_id uuid;
  v_user_id uuid;
begin
  select community_id, user_id into v_community_id, v_user_id
  from public.community_join_requests where id = p_request_id and status = 'pending';

  if v_community_id is null then
    raise exception 'Request not found or already decided';
  end if;

  if not (
    is_admin_or_mod()
    or exists (
      select 1 from public.community_memberships m
      where m.community_id = v_community_id and m.user_id = auth.uid() and m.role in ('owner','admin','moderator')
    )
  ) then
    raise exception 'Not authorized to decide this request';
  end if;

  update public.community_join_requests
  set status = case when p_approve then 'approved' else 'rejected' end,
      decided_by = auth.uid(), decided_at = now()
  where id = p_request_id;

  if p_approve then
    insert into public.community_memberships (community_id, user_id, role)
    values (v_community_id, v_user_id, 'member')
    on conflict (community_id, user_id) do nothing;
  end if;
end;
$$;

-- 11. RPC: change a member's role (owner can set admin/moderator/member;
--     admin can only set moderator/member; nobody can touch the owner row)
create or replace function public.set_community_member_role(p_community_id uuid, p_user_id uuid, p_role text)
returns void
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_caller_role text;
  v_target_role text;
begin
  if p_role not in ('admin','moderator','member') then
    raise exception 'Invalid role';
  end if;

  select role into v_caller_role from public.community_memberships
  where community_id = p_community_id and user_id = auth.uid();
  select role into v_target_role from public.community_memberships
  where community_id = p_community_id and user_id = p_user_id;

  if v_target_role is null then
    raise exception 'User is not a member of this community';
  end if;
  if v_target_role = 'owner' then
    raise exception 'Cannot change the owner''s role';
  end if;

  if not (
    is_admin_or_mod()
    or v_caller_role = 'owner'
    or (v_caller_role = 'admin' and p_role in ('moderator','member'))
  ) then
    raise exception 'Not authorized to set this role';
  end if;

  update public.community_memberships set role = p_role
  where community_id = p_community_id and user_id = p_user_id;
end;
$$;

-- 12. RPC: remove (kick) a member. Owner/admin/moderator of the community,
--     or a site admin/mod. Nobody can remove the owner this way (they must
--     delete the community or transfer ownership, which is out of scope
--     for this phase).
create or replace function public.remove_community_member(p_community_id uuid, p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_caller_role text;
  v_target_role text;
begin
  select role into v_caller_role from public.community_memberships
  where community_id = p_community_id and user_id = auth.uid();
  select role into v_target_role from public.community_memberships
  where community_id = p_community_id and user_id = p_user_id;

  if v_target_role is null then
    raise exception 'User is not a member of this community';
  end if;
  if v_target_role = 'owner' then
    raise exception 'Cannot remove the community owner';
  end if;

  if not (
    is_admin_or_mod()
    or v_caller_role in ('owner','admin')
    or (v_caller_role = 'moderator' and v_target_role = 'member')
  ) then
    raise exception 'Not authorized to remove this member';
  end if;

  delete from public.community_memberships
  where community_id = p_community_id and user_id = p_user_id;
end;
$$;

-- 13. RPC: delete a community outright (owner or site admin/mod). Nulls out
--     optional references first so it doesn't fail on the plain (non-
--     cascading) FKs from post_drafts/scheduled_posts.
create or replace function public.delete_community(p_community_id uuid)
returns void
language plpgsql
security definer
set search_path = 'public'
as $$
begin
  if not (
    is_admin_or_mod()
    or exists (
      select 1 from public.communities where id = p_community_id and created_by = auth.uid()
    )
  ) then
    raise exception 'Not authorized to delete this community';
  end if;

  update public.post_drafts set community_id = null where community_id = p_community_id;
  update public.scheduled_posts set community_id = null where community_id = p_community_id;
  delete from public.communities where id = p_community_id;
end;
$$;

grant execute on function public.request_join_community(uuid, text) to authenticated;
grant execute on function public.decide_community_join_request(uuid, boolean) to authenticated;
grant execute on function public.set_community_member_role(uuid, uuid, text) to authenticated;
grant execute on function public.remove_community_member(uuid, uuid) to authenticated;
grant execute on function public.delete_community(uuid) to authenticated;

grant select, insert, delete on public.community_join_requests to authenticated;
