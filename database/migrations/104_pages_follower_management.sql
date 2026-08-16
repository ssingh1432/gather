-- 104_pages_follower_management.sql
-- Page owner/manager audience control: remove a follower without allowing
-- arbitrary authenticated users to delete rows directly.

create or replace function public.remove_page_follower(
  p_page_id uuid,
  p_user_id uuid
)
returns void
language plpgsql
security definer
set search_path = 'public'
as $$
begin
  if not public.current_user_has_page_permission(p_page_id, 'manage_roles') then
    raise exception 'Not authorized to manage followers for this page.';
  end if;

  delete from public.page_followers
  where page_id = p_page_id
    and user_id = p_user_id;

  if found then
    perform public.log_page_audit_event(
      p_page_id,
      'follower_removed',
      'user',
      p_user_id,
      jsonb_build_object('removed_user_id', p_user_id)
    );
  end if;
end;
$$;

grant execute on function public.remove_page_follower(uuid, uuid) to authenticated;
