-- A lesson's class week dates: both or neither, in order, at most two weeks long; students
-- read them like any other lesson column and can't change them.

select tests.remember('student', tests.create_user('student'));
select tests.remember('admin', tests.create_user('admin'));
select tests.make_admin(tests.id('admin'));

select tests.authenticate_as(tests.id('admin'));
update public.lessons set week_starts_on = '2026-10-18', week_ends_on = '2026-10-23' where id = tests.id('req_vectors');
select tests.is((select week_ends_on - week_starts_on from public.lessons where id = tests.id('req_vectors')), 5,
  'admin: a lesson keeps its class week dates');
select tests.throws(format('update public.lessons set week_ends_on = null where id = %L', tests.id('req_vectors')),
  'only one of the two dates is rejected');
select tests.throws(format('update public.lessons set week_starts_on = ''2026-10-23'', week_ends_on = ''2026-10-18'' where id = %L', tests.id('req_vectors')),
  'an end before the start is rejected');
select tests.throws(format('update public.lessons set week_starts_on = ''2026-10-01'', week_ends_on = ''2026-10-30'' where id = %L', tests.id('req_vectors')),
  'a "week" longer than two weeks is rejected');

select tests.authenticate_as(tests.id('student'));
select tests.is((select week_starts_on::text from public.lessons where id = tests.id('req_vectors')), '2026-10-18',
  'student: reads the class week dates');
select tests.is(
  tests.rows_affected(format('update public.lessons set week_starts_on = ''2026-11-01'', week_ends_on = ''2026-11-07'' where id = %L',
                             tests.id('req_vectors'))),
  0::bigint, 'student cannot move a lesson to another week');
select tests.is((select week_starts_on::text from public.lessons where id = tests.id('req_vectors')), '2026-10-18',
  'student: the dates are unchanged');
