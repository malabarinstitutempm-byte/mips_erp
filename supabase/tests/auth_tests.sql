-- =============================================================================
-- MIPS ERP Database Test Suite: auth_tests.sql
-- Sub-phase 2B: Verification of Lockout Mechanics, Brute-Force Protection,
-- Admin Account Unlocking, and Password State Transitions
-- =============================================================================

BEGIN;

DO $$
DECLARE
    v_admin_uuid uuid := 'b0000000-0000-0000-0000-000000000001';
    v_student_uuid uuid := 'b0000000-0000-0000-0000-000000000002';
    v_student_id bigint;
    v_res jsonb;
    v_check jsonb;
BEGIN
    RAISE NOTICE '>>> [AUTH TESTS] Initializing test fixtures...';

    -- Mock auth.users (if auth schema exists)
    BEGIN
        INSERT INTO auth.users (id, email, aud, role)
        VALUES 
            (v_admin_uuid, 'admin_auth_test@mips.test', 'authenticated', 'authenticated'),
            (v_student_uuid, 'student_auth_test@mips.test', 'authenticated', 'authenticated')
        ON CONFLICT (id) DO NOTHING;
    EXCEPTION WHEN undefined_table THEN
        NULL;
    END;

    -- Create mock student
    INSERT INTO students (admission_number, name, dob, course_id, batch_id, status)
    VALUES ('AUTH-TEST-001', 'Test Student Auth', '2005-01-01', 1, 1, 'active')
    RETURNING id INTO v_student_id;

    -- Create mock profiles
    INSERT INTO profiles (user_id, role, active, failed_attempts, must_change_password)
    VALUES (v_admin_uuid, 'admin', true, 0, false);

    INSERT INTO profiles (user_id, role, student_id, active, failed_attempts, must_change_password)
    VALUES (v_student_uuid, 'student', v_student_id, true, 0, true);

    RAISE NOTICE '>>> [AUTH TESTS] Fixtures ready. Testing Lockout & Brute-Force Prevention...';

    -- Test 1: Check initial lockout state (should not be locked)
    v_check := check_account_lockout(v_student_uuid);
    IF (v_check ->> 'is_locked')::boolean IS TRUE THEN
        RAISE EXCEPTION 'TEST 1 FAILED: Account was locked initially!';
    END IF;

    -- Test 2: Simulate 4 consecutive failed login attempts (should NOT lock yet)
    FOR i IN 1..4 LOOP
        v_res := record_failed_login(v_student_uuid);
        IF (v_res ->> 'is_locked')::boolean IS TRUE THEN
            RAISE EXCEPTION 'TEST 2 FAILED: Account locked before reaching threshold (attempt %)!', i;
        END IF;
    END LOOP;

    -- Verify attempts = 4
    v_check := check_account_lockout(v_student_uuid);
    IF (v_check ->> 'failed_attempts')::int <> 4 THEN
        RAISE EXCEPTION 'TEST 2 FAILED: Failed attempts count expected 4, got %', v_check ->> 'failed_attempts';
    END IF;

    -- Test 3: 5th failed attempt MUST LOCK the account
    v_res := record_failed_login(v_student_uuid);
    IF (v_res ->> 'is_locked')::boolean IS NOT TRUE THEN
        RAISE EXCEPTION 'TEST 3 FAILED: 5th failed attempt did NOT lock the account!';
    END IF;

    v_check := check_account_lockout(v_student_uuid);
    IF (v_check ->> 'is_locked')::boolean IS NOT TRUE THEN
        RAISE EXCEPTION 'TEST 3 FAILED: check_account_lockout did not report account as locked!';
    END IF;

    IF (v_check ->> 'remaining_seconds')::int <= 0 THEN
        RAISE EXCEPTION 'TEST 3 FAILED: Lockout remaining seconds was not set!';
    END IF;

    RAISE NOTICE '>>> [AUTH TESTS] 5th failed attempt triggered 15-minute lockout successfully.';

    -- Test 4: Non-admin cannot unlock account
    PERFORM set_config('role', 'authenticated', true);
    PERFORM set_config('request.jwt.claim.sub', v_student_uuid::text, true);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_student_uuid, 'role', 'authenticated')::text, true);

    BEGIN
        PERFORM admin_unlock_account(v_student_uuid);
        RAISE EXCEPTION 'TEST 4 FAILED: Student was able to invoke admin_unlock_account!';
    EXCEPTION WHEN others THEN
        IF SQLERRM LIKE '%Access denied%' THEN
            RAISE NOTICE '>>> [AUTH TEST 4] Expected permission rejection caught for non-admin unlock.';
        ELSE
            RAISE EXCEPTION 'TEST 4 FAILED: Unexpected error message: %', SQLERRM;
        END IF;
    END;

    -- Test 5: Admin unlocks account successfully
    PERFORM set_config('request.jwt.claim.sub', v_admin_uuid::text, true);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin_uuid, 'role', 'authenticated')::text, true);

    v_res := admin_unlock_account(v_student_uuid);
    IF (v_res ->> 'success')::boolean IS NOT TRUE THEN
        RAISE EXCEPTION 'TEST 5 FAILED: Admin failed to unlock account: %', v_res;
    END IF;

    v_check := check_account_lockout(v_student_uuid);
    IF (v_check ->> 'is_locked')::boolean IS TRUE THEN
        RAISE EXCEPTION 'TEST 5 FAILED: Account is still locked after admin unlock!';
    END IF;

    IF (v_check ->> 'failed_attempts')::int <> 0 THEN
        RAISE EXCEPTION 'TEST 5 FAILED: Failed attempts were not cleared after admin unlock!';
    END IF;

    RAISE NOTICE '>>> [AUTH TESTS] Admin unlock validated successfully.';

    -- Test 6: Successful login clears failed attempts
    PERFORM record_failed_login(v_student_uuid); -- attempt 1
    v_res := record_successful_login(v_student_uuid);
    v_check := check_account_lockout(v_student_uuid);
    IF (v_check ->> 'failed_attempts')::int <> 0 THEN
        RAISE EXCEPTION 'TEST 6 FAILED: Successful login did not reset failed attempts!';
    END IF;

    -- Test 7: Acknowledge password change clears must_change_password
    PERFORM set_config('request.jwt.claim.sub', v_student_uuid::text, true);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_student_uuid, 'role', 'authenticated')::text, true);

    v_res := acknowledge_password_change();
    v_check := check_account_lockout(v_student_uuid);
    IF (v_check ->> 'must_change_password')::boolean IS TRUE THEN
        RAISE EXCEPTION 'TEST 7 FAILED: must_change_password flag was not cleared!';
    END IF;

    RAISE NOTICE '=============================================================================';
    RAISE NOTICE 'SUCCESS: ALL PHASE 2 AUTH AND LOCKOUT TESTS PASSED!';
    RAISE NOTICE '=============================================================================';
END $$;

ROLLBACK;
