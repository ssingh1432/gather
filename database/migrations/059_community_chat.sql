-- 059_community_chat.sql
-- Community System Step 10: realtime group chat per community.
-- Messages, media attachments, replies, pinned messages/announcements,
-- and read receipts. Typing indicators are NOT a table — they use
-- Supabase Realtime Broadcast (ephemeral, client-to-client, no DB writes),
-- consistent with best practice for high-frequency, disposable signals.
--
-- Reuses existing infra rather than re-inventing it:
--   - current_user_community_permission() (052) for who can send/moderate
--   - is_member_of_community() (051) for read access, safe from recursion
--   - is_admin_or_mod() (site-wide) for site admin/mod override
--   - user_blocks for filtering blocked users out of the message stream

-- ===========================================================================
-- 1. New permission: manage_chat
--    Ordinary sending reuses the existing 'comment' permission (member and
--    trusted_member already have it) so no new grant is needed for that.
--    manage_chat covers: pin/unpin, delete another member's message, and
--    post announcements.
-- ===========================================================================
insert into public.community_permissions (key, label, description) values
  ('manage_chat', 'Manage chat', 'Pin or unpin messages, delete other members'' messages, and post chat announcements.')
on conflict (key) do nothing;

insert into public.community_role_permissions (role, permission_key, allowed)
select r.role, 'manage_chat', true
from (values ('owner'), ('admin'), ('moderator')) as r(role)
on conflict (role, permission_key) do nothing;

-- ===========================================================================
-- 2. Tables
-- ===========================================================================
create table if not exists public.community_chat_messages (
  id uuid primary key default gen_random_uuid(),
  community_id uuid not null references public.communities(id) on delete cascade,
  sender_id uuid not null references public.users(id) on delete cascade,
  content text,
  reply_to_id uuid references public.community_chat_messages(id) on delete set null,
  is_announcement boolean not null default false,
  is_pinned boolean not null default false,
  pinned_by uuid references public.users(id) on delete set null,
  pinned_at timestamptz,
  is_deleted boolean not null default false,
  deleted_by uuid references public.users(id) on delete set null,
  deleted_at timestamptz,
  edited_at timestamptz,
  created_at timestamptz not null default now()
);

comment on table public.community_chat_messages is
  'Group chat messages for a community. Soft-deleted (is_deleted) rather than hard-deleted so reply threads and pin history stay intact; content is nulled out to clients once deleted.';

create index if not exists idx_chat_messages_feed on public.community_chat_messages (community_id, created_at desc);
create index if not exists idx_chat_messages_pinned on public.community_chat_messages (community_id, pinned_at desc) where is_pinned = true and is_deleted = false;
create index if not exists idx_chat_messages_reply on public.community_chat_messages (reply_to_id);

alter table public.community_chat_messages replica identity full;

create table if not exists public.community_chat_message_media (
  id uuid primary key default gen_random_uuid(),
  message_id uuid not null references public.community_chat_messages(id) on delete cascade,
  media_url text not null,
  media_type text not null check (media_type in ('image', 'video', 'file')),
  file_name text,
  file_size_bytes bigint,
  position integer not null default 0,
  created_at timestamptz not null default now()
);

create index if not exists idx_chat_media_message on public.community_chat_message_media (message_id, position);
alter table public.community_chat_message_media replica identity full;

create table if not exists public.community_chat_read_state (
  community_id uuid not null references public.communities(id) on delete cascade,
  user_id uuid not null references public.users(id) on delete cascade,
  last_read_message_id uuid references public.community_chat_messages(id) on delete set null,
  last_read_at timestamptz not null default now(),
  primary key (community_id, user_id)
);

create index if not exists idx_chat_read_state_user on public.community_chat_read_state (user_id);

comment on table public.community_chat_read_state is
  'Read-up-to marker per (community, user) — the standard scalable read-receipt pattern (Slack/Discord-style "read up to X"), not a per-message read-by list, which would not scale to large communities.';

-- ===========================================================================
-- 3. RLS
-- ===========================================================================
alter table public.community_chat_messages enable row level security;
alter table public.community_chat_message_media enable row level security;
alter table public.community_chat_read_state enable row level security;

-- community_chat_messages ---------------------------------------------------
drop policy if exists chat_messages_select on public.community_chat_messages;
create policy chat_messages_select on public.community_chat_messages
  for select using (
    current_user_has_beta_access()
    and (is_admin_or_mod() or is_member_of_community(community_id))
  );

