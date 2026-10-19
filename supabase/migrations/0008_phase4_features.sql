-- =============================================================================
-- Migration: 0008_phase4_features.sql
-- Description: Phase 4 Features:
--   1. Morning/Evening Attendance Model & Percentage Calculation Engine
--   2. Skill Courses & Granular Fee Ledger with FIFO Payment Allocation
--   3. Administrative Announcements & Recipient Notifications
--   4. Weekly Timetable Publishing with Teacher Clash Detection
-- =============================================================================

-- =============================================================================
-- 1. Custom Enum Types
-- =============================================================================

DO $$ BEGIN
    CREATE TYPE course_type AS ENUM ('primary', 'skill');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE enrollment_kind AS ENUM ('primary', 'skill');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE enrollment_status AS ENUM ('active', 'completed', 'withdrawn');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE attendance_slot AS ENUM ('morning', 'evening');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

-- Add 'no_class' value to attendance_session_status enum
DO $$ BEGIN
    ALTER TYPE attendance_session_status ADD VALUE IF NOT EXISTS 'no_class';
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE announcement_category AS ENUM ('programme', 'exam', 'fee_reminder', 'timetable', 'general');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE announcement_audience AS ENUM ('all_students', 'course', 'batch', 'teachers', 'fee_defaulters');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE timetable_status AS ENUM ('draft', 'published', 'archived');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE recipient_type AS ENUM ('student', 'teacher', 'admin');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;


-- =============================================================================
-- 2. Alter Existing Tables
-- =============================================================================

-- 2.1. courses: add course_type
ALTER TABLE courses
    ADD COLUMN IF NOT EXISTS course_type course_type NOT NULL DEFAULT 'primary';

-- 2.2. attendance_sessions: convert from period/subject to slot-based
-- Drop old period/subject unique constraint
ALTER TABLE attendance_sessions
    DROP CONSTRAINT IF EXISTS attendance_sessions_batch_id_subject_id_date_period_key;

-- Make period and subject_id nullable as subject is optional and period is replaced by slot
ALTER TABLE attendance_sessions
    ALTER COLUMN period DROP NOT NULL,
    ALTER COLUMN subject_id DROP NOT NULL;

-- Add slot column
ALTER TABLE attendance_sessions
    ADD COLUMN IF NOT EXISTS slot attendance_slot NOT NULL DEFAULT 'morning';

-- Safe migration of existing sessions: map period 1-5 -> morning, 6-10 -> evening
UPDATE attendance_sessions
SET slot = CASE 
    WHEN period > 5 THEN 'evening'::attendance_slot 
    ELSE 'morning'::attendance_slot 
END
WHERE slot = 'morning' AND period IS NOT NULL;

-- Add UNIQUE (batch_id, date, slot) constraint
DO $$ BEGIN
    ALTER TABLE attendance_sessions
        ADD CONSTRAINT attendance_sessions_batch_date_slot_key UNIQUE (batch_id, date, slot);
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

-- 2.3. teacher_assignments: allow batch-level assignments without subject
ALTER TABLE teacher_assignments
    ALTER COLUMN subject_id DROP NOT NULL;

ALTER TABLE teacher_assignments
    DROP CONSTRAINT IF EXISTS teacher_assignments_teacher_id_batch_id_subject_id_key;

CREATE UNIQUE INDEX IF NOT EXISTS idx_teacher_assignments_batch_subject 
    ON teacher_assignments (teacher_id, batch_id, subject_id) 
    WHERE subject_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_teacher_assignments_batch_only 
    ON teacher_assignments (teacher_id, batch_id) 
    WHERE subject_id IS NULL;

-- 2.4. notifications: support pending/unregistered recipients
ALTER TABLE notifications
    ALTER COLUMN user_id DROP NOT NULL,
    ADD COLUMN IF NOT EXISTS recipient_type recipient_type NOT NULL DEFAULT 'student',
    ADD COLUMN IF NOT EXISTS recipient_id bigint,
    ADD COLUMN IF NOT EXISTS announcement_id bigint;

-- Backfill recipient_id / recipient_type for existing notifications where user_id is set
UPDATE notifications n
SET recipient_type = 'student'::recipient_type,
    recipient_id = s.id
FROM profiles p
JOIN students s ON s.id = p.student_id
WHERE n.user_id = p.user_id AND n.recipient_id IS NULL AND p.student_id IS NOT NULL;

UPDATE notifications n
SET recipient_type = 'teacher'::recipient_type,
    recipient_id = t.id
FROM profiles p
JOIN teachers t ON t.id = p.teacher_id
WHERE n.user_id = p.user_id AND n.recipient_id IS NULL AND p.teacher_id IS NOT NULL;

UPDATE notifications
SET recipient_type = 'admin'::recipient_type
WHERE recipient_id IS NULL;

