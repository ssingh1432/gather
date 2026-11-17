-- Regenerates database/baseline/base_tables_snapshot.sql. Run in the Supabase SQL editor
-- (read-only) and save the single `ddl` value. REVIEW THE OUTPUT FOR SECRETS before committing:
-- Database Webhook triggers (supabase_functions.http_request) embed a service-role JWT and
-- shared secret in their definition and must be removed.
-- The table list = tables that exist live but are never created by database/migrations/*.sql.
with t(name) as (values ('allowed_beta_emails'),('app_config'),('bookmarks'),('close_friends'),('communities'),('community_memberships'),('creator_ad_impressions'),('link_previews'),('notifications'),('post_comments'),('post_downloads'),('post_likes'),('post_media'),('posts'),('reports'),('stories'),('story_audio_tracks'),('story_views'),('user_blocks'),('user_follows'),('user_payout_preferences'),('users')),
cls as (select c.oid, c.relname, c.relrowsecurity from pg_class c join t on t.name=c.relname where c.relnamespace='public'::regnamespace),
cols as (select cls.relname, string_agg(format('  %I %s%s%s', a.attname, format_type(a.atttypid,a.atttypmod), case when a.attnotnull then ' not null' else '' end, case when d.adbin is not null then ' default '||pg_get_expr(d.adbin,d.adrelid) else '' end), E',\n' order by a.attnum) body
  from cls join pg_attribute a on a.attrelid=cls.oid and a.attnum>0 and not a.attisdropped left join pg_attrdef d on d.adrelid=a.attrelid and d.adnum=a.attnum group by cls.relname),
enums as (select 0 ord, ''::name relname, format('do $$ begin if not exists (select 1 from pg_type where typname=%L and typnamespace=''public''::regnamespace) then create type public.%I as enum (%s); end if; end $$;', t.typname, t.typname, (select string_agg(quote_literal(e.enumlabel), ', ' order by e.enumsortorder) from pg_enum e where e.enumtypid=t.oid)) s from pg_type t where t.typnamespace='public'::regnamespace and t.typtype='e'),
parts as (
 select * from enums
 union all select 1, relname, format(E'create table if not exists public.%I (\n%s\n);', relname, body) from cols
 union all select 2, cls.relname, format('alter table public.%I add constraint %I %s;', cls.relname, con.conname, pg_get_constraintdef(con.oid)) from cls join pg_constraint con on con.conrelid=cls.oid where con.contype in ('p','u','c')
 union all select 3, cls.relname, format('alter table public.%I add constraint %I %s;', cls.relname, con.conname, pg_get_constraintdef(con.oid)) from cls join pg_constraint con on con.conrelid=cls.oid where con.contype='f'
 union all select 4, cls.relname, pg_get_indexdef(ix.indexrelid)||';' from cls join pg_index ix on ix.indrelid=cls.oid where not exists (select 1 from pg_constraint c2 where c2.conindid=ix.indexrelid)
 union all select 5, cls.relname, format('alter table public.%I enable row level security;', cls.relname) from cls where cls.relrowsecurity
 union all select 6, pol.tablename, format('create policy %I on public.%I as %s for %s to %s%s%s;', pol.policyname, pol.tablename, pol.permissive, pol.cmd, array_to_string(pol.roles,', '), case when pol.qual is not null then E'\n  using ('||pol.qual||')' else '' end, case when pol.with_check is not null then E'\n  with check ('||pol.with_check||')' else '' end) from pg_policies pol join t on t.name=pol.tablename where pol.schemaname='public'
 union all select 7, cls.relname, pg_get_triggerdef(tg.oid)||';' from cls join pg_trigger tg on tg.tgrelid=cls.oid where not tg.tgisinternal
 union all select 8, g.table_name, format('grant %s on public.%I to %s;', string_agg(distinct g.privilege_type, ', '), g.table_name, g.grantee) from information_schema.role_table_grants g join t on t.name=g.table_name where g.table_schema='public' and g.grantee in ('anon','authenticated','service_role') group by g.table_name, g.grantee)
select string_agg(s, E'\n' order by ord, relname) as ddl from parts;
