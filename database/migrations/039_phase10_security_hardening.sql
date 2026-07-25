-- Phase 10 Step 20: Security hardening.
--
-- Two more bugs found while auditing (on top of the notification enum bug
-- in 038a) — both fixed here before anything else in this migration:
--
-- BUG A (severe): guard_post_create() unconditionally calls
-- current_user_is_active(), which checks `u.id = auth.uid()`. Inside
-- publish_scheduled_posts() (a SECURITY DEFINER function invoked by
-- pg_cron, i.e. no client session, auth.uid() = null), that check always
-- evaluates to false, so guard_post_create raised 'Account is not
-- allowed to create posts' on *every* scheduled-post publish attempt —
-- meaning even after the 038a enum fix, scheduled posts still could not
-- actually publish. Fixed by treating a null auth.uid() as a trusted
-- system/service context and skipping the per-client checks — a real
-- anon/authenticated client call from the app always has auth.uid() set
-- by PostgREST from the JWT, so null only ever happens for
-- superuser/service-role/cron execution, never for an ordinary user
-- request.
--
-- BUG B (real vulnerability): the post-media storage bucket's INSERT
-- policy was `bucket_id = 'post-media'` with no ownership check at all —
-- any authenticated user could upload into *any* postId-keyed folder,
-- including other users' posts. Fixed to require the uploader to own the
-- post (or scheduled post) the folder is keyed to, matching the
-- ownership pattern already used correctly for avatars/story-media.

begin;

-- --- Bug A fix -----------------------------------------------------------
create or replace function public.guard_post_create()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    -- Trusted system context (pg_cron / service role) — e.g.
    -- publish_scheduled_posts(). Client requests always have auth.uid()
    -- set by PostgREST from the JWT, so this path is never reachable
    -- from the app.
    return new;
  end if;

  if new.author_id <> auth.uid() then
    raise exception 'Cannot create posts for another user' using errcode = '42501';
  end if;

  if not public.current_user_is_active() then
    raise exception 'Account is not allowed to create posts' using errcode = '42501';
  end if;

  if (
    select count(*)
    from public.posts p
    where p.author_id = new.author_id
      and p.created_at > now() - interval '1 hour'
  ) >= 10 then
    raise exception 'Post rate limit exceeded' using errcode = 'P0001';
  end if;

  return new;
end;
$$;

-- --- Bug B fix -------------------------------------------------------------
drop policy if exists "Authenticated users can upload post-media" on storage.objects;
create policy "Users can upload post-media for their own posts" on storage.objects
for insert
with check (
  bucket_id = 'post-media'
  and (storage.foldername(name))[1] = 'posts'
  and (
    exists (
      select 1 from public.posts p
      where p.id::text = (storage.foldername(name))[2] and p.author_id = auth.uid()
    )
    or exists (
      select 1 from public.scheduled_posts sp
      where sp.id::text = (storage.foldername(name))[2] and sp.user_id = auth.uid()
    )
  )
);

-- --- Rate limit for scheduled_posts (Step 20 — abuse prevention) ---------
-- scheduled_posts had no create-rate guard at all; without one, someone
-- could queue an unbounded number of future posts (storage/DB bloat, and
-- a way to route around guard_post_create's 10-per-hour limit by having
-- them all fire from the cron job instead of direct inserts — though the
-- Bug A fix above means the cron-inserted rows now skip that particular
-- check too, by design, since the *scheduling* action is what should be
-- rate-limited, not the mechanical publish).
create or replace function public.guard_scheduled_post_create()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.user_id <> auth.uid() then
    raise exception 'Cannot schedule posts for another user' using errcode = '42501';
  end if;

  if not public.current_user_is_active() then
    raise exception 'Account is not allowed to schedule posts' using errcode = '42501';
  end if;

  if (
    select count(*)
    from public.scheduled_posts sp
    where sp.user_id = new.user_id
      and sp.status = 'pending'
  ) >= 50 then
    raise exception 'Too many pending scheduled posts (max 50)' using errcode = 'P0001';
  end if;

  if (
    select count(*)
    from public.scheduled_posts sp
    where sp.user_id = new.user_id
      and sp.created_at > now() - interval '1 hour'
  ) >= 10 then
    raise exception 'Scheduling rate limit exceeded' using errcode = 'P0001';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_guard_scheduled_post_create on public.scheduled_posts;
create trigger trg_guard_scheduled_post_create
before insert on public.scheduled_posts
for each row execute function public.guard_scheduled_post_create();

-- --- File scanning hook (Step 20 — future-ready) --------------------------
-- No malware/CSAM scanner is wired up yet — this adds the interface point
-- so one can be plugged in later (e.g. a storage webhook -> edge function
-- that flips this after running a scan) without another schema change.
-- Everything defaults 'clean' today (upload validation — MIME allowlist +
-- size limits enforced at the bucket level — is the real gate right now).
alter table public.post_media add column if not exists scan_status text not null default 'clean'
  check (scan_status in ('pending', 'clean', 'flagged'));
comment on column public.post_media.scan_status is
  'Hook point for a future automated file-scanning integration (malware/CSAM). No scanner is wired up yet; everything defaults clean. A webhook-driven pipeline would insert as pending and flip to clean/flagged asynchronously.';

commit;
