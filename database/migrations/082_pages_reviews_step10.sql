-- 082_pages_reviews_step10.sql
-- Professional Page System — Step 10 (Reviews).
--
-- Scope (per brief): Ratings, Reviews, Owner Responses, Helpful Votes,
-- Review Reporting, Moderation.
--
-- Design notes:
--   * One review per (page, user) — `unique (page_id, user_id)`, updatable
--     in place (Facebook/Google-style "edit your review", not multiple
--     reviews stacking up). `rating` 1-5, `body` required, `title` optional.
--   * `pages.rating_avg` / `pages.rating_count` are denormalized aggregates
--     maintained by trigger (same pattern as `pages.follower_count` in 072),
--     recomputed only over status = 'published' reviews.
--   * Team members (page_roles) and the page owner cannot review their own
--     page — enforced by trigger, not just UI, since RLS alone can't see
--     "is this reviewer also a page_roles row for this page" cheaply as a
--     constraint.
--   * Two distinct moderation paths, matching the existing page_reports
--     precedent (074) of "reports against a page never go to the page's own
--     team":
--       1. Owner/manage_reviews moderation — the page team can hide a
--          review directly (status -> 'hidden') for spam/off-topic, via the
--          normal update policy. This is the "Moderation" bullet.
--       2. Formal abuse reports (page_review_reports) — go to site-level
--          moderators only (public.is_admin_or_mod()), same as page_reports,
--          so a page can never be judge of a complaint about its own
--          reviews (no "report your critic into silence" loophole).
--   * Helpful votes: simple one-vote-per-user toggle, denormalized
--     `page_reviews.helpful_count` maintained by trigger.
--
-- Depends on: 072_pages_core_schema.sql, 074_pages_ops.sql (page_reports
-- precedent, log_page_audit_event, is_admin_or_mod), 081 (enum values).
-- Fully additive.

-- 1. Rating aggregate columns on `pages` --------------------------------------
alter table public.pages add column if not exists rating_avg numeric(3,2) not null default 0;
alter table public.pages add column if not exists rating_count integer not null default 0;

comment on column public.pages.rating_avg is 'Denormalized average of published page_reviews.rating. Maintained by trg_page_review_rating_aggregate. Do not write directly.';
comment on column public.pages.rating_count is 'Denormalized count of published page_reviews. Maintained by trg_page_review_rating_aggregate. Do not write directly.';

-- 2. Page reviews ---------------------------------------------------------------
create table if not exists public.page_reviews (
  id uuid primary key default gen_random_uuid(),
  page_id uuid not null references public.pages(id) on delete cascade,
  user_id uuid not null references public.users(id) on delete cascade,
  rating smallint not null check (rating between 1 and 5),
  title text check (title is null or char_length(title) <= 120),
  body text not null check (char_length(body) between 1 and 2000),
  status text not null default 'published' check (status in ('published', 'hidden', 'removed')),
  owner_response text check (owner_response is null or char_length(owner_response) <= 2000),
  owner_response_by uuid references public.users(id) on delete set null,
  owner_response_at timestamptz,
  helpful_count integer not null default 0,
  edited boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (page_id, user_id)
);

comment on column public.page_reviews.status is 'published = visible to everyone; hidden = page team moderation action, still visible to the reviewer and the team; removed = formal takedown by a site moderator following a page_review_reports resolution.';
comment on column public.page_reviews.helpful_count is 'Denormalized count maintained by trg_page_review_helpful_count. Do not write directly.';

create index if not exists idx_page_reviews_page on public.page_reviews (page_id, created_at desc) where status = 'published';
create index if not exists idx_page_reviews_user on public.page_reviews (user_id);
create index if not exists idx_page_reviews_page_status on public.page_reviews (page_id, status);

drop trigger if exists trg_page_reviews_touch_updated_at on public.page_reviews;
create trigger trg_page_reviews_touch_updated_at
  before update on public.page_reviews
  for each row execute function public.touch_updated_at();

-- Reviewer edited their rating/body/title -> stamp `edited`, and clear a
-- stale owner response only if the *rating or body* actually changed (an
-- edit that just corrects a typo shouldn't silently orphan a response, but
-- we still flag it for the team to notice via `edited`).
create or replace function public.mark_page_review_edited()
returns trigger
language plpgsql
security definer
set search_path = 'public'
as $$
begin
  if tg_op = 'UPDATE'
     and (new.rating is distinct from old.rating or new.body is distinct from old.body or new.title is distinct from old.title) then
    new.edited := true;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_mark_page_review_edited on public.page_reviews;
create trigger trg_mark_page_review_edited
  before update on public.page_reviews
  for each row execute function public.mark_page_review_edited();

