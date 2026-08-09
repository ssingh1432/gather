-- 093_pages_service_role_grants_fix.sql
-- Professional Page System — Step 16 (Testing) bug fix, found via a real
-- live eSewa test payment (not synthetic testing this time).
--
-- The esewa-payment edge function's service-role client failed with:
--   "permission denied for table page_payment_transactions" (42501),
--   hint: "Grant the required privileges to the current role with:
--   GRANT SELECT ON public.page_payment_transactions TO service_role;"
--
-- Investigation showed this isn't specific to the payment tables from
-- migrations 089/090 — on this project, `service_role` has NEVER had an
-- explicit grant on ANY table under the entire page_* schema (pages,
-- page_posts, page_messages, page_reviews, etc. all included), unlike
-- `users`/`notifications` which do have explicit service_role grants
-- (confirmed: users/notifications each have SELECT/INSERT/UPDATE/DELETE
-- to service_role; every single page_* table had none). service_role is
-- not an automatic RLS-bypassing superuser on every Supabase project —
-- on this one it behaves like any other role and needs explicit grants,
-- same root cause documented in notification-dispatch's comments about
-- this project's Secret Keys / JWT Signing Keys migration.
--
-- This had simply never been exercised before: every existing Pages
-- feature that touches these tables from an edge/service context does so
-- through a SECURITY DEFINER RPC or trigger, which runs as the function
-- owner (bypassing grants) rather than as the literal service_role
-- Postgres role. esewa-payment is the first thing to query page_* tables
-- directly via a service-role Supabase client, which is what finally
-- surfaced this.
grant select, insert, update, delete on
  public.pages,
  public.page_posts,
  public.page_messages,
  public.page_reviews,
  public.page_events,
  public.page_followers,
  public.page_follow_invites,
  public.page_reports,
  public.page_review_reports,
  public.page_review_helpful_votes,
  public.page_audit_logs,
  public.page_analytics,
  public.page_post_metrics,
  public.page_post_view_events,
  public.page_quick_replies,
  public.page_donations,
  public.page_subscription_tiers,
  public.page_subscribers,
  public.page_marketplace_items,
  public.page_marketplace_orders,
  public.page_ad_campaigns,
  public.page_payout_preferences,
  public.page_payment_transactions
to service_role;

-- Reference/lookup tables — read-only is sufficient for service_role here.
grant select on
  public.page_categories,
  public.page_permissions,
  public.page_roles,
  public.page_role_permissions,
  public.page_reserved_usernames
to service_role;
