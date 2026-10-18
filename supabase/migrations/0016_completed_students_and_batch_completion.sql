-- =============================================================================
-- Migration: 0016_completed_students_and_batch_completion.sql
-- Description: Phase 9A & 9E:
--   1. Add 'completed' to student_status and enrollment_status enums
--   2. Add completed_on to students, student_enrollments, and batches
--   3. Add status and audit trigger to batches table
--   4. Add profiles.access_until and completed_access_months setting (Phase 9E)
--   5. Function complete_student() and reopen_student()
--   6. Function preview_batch_completion(), complete_batch(), and reopen_batch()
--   7. Attendance rules: submit_attendance & students_for_teacher ignore completed
--   8. Notification audience rules: fee_defaulters includes completed students
--   9. Reports & Dashboard views: completed students with pending fees & status filters
--  10. Phase 9E Access Window helpers: student_access_allowed(), close_login, extend_access
-- =============================================================================

BEGIN;

-- =============================================================================
-- 1. Enum Types & Columns Evolution
-- =============================================================================

-- 1.1. Add 'completed' to student_status
DO $$ BEGIN
    ALTER TYPE student_status ADD VALUE IF NOT EXISTS 'completed';
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

-- 1.2. Add 'completed' to enrollment_status
DO $$ BEGIN
    ALTER TYPE enrollment_status ADD VALUE IF NOT EXISTS 'completed';
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

-- 1.3. Add completed_on to students
ALTER TABLE students 
    ADD COLUMN IF NOT EXISTS completed_on date;

-- 1.4. Add completed_on to student_enrollments
ALTER TABLE student_enrollments 
    ADD COLUMN IF NOT EXISTS completed_on date;

-- 1.5. Add status & completed_on to batches
ALTER TABLE batches 
    ADD COLUMN IF NOT EXISTS status text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'completed')),
    ADD COLUMN IF NOT EXISTS completed_on date;

-- 1.6. Add access_until to profiles (Phase 9E)
ALTER TABLE profiles 
    ADD COLUMN IF NOT EXISTS access_until date;

-- 1.7. Institutional Setting: completed_access_months (Default: 3 months)
INSERT INTO settings (key, value, description)
VALUES ('completed_access_months', '3', 'Number of months completed students retain read-only login access')
ON CONFLICT (key) DO UPDATE
SET description = EXCLUDED.description;

-- 1.8. Add Audit Triggers to batches and students
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_audit_batches') THEN
        CREATE TRIGGER trg_audit_batches
        AFTER INSERT OR UPDATE OR DELETE ON batches
        FOR EACH ROW EXECUTE FUNCTION audit_log_trigger();
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_audit_students') THEN
        CREATE TRIGGER trg_audit_students
        AFTER INSERT OR UPDATE OR DELETE ON students
        FOR EACH ROW EXECUTE FUNCTION audit_log_trigger();
    END IF;
END $$;

-- 1.9. Data Migration: convert any existing passed_out rows to completed
UPDATE students 
SET status = 'completed'::student_status 
WHERE status::text = 'passed_out';

UPDATE student_enrollments se
SET status = 'completed'::enrollment_status,
    completed_on = coalesce(s.completed_on, CURRENT_DATE)
FROM students s
WHERE se.student_id = s.id 
  AND s.status::text = 'completed'
  AND se.status::text = 'active';

COMMIT;

-- =============================================================================
-- 2. Multi-Enrollment Status Synchronization Engine
-- =============================================================================

CREATE OR REPLACE FUNCTION sync_student_completion_status(p_student_id bigint)
RETURNS text AS $$
DECLARE
    v_active_count int := 0;
    v_completed_count int := 0;
    v_latest_completed_on date;
    v_access_months int := 3;
    v_access_months_str text;
    v_user_id uuid;
    v_new_status text;
BEGIN
    -- Count enrollments
    SELECT 
        count(*) FILTER (WHERE status = 'active' AND deleted_at IS NULL),
        count(*) FILTER (WHERE status = 'completed' AND deleted_at IS NULL),
        max(completed_on) FILTER (WHERE status = 'completed' AND deleted_at IS NULL)
    INTO 
        v_active_count,
        v_completed_count,
        v_latest_completed_on
    FROM student_enrollments
    WHERE student_id = p_student_id;

    -- Fetch user profile ID
    SELECT user_id INTO v_user_id
    FROM profiles
    WHERE student_id = p_student_id;

    -- Fetch completed_access_months setting
    SELECT value INTO v_access_months_str FROM settings WHERE key = 'completed_access_months';
    IF v_access_months_str IS NOT NULL AND v_access_months_str ~ '^\d+$' THEN
        v_access_months := v_access_months_str::int;
    END IF;

    IF v_active_count > 0 THEN
        -- At least one enrollment is active: overall status is active
        v_new_status := 'active';
        UPDATE students 
        SET status = 'active'::student_status,
            completed_on = NULL,
            updated_at = clock_timestamp()
        WHERE id = p_student_id;

        IF v_user_id IS NOT NULL THEN
            UPDATE profiles
            SET access_until = NULL,
                active = true,
                updated_at = clock_timestamp()
            WHERE user_id = v_user_id;
        END IF;

    ELSIF v_completed_count > 0 THEN
        -- No active enrollments, and at least one completed enrollment: overall status is completed
        v_new_status := 'completed';
        v_latest_completed_on := coalesce(v_latest_completed_on, CURRENT_DATE);

        UPDATE students 
        SET status = 'completed'::student_status,
            completed_on = v_latest_completed_on,
            updated_at = clock_timestamp()
        WHERE id = p_student_id;

        IF v_user_id IS NOT NULL THEN
            UPDATE profiles
            SET access_until = coalesce(access_until, (v_latest_completed_on + (v_access_months || ' months')::interval)::date),
                updated_at = clock_timestamp()
            WHERE user_id = v_user_id;
        END IF;

    ELSE
        -- No active and no completed: check if student was marked discontinued/tc_issued
        SELECT status::text INTO v_new_status FROM students WHERE id = p_student_id;
    END IF;

    RETURN v_new_status;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp;

GRANT EXECUTE ON FUNCTION sync_student_completion_status(bigint) TO authenticated;


-- =============================================================================
-- 3. Individual Student Completion & Reopening (Admin Only)
-- =============================================================================

-- Complete Student
CREATE OR REPLACE FUNCTION complete_student(
    p_student_id bigint,
    p_enrollment_id bigint DEFAULT NULL,
    p_completed_on date DEFAULT CURRENT_DATE
)
RETURNS jsonb AS $$
DECLARE
    v_enr_id bigint := p_enrollment_id;
    v_date date := coalesce(p_completed_on, CURRENT_DATE);
    v_student students%ROWTYPE;
    v_new_status text;
    v_actor_id uuid;
