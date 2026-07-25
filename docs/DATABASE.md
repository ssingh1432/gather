# Gather — Database & API Documentation

Living reference for the Supabase/Postgres backend. Written as part of
Phase 10 Step 21; keep it updated when the schema changes rather than
letting it drift — a stale doc is worse than no doc.

## 1. How this backend is structured

Gather has no separate application server. The Flutter client talks
directly to Supabase:

- **Postgres** — all persistent data, plus business logic that must be
  atomic or trusted (rate limits, ownership checks, moderation actions,
  notification fan-out) implemented as triggers and `SECURITY DEFINER`
  functions.
- **PostgREST** (auto-generated REST API over every table, subject to
  RLS) — this is what `supabase_flutter`'s `.from('table')` calls hit.
  There is no hand-written REST layer; the "API" for straightforward
  CRUD *is* the table + its RLS policies.
- **RPC functions** (`postgres.rpc('function_name', params: {...})`) —
  used wherever a request needs to run as a specific SQL query with
  privileged joins/filters that would be awkward or unsafe to express as
  a plain `.select()` (feed assembly, search, admin actions).
- **pg_cron** — scheduled server-side jobs (scheduled-post publishing,
  event reminders, account-deletion purge, backup-integrity heartbeat).
  All are `SECURITY DEFINER` functions invoked directly by cron, never
  reachable from the client.
- **Storage buckets** — media, each with bucket-level MIME/size
  allowlists plus RLS-style storage policies for who can read/write.

Migrations live in `database/migrations/`, numbered and applied in
order. Historically some were also applied directly against the live
project via the Supabase MCP tool when noted in the file header — the
numbered file is still the source of truth for what's live; if a
migration's header says "applied directly," treat the file as
documentation of what was run, not as something still pending.

## 2. Core tables

| Table | Purpose |
|---|---|
| `users` | Profile + account state (status, privacy toggles, safe-search/child-safety flags, default post visibility). |
| `posts` | The central content table. `visibility`, `content_type` (text/repost/cross_post/announcement/poll/event), `community_id`, `reply_to_post_id`, sensitivity/pin/archive flags. |
| `post_media` | 0..N media rows per post (`media_url`, `media_type`, `scan_status`). |
| `post_likes`, `post_comments`, `bookmarks` | Standard interactions. |
| `scheduled_posts` | Not-yet-published posts (Step 10). Promoted to a real `posts` row by `publish_scheduled_posts()`. |
| `polls`, `poll_options`, `poll_votes` | Poll content type support. |
| `events`, `event_rsvps` | Event content type support; `event_rsvps.reminder_sent_at` dedupes reminder notifications. |
| `post_drafts` | Autosave drafts, never appear in any feed query. |
| `communities`, `community_memberships` | Communities and membership. |
| `user_follows`, `close_friends`, `user_blocks` | Social graph + the "friends" (close-friends) visibility tier. |
| `notifications` | Fan-out table; `type` is the `notification_type` enum (see §4). |
| `reports`, `keyword_filters`, `strikes` (etc.) | Moderation — see the Phase 6/7 migrations for the full set. |
| `legal_frameworks`, `data_requests`, account-deletion tables | Nepal legal compliance (Phase 3/4). |

Full column-level detail: read the table's most recent `alter table`/
`create table` statement rather than trusting this doc for exact types —
grep `database/migrations/*.sql` for the table name, latest match wins.

## 3. RPC "API" reference

Everything below is called via `client.rpc('name', params: {...})` from
Dart. All are `security invoker` unless noted — meaning normal RLS still
applies to whatever they query; they are conveniences/optimizations, not
privilege escalations.

