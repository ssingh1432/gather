-- Phase 7 (User Safety) — Part 1: Restrict users, Hide comments.
--
-- Restrict mirrors Instagram's model rather than Block/Mute:
--   * One-directional, never disclosed to the restricted user.
--   * The restricted person can still see the restrictor's public content
--     and still comment — but their comments on the restrictor's posts are
--     only visible to themselves and the restrictor, not to other viewers,
--     unless the restrictor is the one commenting/viewing.
--   * Does not touch follows, so it stays invisible.
--
-- Hide comments lets a post owner hide any comment on their own post
-- (e.g. spam or off-topic replies) without deleting it outright — visible
-- only to the post owner and the comment's own author, same "quiet"
-- visibility contract as restrict.

-- 1. Restrict list -----------------------------------------------------
create table if not exists public.user_restricts (
  restrictor_id uuid not null references public.users(id) on delete cascade,
  restricted_id uuid not null references public.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (restrictor_id, restricted_id),
  constraint user_restricts_no_self_restrict check (restrictor_id <> restricted_id)
);

create index if not exists idx_user_restricts_restrictor on public.user_restricts (restrictor_id);

alter table public.user_restricts enable row level security;
revoke all on public.user_restricts from anon, authenticated;
grant select, insert, delete on public.user_restricts to authenticated;

drop policy if exists "Users manage their own restrict list" on public.user_restricts;
create policy "Users manage their own restrict list"
  on public.user_restricts for all
  to authenticated
  using (restrictor_id = auth.uid())
  with check (restrictor_id = auth.uid());

create or replace function public.is_user_restricted(p_restrictor uuid, p_restricted uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.user_restricts ur
    where ur.restrictor_id = p_restrictor and ur.restricted_id = p_restricted
  );
$$;

grant execute on function public.is_user_restricted(uuid, uuid) to authenticated;

-- 2. Hide comments -------------------------------------------------------
alter table public.post_comments add column if not exists is_hidden boolean not null default false;

-- Post owners toggle this through a SECURITY DEFINER RPC rather than a
-- direct RLS update policy, so the check ("are you the post's author") can
-- reference the parent post without opening post_comments UPDATE to
-- anyone who merely has beta access to that row's post.
create or replace function public.set_comment_hidden(p_comment_id uuid, p_hidden boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_post_author uuid;
begin
  select p.author_id into v_post_author
  from public.post_comments c
  join public.posts p on p.id = c.post_id
  where c.id = p_comment_id;

  if v_post_author is null then
    raise exception 'Comment not found' using errcode = 'P0002';
  end if;

  if v_post_author <> auth.uid() and not public.is_admin_or_mod() then
    raise exception 'Only the post owner can hide comments on this post' using errcode = '42501';
  end if;

  update public.post_comments set is_hidden = p_hidden where id = p_comment_id;
end;
$$;

grant execute on function public.set_comment_hidden(uuid, boolean) to authenticated;

-- 3. Comment visibility — supersedes comments_select_visible_beta to layer
-- restrict + hide on top of the existing block/beta-access checks.
drop policy if exists comments_select_visible_beta on public.post_comments;
create policy comments_select_visible_v2 on public.post_comments for select using (
  public.current_user_has_beta_access()
  and (
    user_id = auth.uid()
    or exists (
      select 1 from public.posts p
      where p.id = post_id
        and p.is_removed = false
        and not public.users_are_blocked(auth.uid(), p.author_id)
        and not public.users_are_blocked(auth.uid(), post_comments.user_id)
        and (
          p.author_id = auth.uid()
          or (
            not post_comments.is_hidden
            and not public.is_user_restricted(p.author_id, post_comments.user_id)
          )
        )
    )
  )
);
