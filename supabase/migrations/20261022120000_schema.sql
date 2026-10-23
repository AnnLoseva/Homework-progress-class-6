-- ============================================================================
-- Woodland Study Tracker — core schema
--
-- Shared educational content: courses, lessons, lesson_prerequisites, lesson_attachments
-- Personal data (one owner):  profiles, class_enrollments, lesson_subscriptions,
--                             lesson_progress
-- Privileged:                 administrator_roles (written only by trusted SQL)
--
-- Row Level Security is enabled in 20261022120100_rls.sql. Validation that must hold no
-- matter which API path writes a row lives in the BEFORE triggers below.
-- ============================================================================

-- Helpers that RLS policies call. Not exposed through the Data API (only `public` is).
create schema if not exists private;
revoke all on schema private from public;
grant usage on schema private to anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Enumerations
-- ---------------------------------------------------------------------------
create type public.lesson_category as enum ('required', 'optional');
comment on type public.lesson_category is
  'Academic classification: required (חובה) or optional (רשות). Not a subscription or completion state.';

create type public.lesson_status as enum ('draft', 'published', 'archived');
create type public.attachment_visibility as enum ('public', 'restricted');
create type public.progress_status as enum ('not_started', 'in_progress', 'completed');

-- ---------------------------------------------------------------------------
-- Shared trigger: updated_at
-- ---------------------------------------------------------------------------
create function private.touch_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- Accounts
-- ---------------------------------------------------------------------------

-- One row per auth user. Deliberately holds no email, Apple ID or role.
create table public.profiles (
  id           uuid primary key references auth.users (id) on delete cascade,
  display_name text check (display_name is null or char_length(btrim(display_name)) between 1 and 80),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
comment on table public.profiles is 'Minimal per-user profile. The id is the stable Supabase user id.';

create trigger profiles_touch before update on public.profiles
  for each row execute function private.touch_updated_at();

-- Who may manage content. There is intentionally no INSERT/UPDATE/DELETE policy for clients:
-- rows are created only by private.grant_admin(), callable from the SQL editor / service role.
create table public.administrator_roles (
  user_id    uuid primary key references auth.users (id) on delete cascade,
  granted_at timestamptz not null default now(),
  note       text check (note is null or char_length(note) <= 200)
);

-- Students who redeemed the class join code. Needed to read restricted materials.
create table public.class_enrollments (
  user_id     uuid primary key references auth.users (id) on delete cascade,
  enrolled_at timestamptz not null default now()
);

-- Create the profile automatically when Supabase Auth creates a user.
create function private.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id) values (new.id) on conflict (id) do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function private.handle_new_user();

-- ---------------------------------------------------------------------------
-- Role helpers (used by RLS). SECURITY DEFINER so they can read the role tables
-- without granting students access to them.
-- ---------------------------------------------------------------------------
create function private.is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.administrator_roles r where r.user_id = (select auth.uid())
  );
$$;

create function private.is_enrolled()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select (select auth.uid()) is not null and (
    exists (select 1 from public.class_enrollments e where e.user_id = (select auth.uid()))
    or private.is_admin()
  );
$$;

