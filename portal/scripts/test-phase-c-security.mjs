import { PGlite } from '@electric-sql/pglite';
import { pgcrypto } from '@electric-sql/pglite/contrib/pgcrypto';
import { uuid_ossp } from '@electric-sql/pglite/contrib/uuid_ossp';
import fs from 'fs';
import path from 'path';

async function run() {
  console.log('=== PHASE C: SECURITY VERIFICATION TEST SUITE ===\n');
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
      SELECT coalesce(current_setting('request.jwt.claim.sub', true), 'a0000000-0000-0000-0000-000000000001')::uuid;
    $$ LANGUAGE sql STABLE;

    CREATE OR REPLACE FUNCTION auth.role() RETURNS text AS $$
      SELECT coalesce(current_setting('request.jwt.claim.role', true), 'authenticated')::text;
    $$ LANGUAGE sql STABLE;
  `);

  // Apply migrations 0001 to 0020
  const dir = path.resolve('../supabase/migrations');
  const files = fs.readdirSync(dir).filter(f => f.endsWith('.sql') && f.startsWith('00') && !f.includes('0021')).sort();
  for (const file of files) {
    let sql = fs.readFileSync(path.join(dir, file), 'utf8');
    sql = sql.replace(/CREATE EXTENSION IF NOT EXISTS "uuid-ossp";?/gi, '-- (uuid-ossp mocked)');
    await db.exec(sql);
  }
  console.log('✓ All 20 migrations applied cleanly on fresh PGlite instance.\n');

  // Setup Users: Admin, Teacher, Student 1, Student 2
  const adminUid = 'a0000000-0000-0000-0000-000000000001';
  const teacherUid = 'a0000000-0000-0000-0000-000000000002';
  const student1Uid = 'a0000000-0000-0000-0000-000000000003';
  const student2Uid = 'a0000000-0000-0000-0000-000000000004';

  await db.query(`INSERT INTO auth.users (id, email) VALUES ($1, 'admin@mips.edu') ON CONFLICT (id) DO NOTHING;`, [adminUid]);
  await db.query(`INSERT INTO profiles (user_id, role, active) VALUES ($1, 'admin', true) ON CONFLICT (user_id) DO UPDATE SET role = 'admin', active = true;`, [adminUid]);

  const teacherRes = await db.query(`INSERT INTO teachers (name, login_username) VALUES ('Prof. Smith', 'prof_smith') RETURNING id;`);
  const teacherId = teacherRes.rows[0].id;
  await db.query(`INSERT INTO auth.users (id, email) VALUES ($1, 'teacher@mips.edu') ON CONFLICT (id) DO NOTHING;`, [teacherUid]);
  await db.query(`INSERT INTO profiles (user_id, role, teacher_id, active) VALUES ($1, 'teacher', $2, true);`, [teacherUid, teacherId]);

  const courseRes = await db.query(`
    INSERT INTO courses (name, code, course_type, structure, attendance_basis, total_fee_paise)
    VALUES ('B.Sc Imaging', 'BSCIMG', 'primary', 'semester', 'semester', 6000000)
    RETURNING id;
  `);
  const courseId = courseRes.rows[0].id;

  const batchRes = await db.query(`
    INSERT INTO batches (batch_name, course_id, start_date)
    VALUES ('Batch 2026 A', $1, '2026-06-01')
    RETURNING id;
  `, [courseId]);
  const batchId = batchRes.rows[0].id;

  const s1Res = await db.query(`INSERT INTO students (name, admission_number, course_id, batch_id) VALUES ('Alice', 'ADM-101', $1, $2) RETURNING id;`, [courseId, batchId]);
  const student1Id = s1Res.rows[0].id;
  await db.query(`INSERT INTO auth.users (id, email) VALUES ($1, 'alice@student.mips.edu') ON CONFLICT (id) DO NOTHING;`, [student1Uid]);
  await db.query(`INSERT INTO profiles (user_id, role, student_id, active) VALUES ($1, 'student', $2, true);`, [student1Uid, student1Id]);

  const s2Res = await db.query(`INSERT INTO students (name, admission_number, course_id, batch_id) VALUES ('Bob', 'ADM-102', $1, $2) RETURNING id;`, [courseId, batchId]);
  const student2Id = s2Res.rows[0].id;
  await db.query(`INSERT INTO auth.users (id, email) VALUES ($1, 'bob@student.mips.edu') ON CONFLICT (id) DO NOTHING;`, [student2Uid]);
  await db.query(`INSERT INTO profiles (user_id, role, student_id, active) VALUES ($1, 'student', $2, true);`, [student2Uid, student2Id]);

  // Helper to simulate JWT claim in session
  async function asUser(uid, role = 'authenticated') {
    if (role === 'service_role' || uid === null) {
      await db.exec(`
        RESET ROLE;
        SELECT set_config('request.jwt.claim.sub', '', false);
        SELECT set_config('request.jwt.claim.role', 'service_role', false);
      `);
    } else {
      await db.exec(`
        RESET ROLE;
        SELECT set_config('request.jwt.claim.sub', '${uid}', false);
        SELECT set_config('request.jwt.claim.role', '${role}', false);
        SET ROLE ${role};
      `);
    }
  }

  // =========================================================================
  // 1. soft_delete restrictions
  // =========================================================================
  console.log('1. Testing soft_delete restrictions...');
  await asUser(adminUid);
  const forbiddenTables = ['payments', 'receipts', 'fees', 'marks', 'results', 'exam_subjects'];
  for (const tbl of forbiddenTables) {
    try {
      await db.query(`SELECT soft_delete($1::text, 1::bigint);`, [tbl]);
      throw new Error(`FAILED: soft_delete should have rejected table "${tbl}"!`);
    } catch (err) {
      if (!err.message.includes('cannot be soft deleted') && !err.message.includes('forbidden')) {
        throw err;
      }
    }
  }
  console.log('✓ PASS: soft_delete successfully rejects payments, receipts, fees, marks, results, and exam_subjects.');

  // =========================================================================
  // 2. Role / is_admin guards on restricted functions
  // =========================================================================
  console.log('2. Testing role & is_admin guards on functions...');

  // Student trying to call admin / teacher functions
  await asUser(student1Uid);

  // report_shortage (admin / teacher only)
  try {
    await db.query(`SELECT * FROM report_shortage();`);
    throw new Error('FAILED: student should not be able to call report_shortage!');
  } catch (err) {
    if (!err.message.includes('Access denied')) throw err;
  }

  // preview_semester_promotion (admin only)
  try {
    await db.query(`SELECT preview_semester_promotion($1::bigint);`, [batchId]);
    throw new Error('FAILED: student should not be able to call preview_semester_promotion!');
  } catch (err) {
    if (!err.message.includes('Access denied')) throw err;
  }

  // preview_promote_year (admin only)
  try {
    await db.query(`SELECT preview_promote_year($1::bigint);`, [batchId]);
    throw new Error('FAILED: student should not be able to call preview_promote_year!');
  } catch (err) {
    if (!err.message.includes('Access denied')) throw err;
  }

  // list_unmarked_slots (admin / teacher only)
  try {
    await db.query(`SELECT * FROM list_unmarked_slots();`);
    throw new Error('FAILED: student should not be able to call list_unmarked_slots!');
  } catch (err) {
    if (!err.message.includes('Access denied')) throw err;
  }

  // get_dashboard_summary_counts (admin / teacher only)
  try {
    await db.query(`SELECT get_dashboard_summary_counts();`);
    throw new Error('FAILED: student should not be able to call get_dashboard_summary_counts!');
  } catch (err) {
    if (!err.message.includes('Access denied')) throw err;
  }

  // get_migration_reconciliation_report (admin only)
  try {
    await db.query(`SELECT get_migration_reconciliation_report();`);
    throw new Error('FAILED: student should not be able to call get_migration_reconciliation_report!');
  } catch (err) {
    if (!err.message.includes('Access denied')) throw err;
  }

  // audit_inconsistent_batch_semester_dates (admin only)
  try {
    await db.query(`SELECT * FROM audit_inconsistent_batch_semester_dates();`);
    throw new Error('FAILED: student should not be able to call audit_inconsistent_batch_semester_dates!');
  } catch (err) {
    if (!err.message.includes('Access denied')) throw err;
  }

  // student_semesters_summary: student cannot read another student's summary
  try {
    await db.query(`SELECT * FROM student_semesters_summary($1::bigint);`, [student2Id]);
    throw new Error('FAILED: student 1 should not be able to view student 2 semester summary!');
  } catch (err) {
    if (!err.message.includes('Access denied')) throw err;
  }

  console.log('✓ PASS: All role and admin guards are fully enforced.');

  // =========================================================================
  // 3. batch_periods RLS: SELECT for authenticated, writes for admin only
  // =========================================================================
  console.log('3. Testing batch_periods RLS policies...');
  // Close period 1 so next period date does not trigger trigger overlap check
  await asUser(adminUid, 'service_role');
  await db.query(`UPDATE batch_periods SET end_date = '2026-11-30' WHERE batch_id = $1 AND period_no = 1;`, [batchId]);

  // Student can SELECT
  await asUser(student1Uid);
  const selRes = await db.query(`SELECT count(*)::int as cnt FROM batch_periods;`);
  if (selRes.rows[0].cnt < 1) throw new Error('FAILED: authenticated student should be able to read batch_periods!');

  // Student CANNOT INSERT (RLS WITH CHECK fails for non-admin)
  try {
    await db.query(`INSERT INTO batch_periods (batch_id, period_type, period_no, start_date) VALUES ($1, 'semester', 2, '2026-12-01');`, [batchId]);
    throw new Error('FAILED: non-admin should not be able to insert into batch_periods!');
  } catch (err) {
    if (!err.message.includes('violates row-level security policy') && !err.message.includes('permission denied')) {
      throw err;
    }
  }

  // Admin CAN write (RLS WITH CHECK passes for admin)
  await asUser(adminUid);
  await db.query(`INSERT INTO batch_periods (batch_id, period_type, period_no, start_date) VALUES ($1, 'semester', 2, '2026-12-01');`, [batchId]);
  await db.query(`DELETE FROM batch_periods WHERE batch_id = $1 AND period_no = 2;`, [batchId]);

  // Reopen period 1
  await asUser(adminUid, 'service_role');
  await db.query(`UPDATE batch_periods SET end_date = NULL WHERE batch_id = $1 AND period_no = 1;`, [batchId]);
  console.log('✓ PASS: batch_periods allows SELECT for authenticated and writes for admin only.');

  // =========================================================================
  // 4. Student announcements restricted to own notifications
  // =========================================================================
  console.log('4. Testing announcement visibility isolation for students...');
  await asUser(adminUid);
  // Create an announcement targeted to student 1 only
  const ann1 = await db.query(`
    INSERT INTO announcements (category, title, body, audience_type, audience_ids, created_by)
    VALUES ('general', 'Notice for Alice', 'Hello Alice', 'batch', '[]'::jsonb, $1)
    RETURNING id;
  `, [adminUid]);
  const ann1Id = ann1.rows[0].id;

  // Notification for student 1
  await db.query(`
    INSERT INTO notifications (user_id, recipient_type, recipient_id, announcement_id, type, title, body)
    VALUES ($1, 'student', $2, $3, 'announcement', 'Notice for Alice', 'Hello Alice');
  `, [student1Uid, student1Id, ann1Id]);

  // Create an announcement without notification for Alice (targeted to Bob or teachers)
  const ann2 = await db.query(`
    INSERT INTO announcements (category, title, body, audience_type, audience_ids, created_by)
    VALUES ('fee_reminder', 'Private Defaulter Notice', 'Payment pending', 'fee_defaulters', '[]'::jsonb, $1)
    RETURNING id;
  `, [adminUid]);
  const ann2Id = ann2.rows[0].id;

  // Check Alice's visibility
  await asUser(student1Uid);
  const aliceAnnouncements = await db.query(`SELECT id FROM announcements;`);
  const aliceAnnIds = aliceAnnouncements.rows.map(r => r.id);
  if (!aliceAnnIds.includes(ann1Id)) {
    throw new Error('FAILED: Alice should be able to view announcement linked to her notification!');
  }
  if (aliceAnnIds.includes(ann2Id)) {
    throw new Error('FAILED: Alice should NOT be able to view announcement without her notification!');
  }
  console.log('✓ PASS: Announcements readable by students are strictly restricted to their own notifications.');

  // =========================================================================
  // 5. verify_security_rls_matrix check
  // =========================================================================
  console.log('5. Running verify_security_rls_matrix()...');
  await asUser(adminUid, 'service_role');
  const matrixRes = await db.query(`SELECT verify_security_rls_matrix() AS res;`);
  const matrix = matrixRes.rows[0].res;
  console.log('verify_security_rls_matrix report:', JSON.stringify(matrix, null, 2));

  if (matrix.rls_coverage.status !== 'PASS') {
    throw new Error('FAILED: rls_coverage is not PASS: ' + JSON.stringify(matrix.rls_coverage));
  }
  if (matrix.anon_policy_isolation.status !== 'PASS') {
    throw new Error('FAILED: anon_policy_isolation is not PASS: ' + JSON.stringify(matrix.anon_policy_isolation));
  }
  if (matrix.security_definer_search_path.status !== 'PASS') {
    throw new Error('FAILED: security_definer_search_path is not PASS: ' + JSON.stringify(matrix.security_definer_search_path));
  }
  if (matrix.audit_immutability.status !== 'PASS') {
    throw new Error('FAILED: audit_immutability is not PASS: ' + JSON.stringify(matrix.audit_immutability));
  }
  if (matrix.anon_public_functions && matrix.anon_public_functions.status !== 'PASS') {
    throw new Error('FAILED: anon_public_functions is not PASS: ' + JSON.stringify(matrix.anon_public_functions));
  }
  console.log('✓ PASS: verify_security_rls_matrix reported PASS across all checks!');

  console.log('\n=== ALL PHASE C SECURITY TESTS PASSED SUCCESSFULLY! ===');
}

run().catch(err => {
  console.error('\n✗ TEST FAILED:', err);
  process.exit(1);
});
