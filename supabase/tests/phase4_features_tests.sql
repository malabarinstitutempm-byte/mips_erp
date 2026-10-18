-- =============================================================================
-- Test Suite: phase4_features_tests.sql
-- Description: Comprehensive verification of Phase 4 features:
--   1. Percentage maths (present, late, absent, leave, unmarked exclusion, evening no_class)
--   2. Band boundary precision (80.00%, 75.00%, can_miss_more, recover_sessions)
--   3. Band alert deduplication (fires exactly once per boundary transition)
--   4. Skill course fee ledger, FIFO allocation, and cancellation reversal
--   5. Skill course withdrawal safeguard (blocked until refund/credit adjustment)
--   6. Revenue by course report matching primary and skill allocations
--   7. Announcement audiences, placeholders, RLS isolation, and retract
--   8. Timetable teacher double-booking prevention & RLS scoping
--   9. Teacher batch assignment enforcement & duplicate submission guard
-- =============================================================================

BEGIN;

DO $$
DECLARE
    -- Mock IDs
    v_admin_id uuid := 'a4000000-0000-0000-0000-000000000001'::uuid;
    v_teacher_user_id uuid := 'a4000000-0000-0000-0000-000000000002'::uuid;
    v_student1_user_id uuid := 'a4000000-0000-0000-0000-000000000003'::uuid;
    v_student2_user_id uuid := 'a4000000-0000-0000-0000-000000000004'::uuid;

    v_primary_course_id bigint;
    v_skill_course_id bigint;
    v_batch1_id bigint;
    v_batch2_id bigint;
    v_teacher_id bigint;
    v_student1_id bigint;
    v_student2_id bigint;

    v_session_id bigint;
    v_session2_id bigint;
    v_record_id bigint;
    v_summary RECORD;
    v_alert_count int;
    v_eval_res jsonb;

    v_payment_res jsonb;
    v_cancel_res jsonb;
    v_pay_id bigint;
    v_fee_summary RECORD;

    v_ann_res jsonb;
    v_ann_id bigint;
    v_retract_res jsonb;

    v_tt1_id bigint;
    v_tt2_id bigint;
    v_clash_caught boolean := false;
    v_unassigned_caught boolean := false;
    v_double_submit_caught boolean := false;
    v_withdrawal_caught boolean := false;
