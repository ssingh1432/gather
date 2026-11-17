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
- Base schema `001_initial_schema.sql` is referenced by README but is **not present** in `database/migrations/` — locate it or regenerate a baseline before creating a fresh environment.

## Fresh environment
Apply the baseline, then all migrations in order, create storage buckets/policies (included in migrations), deploy Edge Functions, set secrets, run `database/tests/`.

## Drift check
Compare `supabase_migrations.schema_migrations` with the files list; use `supabase db diff` against staging to detect untracked changes.
