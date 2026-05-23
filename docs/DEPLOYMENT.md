# Deployment Guide (MVP)

## 1) Supabase project bootstrap
1. Create project.
2. Run `database/migrations/001_initial_schema.sql`.
3. Create **public** storage bucket: `post-media`.
4. Apply storage policies:

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

## 2) App environment
Create `flutter_app/.env`:
- `SUPABASE_URL=...`
- `SUPABASE_ANON_KEY=...`

## 3) Local verification before hosting
From `flutter_app/` run:
1. `flutter pub get`
2. `flutter analyze`
3. `flutter test`
4. `flutter run`

## 4) Completed vs remaining
Completed now:
- Core auth/feed/community/post/profile/moderation flows wired to Supabase.
- Removed post filtering in feed/community/bookmark views.

Still required before production hosting:
- Automated CI pipeline and gated release checklist.
- Seeded staging data + integration/e2e suites.
- Incident monitoring, backup/restore drills, and scale testing.
