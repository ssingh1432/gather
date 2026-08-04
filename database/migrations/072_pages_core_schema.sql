-- 072_pages_core_schema.sql
-- Professional Page System — Step 2 (core schema).
-- Fully additive: no existing table (users, posts, communities, ...) is
-- altered. Pages are a new, independent vertical alongside Communities.
--
-- Mirrors conventions already established in this codebase:
--   * text + check constraint for role/status enums (not native pg enum),
--     matching community_memberships.role / communities.visibility.
--   * role -> permission catalog + matrix, matching 052 (community_permissions
--     / community_role_permissions).
--   * explicit `grant ... to authenticated` on every table (migration 041
--     lesson: RLS with no table grant just silently denies everything).
--   * SECURITY DEFINER, search_path-pinned helper functions for permission
--     checks used inside RLS policies (matches 052 / phase10 hardening).

-- 1. Page categories -------------------------------------------------------
create table if not exists public.page_categories (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  slug text not null unique,
  icon text,
  created_at timestamptz not null default now()
);

alter table public.page_categories enable row level security;

drop policy if exists page_categories_select_all on public.page_categories;
create policy page_categories_select_all on public.page_categories
  for select using (true);

grant select on public.page_categories to authenticated;

insert into public.page_categories (name, slug, icon) values
  ('Business',      'business',      'storefront'),
  ('Restaurant',     'restaurant',    'restaurant'),
  ('Church',         'church',        'church'),
  ('School',         'school',        'school'),
  ('News',           'news',          'newspaper'),
  ('Creator',        'creator',       'star'),
  ('Brand',          'brand',         'label'),
  ('Government',     'government',    'account_balance'),
  ('NGO',            'ngo',           'volunteer_activism'),
  ('Entertainment',  'entertainment', 'movie'),
  ('Sports',         'sports',        'sports_soccer'),
  ('Technology',     'technology',    'memory'),
  ('Other',          'other',         'category')
on conflict (name) do nothing;

-- 2. Reserved usernames -----------------------------------------------------
-- Pages get their own @username namespace but must not collide with, or be
-- confusable with, an existing personal profile handle (public.users.username)
-- or a system route/word. No reserved-username system existed anywhere in
-- the repo before this migration.
create table if not exists public.page_reserved_usernames (
  username text primary key
);

insert into public.page_reserved_usernames (username) values
  ('admin'),('api'),('root'),('support'),('help'),('gather'),('settings'),
  ('login'),('signup'),('register'),('logout'),('page'),('pages'),
  ('create-page'),('community'),('communities'),('search'),('notifications'),
  ('legal'),('privacy'),('terms'),('about'),('contact'),('null'),('undefined'),
  ('moderator'),('official'),('verified'),('system')
on conflict do nothing;

alter table public.page_reserved_usernames enable row level security;

drop policy if exists page_reserved_usernames_select_all on public.page_reserved_usernames;
create policy page_reserved_usernames_select_all on public.page_reserved_usernames
  for select using (true);

grant select on public.page_reserved_usernames to authenticated;

