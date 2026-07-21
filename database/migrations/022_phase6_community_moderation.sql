-- Phase 6: Community Moderation — Part B
-- Builds on the existing reports/moderation_actions/is_admin_or_mod/ensure_admin_or_mod
-- foundation from earlier phases. Nothing existing is dropped or renamed.

-- =========================================================================
-- 1. TABLES
-- =========================================================================

-- Appeals against a moderation_actions row (warning, suspension, ban, strike).
create table if not exists public.moderation_appeals (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users(id) on delete cascade,
  action_id uuid not null references public.moderation_actions(id) on delete cascade,
  message text not null,
  status text not null default 'pending' check (status in ('pending', 'approved', 'denied')),
  reviewed_by uuid references public.users(id) on delete set null,
  reviewed_at timestamptz,
  resolution_note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_moderation_appeals_user on public.moderation_appeals(user_id, created_at desc);
create index if not exists idx_moderation_appeals_status on public.moderation_appeals(status, created_at desc);

-- Internal-only notes on a user or post, separate from the public-facing report trail.
create table if not exists public.moderator_notes (
  id uuid primary key default gen_random_uuid(),
  moderator_id uuid not null references public.users(id) on delete cascade,
  target_type text not null check (target_type in ('user', 'post')),
  target_user_id uuid references public.users(id) on delete cascade,
  target_post_id uuid references public.posts(id) on delete cascade,
  note text not null,
  created_at timestamptz not null default now(),
  constraint moderator_notes_target_check check (
    (target_type = 'user' and target_user_id is not null and target_post_id is null) or
    (target_type = 'post' and target_post_id is not null and target_user_id is null)
  )
);

create index if not exists idx_moderator_notes_user on public.moderator_notes(target_user_id, created_at desc);
create index if not exists idx_moderator_notes_post on public.moderator_notes(target_post_id, created_at desc);

-- Evidence attachments (screenshots, links, exported content) tied to a report.
create table if not exists public.moderation_evidence (
  id uuid primary key default gen_random_uuid(),
  report_id uuid not null references public.reports(id) on delete cascade,
  uploaded_by uuid not null references public.users(id) on delete cascade,
  file_url text not null,
  file_type text,
  description text,
  created_at timestamptz not null default now()
);

create index if not exists idx_moderation_evidence_report on public.moderation_evidence(report_id, created_at desc);

-- Keyword-based auto-moderation rules.
create table if not exists public.keyword_filters (
  id uuid primary key default gen_random_uuid(),
  keyword text not null,
  category public.report_category not null default 'other',
  severity text not null default 'flag' check (severity in ('flag', 'block')),
  is_active boolean not null default true,
  created_by uuid references public.users(id) on delete set null,
  created_at timestamptz not null default now(),
  unique (keyword)
);

-- Image/video moderation hook queue. Populated automatically whenever new
-- media is attached to a post; a moderator (or a future Edge Function wired
-- to a vision/video-moderation API) reviews and updates `status`.
create table if not exists public.media_moderation_flags (
  id uuid primary key default gen_random_uuid(),
  post_media_id uuid references public.post_media(id) on delete cascade,
  media_url text not null,
  media_type text not null,
  status text not null default 'pending' check (status in ('pending', 'approved', 'flagged')),
  provider text,
  raw_result jsonb,
  reviewed_by uuid references public.users(id) on delete set null,
  reviewed_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists idx_media_moderation_flags_status on public.media_moderation_flags(status, created_at desc);

-- =========================================================================
-- 2. RLS
-- =========================================================================

alter table public.moderation_appeals enable row level security;
alter table public.moderator_notes enable row level security;
alter table public.moderation_evidence enable row level security;
alter table public.keyword_filters enable row level security;
alter table public.media_moderation_flags enable row level security;

drop policy if exists moderation_appeals_select on public.moderation_appeals;
create policy moderation_appeals_select on public.moderation_appeals
for select using (user_id = auth.uid() or public.is_admin_or_mod());

drop policy if exists moderation_appeals_insert_self on public.moderation_appeals;
create policy moderation_appeals_insert_self on public.moderation_appeals
for insert with check (
  user_id = auth.uid()
  and exists (
    select 1 from public.moderation_actions a
    where a.id = action_id and a.target_user_id = auth.uid()
  )
);

drop policy if exists moderation_appeals_update_mod on public.moderation_appeals;
create policy moderation_appeals_update_mod on public.moderation_appeals
for update using (public.is_admin_or_mod());

drop policy if exists moderator_notes_all_mod on public.moderator_notes;
create policy moderator_notes_all_mod on public.moderator_notes
for all using (public.is_admin_or_mod()) with check (public.is_admin_or_mod());

drop policy if exists moderation_evidence_select_mod on public.moderation_evidence;
create policy moderation_evidence_select_mod on public.moderation_evidence
for select using (
  public.is_admin_or_mod()
  or uploaded_by = auth.uid()
);

drop policy if exists moderation_evidence_insert on public.moderation_evidence;
create policy moderation_evidence_insert on public.moderation_evidence
for insert with check (
  uploaded_by = auth.uid()
  and (
    public.is_admin_or_mod()
    or exists (select 1 from public.reports r where r.id = report_id and r.reporter_id = auth.uid())
  )
);

drop policy if exists keyword_filters_all_mod on public.keyword_filters;
create policy keyword_filters_all_mod on public.keyword_filters
for all using (public.is_admin_or_mod()) with check (public.is_admin_or_mod());

drop policy if exists media_moderation_flags_select_mod on public.media_moderation_flags;
create policy media_moderation_flags_select_mod on public.media_moderation_flags
for select using (public.is_admin_or_mod());

drop policy if exists media_moderation_flags_update_mod on public.media_moderation_flags;
create policy media_moderation_flags_update_mod on public.media_moderation_flags
for update using (public.is_admin_or_mod());

-- =========================================================================
-- 3. CORE MODERATION RPCS (warnings, strikes, suspension, ban, reinstate)
-- =========================================================================

create or replace function public.issue_warning(target_user_id uuid, report_id uuid default null, note text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  admin_user uuid;
begin
  admin_user := public.ensure_admin_or_mod();

  insert into public.moderation_actions(action, admin_id, report_id, target_user_id, note)
  values ('warning_issued', admin_user, report_id, target_user_id, note);
end;
$$;

grant execute on function public.issue_warning(uuid, uuid, text) to authenticated;

-- Adds a strike and auto-escalates: 3 strikes -> 3-day suspension,
-- 5 strikes -> 14-day suspension, 7+ strikes -> permanent ban.
-- Thresholds live here so they can be tuned without touching client code.
create or replace function public.add_strike(target_user_id uuid, report_id uuid default null, note text default null, severity integer default 1)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  admin_user uuid;
  new_count integer;
begin
  admin_user := public.ensure_admin_or_mod();

  update public.users
  set strike_count = strike_count + greatest(severity, 1)
  where id = target_user_id
  returning strike_count into new_count;

  if new_count is null then
    raise exception 'Target user not found' using errcode = 'P0002';
  end if;

  insert into public.moderation_actions(action, admin_id, report_id, target_user_id, note)
  values ('strike_added', admin_user, report_id, target_user_id, coalesce(note, '') || format(' (strike #%s)', new_count));

  if new_count >= 7 then
    perform public.ban_user(target_user_id, report_id, 'Auto-escalated: 7+ strikes');
  elsif new_count >= 5 then
    perform public.suspend_user(target_user_id, report_id, 'Auto-escalated: 5+ strikes', 14);
  elsif new_count >= 3 then
    perform public.suspend_user(target_user_id, report_id, 'Auto-escalated: 3+ strikes', 3);
  end if;
end;
$$;

grant execute on function public.add_strike(uuid, uuid, text, integer) to authenticated;

-- Extends the existing suspend_user() with an optional duration. Existing
-- call sites (suspend_user(target_user_id, report_id, note)) keep working
-- unchanged since duration_days is a new, defaulted trailing parameter.
create or replace function public.suspend_user(target_user_id uuid, report_id uuid default null, note text default null, duration_days integer default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  admin_user uuid;
  until timestamptz;
begin
  admin_user := public.ensure_admin_or_mod();
  until := case when duration_days is null then null else now() + make_interval(days => duration_days) end;

  update public.users
  set status = 'suspended', suspended_until = until
  where id = target_user_id;

  insert into public.moderation_actions(action, admin_id, report_id, target_user_id, note)
  values (
    'user_suspended',
    admin_user,
    report_id,
    target_user_id,
    coalesce(note, '') || case when duration_days is null then ' (indefinite)' else format(' (%s days)', duration_days) end
  );
end;
$$;

grant execute on function public.suspend_user(uuid, uuid, text, integer) to authenticated;

create or replace function public.ban_user(target_user_id uuid, report_id uuid default null, note text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  admin_user uuid;
begin
  admin_user := public.ensure_admin_or_mod();

  update public.users
  set status = 'banned', suspended_until = null
  where id = target_user_id;

  insert into public.moderation_actions(action, admin_id, report_id, target_user_id, note)
  values ('user_banned', admin_user, report_id, target_user_id, note);
end;
$$;

grant execute on function public.ban_user(uuid, uuid, text) to authenticated;

-- Reinstates a suspended or banned user (does not clear strike history).
create or replace function public.reinstate_user(target_user_id uuid, note text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  admin_user uuid;
begin
  admin_user := public.ensure_admin_or_mod();

  update public.users
  set status = 'active', suspended_until = null
  where id = target_user_id;

  insert into public.moderation_actions(action, admin_id, target_user_id, note)
  values ('user_reinstated', admin_user, target_user_id, note);
end;
$$;

grant execute on function public.reinstate_user(uuid, text) to authenticated;

-- Lifts suspensions whose duration has passed. Safe to call repeatedly/on a
-- schedule — mirrors the pattern used by the deletion purge job (019).
create or replace function public.lift_expired_suspensions()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  lifted integer;
begin
  update public.users
  set status = 'active', suspended_until = null
  where status = 'suspended'
    and suspended_until is not null
    and suspended_until <= now();
  get diagnostics lifted = row_count;
  return lifted;
end;
$$;

grant execute on function public.lift_expired_suspensions() to service_role;

-- =========================================================================
-- 4. APPEALS
-- =========================================================================

create or replace function public.submit_appeal(action_id uuid, message text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  new_id uuid;
  owner uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select target_user_id into owner from public.moderation_actions where id = action_id;
  if owner is distinct from auth.uid() then
    raise exception 'Cannot appeal an action against another user' using errcode = '42501';
  end if;

  insert into public.moderation_appeals(user_id, action_id, message)
  values (auth.uid(), action_id, message)
  returning id into new_id;

  return new_id;
end;
$$;

grant execute on function public.submit_appeal(uuid, text) to authenticated;

create or replace function public.review_appeal(appeal_id uuid, decision text, resolution_note text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  admin_user uuid;
  target uuid;
  action_row public.moderation_actions%rowtype;
begin
  admin_user := public.ensure_admin_or_mod();

  if decision not in ('approved', 'denied') then
    raise exception 'decision must be approved or denied' using errcode = '22023';
  end if;

  select ma.* into action_row
  from public.moderation_appeals a
  join public.moderation_actions ma on ma.id = a.action_id
  where a.id = appeal_id;

  target := action_row.target_user_id;

  update public.moderation_appeals
  set status = decision, reviewed_by = admin_user, reviewed_at = now(), resolution_note = resolution_note, updated_at = now()
  where id = appeal_id;

  if decision = 'approved' and action_row.action in ('user_suspended', 'user_banned') then
    perform public.reinstate_user(target, 'Appeal approved: ' || coalesce(resolution_note, ''));
  end if;
end;
$$;

grant execute on function public.review_appeal(uuid, text, text) to authenticated;

-- =========================================================================
-- 5. MODERATOR NOTES & EVIDENCE
-- =========================================================================

create or replace function public.add_moderator_note(target_type text, target_id uuid, note text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  admin_user uuid;
  new_id uuid;
begin
  admin_user := public.ensure_admin_or_mod();

  if target_type not in ('user', 'post') then
    raise exception 'target_type must be user or post' using errcode = '22023';
  end if;

  insert into public.moderator_notes(moderator_id, target_type, target_user_id, target_post_id, note)
  values (
    admin_user,
    target_type,
    case when target_type = 'user' then target_id else null end,
    case when target_type = 'post' then target_id else null end,
    note
  )
  returning id into new_id;

  return new_id;
end;
$$;

grant execute on function public.add_moderator_note(text, uuid, text) to authenticated;

create or replace function public.add_evidence(report_id uuid, file_url text, file_type text default null, description text default null)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  new_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if not public.is_admin_or_mod() and not exists (
    select 1 from public.reports r where r.id = report_id and r.reporter_id = auth.uid()
  ) then
    raise exception 'Cannot attach evidence to this report' using errcode = '42501';
  end if;

  insert into public.moderation_evidence(report_id, uploaded_by, file_url, file_type, description)
  values (report_id, auth.uid(), file_url, file_type, description)
  returning id into new_id;

  return new_id;
end;
$$;

grant execute on function public.add_evidence(uuid, text, text, text) to authenticated;

-- =========================================================================
-- 6. KEYWORD AUTO-MODERATION
-- =========================================================================

create or replace function public.check_keyword_filters(content text)
returns table(keyword text, severity text, category public.report_category)
language sql
stable
security definer
set search_path = public
as $$
  select kf.keyword, kf.severity, kf.category
  from public.keyword_filters kf
  where kf.is_active
    and content ilike '%' || kf.keyword || '%'
  order by kf.severity desc
  limit 5;
$$;

grant execute on function public.check_keyword_filters(text) to authenticated;

create or replace function public.add_keyword_filter(keyword text, category public.report_category default 'other', severity text default 'flag')
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  admin_user uuid;
  new_id uuid;
begin
  admin_user := public.ensure_admin_or_mod();

  if severity not in ('flag', 'block') then
    raise exception 'severity must be flag or block' using errcode = '22023';
  end if;

  insert into public.keyword_filters(keyword, category, severity, created_by)
  values (lower(trim(keyword)), category, severity, admin_user)
  on conflict (keyword) do update set category = excluded.category, severity = excluded.severity, is_active = true
  returning id into new_id;

  return new_id;
end;
$$;

grant execute on function public.add_keyword_filter(text, public.report_category, text) to authenticated;

create or replace function public.remove_keyword_filter(filter_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.ensure_admin_or_mod();
  update public.keyword_filters set is_active = false where id = filter_id;
end;
$$;

grant execute on function public.remove_keyword_filter(uuid) to authenticated;

-- Blocks post creation outright when content matches a 'block' severity rule.
create or replace function public.auto_moderate_post_block()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if exists (
    select 1 from public.check_keyword_filters(coalesce(new.text_content, '')) k where k.severity = 'block'
  ) then
    raise exception 'This post was blocked by automated content moderation' using errcode = 'P0001';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_auto_moderate_post_block on public.posts;
create trigger trg_auto_moderate_post_block
before insert on public.posts
for each row execute function public.auto_moderate_post_block();

-- Files an automated report for a 'flag' severity match, for moderator review.
create or replace function public.auto_moderate_post_flag()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  matched record;
begin
  select k.keyword, k.category into matched
  from public.check_keyword_filters(coalesce(new.text_content, '')) k
  where k.severity = 'flag'
  limit 1;

  if matched.keyword is not null then
    insert into public.reports(reporter_id, target_type, target_post_id, reason, category, status, is_automated)
    values (new.author_id, 'post', new.id, format('Auto-flagged by keyword filter: "%s"', matched.keyword), matched.category, 'open', true);
  end if;

  return new;
end;
$$;

drop trigger if exists trg_auto_moderate_post_flag on public.posts;
create trigger trg_auto_moderate_post_flag
after insert on public.posts
for each row execute function public.auto_moderate_post_flag();

-- Same pattern for comments. Comments aren't a valid report target_type on
-- their own, so a flagged comment is reported against its parent post with
-- the comment id noted in the reason text.
create or replace function public.auto_moderate_comment_block()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if exists (
    select 1 from public.check_keyword_filters(coalesce(new.content, '')) k where k.severity = 'block'
  ) then
    raise exception 'This comment was blocked by automated content moderation' using errcode = 'P0001';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_auto_moderate_comment_block on public.post_comments;
create trigger trg_auto_moderate_comment_block
before insert on public.post_comments
for each row execute function public.auto_moderate_comment_block();

create or replace function public.auto_moderate_comment_flag()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  matched record;
begin
  select k.keyword, k.category into matched
  from public.check_keyword_filters(coalesce(new.content, '')) k
  where k.severity = 'flag'
  limit 1;

  if matched.keyword is not null then
    insert into public.reports(reporter_id, target_type, target_post_id, reason, category, status, is_automated)
    values (new.user_id, 'post', new.post_id, format('Auto-flagged comment %s by keyword filter: "%s"', new.id, matched.keyword), matched.category, 'open', true);
  end if;

  return new;
end;
$$;

drop trigger if exists trg_auto_moderate_comment_flag on public.post_comments;
create trigger trg_auto_moderate_comment_flag
after insert on public.post_comments
for each row execute function public.auto_moderate_comment_flag();

-- Automated reports bypass the "can't report yourself" / rate-limit checks
-- in guard_report_create (they're system-generated, attributed to the
-- content author only to satisfy the NOT NULL reporter_id column).
create or replace function public.guard_report_create()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  target_author uuid;
begin
  if new.is_automated then
    return new;
  end if;

  if new.reporter_id <> auth.uid() then
    raise exception 'Cannot report for another user' using errcode = '42501';
  end if;

  if not public.current_user_is_active() then
    raise exception 'Account is not allowed to report' using errcode = '42501';
  end if;

  if (
    select count(*)
    from public.reports r
    where r.reporter_id = new.reporter_id
      and r.created_at > now() - interval '1 day'
  ) >= 20 then
    raise exception 'Report rate limit exceeded' using errcode = 'P0001';
  end if;

  if new.target_type = 'post' then
    select p.author_id into target_author
    from public.posts p
    where p.id = new.target_post_id
      and p.is_removed = false;
  else
    target_author := new.target_user_id;
  end if;

  if target_author is null then
    raise exception 'Report target does not exist' using errcode = 'P0001';
  end if;

  if public.users_are_blocked(new.reporter_id, target_author) then
    raise exception 'Cannot report this target' using errcode = '42501';
  end if;

  return new;
end;
$$;

-- =========================================================================
-- 7. MEDIA MODERATION HOOKS (image/video)
-- =========================================================================

-- Queues every new post media item for moderation review. A moderator can
-- review the queue directly, or an Edge Function calling an external
-- image/video moderation API can call record_media_moderation_result()
-- once wired up (left as an integration point — no external API key is
-- configured here).
create or replace function public.queue_media_moderation()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.media_moderation_flags(post_media_id, media_url, media_type)
  values (new.id, new.media_url, new.media_type::text);
  return new;
end;
$$;

drop trigger if exists trg_queue_media_moderation on public.post_media;
create trigger trg_queue_media_moderation
after insert on public.post_media
for each row execute function public.queue_media_moderation();

create or replace function public.record_media_moderation_result(flag_id uuid, new_status text, provider text default null, raw_result jsonb default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin_or_mod() then
    raise exception 'Admin or moderator required' using errcode = '42501';
  end if;

  if new_status not in ('pending', 'approved', 'flagged') then
    raise exception 'new_status must be pending, approved or flagged' using errcode = '22023';
  end if;

  update public.media_moderation_flags
  set status = new_status, provider = coalesce(provider, media_moderation_flags.provider),
      raw_result = coalesce(raw_result, media_moderation_flags.raw_result),
      reviewed_by = auth.uid(), reviewed_at = now()
  where id = flag_id;
end;
$$;

grant execute on function public.record_media_moderation_result(uuid, text, text, jsonb) to authenticated;

-- =========================================================================
-- 8. READ HELPERS for the moderator dashboard
-- =========================================================================

create or replace function public.moderation_dashboard_summary()
returns table(open_reports bigint, pending_appeals bigint, flagged_media bigint, suspended_users bigint, banned_users bigint)
language sql
stable
security definer
set search_path = public
as $$
  select
    (select count(*) from public.reports where status = 'open'),
    (select count(*) from public.moderation_appeals where status = 'pending'),
    (select count(*) from public.media_moderation_flags where status = 'flagged'),
    (select count(*) from public.users where status = 'suspended'),
    (select count(*) from public.users where status = 'banned');
$$;

grant execute on function public.moderation_dashboard_summary() to authenticated;
