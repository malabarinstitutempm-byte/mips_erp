-- =============================================================================
-- Migration 0014: Primary Course Attendance & Open Faculty Access
-- =============================================================================
-- 1. Enforces attendance ONLY on PRIMARY course batches (Skill courses have no attendance)
-- 2. Removes teacher assignment concept: any active teacher can mark any primary batch
-- 3. Atomic & race-safe submit_attendance with advisory lock & ALREADY_MARKED error
-- 4. Creates attendance_slot_status(date) for faculty and admin dashboard boards
-- 5. Updates students_for_teacher view for all active primary batches (never DOB/phone/fees)
-- 6. Decouples RLS policies and functions from teacher_assignments
-- 7. Drops teacher_assignments table and teacher_has_assignment() function cleanly
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Validation Trigger: Attendance sessions ONLY for PRIMARY courses
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_enforce_primary_course_attendance()
RETURNS trigger AS $$
DECLARE
    v_course_type text;
BEGIN
    SELECT c.course_type INTO v_course_type
    FROM batches b
    JOIN courses c ON c.id = b.course_id
    WHERE b.id = NEW.batch_id AND b.deleted_at IS NULL;

    IF v_course_type IS NULL THEN
        RAISE EXCEPTION 'Batch ID % does not exist or has been deleted.', NEW.batch_id;
    END IF;

    IF v_course_type != 'primary' THEN
        RAISE EXCEPTION 'Attendance can only be tracked for PRIMARY course batches. Skill courses do not track attendance.'
            USING ERRCODE = '23514'; -- check_violation
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_attendance_sessions_primary_only ON attendance_sessions;
CREATE TRIGGER trg_attendance_sessions_primary_only
    BEFORE INSERT OR UPDATE OF batch_id ON attendance_sessions
    FOR EACH ROW
    EXECUTE FUNCTION trg_enforce_primary_course_attendance();


-- -----------------------------------------------------------------------------
-- 2. student_attendance_summary: PRIMARY Enrollment Only
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION student_attendance_summary(
    p_student_id bigint, 
    p_enrollment_id bigint DEFAULT NULL
)
RETURNS TABLE (
    student_id bigint,
    enrollment_id bigint,
    sessions_held int,
    present_count int,
    late_count int,
    absent_count int,
    leave_count int,
    weighted_present numeric(10,2),
    percentage numeric(5,2),
    status_band text,
    can_miss_more int,
    recover_sessions int,
    absent_impact_pct numeric(5,2),
    late_impact_pct numeric(5,2)
) AS $$
DECLARE
    v_enr_id bigint;
    v_batch_id bigint;
    v_enrolled_on date;
    v_min_pct numeric := 75.0;
    v_rem_pct numeric := 80.0;
    v_late_wt numeric := 0.5;
    v_leave_mode text := 'excluded';
    v_setting text;

    v_total_held int := 0;
    v_present int := 0;
    v_late int := 0;
    v_absent int := 0;
    v_leave int := 0;
    v_effective_held int := 0;
    v_weighted numeric(10,2) := 0.0;
    v_pct numeric(5,2) := 100.0;
    v_band text := 'ok';
    v_miss int := 0;
    v_recover int := 0;
    v_absent_impact numeric(5,2) := 0.0;
    v_late_impact numeric(5,2) := 0.0;
