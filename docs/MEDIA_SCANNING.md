# Media scanning hook (migration 131)

`post_media.scan_status` is `pending | clean | flagged` (default `clean`, so uploads are not blocked yet).
**No scanner is connected.** This migration provides the integration point and the quarantine/review workflow.

## Worker contract
A trusted worker (Edge Function or external service) using the **service role** calls:
`select public.set_media_scan_result(media_id, 'scanner-name', 'clean' | 'flagged' | 'error', 'detail')`.
- `flagged` → media marked flagged, the post is set `is_removed = true` (quarantine), an open event is created for staff.
- Only the service role can call it (anon and signed-in users are blocked; tested).

## Staff review
`admin_review_media_scan(event_id, confirmed, notes)` — `confirmed = true` keeps the removal; `false` (false positive) marks media clean and restores only posts that this event quarantined.
Staff view open events in `media_scan_events` (`review_status = 'open' and result = 'flagged'`).

## To go live
1. Choose a scanner: ClamAV (malware) for files; for child-safety imagery use a hash-matching service (e.g. PhotoDNA-class or an approved regional/NGO program) — requires an agreement, do not self-build.
2. Trigger on storage upload / `post_media` insert (Database Webhook → worker).
3. Flip new media to `pending` and hide pending media from non-owners **only after** the worker is proven reliable.
4. Child-abuse material: preserve evidence, do not view more than needed, report to the competent authority (e.g. Nepal Police Cyber Bureau — confirm the current channel with counsel) and follow the retention rules counsel gives you.
