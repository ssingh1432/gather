-- 116_pages_owner_follow_and_role_invariants.sql
-- COMMAND 3: Page owner/follower and role invariants.
-- Owner following is automatic and cannot be used to obtain visitor authorship.

create or replace function public.ensure_page_owner_follow()
returns trigger
language plpgsql
security definer
set search_path = 'public'
as $$
begin
  insert into public.page_followers(page_id, user_id)
  values (new.id, new.owner_id)
  on conflict (page_id, user_id) do nothing;
  return new;
end;
$$;

drop trigger if exists trg_ensure_page_owner_follow on public.pages;
create trigger trg_ensure_page_owner_follow
after insert on public.pages
for each row execute function public.ensure_page_owner_follow();

create or replace function public.prevent_page_owner_unfollow()
returns trigger
language plpgsql
security definer
set search_path = 'public'
as $$
begin
  if exists (
    select 1 from public.pages p
    where p.id = old.page_id and p.owner_id = old.user_id
  ) then
    raise exception 'A Page owner is automatically a follower and cannot unfollow the Page.';
  end if;
  return old;
end;
$$;

drop trigger if exists trg_prevent_page_owner_unfollow on public.page_followers;
create trigger trg_prevent_page_owner_unfollow
before delete on public.page_followers
for each row execute function public.prevent_page_owner_unfollow();

create or replace function public.prevent_owner_as_visitor_author()
returns trigger
language plpgsql
security definer
set search_path = 'public'
as $$
begin
  if tg_op = 'INSERT' and exists (
    select 1 from public.pages p
    where p.id = new.page_id and p.owner_id = auth.uid()
  ) then
    raise exception 'Page owners must publish Page-authored posts, not visitor posts.';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_prevent_owner_as_visitor_author on public.page_visitor_posts;
create trigger trg_prevent_owner_as_visitor_author
before insert on public.page_visitor_posts
for each row execute function public.prevent_owner_as_visitor_author();

create or replace function public.prevent_page_owner_role_assignment()
returns trigger
language plpgsql
security definer
set search_path = 'public'
as $$
begin
  if new.role = 'owner' then
    raise exception 'The Page owner is defined by pages.owner_id; owner cannot be granted as a team role.';
  end if;
  if exists (
    select 1 from public.pages p
    where p.id = new.page_id and p.owner_id = new.user_id
  ) then
    raise exception 'The Page owner cannot simultaneously hold a visitor/team role.';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_prevent_page_owner_role_assignment on public.page_roles;
create trigger trg_prevent_page_owner_role_assignment
before insert or update on public.page_roles
for each row execute function public.prevent_page_owner_role_assignment();