BEGIN
    -- Security guard: Students can only view their own summary
    IF is_student() AND p_student_id != current_student_id() THEN
        RAISE EXCEPTION 'Access denied. You can only view your own attendance summary.';
    END IF;

    -- Load institutional settings
    SELECT value INTO v_setting FROM settings WHERE key = 'min_attendance_percent';
    IF v_setting IS NOT NULL THEN v_min_pct := v_setting::numeric; END IF;

    SELECT value INTO v_setting FROM settings WHERE key = 'reminder_attendance_percent';
    IF v_setting IS NOT NULL THEN v_rem_pct := v_setting::numeric; END IF;

    SELECT value INTO v_setting FROM settings WHERE key = 'late_weight';
    IF v_setting IS NOT NULL THEN v_late_wt := v_setting::numeric; END IF;

    SELECT value INTO v_setting FROM settings WHERE key = 'leave_handling';
    IF v_setting IS NOT NULL THEN v_leave_mode := lower(trim(v_setting)); END IF;

    -- Always resolve student's PRIMARY enrollment (Skill courses have no attendance)
    SELECT se.id, se.batch_id, se.enrolled_on
    INTO v_enr_id, v_batch_id, v_enrolled_on
    FROM student_enrollments se
    JOIN batches b ON b.id = se.batch_id
    JOIN courses c ON c.id = b.course_id
    WHERE se.student_id = p_student_id 
      AND (se.kind = 'primary' OR c.course_type = 'primary')
      AND se.status = 'active'
      AND se.deleted_at IS NULL
    ORDER BY se.id DESC LIMIT 1;

    -- Fallback to master record batch if primary enrollment table record not populated
    IF v_batch_id IS NULL THEN
        SELECT s.batch_id, coalesce(s.admission_date, CURRENT_DATE)
        INTO v_batch_id, v_enrolled_on
        FROM students s
        JOIN batches b ON b.id = s.batch_id
        JOIN courses c ON c.id = b.course_id
        WHERE s.id = p_student_id AND c.course_type = 'primary';
    END IF;

    IF v_batch_id IS NULL THEN
        RETURN;
    END IF;

    -- Count submitted primary sessions held for this batch since enrolled_on
    SELECT count(*)::int INTO v_total_held
    FROM attendance_sessions s
    JOIN batches b ON b.id = s.batch_id
    JOIN courses c ON c.id = b.course_id
    WHERE s.batch_id = v_batch_id
      AND c.course_type = 'primary'
      AND s.date >= v_enrolled_on
      AND s.status IN ('submitted', 'locked');

    -- Tally student attendance records
    SELECT 
        count(*) FILTER (WHERE ar.status = 'present')::int,
        count(*) FILTER (WHERE ar.status = 'late')::int,
        count(*) FILTER (WHERE ar.status = 'absent')::int,
        count(*) FILTER (WHERE ar.status = 'leave')::int
    INTO v_present, v_late, v_absent, v_leave
    FROM attendance_records ar
    JOIN attendance_sessions s ON s.id = ar.session_id
    JOIN batches b ON b.id = s.batch_id
    JOIN courses c ON c.id = b.course_id
    WHERE ar.student_id = p_student_id
      AND s.batch_id = v_batch_id
      AND c.course_type = 'primary'
      AND s.date >= v_enrolled_on
      AND s.status IN ('submitted', 'locked');

    -- Effective sessions calculation based on leave handling
    IF v_leave_mode = 'counted_present' THEN
        v_effective_held := v_total_held;
        v_weighted := v_present + v_leave + (v_late * v_late_wt);
    ELSIF v_leave_mode = 'counted_absent' THEN
        v_effective_held := v_total_held;
        v_weighted := v_present + (v_late * v_late_wt);
    ELSE
        -- Default: excluded
        v_effective_held := GREATEST(0, v_total_held - v_leave);
        v_weighted := v_present + (v_late * v_late_wt);
    END IF;

    IF v_effective_held > 0 THEN
        v_pct := round((v_weighted / v_effective_held::numeric) * 100.0, 2);
    ELSE
        v_pct := 100.0;
    END IF;

    -- Determine band
    IF v_pct < v_min_pct THEN
        v_band := 'shortage';
    ELSIF v_pct < v_rem_pct THEN
        v_band := 'low';
    ELSE
        v_band := 'ok';
    END IF;

    -- Calculate can_miss_more & recover_sessions
    IF v_effective_held > 0 THEN
        IF v_pct >= v_min_pct THEN
            v_miss := floor((v_weighted - (v_min_pct / 100.0) * v_effective_held) / (v_min_pct / 100.0))::int;
            v_miss := GREATEST(0, v_miss);
            v_recover := 0;
        ELSE
            v_miss := 0;
            v_recover := ceil(((v_min_pct / 100.0) * v_effective_held - v_weighted) / (1.0 - (v_min_pct / 100.0)))::int;
            v_recover := GREATEST(1, v_recover);
        END IF;

        v_absent_impact := round((1.0 / (v_effective_held + 1)::numeric) * 100.0, 2);
        v_late_impact := round(((1.0 - v_late_wt) / (v_effective_held + 1)::numeric) * 100.0, 2);
    END IF;

    RETURN QUERY SELECT
        p_student_id,
        v_enr_id,
        v_effective_held,
        v_present,
        v_late,
        v_absent,
        v_leave,
        v_weighted,
        v_pct,
        v_band,
        v_miss,
        v_recover,
        v_absent_impact,
        v_late_impact;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE
SET search_path = public, pg_temp;


