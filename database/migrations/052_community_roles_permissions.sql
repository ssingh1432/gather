-- 052_community_roles_permissions.sql
-- Community System Step 2: turn the 4 hardcoded community roles into a real,
-- queryable permission system (community_permissions catalog +
-- community_role_permissions default matrix + per-community overrides),
-- and add the 'trusted_member' role.
--
-- Backward compatible: existing role checks (role in ('owner','admin',...))
-- scattered through migrations 049/050 and the RPCs they define keep
-- working unchanged. This migration is additive — it does not touch or
-- replace any existing policy or RPC. New code (this phase onward) should
-- prefer public.current_user_community_permission(community_id, key)
-- instead of hardcoding role checks.

-- 1. Add 'trusted_member' role ------------------------------------------
alter table public.community_memberships
  drop constraint if exists community_memberships_role_check;

alter table public.community_memberships
  add constraint community_memberships_role_check
  check (role in ('owner','admin','moderator','trusted_member','member'));

comment on column public.community_memberships.role is
  'owner > admin > moderator > trusted_member > member. Guests (non-members) are implicit — no membership row.';

-- 2. Permission catalog ---------------------------------------------------
create table if not exists public.community_permissions (
  key text primary key,
  label text not null,
  description text not null,
  created_at timestamptz not null default now()
);

insert into public.community_permissions (key, label, description) values
  ('manage_settings',   'Manage settings',    'Edit community name, description, avatar, banner, rules, category.'),
  ('manage_roles',      'Manage roles',       'Promote/demote members and set role permission overrides.'),
  ('manage_members',    'Manage members',     'Approve/reject join requests, remove members, invite members.'),
  ('manage_bans',       'Manage bans',        'Ban, unban, and warn members.'),
  ('manage_posts',      'Manage posts',       'Pin, unpin, remove, or approve posts in the community.'),
  ('manage_events',     'Manage events',      'Create, edit, or cancel community events.'),
  ('manage_reports',    'Manage reports',     'View and resolve reports filed within the community.'),
  ('post_content',      'Post content',       'Create posts, polls, and events in the community.'),
  ('comment',           'Comment',            'Reply to posts in the community.'),
  ('view_private_feed', 'View private feed',  'View posts in a private community.')
on conflict (key) do nothing;

alter table public.community_permissions enable row level security;

drop policy if exists community_permissions_select_all on public.community_permissions;
create policy community_permissions_select_all on public.community_permissions
  for select using (true);

grant select on public.community_permissions to authenticated;

-- 3. Default role -> permission matrix ------------------------------------
create table if not exists public.community_role_permissions (
  role text not null check (role in ('owner','admin','moderator','trusted_member','member')),
  permission_key text not null references public.community_permissions(key) on delete cascade,
  allowed boolean not null default true,
  primary key (role, permission_key)
);

alter table public.community_role_permissions enable row level security;

drop policy if exists community_role_permissions_select_all on public.community_role_permissions;
create policy community_role_permissions_select_all on public.community_role_permissions
  for select using (true);

grant select on public.community_role_permissions to authenticated;

-- Seed sane defaults. Owners/admins get everything; moderators get
-- day-to-day moderation; trusted_member gets posting + comment only
-- (the practical difference from 'member' is intended to live in
-- per-community overrides, e.g. skip-queue posting); member gets
-- posting + comment; nobody below trusted_member gets management keys.
insert into public.community_role_permissions (role, permission_key, allowed)
select r.role, p.key, true
from (values ('owner'), ('admin')) as r(role)
cross join public.community_permissions p
on conflict (role, permission_key) do nothing;

insert into public.community_role_permissions (role, permission_key, allowed) values
  ('moderator', 'manage_members', true),
  ('moderator', 'manage_bans', true),
  ('moderator', 'manage_posts', true),
  ('moderator', 'manage_reports', true),
  ('moderator', 'post_content', true),
  ('moderator', 'comment', true),
  ('moderator', 'view_private_feed', true),
  ('trusted_member', 'post_content', true),
  ('trusted_member', 'comment', true),
  ('trusted_member', 'view_private_feed', true),
  ('member', 'post_content', true),
  ('member', 'comment', true),
  ('member', 'view_private_feed', true)
on conflict (role, permission_key) do nothing;

-- 4. Per-community overrides -----------------------------------------------
-- Lets an owner loosen/tighten a permission for a role within their own
-- community without a code change (e.g. allow 'member' to post events,
-- or require 'trusted_member' before allowing posting at all).
create table if not exists public.community_permission_overrides (
  community_id uuid not null references public.communities(id) on delete cascade,
  role text not null check (role in ('owner','admin','moderator','trusted_member','member')),
  permission_key text not null references public.community_permissions(key) on delete cascade,
  allowed boolean not null,
  updated_by uuid references public.users(id) on delete set null,
  updated_at timestamptz not null default now(),
  primary key (community_id, role, permission_key)
);

create index if not exists idx_community_permission_overrides_community
  on public.community_permission_overrides (community_id);

alter table public.community_permission_overrides enable row level security;

-- Readable by community members and site admins/mods (so a member can see
-- what they're allowed to do); writes only via the RPC below.
drop policy if exists community_permission_overrides_select on public.community_permission_overrides;
create policy community_permission_overrides_select on public.community_permission_overrides
  for select using (
    is_admin_or_mod()
    or is_member_of_community(community_permission_overrides.community_id)
  );

grant select on public.community_permission_overrides to authenticated;

-- 5. Resolution function: does `role` have `permission_key` in `community_id`? ---
create or replace function public.community_role_can(
  p_community_id uuid,
  p_role text,
  p_permission_key text
)
returns boolean
language sql
stable
security definer
set search_path = 'public'
as $$
  select coalesce(
    (select allowed from public.community_permission_overrides
     where community_id = p_community_id and role = p_role and permission_key = p_permission_key),
    (select allowed from public.community_role_permissions
     where role = p_role and permission_key = p_permission_key),
    false
  );
$$;

grant execute on function public.community_role_can(uuid, text, text) to authenticated;

-- 6. Convenience: does the calling user have `permission_key` in `community_id`? ---
-- Site admins/mods always pass. Non-members always fail (guests have no
-- permissions in this table; public-feed read access is handled separately
-- by get_community_feed / communities RLS, not by this permission system).
create or replace function public.current_user_community_permission(
  p_community_id uuid,
  p_permission_key text
)
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
        and public.community_role_can(p_community_id, m.role, p_permission_key)
    );
$$;

grant execute on function public.current_user_community_permission(uuid, text) to authenticated;

-- 7. RPC: set a per-community permission override (owner/admin only) ------
create or replace function public.set_community_permission_override(
  p_community_id uuid,
  p_role text,
  p_permission_key text,
  p_allowed boolean
)
returns void
language plpgsql
security definer
set search_path = 'public'
as $$
begin
  if p_role not in ('admin','moderator','trusted_member','member') then
    raise exception 'Cannot override permissions for role %', p_role;
  end if;

  if not public.is_community_owner_or_admin(p_community_id) then
    raise exception 'Not authorized to change permissions for this community';
  end if;

  insert into public.community_permission_overrides
    (community_id, role, permission_key, allowed, updated_by, updated_at)
  values
    (p_community_id, p_role, p_permission_key, p_allowed, auth.uid(), now())
  on conflict (community_id, role, permission_key)
  do update set allowed = excluded.allowed, updated_by = excluded.updated_by, updated_at = now();
end;
$$;

grant execute on function public.set_community_permission_override(uuid, text, text, boolean) to authenticated;
