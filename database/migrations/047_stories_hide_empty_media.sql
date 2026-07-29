-- 047: Never surface a story with an empty/missing media_url.
--
-- create_post's story flow (story_bar.dart) inserts a `stories` row with
-- media_url = '' BEFORE the actual upload starts, then updates it once the
-- upload succeeds, and best-effort deletes the row if the upload fails.
-- That client-side rollback only runs if the app is still alive to run the
-- catch block — if the app is killed, backgrounded past an OS timeout, or
-- loses network mid-upload, the placeholder row can be orphaned with
-- media_url = '' forever, showing up in the story bar as a broken tile and
-- crashing/blanking the viewer. This is a server-side safety net so a
-- client-side bug or interruption can never leak a broken story into any
-- reader's feed, on any platform.
--
-- get_story_feed() already existed on the live project without a
-- corresponding migration file (see docs/DATABASE.md note on drift) — this
-- migration is written as CREATE OR REPLACE against the function's actual
-- live definition, so it's safe to apply without a preceding DROP.

begin;

create or replace function public.get_story_feed(p_user_id uuid)
returns table(
  author_id uuid,
  author_username text,
  author_avatar_url text,
  story_count integer,
  has_unseen boolean,
  latest_created_at timestamp with time zone,
  latest_thumbnail_url text
)
language sql
stable
set search_path to 'public'
as $function$
  select
    s.author_id,
    u.username,
    u.profile_photo_url,
    count(*)::int as story_count,
    bool_or(sv.viewer_id is null) as has_unseen,
    max(s.created_at) as latest_created_at,
    (
      select coalesce(s2.thumbnail_url, case when s2.media_type = 'image' then s2.media_url end)
      from public.stories s2
      where s2.author_id = s.author_id
        and s2.expires_at > now()
        and s2.media_url is not null and s2.media_url <> ''
      order by s2.created_at desc
      limit 1
    ) as latest_thumbnail_url
  from public.stories s
  join public.users u on u.id = s.author_id
  left join public.story_views sv on sv.story_id = s.id and sv.viewer_id = p_user_id
  where s.expires_at > now()
    and s.media_url is not null and s.media_url <> ''
    and not exists (
      select 1 from public.user_blocks ub
      where (ub.blocker_id = p_user_id and ub.blocked_id = s.author_id)
         or (ub.blocker_id = s.author_id and ub.blocked_id = p_user_id)
    )
    and (
      s.author_id = p_user_id
      or exists (select 1 from public.user_follows uf where uf.follower_id = p_user_id and uf.following_id = s.author_id)
    )
  group by s.author_id, u.username, u.profile_photo_url
  order by (s.author_id = p_user_id) desc, has_unseen desc, latest_created_at desc;
$function$;

commit;

-- Own-transaction housekeeping: clear out any placeholder rows that are
-- already orphaned in production from a past interrupted upload, so this
-- fix also cleans up existing broken state, not just future inserts.
-- Anything older than 1 hour with an empty media_url is unambiguously
-- abandoned (a live in-progress upload finishes in seconds).
begin;

delete from public.stories
where (media_url is null or media_url = '')
  and created_at < now() - interval '1 hour';

commit;
