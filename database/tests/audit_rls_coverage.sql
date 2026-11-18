-- Live audit queries (read-only). Run in the Supabase SQL editor after every migration batch.
-- Expectation: sections 1, 3, 4 return 0 rows. Section 2 should contain only reviewed tables.

-- 1. Tables without RLS
select 'no_rls' as issue, c.relname from pg_class c join pg_namespace n on n.oid=c.relnamespace
 where n.nspname='public' and c.relkind='r' and not c.relrowsecurity;

-- 2. Tables anon can SELECT (RLS is the only guard) -- review each policy
select 'anon_select' as issue, table_name from information_schema.role_table_grants
 where table_schema='public' and grantee='anon' and privilege_type='SELECT' order by 2;

-- 3. Anon/PUBLIC-reachable SELECT policies that are unconditional
select 'open_policy' as issue, tablename, policyname from pg_policies
 where schemaname='public' and cmd in ('SELECT','ALL') and (roles && array['anon'::name,'public'::name])
   and trim(coalesce(qual,'')) in ('true','(true)');

-- 4. Any client write privilege on audit/legal tables
select 'client_write_on_sensitive' as issue, table_name, grantee, privilege_type from information_schema.role_table_grants
 where table_schema='public' and grantee in ('anon','authenticated') and privilege_type in ('INSERT','UPDATE','DELETE')
   and table_name in ('security_events','admin_audit_log','moderation_actions','legal_complaints','legal_data_requests',
                      'copyright_notices','copyright_counter_notices','media_scan_events','auth_login_attempts','repo_migrations');

-- 5. SECURITY DEFINER functions without a pinned search_path
select 'definer_no_search_path' as issue, p.proname from pg_proc p
 where p.pronamespace='public'::regnamespace and p.prosecdef and not coalesce(p.proconfig::text,'') ilike '%search_path%';

-- 6. Storage buckets without MIME allowlist or size limit
select 'bucket_unrestricted' as issue, id, public, file_size_limit, allowed_mime_types is null as any_mime from storage.buckets
 where file_size_limit is null or allowed_mime_types is null;
