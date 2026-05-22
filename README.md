# Gather MVP

## Completed features
- Supabase-backed auth and guarded routing.
- Home feed with pagination/reload and post cards.
- Communities list/search/join and community posting.
- Create community and create post (with optional image upload to `post_media`).
- Profile edit/logout, user profile follow/block.
- Search, notifications, bookmarks, reports, admin moderation tools.

## Setup
1. Copy `flutter_app/.env.example` to `flutter_app/.env` and fill Supabase URL/key.
2. `cd flutter_app && flutter pub get && flutter run`.

## Supabase migration
- Run SQL in `database/migrations/001_initial_schema.sql`.
- Ensure tables exactly match schema (users, community_memberships, post_comments, user_follows, user_blocks, post_media, etc).

## Storage bucket setup
- Create public bucket named `post-media`.
- Grant authenticated upload/read via Supabase policies.

## Remaining work
- Rich comments UX, realtime updates, robust optimistic state.
- Better moderation workflows and report resolution actions.
- Production-ready integration and e2e tests.

## Future short-video expansion
- Extend `post_media.media_type` for `video` posting UX.
- Add transcoding pipeline and adaptive streaming manifests.
- Add video feed ranking and watch-time analytics.
