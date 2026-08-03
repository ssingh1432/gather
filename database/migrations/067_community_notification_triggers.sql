-- 067_community_notification_triggers.sql
-- Step 14: Community Notifications — trigger functions.
--
-- Fan-out notifications (announcements, new events) insert one row per
-- recipient via a single set-based INSERT ... SELECT, not a per-row loop —
-- cheap even for a few thousand members. None of these check a per-user
-- notification-preferences table because no such table exists yet in this
-- codebase (Phase 9 shipped realtime delivery + the FCM dispatch pipeline,
-- but not granular per-type toggles) — every other existing notification
-- trigger (likes, comments, follows, etc.) has the same characteristic, so
-- this is consistent with current behavior, not a new gap.

begin;

-- ---------------------------------------------------------------------------
-- 1. Join request submitted -> notify everyone who can manage members.
-- ---------------------------------------------------------------------------
create or replace function public.notify_on_community_join_request()
returns trigger
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_community_name text;
  v_requester_username text;
begin
  select name into v_community_name from public.communities where id = new.community_id;
  select username into v_requester_username from public.users where id = new.user_id;

  insert into public.notifications (recipient_id, actor_id, type, metadata)
  select m.user_id, new.user_id, 'community_join_request',
    jsonb_build_object('community_id', new.community_id, 'community_name', v_community_name, 'request_id', new.id, 'requester_username', v_requester_username)
  from public.community_memberships m
  where m.community_id = new.community_id
    and m.user_id != new.user_id
    and public.community_role_can(new.community_id, m.role, 'manage_members');

  return new;
end;
$$;

drop trigger if exists trg_notify_community_join_request on public.community_join_requests;
create trigger trg_notify_community_join_request
  after insert on public.community_join_requests
  for each row execute function public.notify_on_community_join_request();

-- ---------------------------------------------------------------------------
-- 2. Join request decided -> notify the requester.
-- ---------------------------------------------------------------------------
create or replace function public.notify_on_community_join_decision()
returns trigger
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_community_name text;
begin
  if old.status = 'pending' and new.status != 'pending' then
    select name into v_community_name from public.communities where id = new.community_id;
    insert into public.notifications (recipient_id, actor_id, type, metadata)
    values (new.user_id, new.decided_by, 'community_join_update',
      jsonb_build_object('community_id', new.community_id, 'community_name', v_community_name, 'status', new.status));
  end if;
  return new;
end;
$$;

drop trigger if exists trg_notify_community_join_decision on public.community_join_requests;
create trigger trg_notify_community_join_decision
  after update on public.community_join_requests
  for each row execute function public.notify_on_community_join_decision();

-- ---------------------------------------------------------------------------
-- 3. Direct invite created -> notify the invited user (reuses the
--    pre-existing community_invite enum value, which had no trigger yet).
-- ---------------------------------------------------------------------------
create or replace function public.notify_on_community_invite()
returns trigger
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_community_name text;
begin
  if new.invited_user_id is not null then
    select name into v_community_name from public.communities where id = new.community_id;
    insert into public.notifications (recipient_id, actor_id, type, metadata)
    values (new.invited_user_id, new.created_by, 'community_invite',
      jsonb_build_object('community_id', new.community_id, 'community_name', v_community_name, 'invite_id', new.id));
  end if;
  return new;
end;
$$;

drop trigger if exists trg_notify_community_invite on public.community_invites;
create trigger trg_notify_community_invite
  after insert on public.community_invites
  for each row execute function public.notify_on_community_invite();

-- ---------------------------------------------------------------------------
-- 4. Role changed -> notify the member.
-- ---------------------------------------------------------------------------
create or replace function public.notify_on_community_role_changed()
returns trigger
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_community_name text;
begin
  if old.role is distinct from new.role then
    select name into v_community_name from public.communities where id = new.community_id;
    insert into public.notifications (recipient_id, actor_id, type, metadata)
    values (new.user_id, null, 'community_role_changed',
      jsonb_build_object('community_id', new.community_id, 'community_name', v_community_name, 'old_role', old.role, 'new_role', new.role));
  end if;
  return new;
end;
$$;

drop trigger if exists trg_notify_community_role_changed on public.community_memberships;
create trigger trg_notify_community_role_changed
  after update on public.community_memberships
  for each row execute function public.notify_on_community_role_changed();

