-- =============================================================================
-- MIPS ERP Database Test Suite: import_students_tests.sql
-- Sub-phase 3B: Tests for import_students and undo_import RPCs
-- =============================================================================

BEGIN;

DO $$
DECLARE
    v_admin_id uuid;
    v_course_id bigint;
    v_batch_id bigint;
    v_import_res jsonb;
    v_undo_res jsonb;
    v_batch_tag text := 'test-batch-' || gen_random_uuid()::text;
    v_student_count int;
    v_student_id bigint;
BEGIN
    RAISE NOTICE '=======================================================';
    RAISE NOTICE 'Starting Sub-Phase 3B: Excel Import & Undo Tests...';
    RAISE NOTICE '=======================================================';

    -- Set up test admin user & profile
    SELECT id INTO v_admin_id FROM auth.users WHERE email = 'admin@mips.edu' LIMIT 1;
    IF v_admin_id IS NULL THEN
        v_admin_id := gen_random_uuid();
        INSERT INTO auth.users (id, email) VALUES (v_admin_id, 'test_import_admin@mips.edu');
        INSERT INTO profiles (user_id, role, active) VALUES (v_admin_id, 'admin', true);
    END IF;

    -- Impersonate admin
    PERFORM set_config('request.jwt.claim.sub', v_admin_id::text, true);
    PERFORM set_config('request.jwt.claim.role', 'authenticated', true);

    -- Ensure a test course and batch exist
    SELECT id INTO v_course_id FROM courses WHERE deleted_at IS NULL LIMIT 1;
    IF v_course_id IS NULL THEN
        INSERT INTO courses (name, code, duration, total_fee_paise, status)
        VALUES ('Test Import Nursing', 'TIN-01', '3 Years', 5000000, 'active')
        RETURNING id INTO v_course_id;
    END IF;

    SELECT id INTO v_batch_id FROM batches WHERE course_id = v_course_id AND deleted_at IS NULL LIMIT 1;
    IF v_batch_id IS NULL THEN
        INSERT INTO batches (course_id, batch_name, start_date)
        VALUES (v_course_id, 'Batch 2026', '2026-06-01')
        RETURNING id INTO v_batch_id;
    END IF;

    -- -------------------------------------------------------------------------
    -- Test 1: import_students creates students and initial fees atomically
    -- -------------------------------------------------------------------------
    RAISE NOTICE 'Test 1: Executing import_students for 2 valid rows...';

    v_import_res := import_students(
        jsonb_build_array(
            jsonb_build_object(
                'name', 'Import Test Student 1',
                'course_id', v_course_id,
                'batch_id', v_batch_id,
                'gender', 'Female',
                'phone', '9876543210'
            ),
            jsonb_build_object(
                'name', 'Import Test Student 2',
                'course_id', v_course_id,
                'batch_id', v_batch_id,
                'gender', 'Male',
                'phone', '9876543211'
            )
        ),
        v_batch_tag
    );

    ASSERT (v_import_res->>'success')::boolean = true, 'Import should succeed';
    ASSERT (v_import_res->>'imported_count')::int = 2, 'Expected 2 imported students';
    ASSERT (v_import_res->>'import_batch_id') = v_batch_tag, 'Batch tag should match';

    SELECT count(*) INTO v_student_count
    FROM students
    WHERE import_batch_id = v_batch_tag AND deleted_at IS NULL;
    ASSERT v_student_count = 2, 'Expected 2 active students in database with import_batch_id';

    -- Verify fees created
    ASSERT (
        SELECT count(*) FROM fees f
        JOIN students s ON f.student_id = s.id
        WHERE s.import_batch_id = v_batch_tag
    ) = 2, 'Initial fee entries must be created for each imported student';

    RAISE NOTICE '  [PASS] import_students created students and fees atomically.';

    -- -------------------------------------------------------------------------
    -- Test 2: undo_import blocks if payments exist
    -- -------------------------------------------------------------------------
    RAISE NOTICE 'Test 2: Verifying undo_import protects against active payments...';

    SELECT id INTO v_student_id
    FROM students WHERE import_batch_id = v_batch_tag LIMIT 1;

    -- Record a dummy payment
    INSERT INTO payments (student_id, amount_paise, payment_mode, date)
    VALUES (v_student_id, 100000, 'cash', CURRENT_DATE);

    BEGIN
        PERFORM undo_import(v_batch_tag);
        RAISE EXCEPTION 'undo_import should have failed because active payment exists!';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%active payment%' THEN
            RAISE NOTICE '  [PASS] undo_import blocked correctly due to payment.';
        ELSE
            RAISE EXCEPTION 'Unexpected error: %', SQLERRM;
        END IF;
    END;

    -- Clean up test payment for undo test
    DELETE FROM payments WHERE student_id = v_student_id;

    -- -------------------------------------------------------------------------
    -- Test 3: undo_import rolls back students and fees cleanly
    -- -------------------------------------------------------------------------
    RAISE NOTICE 'Test 3: Executing undo_import...';

    v_undo_res := undo_import(v_batch_tag);
    ASSERT (v_undo_res->>'success')::boolean = true, 'Undo import should succeed';
    ASSERT (v_undo_res->>'undone_count')::int = 2, 'Expected 2 undone students';

    SELECT count(*) INTO v_student_count
    FROM students
    WHERE import_batch_id = v_batch_tag AND deleted_at IS NULL;
    ASSERT v_student_count = 0, 'No active students should remain for undone batch';

    -- Fees should be deleted
    ASSERT (
        SELECT count(*) FROM fees f
        JOIN students s ON f.student_id = s.id
        WHERE s.import_batch_id = v_batch_tag
    ) = 0, 'Initial fees must be removed after undo';

    RAISE NOTICE '  [PASS] undo_import cleanly rolled back batch.';

    -- -------------------------------------------------------------------------
    -- Test 4: Cannot undo already undone batch
    -- -------------------------------------------------------------------------
    RAISE NOTICE 'Test 4: Verifying double undo rejection...';
    BEGIN
        PERFORM undo_import(v_batch_tag);
        RAISE EXCEPTION 'undo_import should have rejected already undone batch!';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%already been undone%' THEN
            RAISE NOTICE '  [PASS] Duplicate undo rejected.';
        ELSE
            RAISE EXCEPTION 'Unexpected error: %', SQLERRM;
        END IF;
    END;

    RAISE NOTICE '=======================================================';
    RAISE NOTICE 'All Sub-Phase 3B Database & RPC Tests Passed!';
    RAISE NOTICE '=======================================================';
END;
$$;

ROLLBACK;
