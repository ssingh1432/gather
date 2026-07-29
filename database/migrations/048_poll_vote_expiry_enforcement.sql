-- 048: Reject votes on an expired poll at the database layer.
--
-- polls.expires_at has existed since the original poll schema, and the
-- Phase 10 composer now lets a user set it (create_post_screen.dart's poll
-- sheet), but nothing server-side ever enforced it — poll_votes only had
-- `user_id = auth.uid()` on INSERT. The feed card hides/disables voting
-- once expires_at has passed, but that's a client-side courtesy only; the
-- REST endpoint itself would happily accept a vote sent after expiry
-- (replayed request, modified client, or just a clock skew race right at
-- the boundary). This closes that with a BEFORE INSERT trigger, which is
-- the correct enforcement point since with_check clauses in pg_policies
-- can't reference the target row's related-poll expiry without a
-- subquery — a trigger keeps the intent explicit and gives a clear error.

begin;

create or replace function public.reject_vote_on_expired_poll()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  if exists (
    select 1 from public.polls p
    where p.id = new.poll_id
      and p.expires_at is not null
      and p.expires_at <= now()
  ) then
    raise exception 'This poll has closed and is no longer accepting votes.'
      using errcode = 'P0001';
  end if;
  return new;
end;
$function$;

drop trigger if exists trg_reject_vote_on_expired_poll on public.poll_votes;
create trigger trg_reject_vote_on_expired_poll
  before insert on public.poll_votes
  for each row execute function public.reject_vote_on_expired_poll();

commit;
