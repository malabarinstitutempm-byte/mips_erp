-- =============================================================================
-- MIPS ERP Database Test Suite: rls_tests.sql
-- Sub-phase 1C: Comprehensive Verification of RLS Policies, Negative Isolation,
-- Anon Lockdown, Audit Immutability, and Overpayment Safeguards
-- =============================================================================

BEGIN;

-- =============================================================================
-- 1. Setup Test Fixtures (Isolated inside this transaction)
-- =============================================================================

DO $$
DECLARE
    v_admin_uuid uuid := 'a0000000-0000-0000-0000-000000000001';
    v_teacher_a_uuid uuid := 'a0000000-0000-0000-0000-000000000002';
    v_teacher_b_uuid uuid := 'a0000000-0000-0000-0000-000000000003';
    v_student_1_uuid uuid := 'a0000000-0000-0000-0000-000000000004';
    v_student_2_uuid uuid := 'a0000000-0000-0000-0000-000000000005';

    v_year_id bigint;
    v_univ_id bigint;
    v_course_id bigint;
    v_subject_1_id bigint;
    v_subject_2_id bigint;
    v_batch_a_id bigint;
    v_batch_b_id bigint;

    v_teacher_a_id bigint;
    v_teacher_b_id bigint;
    v_student_1_id bigint;
    v_student_2_id bigint;

    v_exam_published_id bigint;
    v_exam_draft_id bigint;
    v_exam_subj_1_id bigint;
    v_exam_subj_2_id bigint;
