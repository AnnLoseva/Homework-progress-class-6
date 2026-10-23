-- ============================================================================
-- Row Level Security and table privileges.
--
-- RLS is enabled on EVERY table in `public`. Privileges are granted explicitly so a table
-- added later without a policy is closed by default. `(select auth.uid())` is used instead
-- of `auth.uid()` so Postgres evaluates it once per statement.
-- ============================================================================

alter table public.profiles             enable row level security;
alter table public.administrator_roles  enable row level security;
alter table public.class_enrollments    enable row level security;
alter table public.courses              enable row level security;
alter table public.lessons              enable row level security;
alter table public.lesson_prerequisites enable row level security;
alter table public.lesson_attachments   enable row level security;
alter table public.lesson_subscriptions enable row level security;
alter table public.lesson_progress      enable row level security;

-- Start from nothing, then grant only what each role needs.
revoke all on public.profiles, public.administrator_roles, public.class_enrollments,
              public.courses, public.lessons, public.lesson_prerequisites,
              public.lesson_attachments, public.lesson_subscriptions, public.lesson_progress
  from anon, authenticated;

grant select on public.courses, public.lessons, public.lesson_prerequisites, public.lesson_attachments
  to anon, authenticated;
grant insert, update, delete on public.courses, public.lessons, public.lesson_prerequisites, public.lesson_attachments
  to authenticated;                                   -- narrowed to administrators by RLS
grant select on public.profiles to authenticated;
grant update (display_name) on public.profiles to authenticated;
grant select on public.administrator_roles to authenticated;
grant select on public.class_enrollments to authenticated;
grant select, insert, update on public.lesson_subscriptions to authenticated;
grant select, insert, update on public.lesson_progress to authenticated;
-- No DELETE on subscriptions/progress: unsubscribing flips a flag, and personal data is
-- removed only by account deletion (ON DELETE CASCADE from auth.users).

-- ---------------------------------------------------------------------------
-- profiles: own row only
-- ---------------------------------------------------------------------------
create policy "profiles: read own" on public.profiles
  for select to authenticated
  using (id = (select auth.uid()));

create policy "profiles: update own" on public.profiles
  for update to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

-- ---------------------------------------------------------------------------
-- administrator_roles / class_enrollments: read own row (so the app knows), never write
-- ---------------------------------------------------------------------------
create policy "administrator_roles: read own" on public.administrator_roles
  for select to authenticated
  using (user_id = (select auth.uid()));

create policy "class_enrollments: read own" on public.class_enrollments
  for select to authenticated
  using (user_id = (select auth.uid()));

-- ---------------------------------------------------------------------------
-- courses
-- ---------------------------------------------------------------------------
create policy "courses: anyone can read" on public.courses
  for select to anon, authenticated
  using (true);

create policy "courses: admins insert" on public.courses
  for insert to authenticated
  with check ((select private.is_admin()));

create policy "courses: admins update" on public.courses
  for update to authenticated
  using ((select private.is_admin()))
  with check ((select private.is_admin()));

create policy "courses: admins delete" on public.courses
  for delete to authenticated
  using ((select private.is_admin()));

-- ---------------------------------------------------------------------------
-- lessons: students see published/archived lessons once available; drafts are admin-only
-- ---------------------------------------------------------------------------
create policy "lessons: read visible or admin" on public.lessons
  for select to anon, authenticated
  using (private.lesson_is_visible(status, available_from) or (select private.is_admin()));

create policy "lessons: admins insert" on public.lessons
  for insert to authenticated
  with check ((select private.is_admin()));

create policy "lessons: admins update" on public.lessons
  for update to authenticated
  using ((select private.is_admin()))
  with check ((select private.is_admin()));

create policy "lessons: admins delete" on public.lessons
  for delete to authenticated
  using ((select private.is_admin()));

-- ---------------------------------------------------------------------------
-- lesson_prerequisites / lesson_attachments: follow the visibility of their lesson.
-- The sub-select runs under the caller's lessons policy, so drafts stay hidden.
-- ---------------------------------------------------------------------------
create policy "lesson_prerequisites: read with lesson" on public.lesson_prerequisites
  for select to anon, authenticated
  using (exists (select 1 from public.lessons l where l.id = lesson_id));

create policy "lesson_prerequisites: admins write" on public.lesson_prerequisites
  for all to authenticated
  using ((select private.is_admin()))
  with check ((select private.is_admin()));

create policy "lesson_attachments: read with lesson" on public.lesson_attachments
  for select to anon, authenticated
  using (exists (select 1 from public.lessons l where l.id = lesson_id));

create policy "lesson_attachments: admins insert" on public.lesson_attachments
  for insert to authenticated
  with check ((select private.is_admin()));

create policy "lesson_attachments: admins update" on public.lesson_attachments
  for update to authenticated
  using ((select private.is_admin()))
  with check ((select private.is_admin()));

create policy "lesson_attachments: admins delete" on public.lesson_attachments
  for delete to authenticated
  using ((select private.is_admin()));

-- ---------------------------------------------------------------------------
-- lesson_subscriptions / lesson_progress: strictly the owner's rows.
-- Administrators have NO policy here: they cannot read students' progress or notes.
-- ---------------------------------------------------------------------------
create policy "lesson_subscriptions: read own" on public.lesson_subscriptions
  for select to authenticated
  using (user_id = (select auth.uid()));

create policy "lesson_subscriptions: insert own" on public.lesson_subscriptions
  for insert to authenticated
  with check (user_id = (select auth.uid()));

create policy "lesson_subscriptions: update own" on public.lesson_subscriptions
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

create policy "lesson_progress: read own" on public.lesson_progress
  for select to authenticated
  using (user_id = (select auth.uid()));

create policy "lesson_progress: insert own" on public.lesson_progress
  for insert to authenticated
  with check (user_id = (select auth.uid()));

create policy "lesson_progress: update own" on public.lesson_progress
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));
