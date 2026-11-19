# Load tests (k6)

**Staging only.** `lib.js` refuses to run against the production project unless you set
`I_KNOW_THIS_IS_PRODUCTION=yes` (don't).

1. Create a staging Supabase project, apply `database/migrations/*`, seed ≥100k users / ≥1M posts
   (a seed script is the missing piece — generate with `generate_series` in SQL).
2. Create ~50 test users with a shared password; set `TEST_USERS`, `TEST_PASSWORD`.
3. Run, e.g. `k6 run -e SCENARIO=baseline -e SUPABASE_URL=... -e SUPABASE_ANON_KEY=... -e TEST_USERS=... -e TEST_PASSWORD=... scripts/loadtest/scenarios.js`
   Scenarios: `smoke` (1 min sanity), `baseline`, `load`, `stress`, `spike`, `soak`.
4. Pass/fail thresholds are the targets in `docs/testing/PERFORMANCE_LOAD_TEST_PLAN.md`; k6 exits non-zero when missed.
5. While it runs, watch Supabase: DB CPU, connections, Realtime, `pg_stat_statements`; afterwards `EXPLAIN (ANALYZE, BUFFERS)` the slowest RPCs.

Writes (post creation, reports, DMs), Realtime fan-out and `admin_send_broadcast` are covered by the plan but not scripted yet.