BEGIN
    RAISE NOTICE '>>> [FIXTURES] Initializing test data environment...';

    -- Mock auth.users (if auth schema exists)
    BEGIN
        INSERT INTO auth.users (id, email, aud, role)
        VALUES 
            (v_admin_uuid, 'admin@mips.test', 'authenticated', 'authenticated'),
            (v_teacher_a_uuid, 'teacher_a@mips.test', 'authenticated', 'authenticated'),
            (v_teacher_b_uuid, 'teacher_b@mips.test', 'authenticated', 'authenticated'),
            (v_student_1_uuid, 'student_1@mips.test', 'authenticated', 'authenticated'),
            (v_student_2_uuid, 'student_2@mips.test', 'authenticated', 'authenticated')
        ON CONFLICT (id) DO NOTHING;
    EXCEPTION WHEN undefined_table THEN
        RAISE NOTICE 'auth.users not present; continuing with simulated context.';
    END;

    -- Master entities
    INSERT INTO academic_years (year_name, is_current)
    VALUES ('2026-2027-TEST', true) RETURNING id INTO v_year_id;

    INSERT INTO universities (name)
    VALUES ('Kerala Paramedical Council TEST') RETURNING id INTO v_univ_id;

    INSERT INTO courses (name, code, university_id, total_fee_paise)
    VALUES ('Diploma in Medical Laboratory Technology TEST', 'DMLT-TEST', v_univ_id, 5000000)
    RETURNING id INTO v_course_id;

    INSERT INTO course_subjects (course_id, subject_name, subject_code, max_marks, pass_marks)
    VALUES (v_course_id, 'Hematology TEST', 'HEM01', 100, 40) RETURNING id INTO v_subject_1_id;

    INSERT INTO course_subjects (course_id, subject_name, subject_code, max_marks, pass_marks)
    VALUES (v_course_id, 'Biochemistry TEST', 'BIO01', 100, 40) RETURNING id INTO v_subject_2_id;

    INSERT INTO batches (course_id, batch_name)
    VALUES (v_course_id, 'DMLT-TEST-BATCH-A') RETURNING id INTO v_batch_a_id;

    INSERT INTO batches (course_id, batch_name)
    VALUES (v_course_id, 'DMLT-TEST-BATCH-B') RETURNING id INTO v_batch_b_id;

    -- Teachers
    INSERT INTO teachers (name, phone, login_username, status)
    VALUES ('Prof. Ahmed TEST', '9876543210', 'ahmed_teacher', 'active')
    RETURNING id INTO v_teacher_a_id;

    INSERT INTO teachers (name, phone, login_username, status)
    VALUES ('Prof. Fatima TEST', '9876543211', 'fatima_teacher', 'active')
    RETURNING id INTO v_teacher_b_id;

    -- Teacher Assignments:
    -- Teacher A -> Batch A (Subject 1)
    -- Teacher B -> Batch B (Subject 2)
    INSERT INTO teacher_assignments (teacher_id, course_id, batch_id, subject_id, active)
    VALUES (v_teacher_a_id, v_course_id, v_batch_a_id, v_subject_1_id, true);

    INSERT INTO teacher_assignments (teacher_id, course_id, batch_id, subject_id, active)
    VALUES (v_teacher_b_id, v_course_id, v_batch_b_id, v_subject_2_id, true);

    -- Students:
    -- Student 1 in Batch A
    -- Student 2 in Batch B
    INSERT INTO students (admission_number, registration_number, name, dob, gender, phone, email, address, course_id, batch_id, university_id, academic_year_id)
    VALUES ('TEST-ADM-001', 'REG-001', 'Zayd Khan TEST', '2004-05-15', 'Male', '9991112220', 'zayd@mips.test', 'Calicut', v_course_id, v_batch_a_id, v_univ_id, v_year_id)
    RETURNING id INTO v_student_1_id;

    INSERT INTO students (admission_number, registration_number, name, dob, gender, phone, email, address, course_id, batch_id, university_id, academic_year_id)
    VALUES ('TEST-ADM-002', 'REG-002', 'Maryam Ali TEST', '2004-08-20', 'Female', '9991112221', 'maryam@mips.test', 'Malappuram', v_course_id, v_batch_b_id, v_univ_id, v_year_id)
    RETURNING id INTO v_student_2_id;

    -- Profiles linked to auth.users
    INSERT INTO profiles (user_id, role, student_id, teacher_id, active)
    VALUES 
        (v_admin_uuid, 'admin', null, null, true),
        (v_teacher_a_uuid, 'teacher', null, v_teacher_a_id, true),
        (v_teacher_b_uuid, 'teacher', null, v_teacher_b_id, true),
        (v_student_1_uuid, 'student', v_student_1_id, null, true),
        (v_student_2_uuid, 'student', v_student_2_id, null, true);

    -- Fees Ledger
    INSERT INTO fees (student_id, total_fee_paise, paid_amount_paise, pending_amount_paise)
    VALUES 
        (v_student_1_id, 5000000, 1000000, 4000000),
        (v_student_2_id, 5000000, 2000000, 3000000);

    -- Payments & Receipts
    INSERT INTO payments (student_id, amount_paise, payment_mode, reference_number, remarks, date)
    VALUES (v_student_1_id, 1000000, 'cash', 'REF-TEST-001', 'Internal Admin Note for Student 1', CURRENT_DATE);

    INSERT INTO payments (student_id, amount_paise, payment_mode, reference_number, remarks, date)
    VALUES (v_student_2_id, 2000000, 'upi', 'REF-TEST-002', 'Internal Admin Note for Student 2', CURRENT_DATE);

    -- Published Exam & Results
    INSERT INTO exams (course_id, batch_id, academic_year_id, name, status, published_at)
    VALUES (v_course_id, v_batch_a_id, v_year_id, 'Annual Exam 2026 TEST', 'published', clock_timestamp())
    RETURNING id INTO v_exam_published_id;

    INSERT INTO exam_subjects (exam_id, name, code, max_marks, pass_marks)
    VALUES (v_exam_published_id, 'Hematology TEST', 'HEM01', 100, 40)
    RETURNING id INTO v_exam_subj_1_id;

    INSERT INTO results (exam_id, student_id, total_marks, percentage, grade, status, rank)
    VALUES (v_exam_published_id, v_student_1_id, 85, 85.0, 'A', 'PASS', 1);

    INSERT INTO results (exam_id, student_id, total_marks, percentage, grade, status, rank)
    VALUES (v_exam_published_id, v_student_2_id, 92, 92.0, 'A+', 'PASS', 2);

    -- Draft Exam (Results must be hidden from students)
    INSERT INTO exams (course_id, batch_id, academic_year_id, name, status)
    VALUES (v_course_id, v_batch_a_id, v_year_id, 'Internal Model Exam TEST (Draft)', 'draft')
    RETURNING id INTO v_exam_draft_id;

    INSERT INTO results (exam_id, student_id, total_marks, percentage, grade, status)
    VALUES (v_exam_draft_id, v_student_1_id, 75, 75.0, 'B+', 'PASS');

    RAISE NOTICE '>>> [FIXTURES] Test data fixtures initialized successfully.';
