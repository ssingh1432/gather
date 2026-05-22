# Gather Flutter MVP

## Run app
1. Install Flutter 3.22+.
2. Copy `.env.example` to `.env` and fill Supabase values.
3. Run:
   - `flutter pub get`
   - `flutter run`

## Supabase setup
- Uses `supabase_flutter` initialization in `lib/core/supabase_client.dart`.
- Auth flows: signup/login/logout/reset password.

## Database migration
Apply existing schema:
```bash
supabase db reset
# or execute database/migrations/001_initial_schema.sql against your project
```

## Completed MVP features
- App structure with clean layers (core, features, shared).
- GoRouter screen navigation for all required screens.
- Supabase auth service and state stream providers.
- Feed repository with chronological ordering and pagination.
- Post interactions: like/unlike/bookmark (repository methods).
- Baseline tests (validation/provider/mock/widget smoke).

## Remaining for short-video expansion
- Video upload/transcoding pipeline.
- Reels-style playback/feed ranking.
- Rich moderation tooling for video reports.
