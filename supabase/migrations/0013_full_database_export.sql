-- =============================================================================
-- MIPS ERP Database Migration: 0013_full_database_export.sql
-- Sub-phase 7C: Complete Institutional Cloud Database Export & Integrity Verification
-- =============================================================================

CREATE OR REPLACE FUNCTION export_database_dump()
RETURNS jsonb AS $$
DECLARE
    v_dump jsonb;
    v_now timestamptz := clock_timestamp();
    
    -- Tables
    v_settings jsonb;
    v_academic_years jsonb;
    v_universities jsonb;
    v_courses jsonb;
    v_course_subjects jsonb;
    v_batches jsonb;
    v_teachers jsonb;
    v_students jsonb;
    v_student_enrollments jsonb;
    v_teacher_assignments jsonb;
    v_fees jsonb;
    v_fee_items jsonb;
    v_payments jsonb;
    v_payment_allocations jsonb;
    v_fee_adjustments jsonb;
    v_receipts jsonb;
    v_exams jsonb;
    v_exam_subjects jsonb;
    v_marks jsonb;
    v_results jsonb;
    v_grading_schemes jsonb;
    v_attendance_sessions jsonb;
    v_attendance_records jsonb;
    v_attendance_alert_state jsonb;
    v_timetables jsonb;
    v_timetable_entries jsonb;
    v_announcements jsonb;
    v_notifications jsonb;
    v_document_templates jsonb;
    v_generated_documents jsonb;

    -- Financial aggregates
    v_total_fee_paise bigint := 0;
    v_total_paid_paise bigint := 0;
    v_total_pending_paise bigint := 0;