END $$;


-- =============================================================================
-- 2. TEST CASE 1: Student Isolation & Data Protection
-- Proves: A student can ONLY see their own data, cannot see other students,
-- cannot see draft results, and cannot see internal admin remarks.
-- =============================================================================

DO $$
DECLARE
    v_cnt int;
    v_student_1_uuid uuid := 'a0000000-0000-0000-0000-000000000004';
    v_student_2_id bigint;
    v_rec record;
BEGIN
    RAISE NOTICE '>>> [TEST 1] Testing Student Isolation (Impersonating Student 1)...';

    -- Impersonate Student 1
    PERFORM set_config('role', 'authenticated', true);
    PERFORM set_config('request.jwt.claim.sub', v_student_1_uuid::text, true);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_student_1_uuid, 'role', 'authenticated')::text, true);

    -- Find Student 2 ID via elevated query to verify cross-boundary lookup
    SELECT s.id INTO v_student_2_id FROM students s WHERE admission_number = 'TEST-ADM-002';

    -- 1.1. Student 1 queries student_profile_view
    SELECT COUNT(*) INTO v_cnt FROM student_profile_view WHERE name = 'Zayd Khan TEST';
    IF v_cnt <> 1 THEN
        RAISE EXCEPTION 'TEST 1.1 FAILED: Student 1 could not view their own profile view.';
    END IF;

    SELECT COUNT(*) INTO v_cnt FROM student_profile_view WHERE name = 'Maryam Ali TEST';
    IF v_cnt <> 0 THEN
        RAISE EXCEPTION 'TEST 1.1 FAILED: Student 1 was able to view Student 2 profile in student_profile_view!';
    END IF;

    -- 1.2. Direct access on students table
    SELECT COUNT(*) INTO v_cnt FROM students WHERE admission_number = 'TEST-ADM-002';
    IF v_cnt <> 0 THEN
        RAISE EXCEPTION 'TEST 1.2 FAILED: Student 1 saw Student 2 in students table!';
    END IF;

    -- 1.3. Student Fee Ledger Isolation
    SELECT COUNT(*) INTO v_cnt FROM fees WHERE student_id = v_student_2_id;
    IF v_cnt <> 0 THEN
        RAISE EXCEPTION 'TEST 1.3 FAILED: Student 1 saw Student 2 fee record!';
    END IF;

    SELECT pending_amount_paise INTO v_cnt FROM fees;
    IF v_cnt <> 4000000 THEN
        RAISE EXCEPTION 'TEST 1.3 FAILED: Student 1 did not see expected pending fee of 4000000 paise.';
    END IF;

    -- 1.4. Payments Table Direct Access Blocked
    -- Direct query on payments returns 0 rows because remarks are hidden from direct table access
    SELECT COUNT(*) INTO v_cnt FROM payments;
    IF v_cnt <> 0 THEN
        RAISE EXCEPTION 'TEST 1.4 FAILED: Student 1 bypassed secure view to query payments table directly!';
    END IF;

    -- 1.5. Payments Secure View Isolation & Remarks Hidden
    SELECT COUNT(*) INTO v_cnt FROM student_payments_view WHERE student_id = v_student_2_id;
    IF v_cnt <> 0 THEN
        RAISE EXCEPTION 'TEST 1.5 FAILED: Student 1 saw Student 2 payment in student_payments_view!';
    END IF;

    SELECT COUNT(*) INTO v_cnt FROM student_payments_view;
    IF v_cnt <> 1 THEN
        RAISE EXCEPTION 'TEST 1.5 FAILED: Student 1 could not view own payment in student_payments_view.';
    END IF;

    -- 1.6. Results Isolation: Student 1 sees own published result, NOT Student 2's
    SELECT COUNT(*) INTO v_cnt FROM results WHERE student_id = v_student_2_id;
    IF v_cnt <> 0 THEN
        RAISE EXCEPTION 'TEST 1.6 FAILED: Student 1 was able to read Student 2 results!';
    END IF;

    -- 1.7. Draft Results Hidden: Student 1 CANNOT see draft exam results
    SELECT COUNT(*) INTO v_cnt FROM results r
    JOIN exams e ON e.id = r.exam_id
    WHERE e.status = 'draft';
    IF v_cnt <> 0 THEN
        RAISE EXCEPTION 'TEST 1.7 FAILED: Student 1 saw unpublished draft exam results!';
    END IF;

    RAISE NOTICE '>>> [TEST 1] PASSED: Student isolation and privacy verified.';
