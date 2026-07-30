-- 051_fix_community_memberships_rls_recursion.sql
-- migration 049's memberships_select_members policy checked "is the caller
-- a member of this same community?" with a subquery against
-- community_memberships itself. Postgres re-evaluates RLS on every access
-- to a table, including from inside that table's own policy, so this was
-- unconditional infinite recursion (42P17) — it broke get_home_feed_cursor
-- and get_community_feed (both security invoker, so both run under the
-- caller's RLS), i.e. the home feed and every community feed, app-wide,
-- for every signed-in user. This is why the app started showing a
-- generic "offline" banner even on a good connection: the RPC call was
-- erroring server-side, not timing out.
--
-- Fix: move the self-check into a SECURITY DEFINER function. Because it
-- runs as the function owner rather than the querying role, its internal
-- query against community_memberships does not re-trigger RLS on that
-- table, which breaks the recursion.
--
-- Backfilled into the migrations folder on 2026-07-30 — this was applied
-- directly to the live project (version 20260730060214) and had no
-- corresponding file in this repo until now.

create or replace function public.is_member_of_community(p_community_id uuid)
returns boolean
language sql
stable
security definer
set search_path = 'public'
as $$
  select exists (
    select 1 from public.community_memberships m
    where m.community_id = p_community_id and m.user_id = auth.uid()
  );
$$;

grant execute on function public.is_member_of_community(uuid) to authenticated;

drop policy if exists memberships_select_members on public.community_memberships;
create policy memberships_select_members on public.community_memberships
  for select using (
    current_user_has_beta_access()
    and (
      user_id = auth.uid()
      or is_admin_or_mod()
      or is_member_of_community(community_memberships.community_id)
    )
  );
