-- ============================================================================
-- Fixes from the Supabase database advisors (performance lints). No behavior change.
-- ============================================================================

-- Covering indexes for foreign keys to auth.users (used when an account is deleted).
create index courses_created_by_idx on public.courses (created_by);
create index lessons_created_by_idx on public.lessons (created_by);
create index lesson_attachments_uploaded_by_idx on public.lesson_attachments (uploaded_by);

-- Every table gets a primary key.
alter table private.join_attempts add column id bigint generated always as identity primary key;

-- "admins write" was FOR ALL, which also added a second permissive SELECT policy for
-- authenticated users. Split it so reads are governed by one policy only.
drop policy "lesson_prerequisites: admins write" on public.lesson_prerequisites;

create policy "lesson_prerequisites: admins insert" on public.lesson_prerequisites
  for insert to authenticated
  with check ((select private.is_admin()));

create policy "lesson_prerequisites: admins update" on public.lesson_prerequisites
  for update to authenticated
  using ((select private.is_admin()))
  with check ((select private.is_admin()));

create policy "lesson_prerequisites: admins delete" on public.lesson_prerequisites
  for delete to authenticated
  using ((select private.is_admin()));
