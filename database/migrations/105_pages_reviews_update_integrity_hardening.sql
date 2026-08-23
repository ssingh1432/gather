-- 105_pages_reviews_update_integrity_hardening.sql
-- Professional Page System — Page Reviews security hardening.
--
-- Fixes a confirmed integrity gap: a reviewer could UPDATE their own review
-- and change page_id. The self-review guard was INSERT-only, so an existing
-- review could potentially be moved onto another Page without re-running the
-- eligibility invariant.
--
-- Scope: Professional Pages / Page Reviews only.

create or replace function public.guard_page_review_update()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_is_team boolean := public.current_user_page_role(new.page_id) = 'owner'
    or public.current_user_has_page_permission(new.page_id, 'manage_reviews');
begin
  -- Review identity is immutable. A review cannot be moved between Pages or
  -- reassigned to another user through UPDATE, including by the reviewer.
  if new.id <> old.id
     or new.page_id <> old.page_id
     or new.user_id <> old.user_id then
    raise exception 'page review identity cannot be changed';
  end if;

  -- Preserve the existing moderation/response boundary for ordinary
  -- reviewers. Page team members may moderate/respond according to the
  -- existing RLS permission checks.
  if not v_is_team then
    if new.status is distinct from old.status
       or new.owner_response is distinct from old.owner_response
       or new.owner_response_by is distinct from old.owner_response_by then
      raise exception 'Only the page team can moderate or respond to a review.';
    end if;
  end if;

  -- Preserve the existing server-side attribution for Page responses.
  if new.owner_response is distinct from old.owner_response
     and new.owner_response is not null then
    new.owner_response_by := auth.uid();
    new.owner_response_at := now();
  end if;

  return new;
end;
$$;

drop trigger if exists trg_guard_page_review_update on public.page_reviews;
create trigger trg_guard_page_review_update
before update on public.page_reviews
for each row execute function public.guard_page_review_update();

comment on function public.guard_page_review_update() is
  'Page Reviews only: prevents changing review identity and preserves existing moderation/response guards.';
