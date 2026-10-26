-- Migration 0034: Cross-User Visibility Layer via Realtime App Events (Phase D4)
CREATE TABLE IF NOT EXISTS public.app_events (
    id bigserial PRIMARY KEY,
    topic text NOT NULL,
    domain text NOT NULL,
    entity_id bigint,
    action text NOT NULL,
    actor_name text,
    metadata jsonb DEFAULT '{}'::jsonb,
    created_at timestamptz DEFAULT clock_timestamp()
);

CREATE INDEX IF NOT EXISTS idx_app_events_topic ON public.app_events(topic);
CREATE INDEX IF NOT EXISTS idx_app_events_created_at ON public.app_events(created_at DESC);

ALTER TABLE public.app_events ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "p_app_events_all" ON public.app_events;
CREATE POLICY "p_app_events_all" ON public.app_events FOR ALL TO anon, authenticated USING (true) WITH CHECK (true);

-- Ensure table is in supabase_realtime publication
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables 
        WHERE pubname = 'supabase_realtime' AND tablename = 'app_events'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.app_events;
    END IF;
END $$;

-- Helper to emit events
CREATE OR REPLACE FUNCTION public.emit_app_event(
    p_topic text,
    p_domain text,
    p_entity_id bigint,
    p_action text,
    p_actor_name text,
    p_metadata jsonb DEFAULT '{}'::jsonb
) RETURNS void AS $$
BEGIN
    INSERT INTO public.app_events (topic, domain, entity_id, action, actor_name, metadata, created_at)
    VALUES (p_topic, p_domain, p_entity_id, p_action, p_actor_name, p_metadata, clock_timestamp());
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 1. Trigger for Courses
CREATE OR REPLACE FUNCTION public.trg_emit_course_event() RETURNS trigger AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        PERFORM emit_app_event('admins', 'course', OLD.id, 'delete', 'Administrator', jsonb_build_object('name', OLD.name));
        PERFORM emit_app_event('teachers', 'course', OLD.id, 'delete', 'Administrator', jsonb_build_object('name', OLD.name));
        RETURN OLD;
    ELSE
        PERFORM emit_app_event('admins', 'course', NEW.id, lower(TG_OP), 'Administrator', jsonb_build_object('name', NEW.name));
        PERFORM emit_app_event('teachers', 'course', NEW.id, lower(TG_OP), 'Administrator', jsonb_build_object('name', NEW.name));
        RETURN NEW;
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_courses_realtime ON public.courses;
CREATE TRIGGER trg_courses_realtime AFTER INSERT OR UPDATE OR DELETE ON public.courses
FOR EACH ROW EXECUTE FUNCTION trg_emit_course_event();

-- 2. Trigger for Batches
CREATE OR REPLACE FUNCTION public.trg_emit_batch_event() RETURNS trigger AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        PERFORM emit_app_event('admins', 'batch', OLD.id, 'delete', 'Administrator', jsonb_build_object('name', OLD.batch_name));
        PERFORM emit_app_event('teachers', 'batch', OLD.id, 'delete', 'Administrator', jsonb_build_object('name', OLD.batch_name));
        PERFORM emit_app_event('batch:' || OLD.id::text, 'batch', OLD.id, 'delete', 'Administrator', jsonb_build_object('name', OLD.batch_name));
        RETURN OLD;
    ELSE
        PERFORM emit_app_event('admins', 'batch', NEW.id, lower(TG_OP), 'Administrator', jsonb_build_object('name', NEW.batch_name, 'status', NEW.status, 'current_semester', NEW.current_semester));
        PERFORM emit_app_event('teachers', 'batch', NEW.id, lower(TG_OP), 'Administrator', jsonb_build_object('name', NEW.batch_name, 'status', NEW.status, 'current_semester', NEW.current_semester));
        PERFORM emit_app_event('batch:' || NEW.id::text, 'batch', NEW.id, lower(TG_OP), 'Administrator', jsonb_build_object('name', NEW.batch_name, 'status', NEW.status, 'current_semester', NEW.current_semester));
        RETURN NEW;
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_batches_realtime ON public.batches;
CREATE TRIGGER trg_batches_realtime AFTER INSERT OR UPDATE OR DELETE ON public.batches
FOR EACH ROW EXECUTE FUNCTION trg_emit_batch_event();

