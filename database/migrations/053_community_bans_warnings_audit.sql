-- 053_community_bans_warnings_audit.sql
-- Community System Step 2 (item 2): community_bans, community_warnings,
-- community_audit_logs — the moderation gap flagged in the Phase 1 audit.
-- Gated by the manage_bans permission from 052. Additive; does not touch
-- existing tables/policies except two small, backward-compatible checks
-- added to the join paths so a banned user can't just rejoin.

-- 1. community_bans --------------------------------------------------------
create table if not exists public.community_bans (
  id uuid primary key default gen_random_uuid(),
  community_id uuid not null references public.communities(id) on delete cascade,
  user_id uuid not null references public.users(id) on delete cascade,
  banned_by uuid references public.users(id) on delete set null,
  reason text,
  expires_at timestamptz,          -- null = permanent
  lifted_at timestamptz,
  lifted_by uuid references public.users(id) on delete set null,
  created_at timestamptz not null default now()
);

comment on column public.community_bans.expires_at is 'null = permanent ban.';
comment on column public.community_bans.lifted_at is 'set when a moderator manually unbans before expiry; null means still in force (subject to expires_at).';

-- Only one *active* (un-lifted) ban row per (community, user) at a time —
-- re-banning updates this row rather than creating a duplicate.
create unique index if not exists idx_community_bans_active_unique
  on public.community_bans (community_id, user_id) where lifted_at is null;

create index if not exists idx_community_bans_lookup
  on public.community_bans (community_id, user_id);

alter table public.community_bans enable row level security;

drop policy if exists community_bans_select on public.community_bans;
create policy community_bans_select on public.community_bans
  for select using (
    is_admin_or_mod()
    or user_id = auth.uid()  -- a banned user can see their own ban and why
    or current_user_community_permission(community_id, 'manage_bans')
  );

grant select on public.community_bans to authenticated;
-- No insert/update/delete policy: writes only via ban_community_member() /
-- unban_community_member() below, both security definer.

