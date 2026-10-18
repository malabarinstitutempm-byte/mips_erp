-- =============================================================================
-- MIPS ERP Database Test Suite: auth_flow_tests.sql
-- Sub-phase 2D: End-to-End Database Auth Flow & Security Validation
-- =============================================================================

BEGIN;

DO $$
DECLARE
    v_admin_id uuid := 'a0000000-0000-0000-0000-000000000001';
    v_teacher_id bigint;
    v_teacher_user_id uuid := 'a0000000-0000-0000-0000-000000000002';
    v_student_id bigint;
    v_student_user_id uuid := 'a0000000-0000-0000-0000-000000000003';
    v_course_id bigint;
    v_batch_id bigint;
    v_subject_id bigint;
    v_draft_session_id bigint;
    v_res jsonb;
    v_is_adm boolean;
BEGIN
    RAISE NOTICE '=======================================================';
    RAISE NOTICE 'Starting Sub-Phase 2D Auth Flow Database Test Suite...';
    RAISE NOTICE '=======================================================';

    -- -------------------------------------------------------------------------
    -- Setup Test Fixtures
    -- -------------------------------------------------------------------------
    -- Academic prerequisites
    INSERT INTO courses (name, code, duration_years, total_fee_paise)
    VALUES ('BCA Test', 'BCA_T', 3, 15000000)
    RETURNING id INTO v_course_id;

    INSERT INTO batches (course_id, name, start_year, end_year)
    VALUES (v_course_id, '2024-2027', 2024, 2027)
    RETURNING id INTO v_batch_id;

    INSERT INTO course_subjects (course_id, name, code, max_marks, pass_marks)
    VALUES (v_course_id, 'Database Systems', 'CS301', 100, 40)
    RETURNING id INTO v_subject_id;

    -- Admin profile
    INSERT INTO profiles (user_id, role, active, must_change_password, failed_attempts)
    VALUES (v_admin_id, 'admin', true, false, 0);

    -- -------------------------------------------------------------------------
    -- Test 1: Admin MFA Function Check (is_admin)
    -- -------------------------------------------------------------------------
    RAISE NOTICE 'Test 1: Testing is_admin() under require_admin_mfa settings...';

    -- Simulate Admin JWT context without MFA (AAL1)
    PERFORM set_config('role', 'authenticated', true);
    PERFORM set_config('request.jwt.claim.sub', v_admin_id::text, true);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin_id, 'role', 'authenticated', 'aal', 'aal1')::text, true);

    -- With require_admin_mfa = 'false', is_admin() should return true
    UPDATE settings SET value = 'false' WHERE key = 'require_admin_mfa';
    v_is_adm := is_admin();
    ASSERT v_is_adm = true, 'is_admin() should pass when MFA is false';
    RAISE NOTICE '  [PASS] is_admin() passes under standard non-MFA setting.';

    -- With require_admin_mfa = 'true', AAL1 session MUST BE REJECTED
    UPDATE settings SET value = 'true' WHERE key = 'require_admin_mfa';
    v_is_adm := is_admin();
    ASSERT v_is_adm = false, 'is_admin() must return false when require_admin_mfa is true and session is AAL1';
    RAISE NOTICE '  [PASS] is_admin() strictly rejects AAL1 session when MFA is enabled.';

    -- Simulate Admin JWT context with TOTP MFA verified (AAL2)
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin_id, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    v_is_adm := is_admin();
    ASSERT v_is_adm = true, 'is_admin() must return true when require_admin_mfa is true and session has AAL2';
    RAISE NOTICE '  [PASS] is_admin() authorizes session with AAL2 claim.';

    -- Reset MFA setting to false for remaining operational tests
    UPDATE settings SET value = 'false' WHERE key = 'require_admin_mfa';

    -- -------------------------------------------------------------------------
    -- Test 2: Teacher Provisioning & Assignments
    -- -------------------------------------------------------------------------
    RAISE NOTICE 'Test 2: Verifying Teacher creation and course assignments...';

    INSERT INTO teachers (name, phone, login_username, status)
    VALUES ('Dr. Alan Turing', '9876543210', 'dr_turing', 'active')
    RETURNING id INTO v_teacher_id;

    INSERT INTO profiles (user_id, role, teacher_id, active, must_change_password, first_login_required)
    VALUES (v_teacher_user_id, 'teacher', v_teacher_id, true, true, false);

    INSERT INTO teacher_assignments (teacher_id, course_id, batch_id, subject_id, active)
    VALUES (v_teacher_id, v_course_id, v_batch_id, v_subject_id, true);

    ASSERT EXISTS (
        SELECT 1 FROM teacher_assignments
        WHERE teacher_id = v_teacher_id AND active = true
    ), 'Teacher assignment record must exist and be active';
    RAISE NOTICE '  [PASS] Teacher master record and active assignment linked.';

    -- -------------------------------------------------------------------------
    -- Test 3: Teacher Open Draft Attendance Sessions Handling
    -- -------------------------------------------------------------------------
    RAISE NOTICE 'Test 3: Checking draft attendance session tracking for teacher...';

    INSERT INTO attendance_sessions (batch_id, subject_id, date, period, status, marked_by)
    VALUES (v_batch_id, v_subject_id, CURRENT_DATE, 1, 'draft', v_teacher_id)
    RETURNING id INTO v_draft_session_id;

    ASSERT EXISTS (
        SELECT 1 FROM attendance_sessions
        WHERE marked_by = v_teacher_id AND status = 'draft'
    ), 'Open draft session must be detected for teacher';
    RAISE NOTICE '  [PASS] Open draft attendance session detected for teacher.';

    -- -------------------------------------------------------------------------
    -- Test 4: Student First-Login Lifecycle Flags
    -- -------------------------------------------------------------------------
    RAISE NOTICE 'Test 4: Verifying Student first_login_required state...';

    INSERT INTO students (admission_number, registration_number, name, dob, course_id, batch_id, status)
    VALUES ('ADM-2024-0099', 'REG-2024-0099', 'Ada Lovelace', '2005-12-10', v_course_id, v_batch_id, 'active')
    RETURNING id INTO v_student_id;

    -- Before first login: profile initialized with first_login_required = true
    INSERT INTO profiles (user_id, role, student_id, active, must_change_password, first_login_required)
    VALUES (v_student_user_id, 'student', v_student_id, true, false, true);

    ASSERT (SELECT first_login_required FROM profiles WHERE user_id = v_student_user_id) = true,
        'Student profile must indicate first_login_required = true';

    -- Simulate password initialization completing first login
    UPDATE profiles
    SET first_login_required = false,
        updated_at = clock_timestamp()
    WHERE user_id = v_student_user_id;

    ASSERT (SELECT first_login_required FROM profiles WHERE user_id = v_student_user_id) = false,
        'Student profile must clear first_login_required after initialization';
    RAISE NOTICE '  [PASS] Student first login initialization lifecycle validated.';

    -- -------------------------------------------------------------------------
    -- Test 5: Admin Unlock Account Procedure (admin_unlock_user)
    -- -------------------------------------------------------------------------
    RAISE NOTICE 'Test 5: Testing admin_unlock_user procedure...';

    -- Simulate locked student
    UPDATE profiles
    SET failed_attempts = 5,
        locked_at = clock_timestamp() - interval '5 minutes'
    WHERE user_id = v_student_user_id;

    ASSERT (SELECT locked_at IS NOT NULL FROM profiles WHERE user_id = v_student_user_id) = true,
        'Student should be locked prior to unlock';

    -- Admin unlocks user
    v_res := admin_unlock_user(v_student_user_id);
    ASSERT (v_res ->> 'success')::boolean = true, 'admin_unlock_user should return success = true';

    ASSERT (SELECT locked_at IS NULL AND failed_attempts = 0 FROM profiles WHERE user_id = v_student_user_id) = true,
        'Locked timestamp and failed attempts must be cleared';
    RAISE NOTICE '  [PASS] Account successfully unlocked and counters reset.';

    RAISE NOTICE '=======================================================';
    RAISE NOTICE 'All Sub-Phase 2D Database Auth Flow Tests PASSED!';
    RAISE NOTICE '=======================================================';

END $$;

ROLLBACK;
