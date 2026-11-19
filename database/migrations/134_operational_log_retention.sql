-- 134: retention for unbounded operational logs (Phase 17 follow-up).
--
--   beta_error_logs   60 days   (client crash/debug logs; largest table at 9.5k rows)
--   analytics_events  400 days  (keeps a full year plus margin for retention cohorts / year-over-year)
--
-- Deliberately NOT pruned: security_events, admin_audit_log, moderation_actions, legal_* and
-- copyright_* tables (audit / legal records; retention for these is a legal decision, see
-- docs/MAINTENANCE.md). Change the intervals here (new migration) if counsel says otherwise.
-- Runs daily at 03:30 UTC. Not callable by API clients.

create index if not exists idx_analytics_events_occurred_at on public.analytics_events (occurred_at);

create or replace function public.prune_operational_logs()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare v_logs bigint; v_events bigint;
begin
  delete from public.beta_error_logs where created_at < now() - interval '60 days';
  get diagnostics v_logs = row_count;
  delete from public.analytics_events where occurred_at < now() - interval '400 days';
  get diagnostics v_events = row_count;
  return jsonb_build_object('beta_error_logs', v_logs, 'analytics_events', v_events, 'ran_at', now());
end $$;

revoke all on function public.prune_operational_logs() from public, anon, authenticated;
grant execute on function public.prune_operational_logs() to service_role;

do $$
begin
  if exists (select 1 from cron.job where jobname = 'prune-operational-logs') then
    perform cron.unschedule('prune-operational-logs');
  end if;
  perform cron.schedule('prune-operational-logs', '30 3 * * *', 'select public.prune_operational_logs();');
end $$;
