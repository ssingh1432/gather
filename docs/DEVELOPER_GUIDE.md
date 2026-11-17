# Gather — Developer Guide

## Setup
1. Install Flutter (stable). `cd flutter_app && cp .env.example .env` and fill `SUPABASE_URL`, `SUPABASE_ANON_KEY`.
2. `flutter pub get && flutter analyze && flutter test && flutter run`.

## Conventions
- Feature-first: new UI goes in `lib/features/<feature>/`; cross-feature code in `lib/shared/`.
- Platform-specific code: `_io` / `_web` / `_stub` files with conditional imports.
- All user-facing strings go through `core/l10n` (en + ne); `scripts/localize_strings.py` helps migrate hard-coded strings.
- Respect accessibility settings (`core/accessibility`).
- Prefer RPCs for privileged/multi-step operations; never trust client-side checks alone.

## Adding a feature (checklist)
1. Migration in `database/migrations/NNN_description.sql` (next free number; avoid duplicate numbers — several exist already).
2. Table: enable RLS, add policies **and** GRANTs (`authenticated`, and `service_role` if Edge Functions use it).
3. RPCs: `SECURITY DEFINER` + `set search_path = public`, explicit auth check, `grant execute` only to needed roles.
4. Storage: policies for SELECT/INSERT/UPDATE/DELETE (upsert needs SELECT).
5. Mutations that must confirm success: chain `.select()` on UPDATE/INSERT so silent RLS no-ops are detected.
6. Avoid N+1 fetches in list items; fetch in the feed RPC.
7. Never pass video/PDF URLs to `Image.network`; branch on media type.
8. Add tests (see below), update `DATABASE.md`.
9. Open a PR; CI must pass; migration applies on merge to main.

## Testing
- Flutter: `flutter test` (unit, widget, contract tests under `flutter_app/test/`).
- Database: SQL scripts in `database/tests/` — run against staging, not production.
- See `TESTING_PLAN.md` for the coverage plan.

## Common pitfalls (from project history)
- Missing GRANT -> 42501 even with correct RLS.
- Direct `execute_sql` schema changes cause live-vs-repo drift.
- Duplicate migration numbers (e.g. several `120_*`, `113_*`) — order is by filename; keep them idempotent.
- Parallel automated processes may modify the same area; pull before starting.
