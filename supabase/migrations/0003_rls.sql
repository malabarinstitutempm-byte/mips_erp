-- =============================================================================
-- MIPS ERP Database Migration: 0003_rls.sql
-- Sub-phase 1C: Row Level Security (RLS) Policies, Secure Views & Role Isolation
-- =============================================================================

-- =============================================================================
-- 1. Helper Function: is_student()
-- =============================================================================

CREATE OR REPLACE FUNCTION is_student()
RETURNS boolean AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM profiles
        WHERE user_id = auth.uid() AND role = 'student' AND active = true
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE
SET search_path = public, pg_temp;

GRANT EXECUTE ON FUNCTION is_admin() TO authenticated;
GRANT EXECUTE ON FUNCTION is_teacher() TO authenticated;
GRANT EXECUTE ON FUNCTION is_student() TO authenticated;
GRANT EXECUTE ON FUNCTION current_teacher_id() TO authenticated;
GRANT EXECUTE ON FUNCTION current_student_id() TO authenticated;
GRANT EXECUTE ON FUNCTION teacher_has_assignment(bigint, bigint) TO authenticated;

-- =============================================================================
-- 2. Revoke Anon / Public Access Across All Schema Objects
-- =============================================================================

-- Completely lock down the public schema from unauthenticated (anon / public) clients
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM anon, PUBLIC;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM anon, PUBLIC;
REVOKE ALL ON ALL ROUTINES IN SCHEMA public FROM anon, PUBLIC;

ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON TABLES FROM anon, PUBLIC;
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON SEQUENCES FROM anon, PUBLIC;
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON ROUTINES FROM anon, PUBLIC;

-- Grant schema access and table CRUD to authenticated users (governed strictly by RLS)
GRANT USAGE ON SCHEMA public TO authenticated, service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO authenticated;

-- Ensure audit log & attendance changes remain immutable (no update or delete by anyone)
REVOKE UPDATE, DELETE ON audit_log FROM PUBLIC, anon, authenticated;
REVOKE UPDATE, DELETE ON attendance_changes FROM PUBLIC, anon, authenticated;
REVOKE INSERT ON audit_log FROM PUBLIC, anon, authenticated;
REVOKE INSERT ON attendance_changes FROM PUBLIC, anon, authenticated;

-- =============================================================================
-- 3. Enable Row Level Security (RLS) on ALL Tables
-- =============================================================================

ALTER TABLE settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE academic_years ENABLE ROW LEVEL SECURITY;
ALTER TABLE universities ENABLE ROW LEVEL SECURITY;
ALTER TABLE courses ENABLE ROW LEVEL SECURITY;
ALTER TABLE course_subjects ENABLE ROW LEVEL SECURITY;
ALTER TABLE batches ENABLE ROW LEVEL SECURITY;
ALTER TABLE teachers ENABLE ROW LEVEL SECURITY;
ALTER TABLE students ENABLE ROW LEVEL SECURITY;
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE teacher_assignments ENABLE ROW LEVEL SECURITY;
ALTER TABLE fees ENABLE ROW LEVEL SECURITY;
ALTER TABLE payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE exams ENABLE ROW LEVEL SECURITY;
ALTER TABLE exam_subjects ENABLE ROW LEVEL SECURITY;
ALTER TABLE marks ENABLE ROW LEVEL SECURITY;
ALTER TABLE results ENABLE ROW LEVEL SECURITY;
ALTER TABLE grading_schemes ENABLE ROW LEVEL SECURITY;
ALTER TABLE attendance_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE attendance_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE attendance_changes ENABLE ROW LEVEL SECURITY;
ALTER TABLE document_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE generated_documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE number_counters ENABLE ROW LEVEL SECURITY;
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE push_subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_log ENABLE ROW LEVEL SECURITY;

-- =============================================================================
-- 4. Specialized Secure Views (Teacher Isolation, Student Profile & Payments)
-- =============================================================================

-- 4.1. students_for_teacher View
-- Teacher can ONLY see assigned batch students: id, name, registration_number, batch
-- DOB, phone, email, address, and fees are strictly excluded.
CREATE OR REPLACE VIEW students_for_teacher
WITH (security_barrier = true)
AS
SELECT 
    s.id,
    s.name,
    s.registration_number,
    s.admission_number,
    s.batch_id,
    b.batch_name AS batch
FROM students s
JOIN batches b ON b.id = s.batch_id
WHERE s.deleted_at IS NULL
  AND s.status = 'active'
  AND (
      is_admin()
      OR (
          is_teacher() AND s.batch_id IN (
              SELECT ta.batch_id 
              FROM teacher_assignments ta 
              WHERE ta.teacher_id = current_teacher_id() 
                AND ta.active = true
          )
      )
  );

