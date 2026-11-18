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

## Pending: migration 127 (page_roles RLS)
Before merging, check production: `select relrowsecurity from pg_class where oid = 'public.page_roles'::regclass;`
- `false` → the table was exposed; 127 fixes it. Check `page_roles` rows for unexpected role grants before and after.
- `true` → someone enabled it by hand; 127 is a no-op that closes the repo/live drift.
On staging, confirm page team management, page switching and role-based page features still work with RLS on.

## Client compatibility
Keep RPC signatures backward compatible (add parameters with defaults) so older app builds keep working; deprecate in a later migration.