-- ---------------------------------------------------------------------------
-- 5. Warning issued -> notify the warned member.
-- ---------------------------------------------------------------------------
create or replace function public.notify_on_community_warning()
returns trigger
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_community_name text;
begin
  select name into v_community_name from public.communities where id = new.community_id;
  insert into public.notifications (recipient_id, actor_id, type, metadata)
  values (new.user_id, new.warned_by, 'community_warning',
    jsonb_build_object('community_id', new.community_id, 'community_name', v_community_name, 'reason', new.reason, 'warning_id', new.id));
  return new;
end;
$$;

drop trigger if exists trg_notify_community_warning on public.community_warnings;
create trigger trg_notify_community_warning
  after insert on public.community_warnings
  for each row execute function public.notify_on_community_warning();

-- ---------------------------------------------------------------------------
-- 6. Ban issued -> notify the banned member.
-- ---------------------------------------------------------------------------
create or replace function public.notify_on_community_ban()
returns trigger
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_community_name text;
begin
  select name into v_community_name from public.communities where id = new.community_id;
  insert into public.notifications (recipient_id, actor_id, type, metadata)
  values (new.user_id, new.banned_by, 'community_ban',
    jsonb_build_object('community_id', new.community_id, 'community_name', v_community_name, 'reason', new.reason, 'expires_at', new.expires_at));
  return new;
end;
$$;

drop trigger if exists trg_notify_community_ban on public.community_bans;
create trigger trg_notify_community_ban
  after insert on public.community_bans
  for each row execute function public.notify_on_community_ban();

-- ---------------------------------------------------------------------------
-- 7. Announcement -> notify every member (except the one who made it).
--    Two source events: pinning a post as the community's announcement,
--    and posting an is_announcement chat message.
-- ---------------------------------------------------------------------------
create or replace function public.notify_on_community_announcement_pinned()
returns trigger
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_actor uuid;
  v_preview text;
begin
  if new.pinned_announcement_post_id is not distinct from old.pinned_announcement_post_id then
    return new;
  end if;
  if new.pinned_announcement_post_id is null then
    return new;
  end if;

  select author_id, left(coalesce(text_content, ''), 140) into v_actor, v_preview
  from public.posts where id = new.pinned_announcement_post_id;

  insert into public.notifications (recipient_id, actor_id, type, metadata)
  select m.user_id, v_actor, 'community_announcement',
    jsonb_build_object('community_id', new.id, 'community_name', new.name, 'post_id', new.pinned_announcement_post_id, 'preview', v_preview)
  from public.community_memberships m
  where m.community_id = new.id and m.user_id != v_actor;

  return new;
end;
$$;

drop trigger if exists trg_notify_community_announcement_pinned on public.communities;
create trigger trg_notify_community_announcement_pinned
  after update on public.communities
  for each row execute function public.notify_on_community_announcement_pinned();

create or replace function public.notify_on_community_announcement_chat()
returns trigger
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_community_name text;
begin
  if new.is_announcement is not true then
    return new;
  end if;
  select name into v_community_name from public.communities where id = new.community_id;

  insert into public.notifications (recipient_id, actor_id, type, metadata)
  select m.user_id, new.sender_id, 'community_announcement',
    jsonb_build_object('community_id', new.community_id, 'community_name', v_community_name, 'chat_message_id', new.id, 'preview', left(coalesce(new.content, ''), 140))
  from public.community_memberships m
  where m.community_id = new.community_id and m.user_id != new.sender_id;

  return new;
end;
$$;

drop trigger if exists trg_notify_community_announcement_chat on public.community_chat_messages;
create trigger trg_notify_community_announcement_chat
  after insert on public.community_chat_messages
  for each row execute function public.notify_on_community_announcement_chat();

-- ---------------------------------------------------------------------------
-- 8. New community event created -> notify every member (except creator).
--    Distinct from event_reminder (Step 11), which fires closer to the
--    event's start time for people who RSVP'd — this fires once, at
--    creation, to everyone in the community.
-- ---------------------------------------------------------------------------
create or replace function public.notify_on_community_event_created()
returns trigger
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_community_name text;
begin
  if new.community_id is null then
    return new;
  end if;
  select name into v_community_name from public.communities where id = new.community_id;

  insert into public.notifications (recipient_id, actor_id, type, metadata)
  select m.user_id, new.created_by, 'community_event_created',
    jsonb_build_object('community_id', new.community_id, 'community_name', v_community_name, 'event_id', new.id, 'title', new.title, 'starts_at', new.starts_at)
  from public.community_memberships m
  where m.community_id = new.community_id and m.user_id != new.created_by;

  return new;
end;
$$;

drop trigger if exists trg_notify_community_event_created on public.events;
create trigger trg_notify_community_event_created
  after insert on public.events
  for each row execute function public.notify_on_community_event_created();

commit;
