-- 090_pages_payments_esewa.sql
-- Professional Page System — real eSewa payment integration on top of Step
-- 15's architecture-only tables.
--
-- Design: the DB never talks to eSewa directly and never holds the secret
-- key. It only owns a payment ledger (page_payment_transactions) that the
-- edge function (service role) reads/writes around calling eSewa's API.
-- Client flow:
--   1. Client calls initiate_page_payment(...) — safe to call directly
--      (SECURITY DEFINER, no secrets involved) — which creates a 'pending'
--      ledger row scoped to the caller and returns its id.
--   2. Client opens (external browser) the edge function's
--      /esewa-payment/pay/<transaction_id> URL, which is where the actual
--      HMAC-signed form to eSewa gets built, server-side, using the secret.
--   3. eSewa redirects to the edge function's own success/failure URLs,
--      which verify the signature AND re-check status directly against
--      eSewa's transaction-status API before marking anything 'completed'
--      — a redirect alone is never trusted.
--   4. The client watches its own transaction row via Realtime (RLS already
--      lets the payer select their own rows) to reflect the outcome.

create table if not exists public.page_payment_transactions (
  id uuid primary key default gen_random_uuid(),
  page_id uuid not null references public.pages(id) on delete cascade,
  payer_id uuid not null references public.users(id) on delete cascade,
  purpose text not null check (purpose in ('donation', 'subscription', 'marketplace_order')),
  -- Points at page_donations.id / page_subscribers.id / page_marketplace_orders.id
  -- depending on purpose. Not a DB-level FK since it targets different
  -- tables; the RPC below validates ownership at creation time instead.
  reference_id uuid not null,
  amount_cents integer not null check (amount_cents > 0),
  currency text not null default 'NPR',
  gateway text not null default 'esewa' check (gateway in ('esewa', 'khalti')),
  status text not null default 'pending' check (status in ('pending', 'completed', 'failed', 'cancelled')),
  gateway_ref_id text,
  raw_response jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_page_payment_transactions_payer on public.page_payment_transactions (payer_id, created_at desc);
create index if not exists idx_page_payment_transactions_page on public.page_payment_transactions (page_id);

alter table public.page_payment_transactions enable row level security;

drop policy if exists page_payment_transactions_select on public.page_payment_transactions;
create policy page_payment_transactions_select on public.page_payment_transactions
  for select using (payer_id = auth.uid() or public.current_user_has_page_permission(page_id, 'manage_monetization'));

-- No direct insert/update grants to `authenticated` — rows are only ever
-- created via initiate_page_payment() and only ever updated by the edge
-- function's service-role client after verifying with eSewa.
drop trigger if exists trg_page_payment_transactions_touch on public.page_payment_transactions;
create trigger trg_page_payment_transactions_touch
  before update on public.page_payment_transactions
  for each row execute function public.touch_updated_at();

-- Marketplace didn't have an "order" concept yet in Step 15 (only listing
-- items) — needed now so a real purchase has somewhere to live.
create table if not exists public.page_marketplace_orders (
  id uuid primary key default gen_random_uuid(),
  page_id uuid not null references public.pages(id) on delete cascade,
  item_id uuid not null references public.page_marketplace_items(id) on delete restrict,
  buyer_id uuid not null references public.users(id) on delete cascade,
  quantity integer not null default 1 check (quantity > 0),
  amount_cents integer not null check (amount_cents > 0),
  currency text not null default 'NPR',
  status text not null default 'pending_payment' check (status in ('pending_payment', 'paid', 'fulfilled', 'cancelled', 'refunded')),
  shipping_info jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_page_marketplace_orders_page on public.page_marketplace_orders (page_id);
create index if not exists idx_page_marketplace_orders_buyer on public.page_marketplace_orders (buyer_id);

alter table public.page_marketplace_orders enable row level security;

drop policy if exists page_marketplace_orders_select on public.page_marketplace_orders;
create policy page_marketplace_orders_select on public.page_marketplace_orders
  for select using (buyer_id = auth.uid() or public.current_user_has_page_permission(page_id, 'manage_monetization'));

drop policy if exists page_marketplace_orders_insert on public.page_marketplace_orders;
create policy page_marketplace_orders_insert on public.page_marketplace_orders
  for insert with check (buyer_id = auth.uid());

drop policy if exists page_marketplace_orders_manager_update on public.page_marketplace_orders;
create policy page_marketplace_orders_manager_update on public.page_marketplace_orders
  for update using (public.current_user_has_page_permission(page_id, 'manage_monetization'));

drop trigger if exists trg_page_marketplace_orders_touch on public.page_marketplace_orders;
create trigger trg_page_marketplace_orders_touch
  before update on public.page_marketplace_orders
  for each row execute function public.touch_updated_at();

-- Initiate a payment: validates the target and creates BOTH the
-- purpose-specific pending row (donation/order) and the payment ledger
-- row in one transaction, so there's never a ledger row with nothing
-- behind it. Returns the transaction id the client needs for step 2.
create or replace function public.initiate_page_payment(
  p_page_id uuid,
  p_purpose text,
  p_amount_cents integer,
  p_message text default null,
  p_tier_id uuid default null,
  p_item_id uuid default null,
  p_quantity integer default 1
)
returns uuid
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_payer uuid := auth.uid();
  v_reference_id uuid;
  v_txn_id uuid;
  v_page_status text;
begin
  if v_payer is null then
    raise exception 'Must be signed in to pay' using errcode = 'P0001';
  end if;
  if p_amount_cents is null or p_amount_cents <= 0 then
    raise exception 'Invalid amount' using errcode = 'P0001';
  end if;

  select status into v_page_status from public.pages where id = p_page_id and deleted_at is null;
  if v_page_status is distinct from 'published' then
    raise exception 'Page not found or not published' using errcode = 'P0001';
  end if;

  if p_purpose = 'donation' then
    insert into public.page_donations (page_id, donor_id, amount_cents, currency, message, status)
    values (p_page_id, v_payer, p_amount_cents, 'NPR', p_message, 'pending')
    returning id into v_reference_id;

  elsif p_purpose = 'subscription' then
    if p_tier_id is null then
      raise exception 'tier_id required for subscription payments' using errcode = 'P0001';
    end if;
    if not exists (select 1 from public.page_subscription_tiers t where t.id = p_tier_id and t.page_id = p_page_id and t.active) then
      raise exception 'Subscription tier not found or inactive' using errcode = 'P0001';
    end if;
    insert into public.page_subscribers (page_id, user_id, tier_id, status)
    values (p_page_id, v_payer, p_tier_id, 'inactive')
    on conflict (page_id, user_id) do update set tier_id = excluded.tier_id, status = 'inactive'
    returning id into v_reference_id;

  elsif p_purpose = 'marketplace_order' then
    if p_item_id is null then
      raise exception 'item_id required for marketplace payments' using errcode = 'P0001';
    end if;
    if not exists (select 1 from public.page_marketplace_items i where i.id = p_item_id and i.page_id = p_page_id and i.status = 'active') then
      raise exception 'Item not found or not available' using errcode = 'P0001';
    end if;
    insert into public.page_marketplace_orders (page_id, item_id, buyer_id, quantity, amount_cents, status)
    values (p_page_id, p_item_id, v_payer, coalesce(p_quantity, 1), p_amount_cents, 'pending_payment')
    returning id into v_reference_id;

  else
    raise exception 'Unknown payment purpose: %', p_purpose using errcode = 'P0001';
  end if;

  insert into public.page_payment_transactions (page_id, payer_id, purpose, reference_id, amount_cents, gateway, status)
  values (p_page_id, v_payer, p_purpose, v_reference_id, p_amount_cents, 'esewa', 'pending')
  returning id into v_txn_id;

  return v_txn_id;
end;
$$;

grant execute on function public.initiate_page_payment(uuid, text, integer, text, uuid, uuid, integer) to authenticated;

-- Realtime — so the client can watch its own transaction row flip from
-- 'pending' to 'completed'/'failed' after the edge function's callback,
-- matching the existing page_messages/notifications realtime pattern.
alter publication supabase_realtime add table public.page_payment_transactions;
