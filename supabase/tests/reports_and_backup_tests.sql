-- =============================================================================
-- Test Suite: reports_and_backup_tests.sql
-- Description: Unit and security tests for 0007_reports_and_backup.sql
-- =============================================================================

BEGIN;
SELECT plan(10);

-- 1. Setup mock admin profile
DO $$
DECLARE
    v_admin_id uuid := 'a0000000-0000-0000-0000-000000000001'::uuid;
BEGIN
    INSERT INTO auth.users (id, email)
    VALUES (v_admin_id, 'admin_report_test@mips.invalid')
    ON CONFLICT (id) DO NOTHING;

    INSERT INTO profiles (id, full_name, email, role, active)
    VALUES (v_admin_id, 'Report Admin Tester', 'admin_report_test@mips.invalid', 'admin', true)
    ON CONFLICT (id) DO UPDATE SET role = 'admin', active = true;
END $$;

-- Switch to admin context
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub": "a0000000-0000-0000-0000-000000000001", "role": "authenticated"}', true);

-- Test 1: Views exist
SELECT has_view('view_course_financial_summary', 'view_course_financial_summary exists');
SELECT has_view('view_fee_defaulters', 'view_fee_defaulters exists');
SELECT has_view('view_merit_list', 'view_merit_list exists');
SELECT has_view('view_fee_collection_daily', 'view_fee_collection_daily exists');

-- Test 2: report_fee_collection RPC exists and executes
SELECT has_function('report_fee_collection', ARRAY['date', 'date', 'text'], 'report_fee_collection RPC exists');

-- Test 3: report_course_revenue RPC exists and executes
SELECT has_function('report_course_revenue', 'report_course_revenue RPC exists');

-- Test 4: report_defaulters RPC exists
SELECT has_function('report_defaulters', ARRAY['bigint', 'bigint'], 'report_defaulters RPC exists');

-- Test 5: report_merit_list RPC exists
SELECT has_function('report_merit_list', ARRAY['bigint', 'bigint', 'bigint'], 'report_merit_list RPC exists');

-- Test 6: export_database_dump RPC returns valid JSON
SELECT ok(
    (export_database_dump()->'meta'->>'app') = 'MIPS ERP',
    'export_database_dump returns valid JSON with MIPS ERP metadata'
);

-- Test 7: Non-admin caller receives permission denied
DO $$
DECLARE
    v_student_id uuid := 'b0000000-0000-0000-0000-000000000002'::uuid;
BEGIN
    INSERT INTO auth.users (id, email)
    VALUES (v_student_id, 'student_report_test@mips.invalid')
    ON CONFLICT (id) DO NOTHING;

    INSERT INTO profiles (id, full_name, email, role, active)
    VALUES (v_student_id, 'Student Tester', 'student_report_test@mips.invalid', 'student', true)
    ON CONFLICT (id) DO UPDATE SET role = 'student', active = true;
END $$;

SELECT set_config('request.jwt.claims', '{"sub": "b0000000-0000-0000-0000-000000000002", "role": "authenticated"}', true);

SELECT throws_ok(
    'SELECT export_database_dump()',
    'Access denied. Administrator privilege required to export database dump.',
    'Non-admin cannot export cloud database dump'
);

SELECT * FROM finish();
ROLLBACK;