-- Resolution helper: is this user currently banned from this community?
create or replace function public.is_banned_from_community(p_community_id uuid, p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = 'public'
as $$
  select exists (
    select 1 from public.community_bans b
    where b.community_id = p_community_id
      and b.user_id = p_user_id
      and b.lifted_at is null
      and (b.expires_at is null or b.expires_at > now())
  );
$$;

grant execute on function public.is_banned_from_community(uuid, uuid) to authenticated;

-- 2. community_warnings -----------------------------------------------------
create table if not exists public.community_warnings (
  id uuid primary key default gen_random_uuid(),
  community_id uuid not null references public.communities(id) on delete cascade,
  user_id uuid not null references public.users(id) on delete cascade,
  warned_by uuid references public.users(id) on delete set null,
  reason text not null,
  acknowledged_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists idx_community_warnings_user
  on public.community_warnings (community_id, user_id, created_at desc);

alter table public.community_warnings enable row level security;

drop policy if exists community_warnings_select on public.community_warnings;
create policy community_warnings_select on public.community_warnings
  for select using (
    is_admin_or_mod()
    or user_id = auth.uid()
    or current_user_community_permission(community_id, 'manage_bans')
  );

grant select on public.community_warnings to authenticated;
-- Writes via warn_community_member() / acknowledge_community_warning() only.

-- 3. community_audit_logs ----------------------------------------------------
create table if not exists public.community_audit_logs (
  id uuid primary key default gen_random_uuid(),
  community_id uuid not null references public.communities(id) on delete cascade,
  actor_id uuid references public.users(id) on delete set null,
  action text not null check (action in (
    'role_changed', 'member_removed', 'member_banned', 'member_unbanned',
    'member_warned', 'permission_overridden', 'settings_changed'
  )),
  target_user_id uuid references public.users(id) on delete set null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists idx_community_audit_logs_community
  on public.community_audit_logs (community_id, created_at desc);

alter table public.community_audit_logs enable row level security;

drop policy if exists community_audit_logs_select on public.community_audit_logs;
create policy community_audit_logs_select on public.community_audit_logs
  for select using (
    is_admin_or_mod()
    or current_user_community_permission(community_id, 'manage_bans')
    or current_user_community_permission(community_id, 'manage_reports')
  );

grant select on public.community_audit_logs to authenticated;
-- Insert-only from the security definer RPCs below; no client insert policy
-- (so the log can't be tampered with or backdated from the client).

-- Small internal helper so every moderation RPC logs consistently.
create or replace function public.log_community_audit(
  p_community_id uuid,
  p_action text,
  p_target_user_id uuid,
  p_metadata jsonb default '{}'::jsonb
)
returns void
language plpgsql
security definer
set search_path = 'public'
as $$
begin
  insert into public.community_audit_logs (community_id, actor_id, action, target_user_id, metadata)
  values (p_community_id, auth.uid(), p_action, p_target_user_id, p_metadata);
end;
$$;

-- Not granted to authenticated directly — only called internally by the
-- other security definer functions in this file (owned by the same role,
-- so they can call it regardless of grants).

-- 4. RPC: ban a member (also kicks their membership) ------------------------
create or replace function public.ban_community_member(
  p_community_id uuid,
  p_user_id uuid,
  p_reason text default null,
  p_expires_at timestamptz default null
)
returns void
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_target_role text;
begin
  if p_user_id = auth.uid() then
    raise exception 'Cannot ban yourself';
  end if;

  if not public.current_user_community_permission(p_community_id, 'manage_bans') then
    raise exception 'Not authorized to ban members in this community';
  end if;

  select role into v_target_role from public.community_memberships
  where community_id = p_community_id and user_id = p_user_id;

  if v_target_role = 'owner' then
    raise exception 'Cannot ban the community owner';
  end if;

  insert into public.community_bans (community_id, user_id, banned_by, reason, expires_at)
  values (p_community_id, p_user_id, auth.uid(), p_reason, p_expires_at)
  on conflict (community_id, user_id) where lifted_at is null
  do update set reason = excluded.reason, expires_at = excluded.expires_at, banned_by = excluded.banned_by, created_at = now();

  delete from public.community_memberships
  where community_id = p_community_id and user_id = p_user_id;

  perform public.log_community_audit(
    p_community_id, 'member_banned', p_user_id,
    jsonb_build_object('reason', p_reason, 'expires_at', p_expires_at)
  );
end;
$$;

grant execute on function public.ban_community_member(uuid, uuid, text, timestamptz) to authenticated;

-- 5. RPC: unban a member -----------------------------------------------------
create or replace function public.unban_community_member(p_community_id uuid, p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = 'public'
as $$
begin
  if not public.current_user_community_permission(p_community_id, 'manage_bans') then
    raise exception 'Not authorized to unban members in this community';
  end if;

  update public.community_bans
  set lifted_at = now(), lifted_by = auth.uid()
  where community_id = p_community_id and user_id = p_user_id and lifted_at is null;

  if not found then
    raise exception 'No active ban found for this user in this community';
  end if;

  perform public.log_community_audit(p_community_id, 'member_unbanned', p_user_id, '{}'::jsonb);
end;
$$;

grant execute on function public.unban_community_member(uuid, uuid) to authenticated;

-- 6. RPC: warn a member -------------------------------------------------------
create or replace function public.warn_community_member(
  p_community_id uuid,
  p_user_id uuid,
  p_reason text
)
returns uuid
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_target_role text;
  v_warning_id uuid;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'A reason is required to warn a member';
  end if;

  if not public.current_user_community_permission(p_community_id, 'manage_bans') then
    raise exception 'Not authorized to warn members in this community';
  end if;

  select role into v_target_role from public.community_memberships
  where community_id = p_community_id and user_id = p_user_id;

  if v_target_role is null then
    raise exception 'User is not a member of this community';
  end if;
  if v_target_role = 'owner' then
    raise exception 'Cannot warn the community owner';
  end if;

  insert into public.community_warnings (community_id, user_id, warned_by, reason)
  values (p_community_id, p_user_id, auth.uid(), p_reason)
  returning id into v_warning_id;

  perform public.log_community_audit(
    p_community_id, 'member_warned', p_user_id, jsonb_build_object('reason', p_reason, 'warning_id', v_warning_id)
  );

  return v_warning_id;
end;
$$;

grant execute on function public.warn_community_member(uuid, uuid, text) to authenticated;

-- 7. RPC: warned user acknowledges their own warning --------------------------
create or replace function public.acknowledge_community_warning(p_warning_id uuid)
returns void
language plpgsql
security definer
set search_path = 'public'
as $$
begin
  update public.community_warnings
  set acknowledged_at = now()
  where id = p_warning_id and user_id = auth.uid() and acknowledged_at is null;

  if not found then
    raise exception 'Warning not found, not yours, or already acknowledged';
  end if;
end;
$$;

grant execute on function public.acknowledge_community_warning(uuid) to authenticated;

-- 8. Close the rejoin loophole: banned users can't walk back in -------------
drop policy if exists memberships_insert_beta on public.community_memberships;
create policy memberships_insert_beta on public.community_memberships for insert with check (
  user_id = auth.uid()
  and public.current_user_has_beta_access()
  and not public.is_banned_from_community(community_id, auth.uid())
);

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

  if public.is_banned_from_community(p_community_id, auth.uid()) then
    raise exception 'You are banned from this community';
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
  if exists (
    select 1 from public.community_memberships
    where community_id = p_community_id and user_id = auth.uid()
  ) then
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

grant execute on function public.request_join_community(uuid, text) to authenticated;
