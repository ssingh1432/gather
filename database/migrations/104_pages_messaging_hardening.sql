-- Stage 4 — Professional Pages messaging hardening.
-- Keeps existing Pages messaging enabled by default, adds an explicit
-- Page-level switch, and closes write/update authorization gaps.

alter table public.pages
  add column if not exists messaging_enabled boolean not null default true;

comment on column public.pages.messaging_enabled is
  'Whether visitors may start new conversations with this Page. Existing Pages default to enabled.';

-- Visitors may only start conversations with a published, live Page that
-- has messaging enabled. Page staff replies require the same switch and must
-- identify the authenticated staff member in sent_by.
drop policy if exists page_messages_insert on public.page_messages;
create policy page_messages_insert on public.page_messages
  for insert with check (
    (
      sender_type = 'user'
      and user_id = auth.uid()
      and exists (
        select 1
        from public.pages p
        where p.id = page_messages.page_id
          and p.status = 'published'
          and p.deleted_at is null
          and p.messaging_enabled = true
      )
    )
    or (
      sender_type = 'page'
      and sent_by = auth.uid()
      and (
        public.current_user_page_role(page_id) = 'owner'
        or public.current_user_has_page_permission(page_id, 'manage_messages')
      )
      and exists (
        select 1
        from public.pages p
        where p.id = page_messages.page_id
          and p.deleted_at is null
          and p.messaging_enabled = true
      )
    )
  );

-- The old UPDATE policy let a Page manager update every column of a message.
-- Page messages are immutable except for read_at; enforce that at the database
-- boundary so content, authorship, thread ownership, and timestamps cannot be
-- rewritten through the client API.
create or replace function public.guard_page_message_update()
returns trigger
language plpgsql
security definer
set search_path = 'public'
as $$
begin
  if new.page_id is distinct from old.page_id
     or new.user_id is distinct from old.user_id
     or new.sender_type is distinct from old.sender_type
     or new.content is distinct from old.content
     or new.media is distinct from old.media
     or new.created_at is distinct from old.created_at
     or new.sent_by is distinct from old.sent_by then
    raise exception 'Page messages are immutable except for read status.';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_guard_page_message_update on public.page_messages;
create trigger trg_guard_page_message_update
  before update on public.page_messages
  for each row execute function public.guard_page_message_update();

-- Automation and notifications must not run when Page messaging is disabled.
create or replace function public.handle_page_message_automation()
returns trigger
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_page public.pages%rowtype;
  v_is_first boolean;
  v_open boolean;
  v_reply_content text;
begin
  select * into v_page from public.pages where id = new.page_id;

  if v_page.id is null or v_page.messaging_enabled = false then
    return new;
  end if;

  if new.sender_type = 'user' then
    insert into public.notifications (recipient_id, actor_id, type, metadata)
    select recipient, new.user_id, 'page_message_received',
      jsonb_build_object('page_id', new.page_id, 'page_name', v_page.name)
    from (
      select v_page.owner_id as recipient
      union
      select pr.user_id
      from public.page_roles pr
      join public.page_role_permissions rp
        on rp.role = pr.role
       and rp.permission_key = 'manage_messages'
       and rp.allowed
      where pr.page_id = new.page_id
    ) recips
    where recipient is not null;

    select not exists (
      select 1 from public.page_messages
      where page_id = new.page_id and user_id = new.user_id and id <> new.id
    ) into v_is_first;

    if v_is_first then
      v_open := public.page_is_open_now(new.page_id);
      v_reply_content := null;

      if not v_open and v_page.away_message_enabled and v_page.away_message is not null then
        v_reply_content := v_page.away_message;
      elsif v_page.auto_reply_enabled and v_page.auto_reply_message is not null then
        v_reply_content := v_page.auto_reply_message;
      end if;

      if v_reply_content is not null then
        insert into public.page_messages (page_id, user_id, sender_type, content, sent_by)
        values (new.page_id, new.user_id, 'page', v_reply_content, null);
      end if;
    end if;

  elsif new.sender_type = 'page' then
    insert into public.notifications (recipient_id, actor_id, type, metadata)
    values (
      new.user_id,
      new.sent_by,
      'page_message_reply',
      jsonb_build_object('page_id', new.page_id, 'page_name', v_page.name)
    );
  end if;

  return new;
end;
$$;