GRANT SELECT ON students_for_teacher TO authenticated;

-- 4.2. student_profile_view View
-- Student reads their own profile with course & batch details, hiding internal fields
-- (legacy_id, import_id, deleted_at, deleted_by, audit timestamps)
CREATE OR REPLACE VIEW student_profile_view
WITH (security_barrier = true)
AS
SELECT 
    s.id,
    s.admission_number,
    s.registration_number,
    s.name,
    s.dob,
    s.gender,
    s.phone,
    s.email,
    s.address,
    s.admission_date,
    s.status,
    s.course_id,
    c.name AS course_name,
    c.code AS course_code,
    s.batch_id,
    b.batch_name,
    s.university_id,
    u.name AS university_name,
    s.academic_year_id,
    ay.year_name AS academic_year
FROM students s
LEFT JOIN courses c ON c.id = s.course_id
LEFT JOIN batches b ON b.id = s.batch_id
LEFT JOIN universities u ON u.id = s.university_id
LEFT JOIN academic_years ay ON ay.id = s.academic_year_id
WHERE s.deleted_at IS NULL
  AND (
      is_admin()
      OR (
          is_student() AND s.id = current_student_id()
      )
  );

GRANT SELECT ON student_profile_view TO authenticated;

-- 4.3. student_payments_view View
-- Student reads their own payments without administrative free-text remarks or internal fields
CREATE OR REPLACE VIEW student_payments_view
WITH (security_barrier = true)
AS
SELECT 
    p.id,
    p.student_id,
    p.amount_paise,
    p.payment_mode,
    p.reference_number,
    p.date,
    p.is_cancelled,
    p.created_at
FROM payments p
WHERE p.deleted_at IS NULL
  AND (
      is_admin()
      OR (
          is_student() AND p.student_id = current_student_id()
      )
  );

GRANT SELECT ON student_payments_view TO authenticated;

-- =============================================================================
-- 5. Row Level Security Policies
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 5.1. settings
-- -----------------------------------------------------------------------------
CREATE POLICY p_settings_admin ON settings
    FOR ALL TO authenticated
    USING (is_admin())
    WITH CHECK (is_admin());

CREATE POLICY p_settings_authenticated_select ON settings
    FOR SELECT TO authenticated
    USING (true);

-- -----------------------------------------------------------------------------
-- 5.2. academic_years
-- -----------------------------------------------------------------------------
CREATE POLICY p_academic_years_admin ON academic_years
    FOR ALL TO authenticated
    USING (is_admin())
    WITH CHECK (is_admin());

CREATE POLICY p_academic_years_select ON academic_years
    FOR SELECT TO authenticated
    USING (deleted_at IS NULL);

-- -----------------------------------------------------------------------------
-- 5.3. universities
-- -----------------------------------------------------------------------------
CREATE POLICY p_universities_admin ON universities
    FOR ALL TO authenticated
    USING (is_admin())
    WITH CHECK (is_admin());

CREATE POLICY p_universities_select ON universities
    FOR SELECT TO authenticated
    USING (deleted_at IS NULL);

-- -----------------------------------------------------------------------------
-- 5.4. courses
-- -----------------------------------------------------------------------------
CREATE POLICY p_courses_admin ON courses
    FOR ALL TO authenticated
    USING (is_admin())
    WITH CHECK (is_admin());

CREATE POLICY p_courses_select ON courses
    FOR SELECT TO authenticated
    USING (deleted_at IS NULL);

-- -----------------------------------------------------------------------------
-- 5.5. course_subjects
-- -----------------------------------------------------------------------------
CREATE POLICY p_course_subjects_admin ON course_subjects
    FOR ALL TO authenticated
    USING (is_admin())
    WITH CHECK (is_admin());

CREATE POLICY p_course_subjects_select ON course_subjects
    FOR SELECT TO authenticated
    USING (deleted_at IS NULL);

-- -----------------------------------------------------------------------------
-- 5.6. batches
-- -----------------------------------------------------------------------------
CREATE POLICY p_batches_admin ON batches
    FOR ALL TO authenticated
    USING (is_admin())
    WITH CHECK (is_admin());

CREATE POLICY p_batches_select ON batches
    FOR SELECT TO authenticated
    USING (deleted_at IS NULL);