-- -----------------------------------------------------------------------------
-- 3. list_unmarked_slots: Filter PRIMARY Course Batches Only
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION list_unmarked_slots(
    p_date date DEFAULT CURRENT_DATE
)
RETURNS TABLE (
    batch_id bigint,
    batch_name text,
    course_id bigint,
    course_name text,
    date date,
    slot attendance_slot,
    status text
) AS $$
BEGIN
    IF NOT is_admin() AND NOT is_teacher() THEN
        RAISE EXCEPTION 'Access denied. Only registered administrators or teachers can list unmarked slots.';
    END IF;

    RETURN QUERY
    WITH active_primary_batches AS (
        SELECT b.id AS b_id, b.batch_name AS b_name, c.id AS c_id, c.name AS c_name
        FROM batches b
        JOIN courses c ON c.id = b.course_id
        WHERE b.deleted_at IS NULL 
          AND b.status = 'active'
          AND c.course_type = 'primary'
    ),
    required_slots AS (
        SELECT 'morning'::attendance_slot AS slot_val
        UNION ALL
        SELECT 'evening'::attendance_slot AS slot_val
    )
    SELECT 
        ab.b_id AS batch_id,
        ab.b_name AS batch_name,
        ab.c_id AS course_id,
        ab.c_name AS course_name,
        p_date AS date,
        rs.slot_val AS slot,
        'unmarked'::text AS status
    FROM active_primary_batches ab
    CROSS JOIN required_slots rs
    WHERE NOT EXISTS (
        SELECT 1 FROM attendance_sessions s
        WHERE s.batch_id = ab.b_id 
          AND s.date = p_date 
          AND s.slot = rs.slot_val
          AND s.status IN ('submitted', 'locked', 'no_class')
    )
    ORDER BY ab.c_name, ab.b_name, rs.slot_val;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE
SET search_path = public, pg_temp;


