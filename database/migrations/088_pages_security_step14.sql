-- 088_pages_security_step14.sql
-- Professional Page System — Step 14 (Security)
--
-- Permission validation, RLS, and page-scoped audit logging were already
-- built in earlier steps (current_user_page_role /
-- current_user_has_page_permission gate every write; page_audit_logs +
-- trg_audit_page_role_change / trg_audit_page_status_change /
-- trg_audit_page_review_change cover the sensitive mutations). This
-- migration closes the gaps found on audit for this step:
--
--   1. Upload validation — page-media storage bucket had a size limit
--      (10MB) but allowed_mime_types was NULL, i.e. any file type could be
--      uploaded to a *public* bucket at a predictable URL. Restricted to
--      an image/video whitelist matching what the app's media picker
--      actually produces.
--   2. Rate limiting / spam protection — mirrors the existing
--      guard_event_rate_limit pattern (trigger-based count + duplicate-
--      content check, no separate rate_limit table) for four write paths
--      that had none: page creation, page posts, page events, and
--      page messages from ordinary users.
--   3. Duplicate reviews — page_reviews had no unique constraint on
--      (page_id, user_id), so a user could submit unlimited reviews for
--      the same page, artificially moving rating_avg. Verified against
--      live data first (no existing duplicates) before adding the
--      constraint.

-- 1. Upload validation --------------------------------------------------------
update storage.buckets
set allowed_mime_types = array[
  'image/jpeg', 'image/png', 'image/webp', 'image/gif',
  'video/mp4', 'video/quicktime', 'video/webm'
]
where id = 'page-media';

-- 2a. Page creation rate limit (prevents a page-creation spam farm) -----------
create or replace function public.guard_page_creation_rate_limit()
returns trigger
language plpgsql
security definer
set search_path = 'public'
as $$
begin
  if (
    select count(*) from public.pages p
    where p.owner_id = new.owner_id
      and p.created_at > now() - interval '24 hours'
  ) >= 5 then
    raise exception 'Too many pages created recently — please wait before creating another' using errcode = 'P0001';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_guard_page_creation_rate_limit on public.pages;
create trigger trg_guard_page_creation_rate_limit
  before insert on public.pages
  for each row execute function public.guard_page_creation_rate_limit();

-- 2b. Page post rate limit + duplicate-content detection ---------------------
create or replace function public.guard_page_post_rate_limit()
returns trigger
language plpgsql
security definer
set search_path = 'public'
as $$
begin
  if (
    select count(*) from public.page_posts pp
    where pp.page_id = new.page_id
      and pp.author_id = new.author_id
      and pp.created_at > now() - interval '1 hour'
  ) >= 20 then
    raise exception 'Too many posts created for this page recently — please wait before posting again' using errcode = 'P0001';
  end if;

  if new.content is not null and length(trim(new.content)) > 0 and exists (
    select 1 from public.page_posts pp
    where pp.page_id = new.page_id
      and pp.author_id = new.author_id
      and pp.content = new.content
      and pp.created_at > now() - interval '10 minutes'
  ) then
    raise exception 'Duplicate post detected — please wait before posting the same content again' using errcode = 'P0001';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_guard_page_post_rate_limit on public.page_posts;
create trigger trg_guard_page_post_rate_limit
  before insert on public.page_posts
  for each row execute function public.guard_page_post_rate_limit();

-- 2c. Page event rate limit + duplicate detection (exact mirror of the
--     existing community guard_event_rate_limit, scoped to page_id) --------
create or replace function public.guard_page_event_rate_limit()
returns trigger
language plpgsql
security definer
set search_path = 'public'
as $$
begin
  if (
    select count(*) from public.page_events e
    where e.created_by = new.created_by
      and e.page_id = new.page_id
      and e.created_at > now() - interval '1 hour'
  ) >= 10 then
    raise exception 'Too many events created for this page recently — please wait before creating another' using errcode = 'P0001';
  end if;

  if exists (
    select 1 from public.page_events e
    where e.created_by = new.created_by
      and e.page_id = new.page_id
      and e.title = new.title
      and e.created_at > now() - interval '10 minutes'
  ) then
    raise exception 'Duplicate event detected — please wait before creating another event with the same title' using errcode = 'P0001';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_guard_page_event_rate_limit on public.page_events;
create trigger trg_guard_page_event_rate_limit
  before insert on public.page_events
  for each row execute function public.guard_page_event_rate_limit();

-- 2d. Page message rate limit — only ordinary users messaging a page;
--     page staff replying is not throttled here. -----------------------------
create or replace function public.guard_page_message_rate_limit()
returns trigger
language plpgsql
security definer
set search_path = 'public'
as $$
begin
  if new.sender_type <> 'user' then
    return new;
  end if;

  if (
    select count(*) from public.page_messages pm
    where pm.page_id = new.page_id
      and pm.user_id = new.user_id
      and pm.sender_type = 'user'
      and pm.created_at > now() - interval '1 hour'
  ) >= 30 then
    raise exception 'Too many messages sent to this page recently — please wait before sending more' using errcode = 'P0001';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_guard_page_message_rate_limit on public.page_messages;
create trigger trg_guard_page_message_rate_limit
  before insert on public.page_messages
  for each row execute function public.guard_page_message_rate_limit();

-- 3. Duplicate reviews — one review per user per page ------------------------
alter table public.page_reviews
  add constraint page_reviews_one_per_user unique (page_id, user_id);
