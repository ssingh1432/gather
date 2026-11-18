# Performance, Load & Stress Test Plan

Run only on staging with production-like data (≥100k users, ≥1M posts seeded). Never against production.

## Targets (proposed, adjust after baseline)
| Flow | p95 | Error rate |
|---|---|---|
| Home feed first page (`get_home_feed_cursor`) | < 400 ms | < 0.5% |
| Feed next page | < 300 ms | < 0.5% |
| Search (`search_posts`, pg_trgm) | < 600 ms | < 1% |
| Create post | < 800 ms | < 1% |
| Notification list / unread count | < 250 ms | < 0.5% |
| Realtime message delivery | < 1.5 s | — |
| Web cold start (4G) | < 5 s | — |

## Scenarios
1. **Baseline**: 50 virtual users, mixed read 90 / write 10, 15 min.
2. **Load**: ramp to expected peak (start with 1,000 concurrent) over 30 min, hold 30 min.
3. **Stress**: keep ramping until p95 or error budget breaks; note the bottleneck (DB CPU, connections, Realtime, Storage).
4. **Spike**: 10× users in 60 s (viral post, push broadcast).
5. **Soak**: 8 h at 50% peak; watch memory, connections, table bloat.
6. **Fan-out**: `admin_send_broadcast` to the full audience; check dispatch function and Resend/FCM limits.
Tools: k6 (HTTP/RPC with test JWTs), Supabase Realtime test client, `pgbench` custom scripts, `EXPLAIN (ANALYZE, BUFFERS)` on feed/search RPCs.

## Database checks
`pg_stat_statements` top queries; missing indexes on new filters; sequential scans on large tables; connection pool saturation; RLS policy cost (policies calling heavy functions per row); autovacuum on hot tables (`notifications`, `auth_login_attempts`).

## Client checks
Flutter DevTools: jank frames in feed scroll, memory growth over 10 min scroll, video disposal (`feed_video_manager`), image cache size, battery on a mid-range Android, offline feed cache and background sync behaviour, Web bundle size (`main.dart.js`) and CanvasKit load.

## Exit criteria
Targets met at expected peak with 2× headroom; no data loss; no RLS bypass under load; recovery after stress within 5 min.
