import psycopg2

conn = psycopg2.connect("postgresql://postgres.evzehywyyqmcktszwmeg:AnzTzOTXxapp1Dys@aws-0-ap-south-1.pooler.supabase.com:6543/postgres", connect_timeout=15)
cur = conn.cursor()

cur.execute("""
CREATE OR REPLACE FUNCTION public.trg_emit_attendance_event() RETURNS trigger AS $$
DECLARE
    v_teacher_name text := 'Teacher';
BEGIN
    IF NEW.marked_by IS NOT NULL THEN
        SELECT coalesce(name, 'Teacher') INTO v_teacher_name FROM public.teachers WHERE id = NEW.marked_by;
    END IF;

    PERFORM emit_app_event('admins', 'attendance', NEW.id, 'submit', v_teacher_name, 
        jsonb_build_object('batch_id', NEW.batch_id, 'date', NEW.date, 'slot', NEW.slot, 'no_class_reason', NEW.no_class_reason));
    PERFORM emit_app_event('teachers', 'attendance', NEW.id, 'submit', v_teacher_name, 
        jsonb_build_object('batch_id', NEW.batch_id, 'date', NEW.date, 'slot', NEW.slot, 'no_class_reason', NEW.no_class_reason));
    PERFORM emit_app_event('batch:' || NEW.batch_id::text, 'attendance', NEW.id, 'submit', v_teacher_name, 
        jsonb_build_object('date', NEW.date, 'slot', NEW.slot, 'no_class_reason', NEW.no_class_reason));
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
""")

conn.commit()
conn.close()
print("Fixed trg_emit_attendance_event trigger successfully.")
