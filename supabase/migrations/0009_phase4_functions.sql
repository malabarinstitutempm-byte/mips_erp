-- =============================================================================
-- Migration: 0009_phase4_functions.sql
-- Description: Phase 4 Functions & Stored Procedures:
--   1. record_payment with FIFO & Explicit Allocation
--   2. cancel_payment with Allocation Reversal
--   3. Skill Course Enrollment & Fee Item Creation
--   4. submit_attendance & correct_attendance with Slot Model & Band Evaluation
--   5. evaluate_attendance_bands: One-time notification per band boundary
--   6. confirm_no_class & list_unmarked_slots
--   7. send_announcement & retract_announcement
--   8. publish_timetable & archive_timetable
--   9. prepare_unmarked_slots_dashboard & pg_cron Schedule (19:30 IST / 14:00 UTC)
-- =============================================================================

-- =============================================================================
-- 1. Financial Ledger: record_payment with FIFO and Explicit Allocation
-- =============================================================================

CREATE OR REPLACE FUNCTION record_payment(
    p_student_id bigint,
    p_amount_paise bigint,
    p_mode payment_mode,
    p_reference text DEFAULT NULL,
    p_remarks text DEFAULT NULL,
    p_allocations jsonb DEFAULT NULL
)
RETURNS jsonb AS $$
DECLARE
    v_payment_id bigint;
    v_receipt_id bigint;
    v_receipt_number text;
    v_current_year int;
    v_admin_id uuid;
    v_total_pending bigint;
    v_remaining bigint;
    v_alloc_item jsonb;
    v_target_item_id bigint;
    v_target_amount bigint;
    v_item_pending bigint;
    v_item RECORD;
    v_alloc_amount bigint;
    v_sum_explicit bigint := 0;
