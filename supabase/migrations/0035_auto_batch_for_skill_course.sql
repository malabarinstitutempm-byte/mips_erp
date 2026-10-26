-- Migration 0035: Auto-create or fallback batch for skill course enrollment
-- Allows enrolling in a skill course even if an explicit batch has not been created yet

CREATE OR REPLACE FUNCTION public.add_student_skill_course(
    p_student_id bigint,
    p_course_id bigint,
    p_batch_id bigint DEFAULT NULL,
    p_fee_paise bigint DEFAULT NULL
)
RETURNS jsonb AS $$
DECLARE
    v_course courses%ROWTYPE;
    v_enr_id bigint;
    v_fee_amount bigint;
    v_fee_item_id bigint;
    v_batch_id bigint := p_batch_id;
BEGIN
    IF NOT is_admin() THEN
        RAISE EXCEPTION 'Access denied. Administrator privilege required.';
    END IF;

    -- Verify course is of type skill
    SELECT * INTO v_course
    FROM courses
    WHERE id = p_course_id AND deleted_at IS NULL;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Course ID % not found.', p_course_id;
    END IF;

    IF v_course.course_type != 'skill' THEN
        RAISE EXCEPTION 'Course "%" (ID %) is not marked as a skill course.', v_course.name, p_course_id;
    END IF;

    -- Check student active
    IF NOT EXISTS (SELECT 1 FROM students WHERE id = p_student_id AND deleted_at IS NULL AND status = 'active') THEN
        RAISE EXCEPTION 'Active student ID % not found.', p_student_id;
    END IF;

    -- Check if student already has an active skill enrollment
    IF EXISTS (
        SELECT 1 FROM student_enrollments 
        WHERE student_id = p_student_id AND kind = 'skill' AND status = 'active' AND deleted_at IS NULL
    ) THEN
        RAISE EXCEPTION 'Student ID % already has an active skill course enrollment.', p_student_id;
    END IF;

    -- Ensure a valid batch_id exists for this skill course
    IF v_batch_id IS NULL THEN
        SELECT id INTO v_batch_id FROM batches WHERE course_id = p_course_id AND deleted_at IS NULL ORDER BY id ASC LIMIT 1;
        IF v_batch_id IS NULL THEN
            INSERT INTO batches (course_id, batch_name, status, start_date)
            VALUES (p_course_id, v_course.name || ' - Batch 1', 'active', CURRENT_DATE)
            RETURNING id INTO v_batch_id;
        END IF;
    END IF;

    -- Insert skill enrollment
    INSERT INTO student_enrollments (
        student_id,
        course_id,
        batch_id,
        kind,
        enrolled_on,
        status,
        created_at,
        updated_at
    ) VALUES (
        p_student_id,
        p_course_id,
        v_batch_id,
        'skill',
        CURRENT_DATE,
        'active',
        clock_timestamp(),
        clock_timestamp()
    ) RETURNING id INTO v_enr_id;

    -- Create fee item for skill course
    v_fee_amount := coalesce(p_fee_paise, v_course.total_fee_paise);
    IF v_fee_amount > 0 THEN
        INSERT INTO fee_items (
            student_id,
            enrollment_id,
            label,
            amount_paise,
            paid_amount_paise,
            due_date,
            status,
            created_at,
            updated_at
        ) VALUES (
            p_student_id,
            v_enr_id,
            v_course.name || ' - Skill Course Fee',
            v_fee_amount,
            0,
            CURRENT_DATE + interval '30 days',
            'unpaid',
            clock_timestamp(),
            clock_timestamp()
        ) RETURNING id INTO v_fee_item_id;
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'enrollment_id', v_enr_id,
        'student_id', p_student_id,
        'course_id', p_course_id,
        'batch_id', v_batch_id,
        'fee_item_id', v_fee_item_id,
        'amount_paise', v_fee_amount
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
