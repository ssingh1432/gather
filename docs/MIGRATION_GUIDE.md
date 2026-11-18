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
They were applied through the Supabase tool, so `supabase_migrations` has them but `repo_migrations` does not. All are idempotent: when CI runs on merge it re-applies them harmlessly and records them.

## Client compatibility
Keep RPC signatures backward compatible (add parameters with defaults) so older app builds keep working; deprecate in a later migration.