-- 3. Trigger for Students
CREATE OR REPLACE FUNCTION public.trg_emit_student_event() RETURNS trigger AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        PERFORM emit_app_event('admins', 'student', OLD.id, 'delete', 'Administrator', jsonb_build_object('name', OLD.name, 'batch_id', OLD.batch_id));
        PERFORM emit_app_event('teachers', 'student', OLD.id, 'delete', 'Administrator', jsonb_build_object('name', OLD.name, 'batch_id', OLD.batch_id));
        PERFORM emit_app_event('student:' || OLD.id::text, 'student', OLD.id, 'delete', 'Administrator', jsonb_build_object('status', 'deleted'));
        IF OLD.batch_id IS NOT NULL THEN
            PERFORM emit_app_event('batch:' || OLD.batch_id::text, 'student', OLD.id, 'delete', 'Administrator', jsonb_build_object('name', OLD.name));
        END IF;
        RETURN OLD;
    ELSE
        PERFORM emit_app_event('admins', 'student', NEW.id, lower(TG_OP), 'Administrator', jsonb_build_object('name', NEW.name, 'batch_id', NEW.batch_id, 'status', NEW.status));
        PERFORM emit_app_event('teachers', 'student', NEW.id, lower(TG_OP), 'Administrator', jsonb_build_object('name', NEW.name, 'batch_id', NEW.batch_id, 'status', NEW.status));
        PERFORM emit_app_event('student:' || NEW.id::text, 'student', NEW.id, lower(TG_OP), 'Administrator', jsonb_build_object('name', NEW.name, 'batch_id', NEW.batch_id, 'status', NEW.status));
        IF NEW.batch_id IS NOT NULL THEN
            PERFORM emit_app_event('batch:' || NEW.batch_id::text, 'student', NEW.id, lower(TG_OP), 'Administrator', jsonb_build_object('name', NEW.name));
        END IF;
        RETURN NEW;
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_students_realtime ON public.students;
CREATE TRIGGER trg_students_realtime AFTER INSERT OR UPDATE OR DELETE ON public.students
FOR EACH ROW EXECUTE FUNCTION trg_emit_student_event();

-- 4. Trigger for Teachers
CREATE OR REPLACE FUNCTION public.trg_emit_teacher_event() RETURNS trigger AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        PERFORM emit_app_event('admins', 'teacher', OLD.id, 'delete', 'Administrator', jsonb_build_object('name', OLD.name));
        RETURN OLD;
    ELSE
        PERFORM emit_app_event('admins', 'teacher', NEW.id, lower(TG_OP), 'Administrator', jsonb_build_object('name', NEW.name, 'status', NEW.status));
        IF NEW.status = 'inactive' THEN
            PERFORM emit_app_event('teacher:' || NEW.id::text, 'account', NEW.id, 'deactivate', 'Administrator', jsonb_build_object('reason', 'Account deactivated'));
        END IF;
        RETURN NEW;
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_teachers_realtime ON public.teachers;
CREATE TRIGGER trg_teachers_realtime AFTER INSERT OR UPDATE OR DELETE ON public.teachers
FOR EACH ROW EXECUTE FUNCTION trg_emit_teacher_event();

-- 5. Trigger for Payments
CREATE OR REPLACE FUNCTION public.trg_emit_payment_event() RETURNS trigger AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        PERFORM emit_app_event('admins', 'payment', NEW.id, 'create', 'Administrator', jsonb_build_object('student_id', NEW.student_id, 'amount_paise', NEW.amount_paise));
        PERFORM emit_app_event('student:' || NEW.student_id::text, 'payment', NEW.id, 'create', 'Administrator', jsonb_build_object('amount_paise', NEW.amount_paise));
        RETURN NEW;
    ELSIF TG_OP = 'UPDATE' THEN
        IF NEW.is_cancelled = true AND OLD.is_cancelled = false THEN
            PERFORM emit_app_event('admins', 'payment', NEW.id, 'cancel', 'Administrator', jsonb_build_object('student_id', NEW.student_id));
            PERFORM emit_app_event('student:' || NEW.student_id::text, 'payment', NEW.id, 'cancel', 'Administrator', jsonb_build_object('student_id', NEW.student_id));
        END IF;
        RETURN NEW;
    END IF;
    RETURN OLD;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_payments_realtime ON public.payments;
CREATE TRIGGER trg_payments_realtime AFTER INSERT OR UPDATE ON public.payments
FOR EACH ROW EXECUTE FUNCTION trg_emit_payment_event();

-- 6. Trigger for Attendance Sessions
CREATE OR REPLACE FUNCTION public.trg_emit_attendance_event() RETURNS trigger AS $$
DECLARE
    v_teacher_name text := 'Teacher';
