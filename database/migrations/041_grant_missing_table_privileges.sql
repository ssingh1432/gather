-- Migration 041: grant missing table-level privileges to `authenticated`.
--
-- Root cause of the "permission denied for table polls / scheduled_posts /
-- events / ..." errors seen in the client: this project has no
-- ALTER DEFAULT PRIVILEGES rule on the public schema (confirmed empty
-- pg_default_acl for `public`). Supabase Studio's table editor auto-grants
-- SELECT/INSERT/UPDATE/DELETE to `authenticated` when you create a table
-- through the UI, but a table created by a raw SQL migration gets NO grant
-- at all unless the migration says so explicitly. RLS policies were written
-- correctly for every one of these tables — the request never even got to
-- the RLS check, because Postgres rejects at the table-grant layer first.
--
-- This affected every content type added from Phase 6 onward: polls,
-- events, scheduled posts, drafts, edit history, beta feedback, and every
-- admin/moderator dashboard table. Confirmed live: 23 public tables had
-- zero grants to `authenticated`; of those, 19 are queried directly by the
-- Flutter client via `.from(...)` (the other 4 — allowed_beta_emails,
-- auth_login_attempts, beta_access_allowlist, creator_ad_impressions — are
-- correctly RPC/cron-only and are deliberately left ungranted).
--
-- Privileges below are scoped to match each table's existing RLS policy
-- set (e.g. poll_votes and post_edit_history have no UPDATE policy, so
-- there's no UPDATE grant either — granting a privilege RLS will always
-- deny is just noise). RLS continues to be the thing that decides which
-- *rows* a user can touch; this migration only restores the ability to
-- reach the table at all.

-- Content creation tables (Phase 10) — this is what broke poll/event/
-- scheduled-post/draft creation in the screenshots.
grant select, insert, update, delete on public.polls to authenticated;
grant select, insert, update, delete on public.poll_options to authenticated;
grant select, insert, delete on public.poll_votes to authenticated;
grant select, insert, update, delete on public.events to authenticated;
grant select, insert, update, delete on public.event_rsvps to authenticated;
grant select, insert, update, delete on public.scheduled_posts to authenticated;
grant select, insert, update, delete on public.post_drafts to authenticated;
grant select, insert on public.post_edit_history to authenticated;

-- User-facing beta feedback (Phase 4) — same bug, silently broken submit.
grant select, insert, update on public.beta_feedback to authenticated;

-- Admin / moderator dashboard read tables (Phase 6/7/8) — same bug,
-- silently broken for every admin/mod screen that reads these directly
-- instead of through an RPC.
grant select on public.admin_audit_log to authenticated;
grant select on public.backup_log to authenticated;
grant select, insert, update, delete on public.keyword_filters to authenticated;
grant select, update on public.media_moderation_flags to authenticated;
grant select on public.moderation_actions to authenticated;
grant select, insert, update on public.moderation_appeals to authenticated;
grant select, insert on public.moderation_evidence to authenticated;
grant select, insert, update, delete on public.moderator_notes to authenticated;
grant select on public.moderator_permissions to authenticated;
grant select on public.security_events to authenticated;

-- Process note (not enforced by this migration): there is deliberately no
-- blanket `alter default privileges ... grant ... on tables to
-- authenticated` here. Doing that would silently expose any *future*
-- admin-only table the moment it's created, before anyone thinks to lock
-- it down — worse than the bug this migration fixes. Every new migration
-- that adds a client-reachable table must include its own explicit GRANT,
-- same as this file. Added a matching note to docs/DATABASE.md.
