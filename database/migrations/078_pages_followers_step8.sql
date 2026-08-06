-- 078_pages_followers_step8.sql
-- Professional Page System — Step 8 (Followers).
--
-- Follow/Unfollow already shipped in 072 (page_followers + follower_count
-- trigger) and is wired up in page_profile_screen.dart. This migration adds
-- the rest of the brief's Step 8 scope:
--   1. Favorite  — a per-follower flag on an existing follow.
--   2. Notifications — new-follower alert to the page team, new-post alert
--      to followers who opted in (page_followers.notify, already existed
--      but was never actually wired to anything until now).
--   3. Invite Followers — page team (manage_content) can invite specific
--      users to follow; invitee gets a notification.
--   4. Follower Analytics — count/growth + a paginated, permission-gated
--      follower roster for the page team (view_analytics).
--
-- Depends on: 072_pages_core_schema.sql, 077_pages_followers_step8_enum.sql.
-- Fully additive — no existing table/column/policy is altered destructively.

-- 1. Favorite -----------------------------------------------------------------
alter table public.page_followers add column if not exists favorite boolean not null default false;

comment on column public.page_followers.favorite is
  'Follower-side flag: this user has starred the page for quick access, distinct from page_followers.notify (their per-page notification preference).';

-- 2a. Notify the page team when someone new follows --------------------------
create or replace function public.notify_page_new_follower()
returns trigger
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_page_name text;
  v_owner_id uuid;
  v_follower_username text;
begin
  select name, owner_id into v_page_name, v_owner_id from public.pages where id = new.page_id;
  select username into v_follower_username from public.users where id = new.user_id;

  insert into public.notifications (recipient_id, actor_id, type, metadata)
  select recipient, new.user_id, 'page_new_follower',
    jsonb_build_object('page_id', new.page_id, 'page_name', v_page_name, 'follower_username', v_follower_username)
  from (
    select v_owner_id as recipient
    union
    select pr.user_id
    from public.page_roles pr
    join public.page_role_permissions rp on rp.role = pr.role and rp.permission_key = 'manage_content' and rp.allowed
    where pr.page_id = new.page_id
  ) recips
  where recipient is not null and recipient <> new.user_id;

  return new;
end;
$$;

drop trigger if exists trg_notify_page_new_follower on public.page_followers;
create trigger trg_notify_page_new_follower
  after insert on public.page_followers
  for each row execute function public.notify_page_new_follower();

-- 2b. Notify opted-in followers when a page publishes a new post -------------
-- Fires only on the transition into 'published' (fresh insert already
-- published, or an update out of draft/scheduled), mirroring the same
-- "first publish only" guard as track_page_post_edits in 073, so editing an
-- already-published post never re-spams followers.
create or replace function public.notify_page_followers_new_post()
returns trigger
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_page_name text;
begin
  if (tg_op = 'INSERT' and new.status = 'published')
     or (tg_op = 'UPDATE' and old.status <> 'published' and new.status = 'published') then

    select name into v_page_name from public.pages where id = new.page_id;

    insert into public.notifications (recipient_id, actor_id, type, metadata)
    select pf.user_id, new.author_id, 'page_new_post',
      jsonb_build_object('page_id', new.page_id, 'page_name', v_page_name, 'page_post_id', new.id, 'post_type', new.post_type)
    from public.page_followers pf
    where pf.page_id = new.page_id
      and pf.notify = true
      and pf.user_id <> coalesce(new.author_id, '00000000-0000-0000-0000-000000000000'::uuid);
  end if;

  return new;
end;
$$;

drop trigger if exists trg_notify_page_followers_new_post on public.page_posts;
create trigger trg_notify_page_followers_new_post
  after insert or update on public.page_posts
  for each row execute function public.notify_page_followers_new_post();

-- 3. Invite Followers ----------------------------------------------------------
create table if not exists public.page_follow_invites (
  id uuid primary key default gen_random_uuid(),
  page_id uuid not null references public.pages(id) on delete cascade,
  inviter_id uuid not null references public.users(id) on delete cascade,
  invitee_id uuid not null references public.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (page_id, invitee_id)
);

create index if not exists idx_page_follow_invites_invitee on public.page_follow_invites (invitee_id);
create index if not exists idx_page_follow_invites_page on public.page_follow_invites (page_id);

alter table public.page_follow_invites enable row level security;

