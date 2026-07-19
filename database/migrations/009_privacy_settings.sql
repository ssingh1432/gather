-- Privacy & notification settings, modeled after common social-app patterns
-- (Instagram/Facebook-style granular audience controls). Backs the new
-- Settings screen: default post audience, friends-list visibility, who
-- can message/tag you, activity status, read receipts, and a per-category
-- notification preferences blob.

alter table public.users
  add column if not exists default_post_visibility text not null default 'public',
  add column if not exists friends_list_visibility text not null default 'everyone',
  add column if not exists message_privacy text not null default 'everyone',
  add column if not exists tag_privacy text not null default 'everyone',
  add column if not exists show_activity_status boolean not null default true,
  add column if not exists show_read_receipts boolean not null default true,
  add column if not exists notification_settings jsonb not null default '{
    "likes": true,
    "comments": true,
    "friend_requests": true,
    "mentions": true,
    "messages": true,
    "community_activity": true
  }'::jsonb;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'users_default_post_visibility_check'
  ) then
    alter table public.users
      add constraint users_default_post_visibility_check
        check (default_post_visibility in ('public','friends','only_me')) not valid;
    alter table public.users validate constraint users_default_post_visibility_check;
  end if;

  if not exists (
    select 1 from pg_constraint where conname = 'users_friends_list_visibility_check'
  ) then
    alter table public.users
      add constraint users_friends_list_visibility_check
        check (friends_list_visibility in ('everyone','friends','only_me')) not valid;
    alter table public.users validate constraint users_friends_list_visibility_check;
  end if;

  if not exists (
    select 1 from pg_constraint where conname = 'users_message_privacy_check'
  ) then
    alter table public.users
      add constraint users_message_privacy_check
        check (message_privacy in ('everyone','friends','no_one')) not valid;
    alter table public.users validate constraint users_message_privacy_check;
  end if;

  if not exists (
    select 1 from pg_constraint where conname = 'users_tag_privacy_check'
  ) then
    alter table public.users
      add constraint users_tag_privacy_check
        check (tag_privacy in ('everyone','friends','no_one')) not valid;
    alter table public.users validate constraint users_tag_privacy_check;
  end if;
end $$;

notify pgrst, 'reload schema';
