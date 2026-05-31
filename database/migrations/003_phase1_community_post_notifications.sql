-- Phase 1: harden notification triggers so database events can create
-- recipient-owned notification records under RLS.

create or replace function public.create_notification_on_follow()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if exists (
    select 1
    from public.user_blocks ub
    where (ub.blocker_id = new.following_id and ub.blocked_id = new.follower_id)
       or (ub.blocker_id = new.follower_id and ub.blocked_id = new.following_id)
  ) then
    return new;
  end if;

  insert into public.notifications(recipient_id, actor_id, type)
  values (new.following_id, new.follower_id, 'new_follower');

  return new;
end;
$$;

create or replace function public.create_notification_on_like()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  post_author uuid;
begin
  select author_id into post_author
  from public.posts
  where id = new.post_id
    and is_removed = false;

  if post_author is not null
     and post_author <> new.user_id
     and not exists (
       select 1
       from public.user_blocks ub
       where (ub.blocker_id = post_author and ub.blocked_id = new.user_id)
          or (ub.blocker_id = new.user_id and ub.blocked_id = post_author)
     ) then
    insert into public.notifications(recipient_id, actor_id, post_id, type)
    values (post_author, new.user_id, new.post_id, 'post_like');
  end if;

  return new;
end;
$$;

create or replace function public.create_notification_on_comment()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  post_author uuid;
begin
  select author_id into post_author
  from public.posts
  where id = new.post_id
    and is_removed = false;

  if post_author is not null
     and post_author <> new.user_id
     and not exists (
       select 1
       from public.user_blocks ub
       where (ub.blocker_id = post_author and ub.blocked_id = new.user_id)
          or (ub.blocker_id = new.user_id and ub.blocked_id = post_author)
     ) then
    insert into public.notifications(recipient_id, actor_id, post_id, type)
    values (post_author, new.user_id, new.post_id, 'post_comment');
  end if;

  return new;
end;
$$;

create or replace function public.create_notification_on_community_post()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.community_id is null or new.is_removed then
    return new;
  end if;

  insert into public.notifications(recipient_id, actor_id, post_id, type)
  select cm.user_id, new.author_id, new.id, 'community_post'::public.notification_type
  from public.community_memberships cm
  where cm.community_id = new.community_id
    and cm.user_id <> new.author_id
    and not exists (
      select 1
      from public.user_blocks ub
      where (ub.blocker_id = cm.user_id and ub.blocked_id = new.author_id)
         or (ub.blocker_id = new.author_id and ub.blocked_id = cm.user_id)
    );

  return new;
end;
$$;

drop trigger if exists trg_community_post_notify on public.posts;
create trigger trg_community_post_notify
after insert on public.posts
for each row execute function public.create_notification_on_community_post();
