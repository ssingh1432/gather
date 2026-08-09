-- 092_pages_eligibility_fn_fix.sql
-- Professional Page System — Step 16 (Testing) bug fix.
--
-- Found via direct RPC testing: check_page_monetization_eligibility
-- (migration 089) threw "malformed array literal" for any page failing
-- at least one eligibility check — i.e. virtually every real page, since
-- 100+ followers AND 30+ days old is a high bar for a brand new page.
-- Root cause: `v_reasons := v_reasons || 'some text';` is ambiguous in
-- PL/pgSQL between the anyarray||anyarray and anyarray||anyelement
-- operators; Postgres picked the array-array form and tried to parse the
-- literal as an array, which fails outright since it isn't
-- curly-brace-formatted. Fix: an explicit ::text cast on each appended
-- literal forces the correct anyarray||anyelement resolution.
create or replace function public.check_page_monetization_eligibility(p_page_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = 'public'
as $$
declare
  v_page record;
  v_reasons text[] := array[]::text[];
begin
  select follower_count, verification_status, status, created_at into v_page
  from public.pages where id = p_page_id;

  if v_page is null then
    return jsonb_build_object('eligible', false, 'reasons', array['Page not found']::text[]);
  end if;
  if not public.current_user_has_page_permission(p_page_id, 'manage_monetization') then
    return jsonb_build_object('eligible', false, 'reasons', array['Not authorized']::text[]);
  end if;

  if v_page.status <> 'published' then
    v_reasons := v_reasons || 'Page must be published'::text;
  end if;
  if v_page.follower_count < 100 then
    v_reasons := v_reasons || 'Page needs at least 100 followers'::text;
  end if;
  if v_page.created_at > now() - interval '30 days' then
    v_reasons := v_reasons || 'Page must be at least 30 days old'::text;
  end if;

  return jsonb_build_object('eligible', array_length(v_reasons, 1) is null, 'reasons', to_jsonb(v_reasons));
end;
$$;
