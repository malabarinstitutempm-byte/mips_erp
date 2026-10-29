import os
import psycopg2

conn = psycopg2.connect(os.environ.get("DATABASE_URL", ""), connect_timeout=15)
cur = conn.cursor()

cur.execute("""
CREATE OR REPLACE FUNCTION public.admin_unlock_account(
    p_role text DEFAULT NULL::text,
    p_identifier text DEFAULT NULL::text,
    p_user_id uuid DEFAULT NULL::uuid
) RETURNS jsonb AS $$
DECLARE
    v_clean text := lower(trim(coalesce(p_identifier, '')));
    v_found boolean := false;
BEGIN
    IF NOT is_admin() THEN
        RAISE EXCEPTION 'Access denied. Administrator privileges required.';
    END IF;

    -- Unlock in profiles by user_id if provided
    IF p_user_id IS NOT NULL THEN
        UPDATE public.profiles
        SET failed_attempts = 0, locked_at = NULL, active = true, updated_at = clock_timestamp()
        WHERE user_id = p_user_id;
        v_found := true;
    END IF;

    -- Unlock by identifier and role
    IF v_clean != '' THEN
        IF p_role = 'teacher' THEN
            UPDATE public.profiles
            SET failed_attempts = 0, locked_at = NULL, active = true, updated_at = clock_timestamp()
            WHERE teacher_id IN (SELECT id FROM public.teachers WHERE lower(login_username) = v_clean);
            
            UPDATE public.teachers
            SET status = 'active', updated_at = clock_timestamp()
            WHERE lower(login_username) = v_clean;
            IF FOUND THEN v_found := true; END IF;
        ELSIF p_role = 'student' THEN
            UPDATE public.profiles
            SET failed_attempts = 0, locked_at = NULL, active = true, updated_at = clock_timestamp()
            WHERE student_id IN (SELECT id FROM public.students WHERE lower(admission_number) = v_clean OR lower(registration_number) = v_clean);

            UPDATE public.students
            SET status = 'active', updated_at = clock_timestamp()
            WHERE lower(admission_number) = v_clean OR lower(registration_number) = v_clean;
            IF FOUND THEN v_found := true; END IF;
        END IF;
    END IF;

    IF v_found THEN
        RETURN jsonb_build_object('success', true, 'message', 'Account unlocked successfully.');
    ELSE
        RETURN jsonb_build_object('success', false, 'error', 'Target user account not found.');
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
""")

conn.commit()
conn.close()
print("Updated admin_unlock_account successfully.")
