-- =============================================================================
-- MIPS ERP Database Migration: 0006_import_students.sql
-- Sub-phase 3B: Atomic Excel Student Import and Undo Batch RPC Functions
-- =============================================================================

-- 1. Ensure students has import_batch_id and index
ALTER TABLE students ADD COLUMN IF NOT EXISTS import_batch_id text;
CREATE INDEX IF NOT EXISTS idx_students_import_batch_id ON students(import_batch_id);

-- 2. Import batches registry
CREATE TABLE IF NOT EXISTS import_batches (
    id text PRIMARY KEY,
    imported_by uuid REFERENCES auth.users(id),
    total_rows int NOT NULL,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    undone_at timestamptz,
    undone_by uuid REFERENCES auth.users(id)
);

-- Enable RLS on import_batches
ALTER TABLE import_batches ENABLE ROW LEVEL SECURITY;

CREATE POLICY "import_batches_admin_all" ON import_batches
    FOR ALL TO authenticated
    USING (is_admin())
    WITH CHECK (is_admin());

-- 3. import_students RPC: inserts students and initial fee entries in ONE atomic transaction
CREATE OR REPLACE FUNCTION import_students(
    p_students jsonb,
    p_import_batch_id text DEFAULT NULL
)
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
    VALUES (v_batch_id, auth.uid(), jsonb_array_length(p_students));

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
        IF v_course_batch_id IS NULL OR NOT EXISTS (SELECT 1 FROM batches WHERE id = v_course_batch_id AND course_id = v_course_id AND deleted_at IS NULL) THEN
            RAISE EXCEPTION 'Valid batch_id matching the course is required for student "%".', v_name;
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
        IF v_reg_no = '' THEN
            v_reg_no := NULL;
        END IF;

        v_gender := coalesce(v_row->>'gender', 'Male');
        IF v_gender NOT IN ('Male', 'Female', 'Other') THEN
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

        -- Insert student
        INSERT INTO students (
            admission_number,
            registration_number,
            name,
            dob,
            gender,
            phone,
            email,
            address,
            admission_date,
            course_id,
            batch_id,
            university_id,
            academic_year_id,
            status,
            import_batch_id
        ) VALUES (
            v_adm_no,
            v_reg_no,
            v_name,
            v_dob,
            v_gender,
            v_phone,
            v_email,
            v_address,
            v_adm_date,
            v_course_id,
            v_course_batch_id,
            v_university_id,
            v_academic_year_id,
            v_status,
            v_batch_id
        ) RETURNING id INTO v_student_id;

        -- Create initial fee ledger entry for student
        SELECT coalesce(total_fee_paise, 0) INTO v_total_fee_paise
        FROM courses WHERE id = v_course_id;

        INSERT INTO fees (
            student_id,
            total_fee_paise,
            paid_amount_paise,
            pending_amount_paise
        ) VALUES (
            v_student_id,
            v_total_fee_paise,
            0,
            v_total_fee_paise
        );

        v_count := v_count + 1;
    END LOOP;

    -- Audit log
    INSERT INTO audit_log (table_name, record_id, action, new_data, actor, created_at)
    VALUES (
        'students',
        v_batch_id,
        'IMPORT_STUDENTS',
        jsonb_build_object('count', v_count, 'batch_id', v_batch_id),
        auth.uid(),
        clock_timestamp()
    );

    RETURN jsonb_build_object(
        'success', true,
        'import_batch_id', v_batch_id,
        'imported_count', v_count
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp;

-- 4. undo_import RPC: rollback student batch and clean fees if no payments exist
CREATE OR REPLACE FUNCTION undo_import(p_import_batch_id text)
RETURNS jsonb AS $$
DECLARE
    v_clean_batch_id text;
    v_count int;
    v_payments_count int;
BEGIN
    IF NOT is_admin() THEN
        RAISE EXCEPTION 'Access denied. Only administrators can undo an import.';
    END IF;

    v_clean_batch_id := trim(p_import_batch_id);
    IF v_clean_batch_id IS NULL OR v_clean_batch_id = '' THEN
        RAISE EXCEPTION 'Import batch ID is required to undo an import.';
    END IF;

    -- Verify the batch exists and hasn't been undone
    IF NOT EXISTS (SELECT 1 FROM import_batches WHERE id = v_clean_batch_id) THEN
        RAISE EXCEPTION 'Import batch "%" not found.', v_clean_batch_id;
    END IF;

    IF EXISTS (SELECT 1 FROM import_batches WHERE id = v_clean_batch_id AND undone_at IS NOT NULL) THEN
        RAISE EXCEPTION 'Import batch "%" has already been undone.', v_clean_batch_id;
    END IF;

    -- Check if any student in this import batch has payments
    SELECT count(*) INTO v_payments_count
    FROM payments p
    JOIN students s ON p.student_id = s.id
    WHERE s.import_batch_id = v_clean_batch_id
      AND p.deleted_at IS NULL
      AND p.is_cancelled = false;

    IF v_payments_count > 0 THEN
        RAISE EXCEPTION 'Cannot undo import: % active payment(s) exist for students in this batch. Please cancel all payments first.', v_payments_count;
    END IF;

    -- Delete initial uncollected fees
    DELETE FROM fees
    WHERE student_id IN (
        SELECT id FROM students WHERE import_batch_id = v_clean_batch_id
    );

    -- Soft delete students
    UPDATE students
    SET deleted_at = clock_timestamp(),
        deleted_by = auth.uid()
    WHERE import_batch_id = v_clean_batch_id
      AND deleted_at IS NULL;

    GET DIAGNOSTICS v_count = ROW_COUNT;

    -- Mark import batch as undone
    UPDATE import_batches
    SET undone_at = clock_timestamp(),
        undone_by = auth.uid()
    WHERE id = v_clean_batch_id;

    -- Audit log
    INSERT INTO audit_log (table_name, record_id, action, new_data, actor, created_at)
    VALUES (
        'students',
        v_clean_batch_id,
        'UNDO_IMPORT',
        jsonb_build_object('undone_count', v_count, 'batch_id', v_clean_batch_id),
        auth.uid(),
        clock_timestamp()
    );

    RETURN jsonb_build_object(
        'success', true,
        'import_batch_id', v_clean_batch_id,
        'undone_count', v_count
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp;

-- Permissions
GRANT EXECUTE ON FUNCTION import_students(jsonb, text) TO authenticated;
GRANT EXECUTE ON FUNCTION undo_import(text) TO authenticated;
