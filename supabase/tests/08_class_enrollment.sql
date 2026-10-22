-- The class join code gates restricted materials. Only a salted hash is stored, only an
-- admin can set it, and guessing is rate limited.

select tests.remember('student', tests.create_user('student'));
select tests.remember('guesser', tests.create_user('guesser'));
select tests.remember('admin',   tests.create_user('admin'));
select tests.make_admin(tests.id('admin'));

select tests.authenticate_as(tests.id('student'));
select tests.is(public.join_class('ANYTHING1'), 'not_configured', 'joining before a code exists reports not_configured');

select tests.authenticate_as(tests.id('admin'));
select tests.throws('select public.set_class_join_code(''short'')', 'codes shorter than 8 characters are rejected', '8–64');
select public.set_class_join_code('Forest-Moss-2026');
select tests.ok(public.class_join_code_updated_at() is not null, 'admin can see when the code was last changed');

reset role;
select tests.ok(
  (select join_code_hash <> 'FORESTMOSS2026' and join_code_hash !~* 'forest' and length(join_code_hash) = 64
     from private.class_settings),
  'only a salted SHA-256 hash of the code is stored');

select tests.authenticate_as(tests.id('student'));
select tests.throws('select public.class_join_code_updated_at()', 'students cannot read code metadata', 'Administrator role required');
select tests.is(public.join_class('wrong-code'), 'invalid_code', 'a wrong code is refused');
select tests.ok(not private.is_enrolled(), 'a refused student is not enrolled');
select tests.is(public.join_class('forest moss 2026'), 'joined', 'the code is case/space/dash-insensitive');
select tests.ok(private.is_enrolled(), 'the student is now enrolled');
select tests.is(public.join_class('forest-moss-2026'), 'already_joined', 'joining twice is idempotent');
select tests.is((select count(*)::int from public.class_enrollments), 1, 'the student sees their own enrollment');

-- Rate limiting.
select tests.authenticate_as(tests.id('guesser'));
select public.join_class('guess-' || g) from generate_series(1, 10) as g;
select tests.is(public.join_class('Forest-Moss-2026'), 'rate_limited',
  'after 10 failed attempts in an hour even the right code is refused');
select tests.ok(not private.is_enrolled(), 'the rate-limited user did not get in');

-- Rotating the code does not remove existing members.
select tests.authenticate_as(tests.id('admin'));
select public.set_class_join_code('New-Semester-Code');
select tests.authenticate_as(tests.id('student'));
select tests.ok(private.is_enrolled(), 'rotating the code keeps existing students enrolled');