drop policy if exists page_follow_invites_select on public.page_follow_invites;
create policy page_follow_invites_select on public.page_follow_invites
  for select using (
    inviter_id = auth.uid()
    or invitee_id = auth.uid()
    or public.current_user_has_page_permission(page_id, 'manage_content')
  );

-- Inserts only ever happen through invite_users_to_follow_page (SECURITY
-- DEFINER below), which already enforces the permission + dedup checks; this
-- policy is defense in depth in case something ever inserts directly.
drop policy if exists page_follow_invites_insert on public.page_follow_invites;
create policy page_follow_invites_insert on public.page_follow_invites
  for insert with check (
    inviter_id = auth.uid()
    and public.current_user_has_page_permission(page_id, 'manage_content')
  );

grant select, insert on public.page_follow_invites to authenticated;

create or replace function public.notify_page_follow_invite()
returns trigger
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_page_name text;
begin
  select name into v_page_name from public.pages where id = new.page_id;
  insert into public.notifications (recipient_id, actor_id, type, metadata)
  values (new.invitee_id, new.inviter_id, 'page_follow_invite',
    jsonb_build_object('page_id', new.page_id, 'page_name', v_page_name, 'invite_id', new.id));
  return new;
end;
$$;

drop trigger if exists trg_notify_page_follow_invite on public.page_follow_invites;
create trigger trg_notify_page_follow_invite
  after insert on public.page_follow_invites
  for each row execute function public.notify_page_follow_invite();

-- Callable RPC: invites a batch of users (by @username, matching the
-- add_page_team_member UX in 075) to follow a page. Skips unknown
-- usernames, anyone already following, and duplicate invites (unique
-- constraint); returns how many new invites were actually created.
create or replace function public.invite_users_to_follow_page(p_page_id uuid, p_usernames text[])
returns integer
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_count integer;
begin
  if not public.current_user_has_page_permission(p_page_id, 'manage_content') then
    raise exception 'Not authorized to invite followers for this page.';
  end if;

  insert into public.page_follow_invites (page_id, inviter_id, invitee_id)
  select p_page_id, auth.uid(), u.id
  from unnest(p_usernames) as raw_username
  join public.users u on lower(u.username) = lower(trim(leading '@' from raw_username))
  where u.id <> auth.uid()
    and not exists (select 1 from public.page_followers pf where pf.page_id = p_page_id and pf.user_id = u.id)
  on conflict (page_id, invitee_id) do nothing;

  get diagnostics v_count = row_count;

  if v_count > 0 then
    perform public.log_page_audit_event(p_page_id, 'followers_invited', 'invite_batch', null, jsonb_build_object('invited_count', v_count));
  end if;

  return v_count;
end;
$$;

grant execute on function public.invite_users_to_follow_page(uuid, text[]) to authenticated;

-- 4. Follower analytics ---------------------------------------------------------
-- Both gated behind view_analytics (not just any team member) since a
-- follower roster is more sensitive than the public follower_count.

create or replace function public.get_page_follower_stats(p_page_id uuid)
returns table(total_followers bigint, new_last_7d bigint, new_last_30d bigint)
language plpgsql
security definer
set search_path = 'public'
as $$
begin
  if not public.current_user_has_page_permission(p_page_id, 'view_analytics') then
    raise exception 'Not authorized to view follower analytics for this page.';
  end if;

  return query
  select
    count(*)::bigint,
    count(*) filter (where created_at >= now() - interval '7 days')::bigint,
    count(*) filter (where created_at >= now() - interval '30 days')::bigint
  from public.page_followers
  where page_id = p_page_id;
end;
$$;

grant execute on function public.get_page_follower_stats(uuid) to authenticated;

create or replace function public.list_page_followers(p_page_id uuid, p_limit integer default 50, p_offset integer default 0)
returns table(
  user_id uuid,
  username text,
  display_name text,
  profile_photo_url text,
  notify boolean,
  followed_at timestamptz
)
language plpgsql
security definer
set search_path = 'public'
as $$
begin
  if not public.current_user_has_page_permission(p_page_id, 'view_analytics') then
    raise exception 'Not authorized to view followers for this page.';
  end if;

  return query
  select u.id, u.username, u.display_name, u.profile_photo_url, pf.notify, pf.created_at
  from public.page_followers pf
  join public.users u on u.id = pf.user_id
  where pf.page_id = p_page_id
  order by pf.created_at desc
  limit greatest(p_limit, 0)
  offset greatest(p_offset, 0);
end;
$$;

grant execute on function public.list_page_followers(uuid, integer, integer) to authenticated;