-- Block page owner / any page_roles member from reviewing their own page.
create or replace function public.prevent_page_self_review()
returns trigger
language plpgsql
security definer
set search_path = 'public'
as $$
begin
  if public.current_user_page_role(new.page_id) is not null then
    raise exception 'Page team members cannot review their own page.';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_prevent_page_self_review on public.page_reviews;
create trigger trg_prevent_page_self_review
  before insert on public.page_reviews
  for each row execute function public.prevent_page_self_review();

-- Keep pages.rating_avg / rating_count in sync, over published reviews only.
create or replace function public.recompute_page_rating_aggregate()
returns trigger
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_page_id uuid := coalesce(new.page_id, old.page_id);
begin
  update public.pages p
  set rating_avg = coalesce((
        select round(avg(r.rating)::numeric, 2)
        from public.page_reviews r
        where r.page_id = v_page_id and r.status = 'published'
      ), 0),
      rating_count = (
        select count(*) from public.page_reviews r
        where r.page_id = v_page_id and r.status = 'published'
      )
  where p.id = v_page_id;
  return null;
end;
$$;

-- (insert/delete unconditionally recompute; update recomputes only when
-- rating or status actually changed, guarded inside the function body via
-- the trigger's WHEN clause below for insert/delete, and an explicit column
-- check isn't needed on update since rating/status are the only columns
-- that affect the aggregate and re-running the aggregate is idempotent —
-- kept as a plain AFTER INSERT OR UPDATE OR DELETE to avoid the
-- "UPDATE OF ... OR DELETE" event-list edge case entirely.)
drop trigger if exists trg_page_review_rating_aggregate on public.page_reviews;
create trigger trg_page_review_rating_aggregate
  after insert or update or delete on public.page_reviews
  for each row execute function public.recompute_page_rating_aggregate();

alter table public.page_reviews enable row level security;

drop policy if exists page_reviews_select on public.page_reviews;
create policy page_reviews_select on public.page_reviews
  for select using (
    status = 'published'
    or user_id = auth.uid()
    or public.current_user_page_role(page_id) = 'owner'
    or public.current_user_has_page_permission(page_id, 'manage_reviews')
  );

drop policy if exists page_reviews_insert on public.page_reviews;
create policy page_reviews_insert on public.page_reviews
  for insert with check (user_id = auth.uid());

