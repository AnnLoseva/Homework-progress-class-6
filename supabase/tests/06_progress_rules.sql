-- Progress validation, server-controlled timestamps, last-writer-wins between devices,
-- and that no content change resets a student's progress.

select tests.remember('student', tests.create_user('student'));
select tests.remember('admin', tests.create_user('admin'));
select tests.make_admin(tests.id('admin'));
select tests.authenticate_as(tests.id('student'));

-- Validation -----------------------------------------------------------------
select tests.throws(format('select public.set_lesson_progress(%L, ''in_progress'', 9, '''', now())', tests.id('req_vectors')),
  'completed exercises cannot exceed the lesson''s exercise count', 'exceeds');
select tests.throws(format('select public.set_lesson_progress(%L, ''in_progress'', -1, '''', now())', tests.id('req_vectors')),
  'completed exercises cannot be negative');
select tests.throws(format('select public.set_lesson_progress(%L, ''not_started'', 2, '''', now())', tests.id('req_vectors')),
  '"not started" with completed exercises is rejected', 'not_started_has_no_exercises');
select tests.throws(format('select public.set_lesson_progress(%L, ''in_progress'', 1, '''', now())', tests.id('opt_puzzles')),
  'a lesson without numbered exercises cannot record exercise counts', 'exceeds');