-- -----------------------------------------------------------------------------
-- 5.7. grading_schemes
-- -----------------------------------------------------------------------------
CREATE POLICY p_grading_schemes_admin ON grading_schemes
    FOR ALL TO authenticated
    USING (is_admin())
    WITH CHECK (is_admin());

CREATE POLICY p_grading_schemes_select ON grading_schemes
    FOR SELECT TO authenticated
    USING (true);

-- -----------------------------------------------------------------------------
-- 5.8. teachers
-- -----------------------------------------------------------------------------
CREATE POLICY p_teachers_admin ON teachers
    FOR ALL TO authenticated
    USING (is_admin())
    WITH CHECK (is_admin());

CREATE POLICY p_teachers_teacher_select ON teachers
    FOR SELECT TO authenticated
    USING (is_teacher() AND id = current_teacher_id() AND deleted_at IS NULL);

-- -----------------------------------------------------------------------------
-- 5.9. profiles
-- -----------------------------------------------------------------------------
CREATE POLICY p_profiles_admin ON profiles
    FOR ALL TO authenticated
    USING (is_admin())
    WITH CHECK (is_admin());

CREATE POLICY p_profiles_self_select ON profiles
    FOR SELECT TO authenticated
    USING (user_id = auth.uid() AND active = true);

CREATE POLICY p_profiles_self_update ON profiles
    FOR UPDATE TO authenticated
    USING (user_id = auth.uid())
    WITH CHECK (user_id = auth.uid());

-- -----------------------------------------------------------------------------
-- 5.10. teacher_assignments
-- -----------------------------------------------------------------------------
CREATE POLICY p_teacher_assignments_admin ON teacher_assignments
    FOR ALL TO authenticated
    USING (is_admin())
    WITH CHECK (is_admin());

CREATE POLICY p_teacher_assignments_teacher_select ON teacher_assignments
    FOR SELECT TO authenticated
    USING (is_teacher() AND teacher_id = current_teacher_id() AND active = true);

-- -----------------------------------------------------------------------------
-- 5.11. students
-- Note: Teachers query students_for_teacher view. Direct table access is blocked.
-- -----------------------------------------------------------------------------
CREATE POLICY p_students_admin ON students
    FOR ALL TO authenticated
    USING (is_admin())
    WITH CHECK (is_admin());

CREATE POLICY p_students_student_select ON students
    FOR SELECT TO authenticated
    USING (is_student() AND id = current_student_id() AND deleted_at IS NULL);

-- -----------------------------------------------------------------------------
-- 5.12. fees
-- -----------------------------------------------------------------------------
CREATE POLICY p_fees_admin ON fees
    FOR ALL TO authenticated
    USING (is_admin())
    WITH CHECK (is_admin());

CREATE POLICY p_fees_student_select ON fees
    FOR SELECT TO authenticated
    USING (is_student() AND student_id = current_student_id() AND deleted_at IS NULL);

-- -----------------------------------------------------------------------------
-- 5.13. payments
-- Note: Students read payments through student_payments_view (which excludes remarks).
-- -----------------------------------------------------------------------------
CREATE POLICY p_payments_admin ON payments
    FOR ALL TO authenticated
    USING (is_admin())
    WITH CHECK (is_admin());

-- -----------------------------------------------------------------------------
-- 5.14. receipts
-- -----------------------------------------------------------------------------
CREATE POLICY p_receipts_admin ON receipts
    FOR ALL TO authenticated
    USING (is_admin())
    WITH CHECK (is_admin());

CREATE POLICY p_receipts_student_select ON receipts
    FOR SELECT TO authenticated
    USING (
        is_student()
        AND deleted_at IS NULL
        AND EXISTS (
            SELECT 1 FROM payments p
            WHERE p.id = receipts.payment_id
              AND p.student_id = current_student_id()
              AND p.deleted_at IS NULL
        )
    );

-- -----------------------------------------------------------------------------
-- 5.15. exams
-- -----------------------------------------------------------------------------
CREATE POLICY p_exams_admin ON exams
    FOR ALL TO authenticated
    USING (is_admin())
    WITH CHECK (is_admin());

CREATE POLICY p_exams_student_select ON exams
    FOR SELECT TO authenticated
    USING (
        is_student()
        AND status = 'published'
        AND deleted_at IS NULL
        AND EXISTS (
            SELECT 1 FROM results r
            WHERE r.exam_id = exams.id
              AND r.student_id = current_student_id()
              AND r.deleted_at IS NULL
        )
    );

-- -----------------------------------------------------------------------------
-- 5.16. exam_subjects
-- -----------------------------------------------------------------------------
CREATE POLICY p_exam_subjects_admin ON exam_subjects
    FOR ALL TO authenticated
    USING (is_admin())
    WITH CHECK (is_admin());

