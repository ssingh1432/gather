# Gather — Migration Guide

## How migrations run
`scripts/apply_migrations.py` runs in CI (`migrate` job) on pushes to main, needing `SUPABASE_ACCESS_TOKEN`. Files in `database/migrations/` are applied in filename order.

## Rules
1. New file, next number, descriptive name. Never edit an applied migration; add a corrective one.
2. Idempotent: `if not exists`, `create or replace`, guarded `do $$` blocks. `alter type ... add value` cannot be used in the same transaction as its first use — split into `a`/`b` files (see 038a/038b, 044a/044b).
3. Include GRANTs and RLS policies in the same migration as the table.
4. Revoke execute from `public`/`anon` on privileged functions.
5. Never apply schema by ad-hoc SQL on production; if unavoidable, back-port the exact SQL into a numbered file immediately.

## Known quirks
- Duplicate numeric prefixes exist (e.g. 104, 105, 108, 109, 113, 114, 117, 120). Order within a prefix is alphabetical.
- Gaps (e.g. 018, 118) — confirm whether intentionally unused.
- Base schema `001_initial_schema.sql` is **not present** in `database/migrations/` (history starts at 002). To build a fresh environment, generate a baseline from production (`supabase db dump --schema public`) and add it before 002 in a separate bootstrap path — do not add it to the CI-applied folder.

## Fresh environment
Apply the baseline, then all migrations in order, create storage buckets/policies (included in migrations), deploy Edge Functions, set secrets, run `database/tests/`.

## Tracking & drift
CI tracks applied files (with checksums) in `public.repo_migrations`; migrations applied through the Supabase MCP `apply_migration` tool are tracked separately in `supabase_migrations.schema_migrations`. Compare both against the files list, and use `supabase db diff` against staging to detect untracked changes. `scripts/apply_migrations.py` refuses to run if `repo_migrations` is empty.

## Lint
`scripts/lint_migrations.py` runs in CI: new migrations (number > 126) must have a unique prefix, valid name, and — if they create a table — enable RLS and include a GRANT. Legacy duplicates are reported as notices only; never rename applied files.
