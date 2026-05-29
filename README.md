# Gather MVP

## Completed features
- Auth flow (signup/login/forgot password/logout) with Supabase.
- Home feed with chronological ordering, removed-post filtering, and like/bookmark/comment actions.
- Communities list/search/join/leave and community detail posting.
- Post detail + comments.
- Profile view/edit and social follow/block primitives.
- Reporting + admin moderation actions (remove post, ban user, resolve report, refresh list).

## Local run steps
1. Install Flutter SDK (stable channel) and verify with `flutter --version`.
2. Copy env file: `cp flutter_app/.env.example flutter_app/.env`.
3. Fill `.env` with `SUPABASE_URL` and `SUPABASE_ANON_KEY`.
4. From `flutter_app/` run:
   - `flutter pub get`
   - `flutter analyze`
   - `flutter test`
   - `flutter run`

## Supabase setup
1. Create a Supabase project.
2. Run migration: `database/migrations/001_initial_schema.sql`.
3. Create one public Storage bucket named `post-media`.
4. Apply the SQL policies below exactly.

## Storage policy SQL (MVP)
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

## Remaining production tasks
- CI pipeline for format/analyze/test on every PR. See `.github/workflows/flutter-ci.yml`.
- Staging release gate/checklist before inviting testers. See `docs/STAGING_RELEASE_CHECKLIST.md`.
- Full integration/e2e tests against seeded Supabase test data.
- Rate limiting/abuse protection and advanced moderation tooling.
- Push notifications and analytics hardening.
