-- =============================================================================
-- MIPS ERP Database Migration: 0012_performance_indexes.sql
-- Sub-phase 7B: High-Volume Performance Optimization & Query Accelerators
-- =============================================================================

-- =============================================================================
-- 1. Payments Compatibility & Date Reporting Index
-- =============================================================================
-- Ensure backward and forward compatibility between 'date' and 'payment_date'
DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' AND table_name = 'payments' AND column_name = 'payment_date'
    ) THEN
        ALTER TABLE payments ADD COLUMN payment_date date GENERATED ALWAYS AS (date) STORED;
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_payments_date_report
    ON payments (date, is_cancelled, payment_mode)
    WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_payments_payment_date_report
    ON payments (payment_date, is_cancelled, payment_mode)
    WHERE deleted_at IS NULL;

-- =============================================================================
-- 2. High-Volume Attendance Aggregation Indexes
-- =============================================================================
-- Optimizes batch session counting across 6 months of attendance (7,000+ sessions)
CREATE INDEX IF NOT EXISTS idx_att_sessions_batch_date_status
    ON attendance_sessions (batch_id, date, status);

-- Covering composite index for student attendance summary calculation (150,000+ records)
CREATE INDEX IF NOT EXISTS idx_att_records_student_session_status
    ON attendance_records (student_id, session_id, status);

CREATE INDEX IF NOT EXISTS idx_att_records_session_status
    ON attendance_records (session_id, status);

-- =============================================================================
-- 3. Defaulter Reports & Fee Pending Fast Scans
-- =============================================================================
-- Partial index for instant defaulter list retrieval across 1,500 students
CREATE INDEX IF NOT EXISTS idx_fees_pending_defaulters
    ON fees (pending_amount_paise DESC, student_id)
    WHERE deleted_at IS NULL AND pending_amount_paise > 0;

CREATE INDEX IF NOT EXISTS idx_fee_items_student_pending
    ON fee_items (student_id, due_date)
    WHERE deleted_at IS NULL AND (amount_paise - paid_amount_paise) > 0;

CREATE INDEX IF NOT EXISTS idx_fee_items_batch_pending
    ON fee_items (enrollment_id, due_date)
    WHERE deleted_at IS NULL;

-- =============================================================================
-- 4. Exam Results, Mark Entry & Merit Ranking Indexes
-- =============================================================================
-- Optimizes merit list reports, ranking calculation, and portal results lookup
CREATE INDEX IF NOT EXISTS idx_results_exam_merit
    ON results (exam_id, status, rank, percentage DESC)
    WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_marks_exam_subject_student
    ON marks (exam_id, subject_id, student_id)
    WHERE deleted_at IS NULL;

-- =============================================================================
-- 5. Mass Login & Notification Dispatch Optimizations
-- =============================================================================
-- Accelerates 300 concurrent logins and instant profile resolution
CREATE INDEX IF NOT EXISTS idx_profiles_student_active
    ON profiles (student_id, active)
    WHERE role = 'student';

CREATE INDEX IF NOT EXISTS idx_profiles_teacher_active
    ON profiles (teacher_id, active)
    WHERE role = 'teacher';

-- Unread notification badge query accelerator
CREATE INDEX IF NOT EXISTS idx_notifications_user_unread
    ON notifications (user_id, read_at)
    WHERE read_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_notifications_recipient_unread
    ON notifications (recipient_type, recipient_id, read_at)
    WHERE read_at IS NULL;