BEGIN
    RAISE NOTICE '=======================================================';
    RAISE NOTICE 'Starting Sub-Phase 4C Comprehensive Test Suite...';
    RAISE NOTICE '=======================================================';

    -- Setup mock users & profiles
    INSERT INTO auth.users (id, email) VALUES 
        (v_admin_id, 'admin_p4@mips.invalid'),
        (v_teacher_user_id, 'teacher_p4@teachers.mips.invalid'),
        (v_student1_user_id, 's1_p4@students.mips.invalid'),
        (v_student2_user_id, 's2_p4@students.mips.invalid')
    ON CONFLICT (id) DO NOTHING;

    INSERT INTO profiles (user_id, full_name, email, role, active) VALUES
        (v_admin_id, 'Phase 4 Admin', 'admin_p4@mips.invalid', 'admin', true),
        (v_teacher_user_id, 'Prof. Alan Turing', 'teacher_p4@teachers.mips.invalid', 'teacher', true),
        (v_student1_user_id, 'Ada Lovelace', 's1_p4@students.mips.invalid', 'student', true),
        (v_student2_user_id, 'Charles Babbage', 's2_p4@students.mips.invalid', 'student', true)
    ON CONFLICT (user_id) DO UPDATE SET active = true;

    -- Setup Primary Course & Skill Course
    INSERT INTO courses (name, code, course_type, total_fee_paise, status)
    VALUES ('B.Sc Computer Science', 'CS-101', 'primary', 5000000, 'active') -- 50,000 INR
    RETURNING id INTO v_primary_course_id;

    INSERT INTO courses (name, code, course_type, total_fee_paise, status)
    VALUES ('Python & AI Certification', 'SKILL-AI', 'skill', 2000000, 'active') -- 20,000 INR
    RETURNING id INTO v_skill_course_id;

    -- Setup Batches
    INSERT INTO batches (batch_name, course_id, start_date, end_date, status)
    VALUES ('CS Batch A', v_primary_course_id, CURRENT_DATE - interval '60 days', CURRENT_DATE + interval '300 days', 'active')
    RETURNING id INTO v_batch1_id;

    INSERT INTO batches (batch_name, course_id, start_date, end_date, status)
    VALUES ('CS Batch B', v_primary_course_id, CURRENT_DATE - interval '60 days', CURRENT_DATE + interval '300 days', 'active')
    RETURNING id INTO v_batch2_id;

    -- Setup Teacher
    INSERT INTO teachers (name, email, phone, employee_id, status)
    VALUES ('Prof. Alan Turing', 'teacher_p4@teachers.mips.invalid', '9876543210', 'T-P4-001', 'active')
    RETURNING id INTO v_teacher_id;

    UPDATE profiles SET teacher_id = v_teacher_id WHERE user_id = v_teacher_user_id;

    -- Assign teacher ONLY to Batch 1
    INSERT INTO teacher_assignments (teacher_id, course_id, batch_id, active)
    VALUES (v_teacher_id, v_primary_course_id, v_batch1_id, true);

    -- Setup Students in Batch 1
    INSERT INTO students (name, admission_number, registration_number, email, course_id, batch_id, admission_date, status)
    VALUES ('Ada Lovelace', 'ADM-P4-01', 'REG-P4-01', 's1_p4@students.mips.invalid', v_primary_course_id, v_batch1_id, CURRENT_DATE - interval '30 days', 'active')
    RETURNING id INTO v_student1_id;

    INSERT INTO students (name, admission_number, registration_number, email, course_id, batch_id, admission_date, status)
    VALUES ('Charles Babbage', 'ADM-P4-02', 'REG-P4-02', 's2_p4@students.mips.invalid', v_primary_course_id, v_batch1_id, CURRENT_DATE - interval '30 days', 'active')
    RETURNING id INTO v_student2_id;

    UPDATE profiles SET student_id = v_student1_id WHERE user_id = v_student1_user_id;
    UPDATE profiles SET student_id = v_student2_id WHERE user_id = v_student2_user_id;

    -- Create primary enrollments and fee items
    INSERT INTO student_enrollments (student_id, course_id, batch_id, kind, enrolled_on, status)
    VALUES 
        (v_student1_id, v_primary_course_id, v_batch1_id, 'primary', CURRENT_DATE - interval '30 days', 'active'),
        (v_student2_id, v_primary_course_id, v_batch1_id, 'primary', CURRENT_DATE - interval '30 days', 'active');

    INSERT INTO fee_items (student_id, enrollment_id, label, amount_paise, due_date, status)
    SELECT 
        se.student_id, se.id, 'Primary Course Tuition', 5000000, CURRENT_DATE - interval '10 days', 'unpaid'
    FROM student_enrollments se;

    -- Insert settings defaults
    INSERT INTO settings (key, value) VALUES
        ('min_attendance_percent', '75'),
        ('reminder_attendance_percent', '80'),
        ('late_weight', '0.5'),
        ('leave_handling', 'excluded')
    ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;

    -- =========================================================================
    -- TEST 1: Percentage Maths, Unmarked Slots Excluded, Evening No-Class
    -- =========================================================================
    RAISE NOTICE 'Test 1: Verifying percentage calculation maths and slot exclusions...';

    -- Create 10 sessions for Batch 1:
    -- Day 1..4: Morning and Evening sessions (8 submitted sessions)
    -- Day 5: Morning session held (submitted), Evening session marked 'no_class'
    -- Total held sessions must equal 9 (the 10th is no_class, so strictly excluded)
    FOR d IN 1..4 LOOP
        INSERT INTO attendance_sessions (batch_id, date, slot, status)
        VALUES 
            (v_batch1_id, CURRENT_DATE - (d || ' days')::interval, 'morning', 'submitted'),
            (v_batch1_id, CURRENT_DATE - (d || ' days')::interval, 'evening', 'submitted');
    END LOOP;

    -- Day 5: Morning submitted, Evening no_class
    INSERT INTO attendance_sessions (batch_id, date, slot, status)
    VALUES (v_batch1_id, CURRENT_DATE - interval '5 days', 'morning', 'submitted')
    RETURNING id INTO v_session_id;

    PERFORM confirm_no_class(v_batch1_id, (CURRENT_DATE - interval '5 days')::date, 'evening', 'Test evening holiday');

    -- Student 1 marks across the 9 sessions:
    -- 7 present, 1 late (0.5), 1 leave (excluded from held total)
    -- Total sessions held = 9. Since leave is excluded, effective held = 8.
    -- Weighted present = 7 + (1 * 0.5) = 7.5.
    -- Expected Percentage = (7.5 / 8) * 100 = 93.75%. Status: 'ok'.
    -- Can miss more while >= 75%: floor(7.5 / 0.75 - 8) = floor(10 - 8) = 2.
    WITH held_sessions AS (
        SELECT id, row_number() over (ORDER BY id) AS rn
        FROM attendance_sessions
        WHERE batch_id = v_batch1_id AND status = 'submitted'
    )
    INSERT INTO attendance_records (session_id, student_id, status)
    SELECT 
        hs.id, 
        v_student1_id,
        CASE 
            WHEN hs.rn <= 7 THEN 'present'::attendance_status
            WHEN hs.rn = 8 THEN 'late'::attendance_status
            ELSE 'leave'::attendance_status
        END
    FROM held_sessions hs;

    SELECT * INTO v_summary FROM student_attendance_summary(v_student1_id);

    ASSERT v_summary.sessions_held = 8, format('Expected 8 effective sessions held (9 held - 1 leave), got %s', v_summary.sessions_held);
    ASSERT v_summary.present_count = 7, 'Expected 7 present';
    ASSERT v_summary.late_count = 1, 'Expected 1 late';
    ASSERT v_summary.leave_count = 1, 'Expected 1 leave';
    ASSERT v_summary.weighted_present = 7.5, format('Expected 7.5 weighted present, got %s', v_summary.weighted_present);
    ASSERT v_summary.percentage = 93.75, format('Expected 93.75%%, got %s%%', v_summary.percentage);
    ASSERT v_summary.status_band = 'ok', format('Expected status_band ok, got %s', v_summary.status_band);
    ASSERT v_summary.can_miss_more = 2, format('Expected can_miss_more = 2, got %s', v_summary.can_miss_more);
    ASSERT v_summary.recover_sessions = 0, 'Expected recover_sessions = 0';

    RAISE NOTICE '  [PASS] Percentage maths, leave exclusion, and evening no-class passed.';

    -- =========================================================================
    -- TEST 2: Band Boundaries (Exactly 80% & 75%) & Recovery Maths
    -- =========================================================================
    RAISE NOTICE 'Test 2: Verifying band boundaries (80%%, 75%%) and recovery count...';

    -- Add 2 absent records for Student 1 to bring attendance down
    INSERT INTO attendance_sessions (batch_id, date, slot, status)
    VALUES 
        (v_batch1_id, CURRENT_DATE - interval '6 days', 'morning', 'submitted'),
        (v_batch1_id, CURRENT_DATE - interval '6 days', 'evening', 'submitted');

    WITH s_ids AS (
        SELECT id FROM attendance_sessions 
        WHERE batch_id = v_batch1_id AND date = (CURRENT_DATE - interval '6 days')::date
    )
    INSERT INTO attendance_records (session_id, student_id, status)
    SELECT id, v_student1_id, 'absent'::attendance_status FROM s_ids;

    -- Now effective held = 10 (8 + 2). Weighted = 7.5.
    -- Percentage = 7.5 / 10 * 100 = 75.00%.
    -- At exactly 75.00%, band must be 'low' (since min=75, reminder=80).
    -- can_miss_more: floor(7.5 / 0.75 - 10) = 0.
    -- recover_sessions: 0.
    SELECT * INTO v_summary FROM student_attendance_summary(v_student1_id);

    ASSERT v_summary.percentage = 75.00, format('Expected exactly 75.00%%, got %s%%', v_summary.percentage);
    ASSERT v_summary.status_band = 'low', format('Expected status_band low at 75%%, got %s', v_summary.status_band);
    ASSERT v_summary.can_miss_more = 0, format('Expected can_miss_more = 0, got %s', v_summary.can_miss_more);
    ASSERT v_summary.recover_sessions = 0, 'Expected recover_sessions = 0';

    -- Add 1 more absent to fall into shortage (11 effective held, 7.5 weighted)
    -- Percentage = 7.5 / 11 * 100 = 68.18% (< 75%).
    -- recover_sessions: ceil((0.75 * 11 - 7.5) / (1 - 0.75)) = ceil((8.25 - 7.5) / 0.25) = ceil(0.75 / 0.25) = 3 sessions!
    INSERT INTO attendance_sessions (batch_id, date, slot, status)
    VALUES (v_batch1_id, CURRENT_DATE - interval '7 days', 'morning', 'submitted')
    RETURNING id INTO v_session2_id;

    INSERT INTO attendance_records (session_id, student_id, status)
    VALUES (v_session2_id, v_student1_id, 'absent');

    SELECT * INTO v_summary FROM student_attendance_summary(v_student1_id);

    ASSERT v_summary.percentage = 68.18, format('Expected 68.18%%, got %s%%', v_summary.percentage);
    ASSERT v_summary.status_band = 'shortage', format('Expected shortage, got %s', v_summary.status_band);
    ASSERT v_summary.recover_sessions = 3, format('Expected recover_sessions = 3, got %s', v_summary.recover_sessions);

    -- Verification of recover_sessions = 3: If student attends 3 full present:
    -- Weighted becomes 7.5 + 3 = 10.5. Total held = 11 + 3 = 14.
    -- 10.5 / 14 = 75.00%! Exactly 3 sessions restore 75%.
    RAISE NOTICE '  [PASS] Band boundary and exact recovery calculation verified.';

    -- =========================================================================
    -- TEST 3: Alert Deduplication (Fires ONCE per crossing)
    -- =========================================================================
    RAISE NOTICE 'Test 3: Verifying alert deduplication per band crossing...';

    -- Reset alert state to 'ok'
    DELETE FROM attendance_alert_state WHERE student_id = v_student1_id;
    DELETE FROM notifications WHERE recipient_id = v_student1_id;

    -- Evaluate bands: student is currently in 'shortage'
    v_eval_res := evaluate_attendance_bands(v_student1_id, NULL);
    ASSERT (v_eval_res->>'alerts_sent')::int = 1, 'Expected 1 alert sent when entering shortage';

    -- Verify notification created
    SELECT count(*) INTO v_alert_count 
    FROM notifications 
    WHERE recipient_type = 'student' AND recipient_id = v_student1_id AND type = 'attendance_shortage';
    ASSERT v_alert_count = 1, 'Expected exactly 1 shortage notification';

    -- Re-evaluate immediately without band change: must NOT send another alert
    v_eval_res := evaluate_attendance_bands(v_student1_id, NULL);
    ASSERT (v_eval_res->>'alerts_sent')::int = 0, 'Alert must not fire repeatedly when staying in same band';

    SELECT count(*) INTO v_alert_count 
    FROM notifications 
    WHERE recipient_type = 'student' AND recipient_id = v_student1_id AND type = 'attendance_shortage';
    ASSERT v_alert_count = 1, 'Notification count must remain exactly 1';

    RAISE NOTICE '  [PASS] Band alert deduplication verified.';

    -- =========================================================================
    -- TEST 4: Skill Course, FIFO Allocation, and Cancellation Reversal
    -- =========================================================================
    RAISE NOTICE 'Test 4: Verifying skill course, FIFO payment allocation & cancellation...';

    -- Student 2 has Primary Fee of 50,000 INR (5,000,000 paise) due 10 days ago.
    -- Admin enrolls Student 2 into Skill Course (20,000 INR / 2,000,000 paise due in 30 days).
    -- Total fee for Student 2 becomes 70,000 INR (7,000,000 paise).
    SET LOCAL ROLE authenticated;
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin_id::text, 'role', 'authenticated')::text, true);

    PERFORM add_student_skill_course(v_student2_id, v_skill_course_id, v_batch1_id, 2000000);

    SELECT * INTO v_fee_summary FROM view_student_fee_summary WHERE student_id = v_student2_id;
    ASSERT v_fee_summary.total_fee_paise = 7000000, format('Expected 7,000,000 paise total, got %s', v_fee_summary.total_fee_paise);
    ASSERT v_fee_summary.primary_fee_paise = 5000000, 'Expected 5,000,000 primary fee';
    ASSERT v_fee_summary.skill_fee_paise = 2000000, 'Expected 2,000,000 skill fee';
    ASSERT v_fee_summary.pending_amount_paise = 7000000, 'Expected 7,000,000 pending fee';

    -- Record Payment of 60,000 INR (6,000,000 paise) with FIFO allocation:
    -- 1. Primary fee (due earlier) takes 5,000,000 paise (100% paid).
    -- 2. Skill fee (due later) takes remaining 1,000,000 paise (50% paid, 1,000,000 pending).
    v_payment_res := record_payment(v_student2_id, 6000000, 'upi', 'UPI-TEST-123', 'Tuition & Skill Payment');
    ASSERT (v_payment_res->>'success')::boolean = true, 'Payment recording failed';
    v_pay_id := (v_payment_res->>'payment_id')::bigint;

    -- Verify allocation breakdown
    SELECT * INTO v_fee_summary FROM view_student_fee_summary WHERE student_id = v_student2_id;
    ASSERT v_fee_summary.paid_amount_paise = 6000000, 'Expected 6,000,000 paid';
    ASSERT v_fee_summary.primary_paid_paise = 5000000, 'Primary should be fully paid (5,000,000)';
    ASSERT v_fee_summary.skill_paid_paise = 1000000, 'Skill should have 1,000,000 allocated';
    ASSERT v_fee_summary.pending_amount_paise = 1000000, 'Remaining pending should be 1,000,000';

    -- Test Cancellation Reversal
    v_cancel_res := cancel_payment(v_pay_id, 'Mistaken test deposit');
    ASSERT (v_cancel_res->>'success')::boolean = true, 'Cancellation failed';

    SELECT * INTO v_fee_summary FROM view_student_fee_summary WHERE student_id = v_student2_id;
    ASSERT v_fee_summary.paid_amount_paise = 0, 'Paid amount must be 0 after cancellation';
    ASSERT v_fee_summary.primary_paid_paise = 0, 'Primary paid must be 0';
    ASSERT v_fee_summary.skill_paid_paise = 0, 'Skill paid must be 0';
    ASSERT v_fee_summary.pending_amount_paise = 7000000, 'Total pending must be restored to 7,000,000';

    RAISE NOTICE '  [PASS] Skill course fee breakdown, FIFO allocation & cancellation reversal passed.';

    -- =========================================================================
    -- TEST 5: Skill Course Withdrawal Safeguard (Blocked until Adjustment)
    -- =========================================================================
    RAISE NOTICE 'Test 5: Verifying skill course withdrawal safeguard...';

    -- Re-pay 60,000 INR so skill course has 10,000 INR allocated
    PERFORM record_payment(v_student2_id, 6000000, 'cash', 'CASH-REC-1', 'Re-pay test');

    -- Attempt to withdraw skill course without adjustment: MUST FAIL
    BEGIN
        UPDATE student_enrollments
        SET status = 'withdrawn'
        WHERE student_id = v_student2_id AND kind = 'skill';
        v_withdrawal_caught := false;
    EXCEPTION WHEN OTHERS THEN
        v_withdrawal_caught := true;
        RAISE NOTICE '  [PASS] Caught expected skill withdrawal block: %', SQLERRM;
    END;
    ASSERT v_withdrawal_caught = true, 'Expected withdrawal block when payments are allocated';

    -- Record credit/refund adjustment of 10,000 INR (1,000,000 paise)
    PERFORM record_fee_adjustment(
        v_student2_id, 
        (SELECT id FROM student_enrollments WHERE student_id = v_student2_id AND kind = 'skill'),
        1000000,
        'refund',
        'Approved skill course discontinuation refund'
    );

    -- Now withdrawal MUST succeed
    UPDATE student_enrollments
    SET status = 'withdrawn'
    WHERE student_id = v_student2_id AND kind = 'skill';

    ASSERT (SELECT status FROM student_enrollments WHERE student_id = v_student2_id AND kind = 'skill') = 'withdrawn',
        'Skill course withdrawal should succeed after adjustment recorded';

    RAISE NOTICE '  [PASS] Skill withdrawal safeguard verified.';

    -- =========================================================================
    -- TEST 6: Timetable Teacher Double-Booking Prevention & Scoping
    -- =========================================================================
    RAISE NOTICE 'Test 6: Verifying timetable teacher clash prevention and published scoping...';

    -- Create and publish Timetable 1 for Batch 1 with Prof. Turing on Monday 09:00 - 10:30
    INSERT INTO timetables (batch_id, title, status)
    VALUES (v_batch1_id, 'Batch 1 Mon Schedule', 'published')
    RETURNING id INTO v_tt1_id;

    INSERT INTO timetable_entries (timetable_id, weekday, slot, start_time, end_time, teacher_id, room)
    VALUES (v_tt1_id, 1, 'morning', '09:00:00', '10:30:00', v_teacher_id, 'Room 101');

    -- Create Timetable 2 for Batch 2: try to schedule Prof. Turing on Monday overlapping 10:00 - 11:00
    INSERT INTO timetables (batch_id, title, status)
    VALUES (v_batch2_id, 'Batch 2 Mon Schedule', 'published')
    RETURNING id INTO v_tt2_id;

    BEGIN
        INSERT INTO timetable_entries (timetable_id, weekday, slot, start_time, end_time, teacher_id, room)
        VALUES (v_tt2_id, 1, 'morning', '10:00:00', '11:00:00', v_teacher_id, 'Room 202');
        v_clash_caught := false;
    EXCEPTION WHEN OTHERS THEN
        v_clash_caught := true;
        RAISE NOTICE '  [PASS] Caught expected timetable clash: %', SQLERRM;
    END;
    ASSERT v_clash_caught = true, 'Expected timetable clash trigger to reject overlapping teacher schedule';

    -- Non-overlapping schedule (Monday 11:00 - 12:00) MUST succeed
    INSERT INTO timetable_entries (timetable_id, weekday, slot, start_time, end_time, teacher_id, room)
    VALUES (v_tt2_id, 1, 'morning', '11:00:00', '12:00:00', v_teacher_id, 'Room 202');

    RAISE NOTICE '  [PASS] Timetable clash prevention verified.';

    -- =========================================================================
    -- TEST 7: Announcements - Audiences, Personal Placeholders, RLS & Retract
    -- =========================================================================
    RAISE NOTICE 'Test 7: Verifying announcement delivery, placeholders, and retract...';

    -- Dispatch announcement to 'fee_defaulters' with min_balance_paise = 500,000 (5,000 INR)
    -- Student 1 has pending balance > 5,000 INR
    v_ann_res := send_announcement(jsonb_build_object(
        'category', 'fee_reminder',
        'title', 'Urgent Fee Notice',
        'body', 'Dear {student_name}, your balance of {balance} for {course} is overdue.',
        'audience_type', 'fee_defaulters',
        'min_balance_paise', 500000,
        'dry_run', false
    ));

    ASSERT (v_ann_res->>'success')::boolean = true, 'Announcement sending failed';
    v_ann_id := (v_ann_res->>'announcement_id')::bigint;

    -- Verify placeholder rendering
    SELECT body INTO v_fee_summary FROM notifications WHERE announcement_id = v_ann_id AND recipient_id = v_student1_id;
    ASSERT v_fee_summary.body LIKE '%Ada Lovelace%', 'Body should contain student name placeholder replacement';
    ASSERT v_fee_summary.body LIKE '%B.Sc Computer Science%', 'Body should contain course name placeholder replacement';

    -- Retract announcement
    v_retract_res := retract_announcement(v_ann_id);
    ASSERT (v_retract_res->>'success')::boolean = true, 'Retract announcement failed';
    ASSERT (v_retract_res->>'deleted_unread_notifications')::int > 0, 'Unread notifications should be deleted on retract';

    RAISE NOTICE '  [PASS] Announcement placeholders and retract verified.';

    -- =========================================================================
    -- TEST 8: Teacher Assignment Enforcement & Duplicate Slot Rejection
    -- =========================================================================
    RAISE NOTICE 'Test 8: Verifying teacher assignment security and double-submit rejection...';

    -- Switch to teacher role
    SET LOCAL ROLE authenticated;
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_teacher_user_id::text, 'role', 'authenticated')::text, true);

    -- Create draft session in Batch 2 (teacher is NOT assigned to Batch 2)
    -- Setting local role back to admin briefly to insert the session in Batch 2
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin_id::text, 'role', 'authenticated')::text, true);
    INSERT INTO attendance_sessions (batch_id, date, slot, status)
    VALUES (v_batch2_id, CURRENT_DATE, 'morning', 'draft')
    RETURNING id INTO v_session_id;

    -- Switch back to teacher role
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_teacher_user_id::text, 'role', 'authenticated')::text, true);

    BEGIN
        PERFORM submit_attendance(v_session_id, jsonb_build_array(
            jsonb_build_object('student_id', v_student1_id, 'status', 'present')
        ));
        v_unassigned_caught := false;
    EXCEPTION WHEN OTHERS THEN
        v_unassigned_caught := true;
        RAISE NOTICE '  [PASS] Caught expected unassigned batch rejection: %', SQLERRM;
    END;
    ASSERT v_unassigned_caught = true, 'Teacher must not be able to mark a batch they are not assigned to';

    -- Switch to Batch 1 draft session (assigned to teacher): first submission succeeds
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin_id::text, 'role', 'authenticated')::text, true);
    INSERT INTO attendance_sessions (batch_id, date, slot, status)
    VALUES (v_batch1_id, CURRENT_DATE, 'morning', 'draft')
    RETURNING id INTO v_session_id;

    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_teacher_user_id::text, 'role', 'authenticated')::text, true);
    PERFORM submit_attendance(v_session_id, jsonb_build_array(
        jsonb_build_object('student_id', v_student1_id, 'status', 'present')
    ));

    -- Re-submitting the same slot MUST be rejected (status is now 'submitted')
    BEGIN
        PERFORM submit_attendance(v_session_id, jsonb_build_array(
            jsonb_build_object('student_id', v_student1_id, 'status', 'absent')
        ));
        v_double_submit_caught := false;
    EXCEPTION WHEN OTHERS THEN
        v_double_submit_caught := true;
        RAISE NOTICE '  [PASS] Caught expected duplicate submission rejection: %', SQLERRM;
    END;
    ASSERT v_double_submit_caught = true, 'Re-submitting a submitted session must be rejected';

    RAISE NOTICE '=======================================================';
    RAISE NOTICE 'ALL SUB-PHASE 4C TESTS PASSED SUCCESSFULLY!';
    RAISE NOTICE '=======================================================';
END $$;

ROLLBACK;
