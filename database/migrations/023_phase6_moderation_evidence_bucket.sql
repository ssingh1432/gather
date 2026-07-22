-- Phase 6 UI-gap closeout (1/4): storage bucket for evidence attachments.
--
-- moderation_evidence rows (table + RLS + add_evidence RPC) already existed
-- from migration 022 — this was pure plumbing with no way to actually
-- upload a file. This adds the missing storage bucket the app now writes
-- to (see MediaUploadService.evidenceBucket in the Flutter app).
--
-- Unlike avatars/post-media/story-media, this bucket is PRIVATE: report
-- evidence can include screenshots of harassment, personal info, etc. and
-- must not be publicly readable. Objects are served via authenticated
-- Storage requests (not getPublicUrl()), gated by the same
-- "reporter or admin/mod" rule already enforced on the moderation_evidence
-- table itself.
--
-- Path convention: {reportId}/{uploaderId}_{timestamp}.{ext} — scoped by
-- report so a single report's evidence is easy to list, and the uploader
-- segment keeps a reporter and a mod's own uploads from colliding.

insert into storage.buckets (id, name, public, file_size_limit)
values ('moderation-evidence', 'moderation-evidence', false, 20 * 1024 * 1024) -- 20MB/file
on conflict (id) do nothing;

drop policy if exists "moderation_evidence_storage_select" on storage.objects;
create policy "moderation_evidence_storage_select" on storage.objects
for select using (
  bucket_id = 'moderation-evidence'
  and (
    public.is_admin_or_mod()
    or exists (
      select 1 from public.moderation_evidence e
      join public.reports r on r.id = e.report_id
      where e.file_url like '%' || storage.objects.name
        and r.reporter_id = auth.uid()
    )
  )
);

-- Insert is gated the same way the moderation_evidence row insert already
-- is (reporter on their own report, or any admin/mod) — this just lets the
-- matching storage object land alongside that row.
drop policy if exists "moderation_evidence_storage_insert" on storage.objects;
create policy "moderation_evidence_storage_insert" on storage.objects
for insert with check (
  bucket_id = 'moderation-evidence'
  and (
    public.is_admin_or_mod()
    or exists (
      select 1 from public.reports r
      where r.id::text = (storage.foldername(storage.objects.name))[1]
        and r.reporter_id = auth.uid()
    )
  )
);