-- -----------------------------------------------------------------------------
-- 4. Atomic, Race-Safe submit_attendance with Advisory Lock
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS submit_attendance(bigint, jsonb);
DROP FUNCTION IF EXISTS submit_attendance(bigint, date, attendance_slot, jsonb, boolean, text);

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

        -- Verify teacher account is active
        IF NOT EXISTS (SELECT 1 FROM teachers WHERE id = v_teacher_id AND status = 'active') THEN
            RAISE EXCEPTION 'Your teacher account is deactivated. Contact the administrator.';
        END IF;

        -- Date window validation (default 24h)
        SELECT value INTO v_setting_window FROM settings WHERE key = 'teacher_attendance_edit_window_hours';
        IF v_setting_window IS NOT NULL AND v_setting_window ~ '^\d+$' THEN
            v_window_hours := v_setting_window::int;
        END IF;

        IF p_date < (CURRENT_DATE - (v_window_hours / 24)::int) OR p_date > CURRENT_DATE THEN
            RAISE EXCEPTION 'Attendance date % is outside the allowed submission window (% days).', p_date, ceil(v_window_hours / 24.0)::int;
        END IF;
    END IF;

    -- 2. Validate primary course batch
    SELECT c.course_type INTO v_course_type
    FROM batches b
    JOIN courses c ON c.id = b.course_id
    WHERE b.id = p_batch_id AND b.deleted_at IS NULL AND b.status = 'active';

    IF v_course_type IS NULL THEN
        RAISE EXCEPTION 'Active batch ID % not found.', p_batch_id;
    END IF;

    IF v_course_type != 'primary' THEN
        RAISE EXCEPTION 'Attendance can only be submitted for primary course batches. Skill courses do not track attendance.'
            USING ERRCODE = '23514';
    END IF;

    -- 3. Acquire transaction-level advisory lock on (batch_id, date, slot)
    PERFORM pg_advisory_xact_lock(hashtext('mips_att_' || p_batch_id::text || '_' || p_date::text || '_' || p_slot::text));

    -- 4. Check existing session for this slot
    SELECT * INTO v_existing
    FROM attendance_sessions
    WHERE batch_id = p_batch_id AND date = p_date AND slot = p_slot
    FOR UPDATE;

    IF FOUND AND v_existing.status IN ('submitted', 'locked', 'no_class') THEN
        -- Resolve who marked it
        IF v_existing.marked_by IS NOT NULL THEN
            SELECT name INTO v_marker_name FROM teachers WHERE id = v_existing.marked_by;
            v_marker_role := 'teacher';
        END IF;

        IF v_marker_name IS NULL THEN
            v_marker_name := 'Administrator';
            v_marker_role := 'admin';
        END IF;

        -- Return clear error code ALREADY_MARKED with teacher name, role, time
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

    -- 5. Atomic Insertion / Finalization
    IF p_no_class THEN
        INSERT INTO attendance_sessions (
            batch_id,
            date,
            slot,
            status,
            marked_by,
            no_class_reason,
            submitted_at,
            created_at,
            updated_at
        ) VALUES (
            p_batch_id,
            p_date,
            p_slot,
            'no_class',
            v_teacher_id,
            coalesce(trim(p_no_class_reason), 'No class held'),
            clock_timestamp(),
            clock_timestamp(),
            clock_timestamp()
        )
        ON CONFLICT (batch_id, date, slot)
        DO UPDATE SET
            status = 'no_class',
            marked_by = coalesce(v_teacher_id, attendance_sessions.marked_by),
            no_class_reason = EXCLUDED.no_class_reason,
            submitted_at = clock_timestamp(),
            updated_at = clock_timestamp()
        RETURNING id INTO v_session_id;

        -- Delete any records if previously created
        DELETE FROM attendance_records WHERE session_id = v_session_id;
    ELSE
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
            'submitted',
            v_teacher_id,
            clock_timestamp(),
            clock_timestamp(),
            clock_timestamp()
        )
        ON CONFLICT (batch_id, date, slot)
        DO UPDATE SET
            status = 'submitted',
            marked_by = coalesce(v_teacher_id, attendance_sessions.marked_by),
            submitted_at = clock_timestamp(),
            updated_at = clock_timestamp()
        RETURNING id INTO v_session_id;

        -- Insert individual attendance records
        FOR v_item IN SELECT * FROM jsonb_array_elements(p_records)
        LOOP
            v_student_id := (v_item->>'student_id')::bigint;
            v_status := (lower(trim(v_item->>'status')))::attendance_status;
            v_remarks := trim(v_item->>'remarks');

            INSERT INTO attendance_records (
                session_id,
                student_id,
                status,
                remarks,
                created_at,
                updated_at
            ) VALUES (
                v_session_id,
                v_student_id,
                v_status,
                v_remarks,
                clock_timestamp(),
                clock_timestamp()
            )
            ON CONFLICT (session_id, student_id)
            DO UPDATE SET
                status = EXCLUDED.status,
                remarks = EXCLUDED.remarks,
                updated_at = clock_timestamp();

            v_count := v_count + 1;
        END LOOP;
    END IF;

    -- Audit log entry
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
            'records_marked', v_count,
            'marked_by_teacher_id', v_teacher_id
        ),
        auth.uid(),
        clock_timestamp()
    );

    -- Trigger automated attendance band evaluation for all students in this batch
    IF NOT p_no_class THEN
        PERFORM evaluate_attendance_bands(NULL, p_batch_id);
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'session_id', v_session_id,
        'status', CASE WHEN p_no_class THEN 'no_class' ELSE 'submitted' END,
        'records_marked', v_count
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp;




-- -----------------------------------------------------------------------------
-- 5. attendance_slot_status(date): Comprehensive Board for Faculty & Admin
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION attendance_slot_status(
    p_date date DEFAULT CURRENT_DATE
)
RETURNS TABLE (
    course_id bigint,
    course_name text,
    batch_id bigint,
    batch_name text,
    slot attendance_slot,
    state text,
    session_id bigint,
    marked_by text,
    marked_at timestamptz,
    no_class_reason text,
    date date
) AS $$
BEGIN
    -- Security guard: Accessible to all active teachers and administrators; NEVER students
    IF NOT is_admin() AND NOT is_teacher() THEN
        RAISE EXCEPTION 'Access denied. Only registered faculty and administrators may view slot statuses.';
    END IF;

    RETURN QUERY
    WITH active_primary_batches AS (
        SELECT b.id AS b_id, b.batch_name AS b_name, c.id AS c_id, c.name AS c_name
        FROM batches b
        JOIN courses c ON c.id = b.course_id
        WHERE b.deleted_at IS NULL 
          AND b.status = 'active'
          AND c.course_type = 'primary'
    ),
    required_slots AS (
        SELECT 'morning'::attendance_slot AS slot_val
        UNION ALL
        SELECT 'evening'::attendance_slot AS slot_val
    )
    SELECT 
        ab.c_id AS course_id,
        ab.c_name AS course_name,
        ab.b_id AS batch_id,
        ab.b_name AS batch_name,
        rs.slot_val AS slot,
        coalesce(s.status::text, 'not_marked') AS state,
        s.id AS session_id,
        coalesce(t.name, 'Admin') AS marked_by,
        s.submitted_at AS marked_at,
        s.no_class_reason,
        p_date AS date
    FROM active_primary_batches ab
    CROSS JOIN required_slots rs
    LEFT JOIN attendance_sessions s 
        ON s.batch_id = ab.b_id 
       AND s.date = p_date 
       AND s.slot = rs.slot_val
    LEFT JOIN teachers t ON t.id = s.marked_by
    ORDER BY ab.c_name, ab.b_name, rs.slot_val;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE
