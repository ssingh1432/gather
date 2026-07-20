-- Phase 3: Privacy Compliance
-- Consent tracking, data export/deletion requests, mute list, and the
-- remaining granular visibility controls not already covered by migration
-- 009 (default_post_visibility, message_privacy, tag_privacy, is_private,
-- show_activity_status).

-- ---------------------------------------------------------------------
-- 1. Remaining privacy settings: search visibility + last-seen visibility
-- ---------------------------------------------------------------------
alter table public.users
  add column if not exists search_visibility text not null default 'everyone',
  add column if not exists show_last_seen boolean not null default true;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'users_search_visibility_check'
  ) then
    alter table public.users
      add constraint users_search_visibility_check
        check (search_visibility in ('everyone','friends','no_one')) not valid;
    alter table public.users validate constraint users_search_visibility_check;
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 2. Mute list (separate from user_blocks: muted users still visible to
--    you, you just stop seeing their posts/stories in your feed; unlike a
--    block it is one-directional and not disclosed to the muted user).
-- ---------------------------------------------------------------------
create table if not exists public.user_mutes (
  muter_id uuid not null references public.users(id) on delete cascade,
  muted_id uuid not null references public.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (muter_id, muted_id),
  constraint user_mutes_no_self_mute check (muter_id <> muted_id)
);

create index if not exists idx_user_mutes_muter on public.user_mutes (muter_id);

alter table public.user_mutes enable row level security;
revoke all on public.user_mutes from anon, authenticated;
grant select, insert, update, delete on public.user_mutes to authenticated;

create policy "Users manage their own mute list"
  on public.user_mutes for all
  to authenticated
  using (muter_id = auth.uid())
  with check (muter_id = auth.uid());

-- ---------------------------------------------------------------------
-- 3. Consent records — append-only audit trail. Every acceptance of a
--    privacy policy / terms / cookie-storage consent creates a new row
--    rather than overwriting the last one, so we always have proof of
--    what was agreed to and when (needed for Phase 4 legal compliance).
-- ---------------------------------------------------------------------
create table if not exists public.consent_records (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  consent_type text not null, -- 'privacy_policy' | 'terms_of_service' | 'cookie_storage' | 'data_processing' | 'marketing'
  policy_version text not null,
  granted boolean not null,
  recorded_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb -- e.g. {"platform":"web","locale":"ne"}
);

create index if not exists idx_consent_records_user on public.consent_records (user_id, consent_type, recorded_at desc);

alter table public.consent_records enable row level security;
revoke all on public.consent_records from anon, authenticated;
grant select, insert on public.consent_records to authenticated;

create policy "Users read their own consent history"
  on public.consent_records for select
  to authenticated
  using (user_id = auth.uid());

create policy "Users record their own consent"
  on public.consent_records for insert
  to authenticated
  with check (user_id = auth.uid());

create policy "Admins read all consent records"
  on public.consent_records for select
  to authenticated
  using (public.is_admin_or_mod());

-- Convenience view: latest consent per user/type
create or replace view public.latest_consent as
select distinct on (user_id, consent_type)
  user_id, consent_type, policy_version, granted, recorded_at
from public.consent_records
order by user_id, consent_type, recorded_at desc;

grant select on public.latest_consent to authenticated;

-- ---------------------------------------------------------------------
-- 4. Data export requests (GDPR/Privacy-Act-style "download your data").
--    Fulfilled by an Edge Function that assembles a JSON bundle and
--    writes it to a private storage bucket; this table just tracks
--    status so the client can poll/notify.
-- ---------------------------------------------------------------------
create table if not exists public.data_export_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'pending', -- pending | processing | ready | failed | expired
  requested_at timestamptz not null default now(),
  completed_at timestamptz,
  file_path text, -- path within the private 'data-exports' storage bucket
  expires_at timestamptz,
  error_message text
);

create index if not exists idx_data_export_requests_user on public.data_export_requests (user_id, requested_at desc);

alter table public.data_export_requests enable row level security;
revoke all on public.data_export_requests from anon, authenticated;
grant select, insert on public.data_export_requests to authenticated;

create policy "Users manage their own export requests"
  on public.data_export_requests for select
  to authenticated
  using (user_id = auth.uid());

create policy "Users create their own export requests"
  on public.data_export_requests for insert
  to authenticated
  with check (user_id = auth.uid());

create policy "Admins read all export requests"
  on public.data_export_requests for select
  to authenticated
  using (public.is_admin_or_mod());

-- Rate-limit: at most one active export request per user at a time.
create or replace function public.request_data_export()
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_existing uuid;
  v_new_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  select id into v_existing
  from public.data_export_requests
  where user_id = auth.uid() and status in ('pending','processing')
  limit 1;

  if v_existing is not null then
    return v_existing;
  end if;

  insert into public.data_export_requests (user_id) values (auth.uid())
  returning id into v_new_id;

  perform public.log_security_event('data_export_requested', jsonb_build_object('request_id', v_new_id));

  return v_new_id;
end;
$$;

grant execute on function public.request_data_export() to authenticated;

-- ---------------------------------------------------------------------
-- 5. Account deletion — soft delete with a grace period, so accidental
--    or coerced requests can be cancelled before data is actually
--    purged. A scheduled Edge Function / cron sweeps rows past
--    scheduled_purge_at and performs the hard delete + anonymization.
-- ---------------------------------------------------------------------
alter table public.users
  add column if not exists deletion_requested_at timestamptz,
  add column if not exists scheduled_purge_at timestamptz;

create table if not exists public.account_deletion_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'pending', -- pending | cancelled | completed
  reason text,
  requested_at timestamptz not null default now(),
  scheduled_purge_at timestamptz not null,
  cancelled_at timestamptz,
  completed_at timestamptz
);

create index if not exists idx_account_deletion_requests_user on public.account_deletion_requests (user_id, requested_at desc);

alter table public.account_deletion_requests enable row level security;
revoke all on public.account_deletion_requests from anon, authenticated;
grant select, insert on public.account_deletion_requests to authenticated;

create policy "Users manage their own deletion requests"
  on public.account_deletion_requests for select
  to authenticated
  using (user_id = auth.uid());

create policy "Users create their own deletion requests"
  on public.account_deletion_requests for insert
  to authenticated
  with check (user_id = auth.uid());

create policy "Admins read all deletion requests"
  on public.account_deletion_requests for select
  to authenticated
  using (public.is_admin_or_mod());

create or replace function public.request_account_deletion(p_reason text default null, p_grace_days int default 14)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
  v_purge_at timestamptz;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  v_purge_at := now() + make_interval(days => greatest(p_grace_days, 1));

  insert into public.account_deletion_requests (user_id, reason, scheduled_purge_at)
  values (auth.uid(), p_reason, v_purge_at)
  returning id into v_id;

  update public.users
  set deletion_requested_at = now(), scheduled_purge_at = v_purge_at, status = 'pending_deletion'
  where id = auth.uid();

  perform public.log_security_event('account_deletion_requested', jsonb_build_object('scheduled_purge_at', v_purge_at));

  return v_id;
end;
$$;

grant execute on function public.request_account_deletion(text, int) to authenticated;

create or replace function public.cancel_account_deletion()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  update public.account_deletion_requests
  set status = 'cancelled', cancelled_at = now()
  where user_id = auth.uid() and status = 'pending';

  update public.users
  set deletion_requested_at = null, scheduled_purge_at = null, status = 'active'
  where id = auth.uid();

  perform public.log_security_event('account_deletion_cancelled', '{}'::jsonb);
end;
$$;

grant execute on function public.cancel_account_deletion() to authenticated;

notify pgrst, 'reload schema';
