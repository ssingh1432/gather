-- Gather: current-state SNAPSHOT of the 22 base tables that no numbered migration creates
-- (the original 001_initial_schema.sql is not in the repo), plus the public enum types.
-- Generated 2026-11-17 from the live project with database/baseline/generate_base_snapshot.sql;
-- secrets removed.
--
-- NOT part of the CI-applied folder. It reflects the CURRENT schema (columns/policies added by
-- migrations 002-126 are already included), so do not replay 002+ on top of it without checking
-- for duplicate-policy errors. Use it as a reference, or as the start of a fresh database whose
-- migration tracking is seeded as "all applied".
-- Helper functions used by policies/triggers (is_admin_or_mod, current_user_has_beta_access,
-- guard_*, touch_updated_at, ...) and storage buckets are NOT included.

do $$ begin if not exists (select 1 from pg_type where typname='user_status' and typnamespace='public'::regnamespace) then create type public.user_status as enum ('active', 'banned', 'pending_deletion', 'suspended'); end if; end $$;
do $$ begin if not exists (select 1 from pg_type where typname='user_role' and typnamespace='public'::regnamespace) then create type public.user_role as enum ('user', 'moderator', 'admin'); end if; end $$;
do $$ begin if not exists (select 1 from pg_type where typname='notification_type' and typnamespace='public'::regnamespace) then create type public.notification_type as enum ('new_follower', 'post_like', 'post_comment', 'community_post', 'post_reply', 'mention', 'scheduled_post_published', 'post_repost', 'poll_vote', 'event_reminder', 'security_alert', 'login_alert', 'moderation_alert', 'appeal_update', 'report_update', 'admin_broadcast', 'community_invite', 'community_join_request', 'community_join_update', 'community_role_changed', 'community_warning', 'community_ban', 'community_announcement', 'community_event_created', 'page_new_follower', 'page_new_post', 'page_follow_invite', 'page_message_received', 'page_message_reply', 'page_review_received', 'page_review_response', 'page_new_event', 'page_event_reminder', 'page_verification_updated'); end if; end $$;
do $$ begin if not exists (select 1 from pg_type where typname='report_target_type' and typnamespace='public'::regnamespace) then create type public.report_target_type as enum ('user', 'post'); end if; end $$;
do $$ begin if not exists (select 1 from pg_type where typname='report_status' and typnamespace='public'::regnamespace) then create type public.report_status as enum ('open', 'reviewing', 'resolved', 'dismissed'); end if; end $$;
do $$ begin if not exists (select 1 from pg_type where typname='media_type' and typnamespace='public'::regnamespace) then create type public.media_type as enum ('image', 'video', 'audio', 'document'); end if; end $$;
do $$ begin if not exists (select 1 from pg_type where typname='beta_feedback_kind' and typnamespace='public'::regnamespace) then create type public.beta_feedback_kind as enum ('bug', 'general', 'feature_request'); end if; end $$;
do $$ begin if not exists (select 1 from pg_type where typname='beta_feedback_tag' and typnamespace='public'::regnamespace) then create type public.beta_feedback_tag as enum ('bug', 'ux', 'feature_request'); end if; end $$;
do $$ begin if not exists (select 1 from pg_type where typname='beta_feedback_status' and typnamespace='public'::regnamespace) then create type public.beta_feedback_status as enum ('open', 'resolved', 'ignored'); end if; end $$;
do $$ begin if not exists (select 1 from pg_type where typname='report_category' and typnamespace='public'::regnamespace) then create type public.report_category as enum ('spam', 'fake_account', 'harassment', 'hate_speech', 'violence', 'terrorism', 'child_abuse', 'adult_content', 'copyright', 'scam', 'impersonation', 'self_harm', 'drugs', 'other'); end if; end $$;
create table if not exists public.allowed_beta_emails (
  id bigint not null default nextval('allowed_beta_emails_id_seq'::regclass),
  email_address text not null,
  created_at timestamp with time zone default now()
);
create table if not exists public.app_config (
  key text not null,
  value jsonb not null,
  updated_at timestamp with time zone not null default now()
);
create table if not exists public.bookmarks (
  user_id uuid not null,
  post_id uuid not null,
  created_at timestamp with time zone not null default now()
);
create table if not exists public.close_friends (
  user_id uuid not null,
  friend_id uuid not null,
  created_at timestamp with time zone not null default now()
);
create table if not exists public.communities (
  id uuid not null default gen_random_uuid(),
  name text not null,
  description text not null default ''::text,
  image_url text,
  created_by uuid not null,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  visibility text not null default 'public'::text,
  category text,
  rules text,
  banner_url text,
  member_count integer not null default 0,
  is_verified boolean not null default false,
  category_id uuid,
  location text,
  website text,
  language text not null default 'en'::text,
  min_age integer,
  posting_permission text not null default 'all_members'::text,
  is_paid boolean not null default false,
  price_cents integer,
  pinned_announcement_post_id uuid,
  last_activity_at timestamp with time zone not null default now(),
  latitude double precision,
  longitude double precision
);
create table if not exists public.community_memberships (
  user_id uuid not null,
  community_id uuid not null,
  created_at timestamp with time zone not null default now(),
  role text not null default 'member'::text
);
create table if not exists public.creator_ad_impressions (
  id uuid not null default gen_random_uuid(),
  creator_id uuid not null,
  post_id uuid not null,
  viewer_id uuid,
  created_at timestamp with time zone not null default now()
);
create table if not exists public.link_previews (
  url text not null,
  title text,
  description text,
  image_url text,
  site_name text,
  fetched_at timestamp with time zone not null default now()
);
create table if not exists public.notifications (
  id uuid not null default gen_random_uuid(),
  recipient_id uuid not null,
  actor_id uuid,
  post_id uuid,
  type notification_type not null,
  is_read boolean not null default false,
  created_at timestamp with time zone not null default now(),
  metadata jsonb not null default '{}'::jsonb
);
create table if not exists public.post_comments (
  id uuid not null default gen_random_uuid(),
  post_id uuid not null,
  user_id uuid not null,
  content text not null,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  parent_comment_id uuid,
  reply_count integer not null default 0,
  is_hidden boolean not null default false
);
create table if not exists public.post_downloads (
  id uuid not null default gen_random_uuid(),
  post_id uuid not null,
  user_id uuid not null,
  created_at timestamp with time zone not null default now()
);
create table if not exists public.post_likes (
  user_id uuid not null,
  post_id uuid not null,
  created_at timestamp with time zone not null default now()
);
create table if not exists public.post_media (
  id uuid not null default gen_random_uuid(),
  post_id uuid not null,
  media_type media_type not null default 'image'::media_type,
  media_url text not null,
  created_at timestamp with time zone not null default now(),
  scan_status text not null default 'clean'::text
);
create table if not exists public.posts (
  id uuid not null default gen_random_uuid(),
  author_id uuid not null,
  community_id uuid,
  text_content text,
  is_removed boolean not null default false,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  location text,
  feeling text,
  tags text[] not null default '{}'::text[],
  reply_to_post_id uuid,
  share_count integer not null default 0,
  mentioned_user_ids uuid[] not null default '{}'::uuid[],
  mentioned_usernames text[] not null default '{}'::text[],
  reply_count integer not null default 0,
  location_lat double precision,
  location_lng double precision,
  view_count integer not null default 0,
  link_preview_url text,
  link_preview_title text,
  link_preview_description text,
  link_preview_image_url text,
  link_preview_site_name text,
  download_count_cached integer not null default 0,
  visibility text not null default 'public'::text,
  is_sensitive boolean not null default false,
  content_type text not null default 'text'::text,
  is_pinned boolean not null default false,
  pinned_at timestamp with time zone,
  archived_at timestamp with time zone,
  edited_at timestamp with time zone,
  edit_count integer not null default 0,
  scheduled_for timestamp with time zone,
  ai_moderation_status text not null default 'not_scanned'::text,
  publish_status text not null default 'published'::text
);
create table if not exists public.reports (
  id uuid not null default gen_random_uuid(),
  reporter_id uuid not null,
  target_type report_target_type not null,
  target_user_id uuid,
  target_post_id uuid,
  reason text not null,
  status report_status not null default 'open'::report_status,
  reviewed_by uuid,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  category report_category,
  is_automated boolean not null default false
);
create table if not exists public.stories (
  id uuid not null default gen_random_uuid(),
  author_id uuid not null default auth.uid(),
  media_url text not null,
  media_type text not null,
  created_at timestamp with time zone not null default now(),
  expires_at timestamp with time zone not null default (now() + '24:00:00'::interval),
  audio_track_id uuid,
  audio_url text,
  audio_title text,
  mute_original_audio boolean not null default false,
  thumbnail_url text
);
create table if not exists public.story_audio_tracks (
  id uuid not null default gen_random_uuid(),
  title text not null,
  artist text,
  audio_url text not null,
  cover_url text,
  duration_seconds integer,
  is_active boolean not null default true,
  created_at timestamp with time zone not null default now()
);
create table if not exists public.story_views (
  story_id uuid not null,
  viewer_id uuid not null,
  viewed_at timestamp with time zone not null default now()
);
create table if not exists public.user_blocks (
  blocker_id uuid not null,
  blocked_id uuid not null,
  created_at timestamp with time zone not null default now()
);
create table if not exists public.user_follows (
  follower_id uuid not null,
  following_id uuid not null,
  created_at timestamp with time zone not null default now()
);
create table if not exists public.user_payout_preferences (
  user_id uuid not null,
  provider text not null,
  holder_name text not null,
  masked_reference text not null,
  status text not null default 'pending_review'::text,
  notes text,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);
