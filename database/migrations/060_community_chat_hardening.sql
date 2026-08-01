-- 060_community_chat_hardening.sql
-- Follow-up to 059, applied after the Supabase security advisor flagged two
-- real issues immediately after 059 went live:
--
-- 1) chat_messages_update_moderate had `with check (true)` — technically
--    let a moderator's UPDATE rewrite ANY column (including another
--    member's message content), not just moderation fields. Fixed with a
--    trigger that pins down exactly which columns a non-sender update may
--    touch, and the WITH CHECK now re-asserts the permission check instead
--    of a bare `true`.
--
-- 2) mark_community_chat_read didn't need SECURITY DEFINER at all — the
--    table's own RLS (insert requires user_id = auth.uid() and
--    is_member_of_community; update requires user_id = auth.uid()) already
--    enforces the same rule the function's manual check was duplicating.
--    Switched to INVOKER, which also removes it from being reachable by
--    `anon` (definer functions default to PUBLIC execute).

create or replace function public.enforce_chat_message_moderation_columns()
returns trigger
language plpgsql
set search_path = 'public'
as $$
begin
  -- Owner-edit path (chat_messages_update_own) already restricts to the
  -- sender; nothing extra to enforce there. This only tightens the
  -- moderator path, i.e. when the editor is NOT the original sender.
  if auth.uid() is distinct from old.sender_id then
    if new.content is distinct from old.content
      or new.sender_id is distinct from old.sender_id
      or new.community_id is distinct from old.community_id
      or new.reply_to_id is distinct from old.reply_to_id
      or new.is_announcement is distinct from old.is_announcement
      or new.created_at is distinct from old.created_at
    then
      raise exception 'Moderators may only pin, unpin, or soft-delete messages — not edit their content' using errcode = '42501';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_enforce_chat_message_moderation_columns on public.community_chat_messages;
create trigger trg_enforce_chat_message_moderation_columns
  before update on public.community_chat_messages
  for each row execute function public.enforce_chat_message_moderation_columns();

drop policy if exists chat_messages_update_moderate on public.community_chat_messages;
create policy chat_messages_update_moderate on public.community_chat_messages
  for update using (
    is_admin_or_mod() or current_user_community_permission(community_id, 'manage_chat')
  )
  with check (
    is_admin_or_mod() or current_user_community_permission(community_id, 'manage_chat')
  );

create or replace function public.mark_community_chat_read(p_community_id uuid, p_last_message_id uuid default null)
returns void
language plpgsql
security invoker
set search_path = 'public'
as $$
begin
  insert into public.community_chat_read_state (community_id, user_id, last_read_message_id, last_read_at)
  values (p_community_id, auth.uid(), p_last_message_id, now())
  on conflict (community_id, user_id)
  do update set last_read_message_id = coalesce(excluded.last_read_message_id, community_chat_read_state.last_read_message_id),
                last_read_at = now();
end;
$$;

revoke execute on function public.mark_community_chat_read(uuid, uuid) from public;
revoke execute on function public.mark_community_chat_read(uuid, uuid) from anon;
grant execute on function public.mark_community_chat_read(uuid, uuid) to authenticated;

revoke execute on function public.get_community_chat_messages(uuid, timestamptz, integer, boolean) from public;
revoke execute on function public.get_community_chat_messages(uuid, timestamptz, integer, boolean) from anon;
grant execute on function public.get_community_chat_messages(uuid, timestamptz, integer, boolean) to authenticated;

revoke execute on function public.get_community_chat_unread_count(uuid) from public;
revoke execute on function public.get_community_chat_unread_count(uuid) from anon;
grant execute on function public.get_community_chat_unread_count(uuid) to authenticated;
