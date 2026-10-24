-- supabase/migrations/0026_cascade_deletes_and_portal_identity.sql
-- Cascade soft-delete for students/courses/batches, hide deleted students
-- from attendance lists, and expose portal identity RPCs for student & teacher portals.

-- =============================================================================
-- 1. Cascade Deletion Functions
-- =============================================================================

CREATE OR REPLACE FUNCTION public.cascade_soft_delete_student(p_id bigint)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_adm text;
    v_reg text;
BEGIN
    SELECT lower(admission_number), lower(registration_number)
    INTO v_adm, v_reg
    FROM public.students
    WHERE id = p_id;

    -- 1. Soft delete enrollments
    UPDATE public.student_enrollments
    SET deleted_at = coalesce(deleted_at, clock_timestamp()),
        deleted_by = auth.uid(),
        status = 'discontinued'::enrollment_status,
        updated_at = clock_timestamp()
    WHERE student_id = p_id
      AND deleted_at IS NULL;

    -- 2. Soft delete student record
    UPDATE public.students
    SET deleted_at = coalesce(deleted_at, clock_timestamp()),
        deleted_by = auth.uid(),
        status = 'discontinued'::student_status,
        updated_at = clock_timestamp()
    WHERE id = p_id
      AND deleted_at IS NULL;

    -- 3. Deactivate profile
    UPDATE public.profiles
    SET active = false,
        updated_at = clock_timestamp()
    WHERE student_id = p_id;

    -- 4. Purge portal credentials
    DELETE FROM public.portal_credentials
    WHERE role = 'student' 
      AND (
          (v_adm IS NOT NULL AND lower(identifier) = v_adm)
          OR (v_reg IS NOT NULL AND lower(identifier) = v_reg)
      );
END;
$$;

CREATE OR REPLACE FUNCTION public.cascade_soft_delete_batch(p_id bigint)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_sid bigint;
BEGIN
    -- Soft delete all enrolled students
    FOR v_sid IN
        SELECT DISTINCT sid FROM (
            SELECT s.id AS sid
            FROM public.students s
            WHERE s.batch_id = p_id AND s.deleted_at IS NULL
            UNION
            SELECT se.student_id AS sid
            FROM public.student_enrollments se
            WHERE se.batch_id = p_id AND se.deleted_at IS NULL
        ) q
    LOOP
        PERFORM public.cascade_soft_delete_student(v_sid);
    END LOOP;

    UPDATE public.student_enrollments
    SET deleted_at = coalesce(deleted_at, clock_timestamp()),
        deleted_by = auth.uid(),
        status = 'discontinued'::enrollment_status,
        updated_at = clock_timestamp()
    WHERE batch_id = p_id
      AND deleted_at IS NULL;

    UPDATE public.batches
    SET deleted_at = coalesce(deleted_at, clock_timestamp()),
        deleted_by = auth.uid(),
        updated_at = clock_timestamp()
    WHERE id = p_id
      AND deleted_at IS NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public.cascade_soft_delete_course(p_id bigint)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_bid bigint;
    v_sid bigint;
BEGIN
    -- Soft delete all students directly linked to this course
    FOR v_sid IN
        SELECT DISTINCT sid FROM (
            SELECT s.id AS sid
            FROM public.students s
            WHERE s.course_id = p_id AND s.deleted_at IS NULL
            UNION
            SELECT se.student_id AS sid
            FROM public.student_enrollments se
            WHERE se.course_id = p_id AND se.deleted_at IS NULL
        ) q
    LOOP
        PERFORM public.cascade_soft_delete_student(v_sid);
    END LOOP;

    -- Soft delete all batches in this course
    FOR v_bid IN
        SELECT b.id FROM public.batches b
        WHERE b.course_id = p_id AND b.deleted_at IS NULL
    LOOP
        PERFORM public.cascade_soft_delete_batch(v_bid);
    END LOOP;

    UPDATE public.courses
    SET deleted_at = coalesce(deleted_at, clock_timestamp()),
        deleted_by = auth.uid(),
        updated_at = clock_timestamp()
    WHERE id = p_id
      AND deleted_at IS NULL;
