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
BEGIN
    RETURN submit_attendance(
        p_batch_id,
        p_date,
        p_slot,
        '[]'::jsonb,
        true,
        p_reason
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
    v_anon_public_functions text[];
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

    -- 5. Check no functions in schema public are executable by anon or PUBLIC
    SELECT array_agg(DISTINCT p.proname::text)
    INTO v_anon_public_functions
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND (
          has_function_privilege('anon', p.oid, 'EXECUTE')
          OR has_function_privilege('public', p.oid, 'EXECUTE')
      );

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
        ),
        'anon_public_functions', jsonb_build_object(
            'status', CASE WHEN v_anon_public_functions IS NULL THEN 'PASS' ELSE 'FAIL' END,
            'violating_functions', coalesce(v_anon_public_functions, ARRAY[]::text[])
        )
    );

    RETURN v_result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp;

REVOKE ALL ON FUNCTION verify_security_rls_matrix() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION verify_security_rls_matrix() TO service_role;
