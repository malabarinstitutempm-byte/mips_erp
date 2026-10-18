-- =============================================================================
-- MIPS ERP Database Migration: 0002_functions.sql
-- Sub-phase 1B: Security Definer Server Functions, Role Guards & Business Logic
-- =============================================================================

-- =============================================================================
-- 1. Authentication & Role Inspection Helpers
-- =============================================================================

CREATE OR REPLACE FUNCTION get_current_profile()
RETURNS profiles AS $$
DECLARE
    v_profile profiles%ROWTYPE;
BEGIN
    SELECT * INTO v_profile
    FROM profiles
    WHERE user_id = auth.uid() AND active = true;
    
    RETURN v_profile;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE
SET search_path = public, pg_temp;

CREATE OR REPLACE FUNCTION is_admin()
RETURNS boolean AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM profiles
        WHERE user_id = auth.uid() AND role = 'admin' AND active = true
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE
SET search_path = public, pg_temp;

CREATE OR REPLACE FUNCTION is_teacher()
RETURNS boolean AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM profiles
        WHERE user_id = auth.uid() AND role = 'teacher' AND active = true
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE
SET search_path = public, pg_temp;

CREATE OR REPLACE FUNCTION current_teacher_id()
RETURNS bigint AS $$
DECLARE
    v_id bigint;
BEGIN
    SELECT teacher_id INTO v_id
    FROM profiles
    WHERE user_id = auth.uid() AND role = 'teacher' AND active = true;
    
    RETURN v_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE
SET search_path = public, pg_temp;

CREATE OR REPLACE FUNCTION current_student_id()
RETURNS bigint AS $$
DECLARE
    v_id bigint;
BEGIN
    SELECT student_id INTO v_id
    FROM profiles
    WHERE user_id = auth.uid() AND role = 'student' AND active = true;
    
    RETURN v_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE
SET search_path = public, pg_temp;

CREATE OR REPLACE FUNCTION teacher_has_assignment(p_batch_id bigint, p_subject_id bigint)
RETURNS boolean AS $$
DECLARE
    v_teacher_id bigint;
