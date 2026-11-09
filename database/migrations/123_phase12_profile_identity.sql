-- Phase 12 / Step 2: profile identity - username change, profile links,
-- verification (closing a hole in verification requests), badges, themes.
--
-- Findings this migration fixes (from the Phase 12 audit):
--   * Any user could change users.username directly via the API: no format
--     rules, no cooldown, no reserved names, no history.
--   * user_verification_requests INSERT only checked user_id, so a user could
--     insert a row already marked status='approved'.
--   * Approving a verification request never set users.is_verified.
--
-- Manual apply required: CI does not run migrations.

-- =====================================================================
-- 1. New columns on users
-- =====================================================================
alter table public.users add column if not exists username_changed_at timestamptz;
alter table public.users add column if not exists is_verified boolean not null default false;
alter table public.users add column if not exists verified_at timestamptz;
alter table public.users add column if not exists profile_theme text not null default 'default';

alter table public.users drop constraint if exists users_profile_theme_check;
alter table public.users add constraint users_profile_theme_check
  check (profile_theme in ('default','ocean','forest','sunset','rose','midnight'));

-- =====================================================================
-- 2. Guard: identity columns can only change through the RPCs below
--    (or by admins / trusted server contexts with no end-user JWT).
-- =====================================================================
create or replace function public.guard_profile_identity_columns()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_flag boolean := coalesce(current_setting('gather.allow_username_change', true), '') = '1';
begin
  if auth.uid() is null or public.is_admin_or_mod() then
    return new;
  end if;

  if new.is_verified is distinct from old.is_verified
     or new.verified_at is distinct from old.verified_at then
    raise exception 'Verification status can only be changed by moderators' using errcode = '42501';
  end if;

  if (new.username is distinct from old.username
      or new.username_changed_at is distinct from old.username_changed_at)
     and not v_flag then
    raise exception 'Use change_username() to change your username' using errcode = '42501';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_guard_profile_identity_columns on public.users;
create trigger trg_guard_profile_identity_columns
  before update on public.users
  for each row execute function public.guard_profile_identity_columns();

-- =====================================================================
-- 3. Username change
-- =====================================================================
create table if not exists public.username_history (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.users(id) on delete cascade,
  old_username text not null,
  new_username text not null,
  changed_at timestamptz not null default now(),
  reserved_until timestamptz not null default (now() + interval '90 days')
);
create index if not exists idx_username_history_old_lower
  on public.username_history (lower(old_username), reserved_until desc);
create index if not exists idx_username_history_user
  on public.username_history (user_id, changed_at desc);

alter table public.username_history enable row level security;
revoke all on public.username_history from anon, authenticated;
grant select on public.username_history to authenticated;
drop policy if exists "Users read own username history" on public.username_history;
create policy "Users read own username history"
  on public.username_history for select to authenticated
  using (user_id = auth.uid() or public.is_admin_or_mod());

-- Format rules, shared by the RPC and exposed for the client to pre-check.
create or replace function public.validate_username(p_username text)
returns text
language plpgsql
immutable
as $$
declare
  v text := coalesce(p_username, '');
  reserved text[] := array[
    'admin','administrator','moderator','mod','support','help','gather','official',
    'staff','team','security','system','root','null','undefined','api','www',
    'about','privacy','terms','settings','login','signup','register'];
begin
  if v !~ '^[a-z0-9_.]{3,30}$' then
    return 'Usernames are 3-30 characters: lowercase letters, numbers, underscore or dot.';
  end if;
  if v ~ '^[._]' or v ~ '[._]$' then
    return 'Usernames cannot start or end with a dot or underscore.';
  end if;
  if v ~ '\.\.' then
    return 'Usernames cannot contain two dots in a row.';
  end if;
  if v !~ '[a-z]' then
    return 'Usernames must contain at least one letter.';
  end if;
  if v = any(reserved) then
    return 'That username is reserved.';
  end if;
  return null;
end;
$$;
grant execute on function public.validate_username(text) to authenticated;

