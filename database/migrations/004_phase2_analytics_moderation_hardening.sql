-- Phase 2: add suspended user status for admin moderation.
-- Kept separate so PostgreSQL can commit the enum value before later migrations use it.

alter type public.user_status add value if not exists 'suspended';
