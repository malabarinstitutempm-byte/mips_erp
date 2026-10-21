-- supabase/migrations/0023_edge_functions_and_push_optimization.sql
-- Phase O4 Optimization: RPC replacements for Edge Functions, Login Consolidation & Push Batch Helpers

-- 0. Relax audit_log action check constraint to allow custom admin events (e.g., UNLOCK_ACCOUNT)
ALTER TABLE public.audit_log DROP CONSTRAINT IF EXISTS audit_log_action_check;

-- 1. Direct Admin Unlock Account RPC (Replaces unlock-account Edge Function)
CREATE OR REPLACE FUNCTION public.admin_unlock_account(
    p_user_id uuid DEFAULT NULL,
    p_identifier text DEFAULT NULL,
    p_role text DEFAULT NULL
)
RETURNS jsonb AS $$
DECLARE
    v_admin_id uuid := (SELECT auth.uid());
    v_target_user_id uuid := p_user_id;
    v_prof RECORD;
    v_clean text;
BEGIN
    IF NOT (SELECT public.is_admin()) THEN
        RAISE EXCEPTION 'Access denied. Administrator privileges required.';
    END IF;

    -- Resolve user_id if identifier was passed
    IF v_target_user_id IS NULL AND p_identifier IS NOT NULL THEN
        v_clean := lower(trim(p_identifier));
        IF p_role = 'teacher' THEN
            SELECT p.user_id INTO v_target_user_id
            FROM public.teachers t
            JOIN public.profiles p ON p.teacher_id = t.id
            WHERE lower(t.login_username) = v_clean
            LIMIT 1;
        ELSIF p_role = 'student' THEN
            SELECT p.user_id INTO v_target_user_id
            FROM public.students s
            JOIN public.profiles p ON p.student_id = s.id
            WHERE lower(s.registration_number) = v_clean OR lower(s.admission_number) = v_clean
            LIMIT 1;
        ELSE
            SELECT p.user_id INTO v_target_user_id
            FROM public.profiles p
            WHERE p.email ILIKE v_clean
            LIMIT 1;
        END IF;
    END IF;

    IF v_target_user_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'Target user not found.');
    END IF;

    SELECT * INTO v_prof
    FROM public.profiles
    WHERE user_id = v_target_user_id;

    IF v_prof.user_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'Profile not found.');
    END IF;

    -- Reset lockout state atomically
    UPDATE public.profiles
    SET failed_attempts = 0,
        locked_at = NULL,
        active = true,
        updated_at = clock_timestamp()
    WHERE user_id = v_target_user_id;

    -- Audit log
    PERFORM public.log_admin_action(
        'UNLOCK_ACCOUNT',
        v_target_user_id::text,
        jsonb_build_object(
            'target_user_id', v_target_user_id,
            'role', v_prof.role,
            'previous_failed_attempts', v_prof.failed_attempts,
            'was_locked', v_prof.locked_at IS NOT NULL
        )
    );

    RETURN jsonb_build_object(
        'success', true,
        'message', 'Account successfully unlocked and failure counters reset.',
        'user_id', v_target_user_id,
        'role', v_prof.role
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- 2. Atomic Login Success Helper (Combines attempt logging + counter reset into 1 SQL call)
CREATE OR REPLACE FUNCTION public.record_login_success(
    p_user_id uuid,
    p_identifier_hash text,
    p_ip text
)
RETURNS void AS $$
BEGIN
    -- Reset profile counters
    UPDATE public.profiles
    SET failed_attempts = 0,
        locked_at = NULL,
        last_login_at = clock_timestamp()
    WHERE user_id = p_user_id;

    -- Record login attempt
    INSERT INTO public.login_attempts (
        identifier_hash,
        ip,
        success,
        attempted_at
    ) VALUES (
        p_identifier_hash,
        p_ip,
        true,
        clock_timestamp()
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- 3. Batch Push Query Helper with Endpoint Health Filter
CREATE OR REPLACE FUNCTION public.get_batch_push_subscriptions(
    p_user_ids uuid[]
)
RETURNS TABLE (
    user_id uuid,
    endpoint text,
    p256dh text,
    auth text
) AS $$
BEGIN
    RETURN QUERY
    SELECT DISTINCT ON (ps.user_id) 
        ps.user_id,
        ps.endpoint,
        ps.p256dh,
        ps.auth
    FROM public.push_subscriptions ps
    WHERE ps.user_id = ANY(p_user_ids)
    ORDER BY ps.user_id, ps.created_at DESC;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;

-- 4. Automatic Pruning of Dead Endpoints Helper
CREATE OR REPLACE FUNCTION public.prune_dead_push_endpoints(
    p_endpoints text[]
)
RETURNS int AS $$
DECLARE
    v_deleted int := 0;
BEGIN
    IF p_endpoints IS NULL OR array_length(p_endpoints, 1) = 0 THEN
        RETURN 0;
    END IF;

    DELETE FROM public.push_subscriptions
    WHERE endpoint = ANY(p_endpoints);

    GET DIAGNOSTICS v_deleted = ROW_COUNT;
    RETURN v_deleted;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- Permissions
REVOKE EXECUTE ON FUNCTION public.admin_unlock_account(uuid, text, text) FROM anon, PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_unlock_account(uuid, text, text) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.record_login_success(uuid, text, text) FROM anon, PUBLIC;
GRANT EXECUTE ON FUNCTION public.record_login_success(uuid, text, text) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.get_batch_push_subscriptions(uuid[]) FROM anon, PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_batch_push_subscriptions(uuid[]) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.prune_dead_push_endpoints(text[]) FROM anon, PUBLIC;
GRANT EXECUTE ON FUNCTION public.prune_dead_push_endpoints(text[]) TO authenticated;
