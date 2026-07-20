-- Applied directly against the live project via Supabase MCP as
-- 016b_fix_user_mutes_fk_to_public_users and
-- 016c_fix_legal_tables_fk_to_public_users while building out migrations
-- 015/016: the FKs were initially created against auth.users(id), which
-- doesn't support PostgREST embedding (`users!constraint_name(...)`) the
-- way the rest of this app's repositories rely on. Migrations 015/016 in
-- this repo already reflect the corrected public.users(id) references,
-- so this file is a no-op on a fresh database — it only exists so the
-- migration history here matches what was actually run against
-- xttxiwjllumskuhzxngx, in case anyone diffs prod against this folder.

-- (Intentionally left as documentation only — see 015_privacy_compliance.sql
-- and 016_nepal_legal_compliance.sql for the corrected table definitions.)
select 1;
