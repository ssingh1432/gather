-- Phase 9: Notifications — Step B.
-- Must run after 044a (new enum values need to be committed first).
--
-- Bundles:
--   0. Bugfix found while auditing for this phase: moderation_actions.action
--      check constraint (migration 005) never included the values that
--      issue_warning/add_strike/ban_user/reinstate_user (migration 022)
--      insert. Every warning, strike, ban, or reinstatement has been
--      throwing a check-constraint violation since 022 shipped.
--   1. notifications.metadata — free-form context for the new
--      non-post-linked types (device info, broadcast text, security note).
--   2. Realtime on notifications, same pattern as 008.
--   3. user_known_devices — backs login_alert.
--   4. admin_broadcasts — backs admin_broadcast.
--   5. Triggers: moderation_actions -> moderation_alert,
--      reports resolution -> report_update, moderation_appeals/user_appeals
--      status change -> appeal_update, security_events -> security_alert.
--   6. record_login_device() RPC -> login_alert.
--   7. admin_send_broadcast() RPC -> admin_broadcast fan-out.

begin;

-- 0. Bugfix -----------------------------------------------------------
alter table public.moderation_actions drop constraint if exists moderation_actions_action_check;
alter table public.moderation_actions add constraint moderation_actions_action_check
  check (action in (
    'report_resolved', 'post_soft_removed', 'user_suspended',
    'warning_issued', 'strike_added', 'user_banned', 'user_reinstated'
  ));

-- 1. notifications.metadata --------------------------------------------
alter table public.notifications add column if not exists metadata jsonb not null default '{}'::jsonb;

-- 2. Realtime on notifications -------------------------------------------
alter table public.notifications replica identity full;

do $$
begin
  if not exists (
    select 1 from pg_publication_tables where pubname = 'supabase_realtime' and tablename = 'notifications'
  ) then
    alter publication supabase_realtime add table public.notifications;
  end if;
end $$;

-- 3. Known devices (login alerts) ----------------------------------------
create table if not exists public.user_known_devices (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users(id) on delete cascade,
  device_hash text not null,
  device_label text,
  first_seen_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  unique (user_id, device_hash)
);

create index if not exists idx_user_known_devices_user on public.user_known_devices (user_id);

alter table public.user_known_devices enable row level security;
revoke all on public.user_known_devices from anon, authenticated;

create policy "Users read their own known devices"
  on public.user_known_devices for select
  to authenticated
  using (user_id = auth.uid());

-- Reads only — inserts/updates happen exclusively via record_login_device(),
-- a SECURITY DEFINER function which runs as the table owner and doesn't
-- need a grant to `authenticated`. See migration 041 for why this project
-- grants explicitly instead of relying on defaults.
grant select on public.user_known_devices to authenticated;

-- 4. Admin broadcasts -------------------------------------------------------
create table if not exists public.admin_broadcasts (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  body text not null,
  audience text not null default 'all' check (audience in ('all', 'moderators', 'admins')),
  created_by uuid not null references public.users(id) on delete restrict,
  recipient_count integer not null default 0,
  created_at timestamptz not null default now()
);

create index if not exists idx_admin_broadcasts_created on public.admin_broadcasts (created_at desc);

alter table public.admin_broadcasts enable row level security;
revoke all on public.admin_broadcasts from anon, authenticated;

create policy "Admins and mods can read broadcasts"
  on public.admin_broadcasts for select
  to authenticated
  using (public.is_admin_or_mod());

-- Reads only — inserts happen exclusively via admin_send_broadcast().
grant select on public.admin_broadcasts to authenticated;

-- 5a. Moderation actions -> moderation_alert -------------------------------
create or replace function public.notify_on_moderation_action()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- report_resolved's recipient is the *reporter*, handled by the reports
  -- trigger below (moderation_actions has no reporter column) — skip it
  -- here to avoid a duplicate/misattributed notification.
  if new.action = 'report_resolved' or new.target_user_id is null then
    return new;
  end if;

  insert into public.notifications (recipient_id, actor_id, type, metadata)
  values (
    new.target_user_id,
    new.admin_id,
    'moderation_alert',
    jsonb_build_object('action', new.action, 'note', new.note, 'moderation_action_id', new.id)
  );

  return new;
end;
$$;

drop trigger if exists trg_notify_on_moderation_action on public.moderation_actions;
create trigger trg_notify_on_moderation_action
  after insert on public.moderation_actions
  for each row execute function public.notify_on_moderation_action();

-- 5b. Report resolution -> report_update (to the reporter) ----------------
create or replace function public.notify_on_report_status_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status is distinct from old.status and new.status <> 'open' then
    insert into public.notifications (recipient_id, actor_id, type, metadata)
    values (
      new.reporter_id,
      new.reviewed_by,
      'report_update',
      jsonb_build_object('report_id', new.id, 'status', new.status)
    );
  end if;
  return new;
end;
$$;

