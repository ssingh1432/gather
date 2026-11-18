-- 130: DMCA-style copyright notice and counter-notice workflow (Phase 5 gap).
-- Notices and counter-notices are written only through SECURITY DEFINER RPCs;
-- clients can only SELECT rows they are party to (claimant, accused author) or staff.

create table if not exists public.copyright_notices (
  id uuid primary key default gen_random_uuid(),
  claimant_id uuid references public.users(id) on delete set null,
  claimant_name text not null check (length(trim(claimant_name)) between 2 and 200),
  claimant_email text not null check (length(claimant_email) <= 254 and claimant_email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  claimant_address text check (length(claimant_address) <= 500),
  work_description text not null check (length(trim(work_description)) between 10 and 2000),
  original_work_url text check (length(original_work_url) <= 2000),
  target_post_id uuid references public.posts(id) on delete set null,
  target_author_id uuid references public.users(id) on delete set null,
  infringing_url text check (length(infringing_url) <= 2000),
  good_faith_statement boolean not null check (good_faith_statement),
  accuracy_statement boolean not null check (accuracy_statement),
  signature text not null check (length(trim(signature)) between 2 and 200),
  status text not null default 'submitted'
    check (status in ('submitted','under_review','content_removed','rejected','counter_notice_received','restored','withdrawn')),
  reviewer_id uuid references public.users(id) on delete set null,
  review_notes text check (length(review_notes) <= 4000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  resolved_at timestamptz,
  check (target_post_id is not null or infringing_url is not null)
);

create table if not exists public.copyright_counter_notices (
  id uuid primary key default gen_random_uuid(),
  notice_id uuid not null references public.copyright_notices(id) on delete cascade,
  user_id uuid references public.users(id) on delete set null,
  statement text not null check (length(trim(statement)) between 10 and 2000),
  consent_to_jurisdiction boolean not null check (consent_to_jurisdiction),
  signature text not null check (length(trim(signature)) between 2 and 200),
  status text not null default 'submitted' check (status in ('submitted','accepted','rejected')),
  reviewer_id uuid references public.users(id) on delete set null,
  review_notes text check (length(review_notes) <= 4000),
  created_at timestamptz not null default now(),
  resolved_at timestamptz
);

create index if not exists idx_copyright_notices_status on public.copyright_notices (status, created_at desc);
create index if not exists idx_copyright_notices_claimant on public.copyright_notices (claimant_id, created_at desc);
create index if not exists idx_copyright_notices_author on public.copyright_notices (target_author_id);
create unique index if not exists uq_counter_notice_open on public.copyright_counter_notices (notice_id) where status = 'submitted';

alter table public.copyright_notices enable row level security;
alter table public.copyright_counter_notices enable row level security;

drop policy if exists copyright_notices_select on public.copyright_notices;
create policy copyright_notices_select on public.copyright_notices for select to authenticated
  using (claimant_id = auth.uid() or target_author_id = auth.uid() or public.is_admin_or_mod());

drop policy if exists copyright_counter_select on public.copyright_counter_notices;
create policy copyright_counter_select on public.copyright_counter_notices for select to authenticated
  using (user_id = auth.uid() or public.is_admin_or_mod()
         or exists (select 1 from public.copyright_notices n where n.id = notice_id and n.claimant_id = auth.uid()));

revoke all on public.copyright_notices, public.copyright_counter_notices from anon, authenticated;
grant select on public.copyright_notices, public.copyright_counter_notices to authenticated;
grant all on public.copyright_notices, public.copyright_counter_notices to service_role;

create or replace function public.submit_copyright_notice(
  p_claimant_name text, p_claimant_email text, p_claimant_address text,
  p_work_description text, p_original_work_url text,
  p_target_post_id uuid, p_infringing_url text,
  p_good_faith boolean, p_accuracy boolean, p_signature text)
returns uuid
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v_author uuid; v_id uuid;
begin
  if v_uid is null then raise exception 'not_authenticated' using errcode = 'P0001'; end if;
  if p_target_post_id is null and coalesce(trim(p_infringing_url), '') = '' then
    raise exception 'target_required' using errcode = 'P0001';
  end if;
  if (select count(*) from public.copyright_notices where claimant_id = v_uid and created_at > now() - interval '24 hours') >= 5 then
    raise exception 'rate_limited' using errcode = 'P0001';
  end if;
  if p_target_post_id is not null then
    select author_id into v_author from public.posts where id = p_target_post_id;
    if not found then raise exception 'post_not_found' using errcode = 'P0001'; end if;
  end if;
  insert into public.copyright_notices (claimant_id, claimant_name, claimant_email, claimant_address, work_description,
      original_work_url, target_post_id, target_author_id, infringing_url, good_faith_statement, accuracy_statement, signature)
  values (v_uid, p_claimant_name, p_claimant_email, p_claimant_address, p_work_description,
      p_original_work_url, p_target_post_id, v_author, nullif(trim(p_infringing_url), ''), coalesce(p_good_faith, false), coalesce(p_accuracy, false), p_signature)
  returning id into v_id;
  perform public.log_security_event('copyright_notice_submitted', jsonb_build_object('notice_id', v_id));
  return v_id;
end $$;

create or replace function public.withdraw_copyright_notice(p_notice_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  update public.copyright_notices set status = 'withdrawn', resolved_at = now(), updated_at = now()
   where id = p_notice_id and claimant_id = auth.uid() and status in ('submitted','under_review');
  if not found then raise exception 'cannot_withdraw' using errcode = 'P0001'; end if;
end $$;

create or replace function public.admin_resolve_copyright_notice(p_notice_id uuid, p_action text, p_notes text default null)
returns void language plpgsql security definer set search_path = public as $$
declare n public.copyright_notices%rowtype;
begin
  if not public.is_admin_or_mod() then raise exception 'forbidden' using errcode = '42501'; end if;
  if p_action not in ('review','remove','reject') then raise exception 'invalid_action' using errcode = 'P0001'; end if;
  select * into n from public.copyright_notices where id = p_notice_id for update;
  if not found then raise exception 'not_found' using errcode = 'P0001'; end if;
  if n.status not in ('submitted','under_review') then raise exception 'already_resolved' using errcode = 'P0001'; end if;

  if p_action = 'remove' and n.target_post_id is not null then
    update public.posts set is_removed = true where id = n.target_post_id;
  end if;
  update public.copyright_notices set
      status = case p_action when 'review' then 'under_review' when 'remove' then 'content_removed' else 'rejected' end,
      reviewer_id = auth.uid(), review_notes = p_notes, updated_at = now(),
      resolved_at = case when p_action = 'review' then null else now() end
   where id = p_notice_id;
  perform public.log_security_event('copyright_notice_' || p_action, jsonb_build_object('notice_id', p_notice_id));
end $$;

create or replace function public.submit_counter_notice(p_notice_id uuid, p_statement text, p_consent boolean, p_signature text)
returns uuid language plpgsql security definer set search_path = public as $$
declare n public.copyright_notices%rowtype; v_id uuid;
begin
  select * into n from public.copyright_notices where id = p_notice_id for update;
  if not found or n.target_author_id is distinct from auth.uid() or n.status <> 'content_removed' then
    raise exception 'cannot_counter' using errcode = 'P0001';
  end if;
  insert into public.copyright_counter_notices (notice_id, user_id, statement, consent_to_jurisdiction, signature)
  values (p_notice_id, auth.uid(), p_statement, coalesce(p_consent, false), p_signature) returning id into v_id;
  update public.copyright_notices set status = 'counter_notice_received', updated_at = now() where id = p_notice_id;
  perform public.log_security_event('copyright_counter_notice_submitted', jsonb_build_object('notice_id', p_notice_id));
  return v_id;
end $$;

create or replace function public.admin_resolve_counter_notice(p_counter_id uuid, p_restore boolean, p_notes text default null)
returns void language plpgsql security definer set search_path = public as $$
declare c public.copyright_counter_notices%rowtype; n public.copyright_notices%rowtype;
begin
  if not public.is_admin_or_mod() then raise exception 'forbidden' using errcode = '42501'; end if;
  select * into c from public.copyright_counter_notices where id = p_counter_id for update;
  if not found or c.status <> 'submitted' then raise exception 'not_open' using errcode = 'P0001'; end if;
  select * into n from public.copyright_notices where id = c.notice_id for update;
  if p_restore then
    if n.target_post_id is not null then update public.posts set is_removed = false where id = n.target_post_id; end if;
    update public.copyright_notices set status = 'restored', updated_at = now(), resolved_at = now() where id = n.id;
  else
    update public.copyright_notices set status = 'content_removed', updated_at = now() where id = n.id;
  end if;
  update public.copyright_counter_notices set status = case when p_restore then 'accepted' else 'rejected' end,
      reviewer_id = auth.uid(), review_notes = p_notes, resolved_at = now() where id = p_counter_id;
  perform public.log_security_event('copyright_counter_resolved', jsonb_build_object('counter_id', p_counter_id, 'restored', p_restore));
end $$;

do $$
declare f text;
begin
  foreach f in array array[
    'submit_copyright_notice(text,text,text,text,text,uuid,text,boolean,boolean,text)',
    'withdraw_copyright_notice(uuid)',
    'admin_resolve_copyright_notice(uuid,text,text)',
    'submit_counter_notice(uuid,text,boolean,text)',
    'admin_resolve_counter_notice(uuid,boolean,text)'] loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated, service_role', f);
  end loop;
end $$;

comment on table public.copyright_notices is 'DMCA-style takedown notices. Written only via RPCs; see docs/COPYRIGHT_WORKFLOW.md.';
