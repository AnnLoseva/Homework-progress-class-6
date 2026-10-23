-- ============================================================================
-- Test fixtures — MADE-UP DATA, used only by the SQL test suites.
--
-- tools/db-tests/run.mjs loads this inside each suite's transaction and rolls it back, so
-- it never stays in a database and never appears in the app. Contains no users, no
-- personal data and no copyrighted material. Attachments are inserted by the suites.
-- ============================================================================

insert into public.courses (id, slug, title, subtitle, icon_name, color_key, sort_order) values
  ('00000000-0000-4000-8000-000000000c01', 'linear-algebra', 'Linear Algebra', 'אלגברה לינארית', 'CourseLinearAlgebra', 'dusk',   1),
  ('00000000-0000-4000-8000-000000000c02', 'discrete-math',  'Discrete Mathematics', 'מתמטיקה בדידה', 'CourseDiscrete',      'moss',   2),
  ('00000000-0000-4000-8000-000000000c03', 'study-skills',   'Study Skills', 'מיומנויות למידה',       'CourseStudy',          'honey',  3)
on conflict (id) do nothing;

-- Lessons are inserted as drafts first and then published, exactly like the admin flow,
-- so the lifecycle trigger stamps published_at/archived_at.
insert into public.lessons
  (id, course_id, title, description, category, week, module_title, sort_order, due_at, estimated_minutes, exercise_count)
values
  ('00000000-0000-4000-8000-0000000001a1', '00000000-0000-4000-8000-000000000c01',
   'Vectors and linear combinations',
   'Span, linear combinations and the geometric picture of vectors in ℝ².',
   'required', 1, 'Foundations', 1, now() + interval '5 days', 90, 8),
  ('00000000-0000-4000-8000-0000000001a2', '00000000-0000-4000-8000-000000000c01',
   'Matrices as transformations',
   'Reading a matrix as a function; composition as multiplication.',
   'required', 2, 'Foundations', 2, now() + interval '12 days', 120, 10),
  ('00000000-0000-4000-8000-0000000001a3', '00000000-0000-4000-8000-000000000c01',
   'Extra practice: determinants',
   'Optional drills for anyone who wants more determinant practice.',
   'optional', 2, 'Foundations', 3, null, 45, 12),
  ('00000000-0000-4000-8000-0000000001b1', '00000000-0000-4000-8000-000000000c02',
   'Propositional logic',
   'Truth tables, implication and logical equivalence. תרגול בעברית מצורף.',
   'required', 1, 'Logic', 1, now() + interval '3 days', 60, 6),
  ('00000000-0000-4000-8000-0000000001b2', '00000000-0000-4000-8000-000000000c02',
   'Puzzle corner: pigeonhole principle',
   'Optional puzzles. No numbered exercises — mark it complete when you are done.',
   'optional', 3, 'Combinatorics', 1, null, 30, 0),
  ('00000000-0000-4000-8000-0000000001c1', '00000000-0000-4000-8000-000000000c03',
   'Planning your study week',
   'A short reading on spaced repetition and weekly planning.',
   'optional', 0, 'Orientation', 1, null, 20, 0),
  ('00000000-0000-4000-8000-0000000001c2', '00000000-0000-4000-8000-000000000c03',
   'Last semester''s orientation notes',
   'Kept for reference; replaced by "Planning your study week".',
   'optional', 0, 'Orientation', 2, null, 15, 0),
  ('00000000-0000-4000-8000-0000000001d1', '00000000-0000-4000-8000-000000000c01',
   'Eigenvalues (draft)',
   'Not published yet — students must not see this lesson.',
   'required', 6, 'Spectral theory', 1, null, 120, 9)
on conflict (id) do nothing;

update public.lessons set status = 'published'
 where id in ('00000000-0000-4000-8000-0000000001a1', '00000000-0000-4000-8000-0000000001a2',
              '00000000-0000-4000-8000-0000000001a3', '00000000-0000-4000-8000-0000000001b1',
              '00000000-0000-4000-8000-0000000001b2', '00000000-0000-4000-8000-0000000001c1',
              '00000000-0000-4000-8000-0000000001c2')
   and status = 'draft';

update public.lessons set status = 'archived'
 where id = '00000000-0000-4000-8000-0000000001c2' and status = 'published';

insert into public.lesson_prerequisites (lesson_id, prerequisite_id) values
  ('00000000-0000-4000-8000-0000000001a2', '00000000-0000-4000-8000-0000000001a1'),
  ('00000000-0000-4000-8000-0000000001a3', '00000000-0000-4000-8000-0000000001a2')
on conflict do nothing;