drop trigger if exists trg_notify_on_report_status_change on public.reports;
create trigger trg_notify_on_report_status_change
  after update on public.reports
  for each row execute function public.notify_on_report_status_change();

-- 5c. Appeal status changes -> appeal_update -------------------------------
create or replace function public.notify_on_moderation_appeal_status_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status is distinct from old.status and new.status <> 'pending' then
    insert into public.notifications (recipient_id, actor_id, type, metadata)
    values (
      new.user_id,
      new.reviewed_by,
      'appeal_update',
      jsonb_build_object('appeal_id', new.id, 'status', new.status, 'source', 'moderation_appeals')
    );
  end if;
  return new;
end;
$$;

drop trigger if exists trg_notify_on_moderation_appeal_status_change on public.moderation_appeals;
create trigger trg_notify_on_moderation_appeal_status_change
  after update on public.moderation_appeals
  for each row execute function public.notify_on_moderation_appeal_status_change();

create or replace function public.notify_on_user_appeal_status_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status is distinct from old.status and new.status <> 'submitted' then
    insert into public.notifications (recipient_id, actor_id, type, metadata)
    values (
      new.appellant_id,
      new.reviewed_by,
      'appeal_update',
      jsonb_build_object('appeal_id', new.id, 'status', new.status, 'source', 'user_appeals')
    );
  end if;
  return new;
end;
$$;

drop trigger if exists trg_notify_on_user_appeal_status_change on public.user_appeals;
create trigger trg_notify_on_user_appeal_status_change
  after update on public.user_appeals
  for each row execute function public.notify_on_user_appeal_status_change();

-- 5d. Security events -> security_alert (a curated subset, not every event
--     logged via log_security_event — e.g. we don't want to notify on a
--     mere failed-login attempt log, only on completed sensitive changes).
create or replace function public.notify_on_security_event()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.actor_id is null then
    return new;
  end if;

  if new.event_type in ('password_reset_completed', 'password_changed', 'email_changed', 'phone_changed', 'account_recovery') then
    insert into public.notifications (recipient_id, actor_id, type, metadata)
    values (new.actor_id, new.actor_id, 'security_alert', jsonb_build_object('event_type', new.event_type));
  end if;

  return new;
end;
$$;

drop trigger if exists trg_notify_on_security_event on public.security_events;
create trigger trg_notify_on_security_event
  after insert on public.security_events
  for each row execute function public.notify_on_security_event();

-- 6. Login alerts -----------------------------------------------------------
-- The client calls this once per successful sign-in with a stable hash of
-- device/browser identity (not raw fingerprint data). First time a hash is
-- seen for that user, we notify — same "new device" pattern every major app
-- uses. Known devices only ever grow via this path; nothing purges them
-- automatically today (small enough table not to matter yet).
create or replace function public.record_login_device(p_device_hash text, p_device_label text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  is_new boolean;
begin
  if uid is null or p_device_hash is null or length(p_device_hash) = 0 then
    return;
  end if;

  insert into public.user_known_devices (user_id, device_hash, device_label)
  values (uid, p_device_hash, p_device_label)
  on conflict (user_id, device_hash) do update set last_seen_at = now()
  returning (xmax = 0) into is_new;

  if is_new then
    insert into public.notifications (recipient_id, actor_id, type, metadata)
    values (uid, uid, 'login_alert', jsonb_build_object('device_label', coalesce(p_device_label, 'Unknown device')));
  end if;
end;
$$;

grant execute on function public.record_login_device(text, text) to authenticated;

-- 7. Admin broadcast fan-out -------------------------------------------------
create or replace function public.admin_send_broadcast(p_title text, p_body text, p_audience text default 'all')
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  admin_user uuid;
  broadcast_id uuid;
  sent_count integer;
begin
  admin_user := public.ensure_admin_or_mod();

  if p_title is null or length(trim(p_title)) = 0 or p_body is null or length(trim(p_body)) = 0 then
    raise exception 'Broadcast title and body are required';
  end if;
  if p_audience not in ('all', 'moderators', 'admins') then
    raise exception 'Invalid audience';
  end if;

  insert into public.admin_broadcasts (title, body, audience, created_by)
  values (p_title, p_body, p_audience, admin_user)
  returning id into broadcast_id;

  insert into public.notifications (recipient_id, actor_id, type, metadata)
  select u.id, admin_user, 'admin_broadcast', jsonb_build_object('title', p_title, 'body', p_body, 'broadcast_id', broadcast_id)
  from public.users u
  where u.status = 'active'
    and (p_audience = 'all' or u.role = case p_audience when 'moderators' then 'moderator' when 'admins' then 'admin' else u.role end);

  get diagnostics sent_count = row_count;

  update public.admin_broadcasts set recipient_count = sent_count where id = broadcast_id;

  return sent_count;
end;
$$;

grant execute on function public.admin_send_broadcast(text, text, text) to authenticated;

commit;
