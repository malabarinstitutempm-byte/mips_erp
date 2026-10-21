-- supabase/migrations/0022_performance_and_cost_optimization.sql
-- Phase O2: Database Performance, Cost Optimization & Screen-Consolidated RPCs
-- Designed for Supabase Free Tier: minimizes request count, egress bandwidth, and latency.

-- =============================================================================
-- 1. Helper Functions: Ensure STABLE & Wrap in InitPlan Subqueries
-- =============================================================================

CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM public.profiles 
        WHERE profiles.user_id = (SELECT auth.uid()) 
          AND profiles.role = 'admin' 
          AND profiles.active = true
    );
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;

CREATE OR REPLACE FUNCTION public.is_teacher()
RETURNS boolean AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM public.profiles 
        WHERE profiles.user_id = (SELECT auth.uid()) 
          AND profiles.role = 'teacher' 
          AND profiles.active = true
    );
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;

CREATE OR REPLACE FUNCTION public.current_student_id()
RETURNS bigint AS $$
DECLARE
    v_id bigint;
BEGIN
    SELECT student_id INTO v_id
    FROM public.profiles
    WHERE user_id = (SELECT auth.uid()) AND role = 'student' AND active = true;
    RETURN v_id;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;

-- =============================================================================
-- 2. Incremental Period Attendance Summaries Table (Eliminate N+1)
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.student_period_attendance_summaries (
    student_id bigint NOT NULL REFERENCES public.students(id) ON DELETE CASCADE,
    enrollment_id bigint NOT NULL REFERENCES public.student_enrollments(id) ON DELETE CASCADE,
    period_no int NOT NULL DEFAULT 1,
    period_type text NOT NULL DEFAULT 'semester',
    sessions_held int NOT NULL DEFAULT 0,
    present_count int NOT NULL DEFAULT 0,
    late_count int NOT NULL DEFAULT 0,
    absent_count int NOT NULL DEFAULT 0,
    leave_count int NOT NULL DEFAULT 0,
    percentage numeric(5,2) NOT NULL DEFAULT 100.0,
    status_band text NOT NULL DEFAULT 'ok',
    updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    PRIMARY KEY (student_id, enrollment_id, period_no)
);

CREATE INDEX IF NOT EXISTS idx_period_att_sum_lookup
    ON public.student_period_attendance_summaries (period_no, status_band);

ALTER TABLE public.student_period_attendance_summaries ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS p_period_att_sum_read ON public.student_period_attendance_summaries;
CREATE POLICY p_period_att_sum_read ON public.student_period_attendance_summaries
    FOR SELECT TO authenticated
    USING (
        (SELECT public.is_admin()) OR
        (SELECT public.is_teacher()) OR
        student_id = (SELECT public.current_student_id())
    );

-- Fast Incremental Recompute for a Single Student & Period
CREATE OR REPLACE FUNCTION public.recompute_student_period_summary(
    p_student_id bigint,
    p_enrollment_id bigint,
    p_period_no int
)
RETURNS void AS $$
DECLARE
    v_summary RECORD;
BEGIN
    SELECT * INTO v_summary
    FROM public.student_attendance_summary(p_student_id, p_enrollment_id, p_period_no);

    IF v_summary.student_id IS NOT NULL THEN
        INSERT INTO public.student_period_attendance_summaries (
            student_id, enrollment_id, period_no, period_type,
            sessions_held, present_count, late_count, absent_count, leave_count,
            percentage, status_band, updated_at
        ) VALUES (
            p_student_id, p_enrollment_id, p_period_no, coalesce(v_summary.period_type, 'semester'),
            coalesce(v_summary.sessions_held, 0),
            coalesce(v_summary.present_count, 0),
            coalesce(v_summary.late_count, 0),
            coalesce(v_summary.absent_count, 0),
            coalesce(v_summary.leave_count, 0),
            coalesce(v_summary.percentage, 100.0),
            coalesce(v_summary.status_band, 'ok'),
            clock_timestamp()
        )
        ON CONFLICT (student_id, enrollment_id, period_no) DO UPDATE SET
            sessions_held = EXCLUDED.sessions_held,
            present_count = EXCLUDED.present_count,
            late_count = EXCLUDED.late_count,
            absent_count = EXCLUDED.absent_count,
            leave_count = EXCLUDED.leave_count,
            percentage = EXCLUDED.percentage,
            status_band = EXCLUDED.status_band,
            updated_at = clock_timestamp();
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- Trigger to keep period summaries synced on attendance changes
CREATE OR REPLACE FUNCTION public.trg_sync_period_attendance_summary()
RETURNS trigger AS $$
DECLARE
    v_sess RECORD;
    v_enr_id bigint;
