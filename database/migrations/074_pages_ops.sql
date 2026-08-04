-- 074_pages_ops.sql
-- Professional Page System — Step 2 (ops schema): page_analytics,
-- page_messages, page_reports, page_audit_logs, plus the page-media
-- storage bucket + policies. Additive only; depends on 072 and 073.

-- 1. Page analytics -----------------------------------------------------------
-- Populated by a daily rollup job (edge function / cron), not written
-- directly by clients — mirrors the read-only analytics pattern used for
-- community_analytics.
create table if not exists public.page_analytics (
  id uuid primary key default gen_random_uuid(),
  page_id uuid not null references public.pages(id) on delete cascade,
  date date not null,
  reach integer not null default 0,
  impressions integer not null default 0,
  views integer not null default 0,
  new_followers integer not null default 0,
  engagement integer not null default 0,
  created_at timestamptz not null default now(),
  unique (page_id, date)
);

create index if not exists idx_page_analytics_page_date on public.page_analytics (page_id, date desc);

alter table public.page_analytics enable row level security;

drop policy if exists page_analytics_select on public.page_analytics;
create policy page_analytics_select on public.page_analytics
  for select using (
    public.current_user_page_role(page_id) = 'owner'
    or public.current_user_has_page_permission(page_id, 'view_analytics')
  );

-- Intentionally select-only for `authenticated`: rollups are written by the
-- backend using the service role, which bypasses RLS entirely.
grant select on public.page_analytics to authenticated;

-- 2. Page messages (customer chat inbox) ---------------------------------------
create table if not exists public.page_messages (
  id uuid primary key default gen_random_uuid(),
  page_id uuid not null references public.pages(id) on delete cascade,
  user_id uuid not null references public.users(id) on delete cascade,
  sender_type text not null check (sender_type in ('user','page')),
  content text,
  media jsonb not null default '[]'::jsonb,
  read_at timestamptz,
  created_at timestamptz not null default now(),
  constraint page_messages_content_or_media check (content is not null or jsonb_array_length(media) > 0)
);

create index if not exists idx_page_messages_thread on public.page_messages (page_id, user_id, created_at);
create index if not exists idx_page_messages_unread on public.page_messages (page_id) where read_at is null;

alter table public.page_messages enable row level security;

drop policy if exists page_messages_select on public.page_messages;
create policy page_messages_select on public.page_messages
  for select using (
    user_id = auth.uid()
    or public.current_user_page_role(page_id) = 'owner'
    or public.current_user_has_page_permission(page_id, 'manage_messages')
  );

drop policy if exists page_messages_insert on public.page_messages;
create policy page_messages_insert on public.page_messages
  for insert with check (
    (sender_type = 'user' and user_id = auth.uid())
    or (
      sender_type = 'page'
      and (
        public.current_user_page_role(page_id) = 'owner'
        or public.current_user_has_page_permission(page_id, 'manage_messages')
      )
    )
  );

drop policy if exists page_messages_mark_read on public.page_messages;
create policy page_messages_mark_read on public.page_messages
  for update using (
    public.current_user_page_role(page_id) = 'owner'
    or public.current_user_has_page_permission(page_id, 'manage_messages')
  );

grant select, insert, update on public.page_messages to authenticated;

