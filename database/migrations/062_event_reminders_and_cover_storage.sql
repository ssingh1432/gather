-- 062_event_reminders_and_cover_storage.sql
-- Step 11 (cont): extend the existing send_event_reminders() cron job to cover
-- the new occurrence-based RSVPs with per-user configurable lead time, and add
-- storage policies for community event cover images (reusing the community-media
-- bucket under a new {community_id}/events/{event_id}/cover path).

begin;

-- Legacy branch (event_rsvps, fixed 1-hour lead time, post-attached events only)
-- is left completely unchanged. New branch below handles event_occurrence_rsvps
-- with each user's own reminder_minutes_before.
create or replace function public.send_event_reminders()
returns void
language plpgsql
security definer
set search_path = 'public'
as $$
begin
  -- Legacy: per-event RSVPs on post-attached events, fixed 1h lead time.
  insert into public.notifications (recipient_id, actor_id, post_id, type)
  select r.user_id, null, e.post_id, 'event_reminder'
  from public.event_rsvps r
  join public.events e on e.id = r.event_id
  join public.posts p on p.id = e.post_id and p.is_removed = false
  where r.status in ('going', 'interested')
    and r.reminder_sent_at is null
    and e.starts_at between now() and now() + interval '1 hour';

  update public.event_rsvps r
  set reminder_sent_at = now()
  from public.events e
  join public.posts p on p.id = e.post_id and p.is_removed = false
  where r.event_id = e.id
    and r.status in ('going', 'interested')
    and r.reminder_sent_at is null
    and e.starts_at between now() and now() + interval '1 hour';

  -- New: per-occurrence RSVPs (community events + recurring events), each
  -- user's own configurable reminder_minutes_before lead time.
  insert into public.notifications (recipient_id, actor_id, post_id, type, metadata)
  select
    orv.user_id,
    null,
    ev.post_id,
    'event_reminder',
    jsonb_build_object(
      'event_id', ev.id,
      'occurrence_id', occ.id,
      'community_id', ev.community_id,
      'title', coalesce(occ.title_override, ev.title),
      'starts_at', occ.starts_at
    )
  from public.event_occurrence_rsvps orv
  join public.event_occurrences occ on occ.id = orv.occurrence_id
  join public.events ev on ev.id = occ.event_id
  where orv.status in ('going', 'interested')
    and orv.reminder_sent_at is null
    and occ.is_cancelled = false
    and ev.status = 'active'
    and occ.starts_at between now() and now() + (orv.reminder_minutes_before * interval '1 minute');

  update public.event_occurrence_rsvps orv
  set reminder_sent_at = now()
  from public.event_occurrences occ
  join public.events ev on ev.id = occ.event_id
  where orv.occurrence_id = occ.id
    and orv.status in ('going', 'interested')
    and orv.reminder_sent_at is null
    and occ.is_cancelled = false
    and ev.status = 'active'
    and occ.starts_at between now() and now() + (orv.reminder_minutes_before * interval '1 minute');
end;
$$;

-- Storage: event cover images under community-media/{community_id}/events/{event_id}/cover
drop policy if exists "Event managers can upload event covers" on storage.objects;
create policy "Event managers can upload event covers" on storage.objects
  for insert with check (
    bucket_id = 'community-media'
    and (storage.foldername(name))[2] = 'events'
    and public.current_user_community_permission(((storage.foldername(name))[1])::uuid, 'manage_events')
  );

drop policy if exists "Event managers can update event covers" on storage.objects;
create policy "Event managers can update event covers" on storage.objects
  for update using (
    bucket_id = 'community-media'
    and (storage.foldername(name))[2] = 'events'
    and public.current_user_community_permission(((storage.foldername(name))[1])::uuid, 'manage_events')
  );

drop policy if exists "Event managers can delete event covers" on storage.objects;
create policy "Event managers can delete event covers" on storage.objects
  for delete using (
    bucket_id = 'community-media'
    and (storage.foldername(name))[2] = 'events'
    and public.current_user_community_permission(((storage.foldername(name))[1])::uuid, 'manage_events')
  );

commit;
