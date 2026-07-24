-- Phase 10 Step 4: Media upload system extension (audio + documents)
-- Extends the existing media_type enum and post-media storage bucket
-- rather than introducing a parallel table, so all existing feed/media
-- rendering code that queries post_media keeps working unchanged.

alter type public.media_type add value if not exists 'audio';
alter type public.media_type add value if not exists 'document';

update storage.buckets
set allowed_mime_types = array[
  'image/jpeg','image/png','image/webp','image/gif',
  'video/mp4','video/quicktime','video/webm','video/x-matroska',
  'audio/mpeg','audio/mp4','audio/aac','audio/wav',
  'application/pdf','application/msword',
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
]
where id = 'post-media';

