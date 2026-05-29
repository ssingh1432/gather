# Staging Release Checklist

Use this checklist before inviting testers or promoting a build beyond local development. A release should not move forward until every required item is checked or has an owner and documented exception.

## 1) Code health gate

- [ ] Latest branch is rebased/merged against the target release branch.
- [ ] GitHub Actions **Flutter CI** passes for the release commit.
- [ ] `flutter pub get` completes successfully from `flutter_app/`.
- [ ] `flutter analyze` returns no issues from `flutter_app/`.
- [ ] `flutter test` passes all tests from `flutter_app/`.
- [ ] No secrets, Supabase keys, or local `.env` values were committed.

## 2) Supabase staging environment

- [ ] Staging Supabase project exists and is separate from production.
- [ ] `database/migrations/001_initial_schema.sql` has been applied to staging.
- [ ] Public Storage bucket `post-media` exists in staging.
- [ ] Storage policies for `post-media` have been applied.
- [ ] Flutter staging build uses the staging `SUPABASE_URL` and `SUPABASE_ANON_KEY`.
- [ ] Seed/test accounts exist for at least two standard users and one admin/moderator.

## 3) Authentication and user profile flow

- [ ] New user signup succeeds.
- [ ] Signup creates or updates the matching row in `public.users` with `id`, `email`, `username`, and `status`.
- [ ] Existing user login succeeds.
- [ ] Logout succeeds and returns the user to the auth flow.
- [ ] Password reset email delivery works in the staging environment.
- [ ] Banned users are signed out and prevented from continuing normal app actions.

## 4) Community and post flow

- [ ] User can create a community.
- [ ] User can search/list communities.
- [ ] User can join and leave a community.
- [ ] User can create a text post from the home/create-post flow.
- [ ] User can create a community post.
- [ ] Image upload to `post-media` succeeds and the image is visible in the app.
- [ ] Home feed shows expected chronological content.
- [ ] Community detail feed shows expected community content.
- [ ] Removed posts do not appear in home, community, bookmark, or post-detail views.

## 5) Social actions and notifications

- [ ] User can like and unlike a post.
- [ ] User can bookmark and unbookmark a post.
- [ ] User can add a comment to a post.
- [ ] Comments insert into `post_comments.user_id`.
- [ ] User can follow and unfollow another user.
- [ ] User can block another user.
- [ ] Like, comment, and follow actions create expected notification rows when applicable.

## 6) Reporting and moderation

- [ ] User can report a post.
- [ ] User can report another user.
- [ ] Admin/moderator can view open reports.
- [ ] Admin/moderator can remove a reported post.
- [ ] Admin/moderator can ban a reported user.
- [ ] Moderation actions resolve the associated report and refresh the report list.
- [ ] Non-admin users cannot access or perform admin moderation actions.

## 7) Security and RLS spot checks

- [ ] User cannot edit another user's profile.
- [ ] User cannot edit or delete another user's post.
- [ ] Duplicate likes, bookmarks, follows, and memberships are rejected or safely de-duped.
- [ ] User can only read/update their own bookmarks and notifications.
- [ ] Admin/moderator-only policies are verified with a non-admin test user.

## 8) Release readiness

- [ ] Known issues are documented with severity and owner.
- [ ] Tester instructions include environment, test accounts, and feedback channel.
- [ ] Rollback plan is documented for the staging build.
- [ ] Crash/error monitoring plan is documented, even if manual for MVP.
- [ ] Go/no-go decision is recorded with date, commit SHA, and approver.
