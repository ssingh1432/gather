-- Fixes: "already accepted privacy policy at signup, but Data & Privacy
-- still says not accepted."
--
-- Root cause: the client only recorded consent (consent_records insert)
-- when a session already existed right after auth.signUp(). Whenever email
-- confirmation is required (the normal case), there's no session yet at
-- that moment -- the client silently skipped it, and nothing ever went
-- back and recorded it once the person actually confirmed/logged in. From
-- the user's POV they checked "I agree" and it just... didn't stick.
--
-- Fix: record consent inside the same SECURITY DEFINER trigger that
-- already provisions public.users on auth.users insert. This fires at
-- account-creation time regardless of whether a session exists yet, so it
-- can't be skipped by the confirmation-required path. The client passes
-- the policy version it showed the user via signUp() metadata; the
-- trigger falls back to a hardcoded current version if that's missing
-- (e.g. an older client build).
--
-- Applied live via Supabase MCP on 2026-07-21; this file exists to keep
-- the migration history in the repo in sync.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_policy_version text;
begin
  insert into public.users (id, email, username, phone_number, status)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data->>'username', split_part(new.email, '@', 1)),
    nullif(new.raw_user_meta_data->>'phone_number', ''),
    'active'
  )
  on conflict (id) do nothing;

  v_policy_version := coalesce(new.raw_user_meta_data->>'privacy_policy_version', '2026-07-19');

  insert into public.consent_records (user_id, consent_type, policy_version, granted, metadata)
  values
    (new.id, 'privacy_policy', v_policy_version, true, jsonb_build_object('source', 'signup')),
    (new.id, 'terms_of_service', v_policy_version, true, jsonb_build_object('source', 'signup'));

  return new;
end;
$function$;
