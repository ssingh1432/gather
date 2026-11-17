# Gather — Deployment Guide

## Environments
- Production: web at eiquoab.xyz (Hostinger VPS, Nginx SPA), Supabase project `xttxiwjllumskuhzxngx`.
- Staging: see `STAGING_RELEASE_CHECKLIST.md` (a separate Supabase project is recommended).

## Pipeline (`.github/workflows/flutter-ci.yml`)
1. `analyze-and-test` — `flutter pub get`, `flutter analyze`, `flutter test` (all PRs and pushes to main/work).
2. `build-android-apk` — release ARM64 APK on main push / manual run; artifact only on manual run.
3. `migrate` — on main push, runs `scripts/apply_migrations.py` against the Supabase project.
4. `deploy` — `flutter build web --release`, cache-busts `flutter_bootstrap.js`, rsyncs `build/web/` to the VPS.

### Required GitHub secrets
`SUPABASE_ACCESS_TOKEN`, `VPS_SSH_KEY`, `VPS_HOST`, `VPS_USERNAME`, `VPS_PORT`; optional Android signing: `RELEASE_KEYSTORE_BASE64`, `RELEASE_KEYSTORE_PASSWORD`.
If `SUPABASE_ACCESS_TOKEN` is missing, `migrate` fails and the deploy is blocked (intentional gate).

## Client configuration
`flutter_app/.env` (from `.env.example`): `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `GOOGLE_WEB_CLIENT_ID`. Never commit `.env`.

## Release steps
1. Merge PR to main after CI is green.
2. Watch `migrate` job: confirm new migrations applied (check Supabase migration history).
3. Watch `deploy`; load the site in a private window and verify the new `flutter_bootstrap.js?v=<sha>`.
4. Smoke test: sign in, post, comment, DM, open admin dashboard.
5. Edge Functions are deployed separately (`supabase functions deploy <name>`) — they are **not** part of CI.

## Pending external setup (Google Sign-In)
Google Cloud OAuth clients (Web/Android/iOS), Supabase Google provider config, real `GOOGLE_WEB_CLIENT_ID`, iOS `REVERSED_CLIENT_ID` in Info.plist, Windows/Linux protocol handler for `io.eiquoab.gather://`.

## Rollback
- Web: redeploy the previous commit (re-run the workflow on that SHA).
- DB: migrations are forward-only; write a new corrective migration. Take a backup before destructive migrations.

## Nginx requirements (verify on the VPS)
SPA fallback to `index.html`, HTTPS with HSTS, gzip/brotli for `main.dart.js`/canvaskit, short cache on `index.html`/`flutter_bootstrap.js`, long cache on hashed assets.