-- 3. Page reports ---------------------------------------------------------------
-- Reports against a Page go to site-level moderators (public.is_admin_or_mod()),
-- never to the page's own team — a page can't be judge of complaints against
-- itself. Same reason categories as the existing community/post report system.
create table if not exists public.page_reports (
  id uuid primary key default gen_random_uuid(),
  page_id uuid not null references public.pages(id) on delete cascade,
  reporter_id uuid not null references public.users(id) on delete cascade,
  reason text not null check (reason in (
    'spam','fake_account','harassment','hate_speech','violence','terrorism',
    'child_abuse','adult_content','copyright','scam','impersonation',
    'self_harm','drugs','other'
  )),
  details text,
  status text not null default 'pending'
    check (status in ('pending','reviewing','resolved','dismissed')),
  resolved_by uuid references public.users(id) on delete set null,
  resolved_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists idx_page_reports_page on public.page_reports (page_id);
create index if not exists idx_page_reports_status on public.page_reports (status) where status in ('pending','reviewing');

alter table public.page_reports enable row level security;

drop policy if exists page_reports_select on public.page_reports;
create policy page_reports_select on public.page_reports
  for select using (
    reporter_id = auth.uid()
    or public.is_admin_or_mod()
  );

drop policy if exists page_reports_insert on public.page_reports;
create policy page_reports_insert on public.page_reports
  for insert with check (reporter_id = auth.uid());

drop policy if exists page_reports_moderate on public.page_reports;
create policy page_reports_moderate on public.page_reports
  for update using (public.is_admin_or_mod());

grant select, insert, update on public.page_reports to authenticated;

-- 4. Page audit logs --------------------------------------------------------------
-- System-written only. No insert/update/delete grant to `authenticated` —
-- rows are written exclusively via the SECURITY DEFINER helper below (or by
-- the backend service role), which bypasses RLS/grants entirely by running
-- as the function owner.
create table if not exists public.page_audit_logs (
  id uuid primary key default gen_random_uuid(),
  page_id uuid not null references public.pages(id) on delete cascade,
  actor_id uuid references public.users(id) on delete set null,
  action text not null,
  target_type text,
  target_id uuid,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists idx_page_audit_logs_page on public.page_audit_logs (page_id, created_at desc);

alter table public.page_audit_logs enable row level security;

drop policy if exists page_audit_logs_select on public.page_audit_logs;
create policy page_audit_logs_select on public.page_audit_logs
  for select using (
    public.current_user_page_role(page_id) = 'owner'
    or public.current_user_has_page_permission(page_id, 'manage_settings')
    or public.is_admin_or_mod()
  );

grant select on public.page_audit_logs to authenticated;

create or replace function public.log_page_audit_event(
  p_page_id uuid,
  p_action text,
  p_target_type text default null,
  p_target_id uuid default null,
  p_metadata jsonb default '{}'::jsonb
)
returns void
language sql
security definer
set search_path = 'public'
as $$
  insert into public.page_audit_logs (page_id, actor_id, action, target_type, target_id, metadata)
  values (p_page_id, auth.uid(), p_action, p_target_type, p_target_id, p_metadata);
$$;

-- Auto-log role grants/changes/revocations.
create or replace function public.audit_page_role_change()
returns trigger
language plpgsql
security definer
set search_path = 'public'
as $$
begin
  if tg_op = 'INSERT' then
    perform public.log_page_audit_event(new.page_id, 'role_granted', 'user', new.user_id, jsonb_build_object('role', new.role));
  elsif tg_op = 'UPDATE' then
    perform public.log_page_audit_event(old.page_id, 'role_changed', 'user', new.user_id, jsonb_build_object('from', old.role, 'to', new.role));
  elsif tg_op = 'DELETE' then
    perform public.log_page_audit_event(old.page_id, 'role_revoked', 'user', old.user_id, jsonb_build_object('role', old.role));
  end if;
  return null;
end;
$$;

drop trigger if exists trg_audit_page_role_change on public.page_roles;
create trigger trg_audit_page_role_change
  after insert or update or delete on public.page_roles
  for each row execute function public.audit_page_role_change();

-- Auto-log status transitions (publish / suspend / re-draft).
create or replace function public.audit_page_status_change()
returns trigger
language plpgsql
security definer
set search_path = 'public'
as $$
begin
  if new.status is distinct from old.status then
    perform public.log_page_audit_event(new.id, 'status_changed', 'page', new.id, jsonb_build_object('from', old.status, 'to', new.status));
  end if;
  return new;
end;
$$;

drop trigger if exists trg_audit_page_status_change on public.pages;
create trigger trg_audit_page_status_change
  after update on public.pages
  for each row execute function public.audit_page_status_change();

-- 5. Storage: page-media bucket ----------------------------------------------
-- Path convention: {page_id}/logo|cover|posts/{post_id}/... — only that
-- page's manage_content/manage_settings holders may write, matching the
-- community-media bucket pattern (050).
insert into storage.buckets (id, name, public, file_size_limit)
values ('page-media', 'page-media', true, 10485760) -- 10MB
on conflict (id) do nothing;

create or replace function public.can_manage_page_media(p_page_id uuid)
returns boolean
language sql
stable
security definer
set search_path = 'public'
as $$
  select
    public.current_user_page_role(p_page_id) = 'owner'
    or public.current_user_has_page_permission(p_page_id, 'manage_content')
    or public.current_user_has_page_permission(p_page_id, 'manage_settings');
$$;

grant execute on function public.can_manage_page_media(uuid) to authenticated;

drop policy if exists "Page staff can upload media" on storage.objects;
create policy "Page staff can upload media" on storage.objects
  for insert with check (
    bucket_id = 'page-media'
    and public.can_manage_page_media(((storage.foldername(name))[1])::uuid)
  );

drop policy if exists "Page staff can update media" on storage.objects;
create policy "Page staff can update media" on storage.objects
  for update using (
    bucket_id = 'page-media'
    and public.can_manage_page_media(((storage.foldername(name))[1])::uuid)
  );

drop policy if exists "Page staff can delete media" on storage.objects;
create policy "Page staff can delete media" on storage.objects
  for delete using (
    bucket_id = 'page-media'
    and public.can_manage_page_media(((storage.foldername(name))[1])::uuid)
  );
