-- ============================================================================
-- API functions and views.
--
-- Student-facing functions are SECURITY INVOKER: they run under the caller's RLS and use
-- auth.uid() — they never accept a user id. The few SECURITY DEFINER functions check the
-- caller explicitly and touch only private tables.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- Active workload: published required lessons + published optional lessons with an active
-- subscription. Mirrors `Workload` in StudyDomain.
-- ---------------------------------------------------------------------------
create view public.my_workload
with (security_invoker = true)
as
select l.id as lesson_id,
       l.course_id,
       l.category,
       l.due_at,
       l.exercise_count
  from public.lessons l
 where l.status = 'published'
   and private.lesson_is_visible(l.status, l.available_from)
   and (
     l.category = 'required'
     or exists (
       select 1 from public.lesson_subscriptions s
        where s.lesson_id = l.id
          and s.user_id = (select auth.uid())
          and s.is_active
     )
   );

revoke all on public.my_workload from anon, authenticated;
grant select on public.my_workload to authenticated;

-- ---------------------------------------------------------------------------
-- Subscriptions: idempotent upsert of the caller's own row.
-- ---------------------------------------------------------------------------
create function public.set_lesson_subscription(p_lesson_id uuid, p_active boolean)
returns public.lesson_subscriptions
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_row public.lesson_subscriptions;
begin
  if v_uid is null then
    raise exception 'Sign in required' using errcode = '28000';
  end if;

  insert into public.lesson_subscriptions as s (user_id, lesson_id, is_active)
  values (v_uid, p_lesson_id, p_active)
  on conflict (user_id, lesson_id) do update
    set is_active = excluded.is_active
    where s.is_active is distinct from excluded.is_active
  returning * into v_row;

  if v_row.user_id is null then          -- already in the requested state: no-op
    select * into v_row from public.lesson_subscriptions
     where user_id = v_uid and lesson_id = p_lesson_id;
  end if;
  return v_row;
end;
$$;

-- ---------------------------------------------------------------------------
-- Progress: last-writer-wins by the device timestamp, so an offline edit replayed late
-- never overwrites a newer edit from another device, and retries are harmless.
-- ---------------------------------------------------------------------------
create function public.set_lesson_progress(
  p_lesson_id uuid,
  p_status public.progress_status,
  p_completed_exercises integer,
  p_notes text,
  p_client_modified_at timestamptz
)
returns public.lesson_progress
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_row public.lesson_progress;
begin
  if v_uid is null then
    raise exception 'Sign in required' using errcode = '28000';
  end if;

  insert into public.lesson_progress as p
         (user_id, lesson_id, status, completed_exercises, notes, client_modified_at)
  values (v_uid, p_lesson_id, p_status, p_completed_exercises, coalesce(p_notes, ''),
          coalesce(p_client_modified_at, now()))
  on conflict (user_id, lesson_id) do update
    set status              = excluded.status,
        completed_exercises = excluded.completed_exercises,
        notes               = excluded.notes,
        client_modified_at  = excluded.client_modified_at
    where p.client_modified_at <= excluded.client_modified_at
  returning * into v_row;

  if v_row.user_id is null then          -- stale write: keep and return the newer row
    select * into v_row from public.lesson_progress
     where user_id = v_uid and lesson_id = p_lesson_id;
  end if;
  return v_row;
end;
$$;

-- ---------------------------------------------------------------------------
-- Class enrollment
-- ---------------------------------------------------------------------------
create table private.class_settings (
  id              boolean primary key default true check (id),
  join_code_salt  text not null,
  join_code_hash  text not null,
  updated_at      timestamptz not null default now()
);

create table private.join_attempts (
  user_id      uuid not null references auth.users (id) on delete cascade,
  attempted_at timestamptz not null default now(),
  succeeded    boolean not null
);
create index join_attempts_user_time_idx on private.join_attempts (user_id, attempted_at);

create function private.normalize_join_code(p_code text)
returns text
language sql
immutable
set search_path = ''
as $$
  select upper(regexp_replace(coalesce(p_code, ''), '[\s-]', '', 'g'));
$$;

create function private.hash_join_code(p_salt text, p_code text)
returns text
language sql
immutable
set search_path = ''
as $$
  select encode(sha256(convert_to(p_salt || ':' || private.normalize_join_code(p_code), 'UTF8')), 'hex');
$$;

