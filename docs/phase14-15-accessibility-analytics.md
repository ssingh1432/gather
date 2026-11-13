# Phase 14 (Accessibility & localization) and Phase 15 (Platform analytics)

## Phase 14
- **Localization**: `lib/core/l10n/app_l10n.dart` (English + Nepali, falls back to English per key). Add a language by adding a map in `AppL10n.strings` and its code in `supportedLocales`/`languageNames`; `test/core/app_l10n_test.dart` enforces key and placeholder parity. Material/Cupertino widgets use Flutter's built-in `ne` localizations.
- **Preferences** (`Settings > Accessibility & language`, route `/settings/accessibility`): language, appearance (light default / dark / device), text size 85-200% (multiplies the OS scale), high contrast (AAA palettes), bold text, reduce motion. Stored with SharedPreferences; language mirrored to `users.language_preference`.
- **Screen reader / keyboard**: labelled post actions, profile links, poll options, sensitive-content gate, audio player; 40dp tap targets; reading-order focus traversal; action bar reflows at large text; "See more" measured with the active text scaler.
- Coverage is incremental: shell navigation, post card, settings entry and the accessibility screen are localized. Other screens still show English and should migrate to `AppL10n` over time.

## Phase 15
Migration `125_phase15_platform_analytics.sql` adds admin/moderator-only RPCs: `admin_platform_kpis`, `admin_activity_series`, `admin_retention_cohorts`, `admin_engagement_summary`, `admin_moderation_analytics`, `admin_uploads_series`, `admin_crash_analytics`. DAU = one `daily_active_user` event per user per UTC day; MAU is distinct users over 30 days; day-N retention counts users active exactly N days after signup (only eligible users counted). UI: Admin > Analytics (`platform_analytics_tab.dart`), with a text alternative for every chart. The client now stamps DAU on login and app resume.

Not yet covered: revenue readiness and performance (web-vitals/latency) dashboards.

## Migrations in CI
`scripts/apply_migrations.py` applies files not recorded in `public.repo_migrations` (one request per file, rolled back on failure) before deploy. Requires the `SUPABASE_ACCESS_TOKEN` repo secret; without it CI warns and continues. Never edit an applied migration; add a new one.
