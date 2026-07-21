-- Phase 6: Community Moderation — Part A (enums + columns)
-- Split from the main Phase 6 migration because Postgres will not let a new
-- enum label be referenced in the same transaction that adds it.

-- Suspension is a first-class user status alongside active/banned/pending_deletion.
-- NOTE: suspend_user() already wrote 'suspended' into users.status before this
-- value existed on the enum — this migration is what actually makes that valid.
alter type public.user_status add value if not exists 'suspended';

-- Tracks how long a temporary suspension lasts; null once lifted/reinstated.
alter table public.users add column if not exists suspended_until timestamptz;

-- Running strike count used by the auto-escalation logic in Part B.
alter table public.users add column if not exists strike_count integer not null default 0;

-- Structured report categories (Phase 6 requirement). Kept separate from the
-- existing free-text `reason` column (used for reporter-written detail) so
-- older report rows and the existing report_screen.dart insert keep working
-- unchanged; `category` is additive and nullable for backward compatibility.
do $$
begin
  if not exists (select 1 from pg_type where typname = 'report_category') then
    create type public.report_category as enum (
      'spam',
      'fake_account',
      'harassment',
      'hate_speech',
      'violence',
      'terrorism',
      'child_abuse',
      'adult_content',
      'copyright',
      'scam',
      'impersonation',
      'self_harm',
      'drugs',
      'other'
    );
  end if;
end
$$;

alter table public.reports add column if not exists category public.report_category;
alter table public.reports add column if not exists is_automated boolean not null default false;

-- reporter_id stays NOT NULL (schema-compatible); automated reports simply
-- attribute to the content's own author and are marked is_automated = true so
-- guard_report_create can skip the "can't report yourself" / rate-limit checks.
