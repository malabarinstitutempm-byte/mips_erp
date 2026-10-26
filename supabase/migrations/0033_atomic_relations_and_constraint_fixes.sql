-- Migration 0033: Atomic Relations and Constraint Fixes (Phase D3)
-- 1. Make created_by nullable in announcements
ALTER TABLE public.announcements ALTER COLUMN created_by DROP NOT NULL;

-- 2. Update batch_periods status check to include 'closed'
ALTER TABLE public.batch_periods DROP CONSTRAINT IF EXISTS batch_periods_status_check;
ALTER TABLE public.batch_periods ADD CONSTRAINT batch_periods_status_check 
    CHECK (status = ANY (ARRAY['active'::text, 'completed'::text, 'upcoming'::text, 'closed'::text]));

-- 3. Relax profiles user_id fkey to allow non-auth profiles and add unique constraints
ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_user_id_fkey;
ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS uk_profiles_teacher_id;
ALTER TABLE public.profiles ADD CONSTRAINT uk_profiles_teacher_id UNIQUE (teacher_id);
ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS uk_profiles_student_id;
ALTER TABLE public.profiles ADD CONSTRAINT uk_profiles_student_id UNIQUE (student_id);

-- 4. Update import_students to handle on conflict in fees
CREATE OR REPLACE FUNCTION public.import_students(p_students jsonb, p_import_batch_id text DEFAULT NULL::text)
RETURNS jsonb AS $$
DECLARE
    v_batch_id text;
    v_row jsonb;
    v_student_id bigint;
    v_course_id bigint;
    v_course_batch_id bigint;
    v_university_id bigint;
    v_academic_year_id bigint;
    v_name text;
    v_adm_no text;
    v_reg_no text;
    v_dob date;
    v_gender text;
    v_phone text;
    v_email text;
    v_address text;
    v_adm_date date;
    v_status student_status;
    v_total_fee_paise bigint;
    v_count int := 0;
    v_curr_year int;
BEGIN
    IF NOT is_admin() THEN
        RAISE EXCEPTION 'Access denied. Only administrators can import students.';
    END IF;

    IF p_students IS NULL OR jsonb_array_length(p_students) = 0 THEN
        RAISE EXCEPTION 'No student records provided for import.';
    END IF;

    v_batch_id := coalesce(p_import_batch_id, gen_random_uuid()::text);
    v_curr_year := EXTRACT(YEAR FROM CURRENT_DATE)::int;

    -- Record import batch
    INSERT INTO import_batches(id, imported_by, total_rows)
    VALUES (v_batch_id, auth.uid(), jsonb_array_length(p_students))
    ON CONFLICT (id) DO NOTHING;

    FOR v_row IN SELECT * FROM jsonb_array_elements(p_students)
    LOOP
        v_name := trim(coalesce(v_row->>'name', ''));
        IF v_name = '' THEN
            RAISE EXCEPTION 'Student name is required for all import rows.';
        END IF;

        v_course_id := (v_row->>'course_id')::bigint;
        IF v_course_id IS NULL OR NOT EXISTS (SELECT 1 FROM courses WHERE id = v_course_id AND deleted_at IS NULL) THEN
            RAISE EXCEPTION 'Valid course_id is required for student "%".', v_name;
        END IF;

        v_course_batch_id := (v_row->>'batch_id')::bigint;
        IF v_course_batch_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM batches WHERE id = v_course_batch_id AND course_id = v_course_id AND deleted_at IS NULL) THEN
            v_course_batch_id := NULL;
        END IF;

        v_adm_no := trim(coalesce(v_row->>'admission_number', ''));
        IF v_adm_no = '' THEN
            v_adm_no := next_number('admission', v_curr_year);
        ELSE
            IF EXISTS (SELECT 1 FROM students WHERE lower(admission_number) = lower(v_adm_no) AND deleted_at IS NULL) THEN
                RAISE EXCEPTION 'Admission number "%" already exists.', v_adm_no;
            END IF;
        END IF;

        v_reg_no := trim(coalesce(v_row->>'registration_number', ''));
        IF v_reg_no = '' THEN v_reg_no := NULL; END IF;

        v_gender := coalesce(v_row->>'gender', 'Male');
        IF lower(v_gender) NOT IN ('male', 'female', 'other') THEN
            v_gender := 'Male';
        END IF;

        v_dob := (v_row->>'dob')::date;
        v_phone := trim(coalesce(v_row->>'phone', ''));
        IF v_phone = '' THEN v_phone := NULL; END IF;

        v_email := trim(coalesce(v_row->>'email', ''));
        IF v_email = '' THEN v_email := NULL; END IF;

        v_address := trim(coalesce(v_row->>'address', ''));
        IF v_address = '' THEN v_address := NULL; END IF;

        v_adm_date := coalesce((v_row->>'admission_date')::date, CURRENT_DATE);

        v_university_id := (v_row->>'university_id')::bigint;
        v_academic_year_id := (v_row->>'academic_year_id')::bigint;
        v_status := 'active';

        -- Insert student (trigger trg_student_auto_enroll_and_fee will create fees + enrollment + fee items)
        INSERT INTO students (
            admission_number, registration_number, name, dob, gender, phone, email,
            address, admission_date, course_id, batch_id, university_id, academic_year_id,
            status, import_batch_id
        ) VALUES (
            v_adm_no, v_reg_no, v_name, v_dob, v_gender, v_phone, v_email,
            v_address, v_adm_date, v_course_id, v_course_batch_id, v_university_id, v_academic_year_id,
            v_status, v_batch_id
        ) RETURNING id INTO v_student_id;

        -- Ensure fee ledger is updated idempotently
        SELECT coalesce(total_fee_paise, 0) INTO v_total_fee_paise
        FROM courses WHERE id = v_course_id;

        INSERT INTO fees (student_id, total_fee_paise, paid_amount_paise, pending_amount_paise)
        VALUES (v_student_id, v_total_fee_paise, 0, v_total_fee_paise)
        ON CONFLICT (student_id) DO UPDATE SET
            total_fee_paise = GREATEST(fees.total_fee_paise, EXCLUDED.total_fee_paise),
            pending_amount_paise = GREATEST(fees.total_fee_paise, EXCLUDED.total_fee_paise) - fees.paid_amount_paise,
            updated_at = clock_timestamp();

        v_count := v_count + 1;
    END LOOP;

    -- Audit log
    INSERT INTO audit_log (table_name, record_id, action, new_data, actor, created_at)
    VALUES (
        'students', v_batch_id, 'IMPORT_STUDENTS',
        jsonb_build_object('count', v_count, 'batch_id', v_batch_id),
        auth.uid(), clock_timestamp()
    );

    RETURN jsonb_build_object('success', true, 'import_batch_id', v_batch_id, 'imported_count', v_count);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 5. Update admin_upsert_teacher to link profile atomically
