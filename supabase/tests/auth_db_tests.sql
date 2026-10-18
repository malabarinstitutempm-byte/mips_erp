-- =============================================================================
-- MIPS ERP Database Test Suite: auth_db_tests.sql
-- Sub-phase 2A: Verification of Database Additions, Lockout & Anti-Enumeration
-- =============================================================================

BEGIN;

DO $$
DECLARE
    v_metrics jsonb;
    v_test_hash text := encode(sha256('non_existent_user_12345'), 'hex');
    v_ip text := '192.168.1.100';
    v_is_adm boolean;
BEGIN
    RAISE NOTICE '=======================================================';
    RAISE NOTICE 'Starting Sub-Phase 2A Database & Security Test Suite...';
    RAISE NOTICE '=======================================================';

    -- -------------------------------------------------------------------------
    -- Test 1: Verify login_attempts records for unknown / non-existent user
    -- -------------------------------------------------------------------------
    RAISE NOTICE 'Test 1: Recording failures for unknown identifier (anti-enumeration)...';
    
    PERFORM record_login_attempt(v_test_hash, v_ip, false);
    PERFORM record_login_attempt(v_test_hash, v_ip, false);
    
    v_metrics := get_login_failure_metrics(v_test_hash, v_ip, 15);
    ASSERT (v_metrics ->> 'identifier_failures')::int = 2, 'Expected 2 identifier failures';
    ASSERT (v_metrics ->> 'requires_captcha')::boolean = false, 'Captcha should not be required at 2 failures';
    ASSERT (v_metrics ->> 'is_locked')::boolean = false, 'Account should not be locked at 2 failures';
    RAISE NOTICE '  [PASS] 2 failures tracked for non-existent identifier.';

    -- -------------------------------------------------------------------------
    -- Test 2: Trigger CAPTCHA threshold (3rd failure)
    -- -------------------------------------------------------------------------
    RAISE NOTICE 'Test 2: Triggering CAPTCHA threshold at 3 failures...';
    PERFORM record_login_attempt(v_test_hash, v_ip, false);

    v_metrics := get_login_failure_metrics(v_test_hash, v_ip, 15);
    ASSERT (v_metrics ->> 'identifier_failures')::int = 3, 'Expected 3 identifier failures';
    ASSERT (v_metrics ->> 'requires_captcha')::boolean = true, 'Captcha must be required at 3 failures';
    ASSERT (v_metrics ->> 'is_locked')::boolean = false, 'Account should not be locked at 3 failures';
    RAISE NOTICE '  [PASS] CAPTCHA requirement activated on 3rd failure.';

    -- -------------------------------------------------------------------------
    -- Test 3: Trigger Lockout threshold (5th failure)
    -- -------------------------------------------------------------------------
    RAISE NOTICE 'Test 3: Triggering Lockout threshold at 5 failures...';
    PERFORM record_login_attempt(v_test_hash, v_ip, false);
    PERFORM record_login_attempt(v_test_hash, v_ip, false);

    v_metrics := get_login_failure_metrics(v_test_hash, v_ip, 15);
    ASSERT (v_metrics ->> 'identifier_failures')::int = 5, 'Expected 5 identifier failures';
    ASSERT (v_metrics ->> 'is_locked')::boolean = true, 'Account must be locked at 5 failures';
    ASSERT (v_metrics ->> 'attempts_remaining')::int = 0, 'Zero attempts remaining';
    RAISE NOTICE '  [PASS] Lockout triggered identically for unknown identifier.';

    -- -------------------------------------------------------------------------
    -- Test 4: Verify audit_log immutability (No UPDATE or DELETE allowed)
    -- -------------------------------------------------------------------------
    RAISE NOTICE 'Test 4: Verifying audit_log immutability...';
    BEGIN
        DELETE FROM audit_log;
        RAISE EXCEPTION 'CRITICAL: DELETE on audit_log should have failed!';
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE '  [PASS] DELETE on audit_log successfully denied by Postgres.';
    END;

    -- -------------------------------------------------------------------------
    -- Test 5: Verify login_attempts immutability (No UPDATE or DELETE allowed)
    -- -------------------------------------------------------------------------
    RAISE NOTICE 'Test 5: Verifying login_attempts immutability...';
    BEGIN
        DELETE FROM login_attempts;
        RAISE EXCEPTION 'CRITICAL: DELETE on login_attempts should have failed!';
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE '  [PASS] DELETE on login_attempts successfully denied by Postgres.';
    END;

    -- -------------------------------------------------------------------------
    -- Test 6: Verify secret sanitization in log_admin_action()
    -- -------------------------------------------------------------------------
    RAISE NOTICE 'Test 6: Testing secret scrubbing in log_admin_action()...';
    PERFORM log_admin_action(
        'TEST_ACTION',
        'test_target_id',
        jsonb_build_object(
            'safe_key', 'safe_value',
            'password', 'SUPER_SECRET_PLAIN_TEXT',
            'temp_password', 'TEMP_SECRET_123',
            'service_key', 'SECRET_KEY_999'
        )
    );

    ASSERT NOT EXISTS (
        SELECT 1 FROM audit_log 
        WHERE record_id = 'test_target_id' 
          AND (new_data ? 'password' OR new_data ? 'temp_password' OR new_data ? 'service_key')
    ), 'CRITICAL: Secrets leaked into audit_log!';

    RAISE NOTICE '  [PASS] Secrets automatically stripped from audit_log payload.';

    RAISE NOTICE '=======================================================';
    RAISE NOTICE 'All Sub-Phase 2A Tests PASSED cleanly.';
    RAISE NOTICE '=======================================================';
END $$;

ROLLBACK;
