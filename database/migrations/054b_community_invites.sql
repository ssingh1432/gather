-- 054b_community_invites.sql
-- Community System Step 2 (item 3, part 1): community_invites.
-- Two invite types in one table:
--   'direct' — an owner/admin/mod invites a specific user by username.
--              The invited user must explicitly accept (they're never
--              silently added). Works for private communities without
--              going through the join-request/approval queue.
--   'link'   — a shareable code, optionally capped by max_uses and/or an
--              expiry. Anyone holding the code can redeem it. Also bypasses
--              the join-request queue for private communities — that's
--              the point of an invite link.
-- Both respect bans: is_banned_from_community() blocks creation (direct)
-- and redemption (both), same as the existing join paths from 053.

-- 1. community_invites -------------------------------------------------
create table if not exists public.community_invites (
  id uuid primary key default gen_random_uuid(),
  community_id uuid not null references public.communities(id) on delete cascade,
  created_by uuid references public.users(id) on delete set null,
  invite_type text not null check (invite_type in ('direct', 'link')),
  invited_user_id uuid references public.users(id) on delete cascade,
  code text,
  max_uses integer check (max_uses is null or max_uses > 0),
  use_count integer not null default 0,
  expires_at timestamptz,
  revoked_at timestamptz,
  revoked_by uuid references public.users(id) on delete set null,
  accepted_at timestamptz,       -- direct invites only: when the invited user accepted
  created_at timestamptz not null default now(),
  constraint community_invites_type_shape check (
    (invite_type = 'direct' and invited_user_id is not null and code is null)
    or
    (invite_type = 'link' and invited_user_id is null and code is not null)
  )
);

create unique index if not exists idx_community_invites_code on public.community_invites (code) where code is not null;
create index if not exists idx_community_invites_community on public.community_invites (community_id);
create index if not exists idx_community_invites_invited_user on public.community_invites (invited_user_id) where invited_user_id is not null;

alter table public.community_invites enable row level security;

drop policy if exists community_invites_select on public.community_invites;
create policy community_invites_select on public.community_invites
  for select using (
    is_admin_or_mod()
    or invited_user_id = auth.uid()
    or current_user_community_permission(community_id, 'manage_members')
  );

grant select on public.community_invites to authenticated;
-- Writes only via the RPCs below — a link's code should never be
-- guessable/enumerable from the table, and use_count must be
-- incremented atomically inside redeem_community_invite_code().

-- 2. community_invite_redemptions ----------------------------------------
-- Who actually joined via a link invite, and when — separate from
-- community_invites so a single popular link doesn't need row-level
-- updates contended by many simultaneous joiners, and so growth
-- analytics (Step 13) has a clean per-user event log to query later.
create table if not exists public.community_invite_redemptions (
  id uuid primary key default gen_random_uuid(),
  invite_id uuid not null references public.community_invites(id) on delete cascade,
  user_id uuid not null references public.users(id) on delete cascade,
  redeemed_at timestamptz not null default now(),
  unique (invite_id, user_id)
);

create index if not exists idx_community_invite_redemptions_invite on public.community_invite_redemptions (invite_id);

alter table public.community_invite_redemptions enable row level security;

drop policy if exists community_invite_redemptions_select on public.community_invite_redemptions;
create policy community_invite_redemptions_select on public.community_invite_redemptions
  for select using (
    is_admin_or_mod()
    or user_id = auth.uid()
    or exists (
      select 1 from public.community_invites i
      where i.id = community_invite_redemptions.invite_id
        and current_user_community_permission(i.community_id, 'manage_members')
    )
  );

grant select on public.community_invite_redemptions to authenticated;

-- 3. Extend the audit action catalog for invite events ---------------------
alter table public.community_audit_logs drop constraint if exists community_audit_logs_action_check;
alter table public.community_audit_logs add constraint community_audit_logs_action_check
  check (action in (
    'role_changed', 'member_removed', 'member_banned', 'member_unbanned',
    'member_warned', 'permission_overridden', 'settings_changed',
    'member_invited', 'invite_link_created', 'invite_revoked', 'invite_accepted'
  ));

-- 4. RPC: invite a specific user by username -------------------------------
create or replace function public.invite_user_to_community(
  p_community_id uuid,
  p_username text
)
returns uuid
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_invited_user_id uuid;
  v_invite_id uuid;
  v_community_name text;
begin
  if not public.current_user_community_permission(p_community_id, 'manage_members') then
    raise exception 'Not authorized to invite members to this community';
  end if;

  select id into v_invited_user_id from public.users where username = p_username;
  if v_invited_user_id is null then
    raise exception 'No user found with that username';
  end if;

  if v_invited_user_id = auth.uid() then
    raise exception 'Cannot invite yourself';
  end if;

  if exists (
    select 1 from public.community_memberships
    where community_id = p_community_id and user_id = v_invited_user_id
  ) then
    raise exception 'User is already a member';
  end if;

  if public.is_banned_from_community(p_community_id, v_invited_user_id) then
    raise exception 'This user is banned from the community — unban them first';
  end if;

  select name into v_community_name from public.communities where id = p_community_id;

  insert into public.community_invites (community_id, created_by, invite_type, invited_user_id)
  values (p_community_id, auth.uid(), 'direct', v_invited_user_id)
  returning id into v_invite_id;

  insert into public.notifications (recipient_id, actor_id, type, metadata)
  values (
    v_invited_user_id, auth.uid(), 'community_invite',
    jsonb_build_object('community_id', p_community_id, 'community_name', v_community_name, 'invite_id', v_invite_id)
  );

  perform public.log_community_audit(
    p_community_id, 'member_invited', v_invited_user_id, jsonb_build_object('invite_id', v_invite_id)
  );

  return v_invite_id;