BEGIN
    IF NOT is_admin() THEN
        RAISE EXCEPTION 'Access denied. Administrator privilege required to record payments.';
    END IF;

    v_admin_id := auth.uid();

    IF p_amount_paise <= 0 THEN
        RAISE EXCEPTION 'Payment amount must be greater than zero paise.';
    END IF;

    -- Calculate total pending balance across student's fee items
    SELECT coalesce(sum(amount_paise - paid_amount_paise), 0)
    INTO v_total_pending
    FROM fee_items
    WHERE student_id = p_student_id AND deleted_at IS NULL;

    IF v_total_pending <= 0 THEN
        RAISE EXCEPTION 'Student ID % has no pending fee balance.', p_student_id;
    END IF;

    -- Strict overpayment guard
    IF p_amount_paise > v_total_pending THEN
        RAISE EXCEPTION 'Overpayment rejected: payment of % paise exceeds total pending balance of % paise.',
            p_amount_paise, v_total_pending;
    END IF;

    -- Insert payment record
    INSERT INTO payments (
        student_id,
        amount_paise,
        payment_mode,
        reference_number,
        remarks,
        date,
        is_cancelled,
        created_at,
        updated_at
    ) VALUES (
        p_student_id,
        p_amount_paise,
        p_mode,
        p_reference,
        p_remarks,
        CURRENT_DATE,
        false,
        clock_timestamp(),
        clock_timestamp()
    ) RETURNING id INTO v_payment_id;

    -- Generate atomic sequential receipt number
    v_current_year := EXTRACT(YEAR FROM CURRENT_DATE)::int;
    v_receipt_number := next_number('receipt_counter_' || v_current_year, 'REC-' || v_current_year || '-', 5);

    INSERT INTO receipts (
        receipt_number,
        payment_id,
        student_id,
        amount_paise,
        issued_date,
        issued_by,
        created_at,
        updated_at
    ) VALUES (
        v_receipt_number,
        v_payment_id,
        p_student_id,
        p_amount_paise,
        CURRENT_DATE,
        v_admin_id,
        clock_timestamp(),
        clock_timestamp()
    ) RETURNING id INTO v_receipt_id;

    -- Payment Allocation
    IF p_allocations IS NOT NULL AND jsonb_array_length(p_allocations) > 0 THEN
        -- Explicit Allocation Mode
        FOR v_alloc_item IN SELECT * FROM jsonb_array_elements(p_allocations)
        LOOP
            v_target_item_id := (v_alloc_item->>'fee_item_id')::bigint;
            v_target_amount := (v_alloc_item->>'amount_paise')::bigint;

            IF v_target_amount <= 0 THEN
                RAISE EXCEPTION 'Allocated amount must be greater than zero paise.';
            END IF;

            SELECT (amount_paise - paid_amount_paise) INTO v_item_pending
            FROM fee_items
            WHERE id = v_target_item_id AND student_id = p_student_id AND deleted_at IS NULL
            FOR UPDATE;

            IF NOT FOUND THEN
                RAISE EXCEPTION 'Fee item ID % not found for student ID %.', v_target_item_id, p_student_id;
            END IF;

            IF v_target_amount > v_item_pending THEN
                RAISE EXCEPTION 'Allocation of % paise exceeds fee item ID % pending balance of % paise.',
                    v_target_amount, v_target_item_id, v_item_pending;
            END IF;

            INSERT INTO payment_allocations (payment_id, fee_item_id, amount_paise)
            VALUES (v_payment_id, v_target_item_id, v_target_amount);

            UPDATE fee_items
            SET paid_amount_paise = paid_amount_paise + v_target_amount,
                status = CASE 
                    WHEN paid_amount_paise + v_target_amount >= amount_paise THEN 'paid'
                    ELSE 'partially_paid'
                END,
                updated_at = clock_timestamp()
            WHERE id = v_target_item_id;

            v_sum_explicit := v_sum_explicit + v_target_amount;
        END LOOP;

        IF v_sum_explicit != p_amount_paise THEN
            RAISE EXCEPTION 'Sum of explicit allocations (% paise) does not match payment amount (% paise).',
                v_sum_explicit, p_amount_paise;
        END IF;
    ELSE
        -- Default FIFO Allocation Mode (by due date, then id)
        v_remaining := p_amount_paise;

        FOR v_item IN 
            SELECT id, amount_paise, paid_amount_paise
            FROM fee_items
            WHERE student_id = p_student_id 
              AND deleted_at IS NULL 
              AND (amount_paise - paid_amount_paise) > 0
            ORDER BY due_date ASC NULLS LAST, id ASC
            FOR UPDATE
        LOOP
            v_item_pending := v_item.amount_paise - v_item.paid_amount_paise;
            v_alloc_amount := least(v_remaining, v_item_pending);

            INSERT INTO payment_allocations (payment_id, fee_item_id, amount_paise)
            VALUES (v_payment_id, v_item.id, v_alloc_amount);

            UPDATE fee_items
            SET paid_amount_paise = paid_amount_paise + v_alloc_amount,
                status = CASE 
                    WHEN paid_amount_paise + v_alloc_amount >= amount_paise THEN 'paid'
                    ELSE 'partially_paid'
                END,
                updated_at = clock_timestamp()
            WHERE id = v_item.id;

            v_remaining := v_remaining - v_alloc_amount;
            EXIT WHEN v_remaining <= 0;
        END LOOP;

        IF v_remaining > 0 THEN
            RAISE EXCEPTION 'FIFO Allocation Error: % paise remained unallocated.', v_remaining;
        END IF;
    END IF;

    -- Write to audit log
    INSERT INTO audit_log (table_name, record_id, action, new_data, actor, created_at)
    VALUES (
        'payments',
        v_payment_id::text,
        'INSERT',
        jsonb_build_object(
            'payment_id', v_payment_id,
            'receipt_number', v_receipt_number,
            'student_id', p_student_id,
            'amount_paise', p_amount_paise,
            'mode', p_mode
        ),
        v_admin_id,
        clock_timestamp()
    );

    RETURN jsonb_build_object(
        'success', true,
        'payment_id', v_payment_id,
        'receipt_id', v_receipt_id,
        'receipt_number', v_receipt_number,
        'amount_paise', p_amount_paise
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp;

GRANT EXECUTE ON FUNCTION record_payment(bigint, bigint, payment_mode, text, text, jsonb) TO authenticated;


-- =============================================================================
-- 2. cancel_payment with Allocation Reversal
-- =============================================================================

CREATE OR REPLACE FUNCTION cancel_payment(
    p_payment_id bigint,
    p_reason text
)
RETURNS jsonb AS $$
DECLARE
    v_payment payments%ROWTYPE;
    v_admin_id uuid;
    v_alloc RECORD;
BEGIN
    IF NOT is_admin() THEN
        RAISE EXCEPTION 'Access denied. Administrator privilege required to cancel payments.';
    END IF;

    v_admin_id := auth.uid();

    IF p_reason IS NULL OR trim(p_reason) = '' THEN
        RAISE EXCEPTION 'A valid cancellation reason is strictly required.';
    END IF;

    SELECT * INTO v_payment
    FROM payments
    WHERE id = p_payment_id AND deleted_at IS NULL
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Active payment record with ID % not found.', p_payment_id;
    END IF;

    IF v_payment.is_cancelled THEN
        RAISE EXCEPTION 'Payment ID % has already been cancelled.', p_payment_id;
    END IF;

    -- Reverse each payment allocation from fee_items
    FOR v_alloc IN 
        SELECT fee_item_id, amount_paise
        FROM payment_allocations
        WHERE payment_id = p_payment_id
    LOOP
        UPDATE fee_items
        SET paid_amount_paise = greatest(0, paid_amount_paise - v_alloc.amount_paise),
            status = CASE 
                WHEN (paid_amount_paise - v_alloc.amount_paise) <= 0 THEN 'unpaid'
                ELSE 'partially_paid'
            END,
            updated_at = clock_timestamp()
        WHERE id = v_alloc.fee_item_id;
    END LOOP;

    -- Delete or mark payment allocations reversed
    DELETE FROM payment_allocations WHERE payment_id = p_payment_id;

    -- Mark payment cancelled
    UPDATE payments
    SET is_cancelled = true,
        cancel_reason = trim(p_reason),
        cancelled_at = clock_timestamp(),
        cancelled_by = v_admin_id,
        updated_at = clock_timestamp()
    WHERE id = p_payment_id;

    -- Audit log
    INSERT INTO audit_log (table_name, record_id, action, old_data, new_data, actor, created_at)
    VALUES (
        'payments',
        p_payment_id::text,
        'UPDATE',
        row_to_json(v_payment)::jsonb,
        jsonb_build_object(
            'id', p_payment_id,
            'is_cancelled', true,
            'cancel_reason', trim(p_reason),
            'cancelled_by', v_admin_id
        ),
        v_admin_id,
        clock_timestamp()
    );

    RETURN jsonb_build_object(
        'success', true,
        'payment_id', p_payment_id,
        'cancelled_at', clock_timestamp()
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp;

GRANT EXECUTE ON FUNCTION cancel_payment(bigint, text) TO authenticated;


-- =============================================================================
-- 3. Skill Course Management Functions
-- =============================================================================

-- 3.1. add_student_skill_course
CREATE OR REPLACE FUNCTION add_student_skill_course(
    p_student_id bigint,
    p_course_id bigint,
    p_batch_id bigint,
    p_fee_paise bigint DEFAULT NULL
)
RETURNS jsonb AS $$
DECLARE
    v_course courses%ROWTYPE;
    v_enr_id bigint;
    v_fee_amount bigint;
    v_fee_item_id bigint;
BEGIN
    IF NOT is_admin() THEN
        RAISE EXCEPTION 'Access denied. Administrator privilege required.';
    END IF;

    -- Verify course is of type skill
    SELECT * INTO v_course
    FROM courses
    WHERE id = p_course_id AND deleted_at IS NULL;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Course ID % not found.', p_course_id;
    END IF;

    IF v_course.course_type != 'skill' THEN
        RAISE EXCEPTION 'Course "%" (ID %) is not marked as a skill course.', v_course.name, p_course_id;
    END IF;

    -- Check student active
    IF NOT EXISTS (SELECT 1 FROM students WHERE id = p_student_id AND deleted_at IS NULL AND status = 'active') THEN
        RAISE EXCEPTION 'Active student ID % not found.', p_student_id;
    END IF;

    -- Check if student already has an active skill enrollment
    IF EXISTS (
        SELECT 1 FROM student_enrollments 
        WHERE student_id = p_student_id AND kind = 'skill' AND status = 'active' AND deleted_at IS NULL
    ) THEN
        RAISE EXCEPTION 'Student ID % already has an active skill course enrollment.', p_student_id;
    END IF;

    -- Insert skill enrollment
    INSERT INTO student_enrollments (
        student_id,
        course_id,
        batch_id,
        kind,
        enrolled_on,
        status,
        created_at,
        updated_at
    ) VALUES (
        p_student_id,
        p_course_id,
        p_batch_id,
        'skill',
        CURRENT_DATE,
        'active',
        clock_timestamp(),
        clock_timestamp()
    ) RETURNING id INTO v_enr_id;

    -- Create fee item for skill course
    v_fee_amount := coalesce(p_fee_paise, v_course.total_fee_paise);
    IF v_fee_amount > 0 THEN
        INSERT INTO fee_items (
            student_id,
            enrollment_id,
            label,
            amount_paise,
            paid_amount_paise,
            due_date,
            status,
            created_at,
            updated_at
        ) VALUES (
            p_student_id,
            v_enr_id,
            v_course.name || ' - Skill Course Fee',
            v_fee_amount,
            0,
            CURRENT_DATE + interval '30 days',
            'unpaid',
            clock_timestamp(),
            clock_timestamp()
        ) RETURNING id INTO v_fee_item_id;
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'enrollment_id', v_enr_id,
        'student_id', p_student_id,
        'course_id', p_course_id,
        'batch_id', p_batch_id,
        'fee_item_id', v_fee_item_id,
        'amount_paise', v_fee_amount
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp;

GRANT EXECUTE ON FUNCTION add_student_skill_course(bigint, bigint, bigint, bigint) TO authenticated;


-- 3.2. record_fee_adjustment
CREATE OR REPLACE FUNCTION record_fee_adjustment(
    p_student_id bigint,
    p_enrollment_id bigint,
    p_amount_paise bigint,
    p_type text,
    p_reason text
)
RETURNS jsonb AS $$
DECLARE
    v_adj_id bigint;
BEGIN
    IF NOT is_admin() THEN
        RAISE EXCEPTION 'Access denied. Administrator privilege required.';
    END IF;

    IF p_amount_paise <= 0 THEN
        RAISE EXCEPTION 'Adjustment amount must be greater than zero.';
    END IF;

    IF p_type NOT IN ('refund', 'credit') THEN
        RAISE EXCEPTION 'Invalid adjustment type: %. Must be "refund" or "credit".', p_type;
    END IF;

    IF p_reason IS NULL OR trim(p_reason) = '' THEN
        RAISE EXCEPTION 'Adjustment reason is strictly required.';
    END IF;

    INSERT INTO fee_adjustments (
        student_id,
        enrollment_id,
        amount_paise,
        type,
        reason,
        created_by,
        created_at
    ) VALUES (
        p_student_id,
        p_enrollment_id,
        p_amount_paise,
        p_type,
        trim(p_reason),
        auth.uid(),
        clock_timestamp()
    ) RETURNING id INTO v_adj_id;

    RETURN jsonb_build_object(
        'success', true,
        'adjustment_id', v_adj_id,
        'amount_paise', p_amount_paise,
        'type', p_type
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp;

GRANT EXECUTE ON FUNCTION record_fee_adjustment(bigint, bigint, bigint, text, text) TO authenticated;


-- =============================================================================
-- 4. Attendance Engine: submit_attendance & evaluate_attendance_bands
-- =============================================================================

-- 4.1. evaluate_attendance_bands
CREATE OR REPLACE FUNCTION evaluate_attendance_bands(
    p_student_id bigint DEFAULT NULL,
    p_batch_id bigint DEFAULT NULL
)
RETURNS jsonb AS $$
DECLARE
    v_target_students bigint[];
    v_sid bigint;
    v_summary RECORD;
    v_last_band text;
    v_enr_id bigint;
    v_student_name text;
    v_adm_no text;
    v_alerts_sent int := 0;
    v_admin_user_id uuid;
BEGIN
    -- Determine target students
    IF p_student_id IS NOT NULL THEN
        v_target_students := ARRAY[p_student_id];
    ELSIF p_batch_id IS NOT NULL THEN
        SELECT coalesce(array_agg(id), ARRAY[]::bigint[])
        INTO v_target_students
        FROM students
        WHERE (batch_id = p_batch_id OR EXISTS (
            SELECT 1 FROM student_enrollments se 
            WHERE se.student_id = students.id AND se.batch_id = p_batch_id AND se.status = 'active'
        )) AND status = 'active' AND deleted_at IS NULL;
    ELSE
        RETURN jsonb_build_object('success', false, 'message', 'Either student_id or batch_id must be provided.');
    END IF;

    FOREACH v_sid IN ARRAY v_target_students
    LOOP
        -- Get attendance summary for this student
        SELECT * INTO v_summary
        FROM student_attendance_summary(v_sid)
        LIMIT 1;

        IF v_summary.student_id IS NOT NULL THEN
            v_enr_id := coalesce(v_summary.enrollment_id, 0);

            -- Check current alert state
            SELECT last_band INTO v_last_band
            FROM attendance_alert_state
            WHERE student_id = v_sid AND enrollment_id = v_enr_id;

            IF v_last_band IS NULL THEN
                v_last_band := 'ok';
            END IF;

            -- Evaluate boundary transition
            IF v_summary.status_band != v_last_band THEN
                SELECT name, admission_number INTO v_student_name, v_adm_no
                FROM students WHERE id = v_sid;

                IF v_summary.status_band = 'low' THEN
                    -- Student notification for low attendance
                    INSERT INTO notifications (
                        recipient_type,
                        recipient_id,
                        type,
                        title,
                        body,
                        created_at
                    ) VALUES (
                        'student',
                        v_sid,
                        'attendance_warning',
                        'Low attendance',
                        format('Your attendance is currently %s%%. You can miss at most %s more session(s) before facing an attendance shortage below 75%%.', 
                               v_summary.percentage, v_summary.can_miss_more),
                        clock_timestamp()
                    );

                    -- Admin notification
                    INSERT INTO notifications (
                        recipient_type,
                        type,
                        title,
                        body,
                        created_at
                    ) VALUES (
                        'admin',
                        'attendance_warning',
                        format('Low attendance: %s', v_student_name),
                        format('Student %s (Adm No: %s) has entered the low attendance band with %s%%.', 
                               v_student_name, coalesce(v_adm_no, 'N/A'), v_summary.percentage),
                        clock_timestamp()
                    );

                    v_alerts_sent := v_alerts_sent + 1;

                ELSIF v_summary.status_band = 'shortage' THEN
                    -- Student notification for shortage
                    INSERT INTO notifications (
                        recipient_type,
                        recipient_id,
                        type,
                        title,
                        body,
                        created_at
                    ) VALUES (
                        'student',
                        v_sid,
                        'attendance_shortage',
                        'Attendance below minimum',
                        format('Attendance Alert: Your attendance has dropped to %s%% (below mandatory 75%%). You must attend %s consecutive session(s) to restore your percentage.', 
                               v_summary.percentage, v_summary.recover_sessions),
                        clock_timestamp()
                    );

                    -- Admin notification
                    INSERT INTO notifications (
                        recipient_type,
                        type,
                        title,
                        body,
                        created_at
                    ) VALUES (
                        'admin',
                        'attendance_shortage',
                        format('Attendance shortage: %s', v_student_name),
                        format('Urgent: Student %s (Adm No: %s) has fallen into attendance shortage with %s%% (needs %s consecutive sessions to recover).', 
                               v_student_name, coalesce(v_adm_no, 'N/A'), v_summary.percentage, v_summary.recover_sessions),
                        clock_timestamp()
                    );

                    v_alerts_sent := v_alerts_sent + 1;
                END IF;

                -- Update persisted alert state
                INSERT INTO attendance_alert_state (student_id, enrollment_id, last_band, updated_at)
                VALUES (v_sid, v_enr_id, v_summary.status_band, clock_timestamp())
                ON CONFLICT (student_id, enrollment_id)
                DO UPDATE SET last_band = EXCLUDED.last_band, updated_at = clock_timestamp();
            END IF;
        END IF;
    END LOOP;

    RETURN jsonb_build_object(
        'success', true,
        'evaluated_students', coalesce(array_length(v_target_students, 1), 0),
        'alerts_sent', v_alerts_sent
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp;

GRANT EXECUTE ON FUNCTION evaluate_attendance_bands(bigint, bigint) TO authenticated;


-- 4.2. submit_attendance (Updated for slot-based model)
CREATE OR REPLACE FUNCTION submit_attendance(
    p_session_id bigint,
    p_records jsonb
)
RETURNS jsonb AS $$
DECLARE
    v_session attendance_sessions%ROWTYPE;
    v_teacher_id bigint;
    v_window_hours int := 24;
    v_setting_window text;
    v_item jsonb;
    v_student_id bigint;
    v_status attendance_status;
    v_remarks text;
    v_count int := 0;
BEGIN
    IF NOT is_admin() AND NOT is_teacher() THEN
        RAISE EXCEPTION 'Access denied. Only registered teachers or administrators can submit attendance.';
    END IF;

    SELECT * INTO v_session
    FROM attendance_sessions
    WHERE id = p_session_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Attendance session ID % not found.', p_session_id;
    END IF;

    -- If submitted by teacher, enforce teacher assignment and submission window
    IF is_teacher() AND NOT is_admin() THEN
        v_teacher_id := current_teacher_id();
        IF v_teacher_id IS NULL THEN
            RAISE EXCEPTION 'No teacher profile linked to your user account.';
        END IF;

        IF v_session.status != 'draft' THEN
            RAISE EXCEPTION 'Attendance session has already been % and cannot be modified.', v_session.status;
        END IF;

        -- Verify assignment to batch
        IF NOT EXISTS (
            SELECT 1 FROM teacher_assignments
            WHERE teacher_id = v_teacher_id 
              AND batch_id = v_session.batch_id 
              AND active = true
        ) THEN
            RAISE EXCEPTION 'You are not assigned to Batch ID %.', v_session.batch_id;
        END IF;

        SELECT value INTO v_setting_window FROM settings WHERE key = 'teacher_attendance_edit_window_hours';
        IF v_setting_window IS NOT NULL AND v_setting_window ~ '^\d+$' THEN
            v_window_hours := v_setting_window::int;
        END IF;

        IF (clock_timestamp() - v_session.created_at) > (v_window_hours * interval '1 hour') THEN
            RAISE EXCEPTION 'The %-hour submission window for this attendance session has expired.', v_window_hours;
        END IF;
    END IF;

    -- Process records
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_records)
    LOOP
        v_student_id := (v_item->>'student_id')::bigint;
        v_status := (lower(trim(v_item->>'status')))::attendance_status;
        v_remarks := trim(v_item->>'remarks');

        INSERT INTO attendance_records (
            session_id,
            student_id,
            status,
            remarks,
            created_at,
            updated_at
        ) VALUES (
            p_session_id,
            v_student_id,
            v_status,
            v_remarks,
            clock_timestamp(),
            clock_timestamp()
        )
        ON CONFLICT (session_id, student_id)
        DO UPDATE SET
            status = EXCLUDED.status,
            remarks = EXCLUDED.remarks,
            updated_at = clock_timestamp();

        v_count := v_count + 1;
    END LOOP;

    -- Update session status to submitted
    UPDATE attendance_sessions
    SET status = 'submitted',
        marked_by = coalesce(v_teacher_id, v_session.marked_by),
        submitted_at = clock_timestamp(),
        updated_at = clock_timestamp()
    WHERE id = p_session_id;

    -- Audit log
    INSERT INTO audit_log (table_name, record_id, action, new_data, actor, created_at)
    VALUES (
        'attendance_sessions',
        p_session_id::text,
        'UPDATE',
        jsonb_build_object(
            'session_id', p_session_id,
            'status', 'submitted',
            'records_count', v_count,
            'slot', v_session.slot
        ),
        auth.uid(),
        clock_timestamp()
    );

    -- Trigger automated attendance band evaluation for all students in this batch
    PERFORM evaluate_attendance_bands(NULL, v_session.batch_id);

    RETURN jsonb_build_object(
        'success', true,
        'session_id', p_session_id,
        'records_marked', v_count,
        'status', 'submitted'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp;

GRANT EXECUTE ON FUNCTION submit_attendance(bigint, jsonb) TO authenticated;


-- 4.3. correct_attendance (Updated to trigger band evaluation)
CREATE OR REPLACE FUNCTION correct_attendance(
    p_record_id bigint,
    p_new_status attendance_status,
    p_reason text
)
RETURNS jsonb AS $$
DECLARE
    v_record attendance_records%ROWTYPE;
    v_session attendance_sessions%ROWTYPE;
    v_admin_id uuid;
BEGIN
    IF NOT is_admin() THEN
        RAISE EXCEPTION 'Access denied. Administrator privilege required to correct attendance records.';
    END IF;

    v_admin_id := auth.uid();

    IF p_reason IS NULL OR trim(p_reason) = '' THEN
        RAISE EXCEPTION 'A valid correction reason is strictly required.';
    END IF;

    SELECT * INTO v_record
    FROM attendance_records
    WHERE id = p_record_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Attendance record ID % not found.', p_record_id;
    END IF;

    IF v_record.status = p_new_status THEN
        RAISE EXCEPTION 'Status is already set to %.', p_new_status;
    END IF;

    SELECT * INTO v_session FROM attendance_sessions WHERE id = v_record.session_id;

    -- Insert immutable change log
    INSERT INTO attendance_changes (
        record_id,
        old_status,
        new_status,
        changed_by,
        changed_at,
        reason
    ) VALUES (
        p_record_id,
        v_record.status,
        p_new_status,
        v_admin_id,
        clock_timestamp(),
        trim(p_reason)
    );

    -- Update record
    UPDATE attendance_records
    SET status = p_new_status,
        updated_at = clock_timestamp()
    WHERE id = p_record_id;

    -- Re-evaluate student's attendance band
    PERFORM evaluate_attendance_bands(v_record.student_id, NULL);

    RETURN jsonb_build_object(
        'success', true,
        'record_id', p_record_id,
        'old_status', v_record.status,
        'new_status', p_new_status
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp;

GRANT EXECUTE ON FUNCTION correct_attendance(bigint, attendance_status, text) TO authenticated;


-- =============================================================================
-- 5. No-Class & Unmarked Slots Management
-- =============================================================================

-- 5.1. confirm_no_class
CREATE OR REPLACE FUNCTION confirm_no_class(
    p_batch_id bigint,
    p_date date,
    p_slot attendance_slot,
    p_reason text DEFAULT 'Confirmed no class'
)
RETURNS jsonb AS $$
DECLARE
    v_session_id bigint;
BEGIN
    IF NOT is_admin() AND NOT is_teacher() THEN
        RAISE EXCEPTION 'Access denied. Admin or teacher required.';
    END IF;

    -- Verify batch exists
    IF NOT EXISTS (SELECT 1 FROM batches WHERE id = p_batch_id AND deleted_at IS NULL) THEN
        RAISE EXCEPTION 'Active batch ID % not found.', p_batch_id;
    END IF;

    INSERT INTO attendance_sessions (
        batch_id,
        date,
        slot,
        status,
        marked_by,
        submitted_at,
        created_at,
        updated_at
    ) VALUES (
        p_batch_id,
        p_date,
        p_slot,
        'no_class',
        current_teacher_id(),
        clock_timestamp(),
        clock_timestamp(),
        clock_timestamp()
    )
    ON CONFLICT (batch_id, date, slot)
    DO UPDATE SET
        status = 'no_class',
        submitted_at = clock_timestamp(),
        updated_at = clock_timestamp()
    RETURNING id INTO v_session_id;

    -- Delete any individual records attached so they are not counted
    DELETE FROM attendance_records WHERE session_id = v_session_id;

    -- Audit log
    INSERT INTO audit_log (table_name, record_id, action, new_data, actor, created_at)
    VALUES (
        'attendance_sessions',
        v_session_id::text,
        'UPDATE',
        jsonb_build_object('batch_id', p_batch_id, 'date', p_date, 'slot', p_slot, 'status', 'no_class', 'reason', p_reason),
        auth.uid(),
        clock_timestamp()
    );

    RETURN jsonb_build_object(
        'success', true,
        'session_id', v_session_id,
        'batch_id', p_batch_id,
        'date', p_date,
        'slot', p_slot,
        'status', 'no_class'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp;

GRANT EXECUTE ON FUNCTION confirm_no_class(bigint, date, attendance_slot, text) TO authenticated;


-- 5.2. list_unmarked_slots
CREATE OR REPLACE FUNCTION list_unmarked_slots(
    p_date date DEFAULT CURRENT_DATE
)
RETURNS TABLE (
    batch_id bigint,
    batch_name text,
    course_id bigint,
    course_name text,
    date date,
    slot attendance_slot,
    status text
) AS $$
BEGIN
    RETURN QUERY
    WITH active_batches AS (
        SELECT b.id AS b_id, b.batch_name AS b_name, c.id AS c_id, c.name AS c_name
        FROM batches b
        JOIN courses c ON c.id = b.course_id
        WHERE b.deleted_at IS NULL AND b.status = 'active'
    ),
    required_slots AS (
        SELECT 'morning'::attendance_slot AS slot_val
        UNION ALL
        SELECT 'evening'::attendance_slot AS slot_val
    )
    SELECT 
        ab.b_id AS batch_id,
        ab.b_name AS batch_name,
        ab.c_id AS course_id,
        ab.c_name AS course_name,
        p_date AS date,
        rs.slot_val AS slot,
        'unmarked'::text AS status
    FROM active_batches ab
    CROSS JOIN required_slots rs
    WHERE NOT EXISTS (
        SELECT 1 FROM attendance_sessions s
        WHERE s.batch_id = ab.b_id 
          AND s.date = p_date 
          AND s.slot = rs.slot_val
          AND s.status IN ('submitted', 'locked', 'no_class')
    )
    ORDER BY ab.b_name, rs.slot_val;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE
SET search_path = public, pg_temp;

GRANT EXECUTE ON FUNCTION list_unmarked_slots(date) TO authenticated;


-- =============================================================================
-- 6. Announcements: send_announcement & retract_announcement
-- =============================================================================

-- 6.1. send_announcement
CREATE OR REPLACE FUNCTION send_announcement(
    p_payload jsonb
)
RETURNS jsonb AS $$
DECLARE
    v_category announcement_category;
    v_title text;
    v_body text;
    v_audience_type announcement_audience;
    v_audience_ids jsonb;
    v_min_balance bigint := 0;
    v_dry_run boolean := false;

    v_announcement_id bigint;
    v_count int := 0;

    v_rec RECORD;
    v_rendered_body text;
    v_balance_fmt text;
    v_due_date_fmt text;
    v_admin_id uuid;
BEGIN
    IF NOT is_admin() THEN
        RAISE EXCEPTION 'Access denied. Administrator privilege required to send announcements.';
    END IF;

    v_admin_id := auth.uid();
    v_category := (p_payload->>'category')::announcement_category;
    v_title := trim(p_payload->>'title');
    v_body := trim(p_payload->>'body');
    v_audience_type := (p_payload->>'audience_type')::announcement_audience;
    v_audience_ids := coalesce(p_payload->'audience_ids', '[]'::jsonb);
    v_min_balance := coalesce((p_payload->>'min_balance_paise')::bigint, 0);
    v_dry_run := coalesce((p_payload->>'dry_run')::boolean, false);

    IF v_title = '' OR v_body = '' THEN
        RAISE EXCEPTION 'Announcement title and body cannot be empty.';
    END IF;

    -- Calculate recipient count and resolve recipients
    IF v_audience_type = 'teachers' THEN
        -- Resolve teachers
        FOR v_rec IN 
            SELECT t.id AS teacher_id, t.name AS teacher_name, p.user_id
            FROM teachers t
            LEFT JOIN profiles p ON p.teacher_id = t.id AND p.role = 'teacher'
            WHERE t.deleted_at IS NULL AND t.status = 'active'
              AND (
                  jsonb_array_length(v_audience_ids) = 0 
                  OR t.id::text IN (SELECT jsonb_array_elements_text(v_audience_ids))
              )
        LOOP
            v_count := v_count + 1;

            IF NOT v_dry_run THEN
                IF v_count = 1 THEN
                    INSERT INTO announcements (
                        category, title, body, audience_type, audience_ids, 
                        min_balance_paise, recipient_count, created_by, created_at
                    ) VALUES (
                        v_category, v_title, v_body, v_audience_type, v_audience_ids,
                        v_min_balance, 0, v_admin_id, clock_timestamp()
                    ) RETURNING id INTO v_announcement_id;
                END IF;

                v_rendered_body := replace(v_body, '{teacher_name}', v_rec.teacher_name);
                v_rendered_body := replace(v_rendered_body, '{name}', v_rec.teacher_name);

                INSERT INTO notifications (
                    user_id,
                    recipient_type,
                    recipient_id,
                    type,
                    title,
                    body,
                    announcement_id,
                    created_at
                ) VALUES (
                    v_rec.user_id,
                    'teacher',
                    v_rec.teacher_id,
                    'announcement',
                    v_title,
                    v_rendered_body,
                    v_announcement_id,
                    clock_timestamp()
                );
            END IF;
        END LOOP;

    ELSE
        -- Resolve students
        FOR v_rec IN 
            SELECT 
                s.id AS student_id,
                s.name AS student_name,
                coalesce(c.name, 'N/A') AS course_name,
                coalesce(vfs.pending_amount_paise, 0) AS pending_paise,
                (
                    SELECT min(fi.due_date) 
                    FROM fee_items fi 
                    WHERE fi.student_id = s.id AND fi.status != 'paid' AND fi.deleted_at IS NULL
                ) AS earliest_due,
                p.user_id
            FROM students s
            LEFT JOIN courses c ON c.id = s.course_id
            LEFT JOIN view_student_fee_summary vfs ON vfs.student_id = s.id
            LEFT JOIN profiles p ON p.student_id = s.id AND p.role = 'student'
            WHERE s.deleted_at IS NULL AND s.status = 'active'
              AND (
                  -- Audience filter
                  (v_audience_type = 'all_students')
                  OR (v_audience_type = 'course' AND (
                      s.course_id::text IN (SELECT jsonb_array_elements_text(v_audience_ids))
                      OR EXISTS (SELECT 1 FROM student_enrollments se WHERE se.student_id = s.id AND se.course_id::text IN (SELECT jsonb_array_elements_text(v_audience_ids)) AND se.status = 'active')
                  ))
                  OR (v_audience_type = 'batch' AND (
                      s.batch_id::text IN (SELECT jsonb_array_elements_text(v_audience_ids))
                      OR EXISTS (SELECT 1 FROM student_enrollments se WHERE se.student_id = s.id AND se.batch_id::text IN (SELECT jsonb_array_elements_text(v_audience_ids)) AND se.status = 'active')
                  ))
                  OR (v_audience_type = 'fee_defaulters' AND coalesce(vfs.pending_amount_paise, 0) > v_min_balance)
              )
        LOOP
            v_count := v_count + 1;

            IF NOT v_dry_run THEN
                IF v_count = 1 THEN
                    INSERT INTO announcements (
                        category, title, body, audience_type, audience_ids, 
                        min_balance_paise, recipient_count, created_by, created_at
                    ) VALUES (
                        v_category, v_title, v_body, v_audience_type, v_audience_ids,
                        v_min_balance, 0, v_admin_id, clock_timestamp()
                    ) RETURNING id INTO v_announcement_id;
                END IF;

                -- Render personalized placeholders
                v_balance_fmt := '₹' || to_char(round(v_rec.pending_paise / 100.0, 2), 'FM999,999,990.00');
                v_due_date_fmt := coalesce(to_char(v_rec.earliest_due, 'DD-Mon-YYYY'), 'N/A');

                v_rendered_body := replace(v_body, '{student_name}', v_rec.student_name);
                v_rendered_body := replace(v_rendered_body, '{name}', v_rec.student_name);
                v_rendered_body := replace(v_rendered_body, '{balance}', v_balance_fmt);
                v_rendered_body := replace(v_rendered_body, '{course}', v_rec.course_name);
                v_rendered_body := replace(v_rendered_body, '{due_date}', v_due_date_fmt);

                INSERT INTO notifications (
                    user_id,
                    recipient_type,
                    recipient_id,
                    type,
                    title,
                    body,
                    announcement_id,
                    created_at
                ) VALUES (
                    v_rec.user_id,
                    'student',
                    v_rec.student_id,
                    'announcement',
                    v_title,
                    v_rendered_body,
                    v_announcement_id,
                    clock_timestamp()
                );
            END IF;
        END LOOP;
    END IF;

    IF NOT v_dry_run AND v_announcement_id IS NOT NULL THEN
        UPDATE announcements SET recipient_count = v_count WHERE id = v_announcement_id;
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'dry_run', v_dry_run,
        'recipient_count', v_count,
        'announcement_id', v_announcement_id
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp;

GRANT EXECUTE ON FUNCTION send_announcement(jsonb) TO authenticated;


-- 6.2. retract_announcement
CREATE OR REPLACE FUNCTION retract_announcement(
    p_announcement_id bigint
)
RETURNS jsonb AS $$
DECLARE
    v_ann announcements%ROWTYPE;
    v_admin_id uuid;
    v_deleted_count int := 0;
BEGIN
    IF NOT is_admin() THEN
        RAISE EXCEPTION 'Access denied. Administrator privilege required.';
    END IF;

    v_admin_id := auth.uid();

    SELECT * INTO v_ann
    FROM announcements
    WHERE id = p_announcement_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Announcement ID % not found.', p_announcement_id;
    END IF;

    IF v_ann.retracted_at IS NOT NULL THEN
        RAISE EXCEPTION 'Announcement ID % is already retracted.', p_announcement_id;
    END IF;

    -- Update announcement
    UPDATE announcements
    SET retracted_at = clock_timestamp(),
        retracted_by = v_admin_id
    WHERE id = p_announcement_id;

    -- Delete unread notifications created by this announcement
    DELETE FROM notifications
    WHERE announcement_id = p_announcement_id AND read_at IS NULL;
    GET DIAGNOSTICS v_deleted_count = ROW_COUNT;

    -- Audit log
    INSERT INTO audit_log (table_name, record_id, action, new_data, actor, created_at)
    VALUES (
        'announcements',
        p_announcement_id::text,
        'UPDATE',
        jsonb_build_object('retracted_at', clock_timestamp(), 'deleted_unread_notifications', v_deleted_count),
        v_admin_id,
        clock_timestamp()
    );

    RETURN jsonb_build_object(
        'success', true,
        'retracted_id', p_announcement_id,
        'deleted_unread_notifications', v_deleted_count
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp;

GRANT EXECUTE ON FUNCTION retract_announcement(bigint) TO authenticated;


-- =============================================================================
-- 7. Timetable Management: publish_timetable & archive_timetable
-- =============================================================================

-- 7.1. publish_timetable
CREATE OR REPLACE FUNCTION publish_timetable(
    p_timetable_id bigint
)
RETURNS jsonb AS $$
DECLARE
    v_tt timetables%ROWTYPE;
    v_batch_name text;
    v_admin_id uuid;
    v_student_count int := 0;
    v_teacher_count int := 0;
BEGIN
    IF NOT is_admin() THEN
        RAISE EXCEPTION 'Access denied. Administrator privilege required to publish timetables.';
    END IF;

    v_admin_id := auth.uid();

    SELECT * INTO v_tt
    FROM timetables
    WHERE id = p_timetable_id AND deleted_at IS NULL
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Timetable ID % not found.', p_timetable_id;
    END IF;

    SELECT batch_name INTO v_batch_name FROM batches WHERE id = v_tt.batch_id;

    -- Enforce: only one published timetable per batch at a time
    UPDATE timetables
    SET status = 'archived',
        updated_at = clock_timestamp()
    WHERE batch_id = v_tt.batch_id 
      AND status = 'published' 
      AND id != p_timetable_id;

    -- Update target timetable to published
    UPDATE timetables
    SET status = 'published',
        published_at = clock_timestamp(),
        published_by = v_admin_id,
        updated_at = clock_timestamp()
    WHERE id = p_timetable_id;

    -- Notify all active students in this batch
    INSERT INTO notifications (
        user_id,
        recipient_type,
        recipient_id,
        type,
        title,
        body,
        created_at
    )
    SELECT 
        p.user_id,
        'student',
        s.id,
        'timetable',
        'Timetable Published',
        format('A new timetable "%s" is now published and effective for your batch (%s).', v_tt.title, v_batch_name),
        clock_timestamp()
    FROM students s
    LEFT JOIN profiles p ON p.student_id = s.id AND p.role = 'student'
    WHERE s.batch_id = v_tt.batch_id AND s.status = 'active' AND s.deleted_at IS NULL;
    GET DIAGNOSTICS v_student_count = ROW_COUNT;

    -- Notify all teachers assigned in entries of this timetable
    INSERT INTO notifications (
        user_id,
        recipient_type,
        recipient_id,
        type,
        title,
        body,
        created_at
    )
    SELECT DISTINCT
        p.user_id,
        'teacher',
        t.id,
        'timetable',
        'Timetable Published',
        format('Timetable "%s" for %s has been published with your assigned classes.', v_tt.title, v_batch_name),
        clock_timestamp()
    FROM timetable_entries te
    JOIN teachers t ON t.id = te.teacher_id
    LEFT JOIN profiles p ON p.teacher_id = t.id AND p.role = 'teacher'
    WHERE te.timetable_id = p_timetable_id;
    GET DIAGNOSTICS v_teacher_count = ROW_COUNT;

    RETURN jsonb_build_object(
        'success', true,
        'timetable_id', p_timetable_id,
        'status', 'published',
        'students_notified', v_student_count,
        'teachers_notified', v_teacher_count
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp;

GRANT EXECUTE ON FUNCTION publish_timetable(bigint) TO authenticated;


-- 7.2. archive_timetable
CREATE OR REPLACE FUNCTION archive_timetable(
    p_timetable_id bigint
)
RETURNS jsonb AS $$
BEGIN
    IF NOT is_admin() THEN
        RAISE EXCEPTION 'Access denied. Administrator privilege required.';
    END IF;

    UPDATE timetables
    SET status = 'archived',
        updated_at = clock_timestamp()
    WHERE id = p_timetable_id AND deleted_at IS NULL;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Timetable ID % not found.', p_timetable_id;
    END IF;

    RETURN jsonb_build_object('success', true, 'timetable_id', p_timetable_id, 'status', 'archived');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp;

GRANT EXECUTE ON FUNCTION archive_timetable(bigint) TO authenticated;


-- =============================================================================
-- 8. End-of-Day Unmarked Slots Preparation (19:30 IST / 14:00 UTC)
-- =============================================================================

CREATE OR REPLACE FUNCTION prepare_unmarked_slots_dashboard(
    p_date date DEFAULT CURRENT_DATE
)
RETURNS jsonb AS $$
DECLARE
    v_unmarked_count int := 0;
    v_items jsonb;
BEGIN
    SELECT count(*)::int INTO v_unmarked_count
    FROM list_unmarked_slots(p_date);

    SELECT jsonb_agg(row_to_json(u)) INTO v_items
    FROM list_unmarked_slots(p_date) u;

    -- If there are unmarked slots at end-of-day, notify administrators
    IF v_unmarked_count > 0 THEN
        INSERT INTO notifications (
            recipient_type,
            type,
            title,
            body,
            link,
            created_at
        ) VALUES (
            'admin',
            'attendance_unmarked',
            'Unmarked Attendance Sessions Today',
            format('There are %s unmarked attendance session(s) today (%s). Please review and submit or confirm "No Class".', 
                   v_unmarked_count, to_char(p_date, 'DD Mon YYYY')),
            '/attendance/unmarked',
            clock_timestamp()
        );
    END IF;

    RETURN jsonb_build_object(
        'date', p_date,
        'unmarked_count', v_unmarked_count,
        'unmarked_slots', coalesce(v_items, '[]'::jsonb)
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp;

GRANT EXECUTE ON FUNCTION prepare_unmarked_slots_dashboard(date) TO authenticated;

-- Schedule job via pg_cron if available
DO $$ BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
        -- Run at 14:00 UTC (19:30 IST) every day
        PERFORM cron.unschedule('unmarked_sessions_1930_ist');
        PERFORM cron.schedule(
            'unmarked_sessions_1930_ist',
            '0 14 * * *',
            'SELECT prepare_unmarked_slots_dashboard(CURRENT_DATE);'
        );
    END IF;
EXCEPTION
    WHEN OTHERS THEN null;
END $$;