END;
$$;

-- Dedicated Admin RPCs
CREATE OR REPLACE FUNCTION public.admin_delete_student(
    p_student_id bigint,
    p_reason text DEFAULT 'Deleted by administrator'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    PERFORM public.cascade_soft_delete_student(p_student_id);
    RETURN jsonb_build_object('success', true, 'table', 'students', 'id', p_student_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_delete_batch(
    p_batch_id bigint,
    p_reason text DEFAULT 'Deleted by administrator'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    PERFORM public.cascade_soft_delete_batch(p_batch_id);
    RETURN jsonb_build_object('success', true, 'table', 'batches', 'id', p_batch_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_delete_course(
    p_course_id bigint,
    p_reason text DEFAULT 'Deleted by administrator'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    PERFORM public.cascade_soft_delete_course(p_course_id);
    RETURN jsonb_build_object('success', true, 'table', 'courses', 'id', p_course_id);
END;
$$;

-- Generic soft_delete RPC
CREATE OR REPLACE FUNCTION public.soft_delete(
    p_table text,
    p_id bigint,
    p_reason text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_forbidden_tables text[] := ARRAY[
        'payments', 'receipts', 'fees', 'marks', 'results', 'exam_subjects'
    ];
    v_allowed_tables text[] := ARRAY[
        'courses', 'course_subjects', 'batches', 'students',
        'exams', 'teachers', 'academic_years', 'universities',
        'document_templates', 'generated_documents'
    ];
    v_table text;
    v_rows int;
BEGIN
    v_table := lower(trim(p_table));

    IF v_table = ANY(v_forbidden_tables) THEN
        RAISE EXCEPTION 'Table "%" cannot be soft deleted. Direct soft deletion of financial and academic records is forbidden.', v_table;
    END IF;

    IF NOT (v_table = ANY(v_allowed_tables)) THEN
        RAISE EXCEPTION 'Invalid table "%" specified for soft delete.', p_table;
    END IF;

    IF v_table = 'students' THEN
        PERFORM public.cascade_soft_delete_student(p_id);
        GET DIAGNOSTICS v_rows = ROW_COUNT;
    ELSIF v_table = 'batches' THEN
        PERFORM public.cascade_soft_delete_batch(p_id);
        GET DIAGNOSTICS v_rows = ROW_COUNT;
    ELSIF v_table = 'courses' THEN
        PERFORM public.cascade_soft_delete_course(p_id);
        GET DIAGNOSTICS v_rows = ROW_COUNT;
    ELSE
        EXECUTE format(
            'UPDATE %I SET deleted_at = clock_timestamp(), deleted_by = %L, updated_at = clock_timestamp() ' ||
            'WHERE id = %L AND deleted_at IS NULL',
            v_table, auth.uid(), p_id
        );
        GET DIAGNOSTICS v_rows = ROW_COUNT;
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'table', v_table,
        'id', p_id,
        'action', 'soft_delete',
        'reason', p_reason
    );
END;
$$;

-- =============================================================================
-- 2. students_for_teacher View
-- =============================================================================

DROP VIEW IF EXISTS public.students_for_teacher CASCADE;
CREATE OR REPLACE VIEW public.students_for_teacher
WITH (security_barrier = true)
AS
SELECT
    s.id,
    s.name,
    s.registration_number,
    s.admission_number,
    s.batch_id,
    b.batch_name AS batch
FROM public.students s
JOIN public.batches b ON b.id = s.batch_id
JOIN public.courses c ON c.id = b.course_id
WHERE s.deleted_at IS NULL
  AND s.status = 'active'
  AND b.deleted_at IS NULL
  AND b.status = 'active'
  AND c.deleted_at IS NULL;

-- =============================================================================
-- 3. Portal Identity & Batch Attendance RPCs (Security Definer for anon)
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_portal_student_overview(p_student_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_profile jsonb;
    v_enrollments jsonb;
BEGIN
    IF p_student_id IS NULL THEN
        RETURN jsonb_build_object('error', 'Student profile not found');
    END IF;

    SELECT jsonb_build_object(
        'id', s.id,
        'admission_number', s.admission_number,
        'registration_number', s.registration_number,
        'name', s.name,
        'dob', s.dob,
        'gender', s.gender,
        'phone', s.phone,
        'email', s.email,
        'status', s.status,
        'completed_on', s.completed_on,
        'course_id', s.course_id,
        'course_name', c.name,
        'batch_id', s.batch_id,
        'batch_name', b.batch_name,
        'batch_status', b.status
    ) INTO v_profile
    FROM public.students s
    LEFT JOIN public.courses c ON c.id = s.course_id
    LEFT JOIN public.batches b ON b.id = s.batch_id
    WHERE s.id = p_student_id
      AND s.deleted_at IS NULL;

    IF v_profile IS NULL THEN
        RETURN jsonb_build_object('error', 'Student profile not found');
    END IF;

    SELECT coalesce(jsonb_agg(to_jsonb(e)), '[]'::jsonb) INTO v_enrollments
    FROM (
        SELECT
            se.id as enrollment_id,
            se.course_id,
            c.name as course_name,
            c.code as course_code,
            se.kind as course_type,
            c.structure as course_structure,
            c.attendance_basis,
            se.batch_id,
            b.batch_name,
            se.status,
            se.completed_on,
            b.current_semester,
            b.current_year
        FROM public.student_enrollments se
        JOIN public.courses c ON c.id = se.course_id
        JOIN public.batches b ON b.id = se.batch_id
        WHERE se.student_id = p_student_id
          AND se.deleted_at IS NULL
          AND c.deleted_at IS NULL
          AND b.deleted_at IS NULL
    ) e;

    RETURN jsonb_build_object(
        'profile', v_profile,
        'enrollments', v_enrollments
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.get_portal_teacher_profile(p_teacher_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_row record;
BEGIN
    SELECT t.id, t.name, t.login_username, t.phone, t.status
    INTO v_row
    FROM public.teachers t
    WHERE t.id = p_teacher_id
      AND t.deleted_at IS NULL;

    IF v_row.id IS NULL THEN
        RETURN jsonb_build_object('error', 'Teacher profile not found');
    END IF;

    RETURN jsonb_build_object(
        'id', v_row.id,
        'name', v_row.name,
        'login_username', v_row.login_username,
        'phone', v_row.phone,
        'status', coalesce(v_row.status, 'active')
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.get_portal_batch_students(p_batch_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_students jsonb;
BEGIN
    SELECT coalesce(jsonb_agg(to_jsonb(s) ORDER BY s.name), '[]'::jsonb)
    INTO v_students
    FROM (
        SELECT DISTINCT
            st.id,
            st.name,
            st.registration_number,
            st.admission_number
        FROM public.students st
        WHERE st.batch_id = p_batch_id
          AND st.deleted_at IS NULL
          AND st.status = 'active'
        UNION
        SELECT DISTINCT
            st.id,
            st.name,
            st.registration_number,
            st.admission_number
        FROM public.students st
        JOIN public.student_enrollments se
          ON se.student_id = st.id
         AND se.batch_id = p_batch_id
         AND se.deleted_at IS NULL
         AND se.status = 'active'
        WHERE st.deleted_at IS NULL
          AND st.status = 'active'
    ) s;

    RETURN coalesce(v_students, '[]'::jsonb);
END;
$$;

-- =============================================================================
-- 4. Permissions
-- =============================================================================

GRANT EXECUTE ON FUNCTION public.cascade_soft_delete_student(bigint) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.cascade_soft_delete_batch(bigint) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.cascade_soft_delete_course(bigint) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.admin_delete_student(bigint, text) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.admin_delete_batch(bigint, text) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.admin_delete_course(bigint, text) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.soft_delete(text, bigint, text) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_portal_student_overview(bigint) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_portal_teacher_profile(bigint) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_portal_batch_students(bigint) TO anon, authenticated, service_role;
GRANT SELECT ON public.students_for_teacher TO anon, authenticated, service_role;
