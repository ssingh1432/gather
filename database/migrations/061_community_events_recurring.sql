-- 061_community_events_recurring.sql
-- Step 11: Community Events (calendar, RSVP, reminders, recurring events)
--
-- Design summary:
--   * events.post_id becomes nullable — an event can now belong to a community
--     directly (community_id) instead of always requiring an attached post.
--     Existing post-attached events are untouched and keep working exactly as before.
--   * event_occurrences holds one row per concrete date/time instance of an event.
--     Non-recurring events get exactly one occurrence row (auto-created by trigger)
--     so calendar/list queries never need to branch on is_recurring.
--   * Recurrence itself (RRULE-style text) is expanded client-side (Flutter, using
--     the `rrule` package) and the resulting occurrence rows are inserted by the
--     client — Postgres does not parse RRULE syntax, it just stores it for display/edit.
--   * event_occurrence_rsvps is the new per-occurrence RSVP table used by community
--     events. The legacy event_rsvps table (per-event, not per-occurrence) is left
--     fully intact for backward compatibility with existing personal post events.
--   * The existing send_event_reminders() cron function (runs every 15 min) is
--     extended with a second branch for the new occurrence-based RSVPs with
--     per-user configurable lead time; its original behavior for event_rsvps
--     is unchanged.

begin;

-- ---------------------------------------------------------------------------
-- 1. Extend events to allow community-native events (no post required)
-- ---------------------------------------------------------------------------
alter table public.events
  alter column post_id drop not null;

alter table public.events
  add column if not exists community_id uuid references public.communities(id) on delete cascade,
  add column if not exists created_by uuid references public.users(id),
  add column if not exists is_recurring boolean not null default false,
  add column if not exists recurrence_rule text,
  add column if not exists recurrence_end_at timestamptz,
  add column if not exists status text not null default 'active' check (status in ('active','cancelled')),
  add column if not exists cover_image_url text,
  add column if not exists max_attendees integer check (max_attendees is null or max_attendees > 0),
  add column if not exists updated_at timestamptz not null default now();

-- An event must belong to a post, a community, or both — never neither.
alter table public.events
  drop constraint if exists events_owner_or_community_chk;
alter table public.events
  add constraint events_owner_or_community_chk
  check (post_id is not null or community_id is not null);

comment on column public.events.community_id is 'Community this event belongs to. Nullable for legacy personal post-events. Set alongside or instead of post_id.';
comment on column public.events.post_id is 'Optional attached post for rich content/comments. No longer required — community-native events may have no post.';
comment on column public.events.recurrence_rule is 'RRULE-style text (e.g. FREQ=WEEKLY;BYDAY=SA) for display/editing only. Occurrences are expanded and inserted by the client, not parsed in SQL.';

-- Backfill created_by and community_id for the existing row(s) from their post.
update public.events e
set created_by = p.author_id,
    community_id = coalesce(e.community_id, p.community_id)
from public.posts p
where e.post_id = p.id
  and e.created_by is null;

-- Keep updated_at fresh.
drop trigger if exists trg_events_touch on public.events;
create trigger trg_events_touch
  before update on public.events
  for each row execute function public.touch_updated_at();

-- ---------------------------------------------------------------------------
-- 2. event_occurrences — one row per concrete date/time instance
-- ---------------------------------------------------------------------------
create table if not exists public.event_occurrences (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.events(id) on delete cascade,
  starts_at timestamptz not null,
  ends_at timestamptz,
  is_cancelled boolean not null default false,
  cancelled_reason text,
  title_override text,
  description_override text,
  location_override text,
  created_at timestamptz not null default now(),
  unique (event_id, starts_at)
);

create index if not exists idx_event_occurrences_event on public.event_occurrences(event_id);
create index if not exists idx_event_occurrences_starts_at on public.event_occurrences(starts_at);

comment on table public.event_occurrences is 'One row per concrete date/time instance of an event. Non-recurring events get exactly one auto-created row. Recurring events get one row per expanded RRULE instance, inserted by the client.';
comment on column public.event_occurrences.title_override is 'Per-occurrence override, e.g. renaming a single instance of a recurring event without affecting the series.';

-- Auto-create the single occurrence for non-recurring events so all downstream
-- queries (calendar, RSVP, reminders) can always read from event_occurrences.
create or replace function public.create_default_event_occurrence()
returns trigger
language plpgsql
security definer
set search_path = 'public'
as $$
begin
  if new.is_recurring = false then
    insert into public.event_occurrences (event_id, starts_at, ends_at)
    values (new.id, new.starts_at, new.ends_at)
    on conflict (event_id, starts_at) do nothing;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_events_default_occurrence on public.events;
create trigger trg_events_default_occurrence
  after insert on public.events
  for each row execute function public.create_default_event_occurrence();

-- Backfill an occurrence for the existing event row(s).
insert into public.event_occurrences (event_id, starts_at, ends_at)
select e.id, e.starts_at, e.ends_at
from public.events e
where not exists (select 1 from public.event_occurrences o where o.event_id = e.id)
on conflict (event_id, starts_at) do nothing;

