-- Sign-up creates a minimal profile; export returns only the caller's data; deleting the
-- auth user (the last step of the delete-account Edge Function) removes all personal data
-- while shared content stays.

select tests.remember('student', tests.create_user('student'));
select tests.remember('other',   tests.create_user('other'));

select tests.is((select count(*)::int from public.profiles where id = tests.id('student')), 1,
  'a profile row is created automatically on sign-up');
select tests.is((select display_name from public.profiles where id = tests.id('student')), null::text,
  'the profile stores no name or email by default');

select tests.authenticate_as(tests.id('other'));
select public.set_lesson_progress(tests.id('req_vectors'), 'in_progress', 1, 'other''s notes', now());

select tests.authenticate_as(tests.id('student'));
update public.profiles set display_name = 'Moss' where id = tests.id('student');
select public.set_lesson_subscription(tests.id('opt_determ'), true);
select public.set_lesson_progress(tests.id('req_vectors'), 'in_progress', 2, 'my notes', now());

select tests.is((public.export_my_data() ->> 'user_id')::uuid, tests.id('student'), 'export is for the caller');
select tests.is(jsonb_array_length(public.export_my_data() -> 'progress'), 1, 'export contains only the caller''s progress');
select tests.is(jsonb_array_length(public.export_my_data() -> 'subscriptions'), 1, 'export contains the caller''s subscriptions');
select tests.ok(public.export_my_data()::text not like '%other''s notes%', 'export never includes another student''s notes');
select tests.is(public.export_my_data() -> 'profile' ->> 'display_name', 'Moss', 'export includes the profile');

select tests.throws(format('delete from auth.users where id = %L', tests.id('student')),
  'a student cannot delete auth users directly', 'permission denied');

-- What the Edge Function does with the service role, after verifying the caller's JWT:
reset role;
delete from auth.users where id = tests.id('student');

select tests.is((select count(*)::int from public.profiles where id = tests.id('student')), 0, 'account deletion removes the profile');
select tests.is((select count(*)::int from public.lesson_progress where user_id = tests.id('student')), 0, 'account deletion removes progress and notes');
select tests.is((select count(*)::int from public.lesson_subscriptions where user_id = tests.id('student')), 0, 'account deletion removes subscriptions');
select tests.is((select count(*)::int from public.lesson_progress where user_id = tests.id('other')), 1, 'other students'' data is untouched');
select tests.is((select count(*)::int from public.lessons where id = tests.id('req_vectors')), 1, 'shared lessons are untouched');