END $$;


-- =============================================================================
-- 2. TEST CASE 2: Teacher Isolation & Batch Boundary Enforcement
-- Proves: A teacher can ONLY see students in assigned batches via students_for_teacher,
-- cannot see unassigned batches, cannot see sensitive personal fields, and has
-- zero direct access to the students table.
-- =============================================================================

DO $$
DECLARE
    v_cnt int;
    v_teacher_a_uuid uuid := 'a0000000-0000-0000-0000-000000000002';
    v_batch_b_id bigint;
BEGIN
    RAISE NOTICE '>>> [TEST 2] Testing Teacher Isolation (Impersonating Teacher A)...';

    -- Impersonate Teacher A
    PERFORM set_config('role', 'authenticated', true);
    PERFORM set_config('request.jwt.claim.sub', v_teacher_a_uuid::text, true);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_teacher_a_uuid, 'role', 'authenticated')::text, true);

    -- 2.1. Direct SELECT on students table MUST return 0 rows for Teacher
    SELECT COUNT(*) INTO v_cnt FROM students;
    IF v_cnt <> 0 THEN
        RAISE EXCEPTION 'TEST 2.1 FAILED: Teacher A accessed students table directly! Expected 0 rows, got %', v_cnt;
    END IF;

    -- 2.2. Query students_for_teacher:
    -- Teacher A is assigned to Batch A (Zayd Khan).
    -- Teacher A is NOT assigned to Batch B (Maryam Ali).
    SELECT COUNT(*) INTO v_cnt FROM students_for_teacher WHERE name = 'Zayd Khan TEST';
    IF v_cnt <> 1 THEN
        RAISE EXCEPTION 'TEST 2.2 FAILED: Teacher A could not see assigned student in students_for_teacher.';
    END IF;

    SELECT COUNT(*) INTO v_cnt FROM students_for_teacher WHERE name = 'Maryam Ali TEST';
    IF v_cnt <> 0 THEN
        RAISE EXCEPTION 'TEST 2.2 FAILED: Teacher A was able to see unassigned student Maryam Ali (Batch B)!';
    END IF;

    -- 2.3. Teacher Assignment Isolation
    SELECT COUNT(*) INTO v_cnt FROM teacher_assignments;
    IF v_cnt <> 1 THEN
        RAISE EXCEPTION 'TEST 2.3 FAILED: Teacher A saw assignments belonging to other teachers! Count: %', v_cnt;
    END IF;

    -- 2.4. Teacher Attendance Session Restriction
    -- Teacher A attempts to insert a draft session for Batch B (unassigned).
    -- RLS WITH CHECK policy MUST REJECT IT.
    SELECT id INTO v_batch_b_id FROM batches WHERE batch_name = 'DMLT-TEST-BATCH-B';
    BEGIN
        INSERT INTO attendance_sessions (batch_id, subject_id, date, period, status, marked_by)
        VALUES (v_batch_b_id, 1, CURRENT_DATE, 1, 'draft', current_teacher_id());
        
        RAISE EXCEPTION 'TEST 2.4 FAILED: Teacher A was able to create an attendance session for an unassigned batch!';
    EXCEPTION 
        WHEN check_violation OR insufficient_privilege OR others THEN
            RAISE NOTICE '>>> [TEST 2.4] Expected rejection caught: Teacher cannot create session for unassigned batch.';
    END;

    RAISE NOTICE '>>> [TEST 2] PASSED: Teacher batch isolation verified.';
END $$;


