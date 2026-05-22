# Architecture (MVP)

## Principles
- Keep V1 simple and reliable.
- Security first with strict RLS.
- Modular boundaries to enable future video features.
- Chronological feed for V1.

## High-level components
1. Flutter client
2. Supabase Auth
3. Postgres + RLS
4. Supabase Storage for images/media
5. FCM for push notifications
6. Optional analytics SDK

## Flutter module layout
- `features/auth`
- `features/profile`
- `features/communities`
- `features/posts`
- `features/feed`
- `features/social`
- `features/notifications`
- `features/moderation`
- `features/admin`

Each module has:
- `data/` (Supabase datasource + repository impl)
- `domain/` (entities + use cases)
- `presentation/` (screens, controllers, widgets)

## Data model strategy for future video
- Posts are content containers.
- `post_media` supports media type enum (`image`, `video`) now; app uses `image` in MVP.
- Feed query logic is media-agnostic and sorts by `created_at`.
- Video module can later add transcoding metadata table without changing social graph.

## Security model
- All app tables have RLS enabled.
- Users can modify only their own resources unless admin/moderator role.
- Soft-ban support via `users.status` for auth gating in app and policies.

## Operational readiness
- Indexes on feed, follows, community membership, comments.
- Trigger-driven follower counts and lightweight notifications.
- Audit fields (`created_at`, `updated_at`) across mutable tables.
