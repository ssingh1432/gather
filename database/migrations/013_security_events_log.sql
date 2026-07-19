-- General-purpose security event log for auth-adjacent events that aren't
-- already covered by moderation_actions (admin actions) or
-- auth_login_attempts (login brute-force). Starting set: password reset
-- requested/completed. Self-service only — a user can log an event for
-- themselves, never for anyone else; only admins/mods can read the log.

create table if not exists public.security_events (
  id bigint generated always as identity primary key,
  actor_id uuid references auth.users(id) on delete set null,
  event_type text not null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists idx_security_events_actor_created
  on public.security_events (actor_id, created_at desc);

alter table public.security_events enable row level security;
revoke all on public.security_events from anon, authenticated;

-- Reuses the existing is_admin_or_mod() helper (see migration 002+) rather
-- than re-deriving the role check, so this stays correct if that schema
-- ever changes.
create policy "Admins and mods can read security events"
  on public.security_events for select
  to authenticated
  using (public.is_admin_or_mod());

create or replace function public.log_security_event(p_event_type text, p_metadata jsonb default '{}'::jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.security_events (actor_id, event_type, metadata)
  values (auth.uid(), p_event_type, coalesce(p_metadata, '{}'::jsonb));
end;
$$;

grant execute on function public.log_security_event(text, jsonb) to authenticated;
-- Password reset REQUEST happens while logged out (no auth.uid()), so
-- allow anon to call it too — actor_id will just be null for that case,
-- which is fine since the email itself is the useful signal and we don't
-- want to leak account-existence info by requiring auth.
grant execute on function public.log_security_event(text, jsonb) to anon;
