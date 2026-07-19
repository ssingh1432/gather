-- Brute-force protection for email/password login.
-- Client calls check_login_lockout() before attempting sign-in, and
-- record_login_attempt() after each attempt succeeds or fails. The table
-- itself has no direct grants; all access goes through these two
-- SECURITY DEFINER functions so it can't be read or tampered with by
-- clients directly.

create table if not exists public.auth_login_attempts (
  id bigint generated always as identity primary key,
  email text not null,
  success boolean not null,
  created_at timestamptz not null default now()
);

create index if not exists idx_auth_login_attempts_email_created
  on public.auth_login_attempts (email, created_at desc);

alter table public.auth_login_attempts enable row level security;
revoke all on public.auth_login_attempts from anon, authenticated;

create or replace function public.record_login_attempt(p_email text, p_success boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.auth_login_attempts (email, success)
  values (lower(trim(p_email)), p_success);

  -- Keep the table small: prune attempts older than 1 day.
  delete from public.auth_login_attempts
  where created_at < now() - interval '1 day';
end;
$$;

grant execute on function public.record_login_attempt(text, boolean) to anon, authenticated;

create or replace function public.check_login_lockout(p_email text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email text := lower(trim(p_email));
  v_recent_failures int;
  v_last_failure timestamptz;
  v_retry_after int;
begin
  select count(*), max(created_at)
    into v_recent_failures, v_last_failure
  from public.auth_login_attempts
  where email = v_email
    and success = false
    and created_at > now() - interval '15 minutes';

  if v_recent_failures >= 5 then
    v_retry_after := greatest(0, 900 - extract(epoch from (now() - v_last_failure))::int);
    if v_retry_after > 0 then
      return jsonb_build_object('locked', true, 'retry_after_seconds', v_retry_after);
    end if;
  end if;

  return jsonb_build_object('locked', false, 'retry_after_seconds', 0);
end;
$$;

grant execute on function public.check_login_lockout(text) to anon, authenticated;