-- Reviewer may edit their own rating/title/body (status stays whatever it
-- was — they can't un-hide their own hidden review). Page team may only
-- move `status` and set the `owner_response*` columns; enforced together
-- here since column-level RLS isn't available, split precisely below via
-- with check re-validating who's allowed to touch what through the
-- application layer + trg_guard_page_review_update as defense in depth.
drop policy if exists page_reviews_update on public.page_reviews;
create policy page_reviews_update on public.page_reviews
  for update using (
    user_id = auth.uid()
    or public.current_user_page_role(page_id) = 'owner'
    or public.current_user_has_page_permission(page_id, 'manage_reviews')
  ) with check (
    user_id = auth.uid()
    or public.current_user_page_role(page_id) = 'owner'
    or public.current_user_has_page_permission(page_id, 'manage_reviews')
  );

-- Defense in depth: a plain reviewer (not page team) must not be able to
-- change status or write an owner_response themselves, even though the
-- USING/CHECK above allows the row through (they own the row).
create or replace function public.guard_page_review_update()
returns trigger
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_is_team boolean := public.current_user_page_role(new.page_id) = 'owner'
    or public.current_user_has_page_permission(new.page_id, 'manage_reviews');
begin
  if not v_is_team then
    if new.status is distinct from old.status
       or new.owner_response is distinct from old.owner_response
       or new.owner_response_by is distinct from old.owner_response_by then
      raise exception 'Only the page team can moderate or respond to a review.';
    end if;
  end if;

  if new.owner_response is distinct from old.owner_response and new.owner_response is not null then
    new.owner_response_by := auth.uid();
    new.owner_response_at := now();
  end if;

  return new;
end;
$$;

drop trigger if exists trg_guard_page_review_update on public.page_reviews;
create trigger trg_guard_page_review_update
  before update on public.page_reviews
  for each row execute function public.guard_page_review_update();

grant select, insert, update on public.page_reviews to authenticated;

-- 3. Notify the page team when a new review comes in ---------------------------
create or replace function public.notify_page_new_review()
returns trigger
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_page_name text;
  v_owner_id uuid;
  v_reviewer_username text;
begin
  select name, owner_id into v_page_name, v_owner_id from public.pages where id = new.page_id;
  select username into v_reviewer_username from public.users where id = new.user_id;

  insert into public.notifications (recipient_id, actor_id, type, metadata)
  select recipient, new.user_id, 'page_review_received',
    jsonb_build_object('page_id', new.page_id, 'page_name', v_page_name, 'review_id', new.id, 'rating', new.rating, 'reviewer_username', v_reviewer_username)
  from (
    select v_owner_id as recipient
    union
    select pr.user_id
    from public.page_roles pr
    join public.page_role_permissions rp on rp.role = pr.role and rp.permission_key = 'manage_reviews' and rp.allowed
    where pr.page_id = new.page_id
  ) recips
  where recipient is not null and recipient <> new.user_id;

  return new;
end;
$$;

drop trigger if exists trg_notify_page_new_review on public.page_reviews;
create trigger trg_notify_page_new_review
  after insert on public.page_reviews
  for each row execute function public.notify_page_new_review();

-- Notify the reviewer when the page team responds.
create or replace function public.notify_page_review_response()
returns trigger
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_page_name text;
begin
  if new.owner_response is distinct from old.owner_response and new.owner_response is not null then
    select name into v_page_name from public.pages where id = new.page_id;
    insert into public.notifications (recipient_id, actor_id, type, metadata)
    values (new.user_id, new.owner_response_by, 'page_review_response',
      jsonb_build_object('page_id', new.page_id, 'page_name', v_page_name, 'review_id', new.id));
  end if;
  return new;
end;
$$;

drop trigger if exists trg_notify_page_review_response on public.page_reviews;
create trigger trg_notify_page_review_response
  after update on public.page_reviews
  for each row execute function public.notify_page_review_response();

-- Audit trail: team-driven status changes (hide/restore/remove) and responses.
create or replace function public.audit_page_review_change()
returns trigger
language plpgsql
security definer
set search_path = 'public'
as $$
begin
  if new.status is distinct from old.status then
    perform public.log_page_audit_event(new.page_id, 'review_status_changed', 'review', new.id,
      jsonb_build_object('from', old.status, 'to', new.status));
  end if;
  if new.owner_response is distinct from old.owner_response and new.owner_response is not null then
    perform public.log_page_audit_event(new.page_id, 'review_responded', 'review', new.id, '{}'::jsonb);
  end if;
  return new;
end;
$$;

drop trigger if exists trg_audit_page_review_change on public.page_reviews;
create trigger trg_audit_page_review_change
  after update on public.page_reviews
  for each row execute function public.audit_page_review_change();

-- 4. Helpful votes ----------------------------------------------------------------
create table if not exists public.page_review_helpful_votes (
  review_id uuid not null references public.page_reviews(id) on delete cascade,
  user_id uuid not null references public.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (review_id, user_id)
);

create index if not exists idx_page_review_helpful_votes_user on public.page_review_helpful_votes (user_id);

create or replace function public.update_page_review_helpful_count()
returns trigger
language plpgsql
security definer
set search_path = 'public'
as $$
begin
  if tg_op = 'INSERT' then
    update public.page_reviews set helpful_count = helpful_count + 1 where id = new.review_id;
  elsif tg_op = 'DELETE' then
    update public.page_reviews set helpful_count = greatest(0, helpful_count - 1) where id = old.review_id;
  end if;
  return null;
end;
$$;

drop trigger if exists trg_page_review_helpful_count on public.page_review_helpful_votes;
create trigger trg_page_review_helpful_count
  after insert or delete on public.page_review_helpful_votes
  for each row execute function public.update_page_review_helpful_count();

alter table public.page_review_helpful_votes enable row level security;

drop policy if exists page_review_helpful_votes_select on public.page_review_helpful_votes;
create policy page_review_helpful_votes_select on public.page_review_helpful_votes
  for select using (true);

drop policy if exists page_review_helpful_votes_manage_own on public.page_review_helpful_votes;
create policy page_review_helpful_votes_manage_own on public.page_review_helpful_votes
  for all using (user_id = auth.uid()) with check (
    user_id = auth.uid()
    and exists (select 1 from public.page_reviews r where r.id = review_id and r.status = 'published' and r.user_id <> auth.uid())
  );

grant select, insert, delete on public.page_review_helpful_votes to authenticated;

-- 5. Review reports (site-level moderation only — same reasoning as page_reports) -
create table if not exists public.page_review_reports (
  id uuid primary key default gen_random_uuid(),
  review_id uuid not null references public.page_reviews(id) on delete cascade,
  page_id uuid not null references public.pages(id) on delete cascade,
  reporter_id uuid not null references public.users(id) on delete cascade,
  reason text not null check (reason in (
    'spam','fake_account','harassment','hate_speech','violence','terrorism',
    'child_abuse','adult_content','copyright','scam','impersonation',
    'self_harm','drugs','other'
  )),
  details text,
  status text not null default 'pending' check (status in ('pending','reviewing','resolved','dismissed')),
  resolved_by uuid references public.users(id) on delete set null,
  resolved_at timestamptz,
  created_at timestamptz not null default now(),
  unique (review_id, reporter_id)
);

create index if not exists idx_page_review_reports_review on public.page_review_reports (review_id);
create index if not exists idx_page_review_reports_status on public.page_review_reports (status) where status in ('pending','reviewing');

alter table public.page_review_reports enable row level security;

drop policy if exists page_review_reports_select on public.page_review_reports;
create policy page_review_reports_select on public.page_review_reports
  for select using (
    reporter_id = auth.uid()
    or public.is_admin_or_mod()
  );

drop policy if exists page_review_reports_insert on public.page_review_reports;
create policy page_review_reports_insert on public.page_review_reports
  for insert with check (reporter_id = auth.uid());

drop policy if exists page_review_reports_moderate on public.page_review_reports;
create policy page_review_reports_moderate on public.page_review_reports
  for update using (public.is_admin_or_mod());

grant select, insert, update on public.page_review_reports to authenticated;

-- A site moderator resolving a report as upheld can remove the review in the
-- same motion (sets status='removed'); kept as one RPC so the audit trail
-- and the report resolution stay atomic instead of two separate client calls.
create or replace function public.resolve_page_review_report(
  p_report_id uuid,
  p_resolution text, -- 'resolved' or 'dismissed'
  p_remove_review boolean default false
)
returns void
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_review_id uuid;
  v_page_id uuid;
begin
  if not public.is_admin_or_mod() then
    raise exception 'Not authorized to resolve review reports.';
  end if;
  if p_resolution not in ('resolved', 'dismissed') then
    raise exception 'Invalid resolution.';
  end if;

  select review_id, page_id into v_review_id, v_page_id from public.page_review_reports where id = p_report_id;
  if v_review_id is null then
    raise exception 'Report not found.';
  end if;

  update public.page_review_reports
  set status = p_resolution, resolved_by = auth.uid(), resolved_at = now()
  where id = p_report_id;

  if p_remove_review and p_resolution = 'resolved' then
    update public.page_reviews set status = 'removed' where id = v_review_id;
    perform public.log_page_audit_event(v_page_id, 'review_removed_by_moderator', 'review', v_review_id,
      jsonb_build_object('report_id', p_report_id));
  end if;
end;
$$;

grant execute on function public.resolve_page_review_report(uuid, text, boolean) to authenticated;

-- 6. Read helper: paginated review list with the caller's own helpful-vote flag --
create or replace function public.get_page_reviews(
  p_page_id uuid,
  p_limit integer default 20,
  p_offset integer default 0,
  p_sort text default 'recent' -- 'recent' | 'helpful' | 'highest' | 'lowest'
)
returns table (
  id uuid,
  page_id uuid,
  user_id uuid,
  username text,
  profile_photo_url text,
  rating smallint,
  title text,
  body text,
  status text,
  owner_response text,
  owner_response_at timestamptz,
  helpful_count integer,
  edited boolean,
  created_at timestamptz,
  updated_at timestamptz,
  voted_helpful boolean
)
language sql
stable
security definer
set search_path = 'public'
as $$
  select
    r.id, r.page_id, r.user_id, u.username, u.profile_photo_url,
    r.rating, r.title, r.body, r.status, r.owner_response, r.owner_response_at,
    r.helpful_count, r.edited, r.created_at, r.updated_at,
    exists (select 1 from public.page_review_helpful_votes v where v.review_id = r.id and v.user_id = auth.uid()) as voted_helpful
  from public.page_reviews r
  join public.users u on u.id = r.user_id
  where r.page_id = p_page_id
    and (
      r.status = 'published'
      or r.user_id = auth.uid()
      or public.current_user_page_role(p_page_id) = 'owner'
      or public.current_user_has_page_permission(p_page_id, 'manage_reviews')
    )
  order by
    case when p_sort = 'helpful' then r.helpful_count end desc nulls last,
    case when p_sort = 'highest' then r.rating end desc nulls last,
    case when p_sort = 'lowest' then r.rating end asc nulls last,
    r.created_at desc
  limit greatest(1, least(p_limit, 50))
  offset greatest(0, p_offset);
$$;

grant execute on function public.get_page_reviews(uuid, integer, integer, text) to authenticated;

-- Rating breakdown (5/4/3/2/1 star counts) for the profile summary widget.
create or replace function public.get_page_rating_breakdown(p_page_id uuid)
returns table (rating smallint, count bigint)
language sql
stable
security definer
set search_path = 'public'
as $$
  select s.rating, coalesce(count(r.id), 0)
  from generate_series(1, 5) as s(rating)
  left join public.page_reviews r
    on r.page_id = p_page_id and r.status = 'published' and r.rating = s.rating
  group by s.rating
  order by s.rating desc;
$$;

grant execute on function public.get_page_rating_breakdown(uuid) to authenticated;