create table if not exists public.users (
  id uuid not null,
  email text not null,
  username text not null,
  bio text default ''::text,
  profile_photo_url text,
  role user_role not null default 'user'::user_role,
  status user_status not null default 'active'::user_status,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  fcm_token text,
  fcm_token_updated_at timestamp with time zone,
  display_name text,
  cover_photo_url text,
  location text,
  language_preference text not null default 'ne'::text,
  website_url text,
  interests text[] not null default '{}'::text[],
  phone_number text,
  phone_verified boolean not null default false,
  pronouns text,
  is_private boolean not null default false,
  account_mode text not null default 'personal'::text,
  is_verified boolean not null default false,
  monetization_opt_in boolean not null default false,
  monetization_status text not null default 'not_started'::text,
  pinned_post_id uuid,
  default_post_visibility text not null default 'public'::text,
  friends_list_visibility text not null default 'everyone'::text,
  message_privacy text not null default 'everyone'::text,
  tag_privacy text not null default 'everyone'::text,
  show_activity_status boolean not null default true,
  show_read_receipts boolean not null default true,
  notification_settings jsonb not null default '{"likes": true, "comments": true, "mentions": true, "messages": true, "friend_requests": true, "community_activity": true}'::jsonb,
  search_visibility text not null default 'everyone'::text,
  show_last_seen boolean not null default true,
  deletion_requested_at timestamp with time zone,
  scheduled_purge_at timestamp with time zone,
  suspended_until timestamp with time zone,
  strike_count integer not null default 0,
  safe_search_enabled boolean not null default true,
  child_safety_mode boolean not null default false,
  username_changed_at timestamp with time zone,
  verified_at timestamp with time zone,
  profile_theme text not null default 'default'::text,
  dm_privacy text not null default 'everyone'::text
);
alter table public.allowed_beta_emails add constraint allowed_beta_emails_email_address_key UNIQUE (email_address);
alter table public.allowed_beta_emails add constraint allowed_beta_emails_pkey PRIMARY KEY (id);
alter table public.app_config add constraint app_config_pkey PRIMARY KEY (key);
alter table public.bookmarks add constraint bookmarks_pkey PRIMARY KEY (user_id, post_id);
alter table public.close_friends add constraint close_friends_check CHECK ((user_id <> friend_id));
alter table public.close_friends add constraint close_friends_pkey PRIMARY KEY (user_id, friend_id);
alter table public.communities add constraint communities_language_check CHECK ((language = ANY (ARRAY['en'::text, 'ne'::text])));
alter table public.communities add constraint communities_latitude_chk CHECK (((latitude IS NULL) OR ((latitude >= ('-90'::integer)::double precision) AND (latitude <= (90)::double precision))));
alter table public.communities add constraint communities_longitude_chk CHECK (((longitude IS NULL) OR ((longitude >= ('-180'::integer)::double precision) AND (longitude <= (180)::double precision))));
alter table public.communities add constraint communities_min_age_check CHECK (((min_age IS NULL) OR ((min_age >= 13) AND (min_age <= 21))));
alter table public.communities add constraint communities_name_key UNIQUE (name);
alter table public.communities add constraint communities_pkey PRIMARY KEY (id);
alter table public.communities add constraint communities_posting_permission_check CHECK ((posting_permission = ANY (ARRAY['all_members'::text, 'trusted_and_above'::text, 'admins_only'::text])));
alter table public.communities add constraint communities_price_cents_check CHECK (((price_cents IS NULL) OR (price_cents >= 0)));
alter table public.communities add constraint communities_visibility_check CHECK ((visibility = ANY (ARRAY['public'::text, 'private'::text, 'secret'::text, 'invite_only'::text])));
alter table public.community_memberships add constraint community_memberships_pkey PRIMARY KEY (user_id, community_id);
alter table public.community_memberships add constraint community_memberships_role_check CHECK ((role = ANY (ARRAY['owner'::text, 'admin'::text, 'moderator'::text, 'trusted_member'::text, 'member'::text])));
alter table public.creator_ad_impressions add constraint creator_ad_impressions_pkey PRIMARY KEY (id);
alter table public.link_previews add constraint link_previews_pkey PRIMARY KEY (url);
alter table public.notifications add constraint notifications_pkey PRIMARY KEY (id);
alter table public.post_comments add constraint post_comments_pkey PRIMARY KEY (id);
alter table public.post_downloads add constraint post_downloads_pkey PRIMARY KEY (id);
alter table public.post_likes add constraint post_likes_pkey PRIMARY KEY (user_id, post_id);
alter table public.post_media add constraint post_media_pkey PRIMARY KEY (id);
alter table public.post_media add constraint post_media_scan_status_check CHECK ((scan_status = ANY (ARRAY['pending'::text, 'clean'::text, 'flagged'::text])));
alter table public.posts add constraint posts_ai_moderation_status_check CHECK ((ai_moderation_status = ANY (ARRAY['not_scanned'::text, 'pending'::text, 'clean'::text, 'flagged'::text])));
alter table public.posts add constraint posts_content_type_check CHECK ((content_type = ANY (ARRAY['text'::text, 'image'::text, 'video'::text, 'audio'::text, 'document'::text, 'poll'::text, 'event'::text, 'repost'::text, 'cross_post'::text, 'announcement'::text])));
alter table public.posts add constraint posts_pkey PRIMARY KEY (id);
alter table public.posts add constraint posts_publish_status_check CHECK ((publish_status = ANY (ARRAY['publishing'::text, 'published'::text])));
alter table public.posts add constraint posts_visibility_check CHECK ((visibility = ANY (ARRAY['public'::text, 'followers'::text, 'friends'::text, 'community'::text, 'private'::text, 'unlisted'::text])));
alter table public.reports add constraint reports_check CHECK ((((target_type = 'user'::report_target_type) AND (target_user_id IS NOT NULL) AND (target_post_id IS NULL)) OR ((target_type = 'post'::report_target_type) AND (target_post_id IS NOT NULL) AND (target_user_id IS NULL))));
alter table public.reports add constraint reports_pkey PRIMARY KEY (id);
alter table public.stories add constraint stories_media_type_check CHECK ((media_type = ANY (ARRAY['image'::text, 'video'::text])));
alter table public.stories add constraint stories_pkey PRIMARY KEY (id);
alter table public.story_audio_tracks add constraint story_audio_tracks_pkey PRIMARY KEY (id);
alter table public.story_views add constraint story_views_pkey PRIMARY KEY (story_id, viewer_id);
alter table public.user_blocks add constraint user_blocks_check CHECK ((blocker_id <> blocked_id));
alter table public.user_blocks add constraint user_blocks_pkey PRIMARY KEY (blocker_id, blocked_id);
alter table public.user_follows add constraint user_follows_check CHECK ((follower_id <> following_id));
alter table public.user_follows add constraint user_follows_pkey PRIMARY KEY (follower_id, following_id);
alter table public.user_payout_preferences add constraint user_payout_preferences_pkey PRIMARY KEY (user_id);
alter table public.user_payout_preferences add constraint user_payout_preferences_provider_check CHECK ((provider = ANY (ARRAY['esewa'::text, 'khalti'::text, 'bank'::text])));
alter table public.user_payout_preferences add constraint user_payout_preferences_status_check CHECK ((status = ANY (ARRAY['pending_review'::text, 'verified'::text, 'rejected'::text])));
alter table public.users add constraint users_account_mode_check CHECK ((account_mode = ANY (ARRAY['personal'::text, 'creator'::text])));
alter table public.users add constraint users_default_post_visibility_check CHECK ((default_post_visibility = ANY (ARRAY['public'::text, 'followers'::text, 'friends'::text, 'community'::text, 'private'::text, 'unlisted'::text])));
alter table public.users add constraint users_dm_privacy_check CHECK ((dm_privacy = ANY (ARRAY['everyone'::text, 'following'::text, 'nobody'::text])));
alter table public.users add constraint users_email_key UNIQUE (email);
alter table public.users add constraint users_friends_list_visibility_check CHECK ((friends_list_visibility = ANY (ARRAY['everyone'::text, 'friends'::text, 'only_me'::text])));
alter table public.users add constraint users_language_preference_check CHECK ((language_preference = ANY (ARRAY['ne'::text, 'en'::text])));
alter table public.users add constraint users_message_privacy_check CHECK ((message_privacy = ANY (ARRAY['everyone'::text, 'friends'::text, 'no_one'::text])));
alter table public.users add constraint users_monetization_status_check CHECK ((monetization_status = ANY (ARRAY['not_started'::text, 'pending_review'::text, 'approved'::text, 'rejected'::text])));
alter table public.users add constraint users_pkey PRIMARY KEY (id);
alter table public.users add constraint users_profile_theme_check CHECK ((profile_theme = ANY (ARRAY['default'::text, 'ocean'::text, 'forest'::text, 'sunset'::text, 'rose'::text, 'midnight'::text])));
alter table public.users add constraint users_search_visibility_check CHECK ((search_visibility = ANY (ARRAY['everyone'::text, 'friends'::text, 'no_one'::text])));
alter table public.users add constraint users_tag_privacy_check CHECK ((tag_privacy = ANY (ARRAY['everyone'::text, 'friends'::text, 'no_one'::text])));
alter table public.users add constraint users_username_key UNIQUE (username);
alter table public.bookmarks add constraint bookmarks_user_id_fkey FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;
alter table public.bookmarks add constraint bookmarks_post_id_fkey FOREIGN KEY (post_id) REFERENCES posts(id) ON DELETE CASCADE;
alter table public.close_friends add constraint close_friends_friend_id_fkey FOREIGN KEY (friend_id) REFERENCES users(id) ON DELETE CASCADE;
alter table public.close_friends add constraint close_friends_user_id_fkey FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;
alter table public.communities add constraint communities_category_id_fkey FOREIGN KEY (category_id) REFERENCES community_categories(id) ON DELETE SET NULL;
alter table public.communities add constraint communities_created_by_fkey FOREIGN KEY (created_by) REFERENCES users(id) ON DELETE RESTRICT;
alter table public.communities add constraint communities_pinned_announcement_post_id_fkey FOREIGN KEY (pinned_announcement_post_id) REFERENCES posts(id) ON DELETE SET NULL;
alter table public.community_memberships add constraint community_memberships_community_id_fkey FOREIGN KEY (community_id) REFERENCES communities(id) ON DELETE CASCADE;
alter table public.community_memberships add constraint community_memberships_user_id_fkey FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;
alter table public.creator_ad_impressions add constraint creator_ad_impressions_creator_id_fkey FOREIGN KEY (creator_id) REFERENCES users(id) ON DELETE CASCADE;
alter table public.creator_ad_impressions add constraint creator_ad_impressions_post_id_fkey FOREIGN KEY (post_id) REFERENCES posts(id) ON DELETE CASCADE;
alter table public.creator_ad_impressions add constraint creator_ad_impressions_viewer_id_fkey FOREIGN KEY (viewer_id) REFERENCES users(id) ON DELETE SET NULL;
alter table public.notifications add constraint notifications_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES users(id) ON DELETE SET NULL;
alter table public.notifications add constraint notifications_post_id_fkey FOREIGN KEY (post_id) REFERENCES posts(id) ON DELETE SET NULL;
alter table public.notifications add constraint notifications_recipient_id_fkey FOREIGN KEY (recipient_id) REFERENCES users(id) ON DELETE CASCADE;
alter table public.post_comments add constraint post_comments_parent_comment_id_fkey FOREIGN KEY (parent_comment_id) REFERENCES post_comments(id) ON DELETE CASCADE;
alter table public.post_comments add constraint post_comments_post_id_fkey FOREIGN KEY (post_id) REFERENCES posts(id) ON DELETE CASCADE;
alter table public.post_comments add constraint post_comments_user_id_fkey FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;
alter table public.post_downloads add constraint post_downloads_post_id_fkey FOREIGN KEY (post_id) REFERENCES posts(id) ON DELETE CASCADE;
alter table public.post_downloads add constraint post_downloads_user_id_fkey FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;
alter table public.post_likes add constraint post_likes_post_id_fkey FOREIGN KEY (post_id) REFERENCES posts(id) ON DELETE CASCADE;
alter table public.post_likes add constraint post_likes_user_id_fkey FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;
alter table public.post_media add constraint post_media_post_id_fkey FOREIGN KEY (post_id) REFERENCES posts(id) ON DELETE CASCADE;
alter table public.posts add constraint posts_author_id_fkey FOREIGN KEY (author_id) REFERENCES users(id) ON DELETE CASCADE;
alter table public.posts add constraint posts_community_id_fkey FOREIGN KEY (community_id) REFERENCES communities(id) ON DELETE SET NULL;
alter table public.posts add constraint posts_reply_to_post_id_fkey FOREIGN KEY (reply_to_post_id) REFERENCES posts(id) ON DELETE SET NULL;
alter table public.reports add constraint reports_reporter_id_fkey FOREIGN KEY (reporter_id) REFERENCES users(id) ON DELETE CASCADE;
alter table public.reports add constraint reports_reviewed_by_fkey FOREIGN KEY (reviewed_by) REFERENCES users(id) ON DELETE SET NULL;
alter table public.reports add constraint reports_target_post_id_fkey FOREIGN KEY (target_post_id) REFERENCES posts(id) ON DELETE CASCADE;
alter table public.reports add constraint reports_target_user_id_fkey FOREIGN KEY (target_user_id) REFERENCES users(id) ON DELETE CASCADE;
alter table public.stories add constraint stories_author_id_fkey FOREIGN KEY (author_id) REFERENCES users(id) ON DELETE CASCADE;
alter table public.stories add constraint stories_audio_track_id_fkey FOREIGN KEY (audio_track_id) REFERENCES story_audio_tracks(id);
alter table public.story_views add constraint story_views_story_id_fkey FOREIGN KEY (story_id) REFERENCES stories(id) ON DELETE CASCADE;
alter table public.story_views add constraint story_views_viewer_id_fkey FOREIGN KEY (viewer_id) REFERENCES users(id) ON DELETE CASCADE;
alter table public.user_blocks add constraint user_blocks_blocked_id_fkey FOREIGN KEY (blocked_id) REFERENCES users(id) ON DELETE CASCADE;
alter table public.user_blocks add constraint user_blocks_blocker_id_fkey FOREIGN KEY (blocker_id) REFERENCES users(id) ON DELETE CASCADE;
alter table public.user_follows add constraint user_follows_follower_id_fkey FOREIGN KEY (follower_id) REFERENCES users(id) ON DELETE CASCADE;
alter table public.user_follows add constraint user_follows_following_id_fkey FOREIGN KEY (following_id) REFERENCES users(id) ON DELETE CASCADE;
alter table public.user_payout_preferences add constraint user_payout_preferences_user_id_fkey FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;
alter table public.users add constraint users_pinned_post_id_fkey FOREIGN KEY (pinned_post_id) REFERENCES posts(id) ON DELETE SET NULL;
alter table public.users add constraint users_id_fkey FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE;
CREATE INDEX idx_bookmarks_post_user ON public.bookmarks USING btree (post_id, user_id);
CREATE INDEX idx_communities_description_trgm ON public.communities USING gin (description gin_trgm_ops);
CREATE INDEX idx_communities_category_id ON public.communities USING btree (category_id);
CREATE INDEX idx_communities_geo ON public.communities USING btree (latitude, longitude) WHERE ((latitude IS NOT NULL) AND (longitude IS NOT NULL));
CREATE INDEX idx_communities_name_trgm ON public.communities USING gin (name gin_trgm_ops);
CREATE INDEX idx_communities_last_activity ON public.communities USING btree (last_activity_at DESC);
CREATE INDEX idx_community_memberships_community_created ON public.community_memberships USING btree (community_id, created_at);
CREATE INDEX idx_memberships_community_user ON public.community_memberships USING btree (community_id, user_id);
CREATE INDEX creator_ad_impressions_creator_idx ON public.creator_ad_impressions USING btree (creator_id, created_at DESC);
CREATE INDEX creator_ad_impressions_post_idx ON public.creator_ad_impressions USING btree (post_id);
CREATE INDEX idx_notifications_recipient_read ON public.notifications USING btree (recipient_id, is_read, created_at DESC);
CREATE INDEX idx_post_comments_created_at ON public.post_comments USING btree (created_at);
CREATE INDEX idx_post_comments_parent_comment_id ON public.post_comments USING btree (parent_comment_id);
CREATE INDEX idx_comments_post_created ON public.post_comments USING btree (post_id, created_at DESC);
CREATE INDEX idx_post_downloads_post ON public.post_downloads USING btree (post_id);
CREATE INDEX idx_post_likes_post_created ON public.post_likes USING btree (post_id, created_at);
CREATE INDEX idx_post_likes_created_at ON public.post_likes USING btree (created_at);
CREATE INDEX idx_likes_post_user ON public.post_likes USING btree (post_id, user_id);
CREATE INDEX idx_post_media_post_created ON public.post_media USING btree (post_id, created_at);
CREATE INDEX idx_posts_scheduled_for ON public.posts USING btree (scheduled_for) WHERE (scheduled_for IS NOT NULL);
CREATE INDEX idx_posts_content_type ON public.posts USING btree (content_type);
CREATE INDEX idx_posts_tags ON public.posts USING gin (tags);
CREATE INDEX idx_posts_publish_status ON public.posts USING btree (publish_status) WHERE (publish_status = 'publishing'::text);
CREATE INDEX idx_posts_pinned_created_id ON public.posts USING btree (is_pinned DESC, created_at DESC, id DESC);
CREATE INDEX idx_posts_author_created ON public.posts USING btree (author_id, created_at DESC);
CREATE INDEX idx_posts_pinned ON public.posts USING btree (is_pinned) WHERE (is_pinned = true);
CREATE INDEX idx_posts_archived ON public.posts USING btree (archived_at) WHERE (archived_at IS NOT NULL);
CREATE INDEX idx_posts_created_at ON public.posts USING btree (created_at DESC);
CREATE INDEX idx_posts_text_content_trgm ON public.posts USING gin (text_content gin_trgm_ops);
CREATE INDEX idx_posts_community_created ON public.posts USING btree (community_id, created_at DESC);
CREATE INDEX idx_posts_reply_to_post_id ON public.posts USING btree (reply_to_post_id) WHERE (reply_to_post_id IS NOT NULL);
CREATE UNIQUE INDEX uq_reports_open_reporter_user ON public.reports USING btree (reporter_id, target_user_id) WHERE ((status = 'open'::report_status) AND (target_type = 'user'::report_target_type) AND (NOT is_automated));
CREATE INDEX idx_reports_created_at ON public.reports USING btree (created_at);
CREATE UNIQUE INDEX uq_reports_open_reporter_post ON public.reports USING btree (reporter_id, target_post_id) WHERE ((status = 'open'::report_status) AND (target_type = 'post'::report_target_type) AND (NOT is_automated));
CREATE INDEX idx_stories_expires ON public.stories USING btree (expires_at);
CREATE INDEX idx_stories_author ON public.stories USING btree (author_id);
CREATE INDEX idx_users_created_at ON public.users USING btree (created_at);
CREATE INDEX idx_users_username_trgm ON public.users USING gin (username gin_trgm_ops);
CREATE INDEX idx_users_fcm_token_present ON public.users USING btree (fcm_token_updated_at DESC) WHERE (fcm_token IS NOT NULL);
CREATE UNIQUE INDEX users_phone_number_key ON public.users USING btree (phone_number);
alter table public.allowed_beta_emails enable row level security;
alter table public.app_config enable row level security;
alter table public.bookmarks enable row level security;
alter table public.close_friends enable row level security;
alter table public.communities enable row level security;
alter table public.community_memberships enable row level security;
alter table public.creator_ad_impressions enable row level security;
alter table public.link_previews enable row level security;
alter table public.notifications enable row level security;
alter table public.post_comments enable row level security;
alter table public.post_downloads enable row level security;
alter table public.post_likes enable row level security;
alter table public.post_media enable row level security;
alter table public.posts enable row level security;
alter table public.reports enable row level security;
alter table public.stories enable row level security;
alter table public.story_audio_tracks enable row level security;
alter table public.story_views enable row level security;
alter table public.user_blocks enable row level security;
alter table public.user_follows enable row level security;
alter table public.user_payout_preferences enable row level security;
alter table public.users enable row level security;
create policy app_config_select_all on public.app_config as PERMISSIVE for SELECT to public
  using (true);
