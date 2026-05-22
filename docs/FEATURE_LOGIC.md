# MVP Feature Logic

## 1) Authentication
- Supabase email/password sign-up and login.
- Password reset via Supabase `resetPasswordForEmail`.
- Session restored on app startup.
- On first signup, create `users` profile row with username placeholder.

## 2) Profiles
- Editable fields: username, bio, profile_photo_url.
- Read-only counters: follower/following/post counts from aggregate queries/materialized helpers.

## 3) Communities
- Any user can create community.
- Join/leave community via membership table.
- Community feed = posts where `community_id` matches.

## 4) Posts
- Create post with text + optional image.
- Like/unlike through unique (user_id, post_id) table.
- Comments with parent support disabled in V1 (flat comments).
- Users can delete own posts; admin can remove any post.

## 5) Feed
- Home feed pulls:
  - posts from joined communities
  - posts from followed users
- Ordered by `created_at DESC`.
- Pagination with `created_at` cursor.

## 6) Social
- Follow/unfollow via `user_follows`.
- Save/bookmark via `bookmarks`.
- Search:
  - users: username ILIKE
  - communities: name ILIKE

## 7) Notifications
- Types: `new_follower`, `post_like`, `post_comment`.
- Inserted by DB triggers for core events.
- App shows unread count and allows mark-as-read.

## 8) Moderation
- Report post/user through `reports`.
- Block user through `user_blocks` (feed and interactions filtered).
- Admin:
  - ban/unban users
  - remove posts

## Admin role
- Role persisted in `users.role` enum (`user`, `moderator`, `admin`).
- Admin UI should be hidden unless role allows.