-- (public.is_page_username_available is created after `pages` exists, below —
-- SQL-language functions are validated eagerly and would fail to create
-- otherwise since the table doesn't exist yet at this point in the file.)

-- 3. Pages -------------------------------------------------------------------
create table if not exists public.pages (
  id uuid primary key default gen_random_uuid(),
  username text not null unique
    check (username ~ '^[a-z0-9_]{3,30}$'),
  name text not null check (char_length(name) between 2 and 100),
  category_id uuid references public.page_categories(id) on delete set null,
  page_type text not null check (page_type in (
    'business','restaurant','church','school','news','creator','brand',
    'government','ngo','entertainment','sports','technology','other'
  )),
  description text,
  logo_url text,
  cover_url text,
  website text,
  phone text,
  email text,
  location text,
  country text,
  business_hours jsonb not null default '{}'::jsonb,
  language text not null default 'en',
  verification_status text not null default 'unverified'
    check (verification_status in ('unverified','pending','verified')),
  status text not null default 'draft'
    check (status in ('draft','published','suspended')),
  follower_count integer not null default 0,
  owner_id uuid not null references public.users(id) on delete cascade,
  created_by uuid not null references public.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

comment on column public.pages.follower_count is 'Denormalized count maintained by trg_page_follower_count. Do not write directly.';
comment on column public.pages.status is 'draft = only owner/team can see; published = publicly listed; suspended = moderation action, hidden from discovery.';

create index if not exists idx_pages_owner on public.pages (owner_id) where deleted_at is null;
create index if not exists idx_pages_category on public.pages (category_id) where deleted_at is null;
create index if not exists idx_pages_status on public.pages (status) where deleted_at is null;
create index if not exists idx_pages_username_trgm on public.pages using gin (username extensions.gin_trgm_ops);
create index if not exists idx_pages_name_trgm on public.pages using gin (name extensions.gin_trgm_ops);

create or replace function public.enforce_page_username_rules()
returns trigger
language plpgsql
security definer
set search_path = 'public'
as $$
begin
  new.username := lower(new.username);
  if exists (select 1 from public.page_reserved_usernames r where r.username = new.username) then
    raise exception 'This page username is reserved.';
  end if;
  if exists (
    select 1 from public.users u where lower(u.username) = new.username
  ) then
    raise exception 'This page username conflicts with an existing profile handle.';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_page_username_rules on public.pages;
create trigger trg_page_username_rules
  before insert or update of username on public.pages
  for each row execute function public.enforce_page_username_rules();

drop trigger if exists trg_pages_touch_updated_at on public.pages;
create trigger trg_pages_touch_updated_at
  before update on public.pages
  for each row execute function public.touch_updated_at();

create or replace function public.is_page_username_available(p_username text)
returns boolean
language sql
stable
security definer
set search_path = 'public'
as $$
  select
    p_username ~ '^[a-z0-9_]{3,30}$'
    and not exists (select 1 from public.page_reserved_usernames r where r.username = lower(p_username))
    and not exists (select 1 from public.users u where lower(u.username) = lower(p_username))
    and not exists (select 1 from public.pages pg where lower(pg.username) = lower(p_username));
$$;

grant execute on function public.is_page_username_available(text) to authenticated;

-- RLS + grants for `pages` are defined at the end of this file (section 7),
-- once the permission-check helper functions they depend on exist.

-- 4. Page roles ---------------------------------------------------------------
create table if not exists public.page_roles (
  page_id uuid not null references public.pages(id) on delete cascade,
  user_id uuid not null references public.users(id) on delete cascade,
  role text not null check (role in (
    'owner','manager','editor','content_creator','moderator',
    'customer_support','analyst'
  )),
  granted_by uuid references public.users(id) on delete set null,
  created_at timestamptz not null default now(),
  primary key (page_id, user_id)
);

create index if not exists idx_page_roles_user on public.page_roles (user_id);

-- 5. Page permission catalog + role matrix ------------------------------------
create table if not exists public.page_permissions (
  key text primary key,
  label text not null,
  description text not null,
  created_at timestamptz not null default now()
);

insert into public.page_permissions (key, label, description) values
  ('manage_settings',  'Manage settings',   'Edit page info, category, contact details, business hours.'),
  ('manage_roles',     'Manage roles',      'Add/remove team members and assign roles.'),
  ('manage_content',   'Manage content',    'Create, edit, pin, schedule, or delete page posts/events.'),
  ('manage_messages',  'Manage messages',   'Reply to page inbox / customer chat.'),
  ('manage_reviews',   'Manage reviews',    'Respond to and moderate reviews.'),
  ('manage_reports',   'Manage reports',    'View and resolve reports filed against the page.'),
  ('view_analytics',   'View analytics',    'View page insights and analytics dashboards.')
on conflict (key) do nothing;

alter table public.page_permissions enable row level security;

drop policy if exists page_permissions_select_all on public.page_permissions;
create policy page_permissions_select_all on public.page_permissions
  for select using (true);

grant select on public.page_permissions to authenticated;

create table if not exists public.page_role_permissions (
  role text not null check (role in (
    'owner','manager','editor','content_creator','moderator',
    'customer_support','analyst'
  )),
  permission_key text not null references public.page_permissions(key) on delete cascade,
  allowed boolean not null default true,
  primary key (role, permission_key)
);

alter table public.page_role_permissions enable row level security;

drop policy if exists page_role_permissions_select_all on public.page_role_permissions;
create policy page_role_permissions_select_all on public.page_role_permissions
  for select using (true);

grant select on public.page_role_permissions to authenticated;

-- Sane defaults: owner/manager get everything; editors manage content;
-- content_creator can only manage_content; moderator handles reviews/reports;
-- customer_support handles messages; analyst is read-only (view_analytics).
insert into public.page_role_permissions (role, permission_key, allowed)
select r.role, p.key, true from (values ('owner'),('manager')) as r(role)
cross join public.page_permissions p
on conflict do nothing;

insert into public.page_role_permissions (role, permission_key, allowed) values
  ('editor', 'manage_content', true),
  ('editor', 'manage_reviews', true),
  ('content_creator', 'manage_content', true),
  ('moderator', 'manage_reviews', true),
  ('moderator', 'manage_reports', true),
  ('customer_support', 'manage_messages', true),
  ('analyst', 'view_analytics', true)
on conflict do nothing;

create or replace function public.current_user_page_role(p_page_id uuid)
returns text
language sql
stable
security definer
set search_path = 'public'
as $$
  select case
    when exists (select 1 from public.pages pg where pg.id = p_page_id and pg.owner_id = auth.uid())
      then 'owner'
    else (select role from public.page_roles pr where pr.page_id = p_page_id and pr.user_id = auth.uid())
  end;
$$;

create or replace function public.current_user_has_page_permission(p_page_id uuid, p_permission_key text)
returns boolean
language sql
stable
security definer
set search_path = 'public'
as $$
  select coalesce((
    select allowed from public.page_role_permissions
    where role = public.current_user_page_role(p_page_id)
      and permission_key = p_permission_key
  ), false);
$$;

grant execute on function public.current_user_page_role(uuid) to authenticated;
grant execute on function public.current_user_has_page_permission(uuid, text) to authenticated;

drop policy if exists page_roles_select on public.page_roles;
create policy page_roles_select on public.page_roles
  for select using (
    user_id = auth.uid()
    or public.current_user_page_role(page_id) is not null
  );

drop policy if exists page_roles_manage on public.page_roles;
create policy page_roles_manage on public.page_roles
  for all using (
    public.current_user_page_role(page_id) = 'owner'
    or public.current_user_has_page_permission(page_id, 'manage_roles')
  ) with check (
    role <> 'owner'
    and (
      public.current_user_page_role(page_id) = 'owner'
      or public.current_user_has_page_permission(page_id, 'manage_roles')
    )
  );

grant select, insert, update, delete on public.page_roles to authenticated;

-- 6. Page followers -------------------------------------------------------------
create table if not exists public.page_followers (
  page_id uuid not null references public.pages(id) on delete cascade,
  user_id uuid not null references public.users(id) on delete cascade,
  notify boolean not null default true,
  created_at timestamptz not null default now(),
  primary key (page_id, user_id)
);

create index if not exists idx_page_followers_user on public.page_followers (user_id);

create or replace function public.update_page_follower_count()
returns trigger
language plpgsql
security definer
set search_path = 'public'
as $$
begin
  if tg_op = 'INSERT' then
    update public.pages set follower_count = follower_count + 1 where id = new.page_id;
  elsif tg_op = 'DELETE' then
    update public.pages set follower_count = greatest(0, follower_count - 1) where id = old.page_id;
  end if;
  return null;
end;
$$;

drop trigger if exists trg_page_follower_count on public.page_followers;
create trigger trg_page_follower_count
  after insert or delete on public.page_followers
  for each row execute function public.update_page_follower_count();

alter table public.page_followers enable row level security;

drop policy if exists page_followers_select on public.page_followers;
create policy page_followers_select on public.page_followers
  for select using (true);

drop policy if exists page_followers_manage_own on public.page_followers;
create policy page_followers_manage_own on public.page_followers
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());

grant select, insert, delete, update on public.page_followers to authenticated;

-- 7. `pages` RLS (deferred from section 3 — depends on functions from section 5) -
alter table public.pages enable row level security;

drop policy if exists pages_select on public.pages;
create policy pages_select on public.pages
  for select using (
    deleted_at is null
    and (
      status = 'published'
      or owner_id = auth.uid()
      or exists (select 1 from public.page_roles pr where pr.page_id = id and pr.user_id = auth.uid())
    )
  );

drop policy if exists pages_insert on public.pages;
create policy pages_insert on public.pages
  for insert with check (owner_id = auth.uid() and created_by = auth.uid());

drop policy if exists pages_update on public.pages;
create policy pages_update on public.pages
  for update using (
    owner_id = auth.uid()
    or public.current_user_has_page_permission(id, 'manage_settings')
  );

grant select, insert, update on public.pages to authenticated;
