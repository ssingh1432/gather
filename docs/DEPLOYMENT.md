# Gather — Deployment Guide

## Pipeline (`.github/workflows/flutter-ci.yml`)
1. `analyze-and-test` — `flutter analyze`, `flutter test` (all PRs and pushes)
2. `lint-migrations` — static SQL safety lint + its unit tests (no DB needed)
3. `build-android-apk` — manual or main only; ARM64 release; signing from secrets
4. `migrate` — main only; `scripts/apply_migrations.py` applies pending `database/migrations/*.sql`
5. `deploy` — main only; `flutter build web --release`, cache-bust `flutter_bootstrap.js`, rsync to VPS

## Required GitHub secrets
`SUPABASE_ACCESS_TOKEN` (migrations; if missing CI only warns and **skips** — migrations then need a manual push),
`VPS_SSH_KEY`, `VPS_HOST`, `VPS_USERNAME`, `VPS_PORT`, `RELEASE_KEYSTORE_BASE64`, `RELEASE_KEYSTORE_PASSWORD`.

## Supabase project (xttxiwjllumskuhzxngx)
- Edge functions: deploy each folder in `supabase_functions/`.
- Function secrets: see table below.
- Auth: enable Send-Email hook → `auth-email`; set Site URL + redirect URLs (incl. `io.eiquoab.gather://`); enable Google provider; enable MFA (TOTP); email confirmation ON.
- Database Webhook: INSERT on `public.notifications` → `notification-dispatch`, header with `NOTIFICATION_WEBHOOK_SECRET`.
- Extensions/cron: pg_cron, pg_trgm; confirm the cron jobs exist (`select jobname, schedule from cron.job;`): scheduled-post publishing, event reminders, deletion purge, backup heartbeat, suspension expiry, page notification jobs.
- Storage: verify buckets and policies match DATABASE.md §6; `data-exports`, `moderation-evidence`, `verification-docs` must be private.

| Function | Secrets |
|---|---|
| auth-email | RESEND_API_KEY, SEND_EMAIL_HOOK_SECRET, AUTH_EMAIL_FROM |
| notification-dispatch | NOTIFICATION_WEBHOOK_SECRET, RESEND_API_KEY, NOTIFICATION_EMAIL_FROM, FCM_PROJECT_ID, FCM_SERVICE_ACCOUNT_JSON, MANUAL_SERVICE_ROLE_KEY |
| esewa-payment | ESEWA_ENV, ESEWA_PRODUCT_CODE, ESEWA_SECRET_KEY |
| data-export, link-preview | none beyond auto-injected SUPABASE_URL / SERVICE_ROLE_KEY |

## Client config
`flutter_app/.env` (asset): SUPABASE_URL, SUPABASE_ANON_KEY, GOOGLE_WEB_CLIENT_ID. Firebase options for push. iOS `REVERSED_CLIENT_ID` in Info.plist.
Pending from earlier work: Google Cloud OAuth clients, Supabase Google provider config, Windows/Linux protocol handler registration.

## VPS / Nginx
SPA fallback (`try_files $uri /index.html`), HTTPS with auto-renewed certificate, keep `.well-known/` (excluded from rsync `--delete`).
Add security headers (HSTS, X-Content-Type-Options, Referrer-Policy, frame-ancestors/CSP) and gzip/brotli; long cache for hashed assets, no-cache for `index.html`.

## Release procedure
1. PR → CI green (analyze, tests, migration lint).
2. If PR contains `.sql`: confirm `SUPABASE_ACCESS_TOKEN` is set, or apply manually and verify `repo_migrations`.
3. Merge to main → migrate → deploy. Smoke test (PRODUCTION_CHECKLIST.md).
4. Rollback: redeploy previous commit's web build; DB rollbacks are forward-only fix migrations (never edit applied files).
