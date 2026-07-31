-- 056_communities_update_rls_manage_settings.sql
-- Found while wiring category/tag editing into the edit-community screen:
-- communities_update_owner_or_admin only allowed `created_by = auth.uid()
-- OR is_admin_or_mod()` — i.e. the literal creator or a site-wide admin/mod.
-- A *community* admin (a role granted by the owner, distinct from being
-- the creator) could open the edit screen (gated by `_canManage` in
-- Flutter, which includes admin/moderator) but would get a raw RLS
-- rejection on save. The new set_community_tags()/set_community_category()
-- RPCs from 055/052 correctly allow a community admin via the
-- manage_settings permission, which made the mismatch obvious: same
-- screen, same admin, one call succeeds and the other 42501s.
--
-- Fix: extend the policy to also honor manage_settings, aligning the raw
-- column update with the RPCs. Moderators still can't save settings
-- (manage_settings isn't in their default permission set) — only
-- owner/admin, same as before, now correctly including non-creator admins.

drop policy if exists communities_update_owner_or_admin on public.communities;
create policy communities_update_owner_or_admin on public.communities
  for update using (
    created_by = auth.uid()
    or is_admin_or_mod()
    or current_user_community_permission(id, 'manage_settings')
  )
  with check (
    created_by = auth.uid()
    or is_admin_or_mod()
    or current_user_community_permission(id, 'manage_settings')
  );
