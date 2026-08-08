-- 087_pages_notifications_step13.sql
-- Professional Page System — Step 13 (Notifications), part 2 of 2.
--
-- Covers the four gaps still open after auditing existing triggers
-- (page_new_follower, page_new_post, page_follow_invite,
-- page_message_received/reply, page_review_received/response were already
-- wired in earlier steps):
--   1. Mentions on page posts (page_posts had no mention_ids column at all).
--   2. Scheduled page posts — real bug found: page_posts has a working
--      'scheduled' status + scheduled_at column and a
--      trg_notify_page_followers_new_post trigger ready to fire on the
--      scheduled->published transition, but NOTHING was actually flipping
--      that status when scheduled_at arrived. No cron job existed for it
--      (confirmed against cron.job — only publish-scheduled-posts for the
--      unrelated community `scheduled_posts` staging table, and
--      send-event-reminders existed). Scheduled page posts have been
--      silently stuck forever until now.
--   3. Page events — no "new event" notification to followers, and no
--      reminder before start (page_events has no RSVP table yet, so the
--      reminder goes to followers with notify=true, same audience as new
--      posts, deduped via a new reminder_sent_at column).
--   4. Page verification status changes — no notification to the owner.

-- 1. Mentions --------------------------------------------------------------
alter table public.page_posts add column if not exists mention_ids uuid[];

create or replace function public.notify_page_post_mentions()
returns trigger
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  mentioned_id uuid;
  v_page_name text;
begin
  if new.status <> 'published' or new.mention_ids is null or array_length(new.mention_ids, 1) is null then
    return new;
  end if;
  if tg_op = 'UPDATE' and old.status = 'published' then
    return new;
  end if;

  select name into v_page_name from public.pages where id = new.page_id;

  foreach mentioned_id in array new.mention_ids
  loop
    if mentioned_id = new.author_id then
      continue;
    end if;
    if exists (
      select 1 from public.user_blocks ub
      where (ub.blocker_id = mentioned_id and ub.blocked_id = new.author_id)
         or (ub.blocker_id = new.author_id and ub.blocked_id = mentioned_id)
    ) then
      continue;
    end if;
    insert into public.notifications (recipient_id, actor_id, type, metadata)
    values (
      mentioned_id, new.author_id, 'mention',
      jsonb_build_object('page_id', new.page_id, 'page_name', v_page_name, 'page_post_id', new.id)
    );
  end loop;

  return new;
end;
$$;

drop trigger if exists trg_notify_page_post_mentions on public.page_posts;
create trigger trg_notify_page_post_mentions
  after insert or update on public.page_posts
  for each row execute function public.notify_page_post_mentions();

-- 2. Scheduled page posts — auto-publish cron (the actual missing piece) ---
create or replace function public.publish_scheduled_page_posts()
returns void
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  r record;
  v_page_name text;
begin
  for r in
    select * from public.page_posts
    where status = 'scheduled' and scheduled_at <= now() and deleted_at is null
    order by scheduled_at asc
    limit 200
  loop
    update public.page_posts
    set status = 'published', published_at = now()
    where id = r.id;

    select name into v_page_name from public.pages where id = r.page_id;
    if r.author_id is not null then
      insert into public.notifications (recipient_id, actor_id, type, metadata)
      values (
        r.author_id, r.author_id, 'scheduled_post_published',
        jsonb_build_object('page_id', r.page_id, 'page_name', v_page_name, 'page_post_id', r.id)
      );
    end if;
  end loop;
end;
$$;

revoke all on function public.publish_scheduled_page_posts() from public, authenticated, anon;

select cron.schedule(
  'publish-scheduled-page-posts',
  '* * * * *', -- every minute
  $$select public.publish_scheduled_page_posts();$$
);

-- 3. Page events — new-event notification + reminder ------------------------
alter table public.page_events add column if not exists reminder_sent_at timestamptz;

create or replace function public.notify_page_followers_new_event()
returns trigger
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_page_name text;
begin
  select name into v_page_name from public.pages where id = new.page_id;

  insert into public.notifications (recipient_id, actor_id, type, metadata)
  select pf.user_id, new.created_by, 'page_new_event',
    jsonb_build_object('page_id', new.page_id, 'page_name', v_page_name, 'event_id', new.id, 'title', new.title, 'start_time', new.start_time)
  from public.page_followers pf
  where pf.page_id = new.page_id
    and pf.notify = true
    and pf.user_id <> coalesce(new.created_by, '00000000-0000-0000-0000-000000000000'::uuid);

  return new;
end;
$$;

drop trigger if exists trg_notify_page_followers_new_event on public.page_events;
create trigger trg_notify_page_followers_new_event
  after insert on public.page_events
  for each row execute function public.notify_page_followers_new_event();

create or replace function public.send_page_event_reminders()
returns void
language plpgsql
security definer
set search_path = 'public'
as $$
begin
  insert into public.notifications (recipient_id, actor_id, type, metadata)
  select pf.user_id, null, 'page_event_reminder',
    jsonb_build_object('page_id', e.page_id, 'page_name', p.name, 'event_id', e.id, 'title', e.title, 'start_time', e.start_time)
  from public.page_events e
  join public.pages p on p.id = e.page_id
  join public.page_followers pf on pf.page_id = e.page_id and pf.notify = true
  where e.deleted_at is null
    and e.reminder_sent_at is null
    and e.start_time between now() and now() + interval '1 hour';

  update public.page_events e
  set reminder_sent_at = now()
  where e.deleted_at is null
    and e.reminder_sent_at is null
    and e.start_time between now() and now() + interval '1 hour';
end;
$$;

revoke all on function public.send_page_event_reminders() from public, authenticated, anon;

select cron.schedule(
  'send-page-event-reminders',
  '*/15 * * * *',
  $$select public.send_page_event_reminders();$$
);

-- 4. Verification status changes ---------------------------------------------
create or replace function public.notify_page_verification_change()
returns trigger
language plpgsql
security definer
set search_path = 'public'
as $$
begin
  if new.verification_status is distinct from old.verification_status then
    insert into public.notifications (recipient_id, actor_id, type, metadata)
    values (
      new.owner_id, null, 'page_verification_updated',
      jsonb_build_object('page_id', new.id, 'page_name', new.name, 'verification_status', new.verification_status)
    );
  end if;
  return new;
end;
$$;

drop trigger if exists trg_notify_page_verification_change on public.pages;
create trigger trg_notify_page_verification_change
  after update on public.pages
  for each row execute function public.notify_page_verification_change();
