# Gather — Developer Guide

## Setup
```
git clone https://github.com/ssingh1432/gather && cd gather/flutter_app
cp .env.example .env   # fill SUPABASE_URL, SUPABASE_ANON_KEY, GOOGLE_WEB_CLIENT_ID
flutter pub get
flutter run -d chrome        # or an emulator / device
```
Use a **staging** Supabase project for development; never point local builds at production data.

## Commands
| Task | Command (from `flutter_app/`) |
|---|---|
| Analyze | `flutter analyze` |
| Unit/widget/contract tests | `flutter test` |
| Migration lint (repo root) | `python3 scripts/lint_migrations.py` |
| Lint tests (repo root) | `python3 -m unittest scripts/test_lint_migrations.py` |
| Localize hard-coded strings | `python3 scripts/localize_strings.py <table.py> <dart files>` (replaces literals with `AppL10n` lookups) |
| Web build | `flutter build web --release` |

## Conventions
- Supabase calls go through `features/data/repositories.dart` or a service in `shared/services/`.
- **Writes must use `.select()`** (or check the result): an `UPDATE` without it silently succeeds when RLS filters the row (caused stuck drafts).
- Never route video/PDF URLs into `Image.network`; check media type first (caused ImageCodecException cascades).
- Avoid N+1 queries in list items; fetch in the RPC or batch.
- All user-facing strings go through `AppL10n` (en + ne). Respect `AccessibilitySettings` (text scale, high contrast); add `Semantics` to icon-only buttons.
- Keep pure logic in `shared/utils/` so it is unit-testable.

## Database changes
1. New file `database/migrations/NNN_short_name.sql` (next free number; no duplicate prefixes).
2. Tables: `enable row level security`, policies, and explicit `grant ... to authenticated` (no default privileges exist).
3. `SECURITY DEFINER` functions: `set search_path = public`, explicit authorization check, `revoke ... from public, anon, authenticated` unless a client should call them, then grant narrowly.
4. Add/extend a test plan in `database/tests/` and run `scripts/lint_migrations.py`.
5. Update `docs/DATABASE.md`. Never edit an applied migration; add a new one.

## Adding a feature checklist
Migration + RLS → repository method → screen → l10n strings → semantics → tests (unit + contract if it mirrors a DB rule) → docs.

## Testing layout
See `docs/testing/TESTING_STRATEGY.md`.

## Do not
Commit `.env`, keystores, tokens; call `supabase.from()` for admin data from non-admin screens; bypass the consent flow; add a dependency without checking all target platforms.