drop policy if exists chat_messages_insert on public.community_chat_messages;
create policy chat_messages_insert on public.community_chat_messages
  for insert with check (
    current_user_has_beta_access()
    and sender_id = auth.uid()
    and not is_deleted
    and (
      (is_announcement and current_user_community_permission(community_id, 'manage_chat'))
      or (not is_announcement and current_user_community_permission(community_id, 'comment'))
    )
  );

-- Sender can edit their own (not-yet-deleted) message content.
drop policy if exists chat_messages_update_own on public.community_chat_messages;
create policy chat_messages_update_own on public.community_chat_messages
  for update using (sender_id = auth.uid() and not is_deleted)
  with check (sender_id = auth.uid());

-- Moderators (manage_chat) or site admin/mod can pin/unpin or soft-delete
-- any message in the community.
drop policy if exists chat_messages_update_moderate on public.community_chat_messages;
create policy chat_messages_update_moderate on public.community_chat_messages
  for update using (
    is_admin_or_mod() or current_user_community_permission(community_id, 'manage_chat')
  )
  with check (true);

-- community_chat_message_media ----------------------------------------------
drop policy if exists chat_media_select on public.community_chat_message_media;
create policy chat_media_select on public.community_chat_message_media
  for select using (
    exists (
      select 1 from public.community_chat_messages m
      where m.id = message_id
        and current_user_has_beta_access()
        and (is_admin_or_mod() or is_member_of_community(m.community_id))
    )
  );

drop policy if exists chat_media_insert on public.community_chat_message_media;
create policy chat_media_insert on public.community_chat_message_media
  for insert with check (
    exists (select 1 from public.community_chat_messages m where m.id = message_id and m.sender_id = auth.uid())
  );

-- community_chat_read_state --------------------------------------------------
drop policy if exists chat_read_state_select on public.community_chat_read_state;
create policy chat_read_state_select on public.community_chat_read_state
  for select using (
    user_id = auth.uid()
    or is_admin_or_mod()
    or current_user_community_permission(community_id, 'manage_chat')
  );

drop policy if exists chat_read_state_insert on public.community_chat_read_state;
create policy chat_read_state_insert on public.community_chat_read_state
  for insert with check (user_id = auth.uid() and is_member_of_community(community_id));

drop policy if exists chat_read_state_update on public.community_chat_read_state;
create policy chat_read_state_update on public.community_chat_read_state
  for update using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ===========================================================================
-- 4. Grants — table-level GRANTs are checked before RLS ever runs; missing
--    these silently breaks everything (the exact bug fixed for 19 other
--    tables in migration 041). Not repeating that mistake here.
-- ===========================================================================
grant select, insert, update on public.community_chat_messages to authenticated;
grant select, insert on public.community_chat_message_media to authenticated;
grant select, insert, update on public.community_chat_read_state to authenticated;

-- ===========================================================================
-- 5. Realtime
-- ===========================================================================
do $$
begin
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and tablename = 'community_chat_messages') then
    alter publication supabase_realtime add table public.community_chat_messages;
  end if;
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and tablename = 'community_chat_message_media') then
    alter publication supabase_realtime add table public.community_chat_message_media;
  end if;
end $$;

-- ===========================================================================
-- 6. RPCs
-- ===========================================================================

