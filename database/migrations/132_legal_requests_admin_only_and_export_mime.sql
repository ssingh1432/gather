-- 132: least privilege for legal/police data requests + MIME allowlist for data exports.
--
-- The policy was named "Admins manage legal data requests" but used is_admin_or_mod(), so
-- every moderator could read and edit legal/police data requests. Restrict to admins.
-- Complaints (legal_complaints) stay open to moderators.
-- data-export writes only application/json; lock the private bucket to that.
alter policy "Admins manage legal data requests" on public.legal_data_requests
  using (public.is_admin())
  with check (public.is_admin());

update storage.buckets set allowed_mime_types = array['application/json']
 where id = 'data-exports' and allowed_mime_types is null;
