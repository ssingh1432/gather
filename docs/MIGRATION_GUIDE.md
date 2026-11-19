# Gather — Migration Guide

## How migrations run
`scripts/apply_migrations.py` (CI `migrate` job) runs pending files from `database/migrations/` in filename order through the Supabase Management API. Each file runs with its tracking insert in one request into `public.repo_migrations(filename, checksum, applied_at)`; failure rolls that file back and stops the deploy. If the tracking table is empty the script refuses to run (seed a baseline first).

## Rules
- Forward-only. Never edit an applied file; add a new one (next number after the highest — currently 127).
- Idempotent where possible (`if not exists`, `drop policy if exists`).
- Do not change live schema with ad-hoc SQL; it causes repo↔live drift (happened several times).
- Avoid duplicate numeric prefixes; if unavoidable, the suffix letter (`a`, `b`) defines order.

## Procedure
1. Write migration + test plan; run `python3 scripts/lint_migrations.py`.
2. Apply to **staging** first; run the test plan.
3. PR → merge → CI applies to production. Verify: `select filename from repo_migrations order by applied_at desc limit 5;`
4. Re-run Supabase security advisors.

## Migrations 127–132 (applied live 2026-11-18, also in repo)
| # | What |
|---|---|
| 127 | `page_roles` RLS enable (live already had it; closes repo drift) |
| 128 | advisor hardening: search_path, anon revokes, `log_security_event` limits |
| 129 | close anonymous read leaks; `community-media` MIME allowlist |
| 130 | copyright notice + counter-notice workflow (COPYRIGHT_WORKFLOW.md) |
| 131 | media scan quarantine hook (MEDIA_SCANNING.md) |
| 132 | legal data requests admin-only; `data-exports` MIME allowlist |
| 133 | performance: 159 policies use `(select auth.uid())`, 137 FK indexes, duplicate constraint dropped |
| 134 | retention: daily prune of `beta_error_logs` (60 d) and `analytics_events` (400 d) |
They were applied through the Supabase tool, so `supabase_migrations` has them but `repo_migrations` does not. All are idempotent: when CI runs on merge it re-applies them harmlessly and records them.

## Client compatibility
Keep RPC signatures backward compatible (add parameters with defaults) so older app builds keep working; deprecate in a later migration.

## Known risk: the repo cannot rebuild the database
Migrations start at `002` and assume tables such as `users` already existed (the original baseline was created before migrations were tracked and never committed). Consequences: no fresh staging project, no disaster-recovery rebuild from git, and no CI that applies migrations to a throwaway Postgres.
**Fix (do once, ~1 hour):** with the Supabase CLI run `supabase db dump --schema public,storage --linked -f database/baseline/000_baseline_schema.sql` (plus `--data-only` for config tables such as `legal_frameworks`, `permissions`, `app_config`), commit it, and make the migration runner and a new CI job apply `000_baseline` followed by `002…` on a local `supabase start`. Then `database/tests/audit_rls_coverage.sql` and the RLS plans can run in CI. Until then use Supabase **branching** or a project restored from a production backup for staging.
