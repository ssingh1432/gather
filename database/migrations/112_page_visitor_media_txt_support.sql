-- Page-only visitor media: keep file support aligned with the Page rich-media
-- composer by allowing plain-text documents in the existing visitor bucket.
update storage.buckets
set allowed_mime_types = array[
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
where id = 'page-visitor-media';
