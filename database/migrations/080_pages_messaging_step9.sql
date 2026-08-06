-- 080_pages_messaging_step9.sql
-- Professional Page System — Step 9 (Messaging).
--
-- `page_messages` (the customer-chat/inbox table itself) already shipped in
-- 074_pages_ops.sql with full RLS, but had zero Flutter UI and none of the
-- brief's automation features. This migration adds:
--   1. `sent_by` on page_messages — which team member sent a page-side
--      reply (null = automated). Purely additive/nullable.
--   2. Quick Replies — `page_quick_replies`, a saved-template table.
--   3. Auto Replies + Away Messages + Business Hours Responses — new
--      columns on `pages` (auto_reply_*, away_message_*,
--      business_hours_schedule) plus `page_is_open_now()` and a trigger
--      that fires the right automated first-reply, and notifies both
--      sides (page team on inbound, user on the page's reply).
--   4. Inbox RPCs for the team: list_page_message_threads,
--      mark_page_thread_read.
--
-- Depends on: 072, 074, 079_pages_messaging_step9_enum.sql.
-- Fully additive — no existing table/column/policy is altered destructively.

-- 1. sent_by --------------------------------------------------------------------
alter table public.page_messages add column if not exists sent_by uuid references public.users(id) on delete set null;
comment on column public.page_messages.sent_by is
  'Which team member sent this page-side (sender_type = ''page'') message. Null means it was sent automatically (auto-reply/away message).';

-- 2. Quick Replies ----------------------------------------------------------------
create table if not exists public.page_quick_replies (
  id uuid primary key default gen_random_uuid(),
  page_id uuid not null references public.pages(id) on delete cascade,
  title text not null,
  content text not null,
  sort_order integer not null default 0,
  created_by uuid not null references public.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

create index if not exists idx_page_quick_replies_page on public.page_quick_replies (page_id, sort_order);

alter table public.page_quick_replies enable row level security;

drop policy if exists page_quick_replies_select on public.page_quick_replies;
create policy page_quick_replies_select on public.page_quick_replies
  for select using (
    public.current_user_page_role(page_id) = 'owner'
    or public.current_user_has_page_permission(page_id, 'manage_messages')
  );

drop policy if exists page_quick_replies_insert on public.page_quick_replies;
create policy page_quick_replies_insert on public.page_quick_replies
  for insert with check (
    created_by = auth.uid()
    and (
      public.current_user_page_role(page_id) = 'owner'
      or public.current_user_has_page_permission(page_id, 'manage_messages')
    )
  );

drop policy if exists page_quick_replies_update on public.page_quick_replies;
create policy page_quick_replies_update on public.page_quick_replies
  for update using (
    public.current_user_page_role(page_id) = 'owner'
    or public.current_user_has_page_permission(page_id, 'manage_messages')
  );

drop policy if exists page_quick_replies_delete on public.page_quick_replies;
create policy page_quick_replies_delete on public.page_quick_replies
  for delete using (
    public.current_user_page_role(page_id) = 'owner'
    or public.current_user_has_page_permission(page_id, 'manage_messages')
  );

grant select, insert, update, delete on public.page_quick_replies to authenticated;

-- 3. Auto Replies / Away Messages / Business Hours Responses ---------------------
-- These live on `pages` itself (small, single-row settings, same shape as
-- the existing business_hours/social_links jsonb columns from 072) rather
-- than a separate settings table. Gated by the existing pages_update RLS
-- policy (owner or manage_settings) — deliberately *not* manage_messages,
-- since these are page-wide configuration, not day-to-day inbox work.
alter table public.pages add column if not exists auto_reply_enabled boolean not null default false;
alter table public.pages add column if not exists auto_reply_message text;
alter table public.pages add column if not exists away_message_enabled boolean not null default false;
alter table public.pages add column if not exists away_message text;
-- Weekly schedule, independent of the freeform `business_hours` note added
-- in 072 (e.g. business_hours = {"note": "..."}). Shape:
--   {"mon": {"open": "09:00", "close": "18:00"}, "tue": null, ...}
-- A missing/null day, or an empty schedule altogether, means "no hours
-- configured for that day" — page_is_open_now() treats an entirely empty
-- schedule as always-open (so away messages never fire until a schedule is
-- actually set), and a specific closed day as closed.
alter table public.pages add column if not exists business_hours_schedule jsonb not null default '{}'::jsonb;

comment on column public.pages.business_hours_schedule is
  'Structured weekly hours used by page_is_open_now()/away-message automation. Distinct from the freeform business_hours.note shown on the profile.';

-- Evaluated in Asia/Kathmandu local time — Gather is a Nepal-focused
-- platform (see project brief), so this intentionally doesn't attempt a
-- per-page timezone. Fails open (returns true = "open") on any parsing
-- error so malformed schedule data can never block messaging outright.
create or replace function public.page_is_open_now(p_page_id uuid)
returns boolean
language plpgsql
stable
set search_path = 'public'
as $$
declare
  v_schedule jsonb;
  v_local timestamp;
  v_dow text;
  v_day jsonb;
  v_time time;
begin
  select business_hours_schedule into v_schedule from public.pages where id = p_page_id;

  if v_schedule is null or v_schedule = '{}'::jsonb then
    return true;
  end if;

  v_local := now() at time zone 'Asia/Kathmandu';
  v_dow := lower(to_char(v_local, 'Dy'));
  v_day := v_schedule -> v_dow;

  if v_day is null or v_day = 'null'::jsonb then
    return false;
  end if;

  v_time := v_local::time;
  return v_time >= (v_day ->> 'open')::time and v_time <= (v_day ->> 'close')::time;
exception when others then
  return true;
end;
$$;

grant execute on function public.page_is_open_now(uuid) to authenticated;

-- Fires on every page_messages insert:
--   * sender_type = 'user'  -> notifies the page team, and — only on the
--     very first message of a new thread — inserts one automated reply
--     (away message if currently closed and configured, else auto-reply
--     if enabled). "First message of a thread" is a lifetime check (not
--     time-windowed), i.e. a v1 simplification: a thread only ever gets
--     one automated reply, not one per re-engagement.
--   * sender_type = 'page'  -> notifies the user (their recipient side),
--     whether the reply was a human team member (sent_by set) or one of
--     the automated replies just described (sent_by null).
create or replace function public.handle_page_message_automation()
returns trigger
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_page public.pages%rowtype;
  v_is_first boolean;
  v_open boolean;
  v_reply_content text;
begin
  if new.sender_type = 'user' then
    select * into v_page from public.pages where id = new.page_id;

    insert into public.notifications (recipient_id, actor_id, type, metadata)
    select recipient, new.user_id, 'page_message_received',
      jsonb_build_object('page_id', new.page_id, 'page_name', v_page.name)
    from (
      select v_page.owner_id as recipient
      union
      select pr.user_id
      from public.page_roles pr
      join public.page_role_permissions rp on rp.role = pr.role and rp.permission_key = 'manage_messages' and rp.allowed
      where pr.page_id = new.page_id
    ) recips
    where recipient is not null;

    select not exists (
      select 1 from public.page_messages
      where page_id = new.page_id and user_id = new.user_id and id <> new.id
    ) into v_is_first;

    if v_is_first then
      v_open := public.page_is_open_now(new.page_id);
      v_reply_content := null;

      if not v_open and v_page.away_message_enabled and v_page.away_message is not null then
        v_reply_content := v_page.away_message;
      elsif v_page.auto_reply_enabled and v_page.auto_reply_message is not null then
        v_reply_content := v_page.auto_reply_message;
      end if;

      if v_reply_content is not null then
        insert into public.page_messages (page_id, user_id, sender_type, content, sent_by)
        values (new.page_id, new.user_id, 'page', v_reply_content, null);
      end if;
    end if;

  elsif new.sender_type = 'page' then
    insert into public.notifications (recipient_id, actor_id, type, metadata)
    values (
      new.user_id,
      new.sent_by,
      'page_message_reply',
      jsonb_build_object('page_id', new.page_id, 'page_name', (select name from public.pages where id = new.page_id))
    );
  end if;

  return new;
end;
$$;

drop trigger if exists trg_handle_page_message_automation on public.page_messages;
create trigger trg_handle_page_message_automation
  after insert on public.page_messages
  for each row execute function public.handle_page_message_automation();

-- 4. Inbox RPCs (team-facing) -----------------------------------------------------
create or replace function public.list_page_message_threads(p_page_id uuid)
returns table(
  user_id uuid,
  username text,
  display_name text,
  profile_photo_url text,
  last_message text,
  last_message_at timestamptz,
  last_sender_type text,
  unread_count bigint
)
language plpgsql
security definer
set search_path = 'public'
as $$
begin
  if not (
    public.current_user_page_role(p_page_id) = 'owner'
    or public.current_user_has_page_permission(p_page_id, 'manage_messages')
  ) then
    raise exception 'Not authorized to view this page''s inbox.';
  end if;

  return query
  select
    u.id,
    u.username,
    u.display_name,
    u.profile_photo_url,
    last_msg.content,
    last_msg.created_at,
    last_msg.sender_type,
    (
      select count(*) from public.page_messages pm2
      where pm2.page_id = p_page_id and pm2.user_id = u.id and pm2.sender_type = 'user' and pm2.read_at is null
    )::bigint
  from (
    select distinct on (user_id) user_id, content, created_at, sender_type
    from public.page_messages
    where page_id = p_page_id
    order by user_id, created_at desc
  ) last_msg
  join public.users u on u.id = last_msg.user_id
  order by last_msg.created_at desc;
end;
$$;

grant execute on function public.list_page_message_threads(uuid) to authenticated;

create or replace function public.mark_page_thread_read(p_page_id uuid, p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = 'public'
as $$
begin
  if not (
    public.current_user_page_role(p_page_id) = 'owner'
    or public.current_user_has_page_permission(p_page_id, 'manage_messages')
  ) then
    raise exception 'Not authorized.';
  end if;

  update public.page_messages
  set read_at = now()
  where page_id = p_page_id and user_id = p_user_id and sender_type = 'user' and read_at is null;
end;
$$;

grant execute on function public.mark_page_thread_read(uuid, uuid) to authenticated;
