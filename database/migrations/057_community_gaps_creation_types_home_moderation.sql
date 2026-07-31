-- 057_community_gaps_creation_types_home_moderation.sql
-- Closes gaps flagged in the Step-1 audit re-check:
--   Community Creation: location, website, language, age restriction,
--     explicit posting-permission (now actually enforced, not decorative),
--     paid-community scaffolding, name-availability check.
--   Community Types: 'secret' (hidden from discovery) and 'invite_only'
--     (visible, but no join-request path) added alongside public/private.
--   Community Home: pinned announcement, activity summary (no "online
--     members" here — that's a Realtime Presence feature, client-side only,
--     tracked as a follow-up rather than a schema change).
--   Moderation: keyword filters can now be community-scoped (global filters
--     still apply everywhere), and moderator notes can be attached to a
--     community's own moderation history.
-- Image cropping (Step 3) is a client-side UI feature with no DB
-- component — not addressed here, tracked separately.

-- 1. New communities columns -------------------------------------------
alter table public.communities
  add column if not exists location text,
  add column if not exists website text,
  add column if not exists language text not null default 'en' check (language in ('en', 'ne')),
  add column if not exists min_age integer check (min_age is null or min_age between 13 and 21),
  add column if not exists posting_permission text not null default 'all_members'
    check (posting_permission in ('all_members', 'trusted_and_above', 'admins_only')),
  add column if not exists is_paid boolean not null default false,
  add column if not exists price_cents integer check (price_cents is null or price_cents >= 0),
  add column if not exists pinned_announcement_post_id uuid references public.posts(id) on delete set null;

comment on column public.communities.is_paid is 'Future-ready scaffolding only — no billing/entitlement enforcement exists yet.';
comment on column public.communities.posting_permission is 'Mirrors the post_content permission overrides this sets via set_community_posting_permission() — the actual enforcement lives in the posts_insert RLS policy, this column is just the human-readable label for it.';

-- 2. Community types: secret, invite_only --------------------------------
alter table public.communities drop constraint if exists communities_visibility_check;
alter table public.communities add constraint communities_visibility_check
  check (visibility in ('public', 'private', 'secret', 'invite_only'));

comment on column public.communities.visibility is
  'public = listed, instant join. private = listed, join requires approval. '
  'secret = hidden from listings/search entirely (members/invitees only). '
  'invite_only = listed and visible, but no join-request path — only direct invite or link.';

-- Hide 'secret' communities from non-members in the general SELECT policy.
-- (private/public/invite_only stay exactly as visible as before — this is
-- the one visibility value that changes discoverability, per 049's own
-- comment that private communities are intentionally still "listed".)
drop policy if exists communities_select_beta on public.communities;
create policy communities_select_beta on public.communities for select using (
  public.current_user_has_beta_access()
  and (
    visibility <> 'secret'
    or is_admin_or_mod()
    or exists (
      select 1 from public.community_memberships m where m.community_id = communities.id and m.user_id = auth.uid()
    )
    or exists (
      select 1 from public.community_invites i
      where i.community_id = communities.id and i.invited_user_id = auth.uid() and i.revoked_at is null
    )
  )
);

-- request_join_community: secret/invite_only have no join-request path.
create or replace function public.request_join_community(p_community_id uuid, p_message text default null)
returns text
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_visibility text;
begin
  if not current_user_has_beta_access() then
    raise exception 'Beta access required';
  end if;

  if public.is_banned_from_community(p_community_id, auth.uid()) then
    raise exception 'You are banned from this community';
  end if;

  select visibility into v_visibility from public.communities where id = p_community_id;
  if v_visibility is null then
    raise exception 'Community not found';
  end if;

  if v_visibility = 'public' then
    insert into public.community_memberships (community_id, user_id, role)
    values (p_community_id, auth.uid(), 'member')
    on conflict (community_id, user_id) do nothing;
    return 'joined';
  end if;

  if v_visibility in ('secret', 'invite_only') then
    raise exception 'This community is invite-only — ask a member for an invite or invite link';
  end if;

  -- Private: already a member?
  if exists (
    select 1 from public.community_memberships
    where community_id = p_community_id and user_id = auth.uid()
  ) then
    return 'already_member';
  end if;

  insert into public.community_join_requests (community_id, user_id, message, status)
  values (p_community_id, auth.uid(), p_message, 'pending')
  on conflict (community_id, user_id)
  do update set status = 'pending', message = excluded.message, decided_by = null, decided_at = null, created_at = now()
  where community_join_requests.status = 'rejected';
  return 'requested';
end;
$$;

grant execute on function public.request_join_community(uuid, text) to authenticated;

