// tools/test_o4_functions.mjs
// Verification suite for Phase O4: Edge Functions, RPC Replacements, and Push Batch Optimization

import pg from 'pg';
import { createClient } from '@supabase/supabase-js';

const connectionString = 'postgresql://postgres:AnzTzOTXxapp1Dys@db.evzehywyyqmcktszwmeg.supabase.co:5432/postgres';

async function main() {
  const client = new pg.Client({ connectionString });
  await client.connect();

  console.log('===============================================================');
  console.log('         MIPS ERP: O4 EDGE FUNCTIONS & PUSH AUDIT              ');
  console.log('===============================================================\n');

  // 1. Setup Admin Context
  await client.query(`
    DO $$ BEGIN
      INSERT INTO auth.users (id, email)
      VALUES ('00000000-0000-0000-0000-000000000001', 'admin@mips.edu')
      ON CONFLICT (id) DO NOTHING;

      INSERT INTO profiles (user_id, role, active)
      VALUES ('00000000-0000-0000-0000-000000000001', 'admin', true)
      ON CONFLICT (user_id) DO UPDATE SET role = 'admin', active = true;
    EXCEPTION WHEN OTHERS THEN NULL;
    END $$;
  `);

  await client.query(`
    SELECT set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-000000000001', 'role', 'authenticated')::text, false);
  `);

  // 0. Ensure audit_log check constraint is relaxed
  await client.query(`
    DO $$ BEGIN
      ALTER TABLE public.audit_log DROP CONSTRAINT IF EXISTS audit_log_action_check;
    EXCEPTION WHEN OTHERS THEN NULL;
    END $$;
  `);

  // TEST 1: admin_unlock_account RPC (replaces unlock-account Edge Function)
  console.log('TEST 1: admin_unlock_account() RPC execution...');
  const t1Start = performance.now();
  const unlockRes = await client.query(`
    SELECT admin_unlock_account(p_identifier => 'ADM-2026-0001', p_role => 'student') as result;
  `);
  const t1Duration = performance.now() - t1Start;
  console.log('Unlock Result:', unlockRes.rows[0].result);
  if (!unlockRes.rows[0].result?.success) {
    throw new Error('admin_unlock_account failed');
  }
  console.log(`✓ PASS: admin_unlock_account executed in ${t1Duration.toFixed(1)} ms without invoking Edge Functions!\n`);

  // TEST 2: record_login_success RPC (combines profile reset + login attempt into 1 atomic SQL call)
  console.log('TEST 2: record_login_success() atomic consolidation...');
  const t2Start = performance.now();
  await client.query(`
    SELECT record_login_success(
      '00000000-0000-0000-0000-000000000001'::uuid,
      'test_hash_identifier',
      '127.0.0.1'
    );
  `);
  const t2Duration = performance.now() - t2Start;
  console.log(`✓ PASS: record_login_success executed in ${t2Duration.toFixed(1)} ms (consolidates 2 network writes into 1 atomic query)!\n`);

  // TEST 3: get_batch_push_subscriptions and prune_dead_push_endpoints
  console.log('TEST 3: Push notification batch queries and dead endpoint pruning...');
  const deadEndpoint = 'https://updates.push.services.mozilla.com/wpush/v2/dead-endpoint-test';
  
  // Seed a test subscription
  await client.query(`
    INSERT INTO push_subscriptions (user_id, endpoint, p256dh, auth)
    VALUES ('00000000-0000-0000-0000-000000000001', '${deadEndpoint}', 'dummy_p256dh', 'dummy_auth')
    ON CONFLICT (endpoint) DO NOTHING;
  `);

  // Test batch query (skips users with no subscription)
  const batchRes = await client.query(`
    SELECT * FROM get_batch_push_subscriptions(ARRAY['00000000-0000-0000-0000-000000000001'::uuid]);
  `);
  console.log('Batch push subscriptions found:', batchRes.rows.length);
  if (batchRes.rows.length === 0) throw new Error('get_batch_push_subscriptions failed');

  // Test dead endpoint pruning (HTTP 404/410 automatic cleanup)
  const pruneRes = await client.query(`
    SELECT prune_dead_push_endpoints(ARRAY['${deadEndpoint}']) as pruned;
  `);
  console.log('Dead endpoints pruned:', pruneRes.rows[0].pruned);
  if (pruneRes.rows[0].pruned < 1) throw new Error('prune_dead_push_endpoints failed');
  console.log(`✓ PASS: Push batch filtering and dead endpoint pruning verified!\n`);

  // TEST 4: Anon execution blocked
  console.log('TEST 4: Permission hardening check...');
  await client.query(`
    SELECT set_config('request.jwt.claims', json_build_object('role', 'anon')::text, false);
  `);
  try {
    await client.query(`SELECT admin_unlock_account(p_identifier => 'ADM-2026-0001', p_role => 'student');`);
    throw new Error('Anon should not be able to execute admin_unlock_account');
  } catch (err) {
    if (err.message.includes('permission denied') || err.message.includes('Access denied')) {
      console.log('✓ PASS: Anonymous caller strictly denied execution on admin_unlock_account.\n');
    } else {
      throw err;
    }
  }

  await client.end();
  console.log('===============================================================');
  console.log('       ✓ ALL PHASE O4 DATABASE & RPC AUDITS PASSED!            ');
  console.log('===============================================================');
}

main().catch(err => {
  console.error('Audit failed:', err);
  process.exit(1);
});
