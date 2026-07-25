-- Migration 040: close a real privilege-escalation hole on cron-only functions.
--
-- Purpose: 019_scheduled_account_deletion_purge.sql (and the equivalent grants
-- for the other pg_cron-only jobs) revoked EXECUTE from `anon` and
-- `authenticated` specifically, but never revoked it from `PUBLIC`. In
-- Postgres, every function grants EXECUTE to PUBLIC by default at creation
-- time, and revoking a privilege from a named role does NOT remove a
-- separate PUBLIC grant — PUBLIC privileges apply to every role regardless
-- of what's revoked from them individually. Because `anon` and
-- `authenticated` are themselves ordinary roles, they still inherit the
-- PUBLIC grant. Net effect, confirmed live on the project: any client using
-- the anon or authenticated Supabase key can currently call
--   supabase.rpc('purge_expired_account_deletions')
--   supabase.rpc('publish_scheduled_posts')
--   supabase.rpc('send_event_reminders')
--   supabase.rpc('run_backup_heartbeat')
--   supabase.rpc('lift_expired_suspensions')
-- directly and it will execute as SECURITY DEFINER (postgres), with no
-- ownership/rate-limit/idempotency guard against being called on-demand
-- instead of on the pg_cron schedule. None of these are called by the
-- Flutter client today, so this fix is purely a hardening change — it does
-- not remove anything the app depends on.
--
-- Fix: explicitly revoke EXECUTE from PUBLIC (in addition to anon/
-- authenticated, kept for clarity/defense-in-depth) on every pg_cron-only
-- function. Going forward, any new cron-only function must include
-- `revoke all on function ... from public, anon, authenticated;` — revoking
-- from PUBLIC is the one that actually matters.
--
-- Rollback: `grant execute on function <name>() to public;` per function
-- below, though there's no legitimate reason to do so.

revoke all on function public.publish_scheduled_posts() from public, anon, authenticated;
revoke all on function public.send_event_reminders() from public, anon, authenticated;
revoke all on function public.purge_expired_account_deletions() from public, anon, authenticated;
revoke all on function public.run_backup_heartbeat() from public, anon, authenticated;
revoke all on function public.lift_expired_suspensions() from public, anon, authenticated;

-- Defense-in-depth audit: any OTHER security-definer function in public
-- that still carries a bare PUBLIC grant and is NOT a trigger function
-- (trigger functions can't be invoked directly via RPC even with EXECUTE
-- granted, so they're already safe) should be reviewed the same way the
-- next time new cron/internal-only functions are added. This migration
-- only closes the five confirmed-live, confirmed-unused-by-the-client cron
-- functions; it deliberately does not touch admin/moderator RPCs (ban_user,
-- set_user_role, etc.) since those are legitimately called by the admin
-- dashboard client and are already gated internally by
-- is_admin()/is_admin_or_mod()/ensure_admin_or_mod() checks.
