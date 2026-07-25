# Phase 10 Testing — Step 22

Honesty up front: this sandbox has no Flutter SDK and no device/browser,
so I could not run `flutter test`, `flutter analyze`, a widget test, or
anything requiring an emulator. What I *could* do — write real unit
tests for pure logic, and verify the riskiest server-side behavior
directly against the live Supabase project (the scheduled-posts
publish-pipeline test in Step 20, run and then cleaned up) — is done.
Everything else below is a concrete checklist for you to run through
CI/devices, not a claim that it already passed.

## 1. Unit tests (automated, in-repo)

`flutter_app/test/scheduled_post_and_cursor_test.dart` — new this phase:
- `ScheduledPostModel.fromMap`: full row, missing-optional-fields
  defaults, and a `failed` row with `failure_reason`.
- `FeedCursor.fromLastPost`: carries `isPinned`/`createdAt`/`id` through
  correctly.

Existing: `post_model_test.dart` (PostModel parsing, incl. thumbnail URL
derivation), `widget_test.dart` (harness smoke test).

Run: `cd flutter_app && flutter test` — this is exactly what your CI's
`flutter test` step already runs; nothing new needed there.

## 2. Server-side verification (done, not just planned)

Run directly against the live project during Step 20, then cleaned up:
- Inserted a real `scheduled_posts` row, called `publish_scheduled_posts()`
  manually, confirmed a real `posts` row + `scheduled_post_published`
  notification were created, confirmed `scheduled_posts.status` flipped
  to `published`. This is what caught the two blocking bugs — without
  running it for real, both would have shipped silently broken.