create policy app_config_write_admin on public.app_config as PERMISSIVE for ALL to public
  using (is_admin_or_mod())
  with check (is_admin_or_mod());
create policy bookmarks_delete_self_beta on public.bookmarks as PERMISSIVE for DELETE to public
  using ((is_admin_or_mod() OR ((user_id = auth.uid()) AND current_user_has_beta_access())));
create policy bookmarks_insert_self_allowed_beta on public.bookmarks as PERMISSIVE for INSERT to public
  with check (((user_id = auth.uid()) AND current_user_is_active() AND current_user_has_beta_access() AND (EXISTS ( SELECT 1
   FROM posts p
  WHERE ((p.id = bookmarks.post_id) AND (p.is_removed = false) AND (NOT users_are_blocked(auth.uid(), p.author_id)))))));
create policy bookmarks_select_self_beta on public.bookmarks as PERMISSIVE for SELECT to public
  using (((user_id = auth.uid()) AND current_user_has_beta_access()));
create policy close_friends_owner_only on public.close_friends as PERMISSIVE for ALL to public
  using ((user_id = auth.uid()))
  with check ((user_id = auth.uid()));
create policy communities_delete_owner_or_admin on public.communities as PERMISSIVE for DELETE to public
  using (((created_by = auth.uid()) OR is_admin_or_mod()));
