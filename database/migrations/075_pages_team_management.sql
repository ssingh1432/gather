-- 075_pages_team_management.sql
-- Professional Page System — Step 5 (Page Roles / Team Management).
--
-- The schema, permission catalog, role matrix, and RLS for `page_roles` /
-- `page_permissions` were already built in migration 072. This migration is
-- additive UX/safety wrapping only: three SECURITY DEFINER RPCs so the
-- Flutter Team Management screen (Step 5) can add/change/remove a team
-- member in a single round trip with friendly, specific error messages,
-- instead of the client doing a raw users-lookup + page_roles write and
-- surfacing a bare Postgres constraint violation.
--
-- Nothing about the authorization boundary changes: every RPC re-checks
-- `current_user_page_role` / `current_user_has_page_permission` itself
-- (same helpers migration 072 defined), exactly mirroring what
-- `page_roles_manage` RLS already enforces on direct table access — RLS
-- is not bypassed by policy, only by convenience, so direct table access
-- to page_roles continues to work unchanged for anything that doesn't
-- go through these RPCs.
--
-- Reminder: the page **owner** is tracked on `pages.owner_id`, not as a
-- row in `page_roles` (see `current_user_page_role`, migration 072). The
-- Team Management screen must show the owner separately from the
-- `page_roles` roster for this reason.

create or replace function public.add_page_team_member(
  p_page_id uuid,
  p_username text,
  p_role text
)
returns uuid
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_target_id uuid;
  v_owner_id uuid;
begin
  if not (
    public.current_user_page_role(p_page_id) = 'owner'
    or public.current_user_has_page_permission(p_page_id, 'manage_roles')
  ) then
    raise exception 'You do not have permission to manage this page''s team.';
  end if;

  if p_role not in ('manager','editor','content_creator','moderator','customer_support','analyst') then
    raise exception 'Invalid role.';
  end if;

  select id into v_target_id from public.users where lower(username) = lower(trim(leading '@' from p_username));
  if v_target_id is null then
    raise exception 'No user found with that username.';
  end if;

  select owner_id into v_owner_id from public.pages where id = p_page_id;
  if v_target_id = v_owner_id then
    raise exception 'This user already owns the page.';
  end if;

  if exists (select 1 from public.page_roles where page_id = p_page_id and user_id = v_target_id) then
    raise exception 'This user is already on the team. Change their role instead.';
  end if;

  insert into public.page_roles (page_id, user_id, role, granted_by)
  values (p_page_id, v_target_id, p_role, auth.uid());

  return v_target_id;
end;
$$;

create or replace function public.update_page_team_member_role(
  p_page_id uuid,
  p_user_id uuid,
  p_role text
)
returns void
language plpgsql
security definer
set search_path = 'public'
as $$
begin
  if not (
    public.current_user_page_role(p_page_id) = 'owner'
    or public.current_user_has_page_permission(p_page_id, 'manage_roles')
  ) then
    raise exception 'You do not have permission to manage this page''s team.';
  end if;

  if p_role not in ('manager','editor','content_creator','moderator','customer_support','analyst') then
    raise exception 'Invalid role.';
  end if;

  update public.page_roles set role = p_role where page_id = p_page_id and user_id = p_user_id;
  if not found then
    raise exception 'This user is not on the team.';
  end if;
end;
$$;

create or replace function public.remove_page_team_member(
  p_page_id uuid,
  p_user_id uuid
)
returns void
language plpgsql
security definer
set search_path = 'public'
as $$
begin
  if not (
    public.current_user_page_role(p_page_id) = 'owner'
    or public.current_user_has_page_permission(p_page_id, 'manage_roles')
  ) then
    raise exception 'You do not have permission to manage this page''s team.';
  end if;

  delete from public.page_roles where page_id = p_page_id and user_id = p_user_id;
  if not found then
    raise exception 'This user is not on the team.';
  end if;
end;
$$;

grant execute on function public.add_page_team_member(uuid, text, text) to authenticated;
grant execute on function public.update_page_team_member_role(uuid, uuid, text) to authenticated;
grant execute on function public.remove_page_team_member(uuid, uuid) to authenticated;
