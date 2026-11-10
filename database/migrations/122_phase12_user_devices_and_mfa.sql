-- Phase 12 / Step 1: device sessions, trusted devices, and 2FA (TOTP) support.
--
-- TOTP enrollment/verification itself is handled by Supabase Auth MFA
-- (auth.mfa_factors); nothing here re-implements it. This migration adds:
--   1. public.user_devices        - per-user device registry (login alerts,
--                                   "your devices" list, trusted devices)
--   2. register_device / list_my_devices / is_device_trusted /
--      set_device_trust / revoke_device   (SECURITY DEFINER RPCs)
--   3. require_aal2_if_enrolled() - server-side step-up guard for sensitive RPCs
--
-- Limits (documented honestly):
--   * Supabase sessions are not linked to a device_id, so revoking a device
--     un-trusts it and the client then calls signOut(scope: others). A
--     single remote session cannot be killed from SQL.
--   * "Trusted device" only skips the login-time 2FA prompt in the app.
--     Sensitive RPCs below still demand an AAL2 session.
--
-- Manual apply required: CI does not run migrations.

create table if not exists public.user_devices (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  device_id text not null check (char_length(device_id) between 16 and 64),
  device_name text not null check (char_length(device_name) between 1 and 100),
  platform text not null default 'unknown'
    check (platform in ('android','ios','web','macos','windows','linux','unknown')),
  first_seen_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  trusted_until timestamptz,
  revoked_at timestamptz,
  unique (user_id, device_id)
);

create index if not exists idx_user_devices_user_last_seen
  on public.user_devices (user_id, last_seen_at desc);

alter table public.user_devices enable row level security;
revoke all on public.user_devices from anon, authenticated;
grant select on public.user_devices to authenticated;

drop policy if exists "Users read own devices" on public.user_devices;
create policy "Users read own devices"
  on public.user_devices for select
  to authenticated
  using (user_id = auth.uid());

-- ---------------------------------------------------------------------
-- Step-up guard: raises when the user has a verified MFA factor but the
-- current JWT is not AAL2.
-- ---------------------------------------------------------------------
create or replace function public.require_aal2_if_enrolled()
returns void
language plpgsql
stable
security definer
set search_path = public, auth
as $$
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  if exists (
    select 1 from auth.mfa_factors
    where user_id = auth.uid() and status = 'verified'
  ) and coalesce(auth.jwt() ->> 'aal', 'aal1') <> 'aal2' then
    raise exception 'mfa_required' using errcode = '42501';
  end if;
end;
$$;

revoke all on function public.require_aal2_if_enrolled() from public, anon;
grant execute on function public.require_aal2_if_enrolled() to authenticated;

-- ---------------------------------------------------------------------
-- register_device: called after every successful sign-in.
-- Returns { is_new, trusted }. A previously revoked device is treated as
-- new again (trust cleared). New devices write a security event so the
-- login-alert pipeline can pick them up.
-- ---------------------------------------------------------------------
create or replace function public.register_device(
  p_device_id text,
  p_device_name text,
  p_platform text default 'unknown'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_row public.user_devices%rowtype;
  v_platform text := lower(coalesce(p_platform, 'unknown'));
  v_name text := left(trim(coalesce(p_device_name, '')), 100);
  v_is_new boolean := false;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;
  if p_device_id is null or char_length(p_device_id) not between 16 and 64 then
    raise exception 'invalid_device_id' using errcode = '22023';
  end if;
  if v_name = '' then v_name := 'Unknown device'; end if;
  if v_platform not in ('android','ios','web','macos','windows','linux') then
    v_platform := 'unknown';
  end if;

  select * into v_row from public.user_devices
  where user_id = v_uid and device_id = p_device_id
  for update;

  if not found then
    insert into public.user_devices (user_id, device_id, device_name, platform)
    values (v_uid, p_device_id, v_name, v_platform)
    returning * into v_row;
    v_is_new := true;
  elsif v_row.revoked_at is not null then
    update public.user_devices
       set revoked_at = null, trusted_until = null,
           device_name = v_name, platform = v_platform, last_seen_at = now()
     where id = v_row.id
    returning * into v_row;
    v_is_new := true;
  else
    update public.user_devices
       set last_seen_at = now(), device_name = v_name, platform = v_platform
     where id = v_row.id
    returning * into v_row;
  end if;

  if v_is_new then
    insert into public.security_events (actor_id, event_type, metadata)
    values (v_uid, 'new_device_login',
            jsonb_build_object('device_name', v_name, 'platform', v_platform));
  end if;

  return jsonb_build_object(
    'is_new', v_is_new,
    'trusted', v_row.trusted_until is not null and v_row.trusted_until > now()
  );
end;
$$;

revoke all on function public.register_device(text, text, text) from public, anon;
grant execute on function public.register_device(text, text, text) to authenticated;

create or replace function public.is_device_trusted(p_device_id text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.user_devices
    where user_id = auth.uid()
      and device_id = p_device_id
      and revoked_at is null
      and trusted_until is not null
      and trusted_until > now()
  );
$$;

revoke all on function public.is_device_trusted(text) from public, anon;
grant execute on function public.is_device_trusted(text) to authenticated;

create or replace function public.list_my_devices()
returns table (
  id uuid, device_id text, device_name text, platform text,
  first_seen_at timestamptz, last_seen_at timestamptz,
  trusted boolean, revoked boolean
)
language sql
stable
security definer
set search_path = public
as $$
  select d.id, d.device_id, d.device_name, d.platform,
         d.first_seen_at, d.last_seen_at,
         (d.revoked_at is null and d.trusted_until is not null and d.trusted_until > now()),
         (d.revoked_at is not null)
  from public.user_devices d
  where d.user_id = auth.uid()
  order by d.last_seen_at desc
  limit 50;
$$;

revoke all on function public.list_my_devices() from public, anon;
grant execute on function public.list_my_devices() to authenticated;

-- Trust (or un-trust) the device. Trusting requires AAL2 when 2FA is on.
create or replace function public.set_device_trust(
  p_device_id text,
  p_trusted boolean,
  p_days int default 30
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_days int := greatest(1, least(coalesce(p_days, 30), 90));
  v_count int;
begin
  perform public.require_aal2_if_enrolled();

  update public.user_devices
     set trusted_until = case when p_trusted then now() + make_interval(days => v_days) else null end
   where user_id = auth.uid() and device_id = p_device_id and revoked_at is null;
  get diagnostics v_count = row_count;
  if v_count = 0 then
    raise exception 'device_not_found' using errcode = 'P0002';
  end if;

  insert into public.security_events (actor_id, event_type, metadata)
  values (auth.uid(),
          case when p_trusted then 'device_trusted' else 'device_untrusted' end,
          jsonb_build_object('device_id', left(p_device_id, 8)));
end;
$$;

revoke all on function public.set_device_trust(text, boolean, int) from public, anon;
grant execute on function public.set_device_trust(text, boolean, int) to authenticated;

create or replace function public.revoke_device(p_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare v_count int;
begin
  perform public.require_aal2_if_enrolled();

  update public.user_devices
     set revoked_at = now(), trusted_until = null
   where id = p_id and user_id = auth.uid() and revoked_at is null;
  get diagnostics v_count = row_count;
  if v_count = 0 then
    raise exception 'device_not_found' using errcode = 'P0002';
  end if;

  insert into public.security_events (actor_id, event_type, metadata)
  values (auth.uid(), 'device_revoked', jsonb_build_object('device_row', p_id));
end;
$$;

revoke all on function public.revoke_device(uuid) from public, anon;
grant execute on function public.revoke_device(uuid) to authenticated;
