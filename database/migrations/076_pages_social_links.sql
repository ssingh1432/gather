-- 076_pages_social_links.sql
-- Professional Page System — Step 6 (Professional Page Profile).
--
-- Adds the one small schema piece Step 6 needs that didn't already exist:
-- a `social_links` column on `pages`, storing a jsonb map of
-- platform -> url (e.g. {"facebook": "...", "instagram": "..."}).
--
-- Per the brief, Social Links are explicitly "future-ready" for Step 6 —
-- there's no dedicated editor UI yet (that lands whenever Page editing is
-- built), but the Profile screen already renders whatever is present here,
-- and the column exists now so no further schema change is needed to
-- light the feature up later. Mirrors the existing `business_hours` jsonb
-- column's pattern on the same table.
--
-- Purely additive: default '{}'::jsonb means every existing page is
-- unaffected, and it's covered by the same `pages_select` / `pages_update`
-- RLS policies (migration 072) as every other page column already.

alter table public.pages
  add column if not exists social_links jsonb not null default '{}'::jsonb;

comment on column public.pages.social_links is
  'Future-ready (Step 6): platform -> url map, e.g. {"facebook": "https://...", "instagram": "https://..."}. No dedicated editor yet; Page Profile renders whatever is present.';
