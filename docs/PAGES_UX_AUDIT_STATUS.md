# Pages UX Audit — Current Status

## Scope
Pages only, with explicit permission granted on 2026-08-16 to cross the Home Feed boundary for Page-specific distribution.

## Findings
- Page visitor posts are stored in `public.page_visitor_posts`, not `public.posts`.
- Published visitor posts correctly carry the real `author_id`, so the author identity is preserved.
- Page rules and visitor-post moderation are enforced by Page-specific RLS/permission checks.
- The authenticated Home Feed previously read only `get_home_feed_cursor()` over `public.posts`, so published Page visitor posts could disappear from Home even though they existed on the Page.

## Decision
Published visitor posts now enter the authenticated Home Feed only when:
1. the viewer is the visitor-post author, or
2. the viewer follows the Page, or
3. the viewer has Page content-management permission.

Blocked authors remain excluded.

The feed preserves the visitor post's real author and adds `Posted on <Page Name>` in the existing Home post location metadata so the relationship is understandable without creating a fake personal post.

Visitor posts are **not copied into `public.posts`**. This avoids turning a Page visitor post into a personal profile post and keeps Page moderation as the source of truth.

## Files / database changed
- `database/migrations/101_pages_visitor_posts_home_feed_cursor.sql`
- Supabase migration applied to project `xttxiwjllumskuhzxngx`.
- `docs/PAGES_UX_AUDIT_STATUS.md`

## Verified behavior
- Existing Monteshwory visitor post `75e6c64f-d5d1-4633-b63a-a2dbde781d45` is published.
- Calling `get_home_feed_cursor()` as its author returns that visitor post with `location = 'Posted on Monteshwory'`.
- Existing CI run #297 was fully successful before this change.
- CI run #298 for this Pages change is in progress.

## Remaining issue
Home currently renders Page visitor posts through the existing generic `PostCard`. The database distribution is now correct, but visitor-post interaction controls (likes/comments/bookmarks) are still backed by the normal `posts` interaction tables. A follow-up Pages-specific Home card should make visitor posts explicitly Page-scoped and expose only interactions that are actually supported, rather than showing misleading controls.