BEGIN
    SELECT batch_id, coalesce(period_no, semester_no, 1) as period_no
    INTO v_sess
    FROM public.attendance_sessions
    WHERE id = coalesce(NEW.session_id, OLD.session_id);

    IF v_sess.batch_id IS NOT NULL THEN
        SELECT id INTO v_enr_id
        FROM public.student_enrollments
        WHERE student_id = coalesce(NEW.student_id, OLD.student_id)
          AND batch_id = v_sess.batch_id
          AND status = 'active'
        LIMIT 1;

        IF v_enr_id IS NOT NULL THEN
            PERFORM public.recompute_student_period_summary(
                coalesce(NEW.student_id, OLD.student_id),
                v_enr_id,
                v_sess.period_no
            );
        END IF;
    END IF;

    RETURN coalesce(NEW, OLD);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DROP TRIGGER IF EXISTS trg_att_record_sync_summary ON public.attendance_records;
CREATE TRIGGER trg_att_record_sync_summary
    AFTER INSERT OR UPDATE OF status, remarks OR DELETE ON public.attendance_records
    FOR EACH ROW EXECUTE FUNCTION public.trg_sync_period_attendance_summary();

-- Set-based Fast Promotion Preview (Replaces N+1 Dynamic Loop)
CREATE OR REPLACE FUNCTION public.preview_semester_promotion(p_batch_id bigint)
RETURNS jsonb AS $$
DECLARE
    v_b RECORD;
    v_dur_years int;
    v_max_sem int;
    v_students jsonb;
    v_below_count int := 0;
    v_total_count int := 0;
BEGIN
    IF NOT (SELECT public.is_admin()) THEN
        RAISE EXCEPTION 'Access denied. Administrator privilege required to preview semester promotion.';
    END IF;

    SELECT b.*, c.name AS course_name, c.id AS c_id
    INTO v_b
    FROM public.batches b
    JOIN public.courses c ON c.id = b.course_id
    WHERE b.id = p_batch_id AND b.deleted_at IS NULL;

    IF v_b.id IS NULL THEN
        RAISE EXCEPTION 'Batch % not found.', p_batch_id;
    END IF;

    v_dur_years := public.course_duration_years(v_b.c_id);
    v_max_sem := v_dur_years * 2;

    -- Set-based read from student_period_attendance_summaries
    WITH batch_studs AS (
        SELECT s.id, s.name, s.admission_number, s.registration_number, se.id AS enr_id
        FROM public.students s
        JOIN public.student_enrollments se ON se.student_id = s.id AND se.batch_id = p_batch_id AND se.status = 'active'
        WHERE s.status = 'active' AND s.deleted_at IS NULL
    ),
    stud_summaries AS (
        SELECT 
            bs.id AS student_id,
            bs.name,
            bs.admission_number,
            bs.registration_number,
            coalesce(spas.sessions_held, 0) AS sessions_held,
            coalesce(spas.present_count + spas.late_count, 0) AS attended_count,
            coalesce(spas.percentage, 100.0) AS attendance_percentage,
            coalesce(spas.status_band, 'ok') AS status_band,
            (coalesce(spas.percentage, 100.0) < 75.0) AS below_minimum
        FROM batch_studs bs
        LEFT JOIN public.student_period_attendance_summaries spas
            ON spas.student_id = bs.id 
           AND spas.enrollment_id = bs.enr_id 
           AND spas.period_no = v_b.current_semester
    )
    SELECT 
        coalesce(jsonb_agg(to_jsonb(ss)), '[]'::jsonb),
        count(*)::int,
        count(*) FILTER (WHERE ss.below_minimum)::int
    INTO v_students, v_total_count, v_below_count
    FROM stud_summaries ss;

    RETURN jsonb_build_object(
        'batch_id', v_b.id,
        'batch_name', v_b.batch_name,
        'course_name', v_b.course_name,
        'current_semester', v_b.current_semester,
        'current_year', ceil(v_b.current_semester::numeric / 2.0)::int,
        'next_semester', v_b.current_semester + 1,
        'next_year', ceil((v_b.current_semester + 1)::numeric / 2.0)::int,
        'year_will_change', ceil((v_b.current_semester + 1)::numeric / 2.0)::int > ceil(v_b.current_semester::numeric / 2.0)::int,
        'course_duration_years', v_dur_years,
        'max_semesters', v_max_sem,
        'is_final_semester', v_b.current_semester >= v_max_sem,
        'total_active_students', v_total_count,
        'students_below_minimum', v_below_count,
        'students', v_students
    );
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;

