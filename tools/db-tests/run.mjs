#!/usr/bin/env node
// Runs every supabase/tests/NN_*.sql suite and reports each `ok - …` assertion.
//
//   node run.mjs                       # PGlite: real Postgres 17 in WebAssembly, no Docker.
//                                      # Applies the Supabase shim, all migrations and seed.sql.
//   node run.mjs --database-url URL    # An existing database that already has the migrations,
//                                      # e.g. `supabase start` → postgresql://postgres:postgres@127.0.0.1:54322/postgres
//                                      # NEVER point this at production.
//
// Each suite runs as BEGIN; _helpers.sql; suite; ROLLBACK; so nothing is left behind.

import { readFileSync, readdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const supabaseDir = join(here, '..', '..', 'supabase');
const testsDir = join(supabaseDir, 'tests');
const migrationsDir = join(supabaseDir, 'migrations');

const args = process.argv.slice(2);
const urlFlag = args.indexOf('--database-url');
const databaseUrl = urlFlag >= 0 ? args[urlFlag + 1] : process.env.TEST_DATABASE_URL;
const only = args.find((a) => !a.startsWith('--') && a !== databaseUrl);

const read = (path) => readFileSync(path, 'utf8');
const sqlFiles = (dir) => readdirSync(dir).filter((f) => f.endsWith('.sql')).sort();

/** A tiny adapter so suites run the same way on PGlite and node-postgres. */
async function connect() {
  if (databaseUrl) {
    if (/supabase\.co|pooler\.supabase\.com/.test(databaseUrl) && !process.env.ALLOW_REMOTE_TEST_DB) {
      throw new Error('Refusing to run tests against a hosted Supabase database. ' +
        'Use a local `supabase start` database, or set ALLOW_REMOTE_TEST_DB=1 for a throwaway dev project.');
    }
    const { default: pg } = await import('pg');
    const client = new pg.Client({ connectionString: databaseUrl });
    let sink = () => {};
    client.on('notice', (n) => sink(n.message));
    await client.connect();
    return {
      label: 'existing database',
      exec: async (sql, onNotice = () => {}) => { sink = onNotice; try { await client.query(sql); } finally { sink = () => {}; } },
      close: () => client.end(),
      needsBootstrap: false,
    };
  }
  const { PGlite } = await import('@electric-sql/pglite');
  const db = new PGlite();
  return {
    label: 'PGlite (Postgres in WebAssembly)',
    exec: (sql, onNotice = () => {}) => db.exec(sql, { onNotice: (n) => onNotice(n.message) }),
    close: () => db.close(),
    needsBootstrap: true,
  };
}

const db = await connect();
console.log(`Database: ${db.label}`);

if (db.needsBootstrap) {
  await db.exec(read(join(here, 'supabase-shim.sql')));
  for (const file of sqlFiles(migrationsDir)) {
    try {
      await db.exec(read(join(migrationsDir, file)));
    } catch (error) {
      console.error(`Migration ${file} failed: ${error.message}`);
      process.exit(1);
    }
    console.log(`  applied ${file}`);
  }
  await db.exec(read(join(supabaseDir, 'seed.sql')));
  console.log('  applied seed.sql');
}

const helpers = read(join(testsDir, '_helpers.sql'));
const suites = sqlFiles(testsDir).filter((f) => /^\d\d_/.test(f) && (!only || f.includes(only)));
let passed = 0;
let failedSuites = 0;

for (const suite of suites) {
  console.log(`\n# ${suite}`);
  const notices = [];
  try {
    await db.exec(`begin;\n${helpers}\n${read(join(testsDir, suite))}\nrollback;`, (m) => {
      if (m.startsWith('ok - ')) { passed += 1; console.log(`  ✓ ${m.slice(5)}`); } else notices.push(m);
    });
  } catch (error) {
    failedSuites += 1;
    console.log(`  ✗ ${error.message}`);
    if (error.where) console.log(`    at ${error.where.split('\n')[0]}`);
    await db.exec('rollback;').catch(() => {});
  }
}

await db.close();
console.log(`\n${passed} assertions passed, ${failedSuites} of ${suites.length} suites failed.`);
process.exit(failedSuites === 0 ? 0 : 1);
