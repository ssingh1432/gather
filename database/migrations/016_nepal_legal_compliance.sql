-- Phase 4: Nepal Legal Compliance
-- Grievance/complaint system, content-removal workflow, user appeals,
-- law-enforcement/legal data requests, and identity verification support.
-- Legal frameworks are stored as data (not hardcoded enums) so future
-- laws (e.g. an eventual Social Media Bill) can be added with an insert,
-- not a migration.

create table if not exists public.legal_frameworks (
  code text primary key,           -- e.g. 'ETA_2063', 'PRIVACY_ACT_2075', 'SOCIAL_MEDIA_DIRECTIVE'
  name text not null,
  description text,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

insert into public.legal_frameworks (code, name, description) values
  ('ETA_2063', 'Electronic Transactions Act, 2063', 'Governs electronic records, digital signatures, and cyber offences in Nepal.'),
  ('PRIVACY_ACT_2075', 'Privacy Act, 2075', 'Governs collection, use, and protection of personal data in Nepal.'),
  ('SOCIAL_MEDIA_DIRECTIVE', 'Social Media Usage Directive', 'MOCIT directive on registration, grievance handling, and content takedown for social media platforms operating in Nepal.'),
  ('OTHER', 'Other / Future Legal Basis', 'Placeholder for legal bases not yet formally catalogued.')
on conflict (code) do nothing;

alter table public.legal_frameworks enable row level security;
revoke all on public.legal_frameworks from anon, authenticated;
grant select on public.legal_frameworks to authenticated, anon;
create policy "Legal frameworks are publicly readable"
  on public.legal_frameworks for select
  to authenticated, anon
  using (true);

-- Grievances / legal complaints — distinct from the lightweight
-- `reports` table (which is peer-to-peer "report this post/user").
-- This is the formal channel: illegal content, privacy violations,
-- defamation, government/law-enforcement-facing complaints, each
-- trackable against a specific legal basis and assignable to an admin.
create table if not exists public.legal_complaints (
  id uuid primary key default gen_random_uuid(),
  complainant_id uuid references public.users(id) on delete set null,
  complainant_contact text,
  complaint_type text not null,
  legal_basis_code text references public.legal_frameworks(code),
  target_post_id uuid references public.posts(id) on delete set null,
  target_user_id uuid references public.users(id) on delete set null,
  description text not null,
  evidence_urls text[] not null default '{}',
  status text not null default 'submitted',
  assigned_admin_id uuid references public.users(id) on delete set null,
  resolution_notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  resolved_at timestamptz
);

create index if not exists idx_legal_complaints_status on public.legal_complaints (status, created_at desc);
create index if not exists idx_legal_complaints_complainant on public.legal_complaints (complainant_id);

alter table public.legal_complaints enable row level security;
revoke all on public.legal_complaints from anon, authenticated;
grant select, insert, update, delete on public.legal_complaints to authenticated;

create policy "Users read their own complaints"
  on public.legal_complaints for select
  to authenticated
  using (complainant_id = auth.uid());

create policy "Users file complaints"
  on public.legal_complaints for insert
  to authenticated
  with check (complainant_id = auth.uid());

create policy "Admins manage all complaints"
  on public.legal_complaints for all
  to authenticated
  using (public.is_admin_or_mod())
  with check (public.is_admin_or_mod());

-- Content removal actions
create table if not exists public.content_removal_actions (
  id bigint generated always as identity primary key,
  complaint_id uuid references public.legal_complaints(id) on delete set null,
  post_id uuid references public.posts(id) on delete set null,
  removed_by uuid not null references public.users(id) on delete restrict,
  legal_basis_code text references public.legal_frameworks(code),
  reason text not null,
  removed_at timestamptz not null default now(),
  restored_at timestamptz,
  restored_by uuid references public.users(id) on delete set null
);

alter table public.content_removal_actions enable row level security;
revoke all on public.content_removal_actions from anon, authenticated;
grant select, insert, update, delete on public.content_removal_actions to authenticated;
create policy "Admins manage content removal actions"
  on public.content_removal_actions for all
  to authenticated
  using (public.is_admin_or_mod())
  with check (public.is_admin_or_mod());

-- User appeals
create table if not exists public.user_appeals (
  id uuid primary key default gen_random_uuid(),
  appellant_id uuid not null references public.users(id) on delete cascade,
  moderation_action_id uuid references public.moderation_actions(id) on delete set null,
  content_removal_action_id bigint references public.content_removal_actions(id) on delete set null,
  legal_complaint_id uuid references public.legal_complaints(id) on delete set null,
  statement text not null,
  status text not null default 'submitted',
  reviewed_by uuid references public.users(id) on delete set null,
  review_notes text,
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  constraint user_appeals_has_target check (
    moderation_action_id is not null or content_removal_action_id is not null or legal_complaint_id is not null
  )
);

create index if not exists idx_user_appeals_appellant on public.user_appeals (appellant_id, created_at desc);

alter table public.user_appeals enable row level security;
revoke all on public.user_appeals from anon, authenticated;
grant select, insert, update, delete on public.user_appeals to authenticated;

create policy "Users read their own appeals"
  on public.user_appeals for select
  to authenticated
  using (appellant_id = auth.uid());

create policy "Users file appeals"
  on public.user_appeals for insert
  to authenticated
  with check (appellant_id = auth.uid());

create policy "Admins manage all appeals"
  on public.user_appeals for all
  to authenticated
  using (public.is_admin_or_mod())
  with check (public.is_admin_or_mod());

-- Legal / government data requests
create table if not exists public.legal_data_requests (
  id uuid primary key default gen_random_uuid(),
  requesting_authority text not null,
  authority_contact text,
  legal_basis_code text references public.legal_frameworks(code),
  reference_number text,
  target_user_id uuid references public.users(id) on delete set null,
  request_details text not null,
  status text not null default 'received',
  handled_by uuid references public.users(id) on delete set null,
  response_notes text,
  received_at timestamptz not null default now(),
  responded_at timestamptz
);

alter table public.legal_data_requests enable row level security;
revoke all on public.legal_data_requests from anon, authenticated;
grant select, insert, update, delete on public.legal_data_requests to authenticated;
create policy "Admins manage legal data requests"
  on public.legal_data_requests for all
  to authenticated
  using (public.is_admin_or_mod())
  with check (public.is_admin_or_mod());

-- User identity verification requests
create table if not exists public.user_verification_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users(id) on delete cascade,
  id_document_type text,
  id_document_url text,
  status text not null default 'pending',
  reviewed_by uuid references public.users(id) on delete set null,
  review_notes text,
  submitted_at timestamptz not null default now(),
  reviewed_at timestamptz
);

create index if not exists idx_user_verification_requests_user on public.user_verification_requests (user_id, submitted_at desc);

alter table public.user_verification_requests enable row level security;
revoke all on public.user_verification_requests from anon, authenticated;
grant select, insert, update, delete on public.user_verification_requests to authenticated;

create policy "Users read their own verification requests"
  on public.user_verification_requests for select
  to authenticated
  using (user_id = auth.uid());

create policy "Users submit verification requests"
  on public.user_verification_requests for insert
  to authenticated
  with check (user_id = auth.uid());

create policy "Admins manage all verification requests"
  on public.user_verification_requests for all
  to authenticated
  using (public.is_admin_or_mod())
  with check (public.is_admin_or_mod());

-- updated_at trigger for legal_complaints
create or replace function public.touch_legal_complaint_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists trg_legal_complaints_updated_at on public.legal_complaints;
create trigger trg_legal_complaints_updated_at
  before update on public.legal_complaints
  for each row execute function public.touch_legal_complaint_updated_at();

notify pgrst, 'reload schema';