CREATE INDEX IF NOT EXISTS idx_notifications_recipient 
    ON notifications (recipient_type, recipient_id, read_at);

CREATE INDEX IF NOT EXISTS idx_notifications_announcement 
    ON notifications (announcement_id);

-- 2.5. settings: seed Phase 4 defaults
INSERT INTO settings (key, value, description) VALUES
    ('min_attendance_percent', '75', 'Minimum percentage required to avoid shortage warning'),
    ('reminder_attendance_percent', '80', 'Percentage below which low attendance reminder is shown'),
    ('late_weight', '0.5', 'Weight multiplier for late attendance in percentage calculation (0.0 to 1.0)'),
    ('leave_handling', 'excluded', 'Handling of approved leave: excluded (default), absent, or present')
ON CONFLICT (key) DO NOTHING;


-- =============================================================================
-- 3. New Tables
-- =============================================================================

-- 3.1. student_enrollments (Tracks Primary and Optional Skill Courses)
CREATE TABLE IF NOT EXISTS student_enrollments (
    id bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    student_id bigint NOT NULL REFERENCES students(id) ON DELETE CASCADE,
    course_id bigint NOT NULL REFERENCES courses(id) ON DELETE RESTRICT,
    batch_id bigint NOT NULL REFERENCES batches(id) ON DELETE RESTRICT,
    kind enrollment_kind NOT NULL DEFAULT 'primary',
    enrolled_on date NOT NULL DEFAULT CURRENT_DATE,
    status enrollment_status NOT NULL DEFAULT 'active',
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    deleted_at timestamptz,
    deleted_by uuid REFERENCES auth.users(id)
);

CREATE TRIGGER trg_student_enrollments_updated_at
BEFORE UPDATE ON student_enrollments
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_audit_student_enrollments
AFTER INSERT OR UPDATE OR DELETE ON student_enrollments
FOR EACH ROW EXECUTE FUNCTION audit_log_trigger();

-- Enforce at most ONE active primary and at most ONE active skill enrollment per student
CREATE UNIQUE INDEX IF NOT EXISTS idx_student_single_active_primary 
    ON student_enrollments (student_id) 
    WHERE kind = 'primary' AND status = 'active' AND deleted_at IS NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_student_single_active_skill 
    ON student_enrollments (student_id) 
    WHERE kind = 'skill' AND status = 'active' AND deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_student_enrollments_batch 
    ON student_enrollments (batch_id, status) 
    WHERE deleted_at IS NULL;

-- Safe data migration: populate primary enrollments for all existing students
INSERT INTO student_enrollments (student_id, course_id, batch_id, kind, enrolled_on, status, created_at)
SELECT 
    s.id, 
    s.course_id, 
    s.batch_id, 
    'primary'::enrollment_kind, 
    coalesce(s.admission_date, CURRENT_DATE), 
    CASE WHEN s.status = 'active' THEN 'active'::enrollment_status ELSE 'withdrawn'::enrollment_status END,
    coalesce(s.created_at, clock_timestamp())
FROM students s
WHERE s.deleted_at IS NULL 
  AND s.course_id IS NOT NULL 
  AND s.batch_id IS NOT NULL
  AND NOT EXISTS (
      SELECT 1 FROM student_enrollments se 
      WHERE se.student_id = s.id AND se.kind = 'primary'
  );


-- 3.2. fee_items: Granular ledger items per student enrollment
CREATE TABLE IF NOT EXISTS fee_items (
    id bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    student_id bigint NOT NULL REFERENCES students(id) ON DELETE CASCADE,
    enrollment_id bigint REFERENCES student_enrollments(id) ON DELETE RESTRICT,
    label text NOT NULL,
    amount_paise bigint NOT NULL CHECK (amount_paise > 0),
    paid_amount_paise bigint NOT NULL DEFAULT 0 CHECK (paid_amount_paise >= 0),
    due_date date,
    status text NOT NULL DEFAULT 'unpaid' CHECK (status IN ('unpaid', 'partially_paid', 'paid')),
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    deleted_at timestamptz,
    deleted_by uuid REFERENCES auth.users(id)
);

CREATE TRIGGER trg_fee_items_updated_at
BEFORE UPDATE ON fee_items
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_audit_fee_items
AFTER INSERT OR UPDATE OR DELETE ON fee_items
FOR EACH ROW EXECUTE FUNCTION audit_log_trigger();

CREATE INDEX IF NOT EXISTS idx_fee_items_student 
    ON fee_items (student_id, status) 
    WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_fee_items_enrollment 
    ON fee_items (enrollment_id) 
    WHERE deleted_at IS NULL;