-- Admin: set or rotate the class code. Only a salted hash is stored.
create function public.set_class_join_code(p_code text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_salt text := gen_random_uuid()::text;
begin
  if not private.is_admin() then
    raise exception 'Administrator role required' using errcode = '42501';
  end if;
  if char_length(private.normalize_join_code(p_code)) not between 8 and 64 then
    raise exception 'The class code must have 8–64 letters or digits' using errcode = 'check_violation';
  end if;

  insert into private.class_settings (id, join_code_salt, join_code_hash, updated_at)
  values (true, v_salt, private.hash_join_code(v_salt, p_code), now())
  on conflict (id) do update
    set join_code_salt = excluded.join_code_salt,
        join_code_hash = excluded.join_code_hash,
        updated_at = now();
end;
$$;

create function public.class_join_code_updated_at()
returns timestamptz
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not private.is_admin() then
    raise exception 'Administrator role required' using errcode = '42501';
  end if;
  return (select updated_at from private.class_settings where id);
end;
$$;

-- Student: redeem the class code. Returns a status instead of raising, so failed attempts
-- are recorded (an exception would roll the attempt back) and rate limiting works.
create function public.join_class(p_code text)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_settings private.class_settings;
  v_failures integer;
begin
  if v_uid is null then
    raise exception 'Sign in required' using errcode = '28000';
  end if;
  if exists (select 1 from public.class_enrollments where user_id = v_uid) then
    return 'already_joined';
  end if;

  select count(*) into v_failures
    from private.join_attempts
   where user_id = v_uid and not succeeded and attempted_at > now() - interval '1 hour';
  if v_failures >= 10 then
    return 'rate_limited';
  end if;

  select * into v_settings from private.class_settings where id;
  if not found then
    return 'not_configured';
  end if;

  if private.hash_join_code(v_settings.join_code_salt, p_code) <> v_settings.join_code_hash then
    insert into private.join_attempts (user_id, succeeded) values (v_uid, false);
    return 'invalid_code';
  end if;

  insert into private.join_attempts (user_id, succeeded) values (v_uid, true);
  insert into public.class_enrollments (user_id) values (v_uid) on conflict do nothing;
  return 'joined';
end;
$$;

-- ---------------------------------------------------------------------------
-- Data export: everything stored about the caller, as JSON. Runs under RLS.
-- ---------------------------------------------------------------------------
create function public.export_my_data()
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object(
    'exported_at', now(),
    'user_id', auth.uid(),
    'profile', (select to_jsonb(p) from public.profiles p where p.id = auth.uid()),
    'class_enrollment', (select to_jsonb(e) from public.class_enrollments e where e.user_id = auth.uid()),
    'administrator', exists (select 1 from public.administrator_roles r where r.user_id = auth.uid()),
    'subscriptions', coalesce((
      select jsonb_agg(to_jsonb(s) order by s.subscribed_at)
        from public.lesson_subscriptions s where s.user_id = auth.uid()), '[]'::jsonb),
    'progress', coalesce((
      select jsonb_agg(to_jsonb(p) order by p.updated_at)
        from public.lesson_progress p where p.user_id = auth.uid()), '[]'::jsonb)
  );
$$;

-- ---------------------------------------------------------------------------
-- Trusted administration (SQL editor / service role ONLY)
-- ---------------------------------------------------------------------------
create function private.grant_admin(p_user_id uuid, p_note text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (select 1 from auth.users where id = p_user_id) then
    raise exception 'No auth user with id %', p_user_id using errcode = 'no_data_found';
  end if;
  insert into public.administrator_roles (user_id, note) values (p_user_id, p_note)
  on conflict (user_id) do update set note = excluded.note;
end;
$$;

create function private.revoke_admin(p_user_id uuid)
returns void
language sql
security definer
set search_path = ''
as $$
  delete from public.administrator_roles where user_id = p_user_id;
$$;

-- ---------------------------------------------------------------------------
-- Function privileges. Postgres grants EXECUTE to PUBLIC by default; undo that.
-- ---------------------------------------------------------------------------
revoke all on function public.set_lesson_subscription(uuid, boolean) from public, anon;
revoke all on function public.set_lesson_progress(uuid, public.progress_status, integer, text, timestamptz) from public, anon;
revoke all on function public.set_class_join_code(text) from public, anon;
revoke all on function public.class_join_code_updated_at() from public, anon;
revoke all on function public.join_class(text) from public, anon;
revoke all on function public.export_my_data() from public, anon;
revoke all on function private.normalize_join_code(text) from public;
revoke all on function private.hash_join_code(text, text) from public;
revoke all on function private.grant_admin(uuid, text) from public, anon, authenticated;
revoke all on function private.revoke_admin(uuid) from public, anon, authenticated;

grant execute on function public.set_lesson_subscription(uuid, boolean) to authenticated;
grant execute on function public.set_lesson_progress(uuid, public.progress_status, integer, text, timestamptz) to authenticated;
grant execute on function public.set_class_join_code(text) to authenticated;
grant execute on function public.class_join_code_updated_at() to authenticated;
grant execute on function public.join_class(text) to authenticated;
grant execute on function public.export_my_data() to authenticated;
grant execute on function private.grant_admin(uuid, text) to service_role;
grant execute on function private.revoke_admin(uuid) to service_role;

revoke all on private.class_settings, private.join_attempts from public, anon, authenticated;