BEGIN
    IF NOT is_admin() THEN
        RAISE EXCEPTION 'Access denied. Administrator privilege required to export database dump.';
    END IF;

    -- Core Catalog & Config
    SELECT coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_settings FROM (SELECT key, value, description FROM settings) t;
    SELECT coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_academic_years FROM (SELECT id, year_name, is_current FROM academic_years WHERE deleted_at IS NULL) t;
    SELECT coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_universities FROM (SELECT id, name, code FROM universities WHERE deleted_at IS NULL) t;
    SELECT coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_courses FROM (SELECT id, name, code, course_type, total_fee_paise, duration, university_id FROM courses WHERE deleted_at IS NULL) t;
    SELECT coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_course_subjects FROM (SELECT id, course_id, subject_name, subject_code, max_marks, pass_marks FROM course_subjects WHERE deleted_at IS NULL) t;
    SELECT coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_batches FROM (SELECT id, course_id, batch_name, start_date, academic_year_id, status FROM batches WHERE deleted_at IS NULL) t;

    -- People & Staff
    SELECT coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_teachers FROM (SELECT id, name, phone, email, login_username, active FROM teachers WHERE deleted_at IS NULL) t;
    SELECT coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_students FROM (SELECT id, name, admission_number, registration_number, phone, email, gender, dob, address, course_id, batch_id, university_id, academic_year_id, admission_date, status FROM students WHERE deleted_at IS NULL) t;
    SELECT coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_student_enrollments FROM (SELECT id, student_id, course_id, batch_id, kind, status, enrolled_on FROM student_enrollments WHERE deleted_at IS NULL) t;
    SELECT coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_teacher_assignments FROM (SELECT id, teacher_id, course_id, batch_id, subject_id, active FROM teacher_assignments WHERE active = true) t;

    -- Finance & Ledger
    SELECT coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_fees FROM (SELECT id, student_id, total_fee_paise, paid_amount_paise, pending_amount_paise, discount_amount_paise FROM fees WHERE deleted_at IS NULL) t;
    SELECT coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_fee_items FROM (SELECT id, student_id, enrollment_id, fee_head, amount_paise, paid_amount_paise, due_date FROM fee_items WHERE deleted_at IS NULL) t;
    SELECT coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_payments FROM (SELECT id, student_id, amount_paise, payment_mode, reference_number, remarks, date, payment_date, is_cancelled, cancel_reason FROM payments WHERE deleted_at IS NULL) t;
    SELECT coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_payment_allocations FROM (SELECT id, payment_id, fee_item_id, allocated_amount_paise FROM payment_allocations) t;
    SELECT coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_fee_adjustments FROM (SELECT id, student_id, enrollment_id, amount_paise, type, reason FROM fee_adjustments) t;
    SELECT coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_receipts FROM (SELECT id, payment_id, receipt_number, created_at FROM receipts WHERE deleted_at IS NULL) t;

    -- Exams & Results
    SELECT coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_exams FROM (SELECT id, name, course_id, batch_id, status, exam_date, publish_date FROM exams WHERE deleted_at IS NULL) t;
    SELECT coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_exam_subjects FROM (SELECT id, exam_id, name, code, max_marks, pass_marks FROM exam_subjects WHERE deleted_at IS NULL) t;
    SELECT coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_marks FROM (SELECT id, exam_id, subject_id, student_id, marks_obtained, is_absent FROM marks WHERE deleted_at IS NULL) t;
    SELECT coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_results FROM (SELECT id, exam_id, student_id, total_marks, percentage, grade, status, rank FROM results WHERE deleted_at IS NULL) t;
    SELECT coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_grading_schemes FROM (SELECT id, min_percent, max_percent, grade, is_pass FROM grading_schemes) t;

    -- Attendance & Timetables
    SELECT coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_attendance_sessions FROM (SELECT id, batch_id, subject_id, date, slot, status, marked_by, submitted_at FROM attendance_sessions) t;
    SELECT coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_attendance_records FROM (SELECT id, session_id, student_id, status, remarks FROM attendance_records) t;
    SELECT coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_attendance_alert_state FROM (SELECT student_id, enrollment_id, last_band, updated_at FROM attendance_alert_state) t;
    SELECT coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_timetables FROM (SELECT id, batch_id, title, effective_from, status FROM timetables WHERE deleted_at IS NULL) t;
    SELECT coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_timetable_entries FROM (SELECT id, timetable_id, day_of_week, slot, subject_id, teacher_id, room FROM timetable_entries) t;

    -- Communication & Documents
    SELECT coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_announcements FROM (SELECT id, category, title, body, audience_type, recipient_count, created_at FROM announcements WHERE retracted_at IS NULL) t;
    SELECT coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_notifications FROM (SELECT id, user_id, recipient_type, recipient_id, type, title, body, read_at, created_at FROM notifications) t;
    SELECT coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_document_templates FROM (SELECT id, name, template_type, content FROM document_templates WHERE deleted_at IS NULL) t;
    SELECT coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_generated_documents FROM (SELECT id, template_id, student_id, document_number, title, created_at FROM generated_documents WHERE deleted_at IS NULL) t;

    -- Calculate Financial Reconciliation Totals
    SELECT coalesce(sum(amount_paise), 0) INTO v_total_fee_paise FROM fee_items WHERE deleted_at IS NULL;
    SELECT coalesce(sum(amount_paise), 0) INTO v_total_paid_paise FROM payments WHERE deleted_at IS NULL AND is_cancelled = false;
    v_total_pending_paise := greatest(0, v_total_fee_paise - v_total_paid_paise);

    v_dump := jsonb_build_object(
        'meta', jsonb_build_object(
            'app', 'MIPS ERP',
            'version', '2.0.0',
            'exported_at', v_now,
            'exported_by', auth.uid(),
            'counts', jsonb_build_object(
                'students', jsonb_array_length(v_students),
                'student_enrollments', jsonb_array_length(v_student_enrollments),
                'teachers', jsonb_array_length(v_teachers),
                'courses', jsonb_array_length(v_courses),
                'batches', jsonb_array_length(v_batches),
                'fees', jsonb_array_length(v_fees),
                'fee_items', jsonb_array_length(v_fee_items),
                'payments', jsonb_array_length(v_payments),
                'receipts', jsonb_array_length(v_receipts),
                'exams', jsonb_array_length(v_exams),
                'marks', jsonb_array_length(v_marks),
                'results', jsonb_array_length(v_results),
                'attendance_sessions', jsonb_array_length(v_attendance_sessions),
                'attendance_records', jsonb_array_length(v_attendance_records),
                'timetables', jsonb_array_length(v_timetables),
                'announcements', jsonb_array_length(v_announcements),
                'notifications', jsonb_array_length(v_notifications)
            ),
            'reconciliation', jsonb_build_object(
                'total_fee_billed_paise', v_total_fee_paise,
                'total_paid_paise', v_total_paid_paise,
                'total_pending_paise', v_total_pending_paise,
                'students_count', jsonb_array_length(v_students),
                'results_count', jsonb_array_length(v_results)
            )
        ),
        'tables', jsonb_build_object(
            'settings', v_settings,
            'academic_years', v_academic_years,
            'universities', v_universities,
            'courses', v_courses,
            'course_subjects', v_course_subjects,
            'batches', v_batches,
            'teachers', v_teachers,
            'students', v_students,
            'student_enrollments', v_student_enrollments,
            'teacher_assignments', v_teacher_assignments,
            'fees', v_fees,
            'fee_items', v_fee_items,
            'payments', v_payments,
            'payment_allocations', v_payment_allocations,
            'fee_adjustments', v_fee_adjustments,
            'receipts', v_receipts,
            'exams', v_exams,
            'exam_subjects', v_exam_subjects,
            'marks', v_marks,
            'results', v_results,
            'grading_schemes', v_grading_schemes,
            'attendance_sessions', v_attendance_sessions,
            'attendance_records', v_attendance_records,
            'attendance_alert_state', v_attendance_alert_state,
            'timetables', v_timetables,
            'timetable_entries', v_timetable_entries,
            'announcements', v_announcements,
            'notifications', v_notifications,
            'document_templates', v_document_templates,
            'generated_documents', v_generated_documents
        )
    );

    RETURN v_dump;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp;

GRANT EXECUTE ON FUNCTION export_database_dump() TO authenticated;