create or replace function public.change_username(p_new text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_new text := lower(trim(coalesce(p_new, '')));
  v_old text;
  v_changed timestamptz;
  v_err text;
  v_next timestamptz;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  v_err := public.validate_username(v_new);
  if v_err is not null then
    raise exception '%', v_err using errcode = '22023';
  end if;

  -- Serialize concurrent claims of the same name.
  perform pg_advisory_xact_lock(hashtextextended('username:' || v_new, 0));

  select username, username_changed_at into v_old, v_changed
  from public.users where id = v_uid for update;

  if v_old is null then
    raise exception 'user_not_found' using errcode = 'P0002';
  end if;
  if lower(v_old) = v_new and v_old = v_new then
    raise exception 'That is already your username.' using errcode = '22023';
  end if;

  if v_changed is not null and v_changed + interval '30 days' > now() then
    v_next := v_changed + interval '30 days';
    raise exception 'You can change your username again on %.', to_char(v_next, 'YYYY-MM-DD')
      using errcode = '22023';
  end if;

  if exists (select 1 from public.users u where lower(u.username) = v_new and u.id <> v_uid) then
    raise exception 'That username is already taken.' using errcode = '23505';
  end if;

  -- Recently released names stay reserved for their previous owner.
  if exists (
    select 1 from public.username_history h
    where lower(h.old_username) = v_new and h.user_id <> v_uid and h.reserved_until > now()
  ) then
    raise exception 'That username is not available right now.' using errcode = '23505';
  end if;

  perform set_config('gather.allow_username_change', '1', true);
  update public.users
     set username = v_new, username_changed_at = now()
   where id = v_uid;
  perform set_config('gather.allow_username_change', '', true);

  insert into public.username_history (user_id, old_username, new_username)
  values (v_uid, v_old, v_new);

  insert into public.security_events (actor_id, event_type, metadata)
  values (v_uid, 'username_changed', jsonb_build_object('old', v_old, 'new', v_new));

  return jsonb_build_object('username', v_new, 'next_change_at', now() + interval '30 days');
end;
$$;

revoke all on function public.change_username(text) from public, anon;
grant execute on function public.change_username(text) to authenticated;

-- =====================================================================
-- 4. Profile links (in addition to the existing users.website_url)
-- =====================================================================
create table if not exists public.user_links (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users(id) on delete cascade,
  label text not null check (char_length(trim(label)) between 1 and 40),
  url text not null check (char_length(url) <= 300 and url ~* '^https?://[^[:space:]]+$'),
  position smallint not null default 0 check (position between 0 and 4),
  created_at timestamptz not null default now()
);
create index if not exists idx_user_links_user on public.user_links (user_id, position);

alter table public.user_links enable row level security;
revoke all on public.user_links from anon, authenticated;
grant select, insert, update, delete on public.user_links to authenticated;

create or replace function public.enforce_user_links_limit()
returns trigger
language plpgsql
as $$
begin
  if (select count(*) from public.user_links where user_id = new.user_id) >= 5 then
    raise exception 'You can add up to 5 links' using errcode = '22023';
  end if;
  return new;
end;
$$;
drop trigger if exists trg_user_links_limit on public.user_links;
create trigger trg_user_links_limit before insert on public.user_links
  for each row execute function public.enforce_user_links_limit();

drop policy if exists user_links_select on public.user_links;
create policy user_links_select on public.user_links for select to authenticated
  using (
    user_id = auth.uid()
    or public.is_admin_or_mod()
    or (
      not public.users_are_blocked(auth.uid(), user_id)
      and (
        not coalesce((select u.is_private from public.users u where u.id = user_links.user_id), false)
        or exists (select 1 from public.user_follows f
                   where f.follower_id = auth.uid() and f.following_id = user_links.user_id)
      )
    )
  );
drop policy if exists user_links_insert on public.user_links;
create policy user_links_insert on public.user_links for insert to authenticated
  with check (user_id = auth.uid());
drop policy if exists user_links_update on public.user_links;
create policy user_links_update on public.user_links for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
drop policy if exists user_links_delete on public.user_links;
create policy user_links_delete on public.user_links for delete to authenticated
  using (user_id = auth.uid());

-- =====================================================================
-- 5. Verification: close the self-approve hole, link approval to the badge
-- =====================================================================
drop policy if exists "Users submit verification requests" on public.user_verification_requests;
create policy "Users submit verification requests"
  on public.user_verification_requests for insert to authenticated
  with check (
    user_id = auth.uid()
    and status = 'pending'
    and reviewed_by is null
    and reviewed_at is null
    and review_notes is null
    and not exists (
      select 1 from public.user_verification_requests r
      where r.user_id = auth.uid() and r.status = 'pending'
    )
  );

create or replace function public.apply_verification_decision()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status is not distinct from old.status then
    return new;
  end if;

  if new.status = 'approved' then
    update public.users set is_verified = true, verified_at = now() where id = new.user_id;
  elsif old.status = 'approved' then
    update public.users set is_verified = false, verified_at = null where id = new.user_id;
  end if;

  if auth.uid() is not null and public.is_admin_or_mod() then
    perform public.log_admin_action('verification_' || new.status, 'user', new.user_id::text,
                                    jsonb_build_object('request_id', new.id));
  end if;
  return new;
end;
$$;
drop trigger if exists trg_apply_verification_decision on public.user_verification_requests;
create trigger trg_apply_verification_decision
  after update of status on public.user_verification_requests
  for each row execute function public.apply_verification_decision();

-- Private bucket for ID documents: owner uploads/reads/deletes, staff read.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('verification-docs', 'verification-docs', false, 5242880,
        array['image/jpeg','image/png','image/webp'])
on conflict (id) do update
  set public = false, file_size_limit = 5242880,
      allowed_mime_types = array['image/jpeg','image/png','image/webp'];

drop policy if exists "verification_docs_insert_own" on storage.objects;
create policy "verification_docs_insert_own" on storage.objects for insert to authenticated
  with check (bucket_id = 'verification-docs' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists "verification_docs_select_own_or_staff" on storage.objects;
create policy "verification_docs_select_own_or_staff" on storage.objects for select to authenticated
  using (bucket_id = 'verification-docs'
         and ((storage.foldername(name))[1] = auth.uid()::text or public.is_admin_or_mod()));
drop policy if exists "verification_docs_delete_own" on storage.objects;
create policy "verification_docs_delete_own" on storage.objects for delete to authenticated
  using (bucket_id = 'verification-docs' and (storage.foldername(name))[1] = auth.uid()::text);

-- =====================================================================
-- 6. Badges
-- =====================================================================
create table if not exists public.badges (
  slug text primary key check (slug ~ '^[a-z0-9_]{2,40}$'),
  name text not null check (char_length(name) between 1 and 60),
  description text not null default '',
  icon text not null default 'workspace_premium',
  created_at timestamptz not null default now()
);
create table if not exists public.user_badges (
  user_id uuid not null references public.users(id) on delete cascade,
  badge_slug text not null references public.badges(slug) on delete cascade,
  awarded_by uuid references public.users(id) on delete set null,
  awarded_at timestamptz not null default now(),
  primary key (user_id, badge_slug)
);
create index if not exists idx_user_badges_user on public.user_badges (user_id);

alter table public.badges enable row level security;
alter table public.user_badges enable row level security;
revoke all on public.badges, public.user_badges from anon, authenticated;
grant select on public.badges, public.user_badges to authenticated;

drop policy if exists badges_select on public.badges;
create policy badges_select on public.badges for select to authenticated using (true);
drop policy if exists user_badges_select on public.user_badges;
create policy user_badges_select on public.user_badges for select to authenticated
  using (user_id = auth.uid() or public.is_admin_or_mod()
         or not public.users_are_blocked(auth.uid(), user_id));

insert into public.badges (slug, name, description, icon) values
  ('early_supporter', 'Early supporter', 'Joined Gather during the closed beta.', 'favorite'),
  ('creator', 'Creator', 'Recognised for creating great content.', 'auto_awesome'),
  ('community_helper', 'Community helper', 'Helps keep Gather welcoming.', 'volunteer_activism')
on conflict (slug) do nothing;

create or replace function public.admin_award_badge(p_user_id uuid, p_badge_slug text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'not authorized' using errcode = '42501';
  end if;
  insert into public.user_badges (user_id, badge_slug, awarded_by)
  values (p_user_id, p_badge_slug, auth.uid())
  on conflict (user_id, badge_slug) do nothing;
  perform public.log_admin_action('badge_awarded', 'user', p_user_id::text,
                                  jsonb_build_object('badge', p_badge_slug));
end;
$$;

create or replace function public.admin_revoke_badge(p_user_id uuid, p_badge_slug text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'not authorized' using errcode = '42501';
  end if;
  delete from public.user_badges where user_id = p_user_id and badge_slug = p_badge_slug;
  perform public.log_admin_action('badge_revoked', 'user', p_user_id::text,
                                  jsonb_build_object('badge', p_badge_slug));
end;
$$;

revoke all on function public.admin_award_badge(uuid, text) from public, anon;
revoke all on function public.admin_revoke_badge(uuid, text) from public, anon;
grant execute on function public.admin_award_badge(uuid, text) to authenticated;
grant execute on function public.admin_revoke_badge(uuid, text) to authenticated;

notify pgrst, 'reload schema';