-- =============================================================================
-- 3. Screen-Consolidated Unified RPCs
-- =============================================================================

-- RPC 1: Admin Dashboard Summary (Consolidates 6 HTTP requests into 1)
CREATE OR REPLACE FUNCTION public.get_admin_dashboard_summary()
RETURNS jsonb AS $$
DECLARE
    v_total_students int;
    v_total_courses int;
    v_total_batches int;
    v_total_fees bigint;
    v_collected_fees bigint;
    v_pending_fees bigint;
    v_upcoming_exams int;
    v_today date := (CURRENT_TIMESTAMP AT TIME ZONE 'Asia/Kolkata')::date;
    v_today_marked int := 0;
    v_today_unmarked int := 0;
    v_tomorrow_timetable_published boolean := false;
    v_recent_payments jsonb;
BEGIN
    IF NOT (SELECT public.is_admin()) THEN
        RAISE EXCEPTION 'Access denied. Administrator privileges required.';
    END IF;

    -- 1. Student, Course & Batch Counts
    SELECT count(*) INTO v_total_students FROM public.students WHERE deleted_at IS NULL AND status = 'active';
    SELECT count(*) INTO v_total_courses FROM public.courses WHERE deleted_at IS NULL;
    SELECT count(*) INTO v_total_batches FROM public.batches WHERE deleted_at IS NULL AND status = 'active';

    -- 2. Financial Ledger Metrics
    SELECT 
        coalesce(sum(total_fee_paise), 0),
        coalesce(sum(paid_amount_paise), 0),
        coalesce(sum(pending_amount_paise), 0)
    INTO v_total_fees, v_collected_fees, v_pending_fees
    FROM public.fees
    WHERE deleted_at IS NULL;

    -- 3. Upcoming Exams
    SELECT count(*) INTO v_upcoming_exams
    FROM public.exams
    WHERE deleted_at IS NULL AND status != 'published';

    -- 4. Today's Attendance Sessions Status
    SELECT 
        count(*) FILTER (WHERE status IN ('submitted', 'locked')),
        count(*) FILTER (WHERE status NOT IN ('submitted', 'locked'))
    INTO v_today_marked, v_today_unmarked
    FROM public.attendance_sessions
    WHERE date = v_today;

    -- 5. Tomorrow's Timetable Status
    SELECT coalesce(status = 'published', false) INTO v_tomorrow_timetable_published
    FROM public.daily_timetables
    WHERE date = v_today + 1;

    -- 6. Recent 5 Payments
    SELECT coalesce(jsonb_agg(to_jsonb(p)), '[]'::jsonb)
    INTO v_recent_payments
    FROM (
        SELECT pay.id, pay.payment_date, pay.amount_paise, pay.payment_mode, s.name as student_name, s.admission_number
        FROM public.payments pay
        JOIN public.students s ON s.id = pay.student_id
        WHERE pay.deleted_at IS NULL AND pay.is_cancelled = false
        ORDER BY pay.payment_date DESC, pay.id DESC
        LIMIT 5
    ) p;

    RETURN jsonb_build_object(
        'total_students', v_total_students,
        'total_courses', v_total_courses,
        'total_batches', v_total_batches,
        'total_fee_paise', v_total_fees,
        'collected_fee_paise', v_collected_fees,
        'pending_fee_paise', v_pending_fees,
        'upcoming_exams', v_upcoming_exams,
        'today_sessions_marked', v_today_marked,
        'today_sessions_unmarked', v_today_unmarked,
        'tomorrow_timetable_published', v_tomorrow_timetable_published,
        'recent_payments', v_recent_payments
    );
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;

