# Testing Checklist

## Unit tests (Flutter)
- Auth use cases: signup/login/logout/reset password.
- Feed query builder and cursor pagination.
- Follow/unfollow and like/unlike toggles.
- Notification mapping by type.

## Widget tests
- Auth flow screens render and validate forms.
- Home feed list, empty state, pagination.
- Community details screen and join/leave action.
- Post composer text/image validation.

## Integration tests
- Login -> create post -> like/comment -> notification appears.
- Join community -> post -> appears in community feed.
- Follow user -> their post appears in home feed.
- Block user -> blocked user content hidden.

## Database tests (SQL)
- RLS: user cannot edit another user's profile/post.
- RLS: admin can remove any post.
- Unique constraints: likes/bookmarks/follows duplicates rejected.
- Trigger tests for notification inserts.

## Manual QA
- Password reset email delivery.
- Profile photo upload and retrieval permissions.
- Report flow for post and user.
- Ban user blocks posting/commenting/login in app layer.

## Non-functional checks
- Query plans use indexes for feed endpoints.
- Basic rate limiting in API/client retries.
- Crash-free startup with expired sessions.
