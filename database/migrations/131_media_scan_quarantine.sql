-- 131: media scan hook with quarantine (malware / CSAM scanner integration point).
--
-- post_media.scan_status already existed (pending|clean|flagged, default 'clean') but nothing set it.
-- A scanner worker (any provider) running with the service role calls
-- set_media_scan_result(). A 'flagged' result quarantines the post (is_removed = true) and
-- opens a review event for staff. Staff confirm (stays removed) or mark a false positive
-- (restores only posts this event itself quarantined). No scanner is wired yet:
-- see docs/MEDIA_SCANNING.md. The default stays 'clean' so uploads are not blocked meanwhile.

create table if not exists public.media_scan_events (
  id uuid primary key default gen_random_uuid(),
  media_id uuid references public.post_media(id) on delete cascade,
  post_id uuid references public.posts(id) on delete set null,
  scanner text not null check (length(scanner) between 1 and 64),
  result text not null check (result in ('clean','flagged','error')),
  detail text check (length(detail) <= 2000),
  quarantined_post boolean not null default false,
  review_status text not null default 'open' check (review_status in ('open','confirmed','false_positive')),
  reviewer_id uuid references public.users(id) on delete set null,
  review_notes text check (length(review_notes) <= 4000),
  reviewed_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists idx_media_scan_events_open on public.media_scan_events (created_at desc) where review_status = 'open' and result = 'flagged';

alter table public.media_scan_events enable row level security;
drop policy if exists media_scan_events_staff_select on public.media_scan_events;
create policy media_scan_events_staff_select on public.media_scan_events for select to authenticated
  using (public.is_admin_or_mod());
revoke all on public.media_scan_events from anon, authenticated;
grant select on public.media_scan_events to authenticated;
grant all on public.media_scan_events to service_role;

create or replace function public.set_media_scan_result(p_media_id uuid, p_scanner text, p_result text, p_detail text default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_post uuid; v_was_removed boolean; v_quarantined boolean := false; v_id uuid;
begin
  if p_result not in ('clean','flagged','error') then raise exception 'invalid_result' using errcode = 'P0001'; end if;
  select post_id into v_post from public.post_media where id = p_media_id;
  if not found then raise exception 'media_not_found' using errcode = 'P0001'; end if;

  if p_result = 'flagged' then
    update public.post_media set scan_status = 'flagged' where id = p_media_id;
    select is_removed into v_was_removed from public.posts where id = v_post;
    if v_was_removed = false then
      update public.posts set is_removed = true where id = v_post;
      v_quarantined := true;
    end if;
  elsif p_result = 'clean' then
    update public.post_media set scan_status = 'clean' where id = p_media_id and scan_status <> 'flagged';
  end if;

  insert into public.media_scan_events (media_id, post_id, scanner, result, detail, quarantined_post)
  values (p_media_id, v_post, p_scanner, p_result, p_detail, v_quarantined) returning id into v_id;
  return v_id;
end $$;

create or replace function public.admin_review_media_scan(p_event_id uuid, p_confirmed boolean, p_notes text default null)
returns void language plpgsql security definer set search_path = public as $$
declare e public.media_scan_events%rowtype;
begin
  if not public.is_admin_or_mod() then raise exception 'forbidden' using errcode = '42501'; end if;
  select * into e from public.media_scan_events where id = p_event_id for update;
  if not found or e.result <> 'flagged' or e.review_status <> 'open' then raise exception 'not_open' using errcode = 'P0001'; end if;
  if not p_confirmed then
    update public.post_media set scan_status = 'clean' where id = e.media_id;
    if e.quarantined_post and e.post_id is not null then
      update public.posts set is_removed = false where id = e.post_id;
    end if;
  end if;
  update public.media_scan_events set review_status = case when p_confirmed then 'confirmed' else 'false_positive' end,
      reviewer_id = auth.uid(), review_notes = p_notes, reviewed_at = now() where id = p_event_id;
  perform public.log_security_event('media_scan_review', jsonb_build_object('event_id', p_event_id, 'confirmed', p_confirmed));
end $$;

revoke all on function public.set_media_scan_result(uuid,text,text,text) from public, anon, authenticated;
grant execute on function public.set_media_scan_result(uuid,text,text,text) to service_role;
revoke all on function public.admin_review_media_scan(uuid,boolean,text) from public, anon;
grant execute on function public.admin_review_media_scan(uuid,boolean,text) to authenticated, service_role;