BEGIN
    IF NEW.marked_by IS NOT NULL THEN
        SELECT coalesce(name, 'Teacher') INTO v_teacher_name FROM public.teachers WHERE id = NEW.marked_by;
    END IF;

    PERFORM emit_app_event('admins', 'attendance', NEW.id, 'submit', v_teacher_name, jsonb_build_object('batch_id', NEW.batch_id, 'date', NEW.date, 'slot', NEW.slot, 'no_class', NEW.no_class));
    PERFORM emit_app_event('teachers', 'attendance', NEW.id, 'submit', v_teacher_name, jsonb_build_object('batch_id', NEW.batch_id, 'date', NEW.date, 'slot', NEW.slot, 'no_class', NEW.no_class));
    PERFORM emit_app_event('batch:' || NEW.batch_id::text, 'attendance', NEW.id, 'submit', v_teacher_name, jsonb_build_object('date', NEW.date, 'slot', NEW.slot, 'no_class', NEW.no_class));
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_attendance_realtime ON public.attendance_sessions;
CREATE TRIGGER trg_attendance_realtime AFTER INSERT OR UPDATE ON public.attendance_sessions
FOR EACH ROW EXECUTE FUNCTION trg_emit_attendance_event();

-- 7. Trigger for Exams
CREATE OR REPLACE FUNCTION public.trg_emit_exam_event() RETURNS trigger AS $$
BEGIN
    PERFORM emit_app_event('admins', 'exam', NEW.id, lower(TG_OP), 'Administrator', jsonb_build_object('name', NEW.name, 'batch_id', NEW.batch_id, 'status', NEW.status));
    IF NEW.status = 'published' THEN
        PERFORM emit_app_event('batch:' || NEW.batch_id::text, 'exam', NEW.id, 'published', 'Administrator', jsonb_build_object('name', NEW.name));
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_exams_realtime ON public.exams;
CREATE TRIGGER trg_exams_realtime AFTER INSERT OR UPDATE ON public.exams
FOR EACH ROW EXECUTE FUNCTION trg_emit_exam_event();

-- 8. Trigger for Announcements
CREATE OR REPLACE FUNCTION public.trg_emit_announcement_event() RETURNS trigger AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        PERFORM emit_app_event('admins', 'announcement', NEW.id, 'send', 'Administrator', jsonb_build_object('title', NEW.title));
        PERFORM emit_app_event('teachers', 'announcement', NEW.id, 'send', 'Administrator', jsonb_build_object('title', NEW.title));
        PERFORM emit_app_event('students', 'announcement', NEW.id, 'send', 'Administrator', jsonb_build_object('title', NEW.title));
        RETURN NEW;
    ELSIF TG_OP = 'UPDATE' AND NEW.retracted_at IS NOT NULL AND OLD.retracted_at IS NULL THEN
        PERFORM emit_app_event('admins', 'announcement', NEW.id, 'retract', 'Administrator', jsonb_build_object('title', NEW.title));
        PERFORM emit_app_event('teachers', 'announcement', NEW.id, 'retract', 'Administrator', jsonb_build_object('title', NEW.title));
        PERFORM emit_app_event('students', 'announcement', NEW.id, 'retract', 'Administrator', jsonb_build_object('title', NEW.title));
        RETURN NEW;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_announcements_realtime ON public.announcements;
CREATE TRIGGER trg_announcements_realtime AFTER INSERT OR UPDATE ON public.announcements
FOR EACH ROW EXECUTE FUNCTION trg_emit_announcement_event();

-- 9. Trigger for Daily Timetables
CREATE OR REPLACE FUNCTION public.trg_emit_daily_timetable_event() RETURNS trigger AS $$
BEGIN
    PERFORM emit_app_event('admins', 'timetable', NEW.id, lower(TG_OP), 'Administrator', jsonb_build_object('date', NEW.date, 'status', NEW.status));
    PERFORM emit_app_event('teachers', 'timetable', NEW.id, lower(TG_OP), 'Administrator', jsonb_build_object('date', NEW.date, 'status', NEW.status));
    PERFORM emit_app_event('students', 'timetable', NEW.id, lower(TG_OP), 'Administrator', jsonb_build_object('date', NEW.date, 'status', NEW.status));
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_daily_timetables_realtime ON public.daily_timetables;
CREATE TRIGGER trg_daily_timetables_realtime AFTER INSERT OR UPDATE ON public.daily_timetables
FOR EACH ROW EXECUTE FUNCTION trg_emit_daily_timetable_event();
