-- Draft lessons never reach the student catalog; published and archived ones do according
-- to their policy; scheduled lessons appear only once available.

select tests.remember('student', tests.create_user('student'));
select tests.remember('admin', tests.create_user('admin'));
select tests.make_admin(tests.id('admin'));

-- Admin prepares: a draft with an attachment, and a scheduled published lesson.
select tests.authenticate_as(tests.id('admin'));
insert into public.lesson_attachments (id, lesson_id, title, visibility, storage_path, file_name, mime_type, byte_size)
values ('33333333-3333-4333-8333-333333333333', tests.id('draft'), 'Draft sheet', 'public',
        tests.id('draft')::text || '/33333333-3333-4333-8333-333333333333/v1.pdf', 'draft.pdf', 'application/pdf', 1024);
insert into public.lessons (id, course_id, title, category, status, available_from)
values ('44444444-4444-4444-8444-444444444444', tests.id('course_la'), 'Scheduled lesson', 'required', 'published',
        now() + interval '2 days');
insert into public.lesson_prerequisites (lesson_id, prerequisite_id)
values (tests.id('draft'), tests.id('req_vectors'));

-- Visitors -------------------------------------------------------------------
select tests.as_anon();
select tests.is((select count(*)::int from public.lessons where status = 'draft'), 0, 'anon: drafts are hidden');
select tests.is((select count(*)::int from public.lessons where id = tests.id('draft')), 0, 'anon: the draft cannot be fetched by id');
select tests.is((select count(*)::int from public.lessons where id = tests.id('req_vectors')), 1, 'anon: published lessons are visible');
select tests.is((select count(*)::int from public.lesson_attachments where lesson_id = tests.id('draft')), 0,
  'anon: a draft''s attachments are hidden');
select tests.is((select count(*)::int from public.lessons where id = '44444444-4444-4444-8444-444444444444'), 0,
  'anon: a scheduled lesson is hidden until available_from');

-- Students -------------------------------------------------------------------
select tests.authenticate_as(tests.id('student'));
select tests.is((select count(*)::int from public.lessons where status = 'draft'), 0, 'student: drafts are hidden');
select tests.is((select count(*)::int from public.lesson_attachments where lesson_id = tests.id('draft')), 0,
  'student: a draft''s attachments are hidden');
select tests.is((select count(*)::int from public.lesson_prerequisites where lesson_id = tests.id('draft')), 0,
  'student: a draft''s prerequisites are hidden');
select tests.is((select count(*)::int from public.lessons where id = '44444444-4444-4444-8444-444444444444'), 0,
  'student: a scheduled lesson is hidden until available_from');
select tests.is((select count(*)::int from public.lessons where id = tests.id('archived')), 1,
  'student: archived lessons stay readable for history');
select tests.is((select count(*)::int from public.my_workload where lesson_id = tests.id('archived')), 0,
  'student: archived lessons are not active work');
select tests.ok(
  (select bool_and(category is not null) from public.lessons),
  'every lesson a student can see has a category');
select tests.is(
  (select count(*)::int from public.my_workload where lesson_id = tests.id('draft')), 0,
  'student: a required draft is not in the workload');

-- Admin publishing rules ------------------------------------------------------
select tests.authenticate_as(tests.id('admin'));
select tests.throws(
  format('insert into public.lessons (course_id, title, category, status) values (%L, ''x'', null, ''published'')', tests.id('course_la')),
  'a lesson cannot be saved without a category', 'null value');
select tests.throws(
  format('insert into public.lessons (course_id, title, category, status) values (%L, ''x'', ''required'', ''archived'')', tests.id('course_la')),
  'a never-published lesson cannot be archived', 'Only a lesson that was published');

update public.courses set is_archived = true where id = tests.id('course_la');
select tests.throws(
  format('update public.lessons set status = ''published'' where id = %L', tests.id('draft')),
  'a lesson in an archived course cannot be published', 'archived course');
update public.courses set is_archived = false where id = tests.id('course_la');

update public.lessons set status = 'published' where id = tests.id('draft');
select tests.authenticate_as(tests.id('student'));
select tests.is((select count(*)::int from public.lessons where id = tests.id('draft')), 1,
  'once published, the lesson appears for students');
select tests.is((select count(*)::int from public.my_workload where lesson_id = tests.id('draft')), 1,
  'once published, a required lesson enters every student''s workload');

-- Unpublishing hides it again.
select tests.authenticate_as(tests.id('admin'));
update public.lessons set status = 'draft' where id = tests.id('draft');
select tests.authenticate_as(tests.id('student'));
select tests.is((select count(*)::int from public.lessons where id = tests.id('draft')), 0,
  'unpublishing hides the lesson from students again');
