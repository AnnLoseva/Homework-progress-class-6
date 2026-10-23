-- ============================================================================
-- Storage: two PRIVATE buckets. Nothing is served from a public bucket URL; every read
-- goes through these policies (directly or via a short-lived signed URL, which Storage
-- only issues to a caller who passes the SELECT policy).
--
--   lesson-materials  <lesson_id>/<attachment_id>/v<version>.pdf
--       read: decided by the matching lesson_attachments row (lesson status + visibility)
--       write: administrators only
--   student-private   <user_id>/<anything>
--       read/write: the owner only (administrators have no access)
-- ============================================================================

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('lesson-materials', 'lesson-materials', false, 52428800, array['application/pdf']),
  ('student-private',  'student-private',  false, 52428800, array['application/pdf', 'image/png', 'image/jpeg'])
on conflict (id) do update
  set public = false,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- Whether the caller may read a lesson-materials object. A file name being hard to guess is
-- not authorization: the object must be the CURRENT file of an attachment row, and that
-- row's lesson and visibility must allow the caller.
create function private.can_read_lesson_object(p_name text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.is_admin() or exists (
    select 1
      from public.lesson_attachments a
      join public.lessons l on l.id = a.lesson_id
     where a.storage_path = p_name
       and private.lesson_is_visible(l.status, l.available_from)
       and (a.visibility = 'public' or private.is_enrolled())
  );
$$;
revoke all on function private.can_read_lesson_object(text) from public;
grant execute on function private.can_read_lesson_object(text) to anon, authenticated, service_role;

create function private.is_valid_lesson_object_name(p_name text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select p_name ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/v[1-9][0-9]{0,5}\.pdf$';
$$;
grant execute on function private.is_valid_lesson_object_name(text) to anon, authenticated, service_role;

-- lesson-materials -----------------------------------------------------------
create policy "lesson-materials: read per attachment policy" on storage.objects
  for select to anon, authenticated
  using (bucket_id = 'lesson-materials' and private.can_read_lesson_object(name));

create policy "lesson-materials: admins upload" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'lesson-materials'
    and (select private.is_admin())
    and private.is_valid_lesson_object_name(name)
  );

create policy "lesson-materials: admins update" on storage.objects
  for update to authenticated
  using (bucket_id = 'lesson-materials' and (select private.is_admin()))
  with check (
    bucket_id = 'lesson-materials'
    and (select private.is_admin())
    and private.is_valid_lesson_object_name(name)
  );

create policy "lesson-materials: admins delete" on storage.objects
  for delete to authenticated
  using (bucket_id = 'lesson-materials' and (select private.is_admin()));

-- student-private ------------------------------------------------------------
create policy "student-private: owner reads" on storage.objects
  for select to authenticated
  using (bucket_id = 'student-private' and (storage.foldername(name))[1] = (select auth.uid())::text);

create policy "student-private: owner uploads" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'student-private' and (storage.foldername(name))[1] = (select auth.uid())::text);

create policy "student-private: owner updates" on storage.objects
  for update to authenticated
  using (bucket_id = 'student-private' and (storage.foldername(name))[1] = (select auth.uid())::text)
  with check (bucket_id = 'student-private' and (storage.foldername(name))[1] = (select auth.uid())::text);

create policy "student-private: owner deletes" on storage.objects
  for delete to authenticated
  using (bucket_id = 'student-private' and (storage.foldername(name))[1] = (select auth.uid())::text);