create policy communities_insert_beta on public.communities as PERMISSIVE for INSERT to public
  with check (((auth.uid() = created_by) AND current_user_has_beta_access()));
create policy communities_select_beta on public.communities as PERMISSIVE for SELECT to public
  using ((current_user_has_beta_access() AND ((visibility <> 'secret'::text) OR is_admin_or_mod() OR (EXISTS ( SELECT 1
   FROM community_memberships m
  WHERE ((m.community_id = communities.id) AND (m.user_id = auth.uid())))) OR (EXISTS ( SELECT 1
   FROM community_invites i
  WHERE ((i.community_id = communities.id) AND (i.invited_user_id = auth.uid()) AND (i.revoked_at IS NULL)))))));
create policy communities_update_owner_or_admin on public.communities as PERMISSIVE for UPDATE to public
  using (((created_by = auth.uid()) OR is_admin_or_mod() OR current_user_community_permission(id, 'manage_settings'::text)))
  with check (((created_by = auth.uid()) OR is_admin_or_mod() OR current_user_community_permission(id, 'manage_settings'::text)));
create policy memberships_delete_self_beta on public.community_memberships as PERMISSIVE for DELETE to public
  using ((is_admin_or_mod() OR ((user_id = auth.uid()) AND current_user_has_beta_access())));
