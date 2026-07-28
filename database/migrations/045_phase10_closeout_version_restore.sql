-- Phase 10 Closeout — Item 1: Post Version History restore.
--
-- post_edit_history (migration 031) already captures previous_text_content
-- on every edit, with correct owner/admin RLS. What was missing was any way
-- to actually use it: no restore path existed, and nothing distinguished a
-- normal edit-history row from a restore action, so a restore would have
-- been indistinguishable from an edit in the trail.
--
-- This migration:
--   1. Adds post_edit_history.edit_type ('edit' | 'restore') so the admin
--      viewer can label restore events instead of showing them as plain edits.
--   2. Adds restored_from_history_id so a restore row links back to the
--      version it restored, without needing to parse admin_audit_log.
--   3. Adds restore_post_to_version(post_id, edit_history_id) — admin/mod
--      only, snapshots current state first (so the restore itself is
--      undoable via the same mechanism), reverts posts.text_content,
--      bumps edited_at/edit_count, and writes to admin_audit_log via the
--      existing log_admin_action() helper.
--
-- Scope note: editPost() only ever snapshots text_content today (not tags,
-- visibility, or media — previous_media exists on the table but nothing
-- populates it yet). Restoring is therefore limited to text_content, which
-- matches what's actually tracked. Extending edit tracking to tags/
-- visibility/media is a separate follow-up, not silently assumed here.

begin;

alter table public.post_edit_history
  add column if not exists edit_type text not null default 'edit',
  add column if not exists restored_from_history_id uuid references public.post_edit_history(id);

alter table public.post_edit_history
  add constraint post_edit_history_edit_type_check
  check (edit_type in ('edit', 'restore'));

create or replace function public.restore_post_to_version(p_post_id uuid, p_edit_history_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_history record;
  v_current record;
  v_new_history_id uuid;
begin
  if not public.is_admin_or_mod() then
    raise exception 'not authorized' using errcode = '42501';
  end if;

  select id, previous_text_content into v_history
  from public.post_edit_history
  where id = p_edit_history_id and post_id = p_post_id;

  if not found then
    raise exception 'Edit history entry % not found for post %', p_edit_history_id, p_post_id using errcode = 'P0002';
  end if;

  select text_content, edit_count into v_current
  from public.posts
  where id = p_post_id;

  if not found then
    raise exception 'Post % not found', p_post_id using errcode = 'P0002';
  end if;

  -- Snapshot the pre-restore state as its own history row (edit_type =
  -- 'restore'), so restoring never destroys trail — you can always restore
  -- the restore.
  insert into public.post_edit_history (post_id, editor_id, previous_text_content, edit_type, restored_from_history_id)
  values (p_post_id, auth.uid(), v_current.text_content, 'restore', p_edit_history_id)
  returning id into v_new_history_id;

  update public.posts
  set text_content = v_history.previous_text_content,
      edited_at = now(),
      edit_count = coalesce(v_current.edit_count, 0) + 1
  where id = p_post_id;

  perform public.log_admin_action(
    'restore_post_version',
    'post',
    p_post_id::text,
    jsonb_build_object(
      'restored_from_history_id', p_edit_history_id,
      'new_history_id', v_new_history_id,
      'restored_text_preview', left(coalesce(v_history.previous_text_content, ''), 200)
    )
  );
end;
$$;

grant execute on function public.restore_post_to_version(uuid, uuid) to authenticated;

commit;
