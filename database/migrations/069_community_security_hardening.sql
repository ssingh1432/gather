-- 069_community_security_hardening.sql
-- Step 15: Security — Permission validation, rate limiting, spam
-- detection, input validation, RLS enforcement, audit logs, applied to
-- the community system built in Steps 11-14.
--
-- Found during this audit (not previously flagged):
--
-- 1. IDENTITY-SPOOFING GAP: events_write's RLS WITH CHECK allows any
--    manage_events holder to INSERT a row with `created_by` set to any
--    arbitrary user id (unlike posts, where author_id = auth.uid() is
--    strictly required with no OR-bypass). A moderator could misattribute
--    event creation to another member. Compounding this, the Flutter
--    client (createCommunityEvent) never actually sets created_by at all,
--    so every event created since Step 11 shipped has created_by = NULL —
--    meaning ownership, the events_write "creator" bypass, and the
--    community_event_created notification's actor_id have all been wrong
--    since launch. Fixed with a BEFORE INSERT trigger that force-sets
--    created_by = auth.uid() unconditionally, ignoring whatever the
--    client sent — the same "never trust the client for identity fields"
--    principle already used correctly for posts.author_id.
--
-- 2. NO LENGTH LIMITS: events.title/description/location_text/online_url,
--    community_chat_messages.content, community_join_requests.message,
--    and the event_occurrences per-occurrence override fields had no
--    CHECK constraints — a client could insert megabyte-scale text,
--    which posts.text_content also lacks (pre-existing, out of this
--    migration's scope) but is worth closing for the new tables now.
--
-- 3. NO RATE LIMITING on event creation or chat announcements, both of
--    which fan out a notification to every community member — a
--    malicious manage_events/manage_chat holder could spam the entire
--    membership. Added duplicate/frequency guards mirroring the existing
--    guard_duplicate_post_content pattern.
--
-- 4. NO AUDIT TRAIL for event create/cancel, unlike role changes, bans,
--    and warnings which all log to community_audit_logs. Added.
--
-- 5. Minor Step 14 correctness gap found in passing: re-submitting a
--    join request (UPDATE status back to 'pending' after a rejection)
--    never re-notified managers, since the trigger only covered INSERT.

begin;

-- ---------------------------------------------------------------------------
-- 1. Force events.created_by server-side; never trust the client.
-- ---------------------------------------------------------------------------
create or replace function public.force_event_created_by()
returns trigger
language plpgsql
security definer
set search_path = 'public'
as $$
begin
  new.created_by := auth.uid();
  return new;
end;
$$;

drop trigger if exists trg_force_event_created_by on public.events;
create trigger trg_force_event_created_by
  before insert on public.events
  for each row execute function public.force_event_created_by();

update public.events e
set created_by = p.author_id
from public.posts p
where e.post_id = p.id and e.created_by is null;

-- ---------------------------------------------------------------------------
-- 2. Length constraints (input validation).
-- ---------------------------------------------------------------------------
alter table public.events
  drop constraint if exists events_title_len_chk,
  drop constraint if exists events_description_len_chk,
  drop constraint if exists events_location_text_len_chk,
  drop constraint if exists events_online_url_len_chk;
alter table public.events
  add constraint events_title_len_chk check (char_length(title) <= 200),
  add constraint events_description_len_chk check (description is null or char_length(description) <= 5000),
  add constraint events_location_text_len_chk check (location_text is null or char_length(location_text) <= 300),
  add constraint events_online_url_len_chk check (online_url is null or char_length(online_url) <= 500);

alter table public.event_occurrences
  drop constraint if exists event_occurrences_title_override_len_chk,
  drop constraint if exists event_occurrences_description_override_len_chk,
  drop constraint if exists event_occurrences_location_override_len_chk,
  drop constraint if exists event_occurrences_cancelled_reason_len_chk;
alter table public.event_occurrences
  add constraint event_occurrences_title_override_len_chk check (title_override is null or char_length(title_override) <= 200),
  add constraint event_occurrences_description_override_len_chk check (description_override is null or char_length(description_override) <= 5000),
  add constraint event_occurrences_location_override_len_chk check (location_override is null or char_length(location_override) <= 300),
  add constraint event_occurrences_cancelled_reason_len_chk check (cancelled_reason is null or char_length(cancelled_reason) <= 500);

alter table public.community_chat_messages
  drop constraint if exists community_chat_messages_content_len_chk;
alter table public.community_chat_messages
  add constraint community_chat_messages_content_len_chk check (char_length(content) <= 4000);

alter table public.community_join_requests
  drop constraint if exists community_join_requests_message_len_chk;
alter table public.community_join_requests
  add constraint community_join_requests_message_len_chk check (message is null or char_length(message) <= 1000);

-- ---------------------------------------------------------------------------
-- 3. Rate limiting / spam detection.
-- ---------------------------------------------------------------------------

create or replace function public.guard_event_rate_limit()
returns trigger
language plpgsql
security definer
set search_path = 'public'
as $$
begin
  if new.community_id is null then
    return new;
  end if;

  if (
    select count(*) from public.events e
    where e.created_by = new.created_by
      and e.community_id = new.community_id
      and e.created_at > now() - interval '1 hour'
  ) >= 10 then
    raise exception 'Too many events created in this community recently — please wait before creating another' using errcode = 'P0001';
  end if;

  if exists (
    select 1 from public.events e
    where e.created_by = new.created_by
      and e.community_id = new.community_id
      and e.title = new.title
      and e.created_at > now() - interval '10 minutes'
  ) then
    raise exception 'Duplicate event detected — please wait before creating another event with the same title' using errcode = 'P0001';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_guard_event_rate_limit on public.events;
create trigger trg_guard_event_rate_limit
  before insert on public.events
  for each row execute function public.guard_event_rate_limit();

create or replace function public.guard_announcement_rate_limit()
returns trigger
language plpgsql
security definer
set search_path = 'public'
as $$
begin
  if new.is_announcement is not true then
    return new;
  end if;

  if exists (
    select 1 from public.community_chat_messages m
    where m.sender_id = new.sender_id
      and m.community_id = new.community_id
      and m.is_announcement = true
      and m.created_at > now() - interval '5 minutes'
  ) then
    raise exception 'Please wait a few minutes before posting another announcement' using errcode = 'P0001';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_guard_announcement_rate_limit on public.community_chat_messages;
create trigger trg_guard_announcement_rate_limit
  before insert on public.community_chat_messages
  for each row execute function public.guard_announcement_rate_limit();

-- ---------------------------------------------------------------------------
-- 3b. community_audit_logs.action has an allow-list CHECK constraint that
--    doesn't yet include the new event actions used in #4 below — found by
--    the verification insert failing, not by static review. Extend it.
-- ---------------------------------------------------------------------------
alter table public.community_audit_logs
  drop constraint if exists community_audit_logs_action_check;
alter table public.community_audit_logs
  add constraint community_audit_logs_action_check check (action = any (array[
    'role_changed', 'member_removed', 'member_banned', 'member_unbanned', 'member_warned',
    'permission_overridden', 'settings_changed', 'member_invited', 'invite_link_created',
    'invite_revoked', 'invite_accepted', 'report_resolved', 'report_dismissed', 'post_removed',
    'event_created', 'event_cancelled'
  ]));

-- ---------------------------------------------------------------------------
-- 4. Audit trail for event lifecycle (parity with role changes/bans/warnings).
-- ---------------------------------------------------------------------------
create or replace function public.audit_log_event_created()
returns trigger
language plpgsql
security definer
set search_path = 'public'
as $$
begin
  if new.community_id is not null then
    insert into public.community_audit_logs (community_id, actor_id, action, metadata)
    values (new.community_id, new.created_by, 'event_created', jsonb_build_object('event_id', new.id, 'title', new.title, 'starts_at', new.starts_at));
  end if;
  return new;
end;
$$;

drop trigger if exists trg_audit_log_event_created on public.events;
create trigger trg_audit_log_event_created
  after insert on public.events
  for each row execute function public.audit_log_event_created();

create or replace function public.audit_log_event_cancelled()
returns trigger
language plpgsql
security definer
set search_path = 'public'
as $$
begin
  if old.status is distinct from new.status and new.status = 'cancelled' and new.community_id is not null then
    insert into public.community_audit_logs (community_id, actor_id, action, metadata)
    values (new.community_id, auth.uid(), 'event_cancelled', jsonb_build_object('event_id', new.id, 'title', new.title));
  end if;
  return new;
end;
$$;

drop trigger if exists trg_audit_log_event_cancelled on public.events;
create trigger trg_audit_log_event_cancelled
  after update on public.events
  for each row execute function public.audit_log_event_cancelled();

-- ---------------------------------------------------------------------------
-- 5. Re-notify managers when a rejected join request is resubmitted.
-- ---------------------------------------------------------------------------
create or replace function public.notify_on_community_join_resubmitted()
returns trigger
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_community_name text;
  v_requester_username text;
begin
  if old.status != 'pending' and new.status = 'pending' then
    select name into v_community_name from public.communities where id = new.community_id;
    select username into v_requester_username from public.users where id = new.user_id;

    insert into public.notifications (recipient_id, actor_id, type, metadata)
    select m.user_id, new.user_id, 'community_join_request',
      jsonb_build_object('community_id', new.community_id, 'community_name', v_community_name, 'request_id', new.id, 'requester_username', v_requester_username)
    from public.community_memberships m
    where m.community_id = new.community_id
      and m.user_id != new.user_id
      and public.community_role_can(new.community_id, m.role, 'manage_members');
  end if;
  return new;
end;
$$;

drop trigger if exists trg_notify_community_join_resubmitted on public.community_join_requests;
create trigger trg_notify_community_join_resubmitted
  after update on public.community_join_requests
  for each row execute function public.notify_on_community_join_resubmitted();

commit;