- Confirmed `notification_type` enum values applied correctly across two
  separate transactions (couldn't have used them in the same one).
- Confirmed `pg_cron` jobs are registered and `active`: `purge-expired-
  account-deletions`, `backup-integrity-heartbeat`, `publish-scheduled-
  posts`, `send-event-reminders`.

## 3. Widget / UI — manual checklist

- [ ] Composer: pick each of the 6 visibility options; confirm the
      picker's icon/label match, and that **Community only** is hidden
      unless composing inside a community.
- [ ] Composer: tap the schedule button, pick a date/time, confirm the
      Publish button relabels to "Schedule" and back to "Publish" when
      cleared.
- [ ] Composer: try to schedule with a poll or event attached — should
      block with the inline "can't be scheduled yet" message.
- [ ] Scheduled Posts screen (`/scheduled-posts`, linked from Settings):
      list renders, reschedule updates the time shown, cancel removes it
      from the list and shows the confirmation dialog first.
- [ ] Edit-post screen: visibility dropdown shows all 6 options and
      saves correctly.
- [ ] Search screen: `#tag`, `@mention`, plain text, and each filter
      (author, media type, sort, date range) individually and combined;
      trending hashtags on the empty state still work.
- [ ] Notifications screen: trigger each new type at least once (mention
      someone, reply to a post, repost, vote in a poll) and confirm the
      icon/label match what's in `_iconFor`/`_messageFor`.
- [ ] Home feed: scroll past the first page repeatedly — confirm no
      duplicate or skipped posts appear (this is exactly the failure
      mode keyset pagination is supposed to prevent; OFFSET pagination
      would show it under concurrent posting, cursor pagination should
      not).

## 4. Integration testing — manual checklist

- [ ] Full scheduled-post lifecycle from the app: schedule a post with an
      image → wait for it to publish (or shorten the wait by scheduling
      1–2 minutes out) → confirm it appears in the feed with the right
      media, tags, and visibility, and that a notification arrived.
- [ ] Visibility end-to-end: as User A, create one post per visibility
      level. As User B (not following A, no close-friend/community
      relationship), confirm only `public`/`unlisted` are visible. Add
      the follow/close-friend/community relationship one at a time and
      confirm the matching post becomes visible and *only* that one.
- [ ] Search end-to-end: create posts across visibility levels, confirm
      `unlisted`/`private`/`followers`-only posts you can't otherwise see
      do not appear in another user's search results (RLS should already
      guarantee this since `search_posts` is invoker-rights, but verify
      it isn't accidentally leaking via the media-type/author join).
- [ ] Event RSVP → reminder: RSVP "going" to an event starting within the
      next hour, confirm a notification arrives within 15 minutes (the
      cron interval) and `reminder_sent_at` gets set (no duplicate
      reminder on the next cron tick).

## 5. Performance testing

- [ ] `EXPLAIN ANALYZE` on `get_home_feed_cursor` and `search_posts` for
      an account with a realistic follow/community graph — confirm the
      planner is using `idx_post_media_post_created`,
      `idx_posts_pinned_created_id`, and the trigram indexes rather than
      sequential-scanning `post_media`/`posts`/`users`.
- [ ] Compare feed load latency between page 1 and, say, page 10 —
      keyset pagination should show roughly flat latency; if it's
      growing with depth, something's using OFFSET again or the index
      isn't being hit.
- [ ] Confirm `_prefetchMedia` isn't causing jank on lower-end devices —
      it's fire-and-forget/best-effort by design, but worth watching on
      a real mid-range Android device during a long scroll session.

## 6. Upload testing

- [ ] Confirm the Step 20 storage-ownership fix: as User A, try to craft
      an upload request targeting User B's `posts/{B's postId}/...` path
      — should be rejected by the new storage INSERT policy. (This is
      the kind of thing worth a one-off manual `curl`/Postman test
      against the Storage REST endpoint with A's JWT, since the Flutter
      client itself would never construct such a request.)
- [ ] Upload a file at/near each bucket's size limit and just over it —
      confirm the over-limit case is rejected with a clear error, not a
      silent failure or app crash.
- [ ] Upload a disallowed MIME type (e.g. `.exe` renamed to `.jpg`) to
      `post-media` — bucket-level allowlist checks the actual content
      type, not just the extension, so confirm it's still rejected.
- [ ] Schedule a post with an image and confirm the upload path uses the
      `scheduled_posts.id`-keyed folder correctly and that
      `attachMedia`/the publisher correctly carries it over to the real
      `post_media` row.

## 7. Offline testing

- [ ] Load the home feed once successfully, then go to airplane
      mode/disable network, force-quit and reopen the app — confirm the
      "Offline — tap to retry" banner appears and the last-seen posts
      still render instead of a blank error screen.
- [ ] Repeat on web specifically (localStorage-backed cache) and on
      iOS/Android/desktop (file-backed cache via path_provider) — these
      are two different code paths (`feed_offline_cache_web.dart` vs
      `feed_offline_cache_io.dart`) and need to each be checked, not
      just one.
- [ ] Confirm the offline banner clears on the next successful load and
      doesn't get "stuck" showing stale data as if it were live.

## 8. Security testing

- [ ] Re-run the storage-ownership check from §6 as an explicit security
      test, not just a functional one.
- [ ] Confirm `guard_scheduled_post_create`'s caps: try to create a 51st
      pending scheduled post, and an 11th within one hour — both should
      be rejected with the specific error messages in `039`.
- [ ] Confirm `guard_post_create` still correctly rejects a client trying
      to post as `author_id` = someone else's id (the null-`auth.uid()`
      bypass added in `039` should never trigger for a real authenticated
      client call — verify a normal logged-in session still has
      `auth.uid()` populated and still gets the ownership check).
- [ ] Spot-check RLS directly in the SQL editor with `set role
      authenticated; set request.jwt.claim.sub = '<some other user's
      id>';` against a `private`/`unlisted` post you don't own — should
      return zero rows.

## 9. Cross-platform testing

- [ ] Android + iOS: composer schedule picker (native date/time pickers
      differ per platform — confirm both render usably).
- [ ] Web: offline cache via `localStorage` (§7), and confirm
      `showDatePicker`/`showTimePicker` work the same as mobile (Flutter
      Web's Material pickers can behave slightly differently in some
      browsers).
- [ ] Desktop (if in scope for this release): confirm `path_provider`'s
      `getApplicationDocumentsDirectory()` resolves to a writable location
      on the target OS — this is the one dependency in this phase that's
      genuinely platform-sensitive.

---

Once you've run through this and CI is green, Phase 10 (Steps 2–22) is
complete. See `docs/DATABASE.md` for the schema/API reference and this
session's commit messages (`61dd63b` through `94b57ae`) for the
step-by-step implementation history, including the three bugs found and
fixed along the way.
