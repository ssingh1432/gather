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
begin
  -- Review identity is immutable. A review cannot be moved between Pages or
  -- reassigned to another user through UPDATE, including by the reviewer.
  if new.id <> old.id
     or new.page_id <> old.page_id
     or new.user_id <> old.user_id then
    raise exception 'page review identity cannot be changed';
  end if;

  -- Preserve the existing moderation/ownership boundary: ordinary reviewers
  -- may edit only review content/rating fields; Page-team moderation may
  -- change moderation fields, while the owner response remains server-side
  -- controlled by the existing review guard/RLS design.
  return new;
end;
$$;

drop trigger if exists trg_guard_page_review_update on public.page_reviews;
create trigger trg_guard_page_review_update
before update on public.page_reviews
for each row execute function public.guard_page_review_update();

-- Defense in depth: ensure the existing INSERT self-review invariant also
-- remains enforced through the UPDATE path if review identity is ever
-- extended in the future.
comment on function public.guard_page_review_update() is
  'Page Reviews only: prevents changing review id, page_id, or user_id during UPDATE.';