-- Paginated (cursor-by-created_at) message fetch with sender info, media,
-- reply preview, and blocked-user filtering in one round trip.
-- security invoker (default) so the underlying SELECT is still gated by
-- the RLS policies above — this function does not widen access.
create or replace function public.get_community_chat_messages(
  p_community_id uuid,
  p_before timestamptz default null,
  p_limit integer default 40,
  p_pinned_only boolean default false
)
returns table (
  id uuid, community_id uuid, sender_id uuid, sender_username text, sender_avatar_url text,
  content text, is_announcement boolean, is_pinned boolean, is_deleted boolean,
  edited_at timestamptz, created_at timestamptz,
  reply_to_id uuid, reply_to_sender_username text, reply_to_content text, reply_to_removed boolean,
  media jsonb
)
language sql
stable
set search_path = 'public'
as $$
  select
    m.id, m.community_id, m.sender_id, u.username as sender_username, u.profile_photo_url as sender_avatar_url,
    case when m.is_deleted then null else m.content end as content,
    m.is_announcement, m.is_pinned, m.is_deleted, m.edited_at, m.created_at,
    m.reply_to_id, ru.username as reply_to_sender_username,
    case when rm.is_deleted then null else rm.content end as reply_to_content,
    (m.reply_to_id is not null and rm.id is null) as reply_to_removed,
    coalesce(media.media, '[]'::jsonb) as media
  from public.community_chat_messages m
  join public.users u on u.id = m.sender_id
  left join public.community_chat_messages rm on rm.id = m.reply_to_id
  left join public.users ru on ru.id = rm.sender_id
  left join lateral (
    select jsonb_agg(jsonb_build_object(
      'id', cm.id, 'media_url', cm.media_url, 'media_type', cm.media_type,
      'file_name', cm.file_name, 'file_size_bytes', cm.file_size_bytes
    ) order by cm.position) as media
    from public.community_chat_message_media cm where cm.message_id = m.id
  ) media on true
  where m.community_id = p_community_id
    and (p_before is null or m.created_at < p_before)
    and (not p_pinned_only or (m.is_pinned and not m.is_deleted))
    and not exists (
      select 1 from public.user_blocks ub
      where (ub.blocker_id = auth.uid() and ub.blocked_id = m.sender_id)
         or (ub.blocker_id = m.sender_id and ub.blocked_id = auth.uid())
    )
  order by m.created_at desc
  limit least(greatest(coalesce(p_limit, 40), 1), 100);
$$;

grant execute on function public.get_community_chat_messages(uuid, timestamptz, integer, boolean) to authenticated;

-- Unread count for a single community, based on the read-state marker.
create or replace function public.get_community_chat_unread_count(p_community_id uuid)
returns integer
language sql
stable
set search_path = 'public'
as $$
  select count(*)::integer
  from public.community_chat_messages m
  where m.community_id = p_community_id
    and m.is_deleted = false
    and m.sender_id <> auth.uid()
    and m.created_at > coalesce(
      (select last_read_at from public.community_chat_read_state r
       where r.community_id = p_community_id and r.user_id = auth.uid()),
      'epoch'::timestamptz
    );
$$;

grant execute on function public.get_community_chat_unread_count(uuid) to authenticated;

-- Mark a community's chat as read up to a given message. Upsert wrapped in
-- an RPC (rather than a raw upsert from the client) so it can double as a
-- single round trip that also returns the new unread count (0).
create or replace function public.mark_community_chat_read(p_community_id uuid, p_last_message_id uuid default null)
returns void
language plpgsql
security definer
set search_path = 'public'
as $$
begin
  if not is_member_of_community(p_community_id) and not is_admin_or_mod() then
    raise exception 'Not a member of this community' using errcode = '42501';
  end if;

  insert into public.community_chat_read_state (community_id, user_id, last_read_message_id, last_read_at)
  values (p_community_id, auth.uid(), p_last_message_id, now())
  on conflict (community_id, user_id)
  do update set last_read_message_id = coalesce(excluded.last_read_message_id, community_chat_read_state.last_read_message_id),
                last_read_at = now();
end;
$$;

grant execute on function public.mark_community_chat_read(uuid, uuid) to authenticated;

-- ===========================================================================
-- 7. Storage bucket for chat media (images / short videos / files).
--    Deliberately private (public = false) — unlike community-media
--    (avatars/banners, meant to be publicly viewable for discovery), chat
--    content should only be reachable by members even if a URL leaks.
--    Path convention: {community_id}/{sender_id}/{filename}
-- ===========================================================================
insert into storage.buckets (id, name, public, file_size_limit)
values ('community-chat-media', 'community-chat-media', false, 15728640) -- 15MB
on conflict (id) do nothing;

drop policy if exists "Community members can upload chat media" on storage.objects;
create policy "Community members can upload chat media" on storage.objects
  for insert with check (
    bucket_id = 'community-chat-media'
    and is_member_of_community(((storage.foldername(name))[1])::uuid)
    and (storage.foldername(name))[2] = auth.uid()::text
  );

drop policy if exists "Community members can view chat media" on storage.objects;
create policy "Community members can view chat media" on storage.objects
  for select using (
    bucket_id = 'community-chat-media'
    and (is_admin_or_mod() or is_member_of_community(((storage.foldername(name))[1])::uuid))
  );

drop policy if exists "Senders can delete their own chat media" on storage.objects;
create policy "Senders can delete their own chat media" on storage.objects
  for delete using (
    bucket_id = 'community-chat-media'
    and (storage.foldername(name))[2] = auth.uid()::text
  );
