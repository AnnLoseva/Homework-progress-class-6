-- Structural guarantees: RLS everywhere, no anonymous writes, private buckets,
-- no privileged function callable by clients.

select tests.is(
  (select count(*)::int from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity),
  0, 'every table in public has row level security enabled');

select tests.is(
  (select count(*)::int from information_schema.role_table_grants
    where table_schema = 'public' and grantee = 'anon' and privilege_type <> 'SELECT'),
  0, 'anon has no INSERT/UPDATE/DELETE privilege on any public table');

select tests.is(
  (select count(*)::int from information_schema.role_table_grants
    where table_schema = 'public' and grantee = 'anon'
      and table_name in ('profiles', 'lesson_progress', 'lesson_subscriptions',
                         'class_enrollments', 'administrator_roles', 'my_workload')),
  0, 'anon has no privilege at all on personal tables');

select tests.is(
  (select count(*)::int from information_schema.role_table_grants
    where table_schema = 'public' and grantee = 'authenticated' and privilege_type = 'DELETE'
      and table_name in ('lesson_progress', 'lesson_subscriptions', 'profiles')),
  0, 'students cannot delete progress, subscriptions or profiles directly');

select tests.is(
  (select count(*)::int from storage.buckets where id in ('lesson-materials', 'student-private') and not public),
  2, 'both storage buckets exist and are private');

select tests.is(
  (select allowed_mime_types from storage.buckets where id = 'lesson-materials'),
  array['application/pdf'], 'lesson-materials accepts PDFs only');

select tests.is(
  (select file_size_limit from storage.buckets where id = 'lesson-materials'),
  52428800::bigint, 'lesson-materials has a 50 MB file size limit');

select tests.ok(
  not has_function_privilege('authenticated', 'private.grant_admin(uuid, text)', 'execute')
  and not has_function_privilege('anon', 'private.grant_admin(uuid, text)', 'execute'),
  'clients cannot execute private.grant_admin');

select tests.ok(
  not has_function_privilege('authenticated', 'private.revoke_admin(uuid)', 'execute'),
  'clients cannot execute private.revoke_admin');

select tests.ok(
  not has_function_privilege('anon', 'public.set_lesson_progress(uuid, public.progress_status, integer, text, timestamptz)', 'execute'),
  'anon cannot call set_lesson_progress');

select tests.ok(
  not has_table_privilege('authenticated', 'private.class_settings', 'select'),
  'the class code hash is not readable by clients');

select tests.ok(
  (select bool_and(prosecdef = false) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname in ('set_lesson_progress', 'set_lesson_subscription', 'export_my_data')),
  'student RPCs run as SECURITY INVOKER (under the caller''s RLS)');

select tests.ok(
  (select bool_and(coalesce(array_to_string(proconfig, ',') like '%search_path=%', false))
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('public', 'private') and p.prosecdef),
  'every SECURITY DEFINER function pins search_path');

select tests.ok(
  (select count(*) from public.lessons where status = 'published') > 0,
  'seed data loaded');
