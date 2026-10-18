-- =============================================================================
-- MIPS ERP Database Migration: 0011_security_hardening.sql
-- Phase 7A: Security Audit Hardening, RLS Lockdown & Policy Enforcement
-- =============================================================================

-- =============================================================================
-- 1. Eliminate Profile Privilege Escalation (Fix Critical Finding 1)
-- =============================================================================
-- Drop policy allowing authenticated users to update their own profile row.
-- Prevents unauthorized users from updating their role to 'admin' or changing student_id/active/locked_at.
DROP POLICY IF EXISTS p_profiles_self_update ON profiles;

-- =============================================================================
-- 2. Safe Admin Profile Lookup by Email (Fix High Finding 3)
-- =============================================================================
-- Resolves user profiles strictly by exact matching auth.users email.
-- Restricts lookup strictly to the service_role to avoid arbitrary email probing.
CREATE OR REPLACE FUNCTION get_profile_by_email(p_email text)
RETURNS TABLE (
    user_id uuid,
    role user_role,
    active boolean,
    locked_at timestamptz,
    failed_attempts int
) AS $$
BEGIN
    RETURN QUERY
    SELECT p.user_id, p.role, p.active, p.locked_at, p.failed_attempts
    FROM auth.users u
    JOIN profiles p ON p.user_id = u.id
    WHERE lower(u.email) = lower(trim(p_email))
    LIMIT 1;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, auth, pg_temp;

REVOKE ALL ON FUNCTION get_profile_by_email(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION get_profile_by_email(text) TO service_role;

-- =============================================================================
-- 3. Revoke Dangerous Auth Function Execution (Fix High Finding 5 & Medium 6)
-- =============================================================================
-- Prevent authenticated users from resetting lockouts on arbitrary target user accounts
REVOKE EXECUTE ON FUNCTION record_successful_login(uuid) FROM authenticated;
GRANT EXECUTE ON FUNCTION record_successful_login(uuid) TO service_role;

-- Prevent anon from probing UUIDs for account existence and lock status
REVOKE EXECUTE ON FUNCTION check_account_lockout(uuid) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION check_account_lockout(uuid) TO service_role;

-- =============================================================================
-- 4. Harden confirm_no_class Attendance Authorization (Fix High Finding 4)
-- =============================================================================
-- 1. Verifies that non-admin teachers have an active assignment to the batch.
-- 2. Strictly prevents teachers from overwriting submitted/locked attendance sessions.
CREATE OR REPLACE FUNCTION confirm_no_class(
    p_batch_id bigint,
    p_date date,
    p_slot attendance_slot,
    p_reason text DEFAULT 'Confirmed no class'
)
RETURNS jsonb AS $$
DECLARE
    v_session_id bigint;
    v_existing attendance_sessions%ROWTYPE;
BEGIN
    IF NOT is_admin() AND NOT is_teacher() THEN
        RAISE EXCEPTION 'Access denied. Administrator or assigned teacher privilege required.';
    END IF;

    -- Verify batch exists
    IF NOT EXISTS (SELECT 1 FROM batches WHERE id = p_batch_id AND deleted_at IS NULL) THEN
        RAISE EXCEPTION 'Active batch ID % not found.', p_batch_id;
    END IF;

    -- Enforce teacher assignment validation
    IF is_teacher() AND NOT is_admin() THEN
        IF NOT EXISTS (
            SELECT 1 FROM teacher_assignments
            WHERE teacher_id = current_teacher_id()
              AND batch_id = p_batch_id
              AND active = true
        ) THEN
            RAISE EXCEPTION 'Access denied: You are not assigned to Batch ID %.', p_batch_id;
        END IF;
    END IF;

    -- Check if session already exists and is submitted/locked
    SELECT * INTO v_existing
    FROM attendance_sessions
    WHERE batch_id = p_batch_id AND date = p_date AND slot = p_slot;

    IF FOUND THEN
        IF is_teacher() AND NOT is_admin() AND v_existing.status IN ('submitted', 'locked') THEN
            RAISE EXCEPTION 'Cannot declare no-class: Session for % slot % is already % and locked.', p_date, p_slot, v_existing.status;
        END IF;
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

    -- Structured Audit Logging
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

-- =============================================================================
-- 5. Automated Security Access Matrix Verification Function
-- =============================================================================
-- Runs an automated verification of RLS configurations, policy rules, and function safety.
CREATE OR REPLACE FUNCTION verify_security_rls_matrix()
RETURNS jsonb AS $$
DECLARE
    v_unprotected_tables text[];
    v_anon_policies text[];
    v_definer_without_searchpath text[];
    v_audit_update_delete_count int;
    v_result jsonb;
BEGIN
    -- 1. Check all public user tables have row security enabled
    SELECT array_agg(relname::text)
    INTO v_unprotected_tables
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relkind = 'r'
      AND c.relrowsecurity = false;

    -- 2. Check no policies grant access to anon or PUBLIC
    SELECT array_agg(format('%s.%s (%s)', schemaname, tablename, policyname))
    INTO v_anon_policies
    FROM pg_policies
    WHERE schemaname = 'public'
      AND ('anon' = ANY(roles) OR 'public' = ANY(roles));

    -- 3. Check all SECURITY DEFINER functions have a search_path set
    SELECT array_agg(p.proname::text)
    INTO v_definer_without_searchpath
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.prosecdef = true
      AND (p.proconfig IS NULL OR NOT EXISTS (
          SELECT 1 FROM unnest(p.proconfig) cfg WHERE cfg LIKE 'search_path=%'
      ));

    -- 4. Check audit_log and attendance_changes have zero UPDATE/DELETE grants
    SELECT COUNT(*)
    INTO v_audit_update_delete_count
    FROM information_schema.table_privileges
    WHERE table_schema = 'public'
      AND table_name IN ('audit_log', 'attendance_changes')
      AND privilege_type IN ('UPDATE', 'DELETE')
      AND grantee IN ('anon', 'authenticated', 'PUBLIC');

    v_result := jsonb_build_object(
        'timestamp', clock_timestamp(),
        'rls_coverage', jsonb_build_object(
            'status', CASE WHEN v_unprotected_tables IS NULL THEN 'PASS' ELSE 'FAIL' END,
            'unprotected_tables', coalesce(v_unprotected_tables, ARRAY[]::text[])
        ),
        'anon_policy_isolation', jsonb_build_object(
            'status', CASE WHEN v_anon_policies IS NULL THEN 'PASS' ELSE 'FAIL' END,
            'violating_policies', coalesce(v_anon_policies, ARRAY[]::text[])
        ),
        'security_definer_search_path', jsonb_build_object(
            'status', CASE WHEN v_definer_without_searchpath IS NULL THEN 'PASS' ELSE 'FAIL' END,
            'violating_routines', coalesce(v_definer_without_searchpath, ARRAY[]::text[])
        ),
        'audit_immutability', jsonb_build_object(
            'status', CASE WHEN v_audit_update_delete_count = 0 THEN 'PASS' ELSE 'FAIL' END,
            'violations_count', v_audit_update_delete_count
        )
    );

    RETURN v_result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp;

REVOKE ALL ON FUNCTION verify_security_rls_matrix() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION verify_security_rls_matrix() TO service_role;
