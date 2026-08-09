-- 091_pages_monetization_grants_fix.sql
-- Professional Page System — Step 16 (Testing) bug fix.
--
-- Found via RLS validation testing (impersonating a real `authenticated`
-- role inside a rolled-back transaction, per the standard Postgres
-- technique: `set local role authenticated; set local
-- request.jwt.claims = '...'`): every monetization table added in
-- migrations 089 and 090 had RLS policies but ZERO GRANTs to the
-- `authenticated` role. In Postgres, GRANT and RLS are two independent
-- layers — RLS only filters rows an operation is already permitted to
-- touch; without the base GRANT, Postgres denies the operation before RLS
-- is ever evaluated ("permission denied for table X").
--
-- Practical impact: every direct-table Flutter call built on top of these
-- tables (subscription tier browsing/management, marketplace item
-- browsing/management, payout preferences, donation/order history,
-- payment-transaction status — including the Realtime status watch used
-- by donate_sheet.dart / subscribe_sheet.dart / marketplace_checkout_
-- sheet.dart) has been silently broken since it was written. The
-- initiate_page_payment() RPC itself still worked (SECURITY DEFINER
-- functions run as the function owner, bypassing grants), which is why
-- this wasn't caught by CI or by eye — only a real permission check
-- surfaced it.

grant select, insert, update, delete on public.page_subscription_tiers to authenticated;
grant select on public.page_subscribers to authenticated;
grant select on public.page_donations to authenticated;
grant select, insert, update, delete on public.page_marketplace_items to authenticated;
grant select, insert, update on public.page_marketplace_orders to authenticated;
grant select, insert, update, delete on public.page_ad_campaigns to authenticated;
grant select, insert, update on public.page_payout_preferences to authenticated;
grant select on public.page_payment_transactions to authenticated;
