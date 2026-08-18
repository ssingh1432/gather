-- Page-only rich post media storage configuration.
-- Existing Page media RLS remains authoritative: uploads/updates/deletes are
-- restricted by can_manage_page_media() using the first path segment.
update storage.buckets
set file_size_limit = 26214400,
    allowed_mime_types = array[
      'image/jpeg',
      'image/png',
      'image/webp',
      'image/gif',
      'video/mp4',
      'video/quicktime',
      'video/webm',
      'application/pdf',
      'application/msword',
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'text/plain'
    ]
where id = 'page-media';