-- 3. Name-availability check (for the create-community screen) -----------
create or replace function public.is_community_name_available(p_name text)
returns boolean
language sql
stable
security definer
set search_path = 'public'
as $$
  select not exists (select 1 from public.communities where lower(name) = lower(trim(p_name)));
$$;

grant execute on function public.is_community_name_available(text) to authenticated;

-- 4. Posting permission: make it real, not decorative ----------------------
-- Reuses the existing permission-override mechanism from 052 instead of a
-- parallel enforcement path: setting a posting_permission tier just writes
-- the corresponding post_content overrides.
create or replace function public.set_community_posting_permission(p_community_id uuid, p_permission text)
returns void
language plpgsql
security definer
set search_path = 'public'
as $$
begin
  if p_permission not in ('all_members', 'trusted_and_above', 'admins_only') then
    raise exception 'Invalid posting permission: %', p_permission;
  end if;
  if not public.current_user_community_permission(p_community_id, 'manage_settings') then
    raise exception 'Not authorized to change this community''s posting permission';
  end if;

  update public.communities set posting_permission = p_permission where id = p_community_id;

  -- Reset to defaults first, then layer overrides for the chosen tier.
  delete from public.community_permission_overrides
  where community_id = p_community_id and permission_key = 'post_content' and role in ('member', 'trusted_member', 'moderator');

  if p_permission = 'trusted_and_above' then
    insert into public.community_permission_overrides (community_id, role, permission_key, allowed, updated_by)
    values (p_community_id, 'member', 'post_content', false, auth.uid());
  elsif p_permission = 'admins_only' then
    insert into public.community_permission_overrides (community_id, role, permission_key, allowed, updated_by)
    values
      (p_community_id, 'member', 'post_content', false, auth.uid()),
      (p_community_id, 'trusted_member', 'post_content', false, auth.uid()),
      (p_community_id, 'moderator', 'post_content', false, auth.uid());
  end if;

  perform public.log_community_audit(p_community_id, 'settings_changed', null, jsonb_build_object('posting_permission', p_permission));
end;
$$;

grant execute on function public.set_community_posting_permission(uuid, text) to authenticated;

-- Actually enforce membership + posting permission at insert time. Today
-- there is NO check at all tying a post's community_id to the author's
-- membership/permission in that community — any active user can insert a
-- post with any community_id. Closing that here.
drop policy if exists posts_insert_self_active_beta on public.posts;
create policy posts_insert_self_active_beta on public.posts for insert with check (
  author_id = auth.uid()
  and public.current_user_is_active()
  and public.current_user_has_beta_access()
  and (community_id is null or public.current_user_community_permission(community_id, 'post_content'))
);

-- 5. Pinned announcement ----------------------------------------------------
create or replace function public.set_community_announcement(p_community_id uuid, p_post_id uuid)
returns void
language plpgsql
security definer
set search_path = 'public'
as $$
begin
  if not public.current_user_community_permission(p_community_id, 'manage_posts') then
    raise exception 'Not authorized to set this community''s announcement';
  end if;

  if p_post_id is not null and not exists (
    select 1 from public.posts where id = p_post_id and community_id = p_community_id
  ) then
    raise exception 'That post does not belong to this community';
  end if;

  update public.communities set pinned_announcement_post_id = p_post_id where id = p_community_id;
  perform public.log_community_audit(p_community_id, 'settings_changed', null, jsonb_build_object('pinned_announcement_post_id', p_post_id));
end;
$$;

grant execute on function public.set_community_announcement(uuid, uuid) to authenticated;