BEGIN
    IF NOT is_admin() THEN
        RAISE EXCEPTION 'Access denied. Administrator privilege required.';
    END IF;

    SELECT * INTO v_student FROM students WHERE id = p_student_id AND deleted_at IS NULL;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Student ID % not found.', p_student_id;
    END IF;

    -- If enrollment_id not explicitly given, complete the primary or sole active enrollment
    IF v_enr_id IS NULL THEN
        SELECT id INTO v_enr_id 
        FROM student_enrollments 
        WHERE student_id = p_student_id AND status = 'active' AND deleted_at IS NULL
        ORDER BY CASE WHEN kind = 'primary' THEN 0 ELSE 1 END, id ASC
        LIMIT 1;
    END IF;

    IF v_enr_id IS NOT NULL THEN
        UPDATE student_enrollments
        SET status = 'completed'::enrollment_status,
            completed_on = v_date,
            updated_at = clock_timestamp()
        WHERE id = v_enr_id AND student_id = p_student_id;
    ELSE
        -- No enrollment row exists: create or update primary fallback
        UPDATE students
        SET status = 'completed'::student_status,
            completed_on = v_date,
            updated_at = clock_timestamp()
        WHERE id = p_student_id;
    END IF;

    v_new_status := sync_student_completion_status(p_student_id);

    -- Audit log
    BEGIN v_actor_id := auth.uid(); EXCEPTION WHEN OTHERS THEN v_actor_id := null; END;
    INSERT INTO audit_log (table_name, record_id, action, new_data, actor, created_at)
    VALUES (
        'students',
        p_student_id::text,
        'STUDENT_COMPLETED',
        jsonb_build_object(
            'student_id', p_student_id,
            'enrollment_id', v_enr_id,
            'completed_on', v_date,
            'overall_status', v_new_status
        ),
        v_actor_id,
        clock_timestamp()
    );

    RETURN jsonb_build_object(
        'success', true,
        'student_id', p_student_id,
        'enrollment_id', v_enr_id,
        'completed_on', v_date,
        'overall_status', v_new_status
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp;

GRANT EXECUTE ON FUNCTION complete_student(bigint, bigint, date) TO authenticated;


-- Reopen Student
CREATE OR REPLACE FUNCTION reopen_student(
    p_student_id bigint,
    p_enrollment_id bigint DEFAULT NULL,
    p_reason text DEFAULT NULL
)
RETURNS jsonb AS $$
DECLARE
    v_clean_reason text := trim(coalesce(p_reason, ''));
    v_student students%ROWTYPE;
    v_new_status text;
    v_actor_id uuid;
BEGIN
    IF NOT is_admin() THEN
        RAISE EXCEPTION 'Access denied. Administrator privilege required.';
    END IF;

    IF v_clean_reason = '' THEN
        RAISE EXCEPTION 'Reopening requires a non-empty reason.' USING ERRCODE = '23514';
    END IF;

    SELECT * INTO v_student FROM students WHERE id = p_student_id AND deleted_at IS NULL;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Student ID % not found.', p_student_id;
    END IF;

    IF p_enrollment_id IS NOT NULL THEN
        UPDATE student_enrollments
        SET status = 'active'::enrollment_status,
            completed_on = NULL,
            updated_at = clock_timestamp()
        WHERE id = p_enrollment_id AND student_id = p_student_id;
    ELSE
        -- Reopen all completed enrollments for this student
        UPDATE student_enrollments
        SET status = 'active'::enrollment_status,
            completed_on = NULL,
            updated_at = clock_timestamp()
        WHERE student_id = p_student_id AND status = 'completed';
    END IF;

    v_new_status := sync_student_completion_status(p_student_id);

    -- Audit log
    BEGIN v_actor_id := auth.uid(); EXCEPTION WHEN OTHERS THEN v_actor_id := null; END;
    INSERT INTO audit_log (table_name, record_id, action, new_data, actor, created_at)
    VALUES (
        'students',
        p_student_id::text,
        'STUDENT_REOPENED',
        jsonb_build_object(
            'student_id', p_student_id,
            'enrollment_id', p_enrollment_id,
            'reason', v_clean_reason,
            'overall_status', v_new_status
        ),
        v_actor_id,
        clock_timestamp()
    );

    RETURN jsonb_build_object(
        'success', true,
        'student_id', p_student_id,
        'reason', v_clean_reason,
        'overall_status', v_new_status
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp;

GRANT EXECUTE ON FUNCTION reopen_student(bigint, bigint, text) TO authenticated;


-- =============================================================================
-- 4. Batch Completion Workflow: Preview, Complete & Reopen
-- =============================================================================

-- 4.1. Preview Batch Completion
CREATE OR REPLACE FUNCTION preview_batch_completion(p_batch_id bigint)
RETURNS TABLE (
    student_id bigint,
    enrollment_id bigint,
    name text,
    admission_number text,
    registration_number text,
    phone text,
    pending_fee_balance_paise bigint,
    pending_fee_balance numeric(12,2),
    has_pending_fee boolean,
    sessions_held int,
    attended_sessions int,
    attendance_percentage numeric(5,2),
    other_active_enrollments_count int,
    will_overall_complete boolean
) AS $$
BEGIN
    IF NOT is_admin() THEN
        RAISE EXCEPTION 'Access denied. Administrator privilege required.';
    END IF;

    RETURN QUERY
    WITH batch_students AS (
        SELECT 
            s.id AS sid,
            se.id AS eid,
            s.name AS sname,
            coalesce(s.admission_number, 'N/A') AS adm_no,
            coalesce(s.registration_number, 'N/A') AS reg_no,
            coalesce(s.phone, 'N/A') AS sphone
        FROM students s
        JOIN student_enrollments se 
            ON se.student_id = s.id 
           AND se.batch_id = p_batch_id 
           AND se.status = 'active' 
           AND se.deleted_at IS NULL
        WHERE s.deleted_at IS NULL
    ),
    student_fees AS (
        SELECT 
            bs.sid,
            coalesce(vfs.pending_amount_paise, f.pending_amount_paise, 0) AS pending_paise
        FROM batch_students bs
        LEFT JOIN view_student_fee_summary vfs ON vfs.student_id = bs.sid
        LEFT JOIN fees f ON f.student_id = bs.sid AND f.deleted_at IS NULL
    ),
    student_att AS (
        SELECT 
            bs.sid,
            coalesce(att.sessions_held, 0) AS held,
            coalesce(att.present_count + att.late_count, 0) AS attended,
            coalesce(att.attendance_percentage, 0.0) AS att_pct
        FROM batch_students bs
        LEFT JOIN LATERAL (
            SELECT 
                sas.sessions_held,
                sas.present_count,
                sas.late_count,
                sas.percentage AS attendance_percentage
            FROM student_attendance_summary(bs.sid, bs.eid) sas
            LIMIT 1
        ) att ON true
    ),
    other_enrollments AS (
        SELECT 
            bs.sid,
            count(se2.id)::int AS other_count
        FROM batch_students bs
        LEFT JOIN student_enrollments se2 
            ON se2.student_id = bs.sid 
           AND se2.batch_id != p_batch_id 
           AND se2.status = 'active' 
           AND se2.deleted_at IS NULL
        GROUP BY bs.sid
    )
    SELECT 
        bs.sid AS student_id,
        bs.eid AS enrollment_id,
        bs.sname AS name,
        bs.adm_no AS admission_number,
        bs.reg_no AS registration_number,
        bs.sphone AS phone,
        sf.pending_paise AS pending_fee_balance_paise,
        round(sf.pending_paise / 100.0, 2) AS pending_fee_balance,
        (sf.pending_paise > 0) AS has_pending_fee,
        sa.held::int AS sessions_held,
        sa.attended::int AS attended_sessions,
        sa.att_pct AS attendance_percentage,
        coalesce(oe.other_count, 0) AS other_active_enrollments_count,
        (coalesce(oe.other_count, 0) = 0) AS will_overall_complete
    FROM batch_students bs
    JOIN student_fees sf ON sf.sid = bs.sid
    JOIN student_att sa ON sa.sid = bs.sid
    LEFT JOIN other_enrollments oe ON oe.sid = bs.sid
    ORDER BY bs.sname ASC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE
SET search_path = public, pg_temp;

GRANT EXECUTE ON FUNCTION preview_batch_completion(bigint) TO authenticated;


-- 4.2. Complete Batch (Atomic Transaction)
CREATE OR REPLACE FUNCTION complete_batch(
    p_batch_id bigint,
    p_completed_on date DEFAULT CURRENT_DATE,
    p_excluded_student_ids bigint[] DEFAULT ARRAY[]::bigint[],
    p_access_until_override date DEFAULT NULL,
    p_close_logins_now boolean DEFAULT false
)
RETURNS jsonb AS $$
DECLARE
    v_date date := coalesce(p_completed_on, CURRENT_DATE);
    v_batch batches%ROWTYPE;
    v_rec record;
    v_completed_count int := 0;
    v_excluded_count int := 0;
    v_actor_id uuid;
    v_user_id uuid;
    v_status text;
BEGIN
    IF NOT is_admin() THEN
        RAISE EXCEPTION 'Access denied. Administrator privilege required.';
    END IF;

    SELECT * INTO v_batch FROM batches WHERE id = p_batch_id AND deleted_at IS NULL;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Batch ID % not found.', p_batch_id;
    END IF;

    -- Update batch status
    UPDATE batches
    SET status = 'completed',
        completed_on = v_date,
        updated_at = clock_timestamp()
    WHERE id = p_batch_id;

    -- Loop through active enrollments for this batch
    FOR v_rec IN 
        SELECT se.id AS enrollment_id, se.student_id 
        FROM student_enrollments se
        WHERE se.batch_id = p_batch_id 
          AND se.status = 'active' 
          AND se.deleted_at IS NULL
    LOOP
        IF p_excluded_student_ids IS NOT NULL AND v_rec.student_id = ANY(p_excluded_student_ids) THEN
            v_excluded_count := v_excluded_count + 1;
        ELSE
            UPDATE student_enrollments
            SET status = 'completed'::enrollment_status,
                completed_on = v_date,
                updated_at = clock_timestamp()
            WHERE id = v_rec.enrollment_id;

            v_status := sync_student_completion_status(v_rec.student_id);

            -- Check if access until override or close logins immediately is specified
            SELECT user_id INTO v_user_id FROM profiles WHERE student_id = v_rec.student_id;
            IF v_user_id IS NOT NULL THEN
                IF p_close_logins_now THEN
                    UPDATE profiles
                    SET active = false,
                        access_until = CURRENT_DATE,
                        updated_at = clock_timestamp()
                    WHERE user_id = v_user_id;
                ELSIF p_access_until_override IS NOT NULL THEN
                    UPDATE profiles
                    SET access_until = p_access_until_override,
                        updated_at = clock_timestamp()
                    WHERE user_id = v_user_id;
                END IF;
            END IF;

            v_completed_count := v_completed_count + 1;
        END IF;
    END LOOP;

    -- Audit log
    BEGIN v_actor_id := auth.uid(); EXCEPTION WHEN OTHERS THEN v_actor_id := null; END;
    INSERT INTO audit_log (table_name, record_id, action, new_data, actor, created_at)
    VALUES (
        'batches',
        p_batch_id::text,
        'BATCH_COMPLETED',
        jsonb_build_object(
            'batch_id', p_batch_id,
            'completed_on', v_date,
            'completed_students_count', v_completed_count,
            'excluded_students_count', v_excluded_count,
            'excluded_student_ids', p_excluded_student_ids,
            'access_until_override', p_access_until_override,
            'close_logins_now', p_close_logins_now
        ),
        v_actor_id,
        clock_timestamp()
    );

    RETURN jsonb_build_object(
        'success', true,
        'batch_id', p_batch_id,
        'completed_on', v_date,
        'completed_students_count', v_completed_count,
        'excluded_students_count', v_excluded_count
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp;

GRANT EXECUTE ON FUNCTION complete_batch(bigint, date, bigint[], date, boolean) TO authenticated;


-- 4.3. Reopen Batch
CREATE OR REPLACE FUNCTION reopen_batch(
    p_batch_id bigint,
    p_reason text
)
RETURNS jsonb AS $$
DECLARE
    v_clean_reason text := trim(coalesce(p_reason, ''));
    v_batch batches%ROWTYPE;
    v_rec record;
    v_reopened_count int := 0;
    v_actor_id uuid;
    v_user_id uuid;
BEGIN
    IF NOT is_admin() THEN
        RAISE EXCEPTION 'Access denied. Administrator privilege required.';
    END IF;

    IF v_clean_reason = '' THEN
        RAISE EXCEPTION 'Reopening requires a non-empty reason.' USING ERRCODE = '23514';
    END IF;

    SELECT * INTO v_batch FROM batches WHERE id = p_batch_id AND deleted_at IS NULL;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Batch ID % not found.', p_batch_id;
    END IF;

    -- Update batch status
    UPDATE batches
    SET status = 'active',
        completed_on = NULL,
        updated_at = clock_timestamp()
    WHERE id = p_batch_id;

    -- Reopen enrollments completed for this batch
    FOR v_rec IN 
        SELECT se.id AS enrollment_id, se.student_id 
        FROM student_enrollments se
        WHERE se.batch_id = p_batch_id 
          AND se.status = 'completed'
          AND se.deleted_at IS NULL
    LOOP
        UPDATE student_enrollments
        SET status = 'active'::enrollment_status,
            completed_on = NULL,
            updated_at = clock_timestamp()
        WHERE id = v_rec.enrollment_id;

        PERFORM sync_student_completion_status(v_rec.student_id);

        -- Restore user profile login access
        SELECT user_id INTO v_user_id FROM profiles WHERE student_id = v_rec.student_id;
        IF v_user_id IS NOT NULL THEN
            UPDATE profiles
            SET active = true,
                access_until = NULL,
                updated_at = clock_timestamp()
            WHERE user_id = v_user_id;
        END IF;

        v_reopened_count := v_reopened_count + 1;
    END LOOP;

    -- Audit log
    BEGIN v_actor_id := auth.uid(); EXCEPTION WHEN OTHERS THEN v_actor_id := null; END;
    INSERT INTO audit_log (table_name, record_id, action, new_data, actor, created_at)
    VALUES (
        'batches',
        p_batch_id::text,
        'BATCH_REOPENED',
        jsonb_build_object(
            'batch_id', p_batch_id,
            'reason', v_clean_reason,
            'reopened_students_count', v_reopened_count
        ),
        v_actor_id,
        clock_timestamp()
    );

    RETURN jsonb_build_object(
        'success', true,
        'batch_id', p_batch_id,
        'reason', v_clean_reason,
        'reopened_students_count', v_reopened_count
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp;

GRANT EXECUTE ON FUNCTION reopen_batch(bigint, text) TO authenticated;


-- =============================================================================
-- 5. Phase 9E: Student Access Window Management & RLS Security
-- =============================================================================

-- 5.1. Helper Function: student_access_allowed()
CREATE OR REPLACE FUNCTION student_access_allowed()
RETURNS boolean AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM profiles
        WHERE user_id = auth.uid() 
          AND role = 'student' 
          AND active = true
          AND (access_until IS NULL OR access_until >= CURRENT_DATE)
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE
SET search_path = public, pg_temp;

GRANT EXECUTE ON FUNCTION student_access_allowed() TO authenticated;


-- 5.2. Admin Action: close_login
CREATE OR REPLACE FUNCTION close_login(
    p_user_id uuid,
    p_reason text
)
RETURNS jsonb AS $$
DECLARE
    v_clean_reason text := trim(coalesce(p_reason, ''));
    v_prof profiles%ROWTYPE;
    v_student_id bigint;
    v_pending_paise bigint := 0;
    v_actor_id uuid;
BEGIN
    IF NOT is_admin() THEN
        RAISE EXCEPTION 'Access denied. Administrator privilege required.';
    END IF;

    IF v_clean_reason = '' THEN
        RAISE EXCEPTION 'Closing login requires a non-empty reason.' USING ERRCODE = '23514';
    END IF;

    SELECT * INTO v_prof FROM profiles WHERE user_id = p_user_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'User profile ID % not found.', p_user_id;
    END IF;

    v_student_id := v_prof.student_id;
    IF v_student_id IS NOT NULL THEN
        SELECT coalesce(f.pending_amount_paise, 0) INTO v_pending_paise
        FROM fees f WHERE f.student_id = v_student_id AND f.deleted_at IS NULL;
    END IF;

    UPDATE profiles
    SET active = false,
        access_until = CURRENT_DATE,
        updated_at = clock_timestamp()
    WHERE user_id = p_user_id;

    -- Audit log
    BEGIN v_actor_id := auth.uid(); EXCEPTION WHEN OTHERS THEN v_actor_id := null; END;
    INSERT INTO audit_log (table_name, record_id, action, new_data, actor, created_at)
    VALUES (
        'profiles',
        p_user_id::text,
        'LOGIN_CLOSED',
        jsonb_build_object(
            'user_id', p_user_id,
            'student_id', v_student_id,
            'reason', v_clean_reason,
            'pending_fee_balance_paise', v_pending_paise,
            'has_pending_fee', (v_pending_paise > 0)
        ),
        v_actor_id,
        clock_timestamp()
    );

    RETURN jsonb_build_object(
        'success', true,
        'user_id', p_user_id,
        'active', false,
        'has_pending_fee', (v_pending_paise > 0),
        'pending_fee_balance_paise', v_pending_paise
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp;

GRANT EXECUTE ON FUNCTION close_login(uuid, text) TO authenticated;


-- 5.3. Admin Action: extend_access
CREATE OR REPLACE FUNCTION extend_access(
    p_user_id uuid,
    p_new_date date
)
RETURNS jsonb AS $$
DECLARE
    v_actor_id uuid;
    v_prof profiles%ROWTYPE;
BEGIN
    IF NOT is_admin() THEN
        RAISE EXCEPTION 'Access denied. Administrator privilege required.';
    END IF;

    IF p_new_date IS NULL OR p_new_date <= CURRENT_DATE THEN
        RAISE EXCEPTION 'Extension date must be in the future.' USING ERRCODE = '23514';
    END IF;

    SELECT * INTO v_prof FROM profiles WHERE user_id = p_user_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'User profile ID % not found.', p_user_id;
    END IF;

    UPDATE profiles
    SET access_until = p_new_date,
        active = true,
        updated_at = clock_timestamp()
    WHERE user_id = p_user_id;

    BEGIN v_actor_id := auth.uid(); EXCEPTION WHEN OTHERS THEN v_actor_id := null; END;
    INSERT INTO audit_log (table_name, record_id, action, new_data, actor, created_at)
    VALUES (
        'profiles',
        p_user_id::text,
        'ACCESS_EXTENDED',
        jsonb_build_object(
            'user_id', p_user_id,
            'new_access_until', p_new_date
        ),
        v_actor_id,
        clock_timestamp()
    );

    RETURN jsonb_build_object(
        'success', true,
        'user_id', p_user_id,
        'access_until', p_new_date
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp;

GRANT EXECUTE ON FUNCTION extend_access(uuid, date) TO authenticated;


-- 5.4. Admin Action: reopen_login
CREATE OR REPLACE FUNCTION reopen_login(
    p_user_id uuid,
    p_new_date date
)
RETURNS jsonb AS $$
BEGIN
    RETURN extend_access(p_user_id, p_new_date);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp;

GRANT EXECUTE ON FUNCTION reopen_login(uuid, date) TO authenticated;


-- 5.5. Daily Expiry Routine (for 00:30 IST Scheduled Job)
CREATE OR REPLACE FUNCTION expire_student_logins_daily()
RETURNS jsonb AS $$
DECLARE
    v_count int := 0;
    v_rec record;
BEGIN
    FOR v_rec IN 
        SELECT p.user_id, p.student_id, p.access_until
        FROM profiles p
        WHERE p.role = 'student'
          AND p.active = true
          AND p.access_until IS NOT NULL
          AND p.access_until < CURRENT_DATE
    LOOP
        UPDATE profiles
        SET active = false,
            updated_at = clock_timestamp()
        WHERE user_id = v_rec.user_id;

        INSERT INTO audit_log (table_name, record_id, action, new_data, actor, created_at)
        VALUES (
            'profiles',
            v_rec.user_id::text,
            'ACCESS_EXPIRED',
            jsonb_build_object(
                'user_id', v_rec.user_id,
                'student_id', v_rec.student_id,
                'access_until', v_rec.access_until
            ),
            NULL,
            clock_timestamp()
        );

        v_count := v_count + 1;
    END LOOP;

    RETURN jsonb_build_object('success', true, 'expired_accounts_count', v_count);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp;

GRANT EXECUTE ON FUNCTION expire_student_logins_daily() TO authenticated;


-- 5.6. Access Expiry Reminders (14 days and 3 days before expiry)
CREATE OR REPLACE FUNCTION send_access_expiry_reminders()
RETURNS jsonb AS $$
DECLARE
    v_count int := 0;
    v_rec record;
    v_body text;
BEGIN
    FOR v_rec IN 
        SELECT p.user_id, p.student_id, p.access_until, s.name,
               (p.access_until - CURRENT_DATE) AS days_remaining
        FROM profiles p
        JOIN students s ON s.id = p.student_id
        WHERE p.role = 'student'
          AND p.active = true
          AND p.access_until IS NOT NULL
          AND (p.access_until = CURRENT_DATE + 14 OR p.access_until = CURRENT_DATE + 3)
          AND NOT EXISTS (
              SELECT 1 FROM notifications n 
              WHERE n.user_id = p.user_id 
                AND n.type = 'access_expiry_warning' 
                AND n.created_at::date = CURRENT_DATE
          )
    LOOP
        v_body := format('Your access ends on %s. Download your results and receipts before then.', 
                         to_char(v_rec.access_until, 'DD-Mon-YYYY'));

        INSERT INTO notifications (
            user_id,
            recipient_type,
            recipient_id,
            type,
            title,
            body,
            created_at
        ) VALUES (
            v_rec.user_id,
            'student',
            v_rec.student_id,
            'access_expiry_warning',
            'Portal Access Ending Soon',
            v_body,
            clock_timestamp()
        );

        v_count := v_count + 1;
    END LOOP;

    RETURN jsonb_build_object('success', true, 'reminders_sent', v_count);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp;

GRANT EXECUTE ON FUNCTION send_access_expiry_reminders() TO authenticated;


-- 5.7. Update Student RLS Read Policies to Enforce student_access_allowed()
DROP POLICY IF EXISTS p_students_student_select ON students;
CREATE POLICY p_students_student_select ON students
    FOR SELECT TO authenticated
    USING (
        student_access_allowed() 
        AND id = current_student_id() 
        AND deleted_at IS NULL
    );

DROP POLICY IF EXISTS p_student_enrollments_student_select ON student_enrollments;
CREATE POLICY p_student_enrollments_student_select ON student_enrollments
    FOR SELECT TO authenticated
    USING (
        student_access_allowed() 
        AND student_id = current_student_id() 
        AND deleted_at IS NULL
    );

DROP POLICY IF EXISTS p_fees_student_select ON fees;
CREATE POLICY p_fees_student_select ON fees
    FOR SELECT TO authenticated
    USING (
        student_access_allowed() 
        AND student_id = current_student_id() 
        AND deleted_at IS NULL
    );

DROP POLICY IF EXISTS p_receipts_student_select ON receipts;
CREATE POLICY p_receipts_student_select ON receipts
    FOR SELECT TO authenticated
    USING (
        student_access_allowed() 
        AND student_id = current_student_id() 
        AND deleted_at IS NULL
    );

DROP POLICY IF EXISTS p_results_student_select ON results;
CREATE POLICY p_results_student_select ON results
    FOR SELECT TO authenticated
    USING (
        student_access_allowed() 
        AND student_id = current_student_id() 
        AND deleted_at IS NULL
    );

DROP POLICY IF EXISTS p_attendance_records_student_select ON attendance_records;
CREATE POLICY p_attendance_records_student_select ON attendance_records
    FOR SELECT TO authenticated
    USING (
        student_access_allowed() 
        AND student_id = current_student_id() 
        AND deleted_at IS NULL
    );

DROP POLICY IF EXISTS p_marks_student_select ON marks;
CREATE POLICY p_marks_student_select ON marks
    FOR SELECT TO authenticated
    USING (
        student_access_allowed() 
        AND student_id = current_student_id() 
        AND deleted_at IS NULL
    );


-- =============================================================================
-- 6. Attendance Engine Updates: Ignored Completed Batches & Students
-- =============================================================================

-- 6.1. students_for_teacher View: Active primary batches and active students only
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
JOIN courses c ON c.id = b.course_id
JOIN student_enrollments se 
    ON se.student_id = s.id 
   AND se.batch_id = b.id 
   AND se.deleted_at IS NULL
WHERE s.deleted_at IS NULL
  AND s.status = 'active'
  AND se.status = 'active'
  AND b.deleted_at IS NULL
  AND b.status = 'active'
  AND c.course_type = 'primary'
  AND (
      is_admin()
      OR (
          is_teacher() AND EXISTS (
              SELECT 1 FROM teachers t 
              WHERE t.id = current_teacher_id() AND t.status = 'active'
          )
      )
  );

GRANT SELECT ON students_for_teacher TO authenticated;


-- 6.2. Atomic submit_attendance: Rejects completed batches & ignores non-active students
CREATE OR REPLACE FUNCTION submit_attendance(
    p_batch_id bigint,
    p_date date,
    p_slot attendance_slot,
    p_records jsonb DEFAULT '[]'::jsonb,
    p_no_class boolean DEFAULT false,
    p_no_class_reason text DEFAULT NULL
)
RETURNS jsonb AS $$
DECLARE
    v_course_type text;
    v_batch_status text;
    v_teacher_id bigint;
    v_marker_name text;
    v_marker_role text := 'teacher';
    v_existing attendance_sessions%ROWTYPE;
    v_session_id bigint;
    v_window_hours int := 24;
    v_setting_window text;
    v_item jsonb;
    v_student_id bigint;
    v_status attendance_status;
    v_remarks text;
    v_count int := 0;
BEGIN
    -- 1. Authorization: Only active teachers or administrators
    IF NOT is_admin() AND NOT is_teacher() THEN
        RAISE EXCEPTION 'Access denied. Only registered teachers or administrators can submit attendance.';
    END IF;

    IF is_teacher() AND NOT is_admin() THEN
        v_teacher_id := current_teacher_id();
        IF v_teacher_id IS NULL THEN
            RAISE EXCEPTION 'No teacher profile linked to your user account.';
        END IF;

        IF NOT EXISTS (SELECT 1 FROM teachers WHERE id = v_teacher_id AND status = 'active') THEN
            RAISE EXCEPTION 'Your teacher account is deactivated. Contact the administrator.';
        END IF;

        SELECT value INTO v_setting_window FROM settings WHERE key = 'teacher_attendance_edit_window_hours';
        IF v_setting_window IS NOT NULL AND v_setting_window ~ '^\d+$' THEN
            v_window_hours := v_setting_window::int;
        END IF;

        IF p_date < (CURRENT_DATE - (v_window_hours / 24)::int) OR p_date > CURRENT_DATE THEN
            RAISE EXCEPTION 'Attendance date % is outside the allowed submission window (% days).', p_date, ceil(v_window_hours / 24.0)::int;
        END IF;
    END IF;

    -- 2. Validate primary course batch and active status
    SELECT c.course_type, b.status INTO v_course_type, v_batch_status
    FROM batches b
    JOIN courses c ON c.id = b.course_id
    WHERE b.id = p_batch_id AND b.deleted_at IS NULL;

    IF v_course_type IS NULL THEN
        RAISE EXCEPTION 'Batch ID % not found.', p_batch_id;
    END IF;

    IF v_batch_status = 'completed' THEN
        RAISE EXCEPTION 'Attendance cannot be submitted for completed batch ID %.', p_batch_id
            USING ERRCODE = '23514';
    END IF;

    IF v_course_type != 'primary' THEN
        RAISE EXCEPTION 'Attendance can only be submitted for primary course batches. Skill courses do not track attendance.'
            USING ERRCODE = '23514';
    END IF;

    -- 3. Acquire transaction-level advisory lock
    PERFORM pg_advisory_xact_lock(hashtext('mips_att_' || p_batch_id::text || '_' || p_date::text || '_' || p_slot::text));

    -- 4. Check existing session for this slot
    SELECT * INTO v_existing
    FROM attendance_sessions
    WHERE batch_id = p_batch_id AND date = p_date AND slot = p_slot
    FOR UPDATE;

    IF FOUND AND v_existing.status IN ('submitted', 'locked', 'no_class') THEN
        IF v_existing.marked_by IS NOT NULL THEN
            SELECT name INTO v_marker_name FROM teachers WHERE id = v_existing.marked_by;
            v_marker_role := 'teacher';
        END IF;

        IF v_marker_name IS NULL THEN
            v_marker_name := 'Administrator';
            v_marker_role := 'admin';
        END IF;

        RETURN jsonb_build_object(
            'success', false,
            'error_code', 'ALREADY_MARKED',
            'message', format('Already marked by %s (%s) at %s. Only the administrator can correct it.', 
                              v_marker_name, v_marker_role, to_char(v_existing.submitted_at, 'DD/MM/YYYY HH24:MI')),
            'marked_by_name', v_marker_name,
            'marked_by_role', v_marker_role,
            'marked_at', v_existing.submitted_at,
            'state', v_existing.status
        );
    END IF;

    -- 5. Atomic Insertion
    IF p_no_class THEN
        INSERT INTO attendance_sessions (
            batch_id, date, slot, status, marked_by, no_class_reason,
            submitted_at, created_at, updated_at
        ) VALUES (
            p_batch_id, p_date, p_slot, 'no_class', v_teacher_id,
            coalesce(trim(p_no_class_reason), 'No class held'),
            clock_timestamp(), clock_timestamp(), clock_timestamp()
        )
        ON CONFLICT (batch_id, date, slot)
        DO UPDATE SET
            status = 'no_class',
            marked_by = coalesce(v_teacher_id, attendance_sessions.marked_by),
            no_class_reason = EXCLUDED.no_class_reason,
            submitted_at = clock_timestamp(),
            updated_at = clock_timestamp()
        RETURNING id INTO v_session_id;

        DELETE FROM attendance_records WHERE session_id = v_session_id;
    ELSE
        INSERT INTO attendance_sessions (
            batch_id, date, slot, status, marked_by,
            submitted_at, created_at, updated_at
        ) VALUES (
            p_batch_id, p_date, p_slot, 'submitted', v_teacher_id,
            clock_timestamp(), clock_timestamp(), clock_timestamp()
        )
        ON CONFLICT (batch_id, date, slot)
        DO UPDATE SET
            status = 'submitted',
            marked_by = coalesce(v_teacher_id, attendance_sessions.marked_by),
            submitted_at = clock_timestamp(),
            updated_at = clock_timestamp()
        RETURNING id INTO v_session_id;

        -- Insert records: ONLY for active students in active enrollments
        FOR v_item IN SELECT * FROM jsonb_array_elements(p_records)
        LOOP
            v_student_id := (v_item->>'student_id')::bigint;
            v_status := (lower(trim(v_item->>'status')))::attendance_status;
            v_remarks := trim(v_item->>'remarks');

            IF EXISTS (
                SELECT 1 FROM students s
                JOIN student_enrollments se ON se.student_id = s.id AND se.batch_id = p_batch_id
                WHERE s.id = v_student_id 
                  AND s.status = 'active' 
                  AND se.status = 'active'
                  AND s.deleted_at IS NULL
            ) THEN
                INSERT INTO attendance_records (
                    session_id, student_id, status, remarks, created_at, updated_at
                ) VALUES (
                    v_session_id, v_student_id, v_status, v_remarks,
                    clock_timestamp(), clock_timestamp()
                )
                ON CONFLICT (session_id, student_id)
                DO UPDATE SET
                    status = EXCLUDED.status,
                    remarks = EXCLUDED.remarks,
                    updated_at = clock_timestamp();

                v_count := v_count + 1;
            END IF;
        END LOOP;
    END IF;

    -- Audit log
    INSERT INTO audit_log (table_name, record_id, action, new_data, actor, created_at)
    VALUES (
        'attendance_sessions',
        v_session_id::text,
        'INSERT',
        jsonb_build_object(
            'batch_id', p_batch_id,
            'date', p_date,
            'slot', p_slot,
            'status', CASE WHEN p_no_class THEN 'no_class' ELSE 'submitted' END,
            'records_count', v_count
        ),
        v_teacher_id,
        clock_timestamp()
    );

    RETURN jsonb_build_object(
        'success', true,
        'session_id', v_session_id,
        'status', CASE WHEN p_no_class THEN 'no_class' ELSE 'submitted' END,
        'records_count', v_count
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp;

GRANT EXECUTE ON FUNCTION submit_attendance(bigint, date, attendance_slot, jsonb, boolean, text) TO authenticated;


-- 6.3. Stop Attendance Alerts for Completed Students
CREATE OR REPLACE FUNCTION evaluate_attendance_alerts(
    p_student_id bigint DEFAULT NULL,
    p_batch_id bigint DEFAULT NULL
)
RETURNS jsonb AS $$
DECLARE
    v_target_students bigint[];
    v_sid bigint;
    v_summary record;
    v_enr_id bigint;
    v_last_band text;
    v_student_name text;
    v_adm_no text;
    v_alerts_sent int := 0;
    v_admin_user_id uuid;
BEGIN
    IF p_student_id IS NOT NULL THEN
        -- Only target active students
        SELECT ARRAY[id] INTO v_target_students
        FROM students
        WHERE id = p_student_id AND status = 'active' AND deleted_at IS NULL;
        IF v_target_students IS NULL THEN
            RETURN jsonb_build_object('success', true, 'alerts_sent', 0, 'message', 'Student is not active; alerts halted.');
        END IF;
    ELSIF p_batch_id IS NOT NULL THEN
        SELECT coalesce(array_agg(s.id), ARRAY[]::bigint[])
        INTO v_target_students
        FROM students s
        JOIN student_enrollments se ON se.student_id = s.id AND se.batch_id = p_batch_id AND se.status = 'active'
        WHERE s.status = 'active' AND s.deleted_at IS NULL;
    ELSE
        RETURN jsonb_build_object('success', false, 'message', 'Either student_id or batch_id must be provided.');
    END IF;

    FOREACH v_sid IN ARRAY v_target_students
    LOOP
        SELECT * INTO v_summary FROM student_attendance_summary(v_sid) LIMIT 1;

        IF v_summary.student_id IS NOT NULL THEN
            v_enr_id := coalesce(v_summary.enrollment_id, 0);

            SELECT last_band INTO v_last_band
            FROM attendance_alert_state
            WHERE student_id = v_sid AND enrollment_id = v_enr_id;

            IF v_last_band IS NULL THEN
                v_last_band := 'ok';
            END IF;

            IF v_summary.status_band != v_last_band THEN
                SELECT name, admission_number INTO v_student_name, v_adm_no
                FROM students WHERE id = v_sid;

                IF v_summary.status_band = 'low' THEN
                    INSERT INTO notifications (
                        recipient_type, recipient_id, type, title, body, created_at
                    ) VALUES (
                        'student', v_sid, 'attendance_warning', 'Low attendance',
                        format('Your attendance is currently %s%%. You can miss at most %s more session(s) before facing an attendance shortage below 75%%.', 
                               v_summary.percentage, v_summary.can_miss_more),
                        clock_timestamp()
                    );
                    v_alerts_sent := v_alerts_sent + 1;

                ELSIF v_summary.status_band = 'shortage' THEN
                    INSERT INTO notifications (
                        recipient_type, recipient_id, type, title, body, created_at
                    ) VALUES (
                        'student', v_sid, 'attendance_shortage', 'Attendance shortage',
                        format('Your attendance is currently %s%% (below 75%%). You must attend the next %s consecutive session(s) to regain eligibility.', 
                               v_summary.percentage, v_summary.recover_sessions),
                        clock_timestamp()
                    );

                    SELECT user_id INTO v_admin_user_id FROM profiles WHERE role = 'admin' AND active = true LIMIT 1;
                    IF v_admin_user_id IS NOT NULL THEN
                        INSERT INTO notifications (
                            user_id, recipient_type, recipient_id, type, title, body, created_at
                        ) VALUES (
                            v_admin_user_id, 'admin', NULL, 'student_attendance_shortage',
                            format('Attendance shortage: %s', v_student_name),
                            format('%s (%s) has an attendance shortage of %s%%.', v_student_name, v_adm_no, v_summary.percentage),
                            clock_timestamp()
                        );
                    END IF;
                    v_alerts_sent := v_alerts_sent + 1;
                END IF;

                INSERT INTO attendance_alert_state (
                    student_id, enrollment_id, last_percentage, last_band, evaluated_at, updated_at
                ) VALUES (
                    v_sid, v_enr_id, v_summary.percentage, v_summary.status_band, clock_timestamp(), clock_timestamp()
                )
                ON CONFLICT (student_id, enrollment_id)
                DO UPDATE SET
                    last_percentage = EXCLUDED.last_percentage,
                    last_band = EXCLUDED.last_band,
                    evaluated_at = EXCLUDED.evaluated_at,
                    updated_at = EXCLUDED.updated_at;
            END IF;
        END IF;
    END LOOP;

    RETURN jsonb_build_object('success', true, 'alerts_sent', v_alerts_sent);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp;

GRANT EXECUTE ON FUNCTION evaluate_attendance_alerts(bigint, bigint) TO authenticated;


-- =============================================================================
-- 7. Announcements Audience Rules: fee_defaulters includes completed students
-- =============================================================================

CREATE OR REPLACE FUNCTION create_announcement(p_payload jsonb)
RETURNS jsonb AS $$
DECLARE
    v_category announcement_category;
    v_audience_type announcement_audience;
    v_title text;
    v_body text;
    v_audience_ids jsonb;
    v_min_balance bigint := 0;
    v_dry_run boolean := false;
    v_admin_id uuid;
    v_count int := 0;
    v_announcement_id bigint;
    v_rec record;
    v_balance_fmt text;
    v_due_date_fmt text;
    v_rendered_body text;
BEGIN
    IF NOT is_admin() THEN
        RAISE EXCEPTION 'Access denied. Administrator privilege required.';
    END IF;

    BEGIN v_admin_id := auth.uid(); EXCEPTION WHEN OTHERS THEN v_admin_id := null; END;

    v_category := (p_payload->>'category')::announcement_category;
    v_audience_type := (p_payload->>'audience_type')::announcement_audience;
    v_title := trim(p_payload->>'title');
    v_body := trim(p_payload->>'body');
    v_audience_ids := coalesce(p_payload->'audience_ids', '[]'::jsonb);
    v_dry_run := coalesce((p_payload->>'dry_run')::boolean, false);

    IF p_payload ? 'min_balance_paise' THEN
        v_min_balance := (p_payload->>'min_balance_paise')::bigint;
    END IF;

    IF v_title = '' OR v_body = '' THEN
        RAISE EXCEPTION 'Title and body are required.';
    END IF;

    -- Audience Resolution
    IF v_audience_type = 'teachers' THEN
        FOR v_rec IN 
            SELECT t.id, t.name, p.user_id 
            FROM teachers t
            LEFT JOIN profiles p ON p.teacher_id = t.id AND p.role = 'teacher'
            WHERE t.deleted_at IS NULL AND t.status = 'active'
        LOOP
            v_count := v_count + 1;
            IF NOT v_dry_run THEN
                IF v_count = 1 THEN
                    INSERT INTO announcements (
                        category, title, body, audience_type, audience_ids, 
                        min_balance_paise, recipient_count, created_by, created_at
                    ) VALUES (
                        v_category, v_title, v_body, v_audience_type, v_audience_ids,
                        v_min_balance, 0, v_admin_id, clock_timestamp()
                    ) RETURNING id INTO v_announcement_id;
                END IF;

                INSERT INTO notifications (
                    user_id, recipient_type, recipient_id, type, title, body, announcement_id, created_at
                ) VALUES (
                    v_rec.user_id, 'teacher', v_rec.id, 'announcement', v_title, v_body, v_announcement_id, clock_timestamp()
                );
            END IF;
        END LOOP;

    ELSE
        -- Resolve students
        FOR v_rec IN 
            SELECT 
                s.id AS student_id,
                s.name AS student_name,
                coalesce(c.name, 'N/A') AS course_name,
                coalesce(vfs.pending_amount_paise, 0) AS pending_paise,
                (
                    SELECT min(fi.due_date) 
                    FROM fee_items fi 
                    WHERE fi.student_id = s.id AND fi.status != 'paid' AND fi.deleted_at IS NULL
                ) AS earliest_due,
                p.user_id
            FROM students s
            LEFT JOIN courses c ON c.id = s.course_id
            LEFT JOIN view_student_fee_summary vfs ON vfs.student_id = s.id
            LEFT JOIN profiles p ON p.student_id = s.id AND p.role = 'student'
            WHERE s.deleted_at IS NULL 
              AND (
                  -- Audience filter: 'all_students', 'course', 'batch' ONLY for ACTIVE students
                  (v_audience_type = 'all_students' AND s.status = 'active')
                  OR (v_audience_type = 'course' AND s.status = 'active' AND (
                      s.course_id::text IN (SELECT jsonb_array_elements_text(v_audience_ids))
                      OR EXISTS (SELECT 1 FROM student_enrollments se WHERE se.student_id = s.id AND se.course_id::text IN (SELECT jsonb_array_elements_text(v_audience_ids)) AND se.status = 'active')
                  ))
                  OR (v_audience_type = 'batch' AND s.status = 'active' AND (
                      s.batch_id::text IN (SELECT jsonb_array_elements_text(v_audience_ids))
                      OR EXISTS (SELECT 1 FROM student_enrollments se WHERE se.student_id = s.id AND se.batch_id::text IN (SELECT jsonb_array_elements_text(v_audience_ids)) AND se.status = 'active')
                  ))
                  -- Fee Defaulters includes BOTH active and completed students who owe money!
                  OR (v_audience_type = 'fee_defaulters' AND s.status IN ('active', 'completed') AND coalesce(vfs.pending_amount_paise, 0) > v_min_balance)
              )
        LOOP
            v_count := v_count + 1;

            IF NOT v_dry_run THEN
                IF v_count = 1 THEN
                    INSERT INTO announcements (
                        category, title, body, audience_type, audience_ids, 
                        min_balance_paise, recipient_count, created_by, created_at
                    ) VALUES (
                        v_category, v_title, v_body, v_audience_type, v_audience_ids,
                        v_min_balance, 0, v_admin_id, clock_timestamp()
                    ) RETURNING id INTO v_announcement_id;
                END IF;

                v_balance_fmt := '₹' || to_char(round(v_rec.pending_paise / 100.0, 2), 'FM999,999,990.00');
                v_due_date_fmt := coalesce(to_char(v_rec.earliest_due, 'DD-Mon-YYYY'), 'N/A');

                v_rendered_body := replace(v_body, '{student_name}', v_rec.student_name);
                v_rendered_body := replace(v_rendered_body, '{name}', v_rec.student_name);
                v_rendered_body := replace(v_rendered_body, '{balance}', v_balance_fmt);
                v_rendered_body := replace(v_rendered_body, '{course}', v_rec.course_name);
                v_rendered_body := replace(v_rendered_body, '{due_date}', v_due_date_fmt);

                INSERT INTO notifications (
                    user_id, recipient_type, recipient_id, type, title, body, announcement_id, created_at
                ) VALUES (
                    v_rec.user_id, 'student', v_rec.student_id, 'announcement', v_title, v_rendered_body, v_announcement_id, clock_timestamp()
                );
            END IF;
        END LOOP;
    END IF;

    IF NOT v_dry_run AND v_announcement_id IS NOT NULL THEN
        UPDATE announcements SET recipient_count = v_count WHERE id = v_announcement_id;
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'dry_run', v_dry_run,
        'recipient_count', v_count,
        'announcement_id', v_announcement_id
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp;

GRANT EXECUTE ON FUNCTION create_announcement(jsonb) TO authenticated;


-- =============================================================================
-- 8. Reports & Views: Status Filters & Completed Students with Pending Fees
-- =============================================================================

-- 8.1. Report: Completed Students with Pending Fees
CREATE OR REPLACE FUNCTION report_completed_students_pending_fees(
    p_course_id bigint DEFAULT NULL,
    p_batch_id bigint DEFAULT NULL
)
RETURNS TABLE (
    student_id bigint,
    student_name text,
    admission_number text,
    registration_number text,
    phone text,
    course_name text,
    batch_name text,
    completed_on text,
    access_until text,
    total_fee_paise bigint,
    paid_amount_paise bigint,
    pending_amount_paise bigint,
    pending_amount numeric(12,2)
) AS $$
BEGIN
    IF NOT is_admin() THEN
        RAISE EXCEPTION 'Access denied. Administrator privilege required.';
    END IF;

    RETURN QUERY
    SELECT 
        s.id AS student_id,
        s.name AS student_name,
        coalesce(s.admission_number, 'N/A') AS admission_number,
        coalesce(s.registration_number, 'N/A') AS registration_number,
        coalesce(s.phone, 'N/A') AS phone,
        coalesce(c.name, 'N/A') AS course_name,
        coalesce(b.batch_name, 'N/A') AS batch_name,
        coalesce(to_char(s.completed_on, 'YYYY-MM-DD'), 'N/A') AS completed_on,
        coalesce(to_char(p.access_until, 'YYYY-MM-DD'), 'N/A') AS access_until,
        f.total_fee_paise,
        f.paid_amount_paise,
        f.pending_amount_paise,
        round(f.pending_amount_paise / 100.0, 2) AS pending_amount
    FROM students s
    JOIN fees f ON f.student_id = s.id AND f.deleted_at IS NULL
    LEFT JOIN profiles p ON p.student_id = s.id
    LEFT JOIN courses c ON c.id = s.course_id
    LEFT JOIN batches b ON b.id = s.batch_id
    WHERE s.deleted_at IS NULL
      AND s.status = 'completed'
      AND f.pending_amount_paise > 0
      AND (p_course_id IS NULL OR s.course_id = p_course_id)
      AND (p_batch_id IS NULL OR s.batch_id = p_batch_id)
    ORDER BY f.pending_amount_paise DESC, s.name ASC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE
SET search_path = public, pg_temp;

GRANT EXECUTE ON FUNCTION report_completed_students_pending_fees(bigint, bigint) TO authenticated;


-- 8.2. Update report_student_list with Status Filter
CREATE OR REPLACE FUNCTION report_student_list(
    p_course_id bigint DEFAULT NULL,
    p_batch_id bigint DEFAULT NULL,
    p_status text DEFAULT NULL
)
RETURNS TABLE (
    id bigint,
    name text,
    admission_number text,
    registration_number text,
    phone text,
    gender text,
    course_name text,
    batch_name text,
    admission_date text,
    status text,
    completed_on text
) AS $$
BEGIN
    IF NOT is_admin() THEN
        RAISE EXCEPTION 'Access denied. Administrator privilege required.';
    END IF;

    RETURN QUERY
    SELECT 
        s.id,
        s.name,
        coalesce(s.admission_number, 'N/A') AS admission_number,
        coalesce(s.registration_number, 'N/A') AS registration_number,
        coalesce(s.phone, 'N/A') AS phone,
        coalesce(s.gender, 'N/A') AS gender,
        coalesce(c.name, 'N/A') AS course_name,
        coalesce(b.batch_name, 'N/A') AS batch_name,
        coalesce(to_char(s.admission_date, 'YYYY-MM-DD'), 'N/A') AS admission_date,
        s.status::text AS status,
        coalesce(to_char(s.completed_on, 'YYYY-MM-DD'), '-') AS completed_on
    FROM students s
    LEFT JOIN courses c ON s.course_id = c.id
    LEFT JOIN batches b ON s.batch_id = b.id
    WHERE s.deleted_at IS NULL
      AND (p_course_id IS NULL OR s.course_id = p_course_id)
      AND (p_batch_id IS NULL OR s.batch_id = p_batch_id)
      AND (
          p_status IS NULL 
          OR p_status = 'all' 
          OR s.status::text = p_status
      )
    ORDER BY s.name ASC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE
SET search_path = public, pg_temp;

GRANT EXECUTE ON FUNCTION report_student_list(bigint, bigint, text) TO authenticated;


-- 8.3. Dashboard Stats RPC: Active vs Completed Students & Batches
CREATE OR REPLACE FUNCTION get_dashboard_summary_counts()
RETURNS jsonb AS $$
DECLARE
    v_active_students int := 0;
    v_completed_students int := 0;
    v_discontinued_students int := 0;
    v_tc_issued_students int := 0;
    v_active_batches int := 0;
    v_completed_batches int := 0;
    v_total_courses int := 0;
BEGIN
    SELECT 
        count(*) FILTER (WHERE status = 'active'),
        count(*) FILTER (WHERE status = 'completed'),
        count(*) FILTER (WHERE status = 'discontinued'),
        count(*) FILTER (WHERE status = 'tc_issued')
    INTO 
        v_active_students,
        v_completed_students,
        v_discontinued_students,
        v_tc_issued_students
    FROM students
    WHERE deleted_at IS NULL;

    SELECT 
        count(*) FILTER (WHERE status = 'active'),
        count(*) FILTER (WHERE status = 'completed')
    INTO 
        v_active_batches,
        v_completed_batches
    FROM batches
    WHERE deleted_at IS NULL;

    SELECT count(*) INTO v_total_courses
    FROM courses
    WHERE deleted_at IS NULL;

    RETURN jsonb_build_object(
        'active_students', v_active_students,
        'completed_students', v_completed_students,
        'discontinued_students', v_discontinued_students,
        'tc_issued_students', v_tc_issued_students,
        'active_batches', v_active_batches,
        'completed_batches', v_completed_batches,
        'total_courses', v_total_courses
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE
SET search_path = public, pg_temp;

GRANT EXECUTE ON FUNCTION get_dashboard_summary_counts() TO authenticated;


-- 8.4. student_profile_view View Update (Include completed_on and access_until)
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
    s.status::text AS status,
    s.completed_on,
    p.access_until,
    s.course_id,
    c.name AS course_name,
    c.code AS course_code,
    s.batch_id,
    b.batch_name,
    b.status AS batch_status,
    s.university_id,
    u.name AS university_name,
    s.academic_year_id,
    ay.year_name AS academic_year
FROM students s
LEFT JOIN profiles p ON p.student_id = s.id
LEFT JOIN courses c ON c.id = s.course_id
LEFT JOIN batches b ON b.id = s.batch_id
LEFT JOIN universities u ON u.id = s.university_id
LEFT JOIN academic_years ay ON ay.id = s.academic_year_id
WHERE s.deleted_at IS NULL
  AND (
      is_admin()
      OR (
          is_student() 
          AND student_access_allowed() 
          AND s.id = current_student_id()
      )
  );

GRANT SELECT ON student_profile_view TO authenticated;