-- RPC 2: Student Portal Overview (Initial Mount: consolidates profile, enrollments, unread count)
CREATE OR REPLACE FUNCTION public.get_student_portal_overview()
RETURNS jsonb AS $$
DECLARE
    v_uid uuid := (SELECT auth.uid());
    v_student_id bigint := (SELECT public.current_student_id());
    v_profile jsonb;
    v_enrollments jsonb;
    v_unread_count int := 0;
BEGIN
    -- 1. Student Profile
    SELECT to_jsonb(p) INTO v_profile
    FROM public.student_profile_view p
    WHERE p.id = v_student_id;

    IF v_profile IS NULL THEN
        -- Fallback if admin or lookup preview
        SELECT to_jsonb(p) INTO v_profile
        FROM public.student_profile_view p
        LIMIT 1;
        IF v_profile IS NOT NULL THEN
            v_student_id := (v_profile->>'id')::bigint;
        ELSE
            RETURN jsonb_build_object('error', 'Student profile not found');
        END IF;
    END IF;

    -- 2. Enrollments with Course Details
    SELECT coalesce(jsonb_agg(to_jsonb(e)), '[]'::jsonb) INTO v_enrollments
    FROM (
        SELECT 
            se.id as enrollment_id,
            se.course_id,
            c.name as course_name,
            c.code as course_code,
            se.kind as course_type,
            c.structure as course_structure,
            c.attendance_basis,
            public.course_duration_years(c.id) as duration_years,
            se.batch_id,
            b.batch_name,
            se.status,
            se.completed_on,
            b.current_semester,
            b.current_year
        FROM public.student_enrollments se
        JOIN public.courses c ON c.id = se.course_id
        JOIN public.batches b ON b.id = se.batch_id
        WHERE se.student_id = v_student_id
          AND se.deleted_at IS NULL
    ) e;

    -- 3. Unread Notifications Count
    SELECT count(*)::int INTO v_unread_count
    FROM public.notifications
    WHERE user_id = v_uid AND read_at IS NULL;

    RETURN jsonb_build_object(
        'profile', v_profile,
        'enrollments', v_enrollments,
        'unread_notifications_count', v_unread_count
    );
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;

-- RPC 3: Student Attendance Tab Unified Payload (Consolidates 5 queries into 1)
CREATE OR REPLACE FUNCTION public.get_student_attendance_payload(
    p_student_id bigint,
    p_enrollment_id bigint
)
RETURNS jsonb AS $$
DECLARE
    v_enr RECORD;
    v_periods jsonb;
    v_summaries jsonb;
    v_recent_records jsonb;
BEGIN
    SELECT se.*, b.id as b_id, b.batch_name
    INTO v_enr
    FROM public.student_enrollments se
    JOIN public.batches b ON b.id = se.batch_id
    WHERE se.id = p_enrollment_id AND se.student_id = p_student_id;

    IF v_enr.id IS NULL THEN
        RETURN jsonb_build_object('error', 'Enrollment not found');
    END IF;

    -- 1. Batch Periods (Semesters / Years)
    SELECT coalesce(jsonb_agg(to_jsonb(bp)), '[]'::jsonb) INTO v_periods
    FROM (
        SELECT period_no, period_type, start_date, end_date, status
        FROM public.batch_periods
        WHERE batch_id = v_enr.b_id
        ORDER BY period_no ASC
    ) bp;

    -- 2. Attendance Summaries per period (from cached table or dynamic fallback)
    SELECT coalesce(jsonb_agg(to_jsonb(s)), '[]'::jsonb) INTO v_summaries
    FROM (
        SELECT period_no, period_type, sessions_held, present_count, late_count, absent_count, leave_count, percentage, status_band
        FROM public.student_period_attendance_summaries
        WHERE student_id = p_student_id AND enrollment_id = p_enrollment_id
        ORDER BY period_no ASC
    ) s;

    -- 3. Recent 30 Attendance Session Records
    SELECT coalesce(jsonb_agg(to_jsonb(r)), '[]'::jsonb) INTO v_recent_records
    FROM (
        SELECT ar.id, ats.date, ats.slot, ar.status, ar.remarks
        FROM public.attendance_records ar
        JOIN public.attendance_sessions ats ON ats.id = ar.session_id
        WHERE ar.student_id = p_student_id AND ats.batch_id = v_enr.b_id
        ORDER BY ats.date DESC, ats.slot ASC
        LIMIT 30
    ) r;

    RETURN jsonb_build_object(
        'batch_id', v_enr.b_id,
        'batch_name', v_enr.batch_name,
        'periods', v_periods,
        'period_summaries', v_summaries,
        'recent_records', v_recent_records
    );
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;

