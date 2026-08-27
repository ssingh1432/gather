-- 082_fix_page_inbox_user_id_ambiguity.sql
-- Fixes the Page inbox RPC's PL/pgSQL output-parameter/column name collision.
--
-- `list_page_message_threads` returns a `user_id` column. In PL/pgSQL,
-- output columns are variables in scope, so an unqualified `user_id` inside
-- `DISTINCT ON` was ambiguous between the function variable and
-- `page_messages.user_id` (Postgres 42702). Qualify the source column while
-- preserving the RPC signature, authorization, ordering, and result shape.

create or replace function public.list_page_message_threads(p_page_id uuid)
returns table(
  user_id uuid,
  username text,
  display_name text,
  profile_photo_url text,
  last_message text,
  last_message_at timestamptz,
  last_sender_type text,
  unread_count bigint
)
language plpgsql
security definer
set search_path = 'public'
as $$
begin
  if not (
    public.current_user_page_role(p_page_id) = 'owner'
    or public.current_user_has_page_permission(p_page_id, 'manage_messages')
  ) then
    raise exception 'Not authorized to view this page''s inbox.';
  end if;

  return query
  select
    u.id,
    u.username,
    u.display_name,
    u.profile_photo_url,
    last_msg.content,
    last_msg.created_at,
    last_msg.sender_type,
    (
      select count(*) from public.page_messages pm2
      where pm2.page_id = p_page_id
        and pm2.user_id = u.id
        and pm2.sender_type = 'user'
        and pm2.read_at is null
    )::bigint
  from (
    select distinct on (pm.user_id)
      pm.user_id,
      pm.content,
      pm.created_at,
      pm.sender_type
    from public.page_messages pm
    where pm.page_id = p_page_id
    order by pm.user_id, pm.created_at desc
  ) last_msg
  join public.users u on u.id = last_msg.user_id
  order by last_msg.created_at desc;
end;
$$;

grant execute on function public.list_page_message_threads(uuid) to authenticated;