| Function | Params | Returns | Notes |
|---|---|---|---|
| `get_home_feed(user_id, page_size, page_offset)` | offset pagination | feed rows | Legacy; kept for back-compat, nothing in the app calls it anymore as of Step 16. |
| `get_home_feed_cursor(user_id, page_size, cursor_is_pinned, cursor_created_at, cursor_id)` | keyset pagination | feed rows | **Current** home-feed RPC (Step 16). Pass all three cursor params `null` for page 1. |
| `get_community_feed(community_id, user_id, page_size, page_offset)` | offset pagination | feed rows | |
| `get_story_feed(...)` | — | story rows | Pre-Phase-10. |
| `search_posts(viewer_id, q, p_tag, p_mentioned_username, p_author_username, p_community_id, p_media_type, p_date_from, p_date_to, p_sort, page_size, page_offset)` | see above | post rows | Step 17. `p_sort` is `'recent'` or `'popular'`. |
| `trending_hashtags(days_back, result_limit)` | — | `{tag, post_count}` | |
| `publish_scheduled_posts()` | none | void | **Not client-callable** (revoked from anon/authenticated) — pg_cron only, every minute. |
| `send_event_reminders()` | none | void | **Not client-callable** — pg_cron only, every 15 min. |
| `purge_expired_account_deletions()` | none | void | **Not client-callable** — pg_cron only, daily. |
| `soft_remove_post`, `restore_post`, `suspend_user`, `ban_user`, `issue_warning`, `resolve_report`, `add_strike` | various | void | Moderator/admin actions; internally check `is_admin_or_mod()`/`ensure_admin_or_mod()`. |
| `fake_account_signals(min_score)` | int | scored user rows | Advisory heuristic for the admin review queue, never auto-acts. |

For anything not listed here (admin dashboard RPCs, legal-compliance
RPCs, etc.), search `database/migrations/*.sql` for `create or replace
function public.` — every one has a comment explaining its purpose.

## 4. Enums worth knowing

- `posts.visibility` — `public | followers | friends | community |
  private | unlisted` (Step 13; `friends` = the `close_friends` list,
  not mutual-follow).
- `posts.content_type` — `text | repost | cross_post | announcement |
  poll | event`.
- `scheduled_posts.status` — `pending | published | cancelled | failed`.
- `notification_type` — `new_follower, post_like, post_comment,
  community_post, post_reply, mention, scheduled_post_published,
  post_repost, poll_vote, event_reminder`. **Enum, not free text** —
  adding a new notification type requires its own `alter type ... add
  value` migration, applied in its own transaction before anything that
  uses the new value (see `038a`/`038b` for the pattern, and the postmortem
  in `039` for what happens if you forget the two-transaction rule).
- `post_media.scan_status` — `pending | clean | flagged` (Step 20 file-scan
  hook; nothing sets anything but `clean` today — no scanner wired up).

## 5. RLS — how visibility is actually enforced

The single source of truth for "can this viewer see this post" is the
`posts_select_visible_beta` policy on `public.posts` (see `035`). Every
RPC that reads posts (`get_home_feed*`, `search_posts`,
`get_community_feed`) is `security invoker`, so this policy applies
underneath them automatically — there is no parallel visibility logic to
keep in sync. `polls`/`events` delegate to it too (`exists (select 1 from
posts where id = post_id)` — see `038b`), rather than re-implementing
the visibility check, precisely so they can't drift out of sync with it
again the way they did before Step 13.

If you add a new table that references a post and needs the same
visibility gating, delegate to `posts` the same way — don't re-derive
the visibility rules.

## 6. Storage buckets

| Bucket | Public | Size limit | Allowed MIME types |
|---|---|---|---|
| `avatars` | yes | 5 MB | image/jpeg, png, webp |
| `post-media` | yes | 100 MB | jpeg/png/webp/gif, mp4/mov/webm/mkv, mpeg/mp4/aac/wav audio, pdf, doc(x) |
| `story-media` | yes | 100 MB | jpeg/png/webp/gif, mp4/mov/webm/mkv |
| `story-audio` | yes | 20 MB | mpeg/mp4/aac/wav audio |
| `moderation-evidence` | no | 25 MB | jpeg/png/webp, pdf |
| `data-exports` | no | 50 MB | any |

Upload paths are `{table-scope}/{postId-or-userId}/{kind}` (e.g.
`posts/{postId}/original`). Ownership on write is enforced by RLS-style
storage policies keyed off that path segment (see `039` for the
post-media fix — every bucket's INSERT policy should check that the
path's owning row belongs to `auth.uid()`, not just that the bucket name
matches).

