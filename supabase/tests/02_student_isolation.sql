-- Student A must never read or modify Student B's progress, notes or subscriptions,
-- whatever payload they send.

select tests.remember('student_a', tests.create_user('student-a'));
select tests.remember('student_b', tests.create_user('student-b'));

-- Student B records progress with private notes and follows an optional lesson.
select tests.authenticate_as(tests.id('student_b'));
select public.set_lesson_progress(tests.id('req_vectors'), 'in_progress', 3, 'B''s private notes', now());
select public.set_lesson_subscription(tests.id('opt_determ'), true);

-- Student A ---------------------------------------------------------------
select tests.authenticate_as(tests.id('student_a'));

select tests.is((select count(*)::int from public.lesson_progress), 0,
  'A sees no progress rows (B''s are invisible)');
select tests.is((select count(*)::int from public.lesson_progress where user_id = tests.id('student_b')), 0,
  'A cannot read B''s progress even by filtering on B''s id');
select tests.is((select count(*)::int from public.lesson_progress where notes like '%private%'), 0,
  'A cannot read B''s private notes');
select tests.is((select count(*)::int from public.lesson_subscriptions), 0,
  'A cannot read B''s subscriptions');
select tests.is((select count(*)::int from public.profiles), 1,
  'A sees exactly one profile: their own');

select tests.is(
  tests.rows_affected(format('update public.lesson_progress set notes = %L, completed_exercises = 0 where user_id = %L',
    'hacked', tests.id('student_b'))),
  0::bigint, 'A''s UPDATE of B''s progress touches 0 rows');
select tests.is(
  tests.rows_affected(format('update public.lesson_subscriptions set is_active = false where user_id = %L',
    tests.id('student_b'))),
  0::bigint, 'A cannot unsubscribe B');
select tests.is(
  tests.rows_affected(format('update public.profiles set display_name = %L where id = %L', 'hacked', tests.id('student_b'))),
  0::bigint, 'A cannot rename B''s profile');

select tests.throws(
  format('insert into public.lesson_progress (user_id, lesson_id, status, completed_exercises) values (%L, %L, ''completed'', 8)',
    tests.id('student_b'), tests.id('req_matrices')),
  'A cannot insert progress on B''s behalf', 'row-level security');
select tests.throws(
  format('insert into public.lesson_subscriptions (user_id, lesson_id) values (%L, %L)',
    tests.id('student_b'), tests.id('opt_puzzles')),
  'A cannot subscribe B to a lesson', 'row-level security');

-- A writes their own row, then tries to re-home it to B by changing user_id.
select public.set_lesson_progress(tests.id('req_logic'), 'in_progress', 1, '', now());
select tests.throws(
  format('update public.lesson_progress set user_id = %L where lesson_id = %L',
    tests.id('student_b'), tests.id('req_logic')),
  'A cannot move their progress row onto B');
select tests.throws(
  format('delete from public.lesson_progress where user_id = %L', tests.id('student_b')),
  'A has no DELETE privilege on progress', 'permission denied');

-- The RPC ignores any notion of "which user": it always writes the caller's row.
select public.set_lesson_progress(tests.id('req_vectors'), 'completed', 8, 'A''s notes', now());

reset role;
select tests.is(
  (select notes from public.lesson_progress where user_id = tests.id('student_b') and lesson_id = tests.id('req_vectors')),
  'B''s private notes', 'B''s notes are unchanged after all of A''s attempts');
select tests.is(
  (select completed_exercises from public.lesson_progress where user_id = tests.id('student_b') and lesson_id = tests.id('req_vectors')),
  3, 'B''s exercise count is unchanged');
select tests.is(
  (select is_active from public.lesson_subscriptions where user_id = tests.id('student_b') and lesson_id = tests.id('opt_determ')),
  true, 'B''s subscription is unchanged');
select tests.is(
  (select count(*)::int from public.lesson_progress where user_id = tests.id('student_a')),
  2, 'A''s RPC calls created only A''s own rows');

-- Visitors (anon) see no personal data at all.
select tests.as_anon();
select tests.throws('select count(*) from public.lesson_progress', 'anon cannot query progress', 'permission denied');
select tests.throws('select count(*) from public.profiles', 'anon cannot query profiles', 'permission denied');
