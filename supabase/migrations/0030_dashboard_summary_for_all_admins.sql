-- Migration 0030: Allow get_admin_dashboard_summary to be executed by anon and authenticated admins
CREATE OR REPLACE FUNCTION public.get_admin_dashboard_summary()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
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
    v_recent_students jsonb;
BEGIN
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
    SELECT coalesce((SELECT status = 'published' FROM public.daily_timetables WHERE date = v_today + 1 LIMIT 1), false) 
    INTO v_tomorrow_timetable_published;

    -- 6. Recent 5 Payments
    SELECT coalesce(jsonb_agg(to_jsonb(p)), '[]'::jsonb)
    INTO v_recent_payments
    FROM (
        SELECT pay.id, pay.payment_date, pay.amount_paise, pay.payment_mode, s.name as student_name, s.admission_number
        FROM public.payments pay
        JOIN public.students s ON s.id = pay.student_id
        WHERE pay.deleted_at IS NULL AND pay.is_cancelled = false
        ORDER BY pay.payment_date DESC, pay.created_at DESC
        LIMIT 5
    ) p;

    -- 7. Recent 5 Admitted Students
    SELECT coalesce(jsonb_agg(to_jsonb(s)), '[]'::jsonb)
    INTO v_recent_students
    FROM (
        SELECT stud.id, stud.name, stud.admission_number, stud.course_id, stud.created_at
        FROM public.students stud
        WHERE stud.deleted_at IS NULL AND stud.status = 'active'
        ORDER BY stud.created_at DESC
        LIMIT 5
    ) s;

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
        'tomorrow_timetable_published', coalesce(v_tomorrow_timetable_published, false),
        'recent_payments', v_recent_payments,
        'recent_students', v_recent_students
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_admin_dashboard_summary() TO anon, authenticated, service_role;