create policy memberships_insert_beta on public.community_memberships as PERMISSIVE for INSERT to public
  with check (((user_id = auth.uid()) AND current_user_has_beta_access() AND (NOT is_banned_from_community(community_id, auth.uid()))));
create policy memberships_select_members on public.community_memberships as PERMISSIVE for SELECT to public
  using ((current_user_has_beta_access() AND ((user_id = auth.uid()) OR is_admin_or_mod() OR is_member_of_community(community_id))));
create policy creator_ad_impressions_select on public.creator_ad_impressions as PERMISSIVE for SELECT to public
  using (((creator_id = auth.uid()) OR is_admin_or_mod()));
create policy link_previews_select on public.link_previews as PERMISSIVE for SELECT to public
  using (true);
create policy notifications_select_self_beta on public.notifications as PERMISSIVE for SELECT to public
  using (((recipient_id = auth.uid()) AND current_user_has_beta_access()));
create policy notifications_update_self_beta on public.notifications as PERMISSIVE for UPDATE to public
  using (((recipient_id = auth.uid()) AND current_user_has_beta_access()))
  with check (((recipient_id = auth.uid()) AND current_user_has_beta_access()));
create policy comments_delete_self_beta on public.post_comments as PERMISSIVE for DELETE to public
  using ((is_admin_or_mod() OR ((user_id = auth.uid()) AND current_user_has_beta_access())));
create policy comments_insert_self_allowed_beta on public.post_comments as PERMISSIVE for INSERT to public
  with check (((user_id = auth.uid()) AND current_user_is_active() AND current_user_has_beta_access() AND (EXISTS ( SELECT 1
   FROM posts p
  WHERE ((p.id = post_comments.post_id) AND (p.is_removed = false) AND (NOT users_are_blocked(auth.uid(), p.author_id)))))));
create policy comments_select_visible_v2 on public.post_comments as PERMISSIVE for SELECT to public
  using ((current_user_has_beta_access() AND ((user_id = auth.uid()) OR (EXISTS ( SELECT 1
   FROM posts p
  WHERE ((p.id = post_comments.post_id) AND (p.is_removed = false) AND (NOT users_are_blocked(auth.uid(), p.author_id)) AND (NOT users_are_blocked(auth.uid(), post_comments.user_id)) AND ((p.author_id = auth.uid()) OR ((NOT post_comments.is_hidden) AND (NOT is_user_restricted(p.author_id, post_comments.user_id))))))))));
create policy comments_update_self_beta on public.post_comments as PERMISSIVE for UPDATE to public
  using ((is_admin_or_mod() OR ((user_id = auth.uid()) AND current_user_has_beta_access())))
  with check ((is_admin_or_mod() OR ((user_id = auth.uid()) AND current_user_has_beta_access())));
