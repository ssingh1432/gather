-- Phase 10 Step 19: Notification triggers. Must run after
-- 038a_phase10_notification_types.sql in a separate transaction (Postgres
-- won't let a new enum value be used in the same transaction that added
-- it).

begin;

-- 1. Mentions -----------------------------------------------------------
create or replace function public.create_notifications_on_mention()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  mentioned_id uuid;
begin
  if new.mentioned_user_ids is null or array_length(new.mentioned_user_ids, 1) is null then
    return new;
  end if;

  foreach mentioned_id in array new.mentioned_user_ids
  loop
    if mentioned_id = new.author_id then
      continue; -- don't notify yourself for @mentioning your own username
    end if;
    if exists (
      select 1 from public.user_blocks ub
      where (ub.blocker_id = mentioned_id and ub.blocked_id = new.author_id)
         or (ub.blocker_id = new.author_id and ub.blocked_id = mentioned_id)
    ) then
      continue;
    end if;
    insert into public.notifications (recipient_id, actor_id, post_id, type)
    values (mentioned_id, new.author_id, new.id, 'mention');
  end loop;

  return new;
end;
$$;

drop trigger if exists trg_notify_on_mention on public.posts;
create trigger trg_notify_on_mention
  after insert on public.posts
  for each row execute function public.create_notifications_on_mention();

-- 2. Replies and reposts (post-to-post, distinct from comments which are
--    already covered by create_notification_on_comment in migration 003)
-- ------------------------------------------------------------------------
create or replace function public.create_notification_on_post_reply_or_repost()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  original_author uuid;
  notif_type public.notification_type;
begin
  if new.reply_to_post_id is null then
    return new;
  end if;

  select author_id into original_author
  from public.posts
  where id = new.reply_to_post_id and is_removed = false;

  if original_author is null or original_author = new.author_id then
    return new;
  end if;

  if exists (
    select 1 from public.user_blocks ub
    where (ub.blocker_id = original_author and ub.blocked_id = new.author_id)
       or (ub.blocker_id = new.author_id and ub.blocked_id = original_author)
  ) then
    return new;
  end if;

  notif_type := case when new.content_type = 'repost' then 'post_repost'::public.notification_type else 'post_reply'::public.notification_type end;

  insert into public.notifications (recipient_id, actor_id, post_id, type)
  values (original_author, new.author_id, new.id, notif_type);

  return new;
end;
$$;

drop trigger if exists trg_notify_on_post_reply_or_repost on public.posts;
create trigger trg_notify_on_post_reply_or_repost
  after insert on public.posts
  for each row execute function public.create_notification_on_post_reply_or_repost();

-- 3. Poll participation ---------------------------------------------------
create or replace function public.create_notification_on_poll_vote()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  poll_post_id uuid;
  poll_author uuid;
begin
  select p.post_id, po.author_id into poll_post_id, poll_author
  from public.polls p
  join public.posts po on po.id = p.post_id
  where p.id = new.poll_id;

  if poll_author is null or poll_author = new.user_id then
    return new;
  end if;

  if exists (
    select 1 from public.user_blocks ub
    where (ub.blocker_id = poll_author and ub.blocked_id = new.user_id)
       or (ub.blocker_id = new.user_id and ub.blocked_id = poll_author)
  ) then
    return new;
  end if;

  -- One notification per voter per poll, not per option (a multi-select
  -- poll vote is several poll_votes rows in one action).
  if not exists (
    select 1 from public.notifications
    where type = 'poll_vote' and post_id = poll_post_id and actor_id = new.user_id
      and created_at > now() - interval '1 minute'
  ) then
    insert into public.notifications (recipient_id, actor_id, post_id, type)
    values (poll_author, new.user_id, poll_post_id, 'poll_vote');
  end if;

  return new;
end;
$$;

drop trigger if exists trg_notify_on_poll_vote on public.poll_votes;
create trigger trg_notify_on_poll_vote
  after insert on public.poll_votes
  for each row execute function public.create_notification_on_poll_vote();

-- 4. Event reminders (pg_cron, same pattern as scheduled-post publishing
--    and account-deletion purging) ----------------------------------------
alter table public.event_rsvps add column if not exists reminder_sent_at timestamptz;

create or replace function public.send_event_reminders()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.notifications (recipient_id, actor_id, post_id, type)
  select r.user_id, null, e.post_id, 'event_reminder'
  from public.event_rsvps r
  join public.events e on e.id = r.event_id
  join public.posts p on p.id = e.post_id and p.is_removed = false
  where r.status in ('going', 'interested')
    and r.reminder_sent_at is null
    and e.starts_at between now() and now() + interval '1 hour';

  update public.event_rsvps r
  set reminder_sent_at = now()
  from public.events e
  join public.posts p on p.id = e.post_id and p.is_removed = false
  where r.event_id = e.id
    and r.status in ('going', 'interested')
    and r.reminder_sent_at is null
    and e.starts_at between now() and now() + interval '1 hour';
end;
$$;

revoke all on function public.send_event_reminders() from anon, authenticated;

select cron.schedule(
  'send-event-reminders',
  '*/15 * * * *', -- every 15 minutes; 1-hour lookahead window comfortably covers the gap
  $$select public.send_event_reminders();$$
);

-- 5. Fix stale visibility check on polls/events RLS (predates Step 13's
--    expanded visibility levels — was hardcoded to 'public', which
--    silently hid polls/events on followers/friends/community-visibility
--    posts even from viewers who could see the post itself). Delegating
--    to the posts row's own RLS is simpler and self-correcting for any
--    future visibility changes too.
drop policy if exists polls_read on public.polls;
create policy polls_read on public.polls for select using (
  exists (select 1 from public.posts p where p.id = post_id)
);

drop policy if exists events_read on public.events;
create policy events_read on public.events for select using (
  exists (select 1 from public.posts p where p.id = post_id)
);

commit;
