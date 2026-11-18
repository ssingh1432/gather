# Gather — API Documentation

Gather has no custom REST server. The API is: (1) PostgREST tables under RLS, (2) Postgres RPC functions, (3) five Edge Functions, (4) Realtime channels. Table and RPC reference: **DATABASE.md §2–§3 and the Phase 12 section**.

## Auth
All calls use the Supabase JWT (`Authorization: Bearer <access_token>`) plus the anon `apikey`. Admin/moderator RPCs check role/permission inside the function and raise on failure. Step-up RPCs (`set_device_trust`, `revoke_device`) require AAL2 when 2FA is enrolled.

## Edge Functions
| Function | Method / trigger | Auth | Purpose |
|---|---|---|---|
| `auth-email` | Supabase Auth Send-Email hook | standardwebhooks signature (`SEND_EMAIL_HOOK_SECRET`) | Branded signup / recovery / email-change emails via Resend |
| `data-export` | `functions.invoke('data-export')` | user JWT | Builds the user's JSON export, stores in private `data-exports`, returns 7-day signed URL |
| `esewa-payment` | `GET /esewa-payment/init/<txn_id>` + verification callback | user JWT / server | Signs eSewa fields server-side; confirms payment |
| `link-preview` | invoke with `{url}` | user JWT | Open Graph metadata with SSRF guards; cached in `link_previews` |
| `notification-dispatch` | Database Webhook on `notifications` INSERT | shared secret header | FCM push + Resend email, best effort |

## Key RPC groups (see DATABASE.md for signatures)
- Feed/search: `get_home_feed`, `get_home_feed_cursor`, `get_community_feed`, `search_posts`
- Privacy: `request_data_export`, `request_account_deletion(reason, grace_days=14)`
- Safety/moderation: `resolve_report`, `add_strike`, `suspend_user`, `ban_user`, `submit_appeal`, `check_login_lockout`, `record_login_attempt`
- Devices/identity: `register_device`, `list_my_devices`, `is_device_trusted`, `set_device_trust`, `revoke_device`, `change_username`, `validate_username`, `admin_award_badge`, `admin_revoke_badge`
- Admin: `admin_overview_stats`, `admin_system_health`, `admin_storage_stats`, `admin_realtime_tables`, `admin_recent_login_failures`, `admin_send_broadcast`, `admin_moderator_activity`
- Analytics: `admin_platform_kpis`, `admin_activity_series`, `admin_retention_cohorts`, `admin_engagement_summary`, `admin_moderation_analytics`, `admin_uploads_series`, `admin_crash_analytics`, `admin_performance_analytics`, `admin_revenue_readiness`

## Errors
Postgres errors surface as PostgREST errors: `42501` permission/RLS, `P0001` app-raised (rate limit exceeded, mfa_required, invalid_device_id…), `23xxx` constraint. Clients should map `P0001` messages to friendly text.

## Versioning
Add optional params with defaults; never remove or change return shapes without a deprecation window (MIGRATION_GUIDE.md).
