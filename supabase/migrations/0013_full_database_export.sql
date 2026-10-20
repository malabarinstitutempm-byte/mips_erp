-- =============================================================================
-- MIPS ERP Database Migration: 0013_full_database_export.sql
-- Sub-phase 7C: Complete Institutional Cloud Database Export & Integrity Verification
-- Generic JSONB Export Engine with Full Reconciliation
-- =============================================================================

CREATE OR REPLACE FUNCTION export_database_dump()
RETURNS jsonb AS $$
DECLARE
    v_dump jsonb;
    v_now timestamptz := clock_timestamp();
    
    v_settings jsonb;
    v_academic_years jsonb;
    v_universities jsonb;
    v_courses jsonb;
    v_course_subjects jsonb;
    v_batches jsonb;
    v_batch_periods jsonb;
    v_teachers jsonb;
    v_students jsonb;
    v_student_enrollments jsonb;
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
    v_daily_timetables jsonb;
    v_daily_timetable_entries jsonb;
    v_timetables jsonb;
    v_timetable_entries jsonb;
    v_announcements jsonb;
    v_notifications jsonb;
    v_document_templates jsonb;
    v_generated_documents jsonb;
    v_audit_log jsonb;

    v_total_fee_paise bigint := 0;
    v_total_paid_paise bigint := 0;
    v_total_pending_paise bigint := 0;
    v_total_students bigint := 0;
    v_active_students bigint := 0;
BEGIN
    IF NOT is_admin() THEN
        RAISE EXCEPTION 'Access denied. Administrator privilege required to export database dump.';
    END IF;

    -- Generic exports: to_jsonb(t) of every existing cloud data table
    SELECT coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_settings FROM settings t;
    SELECT coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_academic_years FROM academic_years t;
    SELECT coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_universities FROM universities t;
    SELECT coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_courses FROM courses t;
    SELECT coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_course_subjects FROM course_subjects t;
    SELECT coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_batches FROM batches t;
    SELECT coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_teachers FROM teachers t;
    SELECT coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_students FROM students t;
    SELECT coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_student_enrollments FROM student_enrollments t;
    SELECT coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_fees FROM fees t;
    SELECT coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_fee_items FROM fee_items t;
    SELECT coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_payments FROM payments t;
    SELECT coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_payment_allocations FROM payment_allocations t;
    SELECT coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_fee_adjustments FROM fee_adjustments t;
    SELECT coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_receipts FROM receipts t;
    SELECT coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_exams FROM exams t;
    SELECT coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_exam_subjects FROM exam_subjects t;
    SELECT coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_marks FROM marks t;
    SELECT coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_results FROM results t;
    SELECT coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_grading_schemes FROM grading_schemes t;
    SELECT coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_attendance_sessions FROM attendance_sessions t;
    SELECT coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_attendance_records FROM attendance_records t;
    SELECT coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_attendance_alert_state FROM attendance_alert_state t;
    SELECT coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_timetables FROM timetables t;
    SELECT coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_timetable_entries FROM timetable_entries t;
    SELECT coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_announcements FROM announcements t;
    SELECT coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_notifications FROM notifications t;
    SELECT coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_document_templates FROM document_templates t;
    SELECT coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_generated_documents FROM generated_documents t;

    -- Dynamic table availability checks
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'batch_periods') THEN
        SELECT coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_batch_periods FROM batch_periods t;
    ELSE
        v_batch_periods := '[]'::jsonb;
    END IF;

    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'daily_timetables') THEN
        SELECT coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_daily_timetables FROM daily_timetables t;
        SELECT coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_daily_timetable_entries FROM daily_timetable_entries t;
    ELSE
        v_daily_timetables := '[]'::jsonb;
        v_daily_timetable_entries := '[]'::jsonb;
    END IF;

    SELECT coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_audit_log 
    FROM (SELECT * FROM audit_log ORDER BY id DESC LIMIT 5000) t;

    -- Reconciliation Counts & Ledger Totals
    SELECT count(*), count(*) FILTER (WHERE status = 'active' AND deleted_at IS NULL)
    INTO v_total_students, v_active_students
    FROM students;

    SELECT coalesce(sum(amount_paise), 0) INTO v_total_fee_paise FROM fee_items WHERE deleted_at IS NULL;
    SELECT coalesce(sum(amount_paise), 0) INTO v_total_paid_paise FROM payments WHERE deleted_at IS NULL AND is_cancelled = false;
    v_total_pending_paise := greatest(0, v_total_fee_paise - v_total_paid_paise);

    v_dump := jsonb_build_object(
        'meta', jsonb_build_object(
            'app', 'MIPS ERP',
            'version', '2.0.0',
            'exported_at', v_now,
            'exported_by', auth.uid()
        ),
        'reconciliation', jsonb_build_object(
            'total_students', v_total_students,
            'active_students', v_active_students,
            'total_fee_billed_paise', v_total_fee_paise,
            'total_paid_paise', v_total_paid_paise,
            'total_pending_paise', v_total_pending_paise,
            'total_payments', (SELECT count(*) FROM payments WHERE deleted_at IS NULL),
            'total_receipts', (SELECT count(*) FROM receipts WHERE deleted_at IS NULL),
            'total_attendance_sessions', (SELECT count(*) FROM attendance_sessions),
            'total_exams', (SELECT count(*) FROM exams WHERE deleted_at IS NULL),
            'total_results', (SELECT count(*) FROM results WHERE deleted_at IS NULL)
        ),
        'tables', jsonb_build_object(
            'settings', v_settings,
            'academic_years', v_academic_years,
            'universities', v_universities,
            'courses', v_courses,
            'course_subjects', v_course_subjects,
            'batches', v_batches,
            'batch_periods', v_batch_periods,
            'teachers', v_teachers,
            'students', v_students,
            'student_enrollments', v_student_enrollments,
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
            'daily_timetables', v_daily_timetables,
            'daily_timetable_entries', v_daily_timetable_entries,
            'timetables', v_timetables,
            'timetable_entries', v_timetable_entries,
            'announcements', v_announcements,
            'notifications', v_notifications,
            'document_templates', v_document_templates,
            'generated_documents', v_generated_documents,
            'audit_log', v_audit_log
        )
    );

    RETURN v_dump;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp;

GRANT EXECUTE ON FUNCTION export_database_dump() TO authenticated;
