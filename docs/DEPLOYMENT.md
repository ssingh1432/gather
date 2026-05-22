# Deployment Guide

## 1. Supabase setup
1. Create a new Supabase project.
2. Run `database/migrations/001_initial_schema.sql` in SQL editor.
3. Create storage buckets:
   - `profile-photos` (private with signed URLs)
   - `post-media` (private with signed URLs)
   - `community-images` (private with signed URLs)
4. Configure auth settings:
   - Enable email/password.
   - Set redirect URL for password reset.

## 2. Secrets & env
Flutter `.env` / build vars:
- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `FCM_SENDER_ID` / Firebase config values
- `ANALYTICS_PROVIDER`

## 3. Flutter build
- Android: `flutter build appbundle --release`
- iOS: `flutter build ipa --release`
- Web (optional admin panel): `flutter build web --release`

## 4. Push notifications
1. Create Firebase project.
2. Add Android/iOS app identifiers.
3. Configure FCM tokens in app and save token per user device.
4. Use Supabase Edge Function / background worker to dispatch push on new notifications.

## 5. Monitoring
- Enable Supabase logs and query performance monitoring.
- Configure analytics dashboards for DAU/retention/community engagement.
- Add crash reporting (Firebase Crashlytics or Sentry).

## 6. Release process
1. Run tests from checklist.
2. Apply migrations to staging.
3. Smoke test auth/feed/post/moderation.
4. Promote to production.