BEGIN
    v_teacher_id := current_teacher_id();
    IF v_teacher_id IS NULL THEN
        RETURN false;
    END IF;

    RETURN EXISTS (
        SELECT 1 FROM teacher_assignments
        WHERE teacher_id = v_teacher_id
          AND batch_id = p_batch_id
          AND subject_id = p_subject_id
          AND active = true
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE
SET search_path = public, pg_temp;

-- =============================================================================
-- 2. Concurrency-Safe Sequential Counter: next_number
-- =============================================================================

CREATE OR REPLACE FUNCTION next_number(p_kind text, p_year int)
RETURNS text AS $$
DECLARE
    v_next_val bigint;
    v_prefix text;
    v_clean_kind text;
BEGIN
    IF NOT (is_admin() OR is_teacher()) THEN
        RAISE EXCEPTION 'Access denied. Administrator or staff role required to generate numbers.';
    END IF;

    v_clean_kind := lower(trim(p_kind));

    -- Atomic increment with row-level locking
    INSERT INTO number_counters (kind, year, last_value, updated_at)
    VALUES (v_clean_kind, p_year, 1, clock_timestamp())
    ON CONFLICT (kind, year)
    DO UPDATE SET 
        last_value = number_counters.last_value + 1,
        updated_at = clock_timestamp()
    RETURNING last_value INTO v_next_val;

    IF v_clean_kind = 'admission' THEN
        RETURN 'ADM-' || p_year::text || '-' || lpad(v_next_val::text, 4, '0');
    ELSIF v_clean_kind = 'receipt' THEN
        SELECT coalesce(value, 'REC') INTO v_prefix FROM settings WHERE key = 'receipt_prefix';
        IF v_prefix IS NULL OR trim(v_prefix) = '' THEN
            v_prefix := 'REC';
        END IF;
        RETURN v_prefix || '/' || p_year::text || '/' || lpad(v_next_val::text, 4, '0');
    ELSE
        RETURN upper(v_clean_kind) || '/' || p_year::text || '/' || lpad(v_next_val::text, 4, '0');
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp;

-- =============================================================================
-- 3. Financial Transactions: record_payment & cancel_payment
-- =============================================================================

CREATE OR REPLACE FUNCTION record_payment(
    p_student_id bigint,
    p_amount_paise bigint,
    p_mode payment_mode,
    p_reference text DEFAULT NULL,
    p_remarks text DEFAULT NULL
)
RETURNS jsonb AS $$
DECLARE
    v_fee fees%ROWTYPE;
    v_payment_id bigint;
    v_receipt_id bigint;
    v_receipt_number text;
    v_current_year int;
    v_admin_id uuid;
BEGIN
    IF NOT is_admin() THEN
        RAISE EXCEPTION 'Access denied. Administrator privilege required to record payments.';
    END IF;

    v_admin_id := auth.uid();

    IF p_amount_paise <= 0 THEN
        RAISE EXCEPTION 'Payment amount must be greater than zero paise.';
    END IF;

    -- Lock student fees record to eliminate race conditions
    SELECT * INTO v_fee
    FROM fees
    WHERE student_id = p_student_id AND deleted_at IS NULL
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'No active fee structure found for student ID %.', p_student_id;
    END IF;

    -- Strict overpayment guard
    IF p_amount_paise > v_fee.pending_amount_paise THEN
        RAISE EXCEPTION 'Overpayment rejected: payment of % paise exceeds current pending balance of % paise.',
            p_amount_paise, v_fee.pending_amount_paise;
    END IF;

    v_current_year := extract(year FROM CURRENT_DATE)::int;
    v_receipt_number := next_number('receipt', v_current_year);

    -- 1. Create Payment record
    INSERT INTO payments (
        student_id, amount_paise, payment_mode, reference_number, remarks,
        date, is_cancelled, created_at, updated_at
    )
    VALUES (
        p_student_id, p_amount_paise, p_mode, trim(p_reference), trim(p_remarks),
        CURRENT_DATE, false, clock_timestamp(), clock_timestamp()
    )
    RETURNING id INTO v_payment_id;

    -- 2. Create Receipt record
    INSERT INTO receipts (payment_id, receipt_number, created_at, updated_at)
    VALUES (v_payment_id, v_receipt_number, clock_timestamp(), clock_timestamp())
    RETURNING id INTO v_receipt_id;

    -- 3. Update payment with receipt_id linkage
    UPDATE payments
    SET updated_at = clock_timestamp()
    WHERE id = v_payment_id;

    -- 4. Update student fee ledger totals
    UPDATE fees
    SET paid_amount_paise = paid_amount_paise + p_amount_paise,
        pending_amount_paise = pending_amount_paise - p_amount_paise,
        updated_at = clock_timestamp()
    WHERE student_id = p_student_id;

    RETURN jsonb_build_object(
        'success', true,
        'payment_id', v_payment_id,
        'receipt_id', v_receipt_id,
        'receipt_number', v_receipt_number,
        'student_id', p_student_id,
        'amount_paise', p_amount_paise,
        'remaining_pending_paise', v_fee.pending_amount_paise - p_amount_paise
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp;

CREATE OR REPLACE FUNCTION cancel_payment(
    p_payment_id bigint,
    p_reason text
)
RETURNS jsonb AS $$
DECLARE
    v_payment payments%ROWTYPE;
    v_fee fees%ROWTYPE;
    v_admin_id uuid;
BEGIN
    IF NOT is_admin() THEN
        RAISE EXCEPTION 'Access denied. Administrator privilege required to cancel payments.';
    END IF;

    v_admin_id := auth.uid();

    IF p_reason IS NULL OR trim(p_reason) = '' THEN
        RAISE EXCEPTION 'A valid cancellation reason is strictly required.';
    END IF;

    -- Lock the payment record
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

    -- Lock the corresponding fee ledger
    SELECT * INTO v_fee
    FROM fees
    WHERE student_id = v_payment.student_id AND deleted_at IS NULL
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Fee ledger for student ID % not found.', v_payment.student_id;
    END IF;

    -- Mark payment as cancelled (never delete)
    UPDATE payments
    SET is_cancelled = true,
        cancel_reason = trim(p_reason),
        cancelled_at = clock_timestamp(),
        cancelled_by = v_admin_id,
        updated_at = clock_timestamp()
    WHERE id = p_payment_id;

    -- Revert the student's fee ledger totals
    UPDATE fees
    SET paid_amount_paise = paid_amount_paise - v_payment.amount_paise,
        pending_amount_paise = pending_amount_paise + v_payment.amount_paise,
        updated_at = clock_timestamp()
    WHERE student_id = v_payment.student_id;

    RETURN jsonb_build_object(
        'success', true,
        'payment_id', p_payment_id,
        'student_id', v_payment.student_id,
        'reverted_amount_paise', v_payment.amount_paise,
        'new_pending_paise', v_fee.pending_amount_paise + v_payment.amount_paise
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp;

-- =============================================================================
-- 4. Examination & Marks: save_marks & compute_results
-- =============================================================================

CREATE OR REPLACE FUNCTION save_marks(
    p_exam_id bigint,
    p_marks jsonb
)
RETURNS jsonb AS $$
DECLARE
    v_exam exams%ROWTYPE;
    v_item jsonb;
    v_subject_id bigint;
    v_student_id bigint;
    v_marks_obtained numeric(5,2);
    v_is_absent boolean;
    v_subject exam_subjects%ROWTYPE;
    v_count int := 0;
BEGIN
    IF NOT is_admin() THEN
        RAISE EXCEPTION 'Access denied. Administrator privilege required to enter marks.';
    END IF;

    SELECT * INTO v_exam FROM exams WHERE id = p_exam_id AND deleted_at IS NULL;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Exam with ID % does not exist or has been deleted.', p_exam_id;
    END IF;

    FOR v_item IN SELECT * FROM jsonb_array_elements(p_marks)
    LOOP
        v_subject_id := (v_item->>'subject_id')::bigint;
        v_student_id := (v_item->>'student_id')::bigint;
        v_is_absent := coalesce((v_item->>'is_absent')::boolean, false);
        
        IF (v_item->>'marks_obtained') IS NOT NULL AND trim(v_item->>'marks_obtained') != '' THEN
            v_marks_obtained := (v_item->>'marks_obtained')::numeric;
        ELSE
            v_marks_obtained := NULL;
        END IF;

        -- Verify subject belongs to this exam
        SELECT * INTO v_subject
        FROM exam_subjects
        WHERE id = v_subject_id AND exam_id = p_exam_id AND deleted_at IS NULL;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'Subject ID % does not belong to Exam ID %.', v_subject_id, p_exam_id;
        END IF;

        -- Validate mark boundaries
        IF NOT v_is_absent AND v_marks_obtained IS NOT NULL THEN
            IF v_marks_obtained < 0 OR v_marks_obtained > v_subject.max_marks THEN
                RAISE EXCEPTION 'Invalid mark % for Subject "%": must be between 0 and %.',
                    v_marks_obtained, v_subject.name, v_subject.max_marks;
            END IF;
        END IF;

        -- Upsert mark record
        INSERT INTO marks (
            exam_id, subject_id, student_id, marks_obtained, is_absent,
            created_at, updated_at, deleted_at, deleted_by
        )
        VALUES (
            p_exam_id, v_subject_id, v_student_id,
            CASE WHEN v_is_absent THEN NULL ELSE v_marks_obtained END,
            v_is_absent,
            clock_timestamp(), clock_timestamp(), NULL, NULL
        )
        ON CONFLICT (exam_id, subject_id, student_id)
        DO UPDATE SET
            marks_obtained = EXCLUDED.marks_obtained,
            is_absent = EXCLUDED.is_absent,
            deleted_at = NULL,
            deleted_by = NULL,
            updated_at = clock_timestamp();

        v_count := v_count + 1;
    END LOOP;

    RETURN jsonb_build_object(
        'success', true,
        'exam_id', p_exam_id,
        'upserted_count', v_count
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp;

CREATE OR REPLACE FUNCTION compute_results(
    p_exam_id bigint
)
RETURNS jsonb AS $$
DECLARE
    v_exam exams%ROWTYPE;
    v_student record;
    v_mark record;
    v_total_max numeric(6,2) := 0;
    v_total_obtained numeric(6,2);
    v_pct numeric(5,2);
    v_has_failed boolean;
    v_grade text;
    v_status text;
    v_computed_count int := 0;
    v_pass_count int := 0;
    v_fail_count int := 0;
BEGIN
    IF NOT is_admin() THEN
        RAISE EXCEPTION 'Access denied. Administrator privilege required to compute results.';
    END IF;

    SELECT * INTO v_exam FROM exams WHERE id = p_exam_id AND deleted_at IS NULL;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Exam with ID % does not exist or has been deleted.', p_exam_id;
    END IF;

    -- Calculate total maximum possible marks across all exam subjects
    SELECT coalesce(sum(max_marks), 0) INTO v_total_max
    FROM exam_subjects
    WHERE exam_id = p_exam_id AND deleted_at IS NULL;

    IF v_total_max <= 0 THEN
        RAISE EXCEPTION 'Exam has no configured subjects or maximum marks.';
    END IF;

    -- Loop through all students who have entered marks for this exam
    FOR v_student IN 
        SELECT DISTINCT student_id 
        FROM marks 
        WHERE exam_id = p_exam_id AND deleted_at IS NULL
    LOOP
        v_total_obtained := 0;
        v_has_failed := false;

        -- Verify every subject in this exam
        FOR v_mark IN
            SELECT es.id as subject_id, es.pass_marks, es.max_marks,
                   m.marks_obtained, m.is_absent
            FROM exam_subjects es
            LEFT JOIN marks m ON m.subject_id = es.id 
                             AND m.student_id = v_student.student_id 
                             AND m.exam_id = p_exam_id 
                             AND m.deleted_at IS NULL
            WHERE es.exam_id = p_exam_id AND es.deleted_at IS NULL
        LOOP
            -- Absent or missing mark or marks less than pass mark triggers FAIL
            IF v_mark.is_absent = true OR v_mark.marks_obtained IS NULL THEN
                v_has_failed := true;
            ELSE
                v_total_obtained := v_total_obtained + v_mark.marks_obtained;
                IF v_mark.marks_obtained < v_mark.pass_marks THEN
                    v_has_failed := true;
                END IF;
            END IF;
        END LOOP;

        v_pct := round((v_total_obtained / v_total_max) * 100.0, 2);

        -- Determine grade based on configured grading scheme
        SELECT grade INTO v_grade
        FROM grading_schemes
        WHERE v_pct >= min_percent AND v_pct <= max_percent
        ORDER BY min_percent DESC
        LIMIT 1;

        IF v_grade IS NULL THEN
            v_grade := CASE WHEN v_has_failed THEN 'F' ELSE 'C' END;
        END IF;

        IF v_has_failed THEN
            v_status := 'FAIL';
            v_fail_count := v_fail_count + 1;
        ELSE
            v_status := 'PASS';
            v_pass_count := v_pass_count + 1;
        END IF;

        -- Upsert into results
        INSERT INTO results (
            exam_id, student_id, total_marks, percentage, grade, status,
            created_at, updated_at, deleted_at, deleted_by
        )
        VALUES (
            p_exam_id, v_student.student_id, v_total_obtained, v_pct, v_grade, v_status,
            clock_timestamp(), clock_timestamp(), NULL, NULL
        )
        ON CONFLICT (exam_id, student_id)
        DO UPDATE SET
            total_marks = EXCLUDED.total_marks,
            percentage = EXCLUDED.percentage,
            grade = EXCLUDED.grade,
            status = EXCLUDED.status,
            deleted_at = NULL,
            deleted_by = NULL,
            updated_at = clock_timestamp();

        v_computed_count := v_computed_count + 1;
    END LOOP;

    -- Compute and assign academic rank among PASS students
    WITH ranked AS (
        SELECT id, rank() OVER (ORDER BY total_marks DESC) as rk
        FROM results
        WHERE exam_id = p_exam_id AND status = 'PASS' AND deleted_at IS NULL
    )
    UPDATE results res
    SET rank = ranked.rk,
        updated_at = clock_timestamp()
    FROM ranked
    WHERE res.id = ranked.id;

    -- Clear ranks for FAIL students
    UPDATE results
    SET rank = NULL,
        updated_at = clock_timestamp()
    WHERE exam_id = p_exam_id AND status != 'PASS' AND deleted_at IS NULL;

    RETURN jsonb_build_object(
        'success', true,
        'exam_id', p_exam_id,
        'total_computed', v_computed_count,
        'passed', v_pass_count,
        'failed', v_fail_count
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp;

-- =============================================================================
-- 5. Exam Publication & Notifications: publish_exam & unpublish_exam
-- =============================================================================

CREATE OR REPLACE FUNCTION publish_exam(
    p_exam_id bigint,
    p_force_notify boolean DEFAULT false
)
RETURNS jsonb AS $$
DECLARE
    v_exam exams%ROWTYPE;
    v_was_published boolean;
    v_results_count int;
    v_notif_count int := 0;
BEGIN
    IF NOT is_admin() THEN
        RAISE EXCEPTION 'Access denied. Administrator privilege required to publish exams.';
    END IF;

    SELECT * INTO v_exam FROM exams WHERE id = p_exam_id AND deleted_at IS NULL;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Exam ID % does not exist.', p_exam_id;
    END IF;

    -- Ensure results have been computed first
    SELECT count(*) INTO v_results_count
    FROM results
    WHERE exam_id = p_exam_id AND deleted_at IS NULL;

    IF v_results_count = 0 THEN
        RAISE EXCEPTION 'Cannot publish exam: results have not yet been computed.';
    END IF;

    v_was_published := (v_exam.status = 'published');

    -- Update exam status
    UPDATE exams
    SET status = 'published',
        published_at = coalesce(published_at, clock_timestamp()),
        publish_date = coalesce(publish_date, CURRENT_DATE),
        updated_at = clock_timestamp()
    WHERE id = p_exam_id;

    -- Dispatch notifications to students if first time or forced
    IF (NOT v_was_published) OR p_force_notify THEN
        INSERT INTO notifications (user_id, type, title, body, link, created_at)
        SELECT 
            p.user_id,
            'result_published',
            'Exam Results Published',
            'Results for "' || v_exam.name || '" are now published. You can now view your official marksheet.',
            '/results/' || p_exam_id::text,
            clock_timestamp()
        FROM results r
        JOIN profiles p ON p.student_id = r.student_id AND p.role = 'student' AND p.active = true
        WHERE r.exam_id = p_exam_id AND r.deleted_at IS NULL;

        GET DIAGNOSTICS v_notif_count = ROW_COUNT;
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'exam_id', p_exam_id,
        'status', 'published',
        'notifications_sent', v_notif_count
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp;

CREATE OR REPLACE FUNCTION unpublish_exam(
    p_exam_id bigint
)
RETURNS jsonb AS $$
BEGIN
    IF NOT is_admin() THEN
        RAISE EXCEPTION 'Access denied. Administrator privilege required to unpublish exams.';
    END IF;

    UPDATE exams
    SET status = 'draft',
        updated_at = clock_timestamp()
    WHERE id = p_exam_id AND deleted_at IS NULL;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Exam ID % not found.', p_exam_id;
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'exam_id', p_exam_id,
        'status', 'draft'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp;

-- =============================================================================
-- 6. Attendance Engine: submit_attendance & correct_attendance
-- =============================================================================

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
    v_status text;
    v_remarks text;
    v_count int := 0;
BEGIN
    IF NOT is_teacher() THEN
        RAISE EXCEPTION 'Access denied. Only registered teachers can submit attendance sessions.';
    END IF;

    v_teacher_id := current_teacher_id();
    IF v_teacher_id IS NULL THEN
        RAISE EXCEPTION 'No teacher profile linked to your user account.';
    END IF;

    SELECT * INTO v_session
    FROM attendance_sessions
    WHERE id = p_session_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Attendance session ID % not found.', p_session_id;
    END IF;

    -- Immutability check: teachers cannot edit once submitted or locked
    IF v_session.status != 'draft' THEN
        RAISE EXCEPTION 'This attendance session has already been % and cannot be modified by teachers.', v_session.status;
    END IF;

    -- Verify teacher assignment
    IF NOT teacher_has_assignment(v_session.batch_id, v_session.subject_id) THEN
        RAISE EXCEPTION 'You are not assigned to teach Subject ID % in Batch ID %.',
            v_session.subject_id, v_session.batch_id;
    END IF;

    -- Enforce configured submission window
    SELECT value INTO v_setting_window FROM settings WHERE key = 'teacher_attendance_edit_window_hours';
    IF v_setting_window IS NOT NULL AND v_setting_window ~ '^\d+$' THEN
        v_window_hours := v_setting_window::int;
    END IF;

    IF (clock_timestamp() - v_session.created_at) > (v_window_hours * interval '1 hour') THEN
        RAISE EXCEPTION 'The %-hour submission window for this attendance session has expired.', v_window_hours;
    END IF;

    -- Process and upsert individual student attendance records
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_records)
    LOOP
        v_student_id := (v_item->>'student_id')::bigint;
        v_status := lower(trim(v_item->>'status'));
        v_remarks := trim(v_item->>'remarks');

        IF v_status NOT IN ('present', 'absent', 'late', 'leave') THEN
            RAISE EXCEPTION 'Invalid attendance status "%" for Student ID %.', v_status, v_student_id;
        END IF;

        INSERT INTO attendance_records (
            session_id, student_id, status, remarks, created_at, updated_at
        )
        VALUES (
            p_session_id, v_student_id, v_status::attendance_status, v_remarks,
            clock_timestamp(), clock_timestamp()
        )
        ON CONFLICT (session_id, student_id)
        DO UPDATE SET
            status = EXCLUDED.status,
            remarks = EXCLUDED.remarks,
            updated_at = clock_timestamp();

        v_count := v_count + 1;
    END LOOP;

    -- Lock and finalize the session
    UPDATE attendance_sessions
    SET status = 'submitted',
        marked_by = v_teacher_id,
        submitted_at = clock_timestamp(),
        updated_at = clock_timestamp()
    WHERE id = p_session_id;

    RETURN jsonb_build_object(
        'success', true,
        'session_id', p_session_id,
        'status', 'submitted',
        'records_recorded', v_count,
        'marked_by', v_teacher_id,
        'submitted_at', clock_timestamp()
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp;

CREATE OR REPLACE FUNCTION correct_attendance(
    p_record_id bigint,
    p_new_status attendance_status,
    p_reason text
)
RETURNS jsonb AS $$
DECLARE
    v_record attendance_records%ROWTYPE;
    v_admin_id uuid;
BEGIN
    IF NOT is_admin() THEN
        RAISE EXCEPTION 'Access denied. Only administrators can perform manual attendance corrections.';
    END IF;

    v_admin_id := auth.uid();

    IF p_reason IS NULL OR trim(p_reason) = '' THEN
        RAISE EXCEPTION 'A clear, documented reason is strictly required for attendance corrections.';
    END IF;

    SELECT * INTO v_record
    FROM attendance_records
    WHERE id = p_record_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Attendance record ID % not found.', p_record_id;
    END IF;

    IF v_record.status = p_new_status THEN
        RAISE EXCEPTION 'The proposed status "%" is identical to the current status.', p_new_status;
    END IF;

    -- 1. Insert immutable record in attendance_changes audit log
    INSERT INTO attendance_changes (
        record_id, old_status, new_status, changed_by, changed_at, reason
    )
    VALUES (
        p_record_id, v_record.status, p_new_status, v_admin_id, clock_timestamp(), trim(p_reason)
    );

    -- 2. Update status on the record
    UPDATE attendance_records
    SET status = p_new_status,
        updated_at = clock_timestamp()
    WHERE id = p_record_id;

    -- Note: Original marked_by and submitted_at on attendance_sessions are intentionally preserved.

    RETURN jsonb_build_object(
        'success', true,
        'record_id', p_record_id,
        'old_status', v_record.status,
        'new_status', p_new_status,
        'changed_by', v_admin_id,
        'reason', trim(p_reason)
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp;

-- =============================================================================
-- 7. Soft Delete & Restore Administration Helpers
-- =============================================================================

CREATE OR REPLACE FUNCTION soft_delete(
    p_table text,
    p_id bigint
)
RETURNS jsonb AS $$
DECLARE
    v_allowed_tables text[] := ARRAY[
        'courses', 'course_subjects', 'batches', 'students', 'fees',
        'payments', 'receipts', 'exams', 'exam_subjects', 'marks',
        'results', 'teachers', 'academic_years', 'universities',
        'document_templates', 'generated_documents'
    ];
    v_table text;
    v_rows int;
BEGIN
    IF NOT is_admin() THEN
        RAISE EXCEPTION 'Access denied. Administrator privilege required to soft-delete records.';
    END IF;

    v_table := lower(trim(p_table));

    IF NOT (v_table = ANY(v_allowed_tables)) THEN
        RAISE EXCEPTION 'Invalid table "%" specified for soft delete.', p_table;
    END IF;

    EXECUTE format(
        'UPDATE %I SET deleted_at = clock_timestamp(), deleted_by = %L, updated_at = clock_timestamp() ' ||
        'WHERE id = %L AND deleted_at IS NULL',
        v_table, auth.uid(), p_id
    );

    GET DIAGNOSTICS v_rows = ROW_COUNT;

    IF v_rows = 0 THEN
        RAISE EXCEPTION 'Record with ID % in table "%" does not exist or was already deleted.', p_id, v_table;
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'table', v_table,
        'id', p_id,
        'action', 'soft_delete'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp;

CREATE OR REPLACE FUNCTION restore_soft_delete(
    p_table text,
    p_id bigint
)
RETURNS jsonb AS $$
DECLARE
    v_allowed_tables text[] := ARRAY[
        'courses', 'course_subjects', 'batches', 'students', 'fees',
        'payments', 'receipts', 'exams', 'exam_subjects', 'marks',
        'results', 'teachers', 'academic_years', 'universities',
        'document_templates', 'generated_documents'
    ];
    v_table text;
    v_rows int;
BEGIN
    IF NOT is_admin() THEN
        RAISE EXCEPTION 'Access denied. Administrator privilege required to restore deleted records.';
    END IF;

    v_table := lower(trim(p_table));

    IF NOT (v_table = ANY(v_allowed_tables)) THEN
        RAISE EXCEPTION 'Invalid table "%" specified for restore.', p_table;
    END IF;

    EXECUTE format(
        'UPDATE %I SET deleted_at = NULL, deleted_by = NULL, updated_at = clock_timestamp() ' ||
        'WHERE id = %L AND deleted_at IS NOT NULL',
        v_table, p_id
    );

    GET DIAGNOSTICS v_rows = ROW_COUNT;

    IF v_rows = 0 THEN
        RAISE EXCEPTION 'Deleted record with ID % in table "%" not found.', p_id, v_table;
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'table', v_table,
        'id', p_id,
        'action', 'restore'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp;
