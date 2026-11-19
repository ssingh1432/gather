# Phase 17 — Execution report (2026-11-18/19)

What was actually run, against what, and what it found. "Not run" items are listed honestly at the end.

## 1. Security audit — RUN (live database + code)
- Supabase security advisors (before/after), live RLS/privilege audit (`database/tests/audit_rls_coverage.sql`), anon-reachability test of changed policies, role-based tests of new RPCs (rollback transactions).
- Found and fixed: 3 anonymous read leaks (downloads, story views, stories), 7 mutable `search_path`s, over-broad anon EXECUTE (5 revoked), log pollution via anonymous `log_security_event`, moderators able to read legal/police data requests, 2 buckets without MIME allowlists, missing repo RLS statement for `page_roles`. Migrations 127–132, all applied and verified. Details: SECURITY.md.
- Open (dashboard-only): leaked-password protection, anonymous sign-ins.

## 2. Database + API optimization — RUN
- Performance advisors: 159 `auth_rls_initplan`, 137 unindexed FKs, 1 duplicate index, 77 unused indexes, 119 multiple permissive policies.
- Fixed (migration 133, applied live): all 159 policies now use `(select auth.uid())`; 137 FK indexes created; duplicate unique constraint removed. **Equivalence proof:** row counts visible to an admin and two users across 20 tables were identical before and after (see below). Advisor re-count: 0 policies and 0 FKs left.
- Measured: cache hit 99.99 %, index hit 99.99 %, no table with notable dead tuples, DB size 97 MB, largest table 9.5k rows.
- Top cost is Supabase Realtime's own WAL query (860k calls) then the app's per-minute crons (`publish_scheduled_posts` 5.4 ms/169k calls, `publish_scheduled_page_posts` 6.0 ms, `send_event_reminders` 58 ms/11k calls every 15 min). They scan 4–16-row tables and `scheduled_posts` already has the right partial index (`idx_scheduled_posts_due`); the time is function overhead, so no index would help. No change.
- Deliberately NOT changed: the 77 "unused" indexes (too little traffic for usage stats to be meaningful; re-check after launch load) and 119 overlapping permissive policies (merging them risks changing who can see what; do it table by table with tests).
- Recommended, needs a retention decision (irreversible deletes): `beta_error_logs` (9.5k rows, largest table) and `analytics_events` (4.4k) grow without bound. Add a cron prune once retention periods are agreed (MAINTENANCE.md).
- API surface: 5 Edge Functions and the RPC set reviewed for authorization and grants (SECURITY.md, API.md).

## 3. Regression testing — RUN in CI
- `flutter analyze`: 0 errors. `flutter test`: all passing (existing + new unit/contract tests). Migration lint: 0 errors. All green on main.
- Migrations 127–133 are idempotent and were re-applied by CI on merge.

## 4. Code cleanup / dead code — RUN
- Import-graph scan from `main.dart`: 191 files, 189 reachable; the 2 unreachable files are tiny helpers used only by tests (kept).
- Analyzer: 147 infos → removed 14 unused/unnecessary imports and fixed 1 unsafe `BuildContext` use across an async gap. Remaining ~133 are one deprecation (`flutter/material.dart` → `material_ui`), tracked in MAINTENANCE.md.
- Build: Android APK was broken on Flutter 3.50 (AGP 9 mismatch) since Phase 14/15; fixed by pinning the APK job to 3.47.x (verified with a version matrix).

## 5. NOT run (needs staging, devices or people)
| Item | Why not | Where to continue |
|---|---|---|
| Load / stress / soak testing | Must not hit production; no staging project | PERFORMANCE_LOAD_TEST_PLAN.md |
| Penetration test (active) | Needs staging + test accounts; only the database layer was probed | SECURITY_AUDIT_AND_PENTEST_CHECKLIST.md |
| Accessibility testing | Needs TalkBack/VoiceOver/NVDA and a human | ACCESSIBILITY_TEST_CHECKLIST.md |
| Privacy + legal compliance audit | Needs a Nepali lawyer for the legal part | PRIVACY_AND_LEGAL_AUDIT.md |
| End-to-end UI tests | No device/emulator here; Flutter SDK not available in the sandbox | add `integration_test` |
| Automated RLS tests in CI | Needs a disposable Postgres with Supabase roles | TESTING_STRATEGY.md |
