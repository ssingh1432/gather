-- 010_post_visibility.sql
-- Enforces per-post visibility (public / friends / only_me) at the compose
-- level. Previously default_post_visibility was stored as a user preference
-- but never actually read anywhere — every post was implicitly public
-- (modulo the existing private-account/follow gating). This migration adds
-- a real `visibility` column on posts and folds it into the SELECT RLS
-- policy so it's enforced everywhere posts are read (feed, profile grid,
-- get_home_feed/get_community_feed RPCs, single-post fetch), since none of
-- those are SECURITY DEFINER and all go through this same policy.

-- 1. Column ---------------------------------------------------------------
alter table public.posts
  add column if not exists visibility text not null default 'public';

alter table public.posts
  add constraint posts_visibility_check
  check (visibility in ('public', 'friends', 'only_me'));

comment on column public.posts.visibility is
  'Who can see this post: public (subject to existing private-account/follow gating), friends (author''s followers + author only), only_me (author only). Set at compose time, defaults from users.default_post_visibility.';

-- 2. SELECT policy ----------------------------------------------------------
-- Replaces posts_select_visible_beta. Same beta/removed/block gating as
-- before, plus:
--   - author can always see their own posts regardless of visibility
--   - 'public' posts still go through can_view_author_posts (handles
--     private-account + follow-required case)
--   - 'friends' posts require the viewer to follow the author
--   - 'only_me' posts are excluded for everyone but the author (no branch
--     matches, so the row is filtered out)
drop policy if exists posts_select_visible_beta on public.posts;

create policy posts_select_visible_beta on public.posts
for select
using (
  current_user_has_beta_access()
  and is_removed = false
  and (author_id = auth.uid() or not users_are_blocked(auth.uid(), author_id))
  and (
    author_id = auth.uid()
    or (
      visibility = 'public'
      and can_view_author_posts(auth.uid(), author_id)
    )
    or (
      visibility = 'friends'
      and exists (
        select 1 from public.user_follows uf
        where uf.follower_id = auth.uid() and uf.following_id = author_id
      )
    )
  )
);
