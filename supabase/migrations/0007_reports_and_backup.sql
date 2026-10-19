-- =============================================================================
-- Migration: 0007_reports_and_backup.sql
-- Description: Server-side views and RPC functions for Reports and Cloud Backup
-- =============================================================================

-- =============================================================================
-- 1. SQL Views for Reports
-- =============================================================================

-- Course financial summary view
DROP VIEW IF EXISTS view_course_financial_summary CASCADE;
CREATE OR REPLACE VIEW view_course_financial_summary AS
SELECT 
    c.id AS course_id,
    c.name AS course_name,
    c.code AS course_code,
    count(DISTINCT s.id) AS total_students,
    coalesce(sum(f.total_fee_paise), 0) AS total_revenue_paise,
    coalesce(sum(f.paid_amount_paise), 0) AS total_collected_paise,
    coalesce(sum(f.pending_amount_paise), 0) AS total_pending_paise,
    round(coalesce(sum(f.total_fee_paise), 0) / 100.0, 2) AS total_revenue_inr,
    round(coalesce(sum(f.paid_amount_paise), 0) / 100.0, 2) AS total_collected_inr,
    round(coalesce(sum(f.pending_amount_paise), 0) / 100.0, 2) AS total_pending_inr
FROM courses c
LEFT JOIN students s ON s.course_id = c.id AND s.deleted_at IS NULL
LEFT JOIN fees f ON f.student_id = s.id AND f.deleted_at IS NULL
WHERE c.deleted_at IS NULL
GROUP BY c.id, c.name, c.code;

-- Fee defaulters view
DROP VIEW IF EXISTS view_fee_defaulters CASCADE;
CREATE OR REPLACE VIEW view_fee_defaulters AS
SELECT 
    s.id AS student_id,
    s.name AS student_name,
    coalesce(s.admission_number, 'N/A') AS admission_number,
    coalesce(s.phone, 'N/A') AS phone,
    s.course_id,
    s.batch_id,
    coalesce(c.name, 'N/A') AS course_name,
    coalesce(b.batch_name, 'N/A') AS batch_name,
    f.total_fee_paise,
    f.paid_amount_paise,
    f.pending_amount_paise,
    round(f.pending_amount_paise / 100.0, 2) AS pending_amount_inr,
    coalesce(to_char(s.admission_date, 'YYYY-MM-DD'), '-') AS due_date
FROM students s
JOIN fees f ON f.student_id = s.id AND f.deleted_at IS NULL
LEFT JOIN courses c ON s.course_id = c.id
LEFT JOIN batches b ON s.batch_id = b.id
WHERE s.deleted_at IS NULL
  AND f.pending_amount_paise > 0;

-- Merit list view
DROP VIEW IF EXISTS view_merit_list CASCADE;
CREATE OR REPLACE VIEW view_merit_list AS
SELECT 
    r.id AS result_id,
    r.rank,
    s.id AS student_id,
    s.name AS student_name,
    coalesce(s.admission_number, 'N/A') AS admission_number,
    e.id AS exam_id,
    e.name AS exam_name,
    s.course_id,
    s.batch_id,
    coalesce(c.name, 'N/A') AS course_name,
    coalesce(b.batch_name, 'N/A') AS batch_name,
    r.total_marks,
    r.percentage,
    r.grade,
    r.status
FROM results r
JOIN students s ON r.student_id = s.id AND s.deleted_at IS NULL
JOIN exams e ON r.exam_id = e.id AND e.deleted_at IS NULL
LEFT JOIN courses c ON s.course_id = c.id
LEFT JOIN batches b ON s.batch_id = b.id
WHERE r.deleted_at IS NULL;

-- Ensure payment_date column exists on payments table
DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' AND table_name = 'payments' AND column_name = 'payment_date'
    ) THEN
        ALTER TABLE public.payments ADD COLUMN payment_date date GENERATED ALWAYS AS (date) STORED;
    END IF;
END $$;

-- Daily fee collection view
DROP VIEW IF EXISTS view_fee_collection_daily CASCADE;
CREATE OR REPLACE VIEW view_fee_collection_daily AS
SELECT 
    p.payment_date,
    p.payment_mode::text AS payment_mode,
    count(p.id) AS transaction_count,
    sum(p.amount_paise) AS total_amount_paise,
    round(sum(p.amount_paise) / 100.0, 2) AS total_amount_inr
FROM payments p
WHERE p.deleted_at IS NULL
  AND p.is_cancelled = false
GROUP BY p.payment_date, p.payment_mode::text;

