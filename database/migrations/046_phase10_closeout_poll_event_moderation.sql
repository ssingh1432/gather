-- Phase 10 Closeout — Item 2: Moderation integration for polls & events.
--
-- Audit findings (confirmed against the live schema before writing this):
--   - posts.is_sensitive already applies to every content_type, including
--     poll/event — the composer's "Sensitive content" toggle is on the same
--     screen and the same posts insert regardless of content_type, so no
--     app-side change was needed there. Already correct.
--   - reports.target_post_id is a generic FK to posts.id, so reporting a
--     poll/event post already works end-to-end (correct target_type,
--     evidence, moderator dashboard query) — no schema change needed.
--   - post_media.scan_status (migration 039) is generic across all
--     media_type values, so audio/document uploads already get the same
--     scan-hook column as image/video. No gap.
--   - REAL GAP: auto_moderate_post_block/auto_moderate_post_flag (migration
--     021) only ever inspect posts.text_content. Polls and events store
--     their user-supplied text in polls.question, poll_options.option_text,
--     and events.title/description — none of that is posts.text_content
--     (which is null/empty for these content types) — so keyword-filtered
--     words placed in a poll option or event description were never caught
--     by either the hard block or the auto-flag path. This migration closes
--     that gap by adding equivalent triggers on polls, poll_options, and
--     events, reusing the existing check_keyword_filters() function so the
--     keyword list stays a single source of truth.
--   - Also adds an ai_moderation_status hook column, matching the same
--     "hook point, no scanner wired up yet" pattern already used for
--     post_media.scan_status (migration 039), extended here to cover all
--     content types generically (including poll/event text) rather than
--     duplicating a scan-status column per content table.

begin;

-- --- Future AI-moderation hook (generic, all content types) --------------
alter table public.posts add column if not exists ai_moderation_status text not null default 'not_scanned'
  check (ai_moderation_status in ('not_scanned', 'pending', 'clean', 'flagged'));
comment on column public.posts.ai_moderation_status is
  'Hook point for a future automated content-moderation integration covering all content types (text, poll question/options, event title/description). No scanner is wired up yet; everything defaults not_scanned. Mirrors the pattern used by post_media.scan_status (migration 039).';

-- --- Keyword filtering: polls ---------------------------------------------
create or replace function public.auto_moderate_poll_block()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if exists (
    select 1 from public.check_keyword_filters(coalesce(new.question, '')) k where k.severity = 'block'
  ) then
    raise exception 'This poll was blocked by automated content moderation' using errcode = 'P0001';
  end if;
  return new;
end;
$$;

create or replace function public.auto_moderate_poll_flag()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  matched record;
  v_author_id uuid;
begin
  select k.keyword, k.category into matched
  from public.check_keyword_filters(coalesce(new.question, '')) k
  where k.severity = 'flag'
  limit 1;

  if matched.keyword is not null then
    select author_id into v_author_id from public.posts where id = new.post_id;
    insert into public.reports(reporter_id, target_type, target_post_id, reason, category, status, is_automated)
    values (v_author_id, 'post', new.post_id, format('Auto-flagged by keyword filter (poll question): "%s"', matched.keyword), matched.category, 'open', true);
  end if;

  return new;
end;
$$;

drop trigger if exists trg_auto_moderate_poll_block on public.polls;
create trigger trg_auto_moderate_poll_block
before insert on public.polls
for each row execute function public.auto_moderate_poll_block();

drop trigger if exists trg_auto_moderate_poll_flag on public.polls;
create trigger trg_auto_moderate_poll_flag
after insert on public.polls
for each row execute function public.auto_moderate_poll_flag();

-- --- Keyword filtering: poll options ---------------------------------------
create or replace function public.auto_moderate_poll_option_block()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if exists (
    select 1 from public.check_keyword_filters(coalesce(new.option_text, '')) k where k.severity = 'block'
  ) then
    raise exception 'This poll option was blocked by automated content moderation' using errcode = 'P0001';
  end if;
  return new;
end;
$$;

create or replace function public.auto_moderate_poll_option_flag()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  matched record;
  v_post_id uuid;
  v_author_id uuid;
begin
  select k.keyword, k.category into matched
  from public.check_keyword_filters(coalesce(new.option_text, '')) k
  where k.severity = 'flag'
  limit 1;

  if matched.keyword is not null then
    select p.id, p.author_id into v_post_id, v_author_id
    from public.polls pl join public.posts p on p.id = pl.post_id
    where pl.id = new.poll_id;

    if v_post_id is not null then
      insert into public.reports(reporter_id, target_type, target_post_id, reason, category, status, is_automated)
      values (v_author_id, 'post', v_post_id, format('Auto-flagged by keyword filter (poll option): "%s"', matched.keyword), matched.category, 'open', true);
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_auto_moderate_poll_option_block on public.poll_options;
create trigger trg_auto_moderate_poll_option_block
before insert on public.poll_options
for each row execute function public.auto_moderate_poll_option_block();

drop trigger if exists trg_auto_moderate_poll_option_flag on public.poll_options;
create trigger trg_auto_moderate_poll_option_flag
after insert on public.poll_options
for each row execute function public.auto_moderate_poll_option_flag();

-- --- Keyword filtering: events ---------------------------------------------
create or replace function public.auto_moderate_event_block()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if exists (
    select 1 from public.check_keyword_filters(coalesce(new.title, '') || ' ' || coalesce(new.description, '')) k
    where k.severity = 'block'
  ) then
    raise exception 'This event was blocked by automated content moderation' using errcode = 'P0001';
  end if;
  return new;
end;
$$;

create or replace function public.auto_moderate_event_flag()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  matched record;
  v_author_id uuid;
begin
  select k.keyword, k.category into matched
  from public.check_keyword_filters(coalesce(new.title, '') || ' ' || coalesce(new.description, '')) k
  where k.severity = 'flag'
  limit 1;

  if matched.keyword is not null then
    select author_id into v_author_id from public.posts where id = new.post_id;
    insert into public.reports(reporter_id, target_type, target_post_id, reason, category, status, is_automated)
    values (v_author_id, 'post', new.post_id, format('Auto-flagged by keyword filter (event): "%s"', matched.keyword), matched.category, 'open', true);
  end if;

  return new;
end;
$$;

drop trigger if exists trg_auto_moderate_event_block on public.events;
create trigger trg_auto_moderate_event_block
before insert on public.events
for each row execute function public.auto_moderate_event_block();

drop trigger if exists trg_auto_moderate_event_flag on public.events;
create trigger trg_auto_moderate_event_flag
after insert on public.events
for each row execute function public.auto_moderate_event_flag();

commit;
