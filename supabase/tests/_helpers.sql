-- ============================================================================
-- Test helpers, loaded by tools/db-tests/run.mjs at the start of every suite. Each suite
-- runs inside one transaction that is rolled back, so nothing persists — not even this
-- schema — on a real database.
--
--   select tests.authenticate_as(uid);  -- act as a signed-in user (role authenticated)
--   select tests.as_anon();             -- act as a visitor (role anon)
--   reset role;                         -- back to the database owner (bypasses RLS)
-- ============================================================================

create schema tests;
grant usage on schema tests to anon, authenticated, service_role;

-- Synthetic users only (example.test is a reserved test domain).
create function tests.create_user(p_label text) returns uuid
language plpgsql as $$
declare
  v_id uuid := gen_random_uuid();
begin
  insert into auth.users (id, email) values (v_id, p_label || '@example.test');
  return v_id;
end $$;

create function tests.authenticate_as(p_user uuid) returns void
language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', p_user::text, true);
  execute 'set local role authenticated';
end $$;

create function tests.as_anon() returns void
language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
  perform set_config('request.jwt.claim.sub', '', true);
  execute 'set local role anon';
end $$;

create function tests.make_admin(p_user uuid) returns void
language sql as $$
  insert into public.administrator_roles (user_id, note) values (p_user, 'test admin');
$$;

create function tests.ok(p_condition boolean, p_name text) returns void
language plpgsql as $$
begin
  if p_condition is distinct from true then
    raise exception 'not ok - %', p_name;
  end if;
  raise notice 'ok - %', p_name;
end $$;

create function tests.is(p_got anyelement, p_want anyelement, p_name text) returns void
language plpgsql as $$
begin
  if p_got is distinct from p_want then
    raise exception 'not ok - % (got %, want %)', p_name, p_got, p_want;
  end if;
  raise notice 'ok - %', p_name;
end $$;

-- Runs p_sql in a subtransaction and expects it to fail (optionally with a message match).
create function tests.throws(p_sql text, p_name text, p_message_like text default null) returns void
language plpgsql as $$
begin
  begin
    execute p_sql;
  exception when others then
    if p_message_like is not null and sqlerrm not ilike '%' || p_message_like || '%' then
      raise exception 'not ok - % (raised "%", expected something like "%")', p_name, sqlerrm, p_message_like;
    end if;
    raise notice 'ok - % [%]', p_name, sqlerrm;
    return;
  end;
  raise exception 'not ok - % (no error was raised)', p_name;
end $$;

-- Runs p_sql and returns how many rows it touched (RLS silently filters UPDATE/DELETE).
create function tests.rows_affected(p_sql text) returns bigint
language plpgsql as $$
declare
  v_count bigint;
begin
  execute p_sql;
  get diagnostics v_count = row_count;
  return v_count;
end $$;

-- Named ids shared between steps of a suite (readable in any role).
create table tests.ctx (key text primary key, id uuid not null);
grant select on tests.ctx to anon, authenticated, service_role;

create function tests.remember(p_key text, p_id uuid) returns uuid
language sql as $$
  insert into tests.ctx (key, id) values (p_key, p_id) returning id;
$$;

create function tests.id(p_key text) returns uuid
language sql stable as $$
  select id from tests.ctx where key = p_key;
$$;

-- Seeded lessons (supabase/seed.sql).
insert into tests.ctx (key, id) values
  ('req_vectors',   '00000000-0000-4000-8000-0000000001a1'),  -- required, 8 exercises
  ('req_matrices',  '00000000-0000-4000-8000-0000000001a2'),  -- required, 10 exercises
  ('opt_determ',    '00000000-0000-4000-8000-0000000001a3'),  -- optional, 12 exercises
  ('req_logic',     '00000000-0000-4000-8000-0000000001b1'),  -- required, 6 exercises
  ('opt_puzzles',   '00000000-0000-4000-8000-0000000001b2'),  -- optional, no exercises
  ('opt_planning',  '00000000-0000-4000-8000-0000000001c1'),  -- optional, no exercises
  ('archived',      '00000000-0000-4000-8000-0000000001c2'),  -- optional, archived
  ('draft',         '00000000-0000-4000-8000-0000000001d1'),  -- required, draft
  ('course_la',     '00000000-0000-4000-8000-000000000c01');

grant execute on all functions in schema tests to anon, authenticated, service_role;