create policy post_downloads_insert on public.post_downloads as PERMISSIVE for INSERT to public
  with check ((auth.uid() = user_id));
create policy post_downloads_select on public.post_downloads as PERMISSIVE for SELECT to public
  using (true);
create policy likes_delete_self_beta on public.post_likes as PERMISSIVE for DELETE to public
  using ((is_admin_or_mod() OR ((user_id = auth.uid()) AND current_user_has_beta_access())));
create policy likes_insert_self_allowed_beta on public.post_likes as PERMISSIVE for INSERT to public
  with check (((user_id = auth.uid()) AND current_user_is_active() AND current_user_has_beta_access() AND (EXISTS ( SELECT 1
   FROM posts p
  WHERE ((p.id = post_likes.post_id) AND (p.is_removed = false) AND (NOT users_are_blocked(auth.uid(), p.author_id)))))));
create policy likes_select_visible_beta on public.post_likes as PERMISSIVE for SELECT to public
  using ((current_user_has_beta_access() AND ((user_id = auth.uid()) OR (EXISTS ( SELECT 1
   FROM posts p
  WHERE ((p.id = post_likes.post_id) AND (p.is_removed = false) AND ((p.author_id = auth.uid()) OR (NOT users_are_blocked(auth.uid(), p.author_id)))))))));
create policy media_delete_owner_or_admin on public.post_media as PERMISSIVE for DELETE to public
  using ((is_admin_or_mod() OR (EXISTS ( SELECT 1
   FROM posts p
  WHERE ((p.id = post_media.post_id) AND (p.author_id = auth.uid()))))));
create policy media_insert_post_owner on public.post_media as PERMISSIVE for INSERT to public
  with check ((EXISTS ( SELECT 1
   FROM posts p
  WHERE ((p.id = post_media.post_id) AND (p.author_id = auth.uid())))));
create policy media_select_admin_all on public.post_media as PERMISSIVE for SELECT to public
  using (is_admin_or_mod());
create policy media_select_visible_beta on public.post_media as PERMISSIVE for SELECT to public
  using ((current_user_has_beta_access() AND (EXISTS ( SELECT 1
   FROM posts p
  WHERE ((p.id = post_media.post_id) AND (p.is_removed = false) AND ((p.author_id = auth.uid()) OR (NOT users_are_blocked(auth.uid(), p.author_id))))))));
create policy posts_delete_owner_or_admin_beta on public.posts as PERMISSIVE for DELETE to public
  using ((is_admin_or_mod() OR ((author_id = auth.uid()) AND current_user_has_beta_access())));
create policy posts_insert_self_active_beta on public.posts as PERMISSIVE for INSERT to public
  with check (((author_id = auth.uid()) AND current_user_is_active() AND current_user_has_beta_access() AND ((community_id IS NULL) OR current_user_community_permission(community_id, 'post_content'::text))));
create policy posts_select_admin_all on public.posts as PERMISSIVE for SELECT to public
  using (is_admin_or_mod());
create policy posts_select_visible_beta on public.posts as PERMISSIVE for SELECT to public
  using ((current_user_has_beta_access() AND (is_removed = false) AND ((author_id = auth.uid()) OR (publish_status = 'published'::text)) AND ((author_id = auth.uid()) OR (NOT users_are_blocked(auth.uid(), author_id))) AND ((author_id = auth.uid()) OR ((visibility = ANY (ARRAY['public'::text, 'unlisted'::text])) AND can_view_author_posts(auth.uid(), author_id)) OR ((visibility = 'followers'::text) AND (EXISTS ( SELECT 1
   FROM user_follows uf
  WHERE ((uf.follower_id = auth.uid()) AND (uf.following_id = posts.author_id))))) OR ((visibility = 'friends'::text) AND (EXISTS ( SELECT 1
   FROM close_friends cf
  WHERE ((cf.user_id = posts.author_id) AND (cf.friend_id = auth.uid()))))) OR ((visibility = 'community'::text) AND post_id_visible_via_community(community_id, auth.uid())))));
create policy posts_update_owner_or_admin_beta on public.posts as PERMISSIVE for UPDATE to public
  using ((is_admin_or_mod() OR ((author_id = auth.uid()) AND (is_removed = false) AND current_user_has_beta_access())))
  with check ((is_admin_or_mod() OR ((author_id = auth.uid()) AND (is_removed = false) AND current_user_has_beta_access())));
create policy reports_insert_self_active_beta on public.reports as PERMISSIVE for INSERT to public
  with check (((reporter_id = auth.uid()) AND current_user_is_active() AND current_user_has_beta_access()));
create policy reports_select_self_or_admin on public.reports as PERMISSIVE for SELECT to public
  using (((reporter_id = auth.uid()) OR is_admin_or_mod() OR ((target_post_id IS NOT NULL) AND (EXISTS ( SELECT 1
   FROM posts p
  WHERE ((p.id = reports.target_post_id) AND (p.community_id IS NOT NULL) AND current_user_community_permission(p.community_id, 'manage_reports'::text)))))));
create policy reports_update_admin on public.reports as PERMISSIVE for UPDATE to public
  using (is_admin_or_mod())
  with check (is_admin_or_mod());
create policy stories_delete on public.stories as PERMISSIVE for DELETE to public
  using ((auth.uid() = author_id));
create policy stories_insert on public.stories as PERMISSIVE for INSERT to public
  with check ((auth.uid() = author_id));
create policy stories_select on public.stories as PERMISSIVE for SELECT to public
  using (((expires_at > now()) AND (NOT (EXISTS ( SELECT 1
   FROM user_blocks ub
  WHERE (((ub.blocker_id = auth.uid()) AND (ub.blocked_id = stories.author_id)) OR ((ub.blocker_id = stories.author_id) AND (ub.blocked_id = auth.uid()))))))));
create policy stories_update on public.stories as PERMISSIVE for UPDATE to public
  using ((auth.uid() = author_id))
  with check ((auth.uid() = author_id));
create policy story_audio_tracks_select on public.story_audio_tracks as PERMISSIVE for SELECT to public
  using ((is_active = true));
create policy story_views_insert on public.story_views as PERMISSIVE for INSERT to public
  with check ((auth.uid() = viewer_id));
create policy story_views_select on public.story_views as PERMISSIVE for SELECT to public
  using (true);
create policy blocks_delete_self on public.user_blocks as PERMISSIVE for DELETE to public
  using (((blocker_id = auth.uid()) OR is_admin_or_mod()));
create policy blocks_insert_self on public.user_blocks as PERMISSIVE for INSERT to public
  with check ((blocker_id = auth.uid()));
create policy blocks_select_self on public.user_blocks as PERMISSIVE for SELECT to public
  using ((blocker_id = auth.uid()));
create policy follows_delete_self_beta on public.user_follows as PERMISSIVE for DELETE to public
  using ((is_admin_or_mod() OR ((follower_id = auth.uid()) AND current_user_has_beta_access())));
create policy follows_insert_self_allowed_beta on public.user_follows as PERMISSIVE for INSERT to public
  with check (((follower_id = auth.uid()) AND current_user_is_active() AND current_user_has_beta_access() AND (NOT users_are_blocked(follower_id, following_id))));
