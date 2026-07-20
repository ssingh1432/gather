-- Must run in its own transaction/migration: new enum values cannot be
-- referenced in the same transaction that adds them (see 015 which sets
-- users.status = 'pending_deletion').
alter type public.user_status add value if not exists 'pending_deletion';
