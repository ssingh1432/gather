# Flutter App (Gather)

## Current completed features
- Auth screens (login/signup/forgot) and auth redirect guards.
- Feed, communities, posts, profile, search, notifications, bookmarks, reports, moderation.
- Reusable UI: post card, community card, profile avatar.

## Setup
```bash
cp .env.example .env
flutter pub get
flutter run
```

## Supabase migration steps
1. Open Supabase SQL editor.
2. Execute `../database/migrations/001_initial_schema.sql`.
3. Verify `users`, `community_memberships`, `post_comments`, `user_follows`, `user_blocks`, `post_media` exist.

## Storage setup
- Create `post-media` bucket (public read).
- Allow authenticated uploads for post owners.

## Remaining work
- Improve bottom nav shell UX and route polish.
- Add richer validation and offline behavior.
- Expand automated integration tests.

## Short-video roadmap
- Post creation toggle for image/video.
- Video player feed and preload strategy.
- Creator analytics and moderation for video-specific reports.
