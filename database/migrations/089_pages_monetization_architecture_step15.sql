-- 089_pages_monetization_architecture_step15.sql
-- Professional Page System — Step 15 (Future Monetization)
--
-- Architecture only, per the brief: "Do not implement payments now."
-- Nothing here charges a card, moves money, or serves an ad — every table
-- defaults to inactive/draft and every feature is opt-in and gated behind
-- a new `manage_monetization` permission (owner + manager only, since
-- these are financial). This mirrors the existing user-level monetization
-- pattern (users.monetization_status, user_payout_preferences,
-- check_monetization_eligibility) exactly, so wiring a real payment
-- processor later is additive — new columns/values, not new tables.
--
-- Covers all six areas from the brief:
--   Subscriptions      -> page_subscription_tiers + page_subscribers
--   Paid Followers      -> page_subscribers.tier_id (a tier IS a paid-
--                          follower tier; no separate concept needed)
--   Advertising          -> page_ad_campaigns (boosted-post model, mirrors
--                          the existing per-user ad system's shape)
--   Donations            -> page_donations
--   Creator Monetization -> pages.monetization_status/enabled +
--                          page_payout_preferences
--   Marketplace          -> page_marketplace_items

-- 0. Permission + page-level monetization status ------------------------------
insert into public.page_permissions (key, label, description)
values ('manage_monetization', 'Manage monetization', 'Configure subscriptions, donations, ads, marketplace listings, and payout details.')
on conflict (key) do nothing;

insert into public.page_role_permissions (role, permission_key, allowed)
values ('owner', 'manage_monetization', true), ('manager', 'manage_monetization', true)
on conflict (role, permission_key) do nothing;

alter table public.pages
  add column if not exists monetization_enabled boolean not null default false,
  add column if not exists monetization_status text not null default 'none';

alter table public.pages drop constraint if exists pages_monetization_status_chk;
alter table public.pages
  add constraint pages_monetization_status_chk
  check (monetization_status in ('none', 'pending_review', 'approved', 'rejected', 'suspended'));

-- 1. Creator Monetization: payout details (page-scoped mirror of
--    user_payout_preferences) -----------------------------------------------
create table if not exists public.page_payout_preferences (
  page_id uuid primary key references public.pages(id) on delete cascade,
  provider text,
  holder_name text,
  masked_reference text,
  status text not null default 'pending_review' check (status in ('pending_review', 'approved', 'rejected')),
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.page_payout_preferences enable row level security;

drop policy if exists page_payout_preferences_select on public.page_payout_preferences;
create policy page_payout_preferences_select on public.page_payout_preferences
  for select using (public.current_user_has_page_permission(page_id, 'manage_monetization'));

drop policy if exists page_payout_preferences_upsert on public.page_payout_preferences;
create policy page_payout_preferences_upsert on public.page_payout_preferences
  for insert with check (public.current_user_has_page_permission(page_id, 'manage_monetization'));

drop policy if exists page_payout_preferences_update on public.page_payout_preferences;
create policy page_payout_preferences_update on public.page_payout_preferences
  for update using (public.current_user_has_page_permission(page_id, 'manage_monetization'));

drop trigger if exists trg_page_payout_preferences_touch on public.page_payout_preferences;
create trigger trg_page_payout_preferences_touch
  before update on public.page_payout_preferences
  for each row execute function public.touch_updated_at();

-- Editing payout details resets status to pending_review, exactly matching
-- the user-level reset_payout_status_on_self_edit behavior.
create or replace function public.reset_page_payout_status_on_self_edit()
returns trigger
language plpgsql
security definer
set search_path = 'public'
as $$
begin
  if new.status is not distinct from old.status
     and (new.provider is distinct from old.provider
       or new.holder_name is distinct from old.holder_name
       or new.masked_reference is distinct from old.masked_reference) then
    new.status := 'pending_review';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_reset_page_payout_status_on_self_edit on public.page_payout_preferences;
create trigger trg_reset_page_payout_status_on_self_edit
  before update on public.page_payout_preferences
  for each row execute function public.reset_page_payout_status_on_self_edit();

-- 2. Subscriptions & Paid Followers -------------------------------------------
create table if not exists public.page_subscription_tiers (
  id uuid primary key default gen_random_uuid(),
  page_id uuid not null references public.pages(id) on delete cascade,
  name text not null check (char_length(name) between 2 and 60),
  description text,
  price_cents integer not null check (price_cents >= 0),
  currency text not null default 'NPR',
  benefits jsonb not null default '[]'::jsonb,
  active boolean not null default false,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_page_subscription_tiers_page on public.page_subscription_tiers (page_id);

alter table public.page_subscription_tiers enable row level security;

drop policy if exists page_subscription_tiers_select on public.page_subscription_tiers;
create policy page_subscription_tiers_select on public.page_subscription_tiers
  for select using (
    (active = true and exists (select 1 from public.pages p where p.id = page_id and p.status = 'published' and p.deleted_at is null))
    or public.current_user_has_page_permission(page_id, 'manage_monetization')
  );

drop policy if exists page_subscription_tiers_manage on public.page_subscription_tiers;
create policy page_subscription_tiers_manage on public.page_subscription_tiers
  for all using (public.current_user_has_page_permission(page_id, 'manage_monetization'))
  with check (public.current_user_has_page_permission(page_id, 'manage_monetization'));

drop trigger if exists trg_page_subscription_tiers_touch on public.page_subscription_tiers;
create trigger trg_page_subscription_tiers_touch
  before update on public.page_subscription_tiers
  for each row execute function public.touch_updated_at();

create table if not exists public.page_subscribers (
  id uuid primary key default gen_random_uuid(),
  page_id uuid not null references public.pages(id) on delete cascade,
  user_id uuid not null references public.users(id) on delete cascade,
  tier_id uuid references public.page_subscription_tiers(id) on delete set null,
  status text not null default 'inactive' check (status in ('inactive', 'active', 'cancelled', 'past_due')),
  started_at timestamptz,
  current_period_end timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (page_id, user_id)
);

create index if not exists idx_page_subscribers_page on public.page_subscribers (page_id) where status = 'active';

alter table public.page_subscribers enable row level security;

drop policy if exists page_subscribers_select_own on public.page_subscribers;
create policy page_subscribers_select_own on public.page_subscribers
  for select using (user_id = auth.uid() or public.current_user_has_page_permission(page_id, 'manage_monetization'));

drop trigger if exists trg_page_subscribers_touch on public.page_subscribers;
create trigger trg_page_subscribers_touch
  before update on public.page_subscribers
  for each row execute function public.touch_updated_at();

-- 3. Donations ------------------------------------------------------------
create table if not exists public.page_donations (
  id uuid primary key default gen_random_uuid(),
  page_id uuid not null references public.pages(id) on delete cascade,
  donor_id uuid references public.users(id) on delete set null,
  amount_cents integer not null check (amount_cents > 0),
  currency text not null default 'NPR',
  message text,
  status text not null default 'pending' check (status in ('pending', 'completed', 'failed', 'refunded')),
  created_at timestamptz not null default now()
);

create index if not exists idx_page_donations_page on public.page_donations (page_id, created_at desc);

alter table public.page_donations enable row level security;

drop policy if exists page_donations_select on public.page_donations;
create policy page_donations_select on public.page_donations
  for select using (donor_id = auth.uid() or public.current_user_has_page_permission(page_id, 'manage_monetization'));

-- 4. Marketplace ----------------------------------------------------------
create table if not exists public.page_marketplace_items (
  id uuid primary key default gen_random_uuid(),
  page_id uuid not null references public.pages(id) on delete cascade,
  title text not null check (char_length(title) between 2 and 120),
  description text,
  price_cents integer not null check (price_cents >= 0),
  currency text not null default 'NPR',
  images jsonb not null default '[]'::jsonb,
  status text not null default 'draft' check (status in ('draft', 'active', 'archived', 'sold_out')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_page_marketplace_items_page on public.page_marketplace_items (page_id);

alter table public.page_marketplace_items enable row level security;

drop policy if exists page_marketplace_items_select on public.page_marketplace_items;
create policy page_marketplace_items_select on public.page_marketplace_items
  for select using (
    (status in ('active', 'sold_out') and exists (select 1 from public.pages p where p.id = page_id and p.status = 'published' and p.deleted_at is null))
    or public.current_user_has_page_permission(page_id, 'manage_monetization')
  );

drop policy if exists page_marketplace_items_manage on public.page_marketplace_items;
create policy page_marketplace_items_manage on public.page_marketplace_items
  for all using (public.current_user_has_page_permission(page_id, 'manage_monetization'))
  with check (public.current_user_has_page_permission(page_id, 'manage_monetization'));

drop trigger if exists trg_page_marketplace_items_touch on public.page_marketplace_items;
create trigger trg_page_marketplace_items_touch
  before update on public.page_marketplace_items
  for each row execute function public.touch_updated_at();

-- 5. Advertising (boosted posts) -------------------------------------------
create table if not exists public.page_ad_campaigns (
  id uuid primary key default gen_random_uuid(),
  page_id uuid not null references public.pages(id) on delete cascade,
  page_post_id uuid references public.page_posts(id) on delete set null,
  objective text not null default 'awareness' check (objective in ('awareness', 'engagement', 'followers', 'clicks')),
  budget_cents integer not null check (budget_cents >= 0),
  currency text not null default 'NPR',
  status text not null default 'draft' check (status in ('draft', 'pending_review', 'active', 'paused', 'completed', 'rejected')),
  start_at timestamptz,
  end_at timestamptz,
  reviewed_by uuid references public.users(id) on delete set null,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_page_ad_campaigns_page on public.page_ad_campaigns (page_id);

alter table public.page_ad_campaigns enable row level security;

drop policy if exists page_ad_campaigns_manage on public.page_ad_campaigns;
create policy page_ad_campaigns_manage on public.page_ad_campaigns
  for all using (public.current_user_has_page_permission(page_id, 'manage_monetization'))
  with check (public.current_user_has_page_permission(page_id, 'manage_monetization'));

drop trigger if exists trg_page_ad_campaigns_touch on public.page_ad_campaigns;
create trigger trg_page_ad_campaigns_touch
  before update on public.page_ad_campaigns
  for each row execute function public.touch_updated_at();

-- 6. Eligibility check, mirroring check_monetization_eligibility's shape
--    for the user-level system so the client can reuse the same UI
--    pattern later. -----------------------------------------------------
create or replace function public.check_page_monetization_eligibility(p_page_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = 'public'
as $$
declare
  v_page record;
  v_reasons text[] := array[]::text[];
begin
  select follower_count, verification_status, status, created_at into v_page
  from public.pages where id = p_page_id;

  if v_page is null then
    return jsonb_build_object('eligible', false, 'reasons', array['Page not found']);
  end if;
  if not public.current_user_has_page_permission(p_page_id, 'manage_monetization') then
    return jsonb_build_object('eligible', false, 'reasons', array['Not authorized']);
  end if;

  if v_page.status <> 'published' then
    v_reasons := v_reasons || 'Page must be published';
  end if;
  if v_page.follower_count < 100 then
    v_reasons := v_reasons || 'Page needs at least 100 followers';
  end if;
  if v_page.created_at > now() - interval '30 days' then
    v_reasons := v_reasons || 'Page must be at least 30 days old';
  end if;

  return jsonb_build_object('eligible', array_length(v_reasons, 1) is null, 'reasons', to_jsonb(v_reasons));
end;
$$;

grant execute on function public.check_page_monetization_eligibility(uuid) to authenticated;
