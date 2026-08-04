-- 073_pages_content.sql
-- Professional Page System — Step 2 (content schema): page_posts, page_events,
-- page_reviews. Additive only; depends on 072_pages_core_schema.sql
-- (pages, page_roles, current_user_has_page_permission).

-- 1. Page posts ---------------------------------------------------------------
create table if not exists public.page_posts (
  id uuid primary key default gen_random_uuid(),
  page_id uuid not null references public.pages(id) on delete cascade,
  author_id uuid references public.users(id) on delete set null,
  post_type text not null default 'post'
    check (post_type in ('post','photo','video','poll','offer','job','article')),
  content text,
  media jsonb not null default '[]'::jsonb,
  status text not null default 'draft'
    check (status in ('draft','scheduled','published','archived')),
  pinned boolean not null default false,
  scheduled_at timestamptz,
  published_at timestamptz,
  edited_at timestamptz,
  version integer not null default 1,
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint page_posts_scheduled_requires_time
    check (status <> 'scheduled' or scheduled_at is not null)
);

comment on column public.page_posts.version is 'Incremented by trg_page_posts_track_edits whenever content or media changes after first publish.';

create index if not exists idx_page_posts_page on public.page_posts (page_id) where deleted_at is null;
create index if not exists idx_page_posts_status on public.page_posts (page_id, status) where deleted_at is null;
create index if not exists idx_page_posts_pinned on public.page_posts (page_id) where pinned and deleted_at is null;
create index if not exists idx_page_posts_scheduled on public.page_posts (scheduled_at) where status = 'scheduled' and deleted_at is null;

drop trigger if exists trg_page_posts_touch_updated_at on public.page_posts;
create trigger trg_page_posts_touch_updated_at
  before update on public.page_posts
  for each row execute function public.touch_updated_at();

create or replace function public.track_page_post_edits()
returns trigger
language plpgsql
security definer
set search_path = 'public'
as $$
begin
  if tg_op = 'UPDATE'
     and old.status = 'published'
     and (new.content is distinct from old.content or new.media is distinct from old.media) then
    new.version := old.version + 1;
    new.edited_at := now();
  end if;
  if tg_op = 'UPDATE' and old.status <> 'published' and new.status = 'published' and new.published_at is null then
    new.published_at := now();
  end if;
  return new;
end;
$$;

drop trigger if exists trg_page_posts_track_edits on public.page_posts;
create trigger trg_page_posts_track_edits
  before update on public.page_posts
  for each row execute function public.track_page_post_edits();

alter table public.page_posts enable row level security;

drop policy if exists page_posts_select on public.page_posts;
create policy page_posts_select on public.page_posts
  for select using (
    deleted_at is null
    and (
      (status = 'published' and exists (
        select 1 from public.pages pg where pg.id = page_id and pg.status = 'published' and pg.deleted_at is null
      ))
      or public.current_user_page_role(page_id) is not null
    )
  );

drop policy if exists page_posts_insert on public.page_posts;
create policy page_posts_insert on public.page_posts
  for insert with check (
    author_id = auth.uid()
    and public.current_user_has_page_permission(page_id, 'manage_content')
  );

drop policy if exists page_posts_update on public.page_posts;
create policy page_posts_update on public.page_posts
  for update using (public.current_user_has_page_permission(page_id, 'manage_content'));

drop policy if exists page_posts_delete on public.page_posts;
create policy page_posts_delete on public.page_posts
  for delete using (public.current_user_has_page_permission(page_id, 'manage_content'));

grant select, insert, update, delete on public.page_posts to authenticated;

-- 2. Page events ----------------------------------------------------------------
create table if not exists public.page_events (
  id uuid primary key default gen_random_uuid(),
  page_id uuid not null references public.pages(id) on delete cascade,
  title text not null check (char_length(title) between 2 and 150),
  description text,
  cover_url text,
  location text,
  start_time timestamptz not null,
  end_time timestamptz,
  created_by uuid references public.users(id) on delete set null,
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint page_events_end_after_start check (end_time is null or end_time >= start_time)
);

create index if not exists idx_page_events_page on public.page_events (page_id, start_time) where deleted_at is null;

