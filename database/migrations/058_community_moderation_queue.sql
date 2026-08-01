-- 058_community_moderation_queue.sql
-- Community System: the community-scoped moderation queue flagged as
-- missing since Step 1.
--
-- Today, reports_select_self_or_admin only lets the reporter themselves
-- or a SITE-WIDE admin/mod (is_admin_or_mod()) see a report — a community
-- moderator, who might have real manage_reports authority over their own
-- community, currently cannot see reports on posts in that community at
-- all, let alone act on them. resolve_report()/soft_remove_post() are
-- similarly gated to ensure_admin_or_mod() only.
--
-- This migration does NOT touch the existing site-wide functions/policies
-- — it adds a parallel, narrower path: a community moderator can view and
-- act on reports, but ONLY when the report targets a post that belongs to
-- a community where they hold manage_reports (for viewing/resolving/
-- dismissing) or manage_posts (for removing the post). Reports with no
-- post (target_type = 'user', no community association) are out of scope
-- for this queue by design — those still only go through the site-wide
-- queue, since there's no community to scope them to.

-- 0. Give report/post-removal actions their own audit action names rather
-- than overloading unrelated ones (e.g. reusing 'member_removed' for a
-- post removal would be misleading in the audit trail).
alter table public.community_audit_logs drop constraint if exists community_audit_logs_action_check;
alter table public.community_audit_logs add constraint community_audit_logs_action_check
  check (action in (
    'role_changed', 'member_removed', 'member_banned', 'member_unbanned',
    'member_warned', 'permission_overridden', 'settings_changed',
    'member_invited', 'invite_link_created', 'invite_revoked', 'invite_accepted',
    'report_resolved', 'report_dismissed', 'post_removed'
  ));

-- 1. Let community moderators SEE reports on their community's posts -------
drop policy if exists reports_select_self_or_admin on public.reports;
create policy reports_select_self_or_admin on public.reports for select using (
  reporter_id = auth.uid()
  or is_admin_or_mod()
  or (
    target_post_id is not null
    and exists (
      select 1 from public.posts p
      where p.id = reports.target_post_id
        and p.community_id is not null
        and current_user_community_permission(p.community_id, 'manage_reports')
    )
  )
);

-- 2. The queue itself --------------------------------------------------------
create or replace function public.get_community_report_queue(p_community_id uuid, p_status text default 'open')
returns table (
  id uuid,
  reporter_username text,
  target_type text,
  target_post_id uuid,
  post_preview text,
  reason text,
  category public.report_category,
  status public.report_status,
  is_automated boolean,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = 'public'
as $$
begin
  if not current_user_community_permission(p_community_id, 'manage_reports') then
    raise exception 'Not authorized to view this community''s report queue';
  end if;

  return query
  select
    r.id, u.username, r.target_type::text, r.target_post_id,
    left(coalesce(p.text_content, ''), 200), r.reason, r.category, r.status, r.is_automated, r.created_at
  from public.reports r
  join public.posts p on p.id = r.target_post_id
  left join public.users u on u.id = r.reporter_id
  where p.community_id = p_community_id
    and (p_status is null or r.status::text = p_status)
  order by r.created_at desc;
end;
$$;

grant execute on function public.get_community_report_queue(uuid, text) to authenticated;

-- 3. Resolve / dismiss (community-scoped) ------------------------------------
create or replace function public.resolve_community_report(p_report_id uuid, p_note text default null)
returns void
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_community_id uuid;
begin
  select p.community_id into v_community_id
  from public.reports r join public.posts p on p.id = r.target_post_id
  where r.id = p_report_id;

  if v_community_id is null or not current_user_community_permission(v_community_id, 'manage_reports') then
    raise exception 'Not authorized to resolve this report';
  end if;

  update public.reports set status = 'resolved', reviewed_by = auth.uid() where id = p_report_id;

  insert into public.moderation_actions(action, admin_id, report_id, note)
  values ('report_resolved', auth.uid(), p_report_id, p_note);

  perform log_community_audit(v_community_id, 'report_resolved', null, jsonb_build_object('report_id', p_report_id));
end;
$$;

grant execute on function public.resolve_community_report(uuid, text) to authenticated;

create or replace function public.dismiss_community_report(p_report_id uuid, p_note text default null)
returns void
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_community_id uuid;
begin
  select p.community_id into v_community_id
  from public.reports r join public.posts p on p.id = r.target_post_id
  where r.id = p_report_id;

  if v_community_id is null or not current_user_community_permission(v_community_id, 'manage_reports') then
    raise exception 'Not authorized to dismiss this report';
  end if;

  update public.reports set status = 'dismissed', reviewed_by = auth.uid() where id = p_report_id;

  insert into public.moderation_actions(action, admin_id, report_id, note)
  values ('report_dismissed', auth.uid(), p_report_id, p_note);

  perform log_community_audit(v_community_id, 'report_dismissed', null, jsonb_build_object('report_id', p_report_id));
end;
$$;

grant execute on function public.dismiss_community_report(uuid, text) to authenticated;

-- 4. Remove the reported post + resolve, in one action -----------------------
-- Distinct permission from resolve/dismiss (manage_posts, not
-- manage_reports) since it's a content action, not just a triage action —
-- a community could grant these to different roles.
create or replace function public.remove_post_via_community_report(p_report_id uuid, p_note text default null)
returns void
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_community_id uuid;
  v_post_id uuid;
begin
  select p.community_id, p.id into v_community_id, v_post_id
  from public.reports r join public.posts p on p.id = r.target_post_id
  where r.id = p_report_id;

  if v_community_id is null or not current_user_community_permission(v_community_id, 'manage_posts') then
    raise exception 'Not authorized to remove posts in this community';
  end if;

  update public.posts set is_removed = true where id = v_post_id;
  update public.reports set status = 'resolved', reviewed_by = auth.uid() where id = p_report_id;

  insert into public.moderation_actions(action, admin_id, report_id, post_id, note)
  values ('post_soft_removed', auth.uid(), p_report_id, v_post_id, p_note);

  perform log_community_audit(v_community_id, 'post_removed', null, jsonb_build_object('post_id', v_post_id, 'via_report', p_report_id, 'reason', p_note));
end;
$$;

grant execute on function public.remove_post_via_community_report(uuid, text) to authenticated;