-- =============================================================================
-- 2. Server RPC Functions for Reports
-- =============================================================================

-- Fee collection report with flexible date & mode filtering
CREATE OR REPLACE FUNCTION report_fee_collection(
    p_start_date date,
    p_end_date date,
    p_payment_mode text DEFAULT NULL
)
RETURNS TABLE (
    id bigint,
    date date,
    student_name text,
    admission_number text,
    course_name text,
    batch_name text,
    amount_paise bigint,
    amount numeric(12,2),
    payment_mode text,
    reference_number text,
    remarks text
) AS $$
BEGIN
    IF NOT is_admin() THEN
        RAISE EXCEPTION 'Access denied. Administrator privilege required.';
    END IF;

    RETURN QUERY
    SELECT 
        p.id,
        p.payment_date AS date,
        s.name AS student_name,
        coalesce(s.admission_number, 'N/A') AS admission_number,
        coalesce(c.name, 'N/A') AS course_name,
        coalesce(b.batch_name, 'N/A') AS batch_name,
        p.amount_paise,
        round(p.amount_paise / 100.0, 2) AS amount,
        p.payment_mode::text,
        coalesce(p.reference_number, '') AS reference_number,
        coalesce(p.remarks, '') AS remarks
    FROM payments p
    JOIN students s ON p.student_id = s.id AND s.deleted_at IS NULL
    LEFT JOIN courses c ON s.course_id = c.id
    LEFT JOIN batches b ON s.batch_id = b.id
    WHERE p.deleted_at IS NULL
      AND p.is_cancelled = false
      AND p.payment_date >= p_start_date
      AND p.payment_date <= p_end_date
      AND (p_payment_mode IS NULL OR p.payment_mode::text = p_payment_mode)
    ORDER BY p.payment_date DESC, p.id DESC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp;

-- Defaulters report function
CREATE OR REPLACE FUNCTION report_defaulters(
    p_course_id bigint DEFAULT NULL,
    p_batch_id bigint DEFAULT NULL
)
RETURNS TABLE (
    student_id bigint,
    student_name text,
    admission_number text,
    phone text,
    course_name text,
    batch_name text,
    fee_head text,
    total_fee_paise bigint,
    paid_amount_paise bigint,
    pending_amount_paise bigint,
    pending_amount numeric(12,2),
    due_date text
) AS $$
BEGIN
    IF NOT is_admin() THEN
        RAISE EXCEPTION 'Access denied. Administrator privilege required.';
    END IF;

    RETURN QUERY
    SELECT 
        s.id AS student_id,
        s.name AS student_name,
        coalesce(s.admission_number, 'N/A') AS admission_number,
        coalesce(s.phone, 'N/A') AS phone,
        coalesce(c.name, 'N/A') AS course_name,
        coalesce(b.batch_name, 'N/A') AS batch_name,
        'Course Fee'::text AS fee_head,
        f.total_fee_paise,
        f.paid_amount_paise,
        f.pending_amount_paise,
        round(f.pending_amount_paise / 100.0, 2) AS pending_amount,
        coalesce(to_char(s.admission_date, 'YYYY-MM-DD'), '-') AS due_date
    FROM students s
    JOIN fees f ON f.student_id = s.id AND f.deleted_at IS NULL
    LEFT JOIN courses c ON s.course_id = c.id
    LEFT JOIN batches b ON s.batch_id = b.id
    WHERE s.deleted_at IS NULL
      AND f.pending_amount_paise > 0
      AND (p_course_id IS NULL OR s.course_id = p_course_id)
      AND (p_batch_id IS NULL OR s.batch_id = p_batch_id)
    ORDER BY f.pending_amount_paise DESC, s.name ASC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp;

-- Course revenue vs collected vs outstanding function
CREATE OR REPLACE FUNCTION report_course_revenue()
RETURNS TABLE (
    course_id bigint,
    course_name text,
    course_code text,
    total_students bigint,
    total_revenue_paise bigint,
    total_collected_paise bigint,
    total_pending_paise bigint,
    total_revenue numeric(14,2),
    total_collected numeric(14,2),
    total_pending numeric(14,2)
) AS $$
BEGIN
    IF NOT is_admin() THEN
        RAISE EXCEPTION 'Access denied. Administrator privilege required.';
    END IF;

    RETURN QUERY
    SELECT 
        c.id AS course_id,
        c.name AS course_name,
        c.code AS course_code,
        count(DISTINCT s.id) AS total_students,
        coalesce(sum(f.total_fee_paise), 0) AS total_revenue_paise,
        coalesce(sum(f.paid_amount_paise), 0) AS total_collected_paise,
        coalesce(sum(f.pending_amount_paise), 0) AS total_pending_paise,
        round(coalesce(sum(f.total_fee_paise), 0) / 100.0, 2) AS total_revenue,
        round(coalesce(sum(f.paid_amount_paise), 0) / 100.0, 2) AS total_collected,
        round(coalesce(sum(f.pending_amount_paise), 0) / 100.0, 2) AS total_pending
    FROM courses c
    LEFT JOIN students s ON s.course_id = c.id AND s.deleted_at IS NULL
    LEFT JOIN fees f ON f.student_id = s.id AND f.deleted_at IS NULL
    WHERE c.deleted_at IS NULL
    GROUP BY c.id, c.name, c.code
    ORDER BY c.name ASC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp;

