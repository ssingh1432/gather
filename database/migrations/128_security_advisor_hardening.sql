-- 128: fixes from the Supabase security advisor run of 2026-11-18.
--
-- 1. function_search_path_mutable (7 functions): pin search_path. All seven are
--    SECURITY INVOKER and use no extension objects, so `public` is sufficient.
-- 2. anon_security_definer_function_executable: remove anonymous EXECUTE from
--    helpers that are NOT used by any policy that applies to anon/PUBLIC and
--    are NOT needed before sign-in. Re-grant explicitly to authenticated and
--    service_role (revoking from PUBLIC would otherwise drop those too).
--    Kept on purpose for anon: check_login_lockout, record_login_attempt
--    (pre-login), log_security_event (password-reset request is logged out,
--    now allow-listed below) and every helper referenced by an anon/PUBLIC
--    RLS policy (revoking those would turn empty results into permission errors).
-- 3. log_security_event: anonymous callers could write arbitrary event types
--    and metadata into security_events (log pollution). Anonymous callers may
--    now only log `password_reset_requested`; payloads are size-capped.

alter function public.enforce_child_safety_mode()            set search_path = public;
alter function public.enforce_scheduled_post_editable()      set search_path = public;
alter function public.slugify(text)                          set search_path = public;
alter function public.guard_page_visitor_post_update()       set search_path = public;
alter function public.validate_username(text)                set search_path = public;
alter function public.touch_legal_complaint_updated_at()     set search_path = public;
alter function public.enforce_user_links_limit()             set search_path = public;

revoke all on function public.community_activity_notifications_enabled(uuid)       from public, anon;
revoke all on function public.community_role_can(uuid, text, text)                 from public, anon;
revoke all on function public.has_permission(text)                                 from public, anon;
revoke all on function public.is_admin()                                           from public, anon;
revoke all on function public.trending_hashtags(integer, integer)                  from public, anon;

grant execute on function public.community_activity_notifications_enabled(uuid)    to authenticated, service_role;
grant execute on function public.community_role_can(uuid, text, text)              to authenticated, service_role;
grant execute on function public.has_permission(text)                              to authenticated, service_role;
grant execute on function public.is_admin()                                        to authenticated, service_role;
grant execute on function public.trending_hashtags(integer, integer)               to authenticated, service_role;

create or replace function public.log_security_event(p_event_type text, p_metadata jsonb default '{}'::jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_meta jsonb := coalesce(p_metadata, '{}'::jsonb);
begin
  if p_event_type is null or length(p_event_type) = 0 or length(p_event_type) > 64 then
    raise exception 'invalid_event_type' using errcode = 'P0001';
  end if;
  if length(v_meta::text) > 4096 then
    raise exception 'metadata_too_large' using errcode = 'P0001';
  end if;
  -- Logged-out callers (no auth.uid()) may only record a password-reset request.
  if auth.uid() is null and p_event_type <> 'password_reset_requested' then
    raise exception 'event_not_allowed' using errcode = 'P0001';
  end if;

  insert into public.security_events (actor_id, event_type, metadata)
  values (auth.uid(), p_event_type, v_meta);
end;
$$;

comment on table public.auth_login_attempts is 'Deny-all by design (RLS on, no policies). Accessed only via SECURITY DEFINER check_login_lockout/record_login_attempt.';
comment on table public.repo_migrations     is 'Deny-all by design (RLS on, no policies). Written only by scripts/apply_migrations.py with the management API.';
comment on table public.allowed_beta_emails is 'Deny-all to API clients by design (RLS on, no policies). Managed with the service role / dashboard only.';