-- Safe data migration: migrate existing student fees into primary fee_items
INSERT INTO fee_items (student_id, enrollment_id, label, amount_paise, paid_amount_paise, due_date, status, created_at)
SELECT 
    f.student_id,
    se.id,
    coalesce(c.name, 'Primary Course') || ' - Tuition Fee',
    f.total_fee_paise,
    f.paid_amount_paise,
    coalesce(s.admission_date, CURRENT_DATE) + interval '30 days',
    CASE 
        WHEN f.pending_amount_paise = 0 AND f.total_fee_paise > 0 THEN 'paid'
        WHEN f.paid_amount_paise > 0 THEN 'partially_paid'
        ELSE 'unpaid'
    END,
    coalesce(f.created_at, clock_timestamp())
FROM fees f
JOIN students s ON s.id = f.student_id
LEFT JOIN student_enrollments se ON se.student_id = f.student_id AND se.kind = 'primary'
LEFT JOIN courses c ON c.id = se.course_id
WHERE f.deleted_at IS NULL 
  AND f.total_fee_paise > 0
  AND NOT EXISTS (
      SELECT 1 FROM fee_items fi WHERE fi.student_id = f.student_id
  );


-- 3.3. payment_allocations: links payment records to fee items
CREATE TABLE IF NOT EXISTS payment_allocations (
    id bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    payment_id bigint NOT NULL REFERENCES payments(id) ON DELETE CASCADE,
    fee_item_id bigint NOT NULL REFERENCES fee_items(id) ON DELETE RESTRICT,
    amount_paise bigint NOT NULL CHECK (amount_paise > 0),
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    UNIQUE (payment_id, fee_item_id)
);

CREATE INDEX IF NOT EXISTS idx_payment_allocations_item 
    ON payment_allocations (fee_item_id);

CREATE INDEX IF NOT EXISTS idx_payment_allocations_payment 
    ON payment_allocations (payment_id);

-- Safe data migration: allocate existing payments to existing fee items
INSERT INTO payment_allocations (payment_id, fee_item_id, amount_paise, created_at)
SELECT 
    p.id,
    fi.id,
    p.amount_paise,
    coalesce(p.created_at, clock_timestamp())
FROM payments p
JOIN fee_items fi ON fi.student_id = p.student_id
WHERE p.is_cancelled = false 
  AND p.deleted_at IS NULL
  AND NOT EXISTS (
      SELECT 1 FROM payment_allocations pa WHERE pa.payment_id = p.id
  );


