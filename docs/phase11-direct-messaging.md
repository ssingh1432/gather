# Phase 11 – Direct Messaging

Migration: `database/migrations/124_phase11_direct_messaging.sql` (**apply manually; CI does not run migrations**).
Flutter: `flutter_app/lib/features/messages/`. Routes: `/messages` (inbox), `/dm-chat`.

## Features
1:1 DMs, typing indicator (Realtime Broadcast, not stored), delivered/read ticks (per-member cursors),
voice notes (<= 5 min), image/video/file sharing (private `dm-media` bucket, 25 MB, mime allowlist),
reactions, reply, forward, delete for me / for everyone, pin / archive / mute, clear chat,
"who can message me" (`users.dm_privacy`), block-aware, 30 msg/min rate limit.

## Security model
- Clients have SELECT only on `dm_*` tables; every write is a SECURITY DEFINER RPC that checks membership, blocks, privacy and rate limit.
- Text is end-to-end encrypted when both users have registered a key: X25519 ECDH -> HKDF-SHA256 (bound to conversation id) -> AES-256-GCM, conversation id as AAD. Private key stays in secure storage on the device.
- Server stores ciphertext, nonce, and public keys only.

## Known limits
- One key per account: a second device sees a "keys on another device" banner and must reset keys (old encrypted messages become unreadable).
- No forward secrecy (no ratchet); media files are protected by TLS + at-rest encryption, not E2EE.
- If the recipient has never opened Messages (no key), text is sent unencrypted; the chat header shows "Not end-to-end encrypted".
- Reporting an encrypted message needs client-side plaintext attachment (not yet built); DM push notifications not yet built.
