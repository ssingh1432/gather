-- 068_fix_check_keyword_filters_ambiguity.sql
-- CRITICAL BUG FIX — found while verifying Step 14 notification triggers.
--
-- check_keyword_filters(text) and check_keyword_filters(text, uuid default
-- null) both exist. Calling with a single text argument is ambiguous
-- ("function is not unique"), which currently makes EVERY insert into
-- post_comments, polls, poll_options, and events fail outright, since
-- auto_moderate_comment_block/flag, auto_moderate_poll_block/flag,
-- auto_moderate_poll_option_block/flag, and auto_moderate_event_block/flag
-- all call the 1-arg form. This is not something introduced by Steps
-- 11/13/14 — it's a latent regression from whichever earlier migration
-- added the 2-arg overload without updating these eight callers — but it
-- was only just now caught because event creation happened to be the
-- first insert exercised against it since then. Fixed by making every
-- caller explicit about which overload it means, and — as a real
-- improvement, not just a disambiguation — passing the actual
-- community_id through for comments/polls/poll-options/events so their
-- keyword filtering becomes community-scoped exactly like post creation
-- already is, instead of only ever matching global (community_id IS NULL)
-- filters.

begin;

create or replace function public.auto_moderate_comment_block()
returns trigger
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_community_id uuid;
begin
  select community_id into v_community_id from public.posts where id = new.post_id;
  if exists (
    select 1 from public.check_keyword_filters(coalesce(new.content, ''), v_community_id) k where k.severity = 'block'
  ) then
    raise exception 'This comment was blocked by automated content moderation' using errcode = 'P0001';
  end if;
  return new;
end;
$$;

create or replace function public.auto_moderate_comment_flag()
returns trigger
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  matched record;
  v_community_id uuid;
begin
  select community_id into v_community_id from public.posts where id = new.post_id;
  select k.keyword, k.category into matched
  from public.check_keyword_filters(coalesce(new.content, ''), v_community_id) k
  where k.severity = 'flag'
  limit 1;

  if matched.keyword is not null then
    insert into public.reports(reporter_id, target_type, target_post_id, reason, category, status, is_automated)
    values (new.user_id, 'post', new.post_id, format('Auto-flagged comment %s by keyword filter: "%s"', new.id, matched.keyword), matched.category, 'open', true);
  end if;

  return new;
end;
$$;

create or replace function public.auto_moderate_poll_block()
returns trigger
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_community_id uuid;
begin
  select community_id into v_community_id from public.posts where id = new.post_id;
  if exists (
    select 1 from public.check_keyword_filters(coalesce(new.question, ''), v_community_id) k where k.severity = 'block'
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
set search_path = 'public'
as $$
declare
  matched record;
  v_author_id uuid;
  v_community_id uuid;
begin
  select community_id into v_community_id from public.posts where id = new.post_id;
  select k.keyword, k.category into matched
  from public.check_keyword_filters(coalesce(new.question, ''), v_community_id) k
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

create or replace function public.auto_moderate_poll_option_block()
returns trigger
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_community_id uuid;
begin
  select p.community_id into v_community_id
  from public.polls pl join public.posts p on p.id = pl.post_id
  where pl.id = new.poll_id;

  if exists (
    select 1 from public.check_keyword_filters(coalesce(new.option_text, ''), v_community_id) k where k.severity = 'block'
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
set search_path = 'public'
as $$
declare
  matched record;
  v_post_id uuid;
  v_author_id uuid;
  v_community_id uuid;
begin
  select p.id, p.author_id, p.community_id into v_post_id, v_author_id, v_community_id
  from public.polls pl join public.posts p on p.id = pl.post_id
  where pl.id = new.poll_id;

  select k.keyword, k.category into matched
  from public.check_keyword_filters(coalesce(new.option_text, ''), v_community_id) k
  where k.severity = 'flag'
  limit 1;

  if matched.keyword is not null then
    if v_post_id is not null then
      insert into public.reports(reporter_id, target_type, target_post_id, reason, category, status, is_automated)
      values (v_author_id, 'post', v_post_id, format('Auto-flagged by keyword filter (poll option): "%s"', matched.keyword), matched.category, 'open', true);
    end if;
  end if;

  return new;
end;
$$;

create or replace function public.auto_moderate_event_block()
returns trigger
language plpgsql
security definer
set search_path = 'public'
as $$
begin
  if exists (
    select 1 from public.check_keyword_filters(coalesce(new.title, '') || ' ' || coalesce(new.description, ''), new.community_id) k
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
set search_path = 'public'
as $$
declare
  matched record;
  v_author_id uuid;
begin
  select k.keyword, k.category into matched
  from public.check_keyword_filters(coalesce(new.title, '') || ' ' || coalesce(new.description, ''), new.community_id) k
  where k.severity = 'flag'
  limit 1;

  if matched.keyword is not null then
    -- Events are no longer always attached to a post (migration 061), so
    -- only file the auto-report when there's a post to attach it to —
    -- the reports table's target_post_id is not-null. A community-native
    -- event with a blocked-severity match is already stopped by
    -- auto_moderate_event_block; flag-severity on a post-less event just
    -- has nowhere to attach a report yet.
    if new.post_id is not null then
      select author_id into v_author_id from public.posts where id = new.post_id;
      insert into public.reports(reporter_id, target_type, target_post_id, reason, category, status, is_automated)
      values (coalesce(v_author_id, new.created_by), 'post', new.post_id, format('Auto-flagged by keyword filter (event): "%s"', matched.keyword), matched.category, 'open', true);
    end if;
  end if;

  return new;
end;
$$;

commit;
