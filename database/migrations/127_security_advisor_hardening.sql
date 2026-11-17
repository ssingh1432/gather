-- 127: Supabase security-advisor hardening (idempotent, no behaviour change
-- for legitimate callers).
--
-- 1. function_search_path_mutable: pin search_path on 7 functions flagged by
--    the advisor (lint 0011).
-- 2. log_security_event is executable by anon (needed for the logged-out
--    password-reset request). Constrain it so anonymous callers cannot write
--    arbitrary event types / unbounded metadata into security_events.

alter function public.enforce_child_safety_mode()          set search_path = public, pg_temp;
alter function public.enforce_scheduled_post_editable()    set search_path = public, pg_temp;
alter function public.slugify(text)                        set search_path = public, pg_temp;
alter function public.guard_page_visitor_post_update()     set search_path = public, pg_temp;
alter function public.validate_username(text)              set search_path = public, pg_temp;
alter function public.touch_legal_complaint_updated_at()   set search_path = public, pg_temp;
alter function public.enforce_user_links_limit()           set search_path = public, pg_temp;

create or replace function public.log_security_event(p_event_type text, p_metadata jsonb default '{}'::jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_meta jsonb := coalesce(p_metadata, '{}'::jsonb);
  v_anon boolean := auth.uid() is null and coalesce(auth.role(), 'anon') = 'anon';
begin
  if p_event_type is null or p_event_type !~ '^[a-z0-9_]{1,64}$' then
    raise exception 'invalid_event_type' using errcode = '22023';
  end if;
  if octet_length(v_meta::text) > 4096 then
    raise exception 'metadata_too_large' using errcode = '22023';
  end if;
  -- Logged-out callers may only record the password-reset request signal.
  if v_anon and p_event_type <> 'password_reset_requested' then
    raise exception 'not_allowed_for_anon' using errcode = '42501';
  end if;

  insert into public.security_events (actor_id, event_type, metadata)
  values (auth.uid(), p_event_type, v_meta);
end;
$$;
