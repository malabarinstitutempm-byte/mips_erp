-- =============================================================================
-- MIPS ERP Database Migration: 0015_accounts_overview.sql
-- Sub-phase 3E: Administrative Accounts Overview & Credential Governance
-- =============================================================================

CREATE OR REPLACE FUNCTION admin_get_accounts_overview()
RETURNS jsonb AS $$
DECLARE
    v_locked_accounts jsonb;
    v_unactivated_students jsonb;
    v_recent_resets jsonb;
BEGIN
    IF NOT is_admin() THEN
        RAISE EXCEPTION 'Access denied: Only administrators can view accounts overview.';
    END IF;

    -- 1. Locked Accounts across teachers and students
    SELECT coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb)
    INTO v_locked_accounts
    FROM (
        SELECT 
            p.user_id,
            p.role,
            p.failed_attempts,
            p.locked_at,
            p.last_login_at,
            p.active,
            CASE 
                WHEN p.role = 'teacher' THEN tch.name
                WHEN p.role = 'student' THEN stu.name
                ELSE 'Administrator'
            END AS name,
            CASE 
                WHEN p.role = 'teacher' THEN tch.login_username
                WHEN p.role = 'student' THEN coalesce(stu.registration_number, stu.admission_number)
                ELSE p.user_id::text
            END AS identifier,
            CASE 
                WHEN p.role = 'teacher' THEN tch.phone
                WHEN p.role = 'student' THEN stu.phone
                ELSE NULL
            END AS phone,
            coalesce(p.teacher_id, p.student_id) AS entity_id
        FROM profiles p
        LEFT JOIN teachers tch ON p.teacher_id = tch.id
        LEFT JOIN students stu ON p.student_id = stu.id
        WHERE (p.locked_at IS NOT NULL OR p.failed_attempts >= 5)
        ORDER BY p.locked_at DESC NULLS LAST
    ) t;

    -- 2. Students Not Yet Activated
    SELECT coalesce(jsonb_agg(to_jsonb(s)), '[]'::jsonb)
    INTO v_unactivated_students
    FROM (
        SELECT 
            stu.id,
            stu.name,
            stu.admission_number,
            stu.registration_number,
            stu.phone,
            stu.status,
            c.name AS course_name,
            stu.created_at
        FROM students stu
        LEFT JOIN profiles p ON p.student_id = stu.id
        LEFT JOIN courses c ON stu.course_id = c.id
        WHERE stu.deleted_at IS NULL
          AND stu.status = 'active'
          AND (p.user_id IS NULL OR (p.first_login_required = true AND p.last_login_at IS NULL))
        ORDER BY stu.created_at DESC
    ) s;

    -- 3. Recently Reset Passwords (zero secrets)
    SELECT coalesce(jsonb_agg(to_jsonb(r)), '[]'::jsonb)
    INTO v_recent_resets
    FROM (
        SELECT 
            al.id,
            al.action,
            al.actor,
            al.record_id AS target,
            al.created_at,
            al.new_data AS details
        FROM audit_log al
        WHERE al.action IN ('RESET_TEACHER_PASSWORD', 'RESET_STUDENT_PASSWORD')
        ORDER BY al.created_at DESC
        LIMIT 40
    ) r;

    RETURN jsonb_build_object(
        'locked_accounts', v_locked_accounts,
        'unactivated_students', v_unactivated_students,
        'recent_resets', v_recent_resets
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp;

GRANT EXECUTE ON FUNCTION admin_get_accounts_overview() TO authenticated, service_role;