create policy follows_select_beta on public.user_follows as PERMISSIVE for SELECT to public
  using (current_user_has_beta_access());
create policy payout_prefs_delete on public.user_payout_preferences as PERMISSIVE for DELETE to public
  using (((user_id = auth.uid()) OR is_admin_or_mod()));
create policy payout_prefs_insert on public.user_payout_preferences as PERMISSIVE for INSERT to public
  with check (((user_id = auth.uid()) OR is_admin_or_mod()));
create policy payout_prefs_select on public.user_payout_preferences as PERMISSIVE for SELECT to public
  using (((user_id = auth.uid()) OR is_admin_or_mod()));
create policy payout_prefs_update on public.user_payout_preferences as PERMISSIVE for UPDATE to public
  using (((user_id = auth.uid()) OR is_admin_or_mod()))
  with check (((user_id = auth.uid()) OR is_admin_or_mod()));
create policy users_admin_update on public.users as PERMISSIVE for UPDATE to public
  using (is_admin_or_mod())
  with check (is_admin_or_mod());
create policy users_insert_auth on public.users as PERMISSIVE for INSERT to authenticated
  with check ((id = auth.uid()));
create policy users_insert_self_beta on public.users as PERMISSIVE for INSERT to public
  with check (((id = auth.uid()) AND beta_email_allowed(email)));
create policy users_select_beta on public.users as PERMISSIVE for SELECT to public
  using (((id = auth.uid()) OR current_user_has_beta_access()));
create policy users_update_self_beta on public.users as PERMISSIVE for UPDATE to public
  using (((id = auth.uid()) AND current_user_has_beta_access()))
  with check (((id = auth.uid()) AND current_user_has_beta_access()));
