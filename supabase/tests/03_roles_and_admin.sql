-- Students cannot gain admin rights or perform content management. Admins can manage
-- content but cannot see students' personal data.

select tests.remember('student', tests.create_user('student'));
select tests.remember('admin', tests.create_user('admin'));
select tests.make_admin(tests.id('admin'));

-- A student records progress so we can check the admin cannot see it.
select tests.authenticate_as(tests.id('student'));
select public.set_lesson_progress(tests.id('req_vectors'), 'in_progress', 2, 'student notes', now());

-- Role escalation attempts ----------------------------------------------------
select tests.is((select count(*)::int from public.administrator_roles), 0, 'student sees no admin rows');
select tests.throws(
  format('insert into public.administrator_roles (user_id) values (%L)', tests.id('student')),
  'student cannot grant themselves the admin role', 'permission denied');
select tests.throws(
  format('update public.administrator_roles set user_id = %L', tests.id('student')),
  'student cannot rewrite admin rows', 'permission denied');
select tests.throws(
  format('select private.grant_admin(%L)', tests.id('student')),
  'student cannot call private.grant_admin', 'permission denied');
select tests.throws(
  format('insert into public.class_enrollments (user_id) values (%L)', tests.id('student')),
  'student cannot enroll themselves without the class code', 'permission denied');
select tests.throws(
  'update public.profiles set id = gen_random_uuid()',
  'student cannot change their profile id', 'permission denied');
select tests.ok(not private.is_admin(), 'is_admin() is false for a student');

-- Content management attempts -------------------------------------------------
select tests.throws(
  format('insert into public.lessons (course_id, title, category) values (%L, ''Fake'', ''required'')', tests.id('course_la')),
  'student cannot create lessons', 'row-level security');
select tests.is(
  tests.rows_affected(format('update public.lessons set status = ''published'' where id = %L', tests.id('draft'))),
  0::bigint, 'student cannot publish a draft (0 rows)');
select tests.is(
  tests.rows_affected(format('update public.lessons set title = ''Defaced'' where id = %L', tests.id('req_vectors'))),
  0::bigint, 'student cannot edit a published lesson');
select tests.is(
  tests.rows_affected(format('update public.lessons set category = ''optional'' where id = %L', tests.id('req_vectors'))),
  0::bigint, 'student cannot downgrade a required lesson to optional');
select tests.is(
  tests.rows_affected(format('delete from public.lessons where id = %L', tests.id('opt_planning'))),
  0::bigint, 'student cannot delete lessons');
select tests.throws(
  format('insert into public.lesson_attachments (id, lesson_id, title, storage_path, file_name, mime_type, byte_size) values (%L, %L, ''x'', %L, ''x.pdf'', ''application/pdf'', 10)',
    '11111111-1111-4111-8111-111111111111', tests.id('req_vectors'),
    tests.id('req_vectors')::text || '/11111111-1111-4111-8111-111111111111/v1.pdf'),
  'student cannot add attachments', 'row-level security');
select tests.throws(
  'insert into public.courses (slug, title) values (''fake-course'', ''Fake'')',
  'student cannot create courses', 'row-level security');
select tests.throws(
  'select public.set_class_join_code(''NEWCODE123'')',
  'student cannot set the class code', 'Administrator role required');
select tests.throws(
  format('insert into public.lessons (id, course_id, title, category) values (%L, %L, ''Defaced'', ''optional'') on conflict (id) do update set title = excluded.title, category = excluded.category',
    tests.id('req_vectors'), tests.id('course_la')),
  'student cannot overwrite a lesson through an upsert', 'row-level security');

reset role;
select tests.is((select title from public.lessons where id = tests.id('req_vectors')), 'Vectors and linear combinations',
  'the published lesson is unchanged after the student''s attempts');
select tests.is((select status::text from public.lessons where id = tests.id('draft')), 'draft',
  'the draft is still a draft after the student''s attempts');

-- Admin ----------------------------------------------------------------------
select tests.authenticate_as(tests.id('admin'));
select tests.ok(private.is_admin(), 'is_admin() is true for the administrator');
select tests.is((select count(*)::int from public.lessons where status = 'draft'), 1, 'admin can see drafts');

insert into public.lessons (id, course_id, title, category, exercise_count, created_by)
values ('22222222-2222-4222-8222-222222222222', tests.id('course_la'), 'Admin lesson', 'optional', 4,
        tests.id('student'));  -- forged author must be ignored
select tests.is((select created_by from public.lessons where id = '22222222-2222-4222-8222-222222222222'),
  tests.id('admin'), 'created_by is set from the JWT, not the payload');
select tests.is((select published_at from public.lessons where id = '22222222-2222-4222-8222-222222222222'),
  null::timestamptz, 'a new draft has no published_at');

update public.lessons set status = 'published' where id = '22222222-2222-4222-8222-222222222222';
select tests.ok((select published_at is not null from public.lessons where id = '22222222-2222-4222-8222-222222222222'),
  'publishing stamps published_at server-side');

select tests.is((select count(*)::int from public.lesson_progress), 0,
  'admin cannot read any student''s progress');
select tests.is((select count(*)::int from public.lesson_progress where notes <> ''), 0,
  'admin cannot read students'' private notes');
select tests.is((select count(*)::int from public.lesson_subscriptions), 0,
  'admin cannot read students'' subscriptions');
select tests.is((select count(*)::int from public.profiles), 1,
  'admin sees only their own profile');
select tests.throws('select private.grant_admin(gen_random_uuid())',
  'even an admin cannot grant roles from the app', 'permission denied');

-- "Publish to class" upserts lessons by id: the first call creates, later ones update in
-- place and keep the status and publication stamp.
insert into public.lessons (id, course_id, title, category, exercise_count)
values ('33333333-3333-4333-8333-333333333333', tests.id('course_la'), 'HW1', 'required', 9)
on conflict (id) do update set title = excluded.title, exercise_count = excluded.exercise_count;
update public.lessons set status = 'published' where id = '33333333-3333-4333-8333-333333333333';
insert into public.lessons (id, course_id, title, category, exercise_count)
values ('33333333-3333-4333-8333-333333333333', tests.id('course_la'), 'HW1 (revised)', 'required', 10)
on conflict (id) do update set title = excluded.title, exercise_count = excluded.exercise_count;
select tests.is((select count(*)::int from public.lessons where id = '33333333-3333-4333-8333-333333333333'), 1,
  'publishing the same homework twice keeps one lesson');
select tests.is((select title || '/' || exercise_count || '/' || status from public.lessons where id = '33333333-3333-4333-8333-333333333333'),
  'HW1 (revised)/10/published', 'a re-publish updates the lesson and keeps it published');

-- An admin cannot hard-delete a lesson a student has worked on.
select tests.throws(format('delete from public.lessons where id = %L', tests.id('req_vectors')),
  'a lesson with student progress cannot be deleted (archive it instead)', 'foreign key');