-- 3.4. fee_adjustments: refunds and credit adjustments
CREATE TABLE IF NOT EXISTS fee_adjustments (
    id bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    student_id bigint NOT NULL REFERENCES students(id) ON DELETE CASCADE,
    enrollment_id bigint REFERENCES student_enrollments(id) ON DELETE RESTRICT,
    amount_paise bigint NOT NULL CHECK (amount_paise > 0),
    type text NOT NULL CHECK (type IN ('refund', 'credit')),
    reason text NOT NULL,
    created_by uuid NOT NULL REFERENCES auth.users(id),
    created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE TRIGGER trg_audit_fee_adjustments
AFTER INSERT OR UPDATE OR DELETE ON fee_adjustments
FOR EACH ROW EXECUTE FUNCTION audit_log_trigger();

CREATE INDEX IF NOT EXISTS idx_fee_adjustments_student 
    ON fee_adjustments (student_id);


-- 3.5. attendance_alert_state: prevents repeated notifications per band crossing
CREATE TABLE IF NOT EXISTS attendance_alert_state (
    student_id bigint NOT NULL REFERENCES students(id) ON DELETE CASCADE,
    enrollment_id bigint NOT NULL REFERENCES student_enrollments(id) ON DELETE CASCADE,
    last_band text NOT NULL DEFAULT 'ok' CHECK (last_band IN ('ok', 'low', 'shortage')),
    updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    PRIMARY KEY (student_id, enrollment_id)
);


-- 3.6. announcements: administrative broadcast messages
CREATE TABLE IF NOT EXISTS announcements (
    id bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    category announcement_category NOT NULL,
    title text NOT NULL,
    body text NOT NULL,
    audience_type announcement_audience NOT NULL,
    audience_ids jsonb NOT NULL DEFAULT '[]'::jsonb,
    min_balance_paise bigint NOT NULL DEFAULT 0,
    recipient_count int NOT NULL DEFAULT 0,
    created_by uuid NOT NULL REFERENCES auth.users(id),
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    retracted_at timestamptz,
    retracted_by uuid REFERENCES auth.users(id)
);

CREATE TRIGGER trg_audit_announcements
AFTER INSERT OR UPDATE OR DELETE ON announcements
FOR EACH ROW EXECUTE FUNCTION audit_log_trigger();

CREATE INDEX IF NOT EXISTS idx_announcements_created 
    ON announcements (created_at DESC);

-- Foreign key on notifications linking to announcements
ALTER TABLE notifications
    DROP CONSTRAINT IF EXISTS fk_notifications_announcement,
    ADD CONSTRAINT fk_notifications_announcement 
    FOREIGN KEY (announcement_id) REFERENCES announcements(id) ON DELETE SET NULL;


-- 3.7. timetables: weekly batch schedules
CREATE TABLE IF NOT EXISTS timetables (
    id bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    batch_id bigint NOT NULL REFERENCES batches(id) ON DELETE RESTRICT,
    title text NOT NULL,
    status timetable_status NOT NULL DEFAULT 'draft',
    effective_from date NOT NULL DEFAULT CURRENT_DATE,
    published_at timestamptz,
    published_by uuid REFERENCES auth.users(id),
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    deleted_at timestamptz,
    deleted_by uuid REFERENCES auth.users(id)
);

CREATE TRIGGER trg_timetables_updated_at
BEFORE UPDATE ON timetables
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_audit_timetables
AFTER INSERT OR UPDATE OR DELETE ON timetables
FOR EACH ROW EXECUTE FUNCTION audit_log_trigger();

CREATE INDEX IF NOT EXISTS idx_timetables_batch 
    ON timetables (batch_id, status) 
    WHERE deleted_at IS NULL;


-- 3.8. timetable_entries: individual day/slot entries
CREATE TABLE IF NOT EXISTS timetable_entries (
    id bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    timetable_id bigint NOT NULL REFERENCES timetables(id) ON DELETE CASCADE,
    weekday int NOT NULL CHECK (weekday >= 1 AND weekday <= 6),
    slot attendance_slot NOT NULL,
    start_time time NOT NULL,
    end_time time NOT NULL CHECK (end_time > start_time),
    subject_id bigint REFERENCES course_subjects(id) ON DELETE SET NULL,
    teacher_id bigint REFERENCES teachers(id) ON DELETE SET NULL,
    room text,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    UNIQUE (timetable_id, weekday, slot, start_time)
);

CREATE TRIGGER trg_timetable_entries_updated_at
BEFORE UPDATE ON timetable_entries
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE INDEX IF NOT EXISTS idx_timetable_entries_lookup 
    ON timetable_entries (timetable_id, weekday, slot);

CREATE INDEX IF NOT EXISTS idx_timetable_entries_teacher 
    ON timetable_entries (teacher_id, weekday);


-- =============================================================================
-- 4. Safeguard Triggers
-- =============================================================================

-- 4.1. Skill Course Withdrawal Safeguard:
-- Cannot withdraw or delete a skill course if payments have been allocated to it,
-- unless the admin records a refund or credit adjustment of at least that amount.
CREATE OR REPLACE FUNCTION check_skill_course_withdrawal()
RETURNS trigger AS $$
DECLARE
    v_allocated_paise bigint := 0;
    v_adjustments_paise bigint := 0;
BEGIN
    IF (TG_OP = 'UPDATE' AND NEW.status = 'withdrawn' AND OLD.status != 'withdrawn')
       OR (TG_OP = 'DELETE')
       OR (TG_OP = 'UPDATE' AND NEW.deleted_at IS NOT NULL AND OLD.deleted_at IS NULL) THEN
        
        IF OLD.kind = 'skill' THEN
            SELECT coalesce(sum(pa.amount_paise), 0) INTO v_allocated_paise
            FROM payment_allocations pa
            JOIN fee_items fi ON fi.id = pa.fee_item_id
            JOIN payments p ON p.id = pa.payment_id
            WHERE fi.enrollment_id = OLD.id
              AND p.is_cancelled = false
              AND p.deleted_at IS NULL;

            IF v_allocated_paise > 0 THEN
                SELECT coalesce(sum(amount_paise), 0) INTO v_adjustments_paise
                FROM fee_adjustments
                WHERE enrollment_id = OLD.id;

                IF v_adjustments_paise < v_allocated_paise THEN
                    RAISE EXCEPTION 'Cannot withdraw skill course (Enrollment ID %): % paise in payments are allocated to it. Admin must record a refund/credit adjustment of at least % paise first (recorded: % paise).',
                        OLD.id, v_allocated_paise, v_allocated_paise, v_adjustments_paise;
                END IF;
            END IF;
        END IF;
    END IF;
    RETURN coalesce(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_check_skill_course_withdrawal ON student_enrollments;
CREATE TRIGGER trg_check_skill_course_withdrawal
BEFORE UPDATE OR DELETE ON student_enrollments
FOR EACH ROW EXECUTE FUNCTION check_skill_course_withdrawal();


-- 4.2. Timetable Teacher Clash Prevention
CREATE OR REPLACE FUNCTION check_timetable_teacher_clash()
RETURNS trigger AS $$
DECLARE
    v_clash_info text;
    v_tt_status text;
BEGIN
    IF NEW.teacher_id IS NULL THEN
        RETURN NEW;
    END IF;

    SELECT status INTO v_tt_status FROM timetables WHERE id = NEW.timetable_id;
    IF v_tt_status != 'published' THEN
        RETURN NEW;
    END IF;

    SELECT format('Teacher ID %s is already scheduled on weekday %s (%s) from %s to %s in published timetable "%s" (Batch ID %s)',
                  t.name, e.weekday, e.slot, e.start_time, e.end_time, tt.title, tt.batch_id)
    INTO v_clash_info
    FROM timetable_entries e
    JOIN timetables tt ON tt.id = e.timetable_id
    JOIN teachers t ON t.id = NEW.teacher_id
    WHERE e.teacher_id = NEW.teacher_id
      AND e.weekday = NEW.weekday
      AND e.id != coalesce(NEW.id, 0)
      AND tt.status = 'published'
      AND tt.deleted_at IS NULL
      AND (NEW.start_time, NEW.end_time) OVERLAPS (e.start_time, e.end_time)
    LIMIT 1;

    IF v_clash_info IS NOT NULL THEN
        RAISE EXCEPTION 'Teacher Scheduling Conflict: %', v_clash_info;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_check_timetable_teacher_clash ON timetable_entries;
CREATE TRIGGER trg_check_timetable_teacher_clash
BEFORE INSERT OR UPDATE ON timetable_entries
FOR EACH ROW EXECUTE FUNCTION check_timetable_teacher_clash();


-- 4.3. Synchronize Legacy fees Table with fee_items
CREATE OR REPLACE FUNCTION sync_legacy_fees_from_items()
RETURNS trigger AS $$
DECLARE
    v_sid bigint;
    v_total bigint;
    v_paid bigint;
BEGIN
    v_sid := coalesce(NEW.student_id, OLD.student_id);

    SELECT 
        coalesce(sum(amount_paise), 0),
        coalesce(sum(paid_amount_paise), 0)
    INTO v_total, v_paid
    FROM fee_items
    WHERE student_id = v_sid AND deleted_at IS NULL;

    UPDATE fees
    SET total_fee_paise = v_total,
        paid_amount_paise = v_paid,
        pending_amount_paise = greatest(0, v_total - v_paid),
        updated_at = clock_timestamp()
    WHERE student_id = v_sid;

    RETURN coalesce(NEW, OLD);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_sync_legacy_fees ON fee_items;
CREATE TRIGGER trg_sync_legacy_fees
AFTER INSERT OR UPDATE OR DELETE ON fee_items
FOR EACH ROW EXECUTE FUNCTION sync_legacy_fees_from_items();


-- =============================================================================
-- 5. Views and Functions
-- =============================================================================

-- 5.1. student_fee_summary View
DROP VIEW IF EXISTS view_student_fee_summary CASCADE;
CREATE OR REPLACE VIEW view_student_fee_summary AS
SELECT 
    s.id AS student_id,
    s.admission_number,
    s.name AS student_name,
    coalesce(sum(fi.amount_paise), 0) AS total_fee_paise,
    coalesce(sum(fi.paid_amount_paise), 0) AS paid_amount_paise,
    coalesce(sum(fi.amount_paise - fi.paid_amount_paise), 0) AS pending_amount_paise,
    coalesce(sum(CASE WHEN se.kind = 'primary' THEN fi.amount_paise ELSE 0 END), 0) AS primary_fee_paise,
    coalesce(sum(CASE WHEN se.kind = 'primary' THEN fi.paid_amount_paise ELSE 0 END), 0) AS primary_paid_paise,
    coalesce(sum(CASE WHEN se.kind = 'primary' THEN fi.amount_paise - fi.paid_amount_paise ELSE 0 END), 0) AS primary_pending_paise,
    coalesce(sum(CASE WHEN se.kind = 'skill' THEN fi.amount_paise ELSE 0 END), 0) AS skill_fee_paise,
    coalesce(sum(CASE WHEN se.kind = 'skill' THEN fi.paid_amount_paise ELSE 0 END), 0) AS skill_paid_paise,
    coalesce(sum(CASE WHEN se.kind = 'skill' THEN fi.amount_paise - fi.paid_amount_paise ELSE 0 END), 0) AS skill_pending_paise
FROM students s
LEFT JOIN student_enrollments se ON se.student_id = s.id AND se.deleted_at IS NULL AND se.status = 'active'
LEFT JOIN fee_items fi ON fi.enrollment_id = se.id AND fi.deleted_at IS NULL
WHERE s.deleted_at IS NULL
GROUP BY s.id, s.admission_number, s.name;


-- 5.2. Update view_course_financial_summary to support course_type & skill courses
DROP VIEW IF EXISTS view_course_financial_summary CASCADE;
CREATE OR REPLACE VIEW view_course_financial_summary AS
SELECT 
    c.id AS course_id,
    c.name AS course_name,
    c.code AS course_code,
    c.course_type,
    count(DISTINCT se.student_id) AS total_students,
    coalesce(sum(fi.amount_paise), 0) AS total_revenue_paise,
    coalesce(sum(fi.paid_amount_paise), 0) AS total_collected_paise,
    coalesce(sum(fi.amount_paise - fi.paid_amount_paise), 0) AS total_pending_paise,
    round(coalesce(sum(fi.amount_paise), 0) / 100.0, 2) AS total_revenue_inr,
    round(coalesce(sum(fi.paid_amount_paise), 0) / 100.0, 2) AS total_collected_inr,
    round(coalesce(sum(fi.amount_paise - fi.paid_amount_paise), 0) / 100.0, 2) AS total_pending_inr
FROM courses c
LEFT JOIN student_enrollments se ON se.course_id = c.id AND se.deleted_at IS NULL AND se.status = 'active'
LEFT JOIN fee_items fi ON fi.enrollment_id = se.id AND fi.deleted_at IS NULL
WHERE c.deleted_at IS NULL
GROUP BY c.id, c.name, c.code, c.course_type;


-- 5.3. Update view_fee_defaulters to include skill course balances
DROP VIEW IF EXISTS view_fee_defaulters CASCADE;
CREATE OR REPLACE VIEW view_fee_defaulters AS
SELECT 
    s.id AS student_id,
    s.name AS student_name,
    coalesce(s.admission_number, 'N/A') AS admission_number,
    coalesce(s.phone, 'N/A') AS phone,
    s.course_id,
    s.batch_id,
    coalesce(c.name, 'N/A') AS course_name,
    coalesce(b.batch_name, 'N/A') AS batch_name,
    vfs.total_fee_paise,
    vfs.paid_amount_paise,
    vfs.pending_amount_paise,
    round(vfs.total_fee_paise / 100.0, 2) AS total_fee_inr,
    round(vfs.paid_amount_paise / 100.0, 2) AS paid_amount_inr,
    round(vfs.pending_amount_paise / 100.0, 2) AS pending_amount_inr
FROM view_student_fee_summary vfs
JOIN students s ON s.id = vfs.student_id
LEFT JOIN courses c ON c.id = s.course_id
LEFT JOIN batches b ON b.id = s.batch_id
WHERE vfs.pending_amount_paise > 0
  AND s.status = 'active'
  AND s.deleted_at IS NULL;


-- 5.4. student_attendance_summary function
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

    -- Load settings
    SELECT value INTO v_setting FROM settings WHERE key = 'min_attendance_percent';
    IF v_setting IS NOT NULL THEN v_min_pct := v_setting::numeric; END IF;

    SELECT value INTO v_setting FROM settings WHERE key = 'reminder_attendance_percent';
    IF v_setting IS NOT NULL THEN v_rem_pct := v_setting::numeric; END IF;

    SELECT value INTO v_setting FROM settings WHERE key = 'late_weight';
    IF v_setting IS NOT NULL THEN v_late_wt := v_setting::numeric; END IF;

    SELECT value INTO v_setting FROM settings WHERE key = 'leave_handling';
    IF v_setting IS NOT NULL THEN v_leave_mode := lower(trim(v_setting)); END IF;

    -- Determine enrollment
    IF p_enrollment_id IS NOT NULL THEN
        SELECT se.id, se.batch_id, se.enrolled_on
        INTO v_enr_id, v_batch_id, v_enrolled_on
        FROM student_enrollments se
        WHERE se.id = p_enrollment_id AND se.student_id = p_student_id AND se.deleted_at IS NULL;
    ELSE
        SELECT se.id, se.batch_id, se.enrolled_on
        INTO v_enr_id, v_batch_id, v_enrolled_on
        FROM student_enrollments se
        WHERE se.student_id = p_student_id AND se.kind = 'primary' AND se.deleted_at IS NULL AND se.status = 'active'
        ORDER BY se.id DESC LIMIT 1;
    END IF;

    IF v_batch_id IS NULL THEN
        -- Fallback to student master record
        SELECT s.batch_id, coalesce(s.admission_date, CURRENT_DATE)
        INTO v_batch_id, v_enrolled_on
        FROM students s WHERE s.id = p_student_id;
    END IF;

    IF v_batch_id IS NULL THEN
        RETURN;
    END IF;

    -- Count submitted sessions held for this batch since enrolled_on (excluding explicit no_class)
    SELECT count(*)::int INTO v_total_held
    FROM attendance_sessions s
    WHERE s.batch_id = v_batch_id
      AND s.date >= v_enrolled_on
      AND s.status IN ('submitted', 'locked');

    -- Aggregate student's marked records
    SELECT 
        count(*) FILTER (WHERE r.status = 'present')::int,
        count(*) FILTER (WHERE r.status = 'late')::int,
        count(*) FILTER (WHERE r.status = 'absent')::int,
        count(*) FILTER (WHERE r.status = 'leave')::int
    INTO v_present, v_late, v_absent, v_leave
    FROM attendance_records r
    JOIN attendance_sessions s ON s.id = r.session_id
    WHERE r.student_id = p_student_id
      AND s.batch_id = v_batch_id
      AND s.date >= v_enrolled_on
      AND s.status IN ('submitted', 'locked');

    -- Calculate effective sessions held based on leave handling
    IF v_leave_mode = 'excluded' THEN
        v_effective_held := greatest(0, v_total_held - v_leave);
    ELSE
        v_effective_held := v_total_held;
    END IF;

    -- Calculate weighted present
    IF v_leave_mode = 'present' THEN
        v_weighted := v_present + v_leave + (v_late * v_late_wt);
    ELSE
        v_weighted := v_present + (v_late * v_late_wt);
    END IF;

    -- Percentage calculation
    IF v_effective_held > 0 THEN
        v_pct := round((v_weighted / v_effective_held * 100.0), 2);
    ELSE
        v_pct := 100.0;
    END IF;

    -- Status Band
    IF v_pct > v_rem_pct THEN
        v_band := 'ok';
    ELSIF v_pct >= v_min_pct THEN
        v_band := 'low';
    ELSE
        v_band := 'shortage';
    END IF;

    -- can_miss_more: max sessions student can miss while staying >= min_pct
    IF v_min_pct > 0 AND v_pct >= v_min_pct THEN
        v_miss := greatest(0, floor(v_weighted / (v_min_pct / 100.0) - v_effective_held)::int);
    ELSE
        v_miss := 0;
    END IF;

    -- recover_sessions: consecutive full sessions needed to reach min_pct
    IF v_pct < v_min_pct AND v_min_pct < 100.0 THEN
        v_recover := ceil(((v_min_pct / 100.0 * v_effective_held) - v_weighted) / (1.0 - (v_min_pct / 100.0)))::int;
        IF v_recover < 0 THEN v_recover := 0; END IF;
    ELSE
        v_recover := 0;
    END IF;

    -- Impact of next absent or late session in percentage points
    IF v_effective_held > 0 THEN
        v_absent_impact := round(v_pct - (v_weighted / (v_effective_held + 1) * 100.0), 2);
        v_late_impact := round(v_pct - ((v_weighted + v_late_wt) / (v_effective_held + 1) * 100.0), 2);
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

GRANT EXECUTE ON FUNCTION student_attendance_summary(bigint, bigint) TO authenticated;


-- =============================================================================
-- 6. Row Level Security (RLS) Policies
-- =============================================================================

ALTER TABLE student_enrollments ENABLE ROW LEVEL SECURITY;
ALTER TABLE fee_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE payment_allocations ENABLE ROW LEVEL SECURITY;
ALTER TABLE fee_adjustments ENABLE ROW LEVEL SECURITY;
ALTER TABLE attendance_alert_state ENABLE ROW LEVEL SECURITY;
ALTER TABLE announcements ENABLE ROW LEVEL SECURITY;
ALTER TABLE timetables ENABLE ROW LEVEL SECURITY;
ALTER TABLE timetable_entries ENABLE ROW LEVEL SECURITY;

-- 6.1. student_enrollments
CREATE POLICY p_student_enrollments_admin ON student_enrollments
    FOR ALL TO authenticated
    USING (is_admin())
    WITH CHECK (is_admin());

CREATE POLICY p_student_enrollments_teacher_select ON student_enrollments
    FOR SELECT TO authenticated
    USING (
        is_teacher() 
        AND deleted_at IS NULL
        AND EXISTS (
            SELECT 1 FROM teacher_assignments ta 
            WHERE ta.teacher_id = current_teacher_id() 
              AND ta.batch_id = student_enrollments.batch_id 
              AND ta.active = true
        )
    );

CREATE POLICY p_student_enrollments_student_select ON student_enrollments
    FOR SELECT TO authenticated
    USING (
        is_student() 
        AND student_id = current_student_id() 
        AND deleted_at IS NULL
    );

-- 6.2. fee_items
CREATE POLICY p_fee_items_admin ON fee_items
    FOR ALL TO authenticated
    USING (is_admin())
    WITH CHECK (is_admin());

CREATE POLICY p_fee_items_student_select ON fee_items
    FOR SELECT TO authenticated
    USING (
        is_student() 
        AND student_id = current_student_id() 
        AND deleted_at IS NULL
    );

-- 6.3. payment_allocations
CREATE POLICY p_payment_allocations_admin ON payment_allocations
    FOR ALL TO authenticated
    USING (is_admin())
    WITH CHECK (is_admin());

CREATE POLICY p_payment_allocations_student_select ON payment_allocations
    FOR SELECT TO authenticated
    USING (
        is_student() 
        AND EXISTS (
            SELECT 1 FROM fee_items fi 
            WHERE fi.id = payment_allocations.fee_item_id 
              AND fi.student_id = current_student_id()
        )
    );

-- 6.4. fee_adjustments
CREATE POLICY p_fee_adjustments_admin ON fee_adjustments
    FOR ALL TO authenticated
    USING (is_admin())
    WITH CHECK (is_admin());

CREATE POLICY p_fee_adjustments_student_select ON fee_adjustments
    FOR SELECT TO authenticated
    USING (
        is_student() 
        AND student_id = current_student_id()
    );

-- 6.5. attendance_alert_state
CREATE POLICY p_attendance_alert_state_admin ON attendance_alert_state
    FOR ALL TO authenticated
    USING (is_admin())
    WITH CHECK (is_admin());

CREATE POLICY p_attendance_alert_state_student_select ON attendance_alert_state
    FOR SELECT TO authenticated
    USING (
        is_student() 
        AND student_id = current_student_id()
    );

-- 6.6. announcements
CREATE POLICY p_announcements_admin ON announcements
    FOR ALL TO authenticated
    USING (is_admin())
    WITH CHECK (is_admin());

CREATE POLICY p_announcements_user_select ON announcements
    FOR SELECT TO authenticated
    USING (retracted_at IS NULL);

-- 6.7. timetables
CREATE POLICY p_timetables_admin ON timetables
    FOR ALL TO authenticated
    USING (is_admin())
    WITH CHECK (is_admin());

CREATE POLICY p_timetables_teacher_select ON timetables
    FOR SELECT TO authenticated
    USING (
        is_teacher() 
        AND deleted_at IS NULL
        AND EXISTS (
            SELECT 1 FROM teacher_assignments ta 
            WHERE ta.teacher_id = current_teacher_id() 
              AND ta.batch_id = timetables.batch_id 
              AND ta.active = true
        )
    );

CREATE POLICY p_timetables_student_select ON timetables
    FOR SELECT TO authenticated
    USING (
        is_student() 
        AND status = 'published' 
        AND deleted_at IS NULL
        AND EXISTS (
            SELECT 1 FROM student_enrollments se 
            WHERE se.student_id = current_student_id() 
              AND se.batch_id = timetables.batch_id 
              AND se.status = 'active' 
              AND se.deleted_at IS NULL
        )
    );

-- 6.8. timetable_entries
CREATE POLICY p_timetable_entries_admin ON timetable_entries
    FOR ALL TO authenticated
    USING (is_admin())
    WITH CHECK (is_admin());

CREATE POLICY p_timetable_entries_teacher_select ON timetable_entries
    FOR SELECT TO authenticated
    USING (
        is_teacher() 
        AND (
            teacher_id = current_teacher_id()
            OR EXISTS (
                SELECT 1 FROM timetables t
                JOIN teacher_assignments ta ON ta.batch_id = t.batch_id
                WHERE t.id = timetable_entries.timetable_id
                  AND ta.teacher_id = current_teacher_id()
                  AND ta.active = true
            )
        )
    );

CREATE POLICY p_timetable_entries_student_select ON timetable_entries
    FOR SELECT TO authenticated
    USING (
        is_student() 
        AND EXISTS (
            SELECT 1 FROM timetables t
            JOIN student_enrollments se ON se.batch_id = t.batch_id
            WHERE t.id = timetable_entries.timetable_id
              AND t.status = 'published'
              AND t.deleted_at IS NULL
              AND se.student_id = current_student_id()
              AND se.status = 'active'
              AND se.deleted_at IS NULL
        )
    );

-- 6.9. Update notifications RLS for recipient_type and recipient_id
DROP POLICY IF EXISTS p_notifications_user_select ON notifications;
DROP POLICY IF EXISTS p_notifications_user_update ON notifications;

CREATE POLICY p_notifications_recipient_select ON notifications
    FOR SELECT TO authenticated
    USING (
        user_id = auth.uid()
        OR (recipient_type = 'student' AND recipient_id = current_student_id())
        OR (recipient_type = 'teacher' AND recipient_id = current_teacher_id())
        OR is_admin()
    );

CREATE POLICY p_notifications_recipient_update ON notifications
    FOR UPDATE TO authenticated
    USING (
        user_id = auth.uid()
        OR (recipient_type = 'student' AND recipient_id = current_student_id())
        OR (recipient_type = 'teacher' AND recipient_id = current_teacher_id())
        OR is_admin()
    )
    WITH CHECK (
        user_id = auth.uid()
        OR (recipient_type = 'student' AND recipient_id = current_student_id())
        OR (recipient_type = 'teacher' AND recipient_id = current_teacher_id())
        OR is_admin()
    );
