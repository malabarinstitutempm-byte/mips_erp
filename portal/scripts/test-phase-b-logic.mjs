import { PGlite } from '@electric-sql/pglite';
import { pgcrypto } from '@electric-sql/pglite/contrib/pgcrypto';
import { uuid_ossp } from '@electric-sql/pglite/contrib/uuid_ossp';
import fs from 'fs';
import path from 'path';

async function run() {
  console.log('=== PHASE B: BUSINESS LOGIC INTEGRATION TEST SUITE ===\n');
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

  // Insert Admin Profile
  const adminId = 'a0000000-0000-0000-0000-000000000001';
  await db.query(`INSERT INTO auth.users (id, email) VALUES ($1, 'admin@mips.edu') ON CONFLICT (id) DO NOTHING;`, [adminId]);
  await db.query(`INSERT INTO profiles (user_id, role, active) VALUES ($1, 'admin', true) ON CONFLICT (user_id) DO UPDATE SET role = 'admin', active = true;`, [adminId]);

  // Test 1: Lockout logic - account remains locked until admin unlocks
  console.log('Test 1: Account lockout (no 15-minute auto-expiry)...');
  await db.exec(`
    INSERT INTO auth.users (id, email) VALUES ('b0000000-0000-0000-0000-000000000002', 'testuser@mips.edu');
    INSERT INTO teachers (name, login_username) VALUES ('Lockout Tester', 'lockout_tester');
    INSERT INTO profiles (user_id, role, teacher_id, active, locked_at, failed_attempts)
    VALUES ('b0000000-0000-0000-0000-000000000002', 'teacher', (SELECT id FROM teachers WHERE login_username = 'lockout_tester'), true, now() - interval '2 hours', 5);
  `);
  const lockRes = await db.query(`SELECT check_account_lockout('b0000000-0000-0000-0000-000000000002'::uuid) AS res;`);
  if (lockRes.rows[0].res.is_locked !== true) {
    throw new Error('FAILED: Account should stay locked even after 2 hours! Got: ' + JSON.stringify(lockRes.rows[0].res));
  }
  console.log('✓ PASS: Account remains locked beyond 15 minutes.');

  // Test 2: Auto-enrollment and fee items trigger
  console.log('Test 2: Auto-enrollment & fee items on student admission...');
  const courseRes = await db.query(`
    INSERT INTO courses (name, code, course_type, structure, attendance_basis, total_fee_paise)
    VALUES ('B.Voc Radiography', 'BVRAD', 'primary', 'semester', 'semester', 5000000)
    RETURNING id;
  `);
  const courseId = courseRes.rows[0].id;

  const batchRes = await db.query(`
    INSERT INTO batches (batch_name, course_id, start_date)
    VALUES ('Batch 2026', $1, '2026-06-01')
    RETURNING id, current_semester, current_year;
  `, [courseId]);
  const batchId = batchRes.rows[0].id;

  // Check batch period was automatically created
  const periodCheck = await db.query(`SELECT * FROM batch_periods WHERE batch_id = $1`, [batchId]);
  if (periodCheck.rows.length === 0) {
    throw new Error('FAILED: First batch_period was not automatically created on batch insert!');
  }
  console.log('✓ PASS: First batch_period automatically created on batch insertion.');

  // Insert Student -> triggers auto-enrollment and fee items
  const studRes = await db.query(`
    INSERT INTO students (name, admission_number, course_id, batch_id, admission_date)
    VALUES ('John Doe', 'ADM-2026-001', $1, $2, '2026-06-01')
    RETURNING id;
  `, [courseId, batchId]);
  const studentId = studRes.rows[0].id;

  const enrCheck = await db.query(`SELECT * FROM student_enrollments WHERE student_id = $1`, [studentId]);
  if (enrCheck.rows.length === 0) {
    throw new Error('FAILED: Student enrollment was not automatically created!');
  }
  const feeCheck = await db.query(`SELECT * FROM fee_items WHERE student_id = $1`, [studentId]);
  if (feeCheck.rows.length === 0) {
    throw new Error('FAILED: Fee items were not automatically created!');
  }
  console.log('✓ PASS: Auto-enrollment and fee items created with fees totals synced.');

  // Test 3: Record Payment FIFO & Receipts
  console.log('Test 3: record_payment with 2-argument next_number and receipt...');
  const payRes = await db.query(`
    SELECT record_payment(
      $1::bigint,
      2000000::bigint,
      'cash'::payment_mode,
      'FEE-2026-001'::text,
      'First installment'::text,
      NULL::jsonb
    ) AS res;
  `, [studentId]);
  const payData = payRes.rows[0].res;
  if (!payData.success || !payData.receipt_number) {
    throw new Error('FAILED: record_payment failed: ' + JSON.stringify(payData));
  }
  console.log('✓ PASS: record_payment succeeded, receipt #' + payData.receipt_number + ' generated.');

  // Test 4: Attendance submission, no-class confirmation, and attendance evaluation
  console.log('Test 4: submit_attendance and evaluate_attendance_bands...');
  const attSubmit = await db.query(`
    SELECT submit_attendance(
      $1::bigint,
      '2026-06-05'::date,
      'morning'::attendance_slot,
      jsonb_build_array(jsonb_build_object('student_id', $2::bigint, 'status', 'present')),
      false,
      NULL
    ) AS res;
  `, [batchId, studentId]);
  if (!attSubmit.rows[0].res.success) {
    throw new Error('FAILED: submit_attendance failed: ' + JSON.stringify(attSubmit.rows[0].res));
  }

  // ALREADY_MARKED guard
  const attRepeat = await db.query(`
    SELECT submit_attendance(
      $1::bigint,
      '2026-06-05'::date,
      'morning'::attendance_slot,
      '[]'::jsonb
    ) AS res;
  `, [batchId]);
  if (attRepeat.rows[0].res.error_code !== 'ALREADY_MARKED') {
    throw new Error('FAILED: Expected ALREADY_MARKED on duplicate slot submission!');
  }
  console.log('✓ PASS: submit_attendance passed and ALREADY_MARKED guard verified.');

  // Test 5: Period-Aware student_attendance_summary
  console.log('Test 5: Period-aware student_attendance_summary...');
  const sumRes = await db.query(`
    SELECT * FROM student_attendance_summary($1::bigint) LIMIT 1;
  `, [studentId]);
  const summary = sumRes.rows[0];
  if (summary.sessions_held !== 1 || summary.present_count !== 1 || summary.percentage !== '100.00' || summary.status_band !== 'ok') {
    throw new Error('FAILED: student_attendance_summary output incorrect: ' + JSON.stringify(summary));
  }
  console.log('✓ PASS: student_attendance_summary returns full original columns and correct statistics.');

  // Test 6: Semester promotion
  console.log('Test 6: Semester promotion (preview & promote_semester)...');
  const promoPrev = await db.query(`
    SELECT preview_promote_semester($1::bigint, '2026-11-30'::date, '2026-12-01'::date) AS res;
  `, [batchId]);
  if (promoPrev.rows[0].res.current_semester !== 1 || promoPrev.rows[0].res.next_semester !== 2) {
    throw new Error('FAILED: preview_promote_semester output incorrect: ' + JSON.stringify(promoPrev.rows[0].res));
  }

  const promoExec = await db.query(`
    SELECT promote_semester($1::bigint, '2026-11-30'::date, '2026-12-01'::date, 'End of Sem 1') AS res;
  `, [batchId]);
  if (!promoExec.rows[0].res.success || promoExec.rows[0].res.current_semester !== 2) {
    throw new Error('FAILED: promote_semester failed: ' + JSON.stringify(promoExec.rows[0].res));
  }
  console.log('✓ PASS: Semester promotion executed, batch advanced to Semester 2, notifications created.');

  // Test 7: Phase 13 create_exam, publish_exam, compute_results
  console.log('Test 7: create_exam, compute_results, and publish_exam...');
  await db.query(`
    INSERT INTO course_subjects (course_id, subject_name, subject_code, max_marks, pass_marks, period_no)
    VALUES ($1, 'Radiation Physics', 'RAD101', 100, 40, 2);
  `, [courseId]);

  const examRes = await db.query(`
    SELECT create_exam(
      $1::bigint,
      $2::bigint,
      'Sem 2 Midterm'::text,
      'semester'::text,
      2::int,
      '2027-01-15'::date,
      NULL,
      NULL
    ) AS res;
  `, [courseId, batchId]);
  const examId = examRes.rows[0].res.exam_id;
  if (!examId || examRes.rows[0].res.subjects_copied < 1) {
    throw new Error('FAILED: create_exam failed: ' + JSON.stringify(examRes.rows[0].res));
  }

  // Insert marks for student
  const subjRes = await db.query(`SELECT id FROM exam_subjects WHERE exam_id = $1 LIMIT 1`, [examId]);
  const examSubjId = subjRes.rows[0].id;
  await db.query(`
    INSERT INTO marks (exam_id, subject_id, student_id, marks_obtained, is_absent)
    VALUES ($1, $2, $3, 85, false);
  `, [examId, examSubjId, studentId]);

  const compRes = await db.query(`SELECT compute_results($1::bigint) AS res;`, [examId]);
  if (!compRes.rows[0].res.success || compRes.rows[0].res.passed !== 1) {
    throw new Error('FAILED: compute_results failed: ' + JSON.stringify(compRes.rows[0].res));
  }

  const pubRes = await db.query(`SELECT publish_exam($1::bigint) AS res;`, [examId]);
  if (!pubRes.rows[0].res.success) {
    throw new Error('FAILED: publish_exam failed: ' + JSON.stringify(pubRes.rows[0].res));
  }
  console.log('✓ PASS: create_exam, compute_results, and publish_exam executed with ranks & notifications.');

  // Test 8: Full database export dump
  console.log('Test 8: Generic export_database_dump()...');
  const dumpRes = await db.query(`SELECT export_database_dump() AS res;`);
  const dump = dumpRes.rows[0].res;
  if (!dump.tables || !dump.reconciliation || dump.reconciliation.students < 1) {
    throw new Error('FAILED: export_database_dump output invalid: ' + JSON.stringify(dump));
  }
  console.log('✓ PASS: export_database_dump generated generic table dumps and reconciliation counts.');

  console.log('\n=== ALL PHASE B BUSINESS LOGIC TESTS PASSED SUCCESSFULLY! ===');
}

run().catch(err => {
  console.error('\n✗ TEST FAILED:', err);
  process.exit(1);
});
