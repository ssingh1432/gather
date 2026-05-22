# Gather MVP (Community-First Social App)

This repository contains a production-ready MVP blueprint for a **community/interest-based social app** designed to evolve into a short-video platform later.

## Stack
- **Frontend:** Flutter
- **Backend:** Supabase (Auth, Postgres, Storage, Edge Functions)
- **Database:** PostgreSQL
- **Push:** Firebase Cloud Messaging
- **Analytics:** PostHog or Firebase Analytics

## What is included
- Project folder structure for Flutter + backend docs
- Database schema SQL and initial migration
- Supabase Row Level Security (RLS) policies
- Auth/session design
- Feed/community/social/notification/moderation logic
- Admin controls for bans and post removal
- Testing checklist
- Deployment guide
- Business plan and phased monetization roadmap

## Repository structure
- `database/migrations/001_initial_schema.sql` — full schema, indexes, triggers, RLS policies.
- `docs/ARCHITECTURE.md` — clean architecture + future video extensibility.
- `docs/FEATURE_LOGIC.md` — feature-by-feature implementation logic.
- `docs/DEPLOYMENT.md` — Supabase + Flutter deployment guide.
- `docs/TESTING_CHECKLIST.md` — QA + automated testing checklist.
- `BUSINESS_PLAN.md` — phased business and product roadmap.
- `flutter_app/` — Flutter app scaffold and screen/module map.

## Quick start
1. Create a Supabase project.
2. Run SQL from `database/migrations/001_initial_schema.sql`.
3. Configure Flutter env variables for Supabase URL and anon key.
4. Implement screens and repositories following `docs/ARCHITECTURE.md` and `docs/FEATURE_LOGIC.md`.
5. Run tests from `docs/TESTING_CHECKLIST.md`.

## MVP scope guardrails
Version 1 intentionally excludes:
- TikTok-style autoplay video feed
- Livestreaming
- Advanced recommendation ML systems
- Complex monetization

## Future-ready note
Schema and module boundaries include media abstractions (`post_media`, storage buckets, and feature modules) so short-video support can be added without rewriting core feed/community/social systems.