CREATE POLICY p_exam_subjects_student_select ON exam_subjects
    FOR SELECT TO authenticated
    USING (
        is_student()
        AND deleted_at IS NULL
        AND EXISTS (
            SELECT 1 FROM exams e
            WHERE e.id = exam_subjects.exam_id
              AND e.status = 'published'
              AND e.deleted_at IS NULL
        )
    );

-- -----------------------------------------------------------------------------
-- 5.17. marks
-- -----------------------------------------------------------------------------
CREATE POLICY p_marks_admin ON marks
    FOR ALL TO authenticated
    USING (is_admin())
    WITH CHECK (is_admin());

CREATE POLICY p_marks_student_select ON marks
    FOR SELECT TO authenticated
    USING (
        is_student()
        AND student_id = current_student_id()
        AND deleted_at IS NULL
        AND EXISTS (
            SELECT 1 FROM exams e
            WHERE e.id = marks.exam_id
              AND e.status = 'published'
              AND e.deleted_at IS NULL
        )
    );

-- -----------------------------------------------------------------------------
-- 5.18. results
-- -----------------------------------------------------------------------------
CREATE POLICY p_results_admin ON results
    FOR ALL TO authenticated
    USING (is_admin())
    WITH CHECK (is_admin());

CREATE POLICY p_results_student_select ON results
    FOR SELECT TO authenticated
    USING (
        is_student()
        AND student_id = current_student_id()
        AND deleted_at IS NULL
        AND EXISTS (
            SELECT 1 FROM exams e
            WHERE e.id = results.exam_id
              AND e.status = 'published'
              AND e.deleted_at IS NULL
        )
    );

-- -----------------------------------------------------------------------------
-- 5.19. attendance_sessions
-- -----------------------------------------------------------------------------
CREATE POLICY p_attendance_sessions_admin ON attendance_sessions
    FOR ALL TO authenticated
    USING (is_admin())
    WITH CHECK (is_admin());

CREATE POLICY p_attendance_sessions_teacher_select ON attendance_sessions
    FOR SELECT TO authenticated
    USING (
        is_teacher()
        AND (
            marked_by = current_teacher_id()
            OR teacher_has_assignment(batch_id, subject_id)
        )
    );

CREATE POLICY p_attendance_sessions_teacher_insert ON attendance_sessions
    FOR INSERT TO authenticated
    WITH CHECK (
        is_teacher()
        AND marked_by = current_teacher_id()
        AND status = 'draft'
        AND teacher_has_assignment(batch_id, subject_id)
    );

CREATE POLICY p_attendance_sessions_teacher_update ON attendance_sessions
    FOR UPDATE TO authenticated
    USING (
        is_teacher()
        AND marked_by = current_teacher_id()
        AND status = 'draft'
        AND teacher_has_assignment(batch_id, subject_id)
    )
    WITH CHECK (
        is_teacher()
        AND marked_by = current_teacher_id()
        AND status = 'draft'
        AND teacher_has_assignment(batch_id, subject_id)
    );

CREATE POLICY p_attendance_sessions_teacher_delete ON attendance_sessions
    FOR DELETE TO authenticated
    USING (
        is_teacher()
        AND marked_by = current_teacher_id()
        AND status = 'draft'
    );

CREATE POLICY p_attendance_sessions_student_select ON attendance_sessions
    FOR SELECT TO authenticated
    USING (
        is_student()
        AND status IN ('submitted', 'locked')
        AND EXISTS (
            SELECT 1 FROM attendance_records ar
            WHERE ar.session_id = attendance_sessions.id
              AND ar.student_id = current_student_id()
        )
    );

-- -----------------------------------------------------------------------------
-- 5.20. attendance_records
-- -----------------------------------------------------------------------------
CREATE POLICY p_attendance_records_admin ON attendance_records
    FOR ALL TO authenticated
    USING (is_admin())
    WITH CHECK (is_admin());

CREATE POLICY p_attendance_records_teacher_select ON attendance_records
    FOR SELECT TO authenticated
    USING (
        is_teacher()
        AND EXISTS (
            SELECT 1 FROM attendance_sessions s
            WHERE s.id = attendance_records.session_id
              AND (
                  s.marked_by = current_teacher_id()
                  OR teacher_has_assignment(s.batch_id, s.subject_id)
              )
        )
    );