-- RPC 4: Student Fees Tab Unified Payload (Consolidates 3 queries into 1)
CREATE OR REPLACE FUNCTION public.get_student_fee_summary(p_student_id bigint)
RETURNS jsonb AS $$
DECLARE
    v_fee RECORD;
    v_items jsonb;
    v_payments jsonb;
BEGIN
    -- 1. Overall Fee Ledger
    SELECT total_fee_paise, paid_amount_paise, pending_amount_paise, updated_at
    INTO v_fee
    FROM public.fees
    WHERE student_id = p_student_id AND deleted_at IS NULL;

    -- 2. Fee Items Breakdown
    SELECT coalesce(jsonb_agg(to_jsonb(fi)), '[]'::jsonb) INTO v_items
    FROM (
        SELECT id, enrollment_id, label, amount_paise, paid_amount_paise, (amount_paise - paid_amount_paise) as pending_amount_paise, due_date, status
        FROM public.fee_items
        WHERE student_id = p_student_id AND deleted_at IS NULL
        ORDER BY due_date ASC NULLS LAST, id ASC
    ) fi;

    -- 3. Payment Receipts History
    SELECT coalesce(jsonb_agg(to_jsonb(p)), '[]'::jsonb) INTO v_payments
    FROM (
        SELECT pay.id, r.receipt_number, pay.payment_date, pay.amount_paise, pay.payment_mode, pay.reference_number
        FROM public.payments pay
        LEFT JOIN public.receipts r ON r.payment_id = pay.id
        WHERE pay.student_id = p_student_id AND pay.deleted_at IS NULL AND pay.is_cancelled = false
        ORDER BY pay.payment_date DESC, pay.id DESC
    ) p;

    RETURN jsonb_build_object(
        'total_fee_paise', coalesce(v_fee.total_fee_paise, 0),
        'paid_amount_paise', coalesce(v_fee.paid_amount_paise, 0),
        'pending_amount_paise', coalesce(v_fee.pending_amount_paise, 0),
        'last_updated', v_fee.updated_at,
        'items', v_items,
        'payments', v_payments
    );
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;

-- RPC 5: Teacher Today Board (Consolidates profile, sessions, timetable into 1)
CREATE OR REPLACE FUNCTION public.get_teacher_today_board()
RETURNS jsonb AS $$
DECLARE
    v_uid uuid := (SELECT auth.uid());
    v_teacher RECORD;
    v_today date := (CURRENT_TIMESTAMP AT TIME ZONE 'Asia/Kolkata')::date;
    v_sessions jsonb;
    v_tomorrow_classes jsonb;
BEGIN
    SELECT * INTO v_teacher
    FROM public.teachers
    WHERE user_id = v_uid AND status = 'active';

    IF v_teacher.id IS NULL THEN
        RETURN jsonb_build_object('error', 'Teacher not found');
    END IF;

    -- Today's Attendance Sessions
    SELECT coalesce(jsonb_agg(to_jsonb(s)), '[]'::jsonb) INTO v_sessions
    FROM (
        SELECT ats.id, ats.batch_id, b.batch_name, ats.slot, ats.status, ats.no_class_reason
        FROM public.attendance_sessions ats
        JOIN public.batches b ON b.id = ats.batch_id
        WHERE ats.date = v_today
        ORDER BY ats.slot ASC
    ) s;

    -- Tomorrow's Timetable Schedule for this teacher
    SELECT coalesce(jsonb_agg(to_jsonb(tt)), '[]'::jsonb) INTO v_tomorrow_classes
    FROM (
        SELECT dte.id, dte.course_name, dte.subject_name, dte.class_room, dte.start_time, dte.end_time, dte.year
        FROM public.daily_timetable_entries dte
        JOIN public.daily_timetables dt ON dt.id = dte.daily_timetable_id
        WHERE dt.date = v_today + 1 AND dt.status = 'published' AND dte.teacher_id = v_teacher.id
        ORDER BY dte.sort_order ASC
    ) tt;

    RETURN jsonb_build_object(
        'teacher_id', v_teacher.id,
        'name', v_teacher.name,
        'phone', v_teacher.phone,
        'today_sessions', v_sessions,
        'tomorrow_classes', v_tomorrow_classes
    );
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;