drop trigger if exists trg_page_events_touch_updated_at on public.page_events;
create trigger trg_page_events_touch_updated_at
  before update on public.page_events
  for each row execute function public.touch_updated_at();

alter table public.page_events enable row level security;

drop policy if exists page_events_select on public.page_events;
create policy page_events_select on public.page_events
  for select using (
    deleted_at is null
    and (
      exists (select 1 from public.pages pg where pg.id = page_id and pg.status = 'published' and pg.deleted_at is null)
      or public.current_user_page_role(page_id) is not null
    )
  );

drop policy if exists page_events_manage on public.page_events;
create policy page_events_manage on public.page_events
  for all using (public.current_user_has_page_permission(page_id, 'manage_content'))
  with check (public.current_user_has_page_permission(page_id, 'manage_content'));

grant select, insert, update, delete on public.page_events to authenticated;

-- 3. Page reviews -----------------------------------------------------------------
create table if not exists public.page_reviews (
  id uuid primary key default gen_random_uuid(),
  page_id uuid not null references public.pages(id) on delete cascade,
  user_id uuid not null references public.users(id) on delete cascade,
  rating integer not null check (rating between 1 and 5),
  comment text,
  owner_response text,
  owner_response_at timestamptz,
  helpful_count integer not null default 0,
  status text not null default 'visible' check (status in ('visible','hidden','removed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (page_id, user_id)
);

create index if not exists idx_page_reviews_page on public.page_reviews (page_id) where status = 'visible';

drop trigger if exists trg_page_reviews_touch_updated_at on public.page_reviews;
create trigger trg_page_reviews_touch_updated_at
  before update on public.page_reviews
  for each row execute function public.touch_updated_at();

-- Prevent a page's own team from reviewing their own page, and prevent a
-- reviewer from writing into owner_response themselves (that's a
-- manage_reviews-only field, enforced here rather than via column-grants
-- since Postgres RLS can't do column-level checks based on which columns
-- changed without a trigger).
create or replace function public.guard_page_review_fields()
returns trigger
language plpgsql
security definer
set search_path = 'public'
as $$
begin
  if tg_op = 'INSERT' and public.current_user_page_role(new.page_id) is not null then
    raise exception 'Page team members cannot review their own page.';
  end if;

  if tg_op = 'UPDATE' then
    -- Only the author may change rating/comment.
    if new.user_id <> auth.uid()
       and (new.rating is distinct from old.rating or new.comment is distinct from old.comment) then
      raise exception 'Only the review author can edit the rating or comment.';
    end if;
    -- Only someone with manage_reviews may change the owner response or status.
    if (new.owner_response is distinct from old.owner_response
        or new.status is distinct from old.status)
       and not public.current_user_has_page_permission(new.page_id, 'manage_reviews') then
      raise exception 'Only page staff with manage_reviews can respond to or moderate a review.';
    end if;
    if new.owner_response is distinct from old.owner_response and new.owner_response is not null then
      new.owner_response_at := now();
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_guard_page_review_fields on public.page_reviews;
create trigger trg_guard_page_review_fields
  before insert or update on public.page_reviews
  for each row execute function public.guard_page_review_fields();

alter table public.page_reviews enable row level security;

drop policy if exists page_reviews_select on public.page_reviews;
create policy page_reviews_select on public.page_reviews
  for select using (
    status = 'visible'
    or user_id = auth.uid()
    or public.current_user_has_page_permission(page_id, 'manage_reviews')
  );

drop policy if exists page_reviews_insert on public.page_reviews;
create policy page_reviews_insert on public.page_reviews
  for insert with check (user_id = auth.uid());

drop policy if exists page_reviews_update on public.page_reviews;
create policy page_reviews_update on public.page_reviews
  for update using (
    user_id = auth.uid()
    or public.current_user_has_page_permission(page_id, 'manage_reviews')
  );

grant select, insert, update on public.page_reviews to authenticated;

-- Helpful votes (dedup table backing page_reviews.helpful_count).
create table if not exists public.page_review_helpful_votes (
  review_id uuid not null references public.page_reviews(id) on delete cascade,
  user_id uuid not null references public.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (review_id, user_id)
);

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
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());

grant select, insert, delete on public.page_review_helpful_votes to authenticated;
