-- =============================================================================
-- MIPS ERP Database Migration: 0004_auth_functions.sql
-- Sub-phase 2A: Authentication Support, Lockout Tracking & Password Governance
-- =============================================================================

-- =============================================================================
-- 1. Account Lockout & Attempt Tracking Functions
-- =============================================================================

-- Check if an account is currently locked out
-- Lockout threshold: 5 failed attempts, 15 minutes lockout duration
CREATE OR REPLACE FUNCTION check_account_lockout(p_user_id uuid)
RETURNS jsonb AS $$
DECLARE
    v_profile profiles%ROWTYPE;
    v_lockout_duration_minutes int := 15;
    v_max_attempts int := 5;
    v_is_locked boolean := false;
    v_remaining_seconds int := 0;
BEGIN
    SELECT * INTO v_profile
    FROM profiles
    WHERE user_id = p_user_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'exists', false,
            'is_locked', false
        );
    END IF;

    IF NOT v_profile.active THEN
        RETURN jsonb_build_object(
            'exists', true,
            'is_locked', true,
            'reason', 'deactivated'
        );
    END IF;

    IF v_profile.locked_at IS NOT NULL THEN
        -- Check if lockout window has expired
        IF v_profile.locked_at > clock_timestamp() - (v_lockout_duration_minutes || ' minutes')::interval THEN
            v_is_locked := true;
            v_remaining_seconds := EXTRACT(EPOCH FROM (v_profile.locked_at + (v_lockout_duration_minutes || ' minutes')::interval - clock_timestamp()))::int;
        ELSE
            -- Lockout has expired; auto-clear lockout
            UPDATE profiles
            SET locked_at = NULL,
                failed_attempts = 0
            WHERE user_id = p_user_id;
            
            v_is_locked := false;
            v_remaining_seconds := 0;
        END IF;
    END IF;

    RETURN jsonb_build_object(
        'exists', true,
        'is_locked', v_is_locked,
        'failed_attempts', v_profile.failed_attempts,
        'remaining_seconds', GREATEST(0, v_remaining_seconds),
        'must_change_password', v_profile.must_change_password
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE
SET search_path = public, pg_temp;

-- Record a failed login attempt; locks account if threshold (5) is reached
CREATE OR REPLACE FUNCTION record_failed_login(p_user_id uuid)
RETURNS jsonb AS $$
DECLARE
    v_new_attempts int;
    v_locked_now boolean := false;
    v_max_attempts int := 5;
BEGIN
    UPDATE profiles
    SET failed_attempts = failed_attempts + 1,
        locked_at = CASE 
            WHEN failed_attempts + 1 >= v_max_attempts THEN clock_timestamp()
            ELSE locked_at
        END,
        updated_at = clock_timestamp()
    WHERE user_id = p_user_id
    RETURNING failed_attempts, (locked_at IS NOT NULL) INTO v_new_attempts, v_locked_now;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'error', 'Profile not found');
    END IF;

    -- Log critical lockout event if newly locked
    IF v_locked_now AND v_new_attempts = v_max_attempts THEN
        INSERT INTO audit_log (table_name, record_id, action, new_data, actor, created_at)
        VALUES (
            'profiles',
            p_user_id::text,
            'ACCOUNT_LOCKED',
            jsonb_build_object('user_id', p_user_id, 'reason', 'Excessive failed login attempts', 'attempts', v_new_attempts),
            p_user_id,
            clock_timestamp()
        );
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'failed_attempts', v_new_attempts,
        'is_locked', v_locked_now,
        'attempts_remaining', GREATEST(0, v_max_attempts - v_new_attempts)
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp;

-- Record a successful login: clears failed attempts and resets lock timestamp
CREATE OR REPLACE FUNCTION record_successful_login(p_user_id uuid)
RETURNS jsonb AS $$
BEGIN
    UPDATE profiles
    SET failed_attempts = 0,
        locked_at = NULL,
        updated_at = clock_timestamp()
    WHERE user_id = p_user_id;

    RETURN jsonb_build_object('success', true);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp;

-- Admin function: manually unlock a locked or deactivated account
CREATE OR REPLACE FUNCTION admin_unlock_account(p_target_user_id uuid)
RETURNS jsonb AS $$
BEGIN
    IF NOT is_admin() THEN
        RAISE EXCEPTION 'Access denied: Only administrators can unlock user accounts.';
    END IF;

    UPDATE profiles
    SET failed_attempts = 0,
        locked_at = NULL,
        active = true,
        updated_at = clock_timestamp()
    WHERE user_id = p_target_user_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'error', 'Target user profile not found');
    END IF;

    INSERT INTO audit_log (table_name, record_id, action, new_data, actor, created_at)
    VALUES (
        'profiles',
        p_target_user_id::text,
        'ADMIN_UNLOCK_ACCOUNT',
        jsonb_build_object('target_user_id', p_target_user_id, 'unlocked_by', auth.uid()),
        auth.uid(),
        clock_timestamp()
    );

    RETURN jsonb_build_object('success', true, 'message', 'Account successfully unlocked and reset.');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp;

-- Acknowledge password change (clears must_change_password flag)
CREATE OR REPLACE FUNCTION acknowledge_password_change()
RETURNS jsonb AS $$
DECLARE
    v_user_id uuid;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required.';
    END IF;

    UPDATE profiles
    SET must_change_password = false,
        updated_at = clock_timestamp()
    WHERE user_id = v_user_id;

    RETURN jsonb_build_object('success', true);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp;

-- =============================================================================
-- 2. Grant Executions to Roles
-- =============================================================================

GRANT EXECUTE ON FUNCTION check_account_lockout(uuid) TO authenticated, anon;
GRANT EXECUTE ON FUNCTION record_failed_login(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION record_successful_login(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION admin_unlock_account(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION acknowledge_password_change() TO authenticated;