CREATE TRIGGER trg_guard_beta_bookmark_create BEFORE INSERT ON public.bookmarks FOR EACH ROW EXECUTE FUNCTION guard_beta_access();
CREATE TRIGGER trg_guard_bookmark_create BEFORE INSERT ON public.bookmarks FOR EACH ROW EXECUTE FUNCTION guard_post_interaction();
CREATE TRIGGER trg_communities_touch BEFORE UPDATE ON public.communities FOR EACH ROW EXECUTE FUNCTION touch_updated_at();
CREATE TRIGGER trg_community_created_owner AFTER INSERT ON public.communities FOR EACH ROW EXECUTE FUNCTION trg_community_created_owner();
CREATE TRIGGER trg_notify_community_announcement_pinned AFTER UPDATE ON public.communities FOR EACH ROW EXECUTE FUNCTION notify_on_community_announcement_pinned();
CREATE TRIGGER trg_sync_community_category_id BEFORE INSERT OR UPDATE ON public.communities FOR EACH ROW EXECUTE FUNCTION sync_community_category_id();
CREATE TRIGGER trg_community_membership_count AFTER INSERT OR DELETE ON public.community_memberships FOR EACH ROW EXECUTE FUNCTION trg_community_membership_count();
CREATE TRIGGER trg_membership_joined AFTER INSERT ON public.community_memberships FOR EACH ROW EXECUTE FUNCTION log_membership_joined();
CREATE TRIGGER trg_membership_left AFTER DELETE ON public.community_memberships FOR EACH ROW EXECUTE FUNCTION log_membership_left();
CREATE TRIGGER trg_notify_community_role_changed AFTER UPDATE ON public.community_memberships FOR EACH ROW EXECUTE FUNCTION notify_on_community_role_changed();
-- NOTE: Database Webhook trigger "notification-dispatch" on public.notifications omitted (its definition embeds secrets).
-- Recreate it in Dashboard > Database > Webhooks: INSERT on public.notifications -> Edge Function notification-dispatch,
-- with an x-webhook-secret header matching the function's configured shared secret.
CREATE TRIGGER trg_auto_moderate_comment_block BEFORE INSERT ON public.post_comments FOR EACH ROW EXECUTE FUNCTION auto_moderate_comment_block();
CREATE TRIGGER trg_auto_moderate_comment_flag AFTER INSERT ON public.post_comments FOR EACH ROW EXECUTE FUNCTION auto_moderate_comment_flag();
CREATE TRIGGER trg_comment_notify AFTER INSERT ON public.post_comments FOR EACH ROW EXECUTE FUNCTION create_notification_on_comment();
CREATE TRIGGER trg_comment_reply_count AFTER INSERT OR DELETE ON public.post_comments FOR EACH ROW EXECUTE FUNCTION maintain_comment_reply_count();
CREATE TRIGGER trg_comments_touch BEFORE UPDATE ON public.post_comments FOR EACH ROW EXECUTE FUNCTION touch_updated_at();
CREATE TRIGGER trg_guard_beta_comment_create BEFORE INSERT ON public.post_comments FOR EACH ROW EXECUTE FUNCTION guard_beta_access();
CREATE TRIGGER trg_guard_comment_create BEFORE INSERT ON public.post_comments FOR EACH ROW EXECUTE FUNCTION guard_comment_create();
CREATE TRIGGER trg_sync_download_count AFTER INSERT OR DELETE ON public.post_downloads FOR EACH ROW EXECUTE FUNCTION sync_download_count();
CREATE TRIGGER trg_guard_beta_like_create BEFORE INSERT ON public.post_likes FOR EACH ROW EXECUTE FUNCTION guard_beta_access();
CREATE TRIGGER trg_guard_like_create BEFORE INSERT ON public.post_likes FOR EACH ROW EXECUTE FUNCTION guard_post_interaction();
CREATE TRIGGER trg_like_notify AFTER INSERT ON public.post_likes FOR EACH ROW EXECUTE FUNCTION create_notification_on_like();
CREATE TRIGGER trg_queue_media_moderation AFTER INSERT ON public.post_media FOR EACH ROW EXECUTE FUNCTION queue_media_moderation();
CREATE TRIGGER trg_auto_moderate_post_block BEFORE INSERT ON public.posts FOR EACH ROW EXECUTE FUNCTION auto_moderate_post_block();
CREATE TRIGGER trg_auto_moderate_post_flag AFTER INSERT ON public.posts FOR EACH ROW EXECUTE FUNCTION auto_moderate_post_flag();
CREATE TRIGGER trg_community_post_notify AFTER INSERT ON public.posts FOR EACH ROW EXECUTE FUNCTION create_notification_on_community_post();
CREATE TRIGGER trg_guard_beta_post_create BEFORE INSERT ON public.posts FOR EACH ROW EXECUTE FUNCTION guard_beta_access();
CREATE TRIGGER trg_guard_duplicate_post_content BEFORE INSERT ON public.posts FOR EACH ROW EXECUTE FUNCTION guard_duplicate_post_content();
CREATE TRIGGER trg_guard_post_create BEFORE INSERT ON public.posts FOR EACH ROW EXECUTE FUNCTION guard_post_create();
CREATE TRIGGER trg_notify_on_mention AFTER INSERT ON public.posts FOR EACH ROW EXECUTE FUNCTION create_notifications_on_mention();
CREATE TRIGGER trg_notify_on_post_reply_or_repost AFTER INSERT ON public.posts FOR EACH ROW EXECUTE FUNCTION create_notification_on_post_reply_or_repost();
CREATE TRIGGER trg_post_reply_mention_notify AFTER INSERT ON public.posts FOR EACH ROW EXECUTE FUNCTION create_notification_on_post_reply_or_mention();
CREATE TRIGGER trg_posts_touch BEFORE UPDATE ON public.posts FOR EACH ROW EXECUTE FUNCTION touch_updated_at();
CREATE TRIGGER trg_posts_touch_community_activity AFTER INSERT ON public.posts FOR EACH ROW WHEN ((new.community_id IS NOT NULL)) EXECUTE FUNCTION touch_community_activity();
CREATE TRIGGER trg_sync_reply_count_on_removal AFTER UPDATE OF is_removed ON public.posts FOR EACH ROW EXECUTE FUNCTION sync_reply_count_on_removal();
CREATE TRIGGER trg_guard_report_create BEFORE INSERT ON public.reports FOR EACH ROW EXECUTE FUNCTION guard_report_create();
CREATE TRIGGER trg_notify_on_report_status_change AFTER UPDATE ON public.reports FOR EACH ROW EXECUTE FUNCTION notify_on_report_status_change();
CREATE TRIGGER trg_reports_touch BEFORE UPDATE ON public.reports FOR EACH ROW EXECUTE FUNCTION touch_updated_at();
CREATE TRIGGER trg_follow_notify AFTER INSERT ON public.user_follows FOR EACH ROW EXECUTE FUNCTION create_notification_on_follow();
CREATE TRIGGER trg_guard_follow_create BEFORE INSERT ON public.user_follows FOR EACH ROW EXECUTE FUNCTION guard_follow_create();
CREATE TRIGGER trg_guard_payout_preference_write BEFORE INSERT OR UPDATE ON public.user_payout_preferences FOR EACH ROW EXECUTE FUNCTION guard_payout_preference_write();
CREATE TRIGGER trg_reset_payout_status BEFORE UPDATE ON public.user_payout_preferences FOR EACH ROW EXECUTE FUNCTION reset_payout_status_on_self_edit();
CREATE TRIGGER trg_enforce_child_safety_mode BEFORE UPDATE OF child_safety_mode, safe_search_enabled, message_privacy ON public.users FOR EACH ROW EXECUTE FUNCTION enforce_child_safety_mode();
CREATE TRIGGER trg_guard_profile_identity_columns BEFORE UPDATE ON public.users FOR EACH ROW EXECUTE FUNCTION guard_profile_identity_columns();
CREATE TRIGGER trg_guard_user_update BEFORE UPDATE ON public.users FOR EACH ROW EXECUTE FUNCTION guard_user_update();
CREATE TRIGGER trg_users_touch BEFORE UPDATE ON public.users FOR EACH ROW EXECUTE FUNCTION touch_updated_at();
grant DELETE, INSERT, SELECT, UPDATE on public.allowed_beta_emails to service_role;
grant SELECT on public.app_config to anon;
grant DELETE, INSERT, SELECT, UPDATE on public.app_config to authenticated;
grant DELETE, INSERT, SELECT, UPDATE on public.app_config to service_role;
grant SELECT on public.bookmarks to anon;
grant DELETE, INSERT, SELECT, UPDATE on public.bookmarks to authenticated;
grant DELETE, INSERT, SELECT, UPDATE on public.bookmarks to service_role;
grant DELETE, INSERT, SELECT, UPDATE on public.close_friends to authenticated;
grant DELETE, INSERT, SELECT, UPDATE on public.close_friends to service_role;
grant SELECT on public.communities to anon;
grant DELETE, INSERT, SELECT, UPDATE on public.communities to authenticated;
grant DELETE, INSERT, SELECT, UPDATE on public.communities to service_role;
grant SELECT on public.community_memberships to anon;
grant DELETE, INSERT, SELECT, UPDATE on public.community_memberships to authenticated;
grant DELETE, INSERT, SELECT, UPDATE on public.community_memberships to service_role;
grant DELETE, INSERT, SELECT, UPDATE on public.creator_ad_impressions to service_role;
grant SELECT on public.link_previews to anon;
grant SELECT on public.link_previews to authenticated;
grant DELETE, INSERT, SELECT, UPDATE on public.link_previews to service_role;
grant SELECT on public.notifications to anon;
grant DELETE, INSERT, SELECT, UPDATE on public.notifications to authenticated;
grant DELETE, INSERT, SELECT, UPDATE on public.notifications to service_role;
grant SELECT on public.post_comments to anon;
grant DELETE, INSERT, SELECT, UPDATE on public.post_comments to authenticated;
grant DELETE, INSERT, SELECT, UPDATE on public.post_comments to service_role;
grant SELECT on public.post_downloads to anon;
grant INSERT, SELECT on public.post_downloads to authenticated;
grant DELETE, INSERT, SELECT, UPDATE on public.post_downloads to service_role;
grant SELECT on public.post_likes to anon;
grant DELETE, INSERT, SELECT, UPDATE on public.post_likes to authenticated;
grant DELETE, INSERT, SELECT, UPDATE on public.post_likes to service_role;
grant SELECT on public.post_media to anon;
grant DELETE, INSERT, SELECT, UPDATE on public.post_media to authenticated;
grant DELETE, INSERT, SELECT, UPDATE on public.post_media to service_role;
grant SELECT on public.posts to anon;
grant DELETE, INSERT, SELECT, UPDATE on public.posts to authenticated;
grant DELETE, INSERT, SELECT, UPDATE on public.posts to service_role;
grant SELECT on public.reports to anon;
grant DELETE, INSERT, SELECT, UPDATE on public.reports to authenticated;
grant DELETE, INSERT, SELECT, UPDATE on public.reports to service_role;
grant SELECT on public.stories to anon;
grant DELETE, INSERT, SELECT, UPDATE on public.stories to authenticated;
grant DELETE, INSERT, SELECT, UPDATE on public.stories to service_role;
grant SELECT on public.story_audio_tracks to anon;
grant SELECT on public.story_audio_tracks to authenticated;
grant DELETE, INSERT, SELECT, UPDATE on public.story_audio_tracks to service_role;
grant SELECT on public.story_views to anon;
grant INSERT, SELECT on public.story_views to authenticated;
grant DELETE, INSERT, SELECT, UPDATE on public.story_views to service_role;
grant SELECT on public.user_blocks to anon;
grant DELETE, INSERT, SELECT, UPDATE on public.user_blocks to authenticated;
grant DELETE, INSERT, SELECT, UPDATE on public.user_blocks to service_role;
grant SELECT on public.user_follows to anon;
grant DELETE, INSERT, SELECT, UPDATE on public.user_follows to authenticated;
grant DELETE, INSERT, SELECT, UPDATE on public.user_follows to service_role;
grant DELETE, INSERT, SELECT, UPDATE on public.user_payout_preferences to authenticated;
grant DELETE, INSERT, SELECT, UPDATE on public.user_payout_preferences to service_role;
grant SELECT on public.users to anon;
grant DELETE, INSERT, SELECT, UPDATE on public.users to authenticated;
grant DELETE, INSERT, SELECT, UPDATE on public.users to service_role;
