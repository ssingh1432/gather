-- 055_community_categories_tags.sql
-- Community System Step 2 (item 4, final): community_categories and
-- community_tags as real catalog tables, replacing the free-text
-- `communities.category` column.
--
-- Backward-compatible by design: `communities.category` (text) is NOT
-- dropped in this migration. Existing create/edit-community Flutter code
-- still writes a plain string to it and keeps working unchanged. A new
-- trigger resolves that string against the community_categories catalog
-- (case-insensitive, get-or-create) and keeps `category_id` in sync
-- automatically, so the relational side populates itself without a
-- Flutter change. The next phase can switch the UI to write category_id
-- directly via set_community_category(); the old text column can be
-- dropped in a follow-up migration once nothing reads it anymore.
--
-- Existing live data (2 communities: category = 'Business', 'dance') is
-- auto-migrated into the catalog by the backfill at the bottom.

-- 1. Slug helper -------------------------------------------------------
create or replace function public.slugify(p_text text)
returns text
language sql
immutable
as $$
  select trim(both '-' from regexp_replace(lower(trim(p_text)), '[^a-z0-9]+', '-', 'g'));
$$;

-- 2. community_categories -----------------------------------------------
create table if not exists public.community_categories (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique,
  name text not null,
  icon text,
  created_at timestamptz not null default now()
);

alter table public.community_categories enable row level security;

drop policy if exists community_categories_select_all on public.community_categories;
create policy community_categories_select_all on public.community_categories for select using (true);

grant select on public.community_categories to authenticated;
-- No client insert/update/delete — only via get_or_create_community_category()
-- (called from the sync trigger and from set_community_category()), so the
-- catalog can't be spammed with junk/duplicate entries from the client.

-- 3. community_tags -------------------------------------------------------
create table if not exists public.community_tags (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique,
  name text not null,
  created_at timestamptz not null default now()
);

alter table public.community_tags enable row level security;

drop policy if exists community_tags_select_all on public.community_tags;
create policy community_tags_select_all on public.community_tags for select using (true);

grant select on public.community_tags to authenticated;

-- 4. community_tag_assignments (many-to-many) ------------------------------
create table if not exists public.community_tag_assignments (
  community_id uuid not null references public.communities(id) on delete cascade,
  tag_id uuid not null references public.community_tags(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (community_id, tag_id)
);

create index if not exists idx_community_tag_assignments_tag on public.community_tag_assignments (tag_id);

alter table public.community_tag_assignments enable row level security;

-- Tag assignments are as public as the community listing itself (not a
-- privacy boundary), so this is a plain select-all like the catalogs.
drop policy if exists community_tag_assignments_select_all on public.community_tag_assignments;
create policy community_tag_assignments_select_all on public.community_tag_assignments for select using (true);

grant select on public.community_tag_assignments to authenticated;
-- Writes only via set_community_tags() below.

-- 5. communities.category_id ----------------------------------------------
alter table public.communities add column if not exists category_id uuid references public.community_categories(id) on delete set null;
create index if not exists idx_communities_category_id on public.communities (category_id);

-- 6. Get-or-create helpers (internal; not directly granted) ----------------
create or replace function public.get_or_create_community_category(p_name text)
returns uuid
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_slug text;
  v_id uuid;
begin
  if p_name is null or length(trim(p_name)) = 0 then
    return null;
  end if;
  v_slug := public.slugify(p_name);
  if v_slug = '' then
    return null;
  end if;

  insert into public.community_categories (slug, name)
  values (v_slug, trim(p_name))
  on conflict (slug) do nothing
  returning id into v_id;

  if v_id is null then
    select id into v_id from public.community_categories where slug = v_slug;
  end if;

  return v_id;
end;
$$;

create or replace function public.get_or_create_community_tag(p_name text)
returns uuid
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_slug text;
  v_id uuid;
begin
  if p_name is null or length(trim(p_name)) = 0 then
    return null;
  end if;
  v_slug := public.slugify(p_name);
  if v_slug = '' then
    return null;
  end if;

  insert into public.community_tags (slug, name)
  values (v_slug, trim(p_name))
  on conflict (slug) do nothing
  returning id into v_id;

  if v_id is null then
    select id into v_id from public.community_tags where slug = v_slug;
  end if;

  return v_id;
end;
$$;

-- 7. Sync trigger: communities.category (text) -> category_id -------------
-- Keeps the relational side populated for free from existing writes to
-- the legacy text column, with zero Flutter changes required.
create or replace function public.sync_community_category_id()
returns trigger
language plpgsql
security definer
set search_path = 'public'
as $$
begin
  if tg_op = 'INSERT' then
    if new.category is not null then
      new.category_id := public.get_or_create_community_category(new.category);
    end if;
  elsif tg_op = 'UPDATE' then
    if new.category is distinct from old.category then
      new.category_id := public.get_or_create_community_category(new.category);
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_sync_community_category_id on public.communities;
create trigger trg_sync_community_category_id
  before insert or update on public.communities
  for each row execute function public.sync_community_category_id();

-- 8. RPC: set category directly (for once the UI moves to category_id) ----
create or replace function public.set_community_category(p_community_id uuid, p_category_name text)
returns uuid
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_category_id uuid;
begin
  if not public.current_user_community_permission(p_community_id, 'manage_settings') then
    raise exception 'Not authorized to change this community''s category';
  end if;

  v_category_id := public.get_or_create_community_category(p_category_name);

  -- Also mirrors into the legacy text column so anything still reading
  -- `category` directly (old client builds, admin views) stays correct.
  update public.communities
  set category_id = v_category_id, category = trim(p_category_name)
  where id = p_community_id;

  perform public.log_community_audit(p_community_id, 'settings_changed', null, jsonb_build_object('category', p_category_name));

  return v_category_id;
end;
$$;

grant execute on function public.set_community_category(uuid, text) to authenticated;

-- 9. RPC: replace a community's full tag set --------------------------------
create or replace function public.set_community_tags(p_community_id uuid, p_tag_names text[])
returns void
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_tag_name text;
  v_tag_id uuid;
  v_tag_ids uuid[] := '{}';
begin
  if not public.current_user_community_permission(p_community_id, 'manage_settings') then
    raise exception 'Not authorized to change this community''s tags';
  end if;

  if array_length(p_tag_names, 1) > 10 then
    raise exception 'A community can have at most 10 tags';
  end if;

  foreach v_tag_name in array coalesce(p_tag_names, '{}') loop
    v_tag_id := public.get_or_create_community_tag(v_tag_name);
    if v_tag_id is not null then
      v_tag_ids := array_append(v_tag_ids, v_tag_id);
    end if;
  end loop;

  delete from public.community_tag_assignments
  where community_id = p_community_id and not (tag_id = any(v_tag_ids));

  insert into public.community_tag_assignments (community_id, tag_id)
  select p_community_id, unnest(v_tag_ids)
  on conflict (community_id, tag_id) do nothing;

  perform public.log_community_audit(p_community_id, 'settings_changed', null, jsonb_build_object('tags', p_tag_names));
end;
$$;

grant execute on function public.set_community_tags(uuid, text[]) to authenticated;

-- 10. Backfill existing live data -------------------------------------------
-- Direct backfill rather than relying on the trigger: a same-value UPDATE
-- wouldn't pass the trigger's `is distinct from` check, so it would be a
-- silent no-op if we tried to "re-save" existing rows instead.
update public.communities
set category_id = public.get_or_create_community_category(category)
where category is not null and category_id is null;