-- RPC 6: Daily Timetable Day Payload (Combines timetable header + entries in 1)
CREATE OR REPLACE FUNCTION public.get_timetable_day_payload(p_date date)
RETURNS jsonb AS $$
DECLARE
    v_tt RECORD;
    v_entries jsonb;
BEGIN
    SELECT * INTO v_tt
    FROM public.daily_timetables
    WHERE date = p_date;

    SELECT coalesce(jsonb_agg(to_jsonb(e)), '[]'::jsonb) INTO v_entries
    FROM (
        SELECT id, course_id, course_name, year, teacher_id, teacher_name, subject_id, subject_name, class_room, start_time, end_time, sort_order
        FROM public.daily_timetable_entries
        WHERE date = p_date
        ORDER BY sort_order ASC
    ) e;

    RETURN jsonb_build_object(
        'id', v_tt.id,
        'date', p_date,
        'status', coalesce(v_tt.status, 'not_created'),
        'published_at', v_tt.published_at,
        'notify_users', coalesce(v_tt.notify_users, true),
        'entries', v_entries
    );
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;

-- RPC 7: Admin Student List with Pagination (Consolidates count + rows + batch/course names in 1)
CREATE OR REPLACE FUNCTION public.get_admin_student_list(
    p_query text DEFAULT NULL,
    p_course_id bigint DEFAULT NULL,
    p_batch_id bigint DEFAULT NULL,
    p_status text DEFAULT 'active',
    p_limit int DEFAULT 25,
    p_offset int DEFAULT 0
)
RETURNS jsonb AS $$
DECLARE
    v_total_count int := 0;
    v_students jsonb;
    v_q text := trim(coalesce(p_query, ''));
BEGIN
    IF NOT (SELECT public.is_admin()) THEN
        RAISE EXCEPTION 'Access denied. Administrator privileges required.';
    END IF;

    -- Count query
    SELECT count(*)::int INTO v_total_count
    FROM public.students s
    WHERE s.deleted_at IS NULL
      AND (p_status IS NULL OR p_status = 'all' OR s.status::text = p_status)
      AND (p_course_id IS NULL OR s.course_id = p_course_id)
      AND (p_batch_id IS NULL OR s.batch_id = p_batch_id)
      AND (
          v_q = '' OR 
          s.name ILIKE ('%' || v_q || '%') OR 
          s.admission_number ILIKE ('%' || v_q || '%') OR 
          s.registration_number ILIKE ('%' || v_q || '%')
      );

    -- Rows query with joins
    SELECT coalesce(jsonb_agg(to_jsonb(r)), '[]'::jsonb) INTO v_students
    FROM (
        SELECT 
            s.id, s.name, s.admission_number, s.registration_number,
            s.course_id, c.name as course_name,
            s.batch_id, b.batch_name,
            s.status, s.phone, s.gender, s.dob, s.admission_date,
            s.profile_photo_path, s.profile_photo_thumb_path
        FROM public.students s
        LEFT JOIN public.courses c ON c.id = s.course_id
        LEFT JOIN public.batches b ON b.id = s.batch_id
        WHERE s.deleted_at IS NULL
          AND (p_status IS NULL OR p_status = 'all' OR s.status::text = p_status)
          AND (p_course_id IS NULL OR s.course_id = p_course_id)
          AND (p_batch_id IS NULL OR s.batch_id = p_batch_id)
          AND (
              v_q = '' OR 
              s.name ILIKE ('%' || v_q || '%') OR 
              s.admission_number ILIKE ('%' || v_q || '%') OR 
              s.registration_number ILIKE ('%' || v_q || '%')
          )
        ORDER BY s.admission_number ASC
        LIMIT p_limit OFFSET p_offset
    ) r;

    RETURN jsonb_build_object(
        'total_count', v_total_count,
        'students', v_students,
        'limit', p_limit,
        'offset', p_offset
    );
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;