-- ---------------------------------------------------------------------------
-- 3. event_occurrence_rsvps — new per-occurrence RSVP + configurable reminder
-- ---------------------------------------------------------------------------
create table if not exists public.event_occurrence_rsvps (
  id uuid primary key default gen_random_uuid(),
  occurrence_id uuid not null references public.event_occurrences(id) on delete cascade,
  user_id uuid not null references public.users(id) on delete cascade,
  status text not null check (status in ('going','interested','not_going')),
  reminder_minutes_before integer not null default 60 check (reminder_minutes_before >= 0),
  reminder_sent_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (occurrence_id, user_id)
);

create index if not exists idx_event_occurrence_rsvps_occurrence on public.event_occurrence_rsvps(occurrence_id);
create index if not exists idx_event_occurrence_rsvps_user on public.event_occurrence_rsvps(user_id);

drop trigger if exists trg_event_occurrence_rsvps_touch on public.event_occurrence_rsvps;
create trigger trg_event_occurrence_rsvps_touch
  before update on public.event_occurrence_rsvps
  for each row execute function public.touch_updated_at();

-- Migrate the existing event_rsvps rows for the backfilled occurrence so
-- current RSVPs show up under the new model too (legacy table is untouched).
insert into public.event_occurrence_rsvps (occurrence_id, user_id, status, reminder_sent_at)
select o.id, r.user_id, r.status, r.reminder_sent_at
from public.event_rsvps r
join public.event_occurrences o on o.event_id = r.event_id
on conflict (occurrence_id, user_id) do nothing;

-- ---------------------------------------------------------------------------
-- 4. Grants (explicit — RLS alone is not enough at the table-grant layer)
-- ---------------------------------------------------------------------------
grant select, insert, update, delete on public.event_occurrences to authenticated;
grant select, insert, update, delete on public.event_occurrence_rsvps to authenticated;
grant select on public.event_occurrences to service_role;
grant select on public.event_occurrence_rsvps to service_role;

-- ---------------------------------------------------------------------------
-- 5. RLS — events (rewritten for nullable post_id + community_id)
-- ---------------------------------------------------------------------------
alter table public.events enable row level security;

drop policy if exists events_read on public.events;
create policy events_read on public.events
  for select using (
    (post_id is not null and exists (select 1 from public.posts p where p.id = events.post_id))
    or (community_id is not null and exists (select 1 from public.communities c where c.id = events.community_id))
  );

drop policy if exists events_owner_write on public.events;
create policy events_write on public.events
  for all using (
    created_by = auth.uid()
    or (post_id is not null and exists (select 1 from public.posts p where p.id = events.post_id and p.author_id = auth.uid()))
    or (community_id is not null and public.current_user_community_permission(community_id, 'manage_events'))
    or public.is_admin_or_mod()
  )
  with check (
    created_by = auth.uid()
    or (post_id is not null and exists (select 1 from public.posts p where p.id = events.post_id and p.author_id = auth.uid()))
    or (community_id is not null and public.current_user_community_permission(community_id, 'manage_events'))
    or public.is_admin_or_mod()
  );

-- ---------------------------------------------------------------------------
-- 6. RLS — event_occurrences
-- ---------------------------------------------------------------------------
alter table public.event_occurrences enable row level security;

drop policy if exists event_occurrences_read on public.event_occurrences;
create policy event_occurrences_read on public.event_occurrences
  for select using (
    exists (select 1 from public.events e where e.id = event_occurrences.event_id)
  );

drop policy if exists event_occurrences_write on public.event_occurrences;
create policy event_occurrences_write on public.event_occurrences
  for all using (
    exists (
      select 1 from public.events e
      where e.id = event_occurrences.event_id
        and (
          e.created_by = auth.uid()
          or (e.community_id is not null and public.current_user_community_permission(e.community_id, 'manage_events'))
          or public.is_admin_or_mod()
        )
    )
  )
  with check (
    exists (
      select 1 from public.events e
      where e.id = event_occurrences.event_id
        and (
          e.created_by = auth.uid()
          or (e.community_id is not null and public.current_user_community_permission(e.community_id, 'manage_events'))
          or public.is_admin_or_mod()
        )
    )
  );

-- ---------------------------------------------------------------------------
-- 7. RLS — event_occurrence_rsvps
-- ---------------------------------------------------------------------------
alter table public.event_occurrence_rsvps enable row level security;

drop policy if exists event_occurrence_rsvps_read on public.event_occurrence_rsvps;
create policy event_occurrence_rsvps_read on public.event_occurrence_rsvps
  for select using (
    exists (select 1 from public.event_occurrences o where o.id = event_occurrence_rsvps.occurrence_id)
  );

drop policy if exists event_occurrence_rsvps_own_write on public.event_occurrence_rsvps;
create policy event_occurrence_rsvps_own_write on public.event_occurrence_rsvps
  for all using (user_id = auth.uid())
  with check (user_id = auth.uid());

commit;
