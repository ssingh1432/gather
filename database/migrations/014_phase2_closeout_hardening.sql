-- Two follow-up hardening fixes applied live via Supabase MCP as part of
-- closing out Phase 2. Kept as one migration file since both are small,
-- purely additive changes with no app-behavior impact.

-- 1) Four public buckets (avatars, post-media, story-audio, story-media)
--    had a broad SELECT policy that let anyone enumerate every file via
--    the Storage list()/authenticated-read API. Public URL fetch
--    (storage.getPublicUrl(), used everywhere in the app) doesn't need
--    this — public buckets serve objects via a separate endpoint that
--    bypasses RLS entirely. Dropping these only closes the enumeration
--    path; nothing the app does depends on them.
drop policy if exists "Public read access for avatars" on storage.objects;
drop policy if exists "Public read access for post-media" on storage.objects;
drop policy if exists "story_audio_public_read" on storage.objects;
drop policy if exists "story_media_public_read" on storage.objects;

-- 2) Pin search_path on 4 pre-existing functions that had a mutable one
--    (flagged by Supabase's own security linter). ALTER FUNCTION only
--    sets a config parameter — does not touch function bodies/behavior.
alter function public.is_admin_or_mod() set search_path = public;
alter function public.touch_updated_at() set search_path = public;
alter function public.current_user_has_beta_access() set search_path = public;
alter function public.beta_email_allowed(text) set search_path = public;