-- =============================================================================
-- 4. Index Optimization & Pruning Redundant Indexes
-- =============================================================================

-- Drop duplicate indexes identified during baseline analysis
DROP INDEX IF EXISTS public.idx_receipts_payment; -- duplicate of receipts_payment_id_key
DROP INDEX IF EXISTS public.idx_receipts_number;  -- duplicate of receipts_receipt_number_key
DROP INDEX IF EXISTS public.idx_students_adm_no;  -- duplicate of students_admission_number_key

-- Add targeted partial and composite indexes for fast filtering
CREATE INDEX IF NOT EXISTS idx_fees_pending_sort
    ON public.fees (pending_amount_paise DESC)
    WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_students_active_list
    ON public.students (status, admission_number)
    WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_announcements_published_feed
    ON public.announcements (created_at DESC)
    WHERE retracted_at IS NULL;

-- =============================================================================
-- 5. Data Lifecycle: Automated Retention Purge (500 MB Budget Protection)
-- =============================================================================

CREATE OR REPLACE FUNCTION public.purge_stale_data()
RETURNS jsonb AS $$
DECLARE
    v_notif_purged int := 0;
    v_audit_purged int := 0;
    v_logins_purged int := 0;
    v_subs_purged int := 0;
BEGIN
    -- 1. Purge read notifications older than 90 days
    DELETE FROM public.notifications
    WHERE read_at IS NOT NULL AND created_at < NOW() - INTERVAL '90 days';
    GET DIAGNOSTICS v_notif_purged = ROW_COUNT;

    -- 2. Purge audit log entries older than 12 months (retained in offline JSON dumps)
    DELETE FROM public.audit_log
    WHERE created_at < NOW() - INTERVAL '12 months';
    GET DIAGNOSTICS v_audit_purged = ROW_COUNT;

    -- 3. Purge failed login attempts older than 30 days
    DELETE FROM public.login_attempts
    WHERE attempted_at < NOW() - INTERVAL '30 days';
    GET DIAGNOSTICS v_logins_purged = ROW_COUNT;

    -- 4. Clean up dead push subscriptions inactive for > 180 days
    DELETE FROM public.push_subscriptions
    WHERE created_at < NOW() - INTERVAL '180 days';
    GET DIAGNOSTICS v_subs_purged = ROW_COUNT;

    RETURN jsonb_build_object(
        'notifications_purged', v_notif_purged,
        'audit_log_purged', v_audit_purged,
        'login_attempts_purged', v_logins_purged,
        'push_subscriptions_purged', v_subs_purged
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- Schedule Daily Retention Purge Job at 03:00 IST (21:30 UTC)
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
        PERFORM cron.unschedule('daily-data-retention-purge')
        FROM cron.job WHERE jobname = 'daily-data-retention-purge';

        PERFORM cron.schedule(
            'daily-data-retention-purge',
            '30 21 * * *',
            'SELECT public.purge_stale_data();'
        );
    END IF;
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

-- =============================================================================
-- 6. Permissions Hardening
-- =============================================================================

REVOKE EXECUTE ON FUNCTION public.get_admin_dashboard_summary() FROM anon, PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_admin_student_list(text, bigint, bigint, text, int, int) FROM anon, PUBLIC;
REVOKE EXECUTE ON FUNCTION public.purge_stale_data() FROM anon, PUBLIC, authenticated;

GRANT EXECUTE ON FUNCTION public.get_admin_dashboard_summary() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_admin_student_list(text, bigint, bigint, text, int, int) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_student_portal_overview() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_student_attendance_payload(bigint, bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_student_fee_summary(bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_teacher_today_board() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_timetable_day_payload(date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.recompute_student_period_summary(bigint, bigint, int) TO authenticated;
