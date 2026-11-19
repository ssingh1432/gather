-- 133: fixes from the Supabase performance advisor (2026-11-18). Behaviour-neutral.
--
-- 1. auth_rls_initplan (159 policies): `auth.uid()` / `auth.role()` / `auth.jwt()` called directly in a
--    policy is re-evaluated for every row. Wrapping it as `(select auth.uid())` makes Postgres
--    evaluate it once per statement (InitPlan). Semantics are identical; only the plan changes.
--    Policies are rewritten from their own deparsed text (the same round trip pg_dump relies on).
-- 2. unindexed_foreign_keys (137): every FK without a covering index gets one. Needed for fast joins
--    and, importantly, for cascading deletes (account deletion purge cascades across many tables).
-- 3. duplicate_index: constraint page_reviews_one_per_user duplicates the unique constraint
--    page_reviews_page_id_user_id_key (same columns). Dropping the former keeps `on conflict (page_id, user_id)` working.
-- Not changed on purpose: 77 "unused" indexes (traffic is too low for usage stats to mean anything;
-- revisit with real load) and 119 overlapping permissive policies (merging risks changing access).

do $$
declare
  r record; q text; w text; stmt text; n int := 0;
begin
  for r in select schemaname, tablename, policyname, qual, with_check from pg_policies where schemaname = 'public' loop
    q := regexp_replace(coalesce(r.qual, ''),       '(?<!select )auth\.(uid|role|jwt)\(\)', '(select auth.\1())', 'gi');
    w := regexp_replace(coalesce(r.with_check, ''), '(?<!select )auth\.(uid|role|jwt)\(\)', '(select auth.\1())', 'gi');
    if q is distinct from coalesce(r.qual, '') or w is distinct from coalesce(r.with_check, '') then
      stmt := format('alter policy %I on %I.%I', r.policyname, r.schemaname, r.tablename);
      if r.qual is not null then stmt := stmt || format(' using (%s)', q); end if;
      if r.with_check is not null then stmt := stmt || format(' with check (%s)', w); end if;
      execute stmt;
      n := n + 1;
    end if;
  end loop;
  raise notice 'rewrote % policies', n;
end $$;

do $$
declare r record; cols text; idx text; n int := 0;
begin
  for r in
    select c.conrelid, c.conname, c.conkey, cl.relname
      from pg_constraint c join pg_class cl on cl.oid = c.conrelid
     where c.contype = 'f' and c.connamespace = 'public'::regnamespace
       and not exists (
         select 1 from pg_index i
          where i.indrelid = c.conrelid
            and (i.indkey::int2[])[0:cardinality(c.conkey) - 1] = c.conkey)
  loop
    select string_agg(quote_ident(a.attname), ', ' order by k.ord) into cols
      from unnest(r.conkey) with ordinality k(attnum, ord)
      join pg_attribute a on a.attrelid = r.conrelid and a.attnum = k.attnum;
    idx := left('idx_' || r.relname || '_' || regexp_replace(replace(cols, ', ', '_'), '"', '', 'g'), 53) || '_' || substr(md5(r.conname), 1, 8);
    execute format('create index if not exists %I on public.%I (%s)', idx, r.relname, cols);
    n := n + 1;
  end loop;
  raise notice 'created % fk indexes', n;
end $$;

alter table public.page_reviews drop constraint if exists page_reviews_one_per_user;
