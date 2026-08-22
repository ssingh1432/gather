-- Professional Pages: owner-authored post engagement.
-- Dedicated tables keep Page posts isolated from the generic public.posts
-- engagement system used by personal/community posts.

create table if not exists public.page_post_likes (
  post_id uuid not null references public.page_posts(id) on delete cascade,
  user_id uuid not null references public.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (post_id, user_id)
);

create table if not exists public.page_post_comments (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.page_posts(id) on delete cascade,
  user_id uuid not null references public.users(id) on delete cascade,
  parent_comment_id uuid references public.page_post_comments(id) on delete cascade,
  content text not null check (char_length(btrim(content)) between 1 and 2000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.page_post_shares (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.page_posts(id) on delete cascade,
  user_id uuid not null references public.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

create index if not exists idx_page_post_comments_post on public.page_post_comments(post_id, created_at);
create index if not exists idx_page_post_shares_post on public.page_post_shares(post_id, created_at);

alter table public.page_post_likes enable row level security;
alter table public.page_post_comments enable row level security;
alter table public.page_post_shares enable row level security;

create policy page_post_likes_select on public.page_post_likes for select using (
  exists (select 1 from public.page_posts pp join public.pages pg on pg.id = pp.page_id
          where pp.id = post_id and pp.status = 'published' and pp.deleted_at is null
            and pg.status = 'published' and pg.deleted_at is null)
);
create policy page_post_likes_insert on public.page_post_likes for insert with check (
  auth.uid() = user_id and exists (select 1 from public.page_posts pp join public.pages pg on pg.id = pp.page_id
    where pp.id = post_id and pp.status = 'published' and pp.deleted_at is null
      and pg.status = 'published' and pg.deleted_at is null)
);
create policy page_post_likes_delete on public.page_post_likes for delete using (auth.uid() = user_id);

create policy page_post_comments_select on public.page_post_comments for select using (
  exists (select 1 from public.page_posts pp join public.pages pg on pg.id = pp.page_id
    where pp.id = post_id and pp.status = 'published' and pp.deleted_at is null
      and pg.status = 'published' and pg.deleted_at is null)
);
create policy page_post_comments_insert on public.page_post_comments for insert with check (
  auth.uid() = user_id and exists (select 1 from public.page_posts pp join public.pages pg on pg.id = pp.page_id
    where pp.id = post_id and pp.status = 'published' and pp.deleted_at is null
      and pg.status = 'published' and pg.deleted_at is null)
);
create policy page_post_comments_update on public.page_post_comments for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy page_post_comments_delete on public.page_post_comments for delete using (
  auth.uid() = user_id or exists (select 1 from public.page_posts pp where pp.id = post_id and public.current_user_has_page_permission(pp.page_id, 'manage_content'))
);

create policy page_post_shares_select on public.page_post_shares for select using (
  exists (select 1 from public.page_posts pp join public.pages pg on pg.id = pp.page_id
    where pp.id = post_id and pp.status = 'published' and pp.deleted_at is null
      and pg.status = 'published' and pg.deleted_at is null)
);
create policy page_post_shares_insert on public.page_post_shares for insert with check (
  auth.uid() = user_id and exists (select 1 from public.page_posts pp join public.pages pg on pg.id = pp.page_id
    where pp.id = post_id and pp.status = 'published' and pp.deleted_at is null
      and pg.status = 'published' and pg.deleted_at is null)
);

grant select on public.page_post_likes, public.page_post_comments, public.page_post_shares to authenticated;
grant insert, delete on public.page_post_likes to authenticated;
grant insert, update, delete on public.page_post_comments to authenticated;
grant insert on public.page_post_shares to authenticated;

create or replace function public.sync_page_post_metrics_engagement()
returns trigger language plpgsql security definer set search_path = 'public' as $$
declare
  v_page_id uuid;
  v_post_id uuid;
begin
  v_post_id := coalesce(new.post_id, old.post_id);
  select page_id into v_page_id from public.page_posts where id = v_post_id;
  if v_page_id is null then return coalesce(new, old); end if;
  insert into public.page_post_metrics(post_id, page_id, reactions, comments, shares)
  values (
    v_post_id, v_page_id,
    (select count(*) from public.page_post_likes where post_id = v_post_id),
    (select count(*) from public.page_post_comments where post_id = v_post_id),
    (select count(*) from public.page_post_shares where post_id = v_post_id)
  )
  on conflict (post_id) do update set
    reactions = (select count(*) from public.page_post_likes where post_id = v_post_id),
    comments = (select count(*) from public.page_post_comments where post_id = v_post_id),
    shares = (select count(*) from public.page_post_shares where post_id = v_post_id),
    updated_at = now();
  return coalesce(new, old);
end;
$$;

drop trigger if exists trg_page_post_like_metrics on public.page_post_likes;
create trigger trg_page_post_like_metrics after insert or delete on public.page_post_likes for each row execute function public.sync_page_post_metrics_engagement();
drop trigger if exists trg_page_post_comment_metrics on public.page_post_comments;
create trigger trg_page_post_comment_metrics after insert or update or delete on public.page_post_comments for each row execute function public.sync_page_post_metrics_engagement();
drop trigger if exists trg_page_post_share_metrics on public.page_post_shares;
create trigger trg_page_post_share_metrics after insert on public.page_post_shares for each row execute function public.sync_page_post_metrics_engagement();