-- Merit list / results report function
CREATE OR REPLACE FUNCTION report_merit_list(
    p_exam_id bigint DEFAULT NULL,
    p_course_id bigint DEFAULT NULL,
    p_batch_id bigint DEFAULT NULL
)
RETURNS TABLE (
    rank int,
    student_id bigint,
    student_name text,
    admission_number text,
    exam_name text,
    course_name text,
    batch_name text,
    total_marks numeric(6,2),
    percentage numeric(5,2),
    grade text,
    status text
) AS $$
BEGIN
    IF NOT is_admin() THEN
        RAISE EXCEPTION 'Access denied. Administrator privilege required.';
    END IF;

    RETURN QUERY
    SELECT 
        r.rank,
        s.id AS student_id,
        s.name AS student_name,
        coalesce(s.admission_number, 'N/A') AS admission_number,
        e.name AS exam_name,
        coalesce(c.name, 'N/A') AS course_name,
        coalesce(b.batch_name, 'N/A') AS batch_name,
        r.total_marks,
        r.percentage,
        r.grade,
        r.status
    FROM results r
    JOIN students s ON r.student_id = s.id AND s.deleted_at IS NULL
    JOIN exams e ON r.exam_id = e.id AND e.deleted_at IS NULL
    LEFT JOIN courses c ON s.course_id = c.id
    LEFT JOIN batches b ON s.batch_id = b.id
    WHERE r.deleted_at IS NULL
      AND (p_exam_id IS NULL OR r.exam_id = p_exam_id)
      AND (p_course_id IS NULL OR s.course_id = p_course_id)
      AND (p_batch_id IS NULL OR s.batch_id = p_batch_id)
    ORDER BY 
        CASE WHEN r.status = 'PASS' THEN 0 ELSE 1 END,
        r.rank ASC NULLS LAST,
        r.percentage DESC,
        s.name ASC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp;

-- Student directory list report function
CREATE OR REPLACE FUNCTION report_student_list(
    p_course_id bigint DEFAULT NULL,
    p_batch_id bigint DEFAULT NULL,
    p_status text DEFAULT NULL
)
RETURNS TABLE (
    id bigint,
    name text,
    admission_number text,
    registration_number text,
    phone text,
    gender text,
    course_name text,
    batch_name text,
    admission_date text,
    status text
) AS $$
BEGIN
    IF NOT is_admin() THEN
        RAISE EXCEPTION 'Access denied. Administrator privilege required.';
    END IF;

    RETURN QUERY
    SELECT 
        s.id,
        s.name,
        coalesce(s.admission_number, 'N/A') AS admission_number,
        coalesce(s.registration_number, 'N/A') AS registration_number,
        coalesce(s.phone, 'N/A') AS phone,
        coalesce(s.gender, 'N/A') AS gender,
        coalesce(c.name, 'N/A') AS course_name,
        coalesce(b.batch_name, 'N/A') AS batch_name,
        coalesce(to_char(s.admission_date, 'YYYY-MM-DD'), 'N/A') AS admission_date,
        coalesce(s.status, 'active') AS status
    FROM students s
    LEFT JOIN courses c ON s.course_id = c.id
    LEFT JOIN batches b ON s.batch_id = b.id
    WHERE s.deleted_at IS NULL
      AND (p_course_id IS NULL OR s.course_id = p_course_id)
      AND (p_batch_id IS NULL OR s.batch_id = p_batch_id)
      AND (p_status IS NULL OR s.status = p_status)
    ORDER BY s.name ASC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp;

-- =============================================================================
-- 3. Cloud Database Dump Export Function
-- =============================================================================

