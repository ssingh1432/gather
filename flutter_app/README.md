# Flutter App (Gather)

## Setup
1. Copy `.env.example` to `.env` in `flutter_app/`.
2. Set:
   - `SUPABASE_URL`
   - `SUPABASE_ANON_KEY`
3. Run:
```bash
flutter pub get
flutter run
```

> App startup is resilient if `.env` is missing, but Supabase features need both values.

## Supabase migration steps
1. Open Supabase SQL editor.
2. Execute `../database/migrations/001_initial_schema.sql`.
3. Verify core tables exist: `users`, `posts`, `post_comments`, `community_memberships`, `user_follows`, `bookmarks`, `post_likes`, `post_media`.

## Storage setup (`post-media`)
1. In Supabase Storage, create bucket `post-media`.
2. Make bucket public for read.
3. Add policies on `storage.objects`:

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