**Known limitation** (documented, not fixed): all the "public" buckets
serve files via public, unsigned URLs. A post's media is reachable by
anyone who has the URL regardless of the post's `visibility` level.
IDs are UUIDs (not enumerable/guessable), and URLs aren't listed
anywhere public, but this is obscurity, not access control. Fixing this
properly means switching to signed, expiring URLs generated per-request
— a real architecture change (every image widget would need to fetch a
fresh signed URL instead of using a stored public one), tracked as
follow-up work rather than done piecemeal.

## 7. Indexes added in Phase 10 (Step 16/17)

- `idx_post_media_post_created (post_id, created_at)` — the single
  highest-impact index in this phase; every feed/search row's media
  lookup was previously unindexed beyond the PK.
- `idx_posts_pinned_created_id (is_pinned desc, created_at desc, id
  desc)` — backs `get_home_feed_cursor`'s keyset row-comparison.
- `idx_posts_text_content_trgm`, `idx_users_username_trgm` (GIN,
  `pg_trgm`) — back `search_posts`'s `ILIKE` filters with an actual
  index instead of a sequential scan.

## 8. Migration index

Numbered files in `database/migrations/`, applied in order (exact
filenames — generated from `ls database/migrations/`, not retyped by
hand, so this list can't drift from reality the way the first draft of
this doc did):

```
002_phase1_lock_foundation.sql
003_phase1_community_post_notifications.sql
004_phase2_analytics_moderation_hardening.sql
005_phase2_analytics_moderation_hardening.sql
006_phase4_closed_beta_feedback_ops.sql
007_phase5_home_feed_rich_interactions.sql
008_phase6_media_video_realtime.sql
009_privacy_settings.sql
010_post_visibility.sql                          (superseded by 035 — see §4)
011_mention_ids_and_action_bar.sql
012_login_rate_limiting.sql
013_security_events_log.sql
014_phase2_closeout_hardening.sql
015_privacy_compliance.sql
015a_add_pending_deletion_status.sql
016_nepal_legal_compliance.sql
017_fk_corrections_audit_note.sql
019_scheduled_account_deletion_purge.sql          (018 was applied live via MCP, no file)
020_auto_record_signup_consent.sql
020a_backfill_missing_signup_consent.sql
021_phase6_moderation_enums.sql
022_phase6_community_moderation.sql
023_phase6_moderation_evidence_bucket.sql
024_phase7_restrict_hide_comments.sql
025_phase7_content_safety.sql
026_phase8_admin_backend_baseline.sql
027_phase8_admin_audit_log.sql
028_phase8_security_storage_realtime_health_backup.sql
029_phase8_permissions_and_moderator_management.sql
030_phase8_notification_stats.sql
031_phase10_content_architecture.sql              (polls, events, drafts, edit history)
032_phase10_media_types.sql                       (audio + documents)
033_phase10_trending_hashtags.sql
034_phase10_feed_archive_pin.sql
035_phase10_scheduled_posts_and_visibility.sql    [Phase 10 Step 10 & 13]
036_phase10_feed_optimization.sql                 [Phase 10 Step 16]
037_phase10_search_integration.sql                [Phase 10 Step 17]
038a_phase10_notification_types.sql               [Phase 10 Step 19 — enum values, own transaction]
038b_phase10_notification_triggers.sql            [Phase 10 Step 19 — triggers + RLS fix]
039_phase10_security_hardening.sql                [Phase 10 Step 20]
```

Gaps in the numbering (001, 018) are real: 001 is the original base
schema, applied before migration-file tracking started (exists live,
not as a file — see §1); 018 was a hotfix applied directly via the
Supabase MCP tool with no corresponding file, same as a couple of others
noted inline above.

## 9. Known gaps / deliberately deferred

- Media URLs are not access-controlled per post visibility (§6).
- `search_posts` doesn't yet have a community picker in the client UI,
  though the RPC parameter (`p_community_id`) works.
- No formal DMCA-style copyright counter-notice workflow — copyright
  takedowns go through the generic report pipeline (category
  `copyright`), which is functional but not a dedicated legal workflow.
- No live malware/CSAM scanner — `post_media.scan_status` is the hook
  point, everything defaults `clean`.
