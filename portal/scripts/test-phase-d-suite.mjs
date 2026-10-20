import { PGlite } from '@electric-sql/pglite';
import { pgcrypto } from '@electric-sql/pglite/contrib/pgcrypto';
import { uuid_ossp } from '@electric-sql/pglite/contrib/uuid_ossp';
import fs from 'fs';
import path from 'path';

async function runPhaseDSuite() {
  console.log('===============================================================');
  console.log('       PHASE D: COMPREHENSIVE AUTOMATED VERIFICATION SUITE      ');
  console.log('===============================================================\n');

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
      SELECT NULLIF(current_setting('request.jwt.claim.sub', true), '')::uuid;
    $$ LANGUAGE sql STABLE;

    CREATE OR REPLACE FUNCTION auth.role() RETURNS text AS $$
      SELECT coalesce(nullif(current_setting('request.jwt.claim.role', true), ''), 'authenticated')::text;
    $$ LANGUAGE sql STABLE;
  `);

  // Helper to switch user context
  async function asUser(uid, role = 'authenticated') {
    if (role === 'service_role') {
      await db.exec(`
        RESET ROLE;
        SELECT set_config('request.jwt.claim.sub', '', false);
        SELECT set_config('request.jwt.claim.role', 'service_role', false);
      `);
    } else if (role === 'anon') {
      await db.exec(`
        RESET ROLE;
        SELECT set_config('request.jwt.claim.sub', '', false);
        SELECT set_config('request.jwt.claim.role', 'anon', false);
        SET ROLE anon;
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
  // TEST 1: Full chain applies on an empty DB
  // =========================================================================
  console.log('TEST 1: Applying full migration chain 0001-0020 on clean database...');
  const dir = path.resolve('../supabase/migrations');
  const files = fs.readdirSync(dir).filter(f => f.endsWith('.sql') && f.startsWith('00') && !f.includes('0021')).sort();
  for (const file of files) {
    let sql = fs.readFileSync(path.join(dir, file), 'utf8');
    sql = sql.replace(/CREATE EXTENSION IF NOT EXISTS "uuid-ossp";?/gi, '-- (uuid-ossp mocked)');
    await db.exec(sql);
  }
  console.log(`✓ PASS: All ${files.length} migrations applied with 0 errors.\n`);

  // Setup Users: Admin, Teacher, Student 1 (Alice), Student 2 (Bob)
  const adminUid = 'a0000000-0000-0000-0000-000000000001';
  const teacherUid = 'a0000000-0000-0000-0000-000000000002';
  const student1Uid = 'a0000000-0000-0000-0000-000000000003';
  const student2Uid = 'a0000000-0000-0000-0000-000000000004';

  await asUser(null, 'service_role');
  await db.query(`INSERT INTO auth.users (id, email) VALUES ($1, 'admin@mips.edu');`, [adminUid]);
  await db.query(`INSERT INTO profiles (user_id, role, active) VALUES ($1, 'admin', true);`, [adminUid]);

  const teacherRes = await db.query(`INSERT INTO teachers (name, login_username) VALUES ('Dr. Teacher', 'dr_teacher') RETURNING id;`);
  const teacherId = teacherRes.rows[0].id;
  await db.query(`INSERT INTO auth.users (id, email) VALUES ($1, 'teacher@mips.edu');`, [teacherUid]);
  await db.query(`INSERT INTO profiles (user_id, role, teacher_id, active) VALUES ($1, 'teacher', $2, true);`, [teacherUid, teacherId]);

  // =========================================================================
  // TEST 2: Admission creates enrollment and fee item; fees synced
  // =========================================================================
  console.log('TEST 2: Verifying admission auto-creates enrollment and fee item...');
  const courseRes = await db.query(`
    INSERT INTO courses (name, code, course_type, structure, attendance_basis, total_fee_paise, duration)
    VALUES ('B.Sc Imaging Technology', 'BSCIT', 'primary', 'semester', 'semester', 6000000, '3 years')
    RETURNING id;
  `);
  const courseId = courseRes.rows[0].id;

  const batchRes = await db.query(`
    INSERT INTO batches (batch_name, course_id, start_date)
    VALUES ('Batch 2026', $1, '2026-06-01')
    RETURNING id;
  `, [courseId]);
  const batchId = batchRes.rows[0].id;

  // Period 1 created automatically
  const periodCheck = await db.query(`SELECT count(*)::int as cnt FROM batch_periods WHERE batch_id = $1 AND period_no = 1;`, [batchId]);
  if (periodCheck.rows[0].cnt !== 1) throw new Error('FAILED: First batch_period not created automatically!');

  // Insert Student 1 (Alice)
  const s1Res = await db.query(`
    INSERT INTO students (name, admission_number, course_id, batch_id)
    VALUES ('Alice Johnson', 'ADM-2026-001', $1, $2)
    RETURNING id;
  `, [courseId, batchId]);
  const student1Id = s1Res.rows[0].id;

  await db.query(`INSERT INTO auth.users (id, email) VALUES ($1, 'alice@student.mips.edu');`, [student1Uid]);
  await db.query(`INSERT INTO profiles (user_id, role, student_id, active) VALUES ($1, 'student', $2, true);`, [student1Uid, student1Id]);

  // Insert Student 2 (Bob)
  const s2Res = await db.query(`
    INSERT INTO students (name, admission_number, course_id, batch_id)
    VALUES ('Bob Williams', 'ADM-2026-002', $1, $2)
    RETURNING id;
  `, [courseId, batchId]);
  const student2Id = s2Res.rows[0].id;

  await db.query(`INSERT INTO auth.users (id, email) VALUES ($1, 'bob@student.mips.edu');`, [student2Uid]);
  await db.query(`INSERT INTO profiles (user_id, role, student_id, active) VALUES ($1, 'student', $2, true);`, [student2Uid, student2Id]);

  // Assert Alice's enrollment and fee items
  const enrRes = await db.query(`SELECT id, status, kind FROM student_enrollments WHERE student_id = $1;`, [student1Id]);
  if (enrRes.rows.length !== 1 || enrRes.rows[0].status !== 'active' || enrRes.rows[0].kind !== 'primary') {
    throw new Error('FAILED: Auto-enrollment row missing or invalid for student!');
  }
  const enrId = enrRes.rows[0].id;

  const feeItemRes = await db.query(`SELECT id, amount_paise, paid_amount_paise FROM fee_items WHERE enrollment_id = $1;`, [enrId]);
  if (feeItemRes.rows.length !== 1 || Number(feeItemRes.rows[0].amount_paise) !== 6000000) {
    throw new Error('FAILED: Auto fee_items row missing or invalid amount!');
  }

  const legacyFeeRes = await db.query(`SELECT total_fee_paise, paid_amount_paise, pending_amount_paise FROM fees WHERE student_id = $1;`, [student1Id]);
  if (legacyFeeRes.rows.length !== 1 || Number(legacyFeeRes.rows[0].pending_amount_paise) !== 6000000) {
    throw new Error('FAILED: Legacy fees sync missing or incorrect balance!');
  }
  console.log('✓ PASS: Student admission automatically created enrollment, fee_item (₹60,000) and synced fees table.\n');

  // =========================================================================
  // TEST 3: Collecting, allocating and cancelling payments keep totals exact
  // =========================================================================
  console.log('TEST 3: Verifying payment collection, FIFO allocations, and cancellation...');
  await asUser(adminUid);
  // Collect ₹20,000 (2000000 paise)
  const payRes = await db.query(`
    SELECT record_payment(
      $1::bigint,
      2000000::bigint,
      'cash'::payment_mode,
      'REF-CASH-001',
      'Initial semester fee payment',
      jsonb_build_array(jsonb_build_object('fee_item_id', $2::bigint, 'amount_paise', 2000000))
    ) AS pay_id;
  `, [student1Id, feeItemRes.rows[0].id]);
  const paymentObj = payRes.rows[0].pay_id;
  const paymentId = typeof paymentObj === 'object' ? paymentObj.payment_id : paymentObj;

  // Verify receipt
  const receiptRes = await db.query(`SELECT receipt_number FROM receipts WHERE payment_id = $1;`, [paymentId]);
  if (receiptRes.rows.length !== 1 || !receiptRes.rows[0].receipt_number.startsWith('REC/')) {
    throw new Error('FAILED: Receipt not generated properly for payment!');
  }

  // Verify fee_items and fees updated
  let feeItemCheck = await db.query(`SELECT paid_amount_paise FROM fee_items WHERE id = $1;`, [feeItemRes.rows[0].id]);
  let feesCheck = await db.query(`SELECT paid_amount_paise, pending_amount_paise FROM fees WHERE student_id = $1;`, [student1Id]);
  if (Number(feeItemCheck.rows[0].paid_amount_paise) !== 2000000 || Number(feesCheck.rows[0].pending_amount_paise) !== 4000000) {
    throw new Error('FAILED: Fee totals did not update after payment collection!');
  }

  // Cancel Payment
  await db.query(`SELECT cancel_payment($1::bigint, 'Wrong receipt cancellation');`, [paymentId]);

  // Verify totals reverted exactly
  feeItemCheck = await db.query(`SELECT paid_amount_paise FROM fee_items WHERE id = $1;`, [feeItemRes.rows[0].id]);
  feesCheck = await db.query(`SELECT paid_amount_paise, pending_amount_paise FROM fees WHERE student_id = $1;`, [student1Id]);
  if (Number(feeItemCheck.rows[0].paid_amount_paise) !== 0 || Number(feesCheck.rows[0].pending_amount_paise) !== 6000000) {
    throw new Error('FAILED: Fee totals did not revert exactly after payment cancellation!');
  }
  console.log('✓ PASS: Payment collection, receipt generation (#REC/...) and cancellation reverted totals exactly.\n');

  // =========================================================================
  // TEST 4: Attendance submit, ALREADY_MARKED, corrections and alerts
  // =========================================================================
  console.log('TEST 4: Verifying attendance submission, duplicate guard, and corrections...');
  await asUser(teacherUid);
  const todayRes = await db.query(`SELECT (CURRENT_TIMESTAMP AT TIME ZONE 'Asia/Kolkata')::date::text AS today;`);
  const attDate = todayRes.rows[0].today;
  const slot = 'morning';

  // Teacher submits attendance
  const submitRes = await db.query(`
    SELECT submit_attendance(
      $1::bigint,
      $2::date,
      $3::attendance_slot,
      jsonb_build_array(
        jsonb_build_object('student_id', $4::bigint, 'status', 'present'),
        jsonb_build_object('student_id', $5::bigint, 'status', 'absent')
      ),
      false,
      NULL
    ) AS session_id;
  `, [batchId, attDate, slot, student1Id, student2Id]);
  const sessionObj = submitRes.rows[0].session_id;
  const sessionId = typeof sessionObj === 'object' ? sessionObj.session_id : sessionObj;

  // Duplicate submission check (ALREADY_MARKED guard)
  try {
    await db.query(`
      SELECT submit_attendance(
        $1::bigint,
        $2::date,
        $3::attendance_slot,
        '[]'::jsonb,
        false,
        NULL
      );
    `, [batchId, attDate, slot]);
    throw new Error('FAILED: Duplicate attendance submission did not throw ALREADY_MARKED!');
  } catch (err) {
    if (!err.message.includes('ALREADY_MARKED')) throw err;
  }

  // Find Alice's attendance record
  const recRes = await db.query(`
    SELECT id, status FROM attendance_records
    WHERE session_id = $1 AND student_id = $2;
  `, [sessionId, student1Id]);
  const recordId = recRes.rows[0].id;
  if (recRes.rows[0].status !== 'present') throw new Error('FAILED: Record status was not present!');

  // Correct Alice's record to absent with reason
  await asUser(adminUid);
  await db.query(`SELECT correct_attendance($1::bigint, 'absent'::attendance_status, 'Medical emergency reported');`, [recordId]);

  // Check audit changes logged
  const changeRes = await db.query(`
    SELECT old_status, new_status, reason FROM attendance_changes
    WHERE record_id = $1;
  `, [recordId]);
  if (changeRes.rows.length === 0 || changeRes.rows[0].new_status !== 'absent') {
    throw new Error('FAILED: attendance_changes audit log not populated upon correction!');
  }
  console.log('✓ PASS: Attendance submit, ALREADY_MARKED guard, and correction audit logging verified.\n');

  // =========================================================================
  // TEST 5: Semester and year promotion
  // =========================================================================
  console.log('TEST 5: Verifying semester and year promotion functions...');
  await asUser(adminUid);
  // Preview semester promotion
  const prevSem = await db.query(`SELECT preview_promote_semester($1::bigint, '2026-11-30', '2026-12-01') AS prev;`, [batchId]);
  if (!prevSem.rows[0].prev || prevSem.rows[0].prev.next_semester !== 2) {
    throw new Error('FAILED: preview_promote_semester did not return next semester 2!');
  }

  // Promote semester
  await db.query(`SELECT promote_semester($1::bigint, '2026-11-30', '2026-12-01', 'Regular end of sem 1');`, [batchId]);

  // Check batch and batch_periods state
  const bCheck = await db.query(`SELECT current_semester, current_year FROM batches WHERE id = $1;`, [batchId]);
  if (bCheck.rows[0].current_semester !== 2) throw new Error('FAILED: batches.current_semester not updated to 2!');

  const p1Check = await db.query(`SELECT status, end_date::text FROM batch_periods WHERE batch_id = $1 AND period_no = 1;`, [batchId]);
  if (p1Check.rows[0].status !== 'closed' || p1Check.rows[0].end_date !== '2026-11-30') {
    throw new Error(`FAILED: Period 1 was not properly closed! got ${JSON.stringify(p1Check.rows[0])}`);
  }

  const p2Check = await db.query(`SELECT status, start_date::text FROM batch_periods WHERE batch_id = $1 AND period_no = 2;`, [batchId]);
  if (p2Check.rows[0].status !== 'active' || p2Check.rows[0].start_date !== '2026-12-01') {
    throw new Error(`FAILED: Period 2 was not properly created/activated! got ${JSON.stringify(p2Check.rows[0])}`);
  }

  // Test Year Promotion on a Year-based Course
  const yrCourseRes = await db.query(`
    INSERT INTO courses (name, code, course_type, structure, attendance_basis, duration)
    VALUES ('Diploma in Radiology', 'DRAD', 'primary', 'year', 'year', '2 years')
    RETURNING id;
  `);
  const yrCourseId = yrCourseRes.rows[0].id;
  const yrBatchRes = await db.query(`
    INSERT INTO batches (batch_name, course_id, start_date)
    VALUES ('DRAD Batch 2026', $1, '2026-06-01')
    RETURNING id;
  `, [yrCourseId]);
  const yrBatchId = yrBatchRes.rows[0].id;

  await db.query(`SELECT promote_year($1::bigint, '2027-05-31', '2027-06-01', 'Advancement to Year 2');`, [yrBatchId]);
  const yrbCheck = await db.query(`SELECT current_year FROM batches WHERE id = $1;`, [yrBatchId]);
  if (yrbCheck.rows[0].current_year !== 2) throw new Error('FAILED: batches.current_year not updated to 2!');
  console.log('✓ PASS: Semester promotion and year promotion transitioned batch periods and batches accurately.\n');

  // =========================================================================
  // TEST 6: Completed batch and access window
  // =========================================================================
  console.log('TEST 6: Verifying completed batch lifecycle and access window...');
  await asUser(adminUid);
  await db.query(`
    SELECT complete_batch(
      $1::bigint,
      '2028-05-31'::date,
      ARRAY[]::bigint[],
      '2028-08-31'::date,
      false
    );
  `, [batchId]);

  const bCompCheck = await db.query(`SELECT status FROM batches WHERE id = $1;`, [batchId]);
  if (bCompCheck.rows[0].status !== 'completed') throw new Error('FAILED: Batch status was not set to completed!');

  const profCheck = await db.query(`SELECT access_until::text FROM profiles WHERE user_id = $1;`, [student1Uid]);
  if (profCheck.rows[0].access_until !== '2028-08-31') {
    throw new Error(`FAILED: Student access_until override was not set to 2028-08-31! got ${JSON.stringify(profCheck.rows[0])}`);
  }

  // Student checks access allowed
  await asUser(student1Uid);
  const accCheck = await db.query(`SELECT student_access_allowed() as allowed;`);
  if (!accCheck.rows[0].allowed) throw new Error('FAILED: Student access should be allowed within grace window!');
  console.log('✓ PASS: Batch completion set completed statuses and respected 90-day access validity window.\n');

  // =========================================================================
  // TEST 7: Unpublished marks and results are invisible to students
  // =========================================================================
  console.log('TEST 7: Verifying unpublished exams, marks, and results isolation from students...');
  await asUser(adminUid);
  // Create subject & exam
  const subRes = await db.query(`INSERT INTO course_subjects (course_id, subject_name, subject_code, max_marks, pass_marks) VALUES ($1, 'Anatomy I', 'ANA101', 100, 40) RETURNING id;`, [courseId]);
  const subjectId = subRes.rows[0].id;

  const examRes = await db.query(`
    SELECT create_exam(
      $1::bigint,
      $2::bigint,
      'Semester 1 Final Exam',
      'semester',
      1,
      '2026-11-15'::date,
      '2026-11-25'::date,
      'Initial scheduling'
    ) AS ex_id;
  `, [courseId, batchId]);
  const examObj = examRes.rows[0].ex_id;
  const examId = typeof examObj === 'object' ? examObj.exam_id : examObj;

  // Get the copied exam_subject id
  const examSubRes = await db.query(`SELECT id FROM exam_subjects WHERE exam_id = $1;`, [examId]);
  const examSubjectId = examSubRes.rows[0].id;

  // Save marks for Alice (85/100)
  await db.query(`
    SELECT save_marks(
      $1::bigint,
      jsonb_build_array(
        jsonb_build_object('student_id', $2::bigint, 'subject_id', $3::bigint, 'marks_obtained', 85)
      )
    );
  `, [examId, student1Id, examSubjectId]);

  // Compute results (still unpublished)
  await db.query(`SELECT compute_results($1::bigint);`, [examId]);

  // Student (Alice) checks visibility
  await asUser(student1Uid);
  let studExams = await db.query(`SELECT count(*)::int as cnt FROM exams WHERE id = $1;`, [examId]);
  let studMarks = await db.query(`SELECT count(*)::int as cnt FROM marks WHERE exam_id = $1 AND student_id = $2;`, [examId, student1Id]);
  let studResults = await db.query(`SELECT count(*)::int as cnt FROM results WHERE exam_id = $1 AND student_id = $2;`, [examId, student1Id]);

  if (studExams.rows[0].cnt !== 0 || studMarks.rows[0].cnt !== 0 || studResults.rows[0].cnt !== 0) {
    throw new Error('FAILED: Unpublished exam, marks, or results leaked to student!');
  }

  // Admin publishes exam
  await asUser(adminUid);
  await db.query(`SELECT publish_exam($1::bigint, false);`, [examId]);

  // Student checks visibility again
  await asUser(student1Uid);
  studExams = await db.query(`SELECT count(*)::int as cnt FROM exams WHERE id = $1;`, [examId]);
  studMarks = await db.query(`SELECT count(*)::int as cnt FROM marks WHERE exam_id = $1 AND student_id = $2;`, [examId, student1Id]);
  studResults = await db.query(`SELECT count(*)::int as cnt FROM results WHERE exam_id = $1 AND student_id = $2;`, [examId, student1Id]);

  if (studExams.rows[0].cnt !== 1 || studMarks.rows[0].cnt !== 1 || studResults.rows[0].cnt !== 1) {
    throw new Error('FAILED: Published exam, marks, or results not visible to student after publish!');
  }
  console.log('✓ PASS: Unpublished exams/marks/results are completely hidden from students until published.\n');

  // =========================================================================
  // TEST 8: Anon can call nothing
  // =========================================================================
  console.log('TEST 8: Verifying anon cannot execute any public functions...');
  await asUser(null, 'anon');

  const testAnonFuncs = [
    `SELECT is_admin();`,
    `SELECT export_database_dump();`,
    `SELECT student_attendance_summary(1, 1);`,
    `SELECT submit_attendance(1, '2026-07-01'::date, 'morning'::attendance_slot, '[]'::jsonb, false, null);`,
    `SELECT record_payment(1, 1000, 'cash', 'ref', 'rem', '[]'::jsonb);`,
    `SELECT get_dashboard_summary_counts();`
  ];

  for (const q of testAnonFuncs) {
    try {
      await db.query(q);
      throw new Error(`FAILED: anon should not be able to execute "${q}"!`);
    } catch (err) {
      if (!err.message.includes('permission denied')) {
        throw err;
      }
    }
  }
  console.log('✓ PASS: All routine calls by anon are strictly blocked by permission denial.\n');

  // =========================================================================
  // TEST 9: Students and teachers cannot read other people\'s data
  // =========================================================================
  console.log('TEST 9: Verifying cross-user data isolation for students and teachers...');
  // Alice tries to read Bob's semester summary
  await asUser(student1Uid);
  try {
    await db.query(`SELECT * FROM student_semesters_summary($1::bigint);`, [student2Id]);
    throw new Error('FAILED: Alice should not be able to call student_semesters_summary for Bob!');
  } catch (err) {
    if (!err.message.includes('Access denied')) throw err;
  }

  // Alice queries payments table for Bob's data
  const aliceBobPayments = await db.query(`SELECT * FROM payments WHERE student_id = $1;`, [student2Id]);
  if (aliceBobPayments.rows.length !== 0) {
    throw new Error('FAILED: Alice was able to view Bob payments via RLS leak!');
  }

  // Alice queries notifications table for Bob's data
  const aliceBobNotifications = await db.query(`SELECT * FROM notifications WHERE user_id = $1;`, [student2Uid]);
  if (aliceBobNotifications.rows.length !== 0) {
    throw new Error('FAILED: Alice was able to view Bob notifications via RLS leak!');
  }

  // Alice queries profiles table for Bob's data
  const aliceBobProfiles = await db.query(`SELECT * FROM profiles WHERE user_id = $1;`, [student2Uid]);
  if (aliceBobProfiles.rows.length !== 0) {
    throw new Error('FAILED: Alice was able to view Bob profile via RLS leak!');
  }

  // Teacher cannot read audit_log (filtered to 0 rows by RLS)
  await asUser(teacherUid);
  const teacherAudit = await db.query(`SELECT * FROM audit_log;`);
  if (teacherAudit.rows.length !== 0) {
    throw new Error('FAILED: Teacher was able to view audit_log rows via RLS leak!');
  }
  console.log('✓ PASS: Strict cross-user data isolation confirmed for students and teachers.\n');

  // =========================================================================
  // TEST 10: Export dump runs and matches counts
  // =========================================================================
  console.log('TEST 10: Verifying generic export_database_dump() reconciliation counts...');
  await asUser(adminUid);
  const dumpRes = await db.query(`SELECT export_database_dump() AS dump;`);
  const dump = dumpRes.rows[0].dump;

  if (!dump.tables || !dump.reconciliation) {
    throw new Error('FAILED: export_database_dump returned invalid structure!');
  }

  const counts = dump.reconciliation;
  console.log('Dump Reconciliation Sample:', {
    total_students: counts.total_students,
    active_students: counts.active_students,
    total_exams: counts.total_exams,
    total_results: counts.total_results,
    total_payments: counts.total_payments,
    total_receipts: counts.total_receipts,
    total_attendance_sessions: counts.total_attendance_sessions
  });

  const realStudentsCount = await db.query(`SELECT count(*)::int as cnt FROM students WHERE deleted_at IS NULL;`);
  if (counts.total_students !== realStudentsCount.rows[0].cnt) {
    throw new Error(`FAILED: Export dump student count (${counts.total_students}) does not match DB (${realStudentsCount.rows[0].cnt})!`);
  }

  const realExamsCount = await db.query(`SELECT count(*)::int as cnt FROM exams WHERE deleted_at IS NULL;`);
  if (counts.total_exams !== realExamsCount.rows[0].cnt) {
    throw new Error(`FAILED: Export dump exams count (${counts.total_exams}) does not match DB (${realExamsCount.rows[0].cnt})!`);
  }
  console.log('✓ PASS: export_database_dump executed generically and reconciliation counts match actual database.\n');

  console.log('===============================================================');
  console.log('    ✓ ALL 10 PHASE D PROOF OF CORRECTNESS TESTS PASSED!       ');
  console.log('===============================================================');
}

runPhaseDSuite().catch(err => {
  console.error('\n✗ TEST FAILED:', err);
  process.exit(1);
});
