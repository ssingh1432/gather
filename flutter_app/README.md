# Flutter App (Gather)

## Local run
1. Copy `.env.example` to `.env`.
2. Set:
   - `SUPABASE_URL`
   - `SUPABASE_ANON_KEY`
3. Run:
```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

## Supabase setup (MVP)
1. Run `../database/migrations/001_initial_schema.sql`.
2. Create public bucket `post-media`.
3. Apply the exact policies:

```sql
create policy "post_media_public_read"
on storage.objects
for select
to public
using (bucket_id = 'post-media');

create policy "post_media_auth_upload"
on storage.objects
for insert
to authenticated
with check (bucket_id = 'post-media');

create policy "post_media_auth_update"
on storage.objects
for update
to authenticated
using (bucket_id = 'post-media')
with check (bucket_id = 'post-media');

create policy "post_media_auth_delete"
on storage.objects
for delete
to authenticated
using (bucket_id = 'post-media');
```

## Status
- Completed: auth, feed, communities, post detail comments, profile edit, bookmarks, report flow, admin moderation actions.
- Remaining for production: CI/CD, staged environment promotion, e2e coverage, abuse prevention, observability.


## Local Supabase Test Checklist
- [ ] `flutter pub get` completes successfully.
- [ ] `flutter analyze` returns no issues.
- [ ] `flutter test` passes all tests.
- [ ] Community detail screen: can create post, like/unlike, comment navigation, bookmark/unbookmark.
- [ ] Admin moderation: remove post and ban user both resolve reports and refresh the report list.
- [ ] Storage bucket is public `post-media` and upload/read works with configured policies.
- [ ] Signup inserts/updates `users` table row with `id`, `email`, `username`, `status`.
- [ ] Comment inserts target `post_comments.user_id` (not `author_id`).
- [ ] Removed posts (`is_removed = true`) do not appear in feed/community/post-detail queries.
- [ ] Banned users are signed out and prevented from logging in.
