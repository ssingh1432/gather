-- 071_community_analytics_performance_indexes.sql
-- Step 16 Testing — performance test found two Seq Scans in queries that
-- back the Step 13 analytics RPCs, both invisible at current data volume
-- but linear-scaling liabilities as the app grows:
--
--   * community_membership_events had no index usable by
--     community_member_growth's per-community date-range scan (it only
--     had a (community_id, created_at) composite, which is fine, but
--     community_memberships itself — used by trending_communities'
--     "recent joins" count and community_retention's cohort join — had
--     no created_at coverage at all and was doing a full Seq Scan).
--   * post_likes had no created_at coverage, used by
--     community_daily_active_members and community_retention's "who was
--     active in the last N days" activity union.
--
-- Verified via EXPLAIN (costs off) before and after.

begin;

create index if not exists idx_community_memberships_community_created
  on public.community_memberships (community_id, created_at);

create index if not exists idx_post_likes_post_created
  on public.post_likes (post_id, created_at);

commit;
