-- Migration 098: closes the known gap flagged in migration 097 — until
-- now, publish_status = 'published' was enforced only in application
-- queries (the feed RPCs and FeedRepository), not in RLS itself. Any
-- future code path that reads posts directly — admin panel, moderation
-- queue, realtime subscriptions, an ad-hoc query someone adds later —
-- would have been able to see another user's still-'publishing' post
-- (partial content, media not yet attached) without going through any
-- of the paths that were explicitly filtered.
--
-- posts_select_admin_all (is_admin_or_mod()) is left untouched:
-- admin/moderator visibility into pending posts is a reasonable
-- capability, not the gap being closed here.
--
-- The author can always see their own post regardless of status — this
-- doesn't restrict anything for them, it only stops OTHER users from
-- seeing a post that isn't finished publishing yet, via any path.
drop policy if exists posts_select_visible_beta on public.posts;

create policy posts_select_visible_beta on public.posts
for select
using (
  current_user_has_beta_access()
  and is_removed = false
  and (author_id = auth.uid() or publish_status = 'published')
  and (author_id = auth.uid() or not users_are_blocked(auth.uid(), author_id))
  and (
    author_id = auth.uid()
    or (visibility = any (array['public', 'unlisted']) and can_view_author_posts(auth.uid(), author_id))
    or (visibility = 'followers' and exists (
      select 1 from user_follows uf
      where uf.follower_id = auth.uid() and uf.following_id = posts.author_id
    ))
    or (visibility = 'friends' and exists (
      select 1 from close_friends cf
      where cf.user_id = posts.author_id and cf.friend_id = auth.uid()
    ))
    or (visibility = 'community' and post_id_visible_via_community(community_id, auth.uid()))
  )
);