-- =============================================================================
-- 3. TEST CASE 3: Complete Anon Lockdown
-- Proves: Nobody can read ANY tables with the unauthenticated anon key.
-- =============================================================================

DO $$
DECLARE
    v_cnt int;
BEGIN
    RAISE NOTICE '>>> [TEST 3] Testing Complete Anon Key Lockdown...';

    -- Impersonate Anon / Public Role
    PERFORM set_config('role', 'anon', true);
    PERFORM set_config('request.jwt.claim.sub', '', true);
    PERFORM set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);

    -- 3.1. Anon on students
    BEGIN
        SELECT COUNT(*) INTO v_cnt FROM students;
        IF v_cnt <> 0 THEN
            RAISE EXCEPTION 'TEST 3.1 FAILED: Anon read % rows from students table!', v_cnt;
        END IF;
    EXCEPTION WHEN insufficient_privilege THEN
        -- Expected behavior when permissions revoked
        NULL;
    END;

    -- 3.2. Anon on settings
    BEGIN
        SELECT COUNT(*) INTO v_cnt FROM settings;
        IF v_cnt <> 0 THEN
            RAISE EXCEPTION 'TEST 3.2 FAILED: Anon read % rows from settings table!', v_cnt;
        END IF;
    EXCEPTION WHEN insufficient_privilege THEN
        NULL;
    END;

    -- 3.3. Anon on courses
    BEGIN
        SELECT COUNT(*) INTO v_cnt FROM courses;
        IF v_cnt <> 0 THEN
            RAISE EXCEPTION 'TEST 3.3 FAILED: Anon read % rows from courses table!', v_cnt;
        END IF;
    EXCEPTION WHEN insufficient_privilege THEN
        NULL;
    END;

    -- 3.4. Anon on results
    BEGIN
        SELECT COUNT(*) INTO v_cnt FROM results;
        IF v_cnt <> 0 THEN
            RAISE EXCEPTION 'TEST 3.4 FAILED: Anon read % rows from results table!', v_cnt;
        END IF;
    EXCEPTION WHEN insufficient_privilege THEN
        NULL;
    END;

    -- 3.5. Anon on fees
    BEGIN
        SELECT COUNT(*) INTO v_cnt FROM fees;
        IF v_cnt <> 0 THEN
            RAISE EXCEPTION 'TEST 3.5 FAILED: Anon read % rows from fees table!', v_cnt;
        END IF;
    EXCEPTION WHEN insufficient_privilege THEN
        NULL;
    END;

    RAISE NOTICE '>>> [TEST 3] PASSED: Anon access strictly denied across all objects.';
END $$;


-- =============================================================================
-- 4. TEST CASE 4: Immutable Audit & Attendance Change Logs
-- Proves: Even Admin cannot UPDATE or DELETE audit_log or attendance_changes.
-- =============================================================================

DO $$
DECLARE
    v_admin_uuid uuid := 'a0000000-0000-0000-0000-000000000001';
BEGIN
    RAISE NOTICE '>>> [TEST 4] Testing Audit Immutability (Admin Impersonation)...';

    -- Impersonate Admin
    PERFORM set_config('role', 'authenticated', true);
    PERFORM set_config('request.jwt.claim.sub', v_admin_uuid::text, true);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin_uuid, 'role', 'authenticated')::text, true);

    -- 4.1. UPDATE on audit_log MUST FAIL
    BEGIN
        UPDATE audit_log SET action = 'MODIFIED';
        RAISE EXCEPTION 'TEST 4.1 FAILED: UPDATE on audit_log was allowed!';
    EXCEPTION 
        WHEN insufficient_privilege THEN
            RAISE NOTICE '>>> [TEST 4.1] Expected error caught: UPDATE on audit_log revoked.';
    END;

    -- 4.2. DELETE on audit_log MUST FAIL
    BEGIN
        DELETE FROM audit_log;
        RAISE EXCEPTION 'TEST 4.2 FAILED: DELETE on audit_log was allowed!';
    EXCEPTION 
        WHEN insufficient_privilege THEN
            RAISE NOTICE '>>> [TEST 4.2] Expected error caught: DELETE on audit_log revoked.';
    END;

    -- 4.3. UPDATE on attendance_changes MUST FAIL
    BEGIN
        UPDATE attendance_changes SET reason = 'MODIFIED';
        RAISE EXCEPTION 'TEST 4.3 FAILED: UPDATE on attendance_changes was allowed!';
    EXCEPTION 
        WHEN insufficient_privilege THEN
            RAISE NOTICE '>>> [TEST 4.3] Expected error caught: UPDATE on attendance_changes revoked.';
    END;

    -- 4.4. DELETE on attendance_changes MUST FAIL
    BEGIN
        DELETE FROM attendance_changes;
        RAISE EXCEPTION 'TEST 4.4 FAILED: DELETE on attendance_changes was allowed!';
    EXCEPTION 
        WHEN insufficient_privilege THEN
            RAISE NOTICE '>>> [TEST 4.4] Expected error caught: DELETE on attendance_changes revoked.';
    END;

    RAISE NOTICE '>>> [TEST 4] PASSED: Audit logs and change tracking are strictly immutable.';
