import { PGlite } from '@electric-sql/pglite';
import { pgcrypto } from '@electric-sql/pglite/contrib/pgcrypto';
import { uuid_ossp } from '@electric-sql/pglite/contrib/uuid_ossp';
import fs from 'fs';
import path from 'path';

const migrationsDir = path.resolve('../supabase/migrations');
const files = fs.readdirSync(migrationsDir)
  .filter(f => f.endsWith('.sql') && f.startsWith('00') && !f.includes('0021')) // Test standard 0001-0020 chain
  .sort();

console.log(`Found ${files.length} migration files in ${migrationsDir}`);

async function run() {
  const db = new PGlite({
    extensions: {
      uuid_ossp,
      pgcrypto,
    }
  });

  // Setup Supabase environment mocks
  await db.exec(`
    DO $$ BEGIN
      CREATE ROLE anon NOLOGIN;
    EXCEPTION WHEN duplicate_object THEN NULL; END $$;

    DO $$ BEGIN
      CREATE ROLE authenticated NOLOGIN;
    EXCEPTION WHEN duplicate_object THEN NULL; END $$;

    DO $$ BEGIN
      CREATE ROLE service_role NOLOGIN;
    EXCEPTION WHEN duplicate_object THEN NULL; END $$;

    CREATE SCHEMA IF NOT EXISTS auth;
    CREATE TABLE IF NOT EXISTS auth.users (
      id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
      instance_id uuid,
      aud varchar(255),
      role varchar(255),
      email varchar(255),
      encrypted_password varchar(255),
      email_confirmed_at timestamptz,
      created_at timestamptz DEFAULT now(),
      updated_at timestamptz DEFAULT now()
    );

    CREATE OR REPLACE FUNCTION uuid_generate_v4() RETURNS uuid AS $$
      SELECT gen_random_uuid();
    $$ LANGUAGE sql;

    CREATE OR REPLACE FUNCTION auth.uid() RETURNS uuid AS $$
      SELECT 'a0000000-0000-0000-0000-000000000001'::uuid;
    $$ LANGUAGE sql STABLE;

    CREATE OR REPLACE FUNCTION auth.role() RETURNS text AS $$
      SELECT 'authenticated'::text;
    $$ LANGUAGE sql STABLE;

    CREATE OR REPLACE FUNCTION auth.jwt() RETURNS jsonb AS $$
      SELECT '{"role": "authenticated", "sub": "a0000000-0000-0000-0000-000000000001"}'::jsonb;
    $$ LANGUAGE sql STABLE;

    CREATE SCHEMA IF NOT EXISTS cron;
    CREATE TABLE IF NOT EXISTS cron.job (
      jobid bigint PRIMARY KEY,
      schedule text,
      command text,
      jobname text
    );
    CREATE OR REPLACE FUNCTION cron.schedule(name text, schedule text, command text) RETURNS bigint AS $$
      BEGIN RETURN 1; END;
    $$ LANGUAGE plpgsql;
    CREATE OR REPLACE FUNCTION cron.unschedule(name text) RETURNS boolean AS $$
      BEGIN RETURN true; END;
    $$ LANGUAGE plpgsql;
  `);

  console.log('✓ Supabase test harness initialized.\n');

  const results = [];

  for (const file of files) {
    const filePath = path.join(migrationsDir, file);
    let sql = fs.readFileSync(filePath, 'utf-8');
    sql = sql.replace(/CREATE EXTENSION IF NOT EXISTS "uuid-ossp";?/gi, '-- (uuid-ossp mocked)');
    process.stdout.write(`Applying ${file}... `);

    try {
      await db.exec(sql);
      console.log('✓ PASS');
      results.push({ file, status: 'PASS' });
    } catch (err) {
      console.log('✗ FAIL');
      console.error(`   Error in ${file}:`, err.message);
      if (err.position) {
        const pos = parseInt(err.position, 10);
        const snippet = sql.substring(Math.max(0, pos - 150), Math.min(sql.length, pos + 150));
        console.error(`   Near position ${pos}:\n--- Snippet ---\n${snippet}\n--- End Snippet ---`);
      }
      results.push({ file, status: 'FAIL', error: err.message });
      break;
    }
  }

  console.log('\n--- MIGRATION RUN SUMMARY ---');
  for (const r of results) {
    console.log(`${r.status === 'PASS' ? '✓' : '✗'} ${r.file}: ${r.status}${r.error ? ' (' + r.error + ')' : ''}`);
  }
}

run().catch(err => {
  console.error('Fatal runner error:', err);
  process.exit(1);
});
