# Gather — Architecture

## Overview
Gather is a Flutter client (Android, iOS, Web, Windows, macOS, Linux) talking directly to Supabase. There is no custom application server.

| Layer | Technology | Notes |
|---|---|---|
| Client | Flutter (`flutter_app/`) | Feature-first layout under `lib/features/`, shared code under `lib/shared/`, app plumbing under `lib/core/` |
| API | Supabase PostgREST + RPC | CRUD is table + RLS; privileged logic is `SECURITY DEFINER` RPCs |
| Auth | Supabase Auth | Email/password, Google Sign-In, MFA (see `mfa_service.dart`), device tracking (`user_devices`) |
| Realtime | Supabase Realtime | Feed, community chat, DMs, notifications |
| Storage | Supabase Storage | Buckets: post-media, avatars, community-media, page-media, story-media, page-visitor-media, moderation evidence |
| Jobs | pg_cron | Scheduled posts (every minute), event reminders (15 min), backup heartbeat (02:00 UTC), account-deletion purge (03:00 UTC) |
| Edge Functions | `supabase_functions/` | `auth-email`, `data-export`, `esewa-payment`, `link-preview`, `notification-dispatch` |
| Push / Email | FCM, Resend | Dispatched via `notification-dispatch` |
| Hosting | Hostinger VPS + Nginx (SPA) | Deployed by GitHub Actions rsync |
| CI/CD | `.github/workflows/flutter-ci.yml` | analyze+test -> (APK) / migrate -> deploy web |

## Client structure (`flutter_app/lib`)
- `core/` — env, router, theme, l10n (en/ne), accessibility settings, secure local storage, legal constants.
- `features/` — admin, auth, beta, bookmarks, communities, data, home, legal, media, messages, moderation, notifications, pages, posts, privacy, profile, reports, search.
- `shared/` — models, providers, services (auth, analytics, device, MFA, media upload, offline feed cache, realtime, push, performance), widgets, utils.

Platform-specific code uses conditional imports with `_io` / `_web` / `_stub` suffixes (e.g. `feed_offline_cache*.dart`, `remember_me_service*.dart`, `ads_bootstrap*.dart`).

## Backend principles
1. **RLS first.** Every table has RLS; Postgres checks table GRANTs *before* RLS, so a new table needs both (past 42501 errors came from missing GRANTs — see migrations 041, 091, 093, 108).
2. **Trusted logic in the database.** Rate limits, ownership checks, moderation actions, notification fan-out are triggers/RPCs, never client-side only.
3. **Admin actions are audited** via `log_admin_action` into `admin_audit_log`; security-relevant events go to `security_events` via `log_security_event`.
4. **Migrations are the source of truth** (`database/migrations/`, applied in CI by `scripts/apply_migrations.py`).

## Major subsystems
- **Feed/Posts:** keyset-cursor feed RPCs (`get_home_feed_cursor`, `get_community_feed`, `search_posts`), scheduled posts, version history, archive/pin, polls/events.
- **Communities:** roles/permissions, bans/warnings, invites, chat, recurring events, discovery (pg_trgm), analytics.
- **Professional Pages:** roles, followers, visitor posts, reviews, messaging, analytics, eSewa monetization.
- **Messaging:** 1:1 DMs with typing, receipts, voice notes, E2EE text (`dm_user_keys`, `dm_crypto`).
- **Safety & legal:** reports, moderation actions/strikes/appeals, evidence, keyword filters, media-moderation hooks, legal complaints, legal data requests, consent records, account deletion, data export.
- **Admin:** dashboard, moderation screen, legal dashboard, platform analytics tab.

See `DATABASE.md` for tables and RPCs.
