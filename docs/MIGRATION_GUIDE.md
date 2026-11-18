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

## Pending: migrations 127 and 128
- **127** (page_roles RLS): live check on 2026-11-18 showed RLS already on, so this is a no-op that closes repo/live drift.
- **128** (advisor hardening): pins `search_path` on 7 functions, revokes anon EXECUTE on 5 helpers, restricts what logged-out callers can write via `log_security_event`, documents deny-all tables. After applying, verify: password-reset request still logs; search → trending hashtags loads; admin screens load; run the security advisors again.
Both are idempotent. Merging to main applies them through CI.

## Client compatibility
Keep RPC signatures backward compatible (add parameters with defaults) so older app builds keep working; deprecate in a later migration.
