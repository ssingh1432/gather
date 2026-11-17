# Gather — Phase 17 Testing Plan

## Current coverage (as of this commit)
- Flutter: ~26 test files (models, validators, l10n, accessibility, DM crypto/models, Pages contract tests, analytics tab, performance service).
- Database: 5 SQL scripts in `database/tests/` (Pages integrity, monetization, devices/MFA, profile identity).
- CI: analyze + test on every PR; no coverage report, no integration/e2e, no RLS suite, analyzer warnings non-fatal.

## Gaps and priorities
| # | Area | Why | Type |
|---|---|---|---|
| 1 | RLS/GRANT matrix (anon vs user A vs user B vs moderator vs admin) for core tables | Most past production bugs were GRANT/RLS | SQL (pgTAP or plain SQL) |
| 2 | Moderation RPCs: strike escalation (3/5/7), suspend/lift, ban/reinstate, appeals, permission checks | Legal/safety critical | SQL |
| 3 | Login lockout (5 fails / 15 min, normalisation) | Security | SQL |
| 4 | Consent, account deletion grace + purge, data export access | Privacy/legal | SQL |
| 5 | Storage policy tests per bucket | Upsert/RLS regressions | SQL / integration |
| 6 | Auth/session/MFA service logic | Security | Flutter unit (mock Supabase) |
| 7 | Report flow and admin moderation screen | Core safety UX | Flutter widget |
| 8 | Feed model parsing for mixed media (video/PDF must not hit image widgets) | Past ImageCodecException cascade | Flutter unit/widget |
| 9 | Legal screens + consent gate at signup | Compliance | Flutter widget |
| 10 | Integration/e2e against seeded staging | Release gate | `integration_test` |
| 11 | Load/stress on feed RPCs, search, realtime | Performance | k6/pgbench |
| 12 | Accessibility: semantics, large text, contrast, keyboard | Phase 14 | Flutter widget/golden |

## CI improvements
1. Add `flutter test --coverage` and publish the summary; set a baseline then ratchet.
2. Make analyzer warnings fatal once the backlog is cleared.
3. Add a `db-tests` job against a throwaway Supabase/Postgres (Docker) that applies migrations then runs `database/tests/*.sql`.
4. Add a migration lint step (duplicate-prefix warning, idempotency, GRANT presence for new tables).

## Manual audits before launch
Security: see SECURITY.md pen-test checklist. Privacy: verify consent record on signup, export contents, deletion purge. Legal: complaint -> action -> appeal flow end to end, audit entries present. Performance: EXPLAIN key feed queries at 100k+ rows; verify indexes.

## Status
Plan only — no new automated tests were added in this step because the sandbox has no Flutter SDK or Postgres to execute them; unexecuted tests should not be committed.
