-- Storage authorization: knowing (or guessing) an object path is never enough.
-- A signed URL is only issued to a caller who passes these SELECT policies.

select tests.remember('outsider', tests.create_user('outsider'));   -- signed in, never joined the class
select tests.remember('enrolled', tests.create_user('enrolled'));
select tests.remember('other',    tests.create_user('other'));
select tests.remember('admin',    tests.create_user('admin'));
select tests.make_admin(tests.id('admin'));
insert into public.class_enrollments (user_id) values (tests.id('enrolled')), (tests.id('other'));

select tests.remember('att_public',     '77777777-0000-4000-8000-000000000001');
select tests.remember('att_restricted', '77777777-0000-4000-8000-000000000002');
select tests.remember('att_draft',      '77777777-0000-4000-8000-000000000003');

-- Admin uploads three files the way the app does: object first, then the attachment row.
select tests.authenticate_as(tests.id('admin'));
insert into storage.objects (bucket_id, name) values
  ('lesson-materials', tests.id('req_vectors') || '/' || tests.id('att_public') || '/v1.pdf'),
  ('lesson-materials', tests.id('req_vectors') || '/' || tests.id('att_restricted') || '/v1.pdf'),
  ('lesson-materials', tests.id('req_vectors') || '/' || tests.id('att_restricted') || '/v2.pdf'),
  ('lesson-materials', tests.id('draft') || '/' || tests.id('att_draft') || '/v1.pdf');
insert into public.lesson_attachments (id, lesson_id, title, visibility, storage_path, file_name, mime_type, byte_size, version) values
  (tests.id('att_public'), tests.id('req_vectors'), 'Public sheet', 'public',
   tests.id('req_vectors') || '/' || tests.id('att_public') || '/v1.pdf', 'public.pdf', 'application/pdf', 100, 1),
  (tests.id('att_restricted'), tests.id('req_vectors'), 'Class notes', 'restricted',
   tests.id('req_vectors') || '/' || tests.id('att_restricted') || '/v2.pdf', 'notes.pdf', 'application/pdf', 100, 2),
  (tests.id('att_draft'), tests.id('draft'), 'Draft sheet', 'public',
   tests.id('draft') || '/' || tests.id('att_draft') || '/v1.pdf', 'draft.pdf', 'application/pdf', 100, 1);

select tests.is((select count(*)::int from storage.objects where bucket_id = 'lesson-materials'), 4,
  'admin can read every lesson-materials object (incl. drafts and old versions)');
select tests.throws(
  'insert into storage.objects (bucket_id, name) values (''lesson-materials'', ''../escape.pdf'')',
  'even admins cannot upload outside the lesson/attachment/vN.pdf layout', 'row-level security');

-- Visitor -----------------------------------------------------------------------
select tests.as_anon();
select tests.is((select count(*)::int from storage.objects where name like '%' || tests.id('att_public') || '%'), 1,
  'anon can read a PUBLIC attachment of a published lesson');
select tests.is((select count(*)::int from storage.objects where name like '%' || tests.id('att_restricted') || '%'), 0,
  'anon cannot read a RESTRICTED attachment');
select tests.is((select count(*)::int from storage.objects where name like '%' || tests.id('att_draft') || '%'), 0,
  'anon cannot read a draft lesson''s file, even a public one');

-- Signed-in but not enrolled -------------------------------------------------------
select tests.authenticate_as(tests.id('outsider'));
select tests.is((select count(*)::int from storage.objects where name like '%' || tests.id('att_restricted') || '%'), 0,
  'a signed-in user who has not joined the class cannot read restricted files');
select tests.is((select count(*)::int from storage.objects where name like '%' || tests.id('att_public') || '%'), 1,
  'a signed-in user can read public files');

-- Enrolled student -------------------------------------------------------------------
select tests.authenticate_as(tests.id('enrolled'));
select tests.is((select count(*)::int from storage.objects
                  where name = tests.id('req_vectors') || '/' || tests.id('att_restricted') || '/v2.pdf'), 1,
  'an enrolled student can read the current restricted file');
select tests.is((select count(*)::int from storage.objects
                  where name = tests.id('req_vectors') || '/' || tests.id('att_restricted') || '/v1.pdf'), 0,
  'a replaced (old-version) file is no longer readable, even with its exact path');
select tests.is((select count(*)::int from storage.objects where name like tests.id('draft') || '/%'), 0,
  'an enrolled student cannot read draft materials by guessing the path');

select tests.throws(
  format('insert into storage.objects (bucket_id, name) values (''lesson-materials'', %L)',
    tests.id('req_vectors') || '/' || tests.id('att_public') || '/v9.pdf'),
  'students cannot upload lesson materials', 'row-level security');
select tests.is(
  tests.rows_affected(format('update storage.objects set metadata = ''{"hacked":true}'' where bucket_id = ''lesson-materials''')),
  0::bigint, 'students cannot overwrite lesson materials');
select tests.is(
  tests.rows_affected('delete from storage.objects where bucket_id = ''lesson-materials'''),
  0::bigint, 'students cannot delete lesson materials');
select tests.is(
  tests.rows_affected(format('update public.lesson_attachments set visibility = ''public'' where id = %L', tests.id('att_restricted'))),
  0::bigint, 'students cannot make a restricted attachment public');

-- student-private bucket ---------------------------------------------------------------
insert into storage.objects (bucket_id, name) values ('student-private', tests.id('enrolled') || '/my-solution.pdf');
select tests.is((select count(*)::int from storage.objects where bucket_id = 'student-private'), 1,
  'a student can upload and read files in their own private folder');
select tests.throws(
  format('insert into storage.objects (bucket_id, name) values (''student-private'', %L)', tests.id('other') || '/planted.pdf'),
  'a student cannot write into another student''s private folder', 'row-level security');

select tests.authenticate_as(tests.id('other'));
select tests.is((select count(*)::int from storage.objects where bucket_id = 'student-private'), 0,
  'another student cannot read someone else''s private files');
select tests.is(
  tests.rows_affected(format('delete from storage.objects where name = %L', tests.id('enrolled') || '/my-solution.pdf')),
  0::bigint, 'another student cannot delete someone else''s private files');

select tests.authenticate_as(tests.id('admin'));
select tests.is((select count(*)::int from storage.objects where bucket_id = 'student-private'), 0,
  'the administrator cannot read students'' private files');