select tests.throws(format('select public.set_lesson_progress(%L, ''in_progress'', 0, '''', now())', tests.id('draft')),
  'progress cannot be created for a draft lesson', 'published or archived');
select tests.throws(format('select public.set_lesson_progress(%L, ''in_progress'', 0, repeat(''x'', 20001), now())', tests.id('req_vectors')),
  'notes are limited to 20 000 characters');

-- Manual completion for lessons without exercises.
select public.set_lesson_progress(tests.id('opt_puzzles'), 'completed', 0, '', now());
select tests.ok((select completed_at is not null from public.lesson_progress where lesson_id = tests.id('opt_puzzles')),
  'manual completion works for lessons without exercises and stamps completed_at');

-- completed_at is server-controlled.
select public.set_lesson_progress(tests.id('req_vectors'), 'in_progress', 3, '', now());
update public.lesson_progress set completed_at = now() where lesson_id = tests.id('req_vectors');
select tests.ok((select completed_at is null from public.lesson_progress where lesson_id = tests.id('req_vectors')),
  'a client-supplied completed_at on an unfinished lesson is discarded');
update public.lesson_progress set status = 'completed', completed_at = '2001-01-01'
 where lesson_id = tests.id('req_vectors');
select tests.ok((select completed_at > now() - interval '1 minute' from public.lesson_progress where lesson_id = tests.id('req_vectors')),
  'a forged completed_at is replaced by the server time');
select public.set_lesson_progress(tests.id('req_vectors'), 'in_progress', 7, '', now() + interval '1 second');
select tests.ok((select completed_at is null from public.lesson_progress where lesson_id = tests.id('req_vectors')),
  'reopening a completed lesson clears completed_at');

-- Lesson completion is separate from exercise completion.
select public.set_lesson_progress(tests.id('req_matrices'), 'completed', 6, '', now());
select tests.is((select status::text || ' ' || completed_exercises from public.lesson_progress where lesson_id = tests.id('req_matrices')),
  'completed 6', 'a lesson can be marked completed without ticking every exercise');

-- Multi-device: last writer (by device time) wins --------------------------------
select public.set_lesson_progress(tests.id('req_logic'), 'in_progress', 4, 'from iPad (newer)', now() + interval '10 seconds');
select public.set_lesson_progress(tests.id('req_logic'), 'in_progress', 1, 'from iPhone (older, synced late)', now());
select tests.is((select notes from public.lesson_progress where lesson_id = tests.id('req_logic')), 'from iPad (newer)',
  'an older offline change replayed late does not overwrite a newer one');
select tests.is((select (public.set_lesson_progress(tests.id('req_logic'), 'in_progress', 1, 'stale', now())).completed_exercises), 4,
  'a stale write returns the current server row so the device can reconcile');

-- A device clock far in the future is clamped, so it cannot win every later conflict.
select public.set_lesson_progress(tests.id('opt_planning'), 'in_progress', 0, '', '2030-01-01T00:00:00Z');
reset role;
select tests.ok((select client_modified_at <= now() + interval '5 minutes' from public.lesson_progress
                  where user_id = tests.id('student') and lesson_id = tests.id('opt_planning')),
  'a device clock far in the future is clamped to server time');

-- Retrying the same request is harmless.
select tests.authenticate_as(tests.id('student'));
select public.set_lesson_progress(tests.id('req_logic'), 'in_progress', 5, 'retry', now() + interval '1 minute');
select public.set_lesson_progress(tests.id('req_logic'), 'in_progress', 5, 'retry', now() + interval '1 minute');
select tests.is((select count(*)::int from public.lesson_progress where lesson_id = tests.id('req_logic')), 1,
  'retries never create duplicate progress rows');
select tests.is((select notes from public.lesson_progress where lesson_id = tests.id('req_logic')), 'retry',
  'a retried write is applied once with the same result');

-- Content changes never reset progress -----------------------------------------
select tests.authenticate_as(tests.id('admin'));
insert into public.lesson_attachments (id, lesson_id, title, visibility, storage_path, file_name, mime_type, byte_size)
values ('55555555-5555-4555-8555-555555555555', tests.id('req_logic'), 'Sheet', 'restricted',
        tests.id('req_logic')::text || '/55555555-5555-4555-8555-555555555555/v1.pdf', 'sheet.pdf', 'application/pdf', 2048);

-- Replace the PDF: same attachment id, new version and path.
update public.lesson_attachments
   set version = 2,
       storage_path = tests.id('req_logic')::text || '/55555555-5555-4555-8555-555555555555/v2.pdf',
       byte_size = 4096, file_name = 'sheet-v2.pdf'
 where id = '55555555-5555-4555-8555-555555555555';
select tests.is((select version from public.lesson_attachments where id = '55555555-5555-4555-8555-555555555555'), 2,
  'replacing a PDF keeps the attachment id and bumps the version');
select tests.throws(
  'update public.lesson_attachments set version = 1, storage_path = replace(storage_path, ''/v2.pdf'', ''/v1.pdf'') where id = ''55555555-5555-4555-8555-555555555555''',
  'attachment versions cannot go backwards', 'backwards');
select tests.throws(
  format('update public.lesson_attachments set storage_path = %L where id = ''55555555-5555-4555-8555-555555555555''',
    tests.id('req_logic')::text || '/55555555-5555-4555-8555-555555555555/../../etc.pdf'),
  'storage paths must follow lesson/attachment/vN.pdf', 'path_format');
select tests.throws(
  format('insert into public.lesson_attachments (lesson_id, title, storage_path, file_name, mime_type, byte_size) values (%L, ''x'', ''x'', ''x.exe'', ''application/x-msdownload'', 10)', tests.id('req_logic')),
  'non-PDF MIME types are rejected', 'mime_type');
select tests.throws(
  format('insert into public.lesson_attachments (id, lesson_id, title, storage_path, file_name, mime_type, byte_size) values (''66666666-6666-4666-8666-666666666666'', %L, ''x'', %L, ''x.pdf'', ''application/pdf'', 52428801)',
    tests.id('req_logic'), tests.id('req_logic')::text || '/66666666-6666-4666-8666-666666666666/v1.pdf'),
  'attachments over 50 MB are rejected', 'byte_size');

update public.lessons set title = 'Propositional logic (revised)', description = 'Edited', due_at = now() + interval '9 days',
                         exercise_count = 7
 where id = tests.id('req_logic');
update public.lessons set status = 'archived' where id = tests.id('req_logic');
update public.lessons set status = 'published' where id = tests.id('req_logic');

select tests.authenticate_as(tests.id('student'));
select tests.is((select completed_exercises || '|' || notes from public.lesson_progress where lesson_id = tests.id('req_logic')),
  '5|retry', 'editing metadata, replacing the PDF, archiving and republishing keep progress intact');
select tests.is((select count(*)::int from public.lessons where id = tests.id('req_logic')), 1,
  'republishing an archived lesson does not duplicate it');
select tests.is((select count(*)::int from public.lesson_progress where lesson_id = tests.id('req_logic')), 1,
  'republishing does not duplicate progress');

-- Archived lessons keep history and still accept notes.
select tests.authenticate_as(tests.id('admin'));
update public.lessons set status = 'archived' where id = tests.id('req_logic');
select tests.authenticate_as(tests.id('student'));
select tests.is((select count(*)::int from public.lesson_progress where lesson_id = tests.id('req_logic')), 1,
  'archived lessons keep the student''s progress');
select public.set_lesson_progress(tests.id('req_logic'), 'completed', 5, 'finished after archive', now() + interval '2 minutes');
select tests.is((select status::text from public.lesson_progress where lesson_id = tests.id('req_logic')), 'completed',
  'progress on an archived lesson can still be updated for the record');