CREATE OR REPLACE FUNCTION public.admin_upsert_teacher(
    p_name text,
    p_username text,
    p_phone text,
    p_temp_password text DEFAULT NULL::text
) RETURNS jsonb AS $$
DECLARE
    v_clean_user text := lower(trim(p_username));
    v_clean_name text := trim(p_name);
    v_clean_phone text := trim(p_phone);
    v_teacher_id bigint;
BEGIN
    IF v_clean_user IS NULL OR v_clean_user = '' THEN
        RETURN jsonb_build_object('success', false, 'error', 'Staff username is required.');
    END IF;

    IF v_clean_name IS NULL OR v_clean_name = '' THEN
        RETURN jsonb_build_object('success', false, 'error', 'Staff name is required.');
    END IF;

    INSERT INTO public.teachers (name, login_username, phone, status, updated_at)
    VALUES (v_clean_name, v_clean_user, v_clean_phone, 'active', clock_timestamp())
    ON CONFLICT (login_username) DO UPDATE
    SET name = EXCLUDED.name,
        phone = EXCLUDED.phone,
        status = 'active',
        deleted_at = NULL,
        updated_at = clock_timestamp()
    RETURNING id INTO v_teacher_id;

    IF p_temp_password IS NOT NULL AND p_temp_password != '' THEN
        INSERT INTO public.portal_credentials (role, identifier, password_hash, is_temporary, updated_at)
        VALUES ('teacher', v_clean_user, p_temp_password, true, clock_timestamp())
        ON CONFLICT (role, identifier) DO UPDATE
        SET password_hash = EXCLUDED.password_hash, is_temporary = true, updated_at = clock_timestamp();
    END IF;

    -- Atomically upsert profile link
    INSERT INTO public.profiles (user_id, role, teacher_id, active, created_at, updated_at)
    VALUES (gen_random_uuid(), 'teacher', v_teacher_id, true, clock_timestamp(), clock_timestamp())
    ON CONFLICT (teacher_id) DO UPDATE
    SET active = true, updated_at = clock_timestamp();

    RETURN jsonb_build_object(
        'success', true,
        'message', 'Teacher provisioned successfully.',
        'teacher', jsonb_build_object(
            'id', v_teacher_id,
            'name', v_clean_name,
            'login_username', v_clean_user,
            'phone', v_clean_phone
        )
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 6. Clean single admin_unlock_account function
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