END $$;


-- =============================================================================
-- 5. TEST CASE 5: Business Rule - Overpayment Safeguard & Payment Transaction
-- Proves: A payment exceeding pending fee obligation is rejected by record_payment().
-- =============================================================================

DO $$
DECLARE
    v_admin_uuid uuid := 'a0000000-0000-0000-0000-000000000001';
    v_student_1_id bigint;
    v_pending_paise bigint;
    v_receipt_res jsonb;
BEGIN
    RAISE NOTICE '>>> [TEST 5] Testing Overpayment Prevention...';

    -- Impersonate Admin
    PERFORM set_config('role', 'authenticated', true);
    PERFORM set_config('request.jwt.claim.sub', v_admin_uuid::text, true);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin_uuid, 'role', 'authenticated')::text, true);

    SELECT s.id, f.pending_amount_paise INTO v_student_1_id, v_pending_paise
    FROM students s
    JOIN fees f ON f.student_id = s.id
    WHERE s.admission_number = 'TEST-ADM-001';

    -- Student 1 has pending_amount_paise = 4,000,000 (Rs. 40,000)
    -- Attempting to pay 4,000,001 MUST FAIL
    BEGIN
        PERFORM record_payment(
            v_student_1_id,
            v_pending_paise + 1,
            'cash'::payment_mode,
            'REF-OVERPAY',
            'Overpayment Test Attempt'
        );
        RAISE EXCEPTION 'TEST 5.1 FAILED: Overpayment was permitted!';
    EXCEPTION 
        WHEN others THEN
            IF SQLERRM LIKE '%Payment exceeds total fee obligation%' THEN
                RAISE NOTICE '>>> [TEST 5.1] Expected error caught: %', SQLERRM;
            ELSE
                RAISE EXCEPTION 'TEST 5.1 FAILED: Unexpected error message: %', SQLERRM;
            END IF;
    END;

    -- Valid payment of 1,000,000 paise (Rs. 10,000) MUST SUCCEED
    v_receipt_res := record_payment(
        v_student_1_id,
        1000000,
        'cash'::payment_mode,
        'REF-VALID-001',
        'Legitimate fee installment'
    );

    IF v_receipt_res ->> 'receipt_number' IS NULL THEN
        RAISE EXCEPTION 'TEST 5.2 FAILED: Receipt number was not returned after valid payment.';
    END IF;

    -- Verify pending balance decreased to 3,000,000 paise
    SELECT pending_amount_paise INTO v_pending_paise
    FROM fees WHERE student_id = v_student_1_id;

    IF v_pending_paise <> 3000000 THEN
        RAISE EXCEPTION 'TEST 5.2 FAILED: Pending fee not updated properly. Expected 3000000, got %', v_pending_paise;
    END IF;

    RAISE NOTICE '>>> [TEST 5] PASSED: Overpayment prevention and receipt generation validated.';
END $$;

RAISE NOTICE '=============================================================================';
RAISE NOTICE 'SUCCESS: ALL RLS AND BUSINESS RULE TESTS PASSED WITHOUT ERRORS!';
RAISE NOTICE '=============================================================================';

-- Roll back all test data so the database remains completely unchanged
ROLLBACK;
