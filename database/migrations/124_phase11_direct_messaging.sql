-- 124_phase11_direct_messaging.sql
-- Phase 11 (Messaging): 1:1 direct messages.
--
-- Adds: conversations + per-member state (read/delivered cursors, pin,
-- archive, mute, clear), messages (text / image / video / file / voice),
-- reply, forward, reactions, delete-for-me, delete-for-everyone, a private
-- storage bucket, public-key registry for end-to-end encrypted text, and a
-- "who can message me" privacy setting.
--
-- Design notes
--   * Writes to dm_messages go ONLY through send_dm_message() (SECURITY
--     DEFINER). Authenticated clients get SELECT on the tables, nothing else,
--     so block / privacy / rate-limit checks cannot be bypassed.
--   * Read + delivered receipts are per-member cursors (last_read_at,
--     last_delivered_at). In a 1:1 chat that is exact and cheap.
--   * Typing indicators are NOT stored; they use Realtime Broadcast.
--   * E2EE: text bodies may be sent as ciphertext (enc_version = 1,
--     X25519 + AES-256-GCM, done on the client). The server stores only
--     ciphertext + nonce and each user's PUBLIC key. Media files are stored
--     in a private bucket (TLS + encryption at rest) but are not E2EE.
--
-- Manual apply required: CI does not run migrations.

-- =====================================================================
-- 1. Privacy setting
-- =====================================================================
alter table public.users add column if not exists dm_privacy text not null default 'everyone';
alter table public.users drop constraint if exists users_dm_privacy_check;
alter table public.users add constraint users_dm_privacy_check
  check (dm_privacy in ('everyone', 'following', 'nobody'));

comment on column public.users.dm_privacy is
  'Who may start/continue a DM with this user: everyone | following (only people this user follows) | nobody.';

-- =====================================================================
-- 2. Tables
-- =====================================================================
create table if not exists public.dm_conversations (
  id uuid primary key default gen_random_uuid(),
  user_a uuid not null references public.users(id) on delete cascade,
  user_b uuid not null references public.users(id) on delete cascade,
  last_message_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  constraint dm_conversations_ordered check (user_a < user_b),
  constraint dm_conversations_unique_pair unique (user_a, user_b)
);

create index if not exists idx_dm_conversations_user_a on public.dm_conversations (user_a, last_message_at desc);
create index if not exists idx_dm_conversations_user_b on public.dm_conversations (user_b, last_message_at desc);

create table if not exists public.dm_conversation_members (
  conversation_id uuid not null references public.dm_conversations(id) on delete cascade,
  user_id uuid not null references public.users(id) on delete cascade,
  last_read_at timestamptz not null default now(),
  last_delivered_at timestamptz not null default now(),
  is_pinned boolean not null default false,
  is_archived boolean not null default false,
  muted_until timestamptz,
  cleared_at timestamptz,
  primary key (conversation_id, user_id)
);

create index if not exists idx_dm_members_user on public.dm_conversation_members (user_id);

create table if not exists public.dm_messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.dm_conversations(id) on delete cascade,
  sender_id uuid not null references public.users(id) on delete cascade,
  kind text not null default 'text' check (kind in ('text', 'image', 'video', 'file', 'voice')),
  body text,
  ciphertext text,
  nonce text,
  enc_version smallint not null default 0 check (enc_version in (0, 1)),
  reply_to_id uuid references public.dm_messages(id) on delete set null,
  is_forwarded boolean not null default false,
  media_path text,
  media_name text,
  media_size_bytes bigint,
  media_mime text,
  duration_ms integer,
  created_at timestamptz not null default now(),
  deleted_at timestamptz,
  deleted_by uuid references public.users(id) on delete set null,
  constraint dm_messages_text_len check (body is null or char_length(body) <= 4000),
  constraint dm_messages_cipher_len check (ciphertext is null or char_length(ciphertext) <= 12000),
  constraint dm_messages_voice_len check (duration_ms is null or (duration_ms >= 0 and duration_ms <= 300000))
);

create index if not exists idx_dm_messages_feed on public.dm_messages (conversation_id, created_at desc);
create index if not exists idx_dm_messages_reply on public.dm_messages (reply_to_id);
alter table public.dm_messages replica identity full;
alter table public.dm_conversation_members replica identity full;

