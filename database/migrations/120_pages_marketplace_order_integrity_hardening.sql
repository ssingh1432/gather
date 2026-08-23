-- 120_pages_marketplace_order_integrity_hardening.sql
-- Professional Pages only.
-- Prevents Page monetization managers from rewriting marketplace order
-- identity or financial fields during status/shipping updates.

create or replace function public.guard_page_marketplace_order_update()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.id <> old.id
     or new.page_id <> old.page_id
     or new.item_id <> old.item_id
     or new.buyer_id <> old.buyer_id
     or new.quantity <> old.quantity
     or new.amount_cents <> old.amount_cents
     or new.currency <> old.currency
     or new.created_at <> old.created_at then
    raise exception 'page marketplace order identity and financial fields cannot be changed';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_guard_page_marketplace_order_update on public.page_marketplace_orders;
create trigger trg_guard_page_marketplace_order_update
before update on public.page_marketplace_orders
for each row execute function public.guard_page_marketplace_order_update();

comment on function public.guard_page_marketplace_order_update() is
  'Page-only: prevents rewriting marketplace order identity and financial fields; status/shipping updates remain supported.';