revoke all on function private.is_admin() from public;
revoke all on function private.is_enrolled() from public;
grant execute on function private.is_admin() to anon, authenticated, service_role;
grant execute on function private.is_enrolled() to anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Shared content
-- ---------------------------------------------------------------------------
create table public.courses (
  id          uuid primary key default gen_random_uuid(),
  slug        text not null unique check (slug ~ '^[a-z0-9][a-z0-9-]{1,62}$'),
  title       text not null check (char_length(btrim(title)) between 1 and 120),
  subtitle    text check (subtitle is null or char_length(subtitle) <= 200),
  icon_name   text not null default 'CourseStudy' check (icon_name ~ '^[A-Za-z0-9._-]{1,64}$'),
  color_key   text not null default 'forest'
              check (color_key in ('dusk', 'moss', 'rust', 'forest', 'berry', 'lake', 'honey', 'bark', 'lavender')),
  sort_order  integer not null default 0,
  is_archived boolean not null default false,
  created_by  uuid references auth.users (id) on delete set null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create table public.lessons (
  id                uuid primary key default gen_random_uuid(),
  course_id         uuid not null references public.courses (id) on delete restrict,
  title             text not null check (char_length(btrim(title)) between 1 and 200),
  description       text not null default '' check (char_length(description) <= 20000),
  category          public.lesson_category not null,
  status            public.lesson_status not null default 'draft',
  week              smallint check (week is null or week between 0 and 60),
  module_title      text check (module_title is null or char_length(module_title) <= 120),
  sort_order        integer not null default 0,
  -- Optional scheduled publication: a published lesson stays hidden from students until then.
  available_from    timestamptz,
  due_at            timestamptz,
  estimated_minutes integer check (estimated_minutes is null or estimated_minutes between 1 and 10000),
  -- 0 = no numbered exercises; the lesson is completed manually.
  exercise_count    integer not null default 0 check (exercise_count between 0 and 500),
  published_at      timestamptz,
  archived_at       timestamptz,
  created_by        uuid references auth.users (id) on delete set null,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  constraint lessons_due_after_available check (due_at is null or available_from is null or due_at >= available_from),
  constraint lessons_published_has_timestamp check (status = 'draft' or published_at is not null),
  constraint lessons_archived_has_timestamp check ((status = 'archived') = (archived_at is not null))
);
comment on column public.lessons.category is 'Every lesson, published or not, has exactly one valid category.';

create index lessons_course_order_idx on public.lessons (course_id, week, sort_order);
create index lessons_status_category_idx on public.lessons (status, category);

create table public.lesson_prerequisites (
  lesson_id       uuid not null references public.lessons (id) on delete cascade,
  prerequisite_id uuid not null references public.lessons (id) on delete cascade,
  primary key (lesson_id, prerequisite_id),
  constraint lesson_prerequisites_not_self check (lesson_id <> prerequisite_id)
);
create index lesson_prerequisites_prereq_idx on public.lesson_prerequisites (prerequisite_id);

-- The attachment id is the stable reference. Replacing the PDF bumps `version` and moves
-- `storage_path`; the row (and anything pointing at it) stays the same.
create table public.lesson_attachments (
  id           uuid primary key default gen_random_uuid(),
  lesson_id    uuid not null references public.lessons (id) on delete cascade,
  title        text not null check (char_length(btrim(title)) between 1 and 200),
  description  text not null default '' check (char_length(description) <= 2000),
  visibility   public.attachment_visibility not null default 'restricted',
  storage_path text not null unique,
  file_name    text not null check (char_length(file_name) between 1 and 255 and position('/' in file_name) = 0),
  mime_type    text not null check (mime_type = 'application/pdf'),
  byte_size    bigint not null check (byte_size between 1 and 52428800),
  version      integer not null default 1 check (version >= 1),
  sort_order   integer not null default 0,
  uploaded_by  uuid references auth.users (id) on delete set null,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  constraint lesson_attachments_path_format
    check (storage_path = lesson_id::text || '/' || id::text || '/v' || version::text || '.pdf')
);
create index lesson_attachments_lesson_idx on public.lesson_attachments (lesson_id, sort_order);

-- ---------------------------------------------------------------------------
-- Personal data
-- ---------------------------------------------------------------------------

-- A subscription is a student's choice to follow an OPTIONAL lesson. Unsubscribing flips
-- is_active; the row and the student's progress are kept, so resubscribing restores both.
create table public.lesson_subscriptions (
  user_id         uuid not null default auth.uid() references auth.users (id) on delete cascade,
  lesson_id       uuid not null references public.lessons (id) on delete cascade,
  is_active       boolean not null default true,
  subscribed_at   timestamptz not null default now(),
  unsubscribed_at timestamptz,
  updated_at      timestamptz not null default now(),
  primary key (user_id, lesson_id)
);
create index lesson_subscriptions_lesson_idx on public.lesson_subscriptions (lesson_id);

-- Progress belongs to one student and one lesson. ON DELETE RESTRICT on the lesson: a lesson
-- that any student has worked on can be archived but never silently deleted.
create table public.lesson_progress (
  user_id             uuid not null default auth.uid() references auth.users (id) on delete cascade,
  lesson_id           uuid not null references public.lessons (id) on delete restrict,
  status              public.progress_status not null default 'not_started',
  completed_exercises integer not null default 0 check (completed_exercises between 0 and 500),
  notes               text not null default '' check (char_length(notes) <= 20000),
  last_activity_at    timestamptz not null default now(),
  completed_at        timestamptz,
  -- When the change was made on the device; used for last-writer-wins between devices.
  client_modified_at  timestamptz not null default now(),
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  primary key (user_id, lesson_id),
  constraint lesson_progress_not_started_has_no_exercises check (status <> 'not_started' or completed_exercises = 0),
  constraint lesson_progress_completed_has_timestamp check ((status = 'completed') = (completed_at is not null))
);
create index lesson_progress_lesson_idx on public.lesson_progress (lesson_id);

-- ---------------------------------------------------------------------------
-- Visibility helper: can students see this lesson right now?
-- ---------------------------------------------------------------------------
create function private.lesson_is_visible(p_status public.lesson_status, p_available_from timestamptz)
returns boolean
language sql
stable
set search_path = ''
as $$
  select p_status in ('published', 'archived') and (p_available_from is null or p_available_from <= now());
$$;
grant execute on function private.lesson_is_visible(public.lesson_status, timestamptz) to anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Content triggers
-- ---------------------------------------------------------------------------
create function private.courses_before_write()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    new.created_by := auth.uid();
    new.created_at := now();
  else
    new.created_by := old.created_by;
    new.created_at := old.created_at;
  end if;
  new.updated_at := now();
  return new;
end;
$$;

create trigger courses_before_write before insert or update on public.courses
  for each row execute function private.courses_before_write();

create function private.lessons_before_write()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_course_archived boolean;
begin
  if tg_op = 'INSERT' then
    new.created_by := auth.uid();
    new.created_at := now();
    new.published_at := null;
    new.archived_at := null;
  else
    new.id := old.id;
    new.created_by := old.created_by;
    new.created_at := old.created_at;
    new.published_at := old.published_at;
    new.archived_at := old.archived_at;
  end if;
  new.updated_at := now();

  -- Archiving a lesson students never saw would publish it into their history.
  if new.status = 'archived' and new.published_at is null then
    raise exception 'Only a lesson that was published can be archived; delete the draft instead'
      using errcode = 'check_violation';
  end if;

  -- Server-controlled lifecycle timestamps.
  if new.status = 'published' and new.published_at is null then
    new.published_at := now();
  end if;
  if new.status = 'archived' then
    new.archived_at := coalesce(new.archived_at, now());
  else
    new.archived_at := null;
  end if;

  if new.status = 'published' and (tg_op = 'INSERT' or old.status <> 'published') then
    select c.is_archived into v_course_archived from public.courses c where c.id = new.course_id;
    if coalesce(v_course_archived, true) then
      raise exception 'Cannot publish a lesson in an archived course'
        using errcode = 'check_violation';
    end if;
  end if;

  return new;
end;
$$;

create trigger lessons_before_write before insert or update on public.lessons
  for each row execute function private.lessons_before_write();

-- Changing a lesson from required to optional must not make started work vanish from a
-- student's workload, so students who already have progress are subscribed automatically.
-- (optional -> required needs nothing: required lessons are always in the workload.)
create function private.lessons_after_category_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.category = 'required' and new.category = 'optional' and new.status = 'published' then
    insert into public.lesson_subscriptions (user_id, lesson_id, is_active)
    select p.user_id, p.lesson_id, true
      from public.lesson_progress p
     where p.lesson_id = new.id
       and (p.status <> 'not_started' or p.notes <> '')
    on conflict (user_id, lesson_id)
      do update set is_active = true, unsubscribed_at = null;
  end if;
  return null;
end;
$$;

create trigger lessons_after_category_change after update of category on public.lessons
  for each row when (old.category is distinct from new.category)
  execute function private.lessons_after_category_change();

create function private.attachments_before_write()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    new.uploaded_by := auth.uid();
    new.created_at := now();
  else
    if new.id <> old.id or new.lesson_id <> old.lesson_id then
      raise exception 'An attachment cannot move to another id or lesson'
        using errcode = 'check_violation';
    end if;
    if new.version < old.version then
      raise exception 'Attachment version cannot go backwards'
        using errcode = 'check_violation';
    end if;
    if new.storage_path <> old.storage_path then
      new.uploaded_by := auth.uid();
    else
      new.uploaded_by := old.uploaded_by;
    end if;
    new.created_at := old.created_at;
  end if;
  new.updated_at := now();
  return new;
end;
$$;

create trigger attachments_before_write before insert or update on public.lesson_attachments
  for each row execute function private.attachments_before_write();

-- ---------------------------------------------------------------------------
-- Personal-data triggers
-- ---------------------------------------------------------------------------
create function private.subscriptions_before_write()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_lesson record;
  v_activating boolean;
begin
  if tg_op = 'UPDATE' and (new.user_id <> old.user_id or new.lesson_id <> old.lesson_id) then
    raise exception 'Subscription owner and lesson are immutable' using errcode = 'check_violation';
  end if;

  select l.category, l.status, l.available_from into v_lesson
    from public.lessons l where l.id = new.lesson_id;
  if not found then
    raise exception 'Lesson not found' using errcode = 'foreign_key_violation';
  end if;

  v_activating := new.is_active and (tg_op = 'INSERT' or not old.is_active);

  if v_activating then
    if v_lesson.status <> 'published'
       or not private.lesson_is_visible(v_lesson.status, v_lesson.available_from) then
      raise exception 'Only published lessons can be subscribed to' using errcode = 'check_violation';
    end if;
    if v_lesson.category = 'required' then
      raise exception 'Required lessons are always in your workload; no subscription is needed'
        using errcode = 'check_violation';
    end if;
    new.subscribed_at := now();
    new.unsubscribed_at := null;
  elsif not new.is_active and (tg_op = 'INSERT' or old.is_active) then
    if v_lesson.category = 'required' then
      raise exception 'Required lessons cannot be removed from your workload'
        using errcode = 'check_violation';
    end if;
    new.unsubscribed_at := now();
    if tg_op = 'UPDATE' then
      new.subscribed_at := old.subscribed_at;
    end if;
  elsif tg_op = 'UPDATE' then
    new.subscribed_at := old.subscribed_at;
    new.unsubscribed_at := old.unsubscribed_at;
  end if;

  new.updated_at := now();
  return new;
end;
$$;

create trigger subscriptions_before_write before insert or update on public.lesson_subscriptions
  for each row execute function private.subscriptions_before_write();

create function private.progress_before_write()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_lesson record;
begin
  if tg_op = 'UPDATE' and (new.user_id <> old.user_id or new.lesson_id <> old.lesson_id) then
    raise exception 'Progress owner and lesson are immutable' using errcode = 'check_violation';
  end if;

  select l.status, l.available_from, l.exercise_count into v_lesson
    from public.lessons l where l.id = new.lesson_id;
  if not found then
    raise exception 'Lesson not found' using errcode = 'foreign_key_violation';
  end if;
  if not private.lesson_is_visible(v_lesson.status, v_lesson.available_from) then
    raise exception 'Progress can only be recorded for published or archived lessons'
      using errcode = 'check_violation';
  end if;

  if new.completed_exercises > v_lesson.exercise_count then
    raise exception 'completed_exercises (%) exceeds the lesson''s % exercises',
      new.completed_exercises, v_lesson.exercise_count
      using errcode = 'check_violation';
  end if;

  -- completed_at is server-controlled.
  if new.status = 'completed' then
    if tg_op = 'UPDATE' and old.status = 'completed' then
      new.completed_at := old.completed_at;
    else
      new.completed_at := now();
    end if;
  else
    new.completed_at := null;
  end if;

  -- A device clock far in the future must not win every future conflict.
  if new.client_modified_at > now() + interval '5 minutes' then
    new.client_modified_at := now();
  end if;

  if tg_op = 'UPDATE' then
    new.created_at := old.created_at;
  else
    new.created_at := now();
  end if;
  new.last_activity_at := now();
  new.updated_at := now();
  return new;
end;
$$;

create trigger progress_before_write before insert or update on public.lesson_progress
  for each row execute function private.progress_before_write();

-- Trigger functions are never called directly.
revoke all on function private.touch_updated_at() from public;
revoke all on function private.handle_new_user() from public;
revoke all on function private.courses_before_write() from public;
revoke all on function private.lessons_before_write() from public;
revoke all on function private.lessons_after_category_change() from public;
revoke all on function private.attachments_before_write() from public;
revoke all on function private.subscriptions_before_write() from public;
revoke all on function private.progress_before_write() from public;