end;
$$;

grant execute on function public.invite_user_to_community(uuid, text) to authenticated;

-- 5. RPC: invited user accepts a direct invite ------------------------------
-- Bypasses the join-request queue entirely — that's the point of a direct
-- invite to a private community: the owner/admin already vouched for them.
create or replace function public.accept_community_invite(p_invite_id uuid)
returns void
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_community_id uuid;
begin
  select community_id into v_community_id
  from public.community_invites
  where id = p_invite_id
    and invite_type = 'direct'
    and invited_user_id = auth.uid()
    and revoked_at is null
    and accepted_at is null;

  if v_community_id is null then
    raise exception 'Invite not found, not yours, already used, or revoked';
  end if;

  if public.is_banned_from_community(v_community_id, auth.uid()) then
    raise exception 'You are banned from this community';
  end if;

  insert into public.community_memberships (community_id, user_id, role)
  values (v_community_id, auth.uid(), 'member')
  on conflict (community_id, user_id) do nothing;

  update public.community_invites set accepted_at = now() where id = p_invite_id;

  perform public.log_community_audit(v_community_id, 'invite_accepted', auth.uid(), jsonb_build_object('invite_id', p_invite_id));
end;
$$;

grant execute on function public.accept_community_invite(uuid) to authenticated;

-- 6. RPC: invited user declines / anyone with manage_members revokes ------
create or replace function public.revoke_community_invite(p_invite_id uuid)
returns void
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_community_id uuid;
  v_invited_user_id uuid;
begin
  select community_id, invited_user_id into v_community_id, v_invited_user_id
  from public.community_invites where id = p_invite_id and revoked_at is null;

  if v_community_id is null then
    raise exception 'Invite not found or already revoked';
  end if;

  if not (v_invited_user_id = auth.uid() or public.current_user_community_permission(v_community_id, 'manage_members')) then
    raise exception 'Not authorized to revoke this invite';
  end if;

  update public.community_invites set revoked_at = now(), revoked_by = auth.uid() where id = p_invite_id;

  perform public.log_community_audit(v_community_id, 'invite_revoked', v_invited_user_id, jsonb_build_object('invite_id', p_invite_id));
end;
$$;

grant execute on function public.revoke_community_invite(uuid) to authenticated;

-- 7. RPC: create a shareable invite link/code -------------------------------
create or replace function public.create_community_invite_link(
  p_community_id uuid,
  p_max_uses integer default null,
  p_expires_at timestamptz default null
)
returns text
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_code text;
  v_invite_id uuid;
begin
  if not public.current_user_community_permission(p_community_id, 'manage_members') then
    raise exception 'Not authorized to create invite links for this community';
  end if;

  -- 8-char base32-ish code (no 0/O/1/I ambiguity), regenerate on the rare collision.
  loop
    v_code := (
      select string_agg(substr('ABCDEFGHJKLMNPQRSTUVWXYZ23456789', (random() * 32)::int + 1, 1), '')
      from generate_series(1, 8)
    );
    exit when not exists (select 1 from public.community_invites where code = v_code);
  end loop;

  insert into public.community_invites (community_id, created_by, invite_type, code, max_uses, expires_at)
  values (p_community_id, auth.uid(), 'link', v_code, p_max_uses, p_expires_at)
  returning id into v_invite_id;

  perform public.log_community_audit(
    p_community_id, 'invite_link_created', null,
    jsonb_build_object('invite_id', v_invite_id, 'max_uses', p_max_uses, 'expires_at', p_expires_at)
  );

  return v_code;
end;
$$;

grant execute on function public.create_community_invite_link(uuid, integer, timestamptz) to authenticated;

-- 8. RPC: redeem a code (link invites) ---------------------------------------
create or replace function public.redeem_community_invite_code(p_code text)
returns jsonb
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_invite record;
begin
  select * into v_invite
  from public.community_invites
  where code = p_code and invite_type = 'link'
  for update;

  if v_invite.id is null then
    raise exception 'Invalid invite code';
  end if;
  if v_invite.revoked_at is not null then
    raise exception 'This invite link has been revoked';
  end if;
  if v_invite.expires_at is not null and v_invite.expires_at <= now() then
    raise exception 'This invite link has expired';
  end if;
  if v_invite.max_uses is not null and v_invite.use_count >= v_invite.max_uses then
    raise exception 'This invite link has reached its use limit';
  end if;
  if public.is_banned_from_community(v_invite.community_id, auth.uid()) then
    raise exception 'You are banned from this community';
  end if;

  if exists (
    select 1 from public.community_memberships
    where community_id = v_invite.community_id and user_id = auth.uid()
  ) then
    return jsonb_build_object('result', 'already_member', 'community_id', v_invite.community_id);
  end if;

  insert into public.community_memberships (community_id, user_id, role)
  values (v_invite.community_id, auth.uid(), 'member');

  update public.community_invites set use_count = use_count + 1 where id = v_invite.id;

  insert into public.community_invite_redemptions (invite_id, user_id)
  values (v_invite.id, auth.uid())
  on conflict (invite_id, user_id) do nothing;

  perform public.log_community_audit(v_invite.community_id, 'invite_accepted', auth.uid(), jsonb_build_object('invite_id', v_invite.id));

  return jsonb_build_object('result', 'joined', 'community_id', v_invite.community_id);
end;
$$;

grant execute on function public.redeem_community_invite_code(text) to authenticated;
