# Gather — Testing Strategy (Phase 17)

## Pyramid
| Layer | Tool | Location | Runs in CI |
|---|---|---|---|
| Pure logic unit tests | flutter_test | `flutter_app/test/shared`, `test/core` | yes |
| Model / widget tests | flutter_test | `flutter_app/test/*`, `test/features` | yes |
| **DB↔client contract tests** | flutter_test reading `../database/migrations` | `flutter_app/test/contracts` | yes |
| Migration static lint | Python | `scripts/lint_migrations.py` (+ `test_lint_migrations.py`) | yes |
| Live RLS/privilege audit | `database/tests/audit_rls_coverage.sql` | after every migration batch |
| DB behaviour tests (RLS, RPC authorization) | SQL plans run as test users on **staging** | `database/tests/` | manual per release |
| End-to-end / integration | `integration_test` (not yet written) | — | planned |
| Load / stress | k6 or pgbench on staging | PERFORMANCE_LOAD_TEST_PLAN.md | before launch |

## What the new tests protect
- Password policy, feelings helpers, profile themes, responsive breakpoints.
- Contracts: theme keys ↔ `users_profile_theme_check`; reserved usernames ↔ `validate_username()`; `kPrivacyPolicyVersion` ↔ `handle_new_user` fallback; `report_category` has the 14 Phase 6 values.
- Migration safety: every table has RLS, every `SECURITY DEFINER` function sets `search_path`, filenames parse, PUBLIC-revoke lesson from migration 040. (First run found the missing RLS on `page_roles`.)

## Rules
- Every bug fix adds a regression test at the lowest layer that can catch it.
- A client mirror of a DB rule gets a contract test.
- A new table/RPC gets a `database/tests` plan covering: owner allowed, other user denied, anon denied, admin/moderator path.

## Known gaps
- No automated RLS tests in CI (needs a disposable Postgres with Supabase roles; recommended next: `supabase start` + pgTAP in a CI job).
- No integration/E2E tests for login, post, report, appeal flows.
- Edge functions have no tests (Deno test for SSRF guard and webhook signature verification recommended).
- Coverage is not measured; add `flutter test --coverage` and a floor.

## Regression suite before each release
`flutter analyze`, `flutter test`, migration lint, DB plans touched by the release, smoke list in PRODUCTION_CHECKLIST.md, Web + Android manual pass.