CREATE POLICY p_attendance_records_teacher_insert ON attendance_records
    FOR INSERT TO authenticated
    WITH CHECK (
        is_teacher()
        AND EXISTS (
            SELECT 1 FROM attendance_sessions s
            WHERE s.id = attendance_records.session_id
              AND s.marked_by = current_teacher_id()
              AND s.status = 'draft'
              AND teacher_has_assignment(s.batch_id, s.subject_id)
        )
    );

CREATE POLICY p_attendance_records_teacher_update ON attendance_records
    FOR UPDATE TO authenticated
    USING (
        is_teacher()
        AND EXISTS (
            SELECT 1 FROM attendance_sessions s
            WHERE s.id = attendance_records.session_id
              AND s.marked_by = current_teacher_id()
              AND s.status = 'draft'
              AND teacher_has_assignment(s.batch_id, s.subject_id)
        )
    )
    WITH CHECK (
        is_teacher()
        AND EXISTS (
            SELECT 1 FROM attendance_sessions s
            WHERE s.id = attendance_records.session_id
              AND s.marked_by = current_teacher_id()
              AND s.status = 'draft'
              AND teacher_has_assignment(s.batch_id, s.subject_id)
        )
    );

CREATE POLICY p_attendance_records_teacher_delete ON attendance_records
    FOR DELETE TO authenticated
    USING (
        is_teacher()
        AND EXISTS (
            SELECT 1 FROM attendance_sessions s
            WHERE s.id = attendance_records.session_id
              AND s.marked_by = current_teacher_id()
              AND s.status = 'draft'
        )
    );

CREATE POLICY p_attendance_records_student_select ON attendance_records
    FOR SELECT TO authenticated
    USING (
        is_student()
        AND student_id = current_student_id()
        AND EXISTS (
            SELECT 1 FROM attendance_sessions s
            WHERE s.id = attendance_records.session_id
              AND s.status IN ('submitted', 'locked')
        )
    );

-- -----------------------------------------------------------------------------
-- 5.21. attendance_changes (INSERT-ONLY via correct_attendance, Admin SELECT)
-- -----------------------------------------------------------------------------
CREATE POLICY p_attendance_changes_admin_select ON attendance_changes
    FOR SELECT TO authenticated
    USING (is_admin());

-- -----------------------------------------------------------------------------
-- 5.22. audit_log (INSERT-ONLY via audit trigger, Admin SELECT)
-- -----------------------------------------------------------------------------
CREATE POLICY p_audit_log_admin_select ON audit_log
    FOR SELECT TO authenticated
    USING (is_admin());

-- -----------------------------------------------------------------------------
-- 5.23. document_templates
-- -----------------------------------------------------------------------------
CREATE POLICY p_document_templates_admin ON document_templates
    FOR ALL TO authenticated
    USING (is_admin())
    WITH CHECK (is_admin());

-- -----------------------------------------------------------------------------
-- 5.24. generated_documents
-- -----------------------------------------------------------------------------
CREATE POLICY p_generated_documents_admin ON generated_documents
    FOR ALL TO authenticated
    USING (is_admin())
    WITH CHECK (is_admin());

CREATE POLICY p_generated_documents_student_select ON generated_documents
    FOR SELECT TO authenticated
    USING (is_student() AND student_id = current_student_id() AND deleted_at IS NULL);

-- -----------------------------------------------------------------------------
-- 5.25. number_counters (Admin read-only, increments via next_number function)
-- -----------------------------------------------------------------------------
CREATE POLICY p_number_counters_admin_select ON number_counters
    FOR SELECT TO authenticated
    USING (is_admin());

-- -----------------------------------------------------------------------------
-- 5.26. notifications
-- -----------------------------------------------------------------------------
CREATE POLICY p_notifications_admin ON notifications
    FOR ALL TO authenticated
    USING (is_admin())
    WITH CHECK (is_admin());

CREATE POLICY p_notifications_user_select ON notifications
    FOR SELECT TO authenticated
    USING (user_id = auth.uid());

CREATE POLICY p_notifications_user_update ON notifications
    FOR UPDATE TO authenticated
    USING (user_id = auth.uid())
    WITH CHECK (user_id = auth.uid());

-- -----------------------------------------------------------------------------
-- 5.27. push_subscriptions
-- -----------------------------------------------------------------------------
CREATE POLICY p_push_subscriptions_admin ON push_subscriptions
    FOR ALL TO authenticated
    USING (is_admin())
    WITH CHECK (is_admin());

CREATE POLICY p_push_subscriptions_user ON push_subscriptions
    FOR ALL TO authenticated
    USING (user_id = auth.uid())
    WITH CHECK (user_id = auth.uid());
