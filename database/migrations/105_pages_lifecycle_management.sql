-- 105_pages_lifecycle_management.sql
-- Page-only lifecycle controls: deactivate/reactivate and permanent deletion.
-- Deactivation preserves the Page and its data; permanent deletion is an
-- explicit owner-only destructive action and relies on existing cascades.

alter table public.pages
  add column if not exists deactivated_at timestamptz,
  add column if not exists deactivated_by uuid references public.users(id) on delete set null;

create index if not exists idx_pages_deactivated
  on public.pages (deactivated_at)
  where deactivated_at is not null;

create or replace function public.deactivate_page(p_page_id uuid)
returns void
language plpgsql
security definer
set search_path = 'public'
as $$
begin
  if public.current_user_page_role(p_page_id) <> 'owner' then
    raise exception 'Only the Page owner can deactivate this Page.';
  end if;

  update public.pages
  set status = 'draft',
      deactivated_at = now(),
      deactivated_by = auth.uid()
  where id = p_page_id
    and deleted_at is null;

  if not found then
    raise exception 'Page not found.';
  end if;

  perform public.log_page_audit_event(
    p_page_id,
    'page_deactivated',
    'page',
    p_page_id,
    jsonb_build_object('reason', 'owner_action')
  );
end;
$$;

grant execute on function public.deactivate_page(uuid) to authenticated;

create or replace function public.reactivate_page(p_page_id uuid)
returns void
language plpgsql
security definer
set search_path = 'public'
as $$
begin
  if public.current_user_page_role(p_page_id) <> 'owner' then
    raise exception 'Only the Page owner can reactivate this Page.';
  end if;

  update public.pages
  set status = 'published',
      deactivated_at = null,
      deactivated_by = null
  where id = p_page_id
    and deleted_at is null
    and deactivated_at is not null;

  if not found then
    raise exception 'Page is not currently deactivated.';
  end if;

  perform public.log_page_audit_event(
    p_page_id,
    'page_reactivated',
    'page',
    p_page_id,
    '{}'::jsonb
  );
end;
$$;

grant execute on function public.reactivate_page(uuid) to authenticated;

create or replace function public.delete_page_permanently(p_page_id uuid)
returns void
language plpgsql
security definer
set search_path = 'public'
as $$
begin
  if public.current_user_page_role(p_page_id) <> 'owner' then
    raise exception 'Only the Page owner can permanently delete this Page.';
  end if;

  if not exists (
    select 1 from public.pages
    where id = p_page_id and deleted_at is null
  ) then
    raise exception 'Page not found.';
  end if;

  -- Record the destructive action before the page cascades away.
  perform public.log_page_audit_event(
    p_page_id,
    'page_deleted_permanently',
    'page',
    p_page_id,
    jsonb_build_object('deleted_at', now())
  );

  update public.pages
  set deleted_at = now(),
      status = 'draft'
  where id = p_page_id;

  delete from public.pages where id = p_page_id;
end;
$$;

grant execute on function public.delete_page_permanently(uuid) to authenticated;