CREATE OR REPLACE FUNCTION export_database_dump()
RETURNS jsonb AS $$
DECLARE
    v_dump jsonb;
    v_now timestamptz := clock_timestamp();
    v_settings jsonb;
    v_academic_years jsonb;
    v_courses jsonb;
    v_course_subjects jsonb;
    v_batches jsonb;
    v_students jsonb;
    v_fees jsonb;
    v_payments jsonb;
    v_receipts jsonb;
    v_exams jsonb;
    v_exam_subjects jsonb;
    v_marks jsonb;
    v_results jsonb;
    v_grading_schemes jsonb;
    v_teachers jsonb;
    v_teacher_assignments jsonb;
BEGIN
    IF NOT is_admin() THEN
        RAISE EXCEPTION 'Access denied. Administrator privilege required to export database dump.';
    END IF;

    SELECT coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_settings FROM (SELECT key, value, description FROM settings) t;
    SELECT coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_academic_years FROM (SELECT id, year_name, is_current FROM academic_years WHERE deleted_at IS NULL) t;
    SELECT coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_courses FROM (SELECT id, name, code, total_fee_paise, duration FROM courses WHERE deleted_at IS NULL) t;
    SELECT coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_course_subjects FROM (SELECT id, course_id, subject_name, subject_code, max_marks, pass_marks FROM course_subjects WHERE deleted_at IS NULL) t;
    SELECT coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_batches FROM (SELECT id, course_id, batch_name, start_date, academic_year_id FROM batches WHERE deleted_at IS NULL) t;
    SELECT coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_students FROM (SELECT id, name, admission_number, registration_number, phone, email, gender, dob, course_id, batch_id, admission_date, status FROM students WHERE deleted_at IS NULL) t;
    SELECT coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_fees FROM (SELECT id, student_id, total_fee_paise, paid_amount_paise, pending_amount_paise, discount_amount_paise FROM fees WHERE deleted_at IS NULL) t;
    SELECT coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_payments FROM (SELECT id, student_id, amount_paise, payment_mode, reference_number, remarks, payment_date, is_cancelled FROM payments WHERE deleted_at IS NULL) t;
    SELECT coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_receipts FROM (SELECT id, payment_id, receipt_number, created_at FROM receipts WHERE deleted_at IS NULL) t;
    SELECT coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_exams FROM (SELECT id, name, course_id, batch_id, status, exam_date, publish_date FROM exams WHERE deleted_at IS NULL) t;
    SELECT coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_exam_subjects FROM (SELECT id, exam_id, name, code, max_marks, pass_marks FROM exam_subjects WHERE deleted_at IS NULL) t;
    SELECT coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_marks FROM (SELECT id, exam_id, subject_id, student_id, marks_obtained, is_absent FROM marks WHERE deleted_at IS NULL) t;
    SELECT coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_results FROM (SELECT id, exam_id, student_id, total_marks, percentage, grade, status, rank FROM results WHERE deleted_at IS NULL) t;
    SELECT coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_grading_schemes FROM (SELECT id, name, min_percent, max_percent, grade, is_pass FROM grading_schemes WHERE deleted_at IS NULL) t;
    SELECT coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_teachers FROM (SELECT id, name, phone, email, active FROM teachers WHERE deleted_at IS NULL) t;
    SELECT coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_teacher_assignments FROM (SELECT id, teacher_id, course_id, batch_id FROM teacher_assignments WHERE deleted_at IS NULL) t;

    v_dump := jsonb_build_object(
        'meta', jsonb_build_object(
            'app', 'MIPS ERP',
            'version', '2.0.0',
            'exported_at', v_now,
            'exported_by', auth.uid(),
            'counts', jsonb_build_object(
                'students', jsonb_array_length(v_students),
                'courses', jsonb_array_length(v_courses),
                'batches', jsonb_array_length(v_batches),
                'payments', jsonb_array_length(v_payments),
                'exams', jsonb_array_length(v_exams),
                'results', jsonb_array_length(v_results)
            )
        ),
        'tables', jsonb_build_object(
            'settings', v_settings,
            'academic_years', v_academic_years,
            'courses', v_courses,
            'course_subjects', v_course_subjects,
            'batches', v_batches,
            'students', v_students,
            'fees', v_fees,
            'payments', v_payments,
            'receipts', v_receipts,
            'exams', v_exams,
            'exam_subjects', v_exam_subjects,
            'marks', v_marks,
            'results', v_results,
            'grading_schemes', v_grading_schemes,
            'teachers', v_teachers,
            'teacher_assignments', v_teacher_assignments
        )
    );

    RETURN v_dump;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp;