create table if not exists public.dm_message_hidden (
  message_id uuid not null references public.dm_messages(id) on delete cascade,
  user_id uuid not null references public.users(id) on delete cascade,
  hidden_at timestamptz not null default now(),
  primary key (message_id, user_id)
);

create table if not exists public.dm_message_reactions (
  message_id uuid not null references public.dm_messages(id) on delete cascade,
  user_id uuid not null references public.users(id) on delete cascade,
  emoji text not null check (char_length(emoji) between 1 and 16),
  created_at timestamptz not null default now(),
  primary key (message_id, user_id, emoji)
);
alter table public.dm_message_reactions replica identity full;

create table if not exists public.dm_user_keys (
  user_id uuid primary key references public.users(id) on delete cascade,
  public_key text not null check (char_length(public_key) between 40 and 64),
  key_version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.dm_user_keys is
  'X25519 PUBLIC keys (base64) for end-to-end encrypted DMs. Private keys never leave the device.';

-- =====================================================================
-- 3. Helpers
-- =====================================================================
create or replace function public.is_dm_member(p_conversation uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.dm_conversation_members m
    where m.conversation_id = p_conversation and m.user_id = auth.uid()
  );
$$;

-- Raises if p_sender may not message p_recipient (block either way, privacy).
create or replace function public.dm_assert_can_message(p_sender uuid, p_recipient uuid)
returns void
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_privacy text;
begin
  if exists (
    select 1 from public.user_blocks ub
    where (ub.blocker_id = p_sender and ub.blocked_id = p_recipient)
       or (ub.blocker_id = p_recipient and ub.blocked_id = p_sender)
  ) then
    raise exception 'dm_blocked' using errcode = 'P0001';
  end if;

  select u.dm_privacy into v_privacy from public.users u where u.id = p_recipient;
  if v_privacy is null then
    raise exception 'dm_recipient_not_found' using errcode = 'P0001';
  end if;
  if v_privacy = 'nobody' then
    raise exception 'dm_not_allowed' using errcode = 'P0001';
  end if;
  if v_privacy = 'following' and not exists (
    select 1 from public.user_follows f
    where f.follower_id = p_recipient and f.following_id = p_sender
  ) then
    raise exception 'dm_not_allowed' using errcode = 'P0001';
  end if;
end;
$$;

-- =====================================================================
-- 4. RLS + grants (read-only for clients; all writes via RPC)
-- =====================================================================
alter table public.dm_conversations enable row level security;
alter table public.dm_conversation_members enable row level security;
alter table public.dm_messages enable row level security;
alter table public.dm_message_hidden enable row level security;
alter table public.dm_message_reactions enable row level security;
alter table public.dm_user_keys enable row level security;

drop policy if exists dm_conversations_select on public.dm_conversations;
create policy dm_conversations_select on public.dm_conversations
  for select using (auth.uid() = user_a or auth.uid() = user_b);

drop policy if exists dm_members_select on public.dm_conversation_members;
create policy dm_members_select on public.dm_conversation_members
  for select using (public.is_dm_member(conversation_id));

drop policy if exists dm_messages_select on public.dm_messages;
create policy dm_messages_select on public.dm_messages
  for select using (public.is_dm_member(conversation_id));

drop policy if exists dm_hidden_select on public.dm_message_hidden;
create policy dm_hidden_select on public.dm_message_hidden
  for select using (user_id = auth.uid());

drop policy if exists dm_reactions_select on public.dm_message_reactions;
create policy dm_reactions_select on public.dm_message_reactions
  for select using (
    exists (
      select 1 from public.dm_messages m
      where m.id = message_id and public.is_dm_member(m.conversation_id)
    )
  );

-- Public keys are public by design.
drop policy if exists dm_keys_select on public.dm_user_keys;
create policy dm_keys_select on public.dm_user_keys
  for select to authenticated using (true);

revoke all on public.dm_conversations, public.dm_conversation_members, public.dm_messages,
  public.dm_message_hidden, public.dm_message_reactions, public.dm_user_keys from anon, authenticated;
grant select on public.dm_conversations, public.dm_conversation_members, public.dm_messages,
  public.dm_message_hidden, public.dm_message_reactions, public.dm_user_keys to authenticated;

-- =====================================================================
-- 5. RPCs
-- =====================================================================
create or replace function public.get_or_create_dm_conversation(p_other uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me uuid := auth.uid();
  v_a uuid;
  v_b uuid;
  v_id uuid;
begin
  if v_me is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  if p_other is null or p_other = v_me then raise exception 'dm_invalid_recipient' using errcode = 'P0001'; end if;
  if not public.current_user_has_beta_access() then raise exception 'dm_not_allowed' using errcode = 'P0001'; end if;

  perform public.dm_assert_can_message(v_me, p_other);

  v_a := least(v_me, p_other);
  v_b := greatest(v_me, p_other);

  select c.id into v_id from public.dm_conversations c where c.user_a = v_a and c.user_b = v_b;
  if v_id is null then
    insert into public.dm_conversations (user_a, user_b) values (v_a, v_b)
    on conflict (user_a, user_b) do nothing
    returning id into v_id;
    if v_id is null then
      select c.id into v_id from public.dm_conversations c where c.user_a = v_a and c.user_b = v_b;
    end if;
    insert into public.dm_conversation_members (conversation_id, user_id)
    values (v_id, v_a), (v_id, v_b)
    on conflict do nothing;
  end if;
  return v_id;
end;
$$;

create or replace function public.send_dm_message(
  p_conversation uuid,
  p_kind text default 'text',
  p_body text default null,
  p_ciphertext text default null,
  p_nonce text default null,
  p_enc_version smallint default 0,
  p_reply_to uuid default null,
  p_media_path text default null,
  p_media_name text default null,
  p_media_size_bytes bigint default null,
  p_media_mime text default null,
  p_duration_ms integer default null,
  p_is_forwarded boolean default false
)
returns public.dm_messages
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me uuid := auth.uid();
  v_other uuid;
  v_row public.dm_messages;
  v_recent integer;
begin
  if v_me is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  if not public.current_user_has_beta_access() then raise exception 'dm_not_allowed' using errcode = 'P0001'; end if;

  select case when c.user_a = v_me then c.user_b else c.user_a end into v_other
  from public.dm_conversations c
  where c.id = p_conversation and (c.user_a = v_me or c.user_b = v_me);
  if v_other is null then raise exception 'dm_not_member' using errcode = '42501'; end if;

  perform public.dm_assert_can_message(v_me, v_other);

  select count(*) into v_recent from public.dm_messages m
  where m.sender_id = v_me and m.created_at > now() - interval '1 minute';
  if v_recent >= 30 then raise exception 'dm_rate_limited' using errcode = 'P0001'; end if;

  if p_kind not in ('text', 'image', 'video', 'file', 'voice') then
    raise exception 'dm_invalid_kind' using errcode = 'P0001';
  end if;

  if p_kind = 'text' then
    if p_enc_version = 1 then
      if p_ciphertext is null or p_nonce is null or p_body is not null then
        raise exception 'dm_invalid_message' using errcode = 'P0001';
      end if;
    else
      if p_body is null or char_length(btrim(p_body)) = 0 or p_ciphertext is not null then
        raise exception 'dm_invalid_message' using errcode = 'P0001';
      end if;
    end if;
  else
    -- Media must live under <conversation>/<sender>/ in the dm-media bucket.
    if p_media_path is null
       or p_media_path not like (p_conversation::text || '/' || v_me::text || '/%') then
      raise exception 'dm_invalid_media' using errcode = 'P0001';
    end if;
    if p_kind = 'voice' and (p_duration_ms is null or p_duration_ms <= 0) then
      raise exception 'dm_invalid_message' using errcode = 'P0001';
    end if;
  end if;

  if p_reply_to is not null and not exists (
    select 1 from public.dm_messages m where m.id = p_reply_to and m.conversation_id = p_conversation
  ) then
    raise exception 'dm_invalid_reply' using errcode = 'P0001';
  end if;

  insert into public.dm_messages (
    conversation_id, sender_id, kind, body, ciphertext, nonce, enc_version, reply_to_id,
    is_forwarded, media_path, media_name, media_size_bytes, media_mime, duration_ms
  ) values (
    p_conversation, v_me, p_kind, p_body, p_ciphertext, p_nonce, p_enc_version, p_reply_to,
    coalesce(p_is_forwarded, false), p_media_path, p_media_name, p_media_size_bytes, p_media_mime,
    p_duration_ms
  ) returning * into v_row;

  update public.dm_conversations set last_message_at = v_row.created_at where id = p_conversation;

  -- Sending implies the sender has read everything so far; a new message
  -- also un-archives the chat for the recipient.
  update public.dm_conversation_members
     set last_read_at = v_row.created_at, last_delivered_at = v_row.created_at
   where conversation_id = p_conversation and user_id = v_me;
  update public.dm_conversation_members
     set is_archived = false
   where conversation_id = p_conversation and user_id = v_other;

  return v_row;
end;
$$;

create or replace function public.mark_dm_delivered(p_conversation uuid)
returns void
language sql
security definer
set search_path = public
as $$
  update public.dm_conversation_members
     set last_delivered_at = greatest(last_delivered_at, now())
   where conversation_id = p_conversation and user_id = auth.uid();
$$;

create or replace function public.mark_dm_read(p_conversation uuid)
returns void
language sql
security definer
set search_path = public
as $$
  update public.dm_conversation_members
     set last_read_at = greatest(last_read_at, now()),
         last_delivered_at = greatest(last_delivered_at, now())
   where conversation_id = p_conversation and user_id = auth.uid();
$$;

-- Returns the stored media path so the client can remove the file too.
create or replace function public.delete_dm_message_for_everyone(p_message uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_path text;
begin
  select media_path into v_path from public.dm_messages
   where id = p_message and sender_id = auth.uid() and deleted_at is null;
  if not found then raise exception 'dm_not_allowed' using errcode = '42501'; end if;

  update public.dm_messages
     set deleted_at = now(), deleted_by = auth.uid(),
         body = null, ciphertext = null, nonce = null,
         media_path = null, media_name = null, media_size_bytes = null, media_mime = null
   where id = p_message;
  delete from public.dm_message_reactions where message_id = p_message;
  return v_path;
end;
$$;

create or replace function public.hide_dm_message_for_me(p_message uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (
    select 1 from public.dm_messages m where m.id = p_message and public.is_dm_member(m.conversation_id)
  ) then
    raise exception 'dm_not_member' using errcode = '42501';
  end if;
  insert into public.dm_message_hidden (message_id, user_id) values (p_message, auth.uid())
  on conflict do nothing;
end;
$$;

create or replace function public.clear_dm_conversation_for_me(p_conversation uuid)
returns void
language sql
security definer
set search_path = public
as $$
  update public.dm_conversation_members
     set cleared_at = now()
   where conversation_id = p_conversation and user_id = auth.uid();
$$;

-- Returns true if the reaction is now present, false if it was removed.
create or replace function public.toggle_dm_reaction(p_message uuid, p_emoji text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_conv uuid;
  v_deleted timestamptz;
begin
  select conversation_id, deleted_at into v_conv, v_deleted from public.dm_messages where id = p_message;
  if v_conv is null or not public.is_dm_member(v_conv) or v_deleted is not null then
    raise exception 'dm_not_allowed' using errcode = '42501';
  end if;

  delete from public.dm_message_reactions
   where message_id = p_message and user_id = auth.uid() and emoji = p_emoji;
  if found then return false; end if;

  insert into public.dm_message_reactions (message_id, user_id, emoji) values (p_message, auth.uid(), p_emoji);
  return true;
end;
$$;

create or replace function public.set_dm_conversation_flags(
  p_conversation uuid,
  p_pinned boolean default null,
  p_archived boolean default null,
  p_muted_until timestamptz default null,
  p_unmute boolean default false
)
returns void
language sql
security definer
set search_path = public
as $$
  update public.dm_conversation_members
     set is_pinned = coalesce(p_pinned, is_pinned),
         is_archived = coalesce(p_archived, is_archived),
         muted_until = case when p_unmute then null else coalesce(p_muted_until, muted_until) end
   where conversation_id = p_conversation and user_id = auth.uid();
$$;

create or replace function public.list_dm_conversations(p_archived boolean default false)
returns table (
  conversation_id uuid,
  other_user_id uuid,
  other_username text,
  other_avatar_url text,
  last_message_at timestamptz,
  last_message_kind text,
  last_message_sender_id uuid,
  last_message_body text,
  last_message_ciphertext text,
  last_message_nonce text,
  last_message_enc_version smallint,
  last_message_deleted boolean,
  unread_count integer,
  is_pinned boolean,
  is_archived boolean,
  muted_until timestamptz,
  other_last_read_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select
    c.id,
    o.id,
    o.username,
    o.profile_photo_url,
    c.last_message_at,
    lm.kind,
    lm.sender_id,
    lm.body,
    lm.ciphertext,
    lm.nonce,
    lm.enc_version,
    (lm.deleted_at is not null),
    (
      select count(*)::integer from public.dm_messages m
      where m.conversation_id = c.id
        and m.sender_id <> auth.uid()
        and m.deleted_at is null
        and m.created_at > me.last_read_at
        and (me.cleared_at is null or m.created_at > me.cleared_at)
        and not exists (select 1 from public.dm_message_hidden h where h.message_id = m.id and h.user_id = auth.uid())
    ),
    me.is_pinned,
    me.is_archived,
    me.muted_until,
    om.last_read_at
  from public.dm_conversations c
  join public.dm_conversation_members me on me.conversation_id = c.id and me.user_id = auth.uid()
  join public.dm_conversation_members om on om.conversation_id = c.id and om.user_id <> auth.uid()
  join public.users o on o.id = om.user_id
  left join lateral (
    select m.* from public.dm_messages m
    where m.conversation_id = c.id
      and (me.cleared_at is null or m.created_at > me.cleared_at)
      and not exists (select 1 from public.dm_message_hidden h where h.message_id = m.id and h.user_id = auth.uid())
    order by m.created_at desc
    limit 1
  ) lm on true
  where me.is_archived = p_archived
    and (lm.id is not null or c.created_at > now() - interval '1 day')
    and not exists (
      select 1 from public.user_blocks ub
      where (ub.blocker_id = auth.uid() and ub.blocked_id = o.id)
         or (ub.blocker_id = o.id and ub.blocked_id = auth.uid())
    )
  order by me.is_pinned desc, c.last_message_at desc;
$$;

-- Messages newest-first, each with reactions and a reply preview, as jsonb.
create or replace function public.get_dm_messages(
  p_conversation uuid,
  p_before timestamptz default null,
  p_limit integer default 40
)
returns setof jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_cleared timestamptz;
begin
  if not public.is_dm_member(p_conversation) then
    raise exception 'dm_not_member' using errcode = '42501';
  end if;
  select cleared_at into v_cleared from public.dm_conversation_members
   where conversation_id = p_conversation and user_id = auth.uid();

  return query
  select (to_jsonb(m) - 'deleted_by') || jsonb_build_object(
    'reactions', coalesce((
      select jsonb_agg(jsonb_build_object('emoji', e.emoji, 'count', e.cnt, 'mine', e.mine) order by e.emoji)
      from (
        select r.emoji, count(*) as cnt, bool_or(r.user_id = auth.uid()) as mine
        from public.dm_message_reactions r where r.message_id = m.id group by r.emoji
      ) e
    ), '[]'::jsonb),
    'reply_to', (
      select jsonb_build_object(
        'id', rm.id, 'sender_id', rm.sender_id, 'kind', rm.kind, 'body', rm.body,
        'ciphertext', rm.ciphertext, 'nonce', rm.nonce, 'enc_version', rm.enc_version,
        'deleted', rm.deleted_at is not null
      ) from public.dm_messages rm where rm.id = m.reply_to_id
    )
  )
  from public.dm_messages m
  where m.conversation_id = p_conversation
    and (v_cleared is null or m.created_at > v_cleared)
    and (p_before is null or m.created_at < p_before)
    and not exists (select 1 from public.dm_message_hidden h where h.message_id = m.id and h.user_id = auth.uid())
  order by m.created_at desc
  limit least(greatest(coalesce(p_limit, 40), 1), 100);
end;
$$;

-- Key registry. Never silently replaces an existing key: a second device
-- gets the registered key back and must decide (p_replace) explicitly.
create or replace function public.register_dm_public_key(p_public_key text, p_replace boolean default false)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_existing text;
begin
  if auth.uid() is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  select public_key into v_existing from public.dm_user_keys where user_id = auth.uid();
  if v_existing is null then
    insert into public.dm_user_keys (user_id, public_key) values (auth.uid(), p_public_key);
    return p_public_key;
  end if;
  if p_replace and v_existing <> p_public_key then
    update public.dm_user_keys
       set public_key = p_public_key, key_version = key_version + 1, updated_at = now()
     where user_id = auth.uid();
    return p_public_key;
  end if;
  return v_existing;
end;
$$;

create or replace function public.get_dm_public_key(p_user uuid)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select k.public_key from public.dm_user_keys k
  where k.user_id = p_user
    and auth.uid() is not null
    and not exists (
      select 1 from public.user_blocks ub
      where (ub.blocker_id = auth.uid() and ub.blocked_id = p_user)
         or (ub.blocker_id = p_user and ub.blocked_id = auth.uid())
    );
$$;

grant execute on function public.is_dm_member(uuid) to authenticated;
grant execute on function public.get_or_create_dm_conversation(uuid) to authenticated;
grant execute on function public.send_dm_message(uuid, text, text, text, text, smallint, uuid, text, text, bigint, text, integer, boolean) to authenticated;
grant execute on function public.mark_dm_delivered(uuid) to authenticated;
grant execute on function public.mark_dm_read(uuid) to authenticated;
grant execute on function public.delete_dm_message_for_everyone(uuid) to authenticated;
grant execute on function public.hide_dm_message_for_me(uuid) to authenticated;
grant execute on function public.clear_dm_conversation_for_me(uuid) to authenticated;
grant execute on function public.toggle_dm_reaction(uuid, text) to authenticated;
grant execute on function public.set_dm_conversation_flags(uuid, boolean, boolean, timestamptz, boolean) to authenticated;
grant execute on function public.list_dm_conversations(boolean) to authenticated;
grant execute on function public.get_dm_messages(uuid, timestamptz, integer) to authenticated;
grant execute on function public.register_dm_public_key(text, boolean) to authenticated;
grant execute on function public.get_dm_public_key(uuid) to authenticated;
revoke execute on function public.dm_assert_can_message(uuid, uuid) from public, anon, authenticated;

-- =====================================================================
-- 6. Realtime
-- =====================================================================
do $$
declare
  t text;
begin
  foreach t in array array['dm_messages', 'dm_conversation_members', 'dm_message_reactions'] loop
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t
    ) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;

-- =====================================================================
-- 7. Storage: private bucket, path = <conversation_id>/<sender_id>/<file>
-- =====================================================================
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'dm-media', 'dm-media', false, 26214400,
  array[
    'image/jpeg', 'image/png', 'image/webp', 'image/gif',
    'video/mp4', 'video/quicktime', 'video/webm',
    'audio/mp4', 'audio/m4a', 'audio/x-m4a', 'audio/aac', 'audio/mpeg', 'audio/ogg', 'audio/webm', 'audio/wav',
    'application/pdf', 'text/plain', 'application/zip',
    'application/msword', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'application/vnd.ms-excel', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
  ]
)
on conflict (id) do update
  set public = false, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "DM members can upload dm media" on storage.objects;
create policy "DM members can upload dm media" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'dm-media'
    and (storage.foldername(name))[2] = auth.uid()::text
    and public.is_dm_member(((storage.foldername(name))[1])::uuid)
  );

drop policy if exists "DM members can view dm media" on storage.objects;
create policy "DM members can view dm media" on storage.objects
  for select to authenticated
  using (
    bucket_id = 'dm-media'
    and public.is_dm_member(((storage.foldername(name))[1])::uuid)
  );

drop policy if exists "Senders can delete own dm media" on storage.objects;
create policy "Senders can delete own dm media" on storage.objects
  for delete to authenticated
  using (bucket_id = 'dm-media' and (storage.foldername(name))[2] = auth.uid()::text);
