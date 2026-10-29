import os
import psycopg2

conn = psycopg2.connect(os.environ.get("DATABASE_URL", ""), connect_timeout=15)
cur = conn.cursor()

# 1. Add unique constraint to profiles
cur.execute("DROP INDEX IF EXISTS idx_profiles_teacher_id;")
cur.execute("ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS uk_profiles_teacher_id;")
cur.execute("ALTER TABLE public.profiles ADD CONSTRAINT uk_profiles_teacher_id UNIQUE (teacher_id);")

cur.execute("DROP INDEX IF EXISTS idx_profiles_student_id;")
cur.execute("ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS uk_profiles_student_id;")
cur.execute("ALTER TABLE public.profiles ADD CONSTRAINT uk_profiles_student_id UNIQUE (student_id);")

# 2. Drop all overloads of admin_unlock_account
cur.execute("""
SELECT oid::regprocedure::text FROM pg_proc WHERE proname = 'admin_unlock_account';
""")
overloads = [r[0] for r in cur.fetchall()]
for ov in overloads:
    print("Dropping overload:", ov)
    cur.execute(f"DROP FUNCTION {ov};")

# 3. Create clean single admin_unlock_account function
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

    -- Unlock in profiles if exists
    IF p_user_id IS NOT NULL THEN
        UPDATE public.profiles
        SET failed_attempts = 0, locked_at = NULL, active = true, updated_at = clock_timestamp()
        WHERE user_id = p_user_id;
        v_found := true;
    END IF;

    -- Unlock in portal_credentials
    IF v_clean != '' THEN
        UPDATE public.portal_credentials
        SET failed_attempts = 0, locked_until = NULL, updated_at = clock_timestamp()
        WHERE lower(identifier) = v_clean
          AND (p_role IS NULL OR role = p_role);
        
        IF FOUND THEN
            v_found := true;
        END IF;

        IF p_role = 'teacher' THEN
            UPDATE public.teachers
            SET status = 'active', updated_at = clock_timestamp()
            WHERE lower(login_username) = v_clean;
            IF FOUND THEN v_found := true; END IF;
        ELSIF p_role = 'student' THEN
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
print("Constraints and clean admin_unlock_account created.")
conn.close()
