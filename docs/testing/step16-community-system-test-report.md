# Step 16 — Community System Testing Report

Scope: the Community System built across Steps 11-15 (Events, Discovery,
Analytics, Notifications, Security). Covers unit, integration/security, and
performance testing. Load testing against realistic data volume was
deliberately **not** run against the live production database — see
"Load testing" below for why, and what to do instead.

## Unit tests (run by CI on every push via `flutter test`)

New files:
- `test/recurrence_expander_test.dart` — 19 tests covering DAILY/WEEKLY/
  MONTHLY expansion, INTERVAL, COUNT, UNTIL, the 104-occurrence hard cap,
  and fallback behavior for malformed rules.
- `test/time_ago_test.dart` — 5 tests covering `formatEventDateTime`,
  including AM/PM boundary cases (midnight, noon) and minute padding.

**Bug found and fixed by writing these tests, not by review:**
`RecurrenceExpander`'s `BYDAY` handling mapped every weekday code to the
wrong `DateTime.weekday` value (it assumed RRULE's SU-first ordering lined
up with Dart's Monday=1 ordering via a plain `+1`; it doesn't — the
mapping needed a 6-day rotation). Picking "weekly on Saturday" would have
silently generated Sunday occurrences instead. This path is currently
unreachable through the app's own UI (the event form only ever sets
`FREQ=WEEKLY` or `FREQ=MONTHLY` with no `BYDAY`), so it hadn't shipped a
user-visible bug yet, but it was a live defect in a documented,
general-purpose utility. Fixed in
`lib/shared/utils/recurrence_expander.dart` and covered by four new
regression tests (`BYDAY=SU`, `BYDAY=SA`, `BYDAY=MO,WE,FR`, and a
same-week-exclusion case). All weekday assumptions in the tests were
verified against the real 2026 calendar before being hardcoded.

Also removed a dead no-op helper (`_withTime`) left over from Step 11.

## Integration / security testing (run live against Supabase, cleaned up after)

Method: real inserts/updates/selects against the production database using
impersonated authenticated sessions (`set local request.jwt.claims`), not
just static policy review. Every test community/event/RSVP created for
this was deleted afterward.

**Bug found and fixed:** `event_occurrence_rsvps`'s write policy
(`WITH CHECK`) only required `user_id = auth.uid()` — it never checked
that the occurrence being RSVP'd to was actually visible to the caller.
Verified live: created a `secret`-visibility test community with an event,
confirmed a non-member correctly got zero rows back when trying to
`SELECT` the event's occurrence (RLS composes correctly there, transitively,
through `event_occurrences -> events -> communities` — this was the
initial hypothesis for a bug, and testing disproved it), but the **same
non-member could still `INSERT` an RSVP row** referencing that occurrence
id, because a foreign key constraint only checks that the referenced row
*exists*, not that it's RLS-visible to the current role. Fixed by adding
an explicit visibility check to the policy's `WITH CHECK` clause
(migration 070). Re-verified: the exploit attempt now fails with
`new row violates row-level security policy`, and a legitimate member's
RSVP still succeeds.

Also re-confirmed (from Step 15, still holding): event `created_by`
spoofing is blocked, event rate-limiting/duplicate-detection triggers
correctly reject abuse, and length constraints correctly reject oversized
input.

## Performance testing

Method: `EXPLAIN (COSTS OFF)` on the query shapes underlying the Step 13
analytics RPCs, run twice — once to find gaps, once after fixing them.

**Gaps found and fixed (migration 071):**
- `community_memberships` had no index covering `created_at`, so the
  "recent joins" lookup used by `trending_communities` and
  `community_retention` was a full `Seq Scan`. Added
  `idx_community_memberships_community_created (community_id, created_at)`.
- `post_likes` had no `created_at` coverage at all, used by
  `community_daily_active_members` and `community_retention`'s activity
  union. Added `idx_post_likes_post_created (post_id, created_at)`.

Both were verified with `SET LOCAL enable_seqscan = off` to confirm
Postgres *can* and *will* use the new indexes — at the current tiny data
volume the planner correctly still prefers a plain scan for some queries,
which is expected, not a sign the index is wrong.

`community_chat_messages` and `post_comments` already had adequate
`(community_id/post_id, created_at)` indexes from earlier work; no changes
needed there.

## Load testing — not run against production, and why

Genuine load testing (thousands of synthetic members/posts/events) was not
executed against the live Supabase project for this step, to avoid
polluting production data — member counts, notification fan-out, and
analytics would all be affected by throwaway synthetic rows, and cleanup
at that volume is itself risky.

Supabase branching (`Supabase:create_branch`) would be the right tool for
this — it gives an isolated copy of the schema to load-test against
without touching production — but creating one may have a cost
implication that wasn't cleared beforehand. **Recommend**: if you want
real load numbers before a public launch, say so explicitly and I'll set
up a branch (checking cost first) and run a proper load test — bulk-insert
a realistic member/post/event volume, re-run the same `EXPLAIN`s at scale,
and time the fan-out notification triggers (event creation, chat
announcements) under a large membership.

## Regression coverage going forward

The two live-database bugs found this step (RSVP write-visibility, the
`BYDAY` weekday mapping) are now both covered by permanent tests/migrations
so they can't silently regress:
- `BYDAY` mapping: `test/recurrence_expander_test.dart` runs on every push.
- RSVP write-visibility: no automated regression test exists for this yet
  (would need a Postgres-level test harness, which this project doesn't
  have set up) — it's protected by the migration itself, but if the RLS
  policy is ever rewritten by a future migration, this specific check
  needs to be manually re-verified the way it was here.
