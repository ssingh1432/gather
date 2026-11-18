# Gather — Architecture

Flutter client talking directly to Supabase. No hand-written application server.

```
Flutter app (Android / iOS / Web / macOS / Windows / Linux)
  │  supabase_flutter (JWT in secure storage)
  ▼
Supabase
  ├─ Auth            email+password, Google, TOTP 2FA (AAL2), Send-Email hook
  ├─ PostgREST       CRUD on tables, filtered by RLS
  ├─ Postgres        tables, RLS, SECURITY DEFINER RPCs, triggers, pg_cron
  ├─ Realtime        feed, community chat, DMs, notifications
  ├─ Storage         post-media, avatars, community-media, page-media, story-media,
  │                  moderation-evidence, data-exports, verification-docs (private ones noted in DATABASE.md §6)
  └─ Edge Functions  auth-email, data-export, esewa-payment, link-preview, notification-dispatch
External: Resend (email), FCM (push), eSewa (payments), Google Sign-In
Hosting: Flutter Web build → Hostinger VPS (Nginx SPA) via GitHub Actions
```

## Layers (flutter_app/lib)
| Path | Responsibility |
|---|---|
| `core/` | env, router (go_router), theme, accessibility, l10n (en/ne), responsive breakpoints, legal constants, secure storage |
| `features/<area>/` | screens per area: auth, home, posts, profile, communities, pages, messages, admin, legal, moderation, privacy, notifications, search, bookmarks, beta |
| `features/data/repositories.dart` | Supabase access (`.from()`, `.rpc()`, storage). Screens should not call Supabase directly. |
| `shared/services/` | cross-cutting services: auth, MFA, devices, push, analytics, performance, offline feed cache, realtime, uploads |
| `shared/models/` | plain Dart models with `fromMap` |
| `shared/utils/` | pure helpers (validators, time_ago, recurrence expander) — easiest code to unit test |

State management: Riverpod. Navigation: go_router. Platform splits use conditional imports (`*_io.dart`, `*_web.dart`, `*_stub.dart`).

## Where trust lives
The client is untrusted. Anything that must be correct is enforced in Postgres:
ownership and visibility (RLS), rate limits and content guards (triggers), moderation actions and role changes
(`SECURITY DEFINER` RPCs with explicit authorization), audit logging, and scheduled jobs (pg_cron, not client-callable).
Client-side validators (password, username) only give instant feedback; contract tests keep them aligned with the DB.

## Key flows
- **Sign-up**: client stamps `privacy_policy_version` into auth metadata → `handle_new_user` trigger records consent (mig. 020) → email confirmation via auth-email hook → Resend.
- **Login**: `check_login_lockout` (5 failures / 15 min) → sign-in → `record_login_attempt` → `register_device` (new-device security event).
- **Feed**: keyset-cursor RPCs (`get_home_feed_cursor`, `get_community_feed`, `search_posts`); offline cache per platform.
- **Moderation**: `reports` (14 categories) → queue → warn / strike / suspend / ban RPCs → `moderation_actions` + `admin_audit_log` → appeal (`submit_appeal`).
- **Legal**: `legal_complaints`, `legal_data_requests`, `legal_frameworks` (data-driven, new laws = insert). Admin legal dashboard.
- **Privacy**: consent records, `request_data_export` → `data-export` function → signed URL (7 days); `request_account_deletion` (14-day grace) → cron purge.
- **Notifications**: DB trigger inserts into `notifications` → Database Webhook → `notification-dispatch` → FCM push + Resend email (best effort, never blocks the insert).
- **Payments**: `initiate_page_payment` RPC → `esewa-payment` function signs fields server-side (secret never on client).

## Cross-platform notes
Web uses `web:` package (not dart:html), no `path_provider`; blob URLs must not be revoked early after image picking. Desktop OAuth uses the `io.eiquoab.gather://` deep link. Ads and some media plugins are mobile-only behind stubs.

## Extending
New legal regime → insert into `legal_frameworks`. New report category → enum migration + client label map + docs.
New table → migration with RLS **and** explicit `grant` (see DATABASE.md §9, migration 041), then a policy test.