SET search_path = public, pg_temp;

GRANT EXECUTE ON FUNCTION attendance_slot_status(date) TO authenticated;


-- -----------------------------------------------------------------------------
-- 6. students_for_teacher View: Active Primary Batches Only (Never DOB/phone/fees)
-- -----------------------------------------------------------------------------
DROP VIEW IF EXISTS students_for_teacher CASCADE;
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
WHERE s.deleted_at IS NULL
  AND s.status = 'active'
  AND b.deleted_at IS NULL
  AND b.status = 'active'
  AND c.course_type = 'primary'
  AND (
      is_admin()
      OR is_teacher()
  );

GRANT SELECT ON students_for_teacher TO authenticated;


-- -----------------------------------------------------------------------------
-- 7. Update RLS Policies: Open Faculty Access on All Primary Batches
-- -----------------------------------------------------------------------------
-- Sessions: Teachers can read all primary sessions
DROP POLICY IF EXISTS p_attendance_sessions_teacher_select ON attendance_sessions;
CREATE POLICY p_attendance_sessions_teacher_select ON attendance_sessions
    FOR SELECT TO authenticated
    USING (
        is_teacher() 
        AND EXISTS (
            SELECT 1 FROM batches b
            JOIN courses c ON c.id = b.course_id
            WHERE b.id = attendance_sessions.batch_id
              AND c.course_type = 'primary'
        )
    );

-- Only Admin can update/delete/insert sessions; teachers cannot modify submitted sessions
DROP POLICY IF EXISTS p_attendance_sessions_teacher_insert ON attendance_sessions;
DROP POLICY IF EXISTS p_attendance_sessions_teacher_update ON attendance_sessions;
DROP POLICY IF EXISTS p_attendance_sessions_teacher_delete ON attendance_sessions;

-- Records: Teachers can read records for all primary sessions
DROP POLICY IF EXISTS p_attendance_records_teacher_select ON attendance_records;
CREATE POLICY p_attendance_records_teacher_select ON attendance_records
    FOR SELECT TO authenticated
    USING (
        is_teacher()
        AND EXISTS (
            SELECT 1 FROM attendance_sessions s
            JOIN batches b ON b.id = s.batch_id
            JOIN courses c ON c.id = b.course_id
            WHERE s.id = attendance_records.session_id
              AND c.course_type = 'primary'
        )
    );

DROP POLICY IF EXISTS p_attendance_records_teacher_insert ON attendance_records;
DROP POLICY IF EXISTS p_attendance_records_teacher_update ON attendance_records;
DROP POLICY IF EXISTS p_attendance_records_teacher_delete ON attendance_records;

-- Enrollments & Timetables: Open read access for all active teachers
DROP POLICY IF EXISTS p_student_enrollments_teacher_select ON student_enrollments;
CREATE POLICY p_student_enrollments_teacher_select ON student_enrollments
    FOR SELECT TO authenticated
    USING (is_teacher() AND deleted_at IS NULL);

DROP POLICY IF EXISTS p_timetables_teacher_select ON timetables;
CREATE POLICY p_timetables_teacher_select ON timetables
    FOR SELECT TO authenticated
    USING (is_teacher() AND deleted_at IS NULL);

DROP POLICY IF EXISTS p_timetable_entries_teacher_select ON timetable_entries;
CREATE POLICY p_timetable_entries_teacher_select ON timetable_entries
    FOR SELECT TO authenticated
    USING (is_teacher());


-- -----------------------------------------------------------------------------
-- 8. Drop Obsolete teacher_has_assignment() Function
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS teacher_has_assignment(bigint, bigint) CASCADE;


-- -----------------------------------------------------------------------------
-- 9. Update Database Export Function (Remove teacher_assignments table query)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION export_full_database()
RETURNS jsonb AS $$
BEGIN
    RETURN export_database_dump();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp;


-- -----------------------------------------------------------------------------
-- 10. Drop teacher_assignments Table Cleanly
DROP TABLE IF EXISTS teacher_assignments CASCADE;
