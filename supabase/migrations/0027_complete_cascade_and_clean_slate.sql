-- ============================================================================
-- Migration: 0027_complete_cascade_and_clean_slate.sql
-- Description:
--   1. Grant SELECT on public.profiles to anon so client queries don't fail with 401.
--   2. Implement robust cascade delete functions (Student, Batch, Course) that
--      purge attendance records, marks, fees, and enrollments completely.
--   3. Implement admin RPCs for direct, race-free single-call deletion & detail fetches.
--   4. Wipe ALL dummy data (students, teachers, courses, batches, attendance, marks, fees)
--      and preserve ONLY the single Super Admin account.
--   5. Reset all primary key auto-increment sequences so manually created items start clean from 1.
-- ============================================================================

-- 1. Grant SELECT on profiles to anon so client app never gets 401 permission denied
GRANT SELECT ON public.profiles TO anon, authenticated, service_role;

-- 2. Cascade Soft Delete Student Function
CREATE OR REPLACE FUNCTION public.cascade_soft_delete_student(
    p_id int,
    p_actor_id text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_adm text;
    v_reg text;
BEGIN
    SELECT lower(admission_number), lower(registration_number)
    INTO v_adm, v_reg
    FROM public.students
    WHERE id = p_id;

    -- A. Completely remove student from attendance records so they never appear on any attendance list
    DELETE FROM public.attendance_records
    WHERE student_id = p_id;

    -- B. Remove marks and results
    DELETE FROM public.marks
    WHERE student_id = p_id;

    DELETE FROM public.results
    WHERE student_id = p_id;

    -- C. Remove financial records
    DELETE FROM public.payment_allocations
    WHERE payment_id IN (SELECT id FROM public.payments WHERE student_id = p_id);

    DELETE FROM public.payments
    WHERE student_id = p_id;

    DELETE FROM public.fee_items
    WHERE fee_id IN (SELECT id FROM public.fees WHERE student_id = p_id);

    DELETE FROM public.fees
    WHERE student_id = p_id;

    -- D. Soft delete enrollments
    UPDATE public.student_enrollments
    SET deleted_at = coalesce(deleted_at, clock_timestamp()),
        deleted_by = coalesce(p_actor_id, auth.uid()::text),
        status = 'discontinued'::enrollment_status,
        updated_at = clock_timestamp()
    WHERE student_id = p_id
      AND deleted_at IS NULL;

    -- E. Soft delete student record
    UPDATE public.students
    SET deleted_at = coalesce(deleted_at, clock_timestamp()),
        deleted_by = coalesce(p_actor_id, auth.uid()::text),
        status = 'discontinued'::student_status,
        updated_at = clock_timestamp()
    WHERE id = p_id
      AND deleted_at IS NULL;

    -- F. Delete profile to revoke all portal access immediately
    DELETE FROM public.profiles
    WHERE student_id = p_id;

    -- G. Purge portal credentials
    DELETE FROM public.portal_credentials
    WHERE role = 'student' 
      AND (
          (v_adm IS NOT NULL AND lower(identifier) = v_adm)
          OR (v_reg IS NOT NULL AND lower(identifier) = v_reg)
      );

    -- H. Log to audit log
    INSERT INTO public.audit_log (
        action,
        table_name,
        record_id,
        actor_id,
        details,
        created_at
    ) VALUES (
        'CASCADE_DELETE_STUDENT',
        'students',
        p_id::text,
        coalesce(p_actor_id, 'admin'),
        jsonb_build_object('student_id', p_id, 'reason', 'Student and related records purged'),
        clock_timestamp()
    );
END;
$$;

-- 3. Cascade Soft Delete Batch Function
CREATE OR REPLACE FUNCTION public.cascade_soft_delete_batch(
    p_id int,
    p_actor_id text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    r_student RECORD;
BEGIN
    -- A. Cascade soft delete all students directly belonging to or enrolled in this batch
    FOR r_student IN
        SELECT DISTINCT id FROM public.students WHERE batch_id = p_id AND deleted_at IS NULL
        UNION
        SELECT DISTINCT student_id AS id FROM public.student_enrollments WHERE batch_id = p_id AND deleted_at IS NULL
    LOOP
        PERFORM public.cascade_soft_delete_student(r_student.id, p_actor_id);
    END LOOP;

    -- B. Soft delete batch record
    UPDATE public.batches
    SET deleted_at = coalesce(deleted_at, clock_timestamp()),
        status = 'archived'::batch_status,
        updated_at = clock_timestamp()
    WHERE id = p_id
      AND deleted_at IS NULL;

    -- C. Archive attendance sessions for this batch
    UPDATE public.attendance_sessions
    SET status = 'locked'::attendance_session_status,
        updated_at = clock_timestamp()
    WHERE batch_id = p_id;

    -- D. Log to audit log
    INSERT INTO public.audit_log (
        action,
        table_name,
        record_id,
        actor_id,
        details,
        created_at
    ) VALUES (
        'CASCADE_DELETE_BATCH',
        'batches',
        p_id::text,
        coalesce(p_actor_id, 'admin'),
        jsonb_build_object('batch_id', p_id, 'reason', 'Batch and enrolled students purged'),
        clock_timestamp()
    );
END;
$$;

-- 4. Cascade Soft Delete Course Function
CREATE OR REPLACE FUNCTION public.cascade_soft_delete_course(
    p_id int,
    p_actor_id text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    r_batch RECORD;
    r_student RECORD;
BEGIN
    -- A. Cascade delete all batches belonging to this course (which cascades to their students)
    FOR r_batch IN
        SELECT id FROM public.batches WHERE course_id = p_id AND deleted_at IS NULL
    LOOP
        PERFORM public.cascade_soft_delete_batch(r_batch.id, p_actor_id);
    END LOOP;

    -- B. Cascade delete any students directly assigned to this course (even without a batch)
    FOR r_student IN
        SELECT id FROM public.students WHERE course_id = p_id AND deleted_at IS NULL
    LOOP
        PERFORM public.cascade_soft_delete_student(r_student.id, p_actor_id);
    END LOOP;

    -- C. Soft delete course record
    UPDATE public.courses
    SET deleted_at = coalesce(deleted_at, clock_timestamp()),
        updated_at = clock_timestamp()
    WHERE id = p_id
      AND deleted_at IS NULL;

    -- D. Log to audit log
    INSERT INTO public.audit_log (
        action,
        table_name,
        record_id,
        actor_id,
        details,
        created_at
    ) VALUES (
        'CASCADE_DELETE_COURSE',
        'courses',
        p_id::text,
        coalesce(p_actor_id, 'admin'),
        jsonb_build_object('course_id', p_id, 'reason', 'Course, batches, and students purged'),
        clock_timestamp()
    );
END;
$$;

-- 5. Dedicated Admin Deletion RPCs
CREATE OR REPLACE FUNCTION public.admin_delete_student(
    p_student_id int,
    p_reason text DEFAULT 'Deleted by administrator'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    PERFORM public.cascade_soft_delete_student(p_student_id, 'admin');
    RETURN jsonb_build_object('success', true, 'student_id', p_student_id);
EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('success', false, 'error', SQLERRM);
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_delete_batch(
    p_batch_id int,
    p_reason text DEFAULT 'Deleted by administrator'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    PERFORM public.cascade_soft_delete_batch(p_batch_id, 'admin');
    RETURN jsonb_build_object('success', true, 'batch_id', p_batch_id);
EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('success', false, 'error', SQLERRM);
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_delete_course(
    p_course_id int,
    p_reason text DEFAULT 'Deleted by administrator'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    PERFORM public.cascade_soft_delete_course(p_course_id, 'admin');
    RETURN jsonb_build_object('success', true, 'course_id', p_course_id);
EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('success', false, 'error', SQLERRM);
END;
$$;

-- 6. Detail Fetch RPCs for Teacher and Student
CREATE OR REPLACE FUNCTION public.admin_get_teacher_by_id(p_teacher_id int)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_res jsonb;
BEGIN
    SELECT to_jsonb(t) INTO v_res
    FROM (
        SELECT 
            t.id,
            t.name,
            t.login_username,
            t.phone,
            t.status,
            t.created_at,
            t.updated_at,
            coalesce(p.active, (t.status = 'active')) AS profile_active,
            p.locked_at,
            p.failed_attempts,
            p.last_login_at,
            (SELECT count(*)::int FROM public.attendance_sessions a WHERE a.marked_by = t.id) as sessions_marked_count
        FROM public.teachers t
        LEFT JOIN public.profiles p ON p.teacher_id = t.id
        WHERE t.id = p_teacher_id
          AND t.deleted_at IS NULL
    ) t;

    RETURN v_res;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_get_student_by_id(p_student_id int)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_res jsonb;
BEGIN
    SELECT to_jsonb(s) INTO v_res
    FROM (
        SELECT 
            st.*,
            c.name AS course_name,
            b.batch_name
        FROM public.students st
        LEFT JOIN public.courses c ON c.id = st.course_id
        LEFT JOIN public.batches b ON b.id = st.batch_id
        WHERE st.id = p_student_id
          AND st.deleted_at IS NULL
    ) s;

    RETURN v_res;
END;
$$;

-- 7. Grant Permissions
GRANT EXECUTE ON FUNCTION public.cascade_soft_delete_student(int, text) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.cascade_soft_delete_batch(int, text) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.cascade_soft_delete_course(int, text) TO anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.admin_delete_student(int, text) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.admin_delete_batch(int, text) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.admin_delete_course(int, text) TO anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.admin_get_teacher_by_id(int) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.admin_get_student_by_id(int) TO anon, authenticated, service_role;

-- 8. CLEAN SLATE: Purge ALL dummy data across all operational tables
TRUNCATE TABLE
    public.attendance_changes,
    public.attendance_records,
    public.attendance_sessions,
    public.marks,
    public.results,
    public.published_results,
    public.payment_allocations,
    public.payments,
    public.receipts,
    public.fee_adjustments,
    public.fee_items,
    public.fees,
    public.daily_timetable_entries,
    public.daily_timetables,
    public.timetable_entries,
    public.timetables,
    public.student_period_attendance_summaries,
    public.student_enrollments,
    public.batch_periods,
    public.batches,
    public.course_subjects,
    public.courses,
    public.portal_credentials,
    public.notifications,
    public.push_subscriptions,
    public.students,
    public.teachers
RESTART IDENTITY CASCADE;

-- 9. Clean profiles and auth.users, preserving ONLY the Super Admin account
DELETE FROM public.profiles
WHERE role != 'admin' OR user_id != '00000000-0000-0000-0000-000000000001';

DELETE FROM auth.users
WHERE id != '00000000-0000-0000-0000-000000000001';

-- Ensure super admin profile exists and is active
INSERT INTO public.profiles (
    user_id,
    role,
    active,
    must_change_password,
    failed_attempts,
    first_login_required,
    created_at,
    updated_at
) VALUES (
    '00000000-0000-0000-0000-000000000001',
    'admin',
    true,
    false,
    0,
    false,
    clock_timestamp(),
    clock_timestamp()
)
ON CONFLICT (user_id) DO UPDATE SET
    role = 'admin',
    active = true,
    failed_attempts = 0,
    updated_at = clock_timestamp();
