-- 120_pages_monetization_update_hardening.sql
-- Professional Pages only.
--
-- The Page settings UPDATE policy intentionally permits manage_settings, but
-- monetization activation is a separate capability. The UI already checks
-- check_page_monetization_eligibility(); this trigger makes that rule
-- authoritative at the database boundary so a direct client update cannot
-- bypass it.

create or replace function public.guard_page_monetization_update()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_eligibility jsonb;
begin
  -- Turning monetization on or manually marking it approved is a
  -- monetization operation, not an ordinary Page-settings operation.
  if (new.monetization_enabled is true and old.monetization_enabled is not true)
     or (new.monetization_status = 'approved'
         and coalesce(old.monetization_status, '') <> 'approved') then

    if not public.current_user_has_page_permission(NEW.id, 'manage_monetization') then
      raise exception 'manage_monetization permission required';
    end if;

    v_eligibility := public.check_page_monetization_eligibility(NEW.id);

    if coalesce((v_eligibility ->> 'eligible')::boolean, false) is not true then
      raise exception 'Page is not eligible for monetization: %',
        coalesce(v_eligibility -> 'reasons', '[]'::jsonb);
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_guard_page_monetization_update on public.pages;

create trigger trg_guard_page_monetization_update
before update of monetization_enabled, monetization_status on public.pages
for each row
execute function public.guard_page_monetization_update();

comment on function public.guard_page_monetization_update() is
  'Professional Pages only: enforces manage_monetization and server-side eligibility when activating or approving Page monetization.';
