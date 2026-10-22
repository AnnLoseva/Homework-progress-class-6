-- Subscriptions are only for optional lessons, are idempotent, never delete progress, and
-- cannot remove required lessons from the workload.

select tests.remember('student', tests.create_user('student'));
select tests.remember('admin', tests.create_user('admin'));
select tests.make_admin(tests.id('admin'));

select tests.authenticate_as(tests.id('student'));

-- Workload of a brand-new student: all published required lessons, nothing optional.
select tests.is(
  (select count(*)::int from public.my_workload),
  (select count(*)::int from public.lessons where status = 'published' and category = 'required'),
  'a new student''s workload is exactly the published required lessons');
select tests.is((select count(*)::int from public.my_workload where category = 'optional'), 0,
  'unsubscribed optional lessons are not in the workload');

-- Subscribe / unsubscribe an optional lesson.
select public.set_lesson_subscription(tests.id('opt_determ'), true);
select tests.is((select count(*)::int from public.my_workload where lesson_id = tests.id('opt_determ')), 1,
  'subscribing adds the optional lesson to the workload');
select tests.is((select status from public.lesson_progress where lesson_id = tests.id('opt_determ')), null::public.progress_status,
  'subscribing does not create or complete progress');

-- Duplicate requests.
select public.set_lesson_subscription(tests.id('opt_determ'), true);
select public.set_lesson_subscription(tests.id('opt_determ'), true);
select tests.is((select count(*)::int from public.lesson_subscriptions where lesson_id = tests.id('opt_determ')), 1,
  'repeated subscribe requests keep exactly one subscription row');
select tests.throws(
  format('insert into public.lesson_subscriptions (user_id, lesson_id) values (%L, %L)', tests.id('student'), tests.id('opt_determ')),
  'a raw duplicate INSERT is rejected by the primary key', 'duplicate key');

-- Progress survives unsubscribe → resubscribe.
select public.set_lesson_progress(tests.id('opt_determ'), 'in_progress', 5, 'halfway', now());
select public.set_lesson_subscription(tests.id('opt_determ'), false);
select tests.is((select count(*)::int from public.my_workload where lesson_id = tests.id('opt_determ')), 0,
  'unsubscribing removes the lesson from the workload');
select tests.is((select completed_exercises from public.lesson_progress where lesson_id = tests.id('opt_determ')), 5,
  'unsubscribing keeps the progress');
select tests.ok((select unsubscribed_at is not null and not is_active from public.lesson_subscriptions where lesson_id = tests.id('opt_determ')),
  'the subscription row is kept and marked inactive');
select public.set_lesson_subscription(tests.id('opt_determ'), true);
select tests.is(
  (select completed_exercises || '|' || notes from public.lesson_progress where lesson_id = tests.id('opt_determ')),
  '5|halfway', 'resubscribing restores the earlier progress and notes');

-- Required lessons cannot be toggled.
select tests.throws(format('select public.set_lesson_subscription(%L, false)', tests.id('req_vectors')),
  'a required lesson cannot be unsubscribed through the RPC', 'Required lessons cannot be removed');
select tests.throws(
  format('insert into public.lesson_subscriptions (user_id, lesson_id, is_active) values (%L, %L, false)', tests.id('student'), tests.id('req_logic')),
  'a required lesson cannot be opted out of with a raw insert', 'Required lessons cannot be removed');
select tests.throws(format('select public.set_lesson_subscription(%L, true)', tests.id('req_vectors')),
  'subscribing to a required lesson is refused (it is already in the workload)', 'always in your workload');
select tests.is((select count(*)::int from public.my_workload where lesson_id = tests.id('req_vectors')), 1,
  'the required lesson is still in the workload after those attempts');

-- Draft and archived lessons cannot be subscribed to.
select tests.throws(format('select public.set_lesson_subscription(%L, true)', tests.id('draft')),
  'cannot subscribe to a draft lesson');
select tests.throws(format('select public.set_lesson_subscription(%L, true)', tests.id('archived')),
  'cannot subscribe to an archived lesson', 'Only published lessons');

-- Category changes never destroy data -----------------------------------------
-- (1) optional -> required: progress and the subscription row survive.
select tests.authenticate_as(tests.id('admin'));
update public.lessons set category = 'required' where id = tests.id('opt_determ');
select tests.authenticate_as(tests.id('student'));
select tests.is((select completed_exercises from public.lesson_progress where lesson_id = tests.id('opt_determ')), 5,
  'optional → required keeps progress');
select tests.is((select count(*)::int from public.my_workload where lesson_id = tests.id('opt_determ')), 1,
  'optional → required keeps the lesson in the workload');
select tests.throws(format('select public.set_lesson_subscription(%L, false)', tests.id('opt_determ')),
  'after optional → required the old subscription cannot be used to drop it', 'Required lessons cannot be removed');

-- (2) required -> optional: a student who already started is auto-subscribed.
select public.set_lesson_progress(tests.id('req_logic'), 'in_progress', 2, '', now());
select tests.authenticate_as(tests.id('admin'));
update public.lessons set category = 'optional' where id = tests.id('req_logic');
select tests.authenticate_as(tests.id('student'));
select tests.is((select count(*)::int from public.my_workload where lesson_id = tests.id('req_logic')), 1,
  'required → optional keeps started work in the workload (auto-subscribed)');
select tests.is((select completed_exercises from public.lesson_progress where lesson_id = tests.id('req_logic')), 2,
  'required → optional keeps progress');
select tests.is((select count(*)::int from public.my_workload where lesson_id = tests.id('req_matrices')), 1,
  'untouched required lessons are unaffected');