-- 6. Activity summary --------------------------------------------------------
create or replace function public.get_community_activity_summary(p_community_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = 'public'
as $$
  select jsonb_build_object(
    'posts_last_24h', (select count(*) from public.posts where community_id = p_community_id and created_at > now() - interval '24 hours' and is_removed = false),
    'posts_last_7d', (select count(*) from public.posts where community_id = p_community_id and created_at > now() - interval '7 days' and is_removed = false),
    'new_members_last_7d', (select count(*) from public.community_memberships where community_id = p_community_id and created_at > now() - interval '7 days'),
    'total_posts', (select count(*) from public.posts where community_id = p_community_id and is_removed = false)
  );
$$;

grant execute on function public.get_community_activity_summary(uuid) to authenticated;

-- 7. Community-scoped keyword filters ---------------------------------------
alter table public.keyword_filters add column if not exists community_id uuid references public.communities(id) on delete cascade;
create index if not exists idx_keyword_filters_community on public.keyword_filters (community_id) where community_id is not null;

comment on column public.keyword_filters.community_id is 'null = global filter (applies everywhere). Set = applies only within that community, in addition to all global filters.';

drop policy if exists keyword_filters_select_community_mod on public.keyword_filters;
create policy keyword_filters_select_community_mod on public.keyword_filters for select using (
  is_admin_or_mod()
  or (community_id is not null and current_user_community_permission(community_id, 'manage_reports'))
);

create or replace function public.check_keyword_filters(content text, p_community_id uuid default null)
returns table(keyword text, severity text, category public.report_category)
language sql
stable
security definer
set search_path = public
as $$
  select kf.keyword, kf.severity, kf.category
  from public.keyword_filters kf
  where kf.is_active
    and (kf.community_id is null or kf.community_id = p_community_id)
    and content ilike '%' || kf.keyword || '%'
  order by kf.severity desc
  limit 5;
$$;

grant execute on function public.check_keyword_filters(text, uuid) to authenticated;

create or replace function public.add_community_keyword_filter(
  p_community_id uuid, p_keyword text, p_category public.report_category default 'other', p_severity text default 'flag'
)
returns uuid
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_id uuid;
begin
  if not public.current_user_community_permission(p_community_id, 'manage_reports') then
    raise exception 'Not authorized to add keyword filters for this community';
  end if;
  if p_severity not in ('flag', 'block') then
    raise exception 'Invalid severity: %', p_severity;
  end if;

  insert into public.keyword_filters (community_id, keyword, category, severity, created_by)
  values (p_community_id, lower(trim(p_keyword)), p_category, p_severity, auth.uid())
  returning id into v_id;

  return v_id;
end;
$$;

grant execute on function public.add_community_keyword_filter(uuid, text, public.report_category, text) to authenticated;

-- Update the auto-moderation triggers to pass the post's community_id
-- through, so community-scoped filters actually get consulted.
create or replace function public.auto_moderate_post_block()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if exists (
    select 1 from public.check_keyword_filters(coalesce(new.text_content, ''), new.community_id) k where k.severity = 'block'
  ) then
    raise exception 'This post was blocked by automated content moderation' using errcode = 'P0001';
  end if;
  return new;
end;
$$;

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
  from public.check_keyword_filters(coalesce(new.text_content, ''), new.community_id) k
  where k.severity = 'flag'
  limit 1;

  if matched.keyword is not null then
    insert into public.reports(reporter_id, target_type, target_post_id, reason, category, status, is_automated)
    values (new.author_id, 'post', new.id, format('Auto-flagged by keyword filter: "%s"', matched.keyword), matched.category, 'open', true);
  end if;
  return new;
end;
$$;

-- 8. Community-scoped moderator notes ----------------------------------------
create table if not exists public.community_moderator_notes (
  id uuid primary key default gen_random_uuid(),
  community_id uuid not null references public.communities(id) on delete cascade,
  moderator_id uuid references public.users(id) on delete set null,
  target_type text not null check (target_type in ('user', 'post')),
  target_user_id uuid references public.users(id) on delete cascade,
  target_post_id uuid references public.posts(id) on delete cascade,
  note text not null,
  created_at timestamptz not null default now(),
  constraint community_moderator_notes_target_shape check (
    (target_type = 'user' and target_user_id is not null and target_post_id is null)
    or
    (target_type = 'post' and target_post_id is not null and target_user_id is null)
  )
);

create index if not exists idx_community_moderator_notes_community on public.community_moderator_notes (community_id, created_at desc);

alter table public.community_moderator_notes enable row level security;

drop policy if exists community_moderator_notes_select on public.community_moderator_notes;
create policy community_moderator_notes_select on public.community_moderator_notes for select using (
  is_admin_or_mod() or current_user_community_permission(community_id, 'manage_reports')
);

grant select on public.community_moderator_notes to authenticated;

create or replace function public.add_community_moderator_note(
  p_community_id uuid, p_target_type text, p_target_user_id uuid, p_target_post_id uuid, p_note text
)
returns uuid
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_id uuid;
begin
  if not public.current_user_community_permission(p_community_id, 'manage_reports') then
    raise exception 'Not authorized to add moderator notes for this community';
  end if;
  if p_note is null or length(trim(p_note)) = 0 then
    raise exception 'Note cannot be empty';
  end if;

  insert into public.community_moderator_notes (community_id, moderator_id, target_type, target_user_id, target_post_id, note)
  values (p_community_id, auth.uid(), p_target_type, p_target_user_id, p_target_post_id, trim(p_note))
  returning id into v_id;

  return v_id;
end;
$$;

grant execute on function public.add_community_moderator_note(uuid, text, uuid, uuid, text) to authenticated;
