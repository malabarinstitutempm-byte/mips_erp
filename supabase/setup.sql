-- Mirrors portal/supabase/setup.sql
-- Run this script in the Supabase SQL Editor (Dashboard -> SQL Editor -> New Query).

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS portal_config (
  key text PRIMARY KEY,
  value text NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE portal_config ENABLE ROW LEVEL SECURITY;

INSERT INTO portal_config (key, value)
VALUES ('pepper', 'MIPS_PEPPER_PARAMEDICAL_2026_SECURE_SALT_9843')
ON CONFLICT (key) DO NOTHING;

CREATE OR REPLACE FUNCTION get_portal_pepper()
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_pepper text;
BEGIN
  SELECT value INTO v_pepper FROM portal_config WHERE key = 'pepper';
  IF v_pepper IS NULL OR v_pepper = '' THEN
    RETURN 'MIPS_PEPPER_PARAMEDICAL_2026_SECURE_SALT_9843';
  END IF;
  RETURN v_pepper;
END;
$$;

CREATE TABLE IF NOT EXISTS published_results (
  id bigserial PRIMARY KEY,
  exam_id integer NOT NULL,
  exam_name text NOT NULL,
  course text NOT NULL,
  batch text,
  register_no text NOT NULL,
  student_name text NOT NULL,
  dob_hash text NOT NULL,
  subjects_json jsonb NOT NULL DEFAULT '[]'::jsonb,
  total numeric NOT NULL DEFAULT 0,
  percentage numeric NOT NULL DEFAULT 0,
  grade text NOT NULL DEFAULT '',
  result_status text NOT NULL DEFAULT 'Pass',
  result_code text NOT NULL UNIQUE,
  published_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT uk_published_results_exam_reg UNIQUE (exam_id, register_no)
);

CREATE INDEX IF NOT EXISTS idx_pub_results_lookup ON published_results (register_no, dob_hash);
CREATE INDEX IF NOT EXISTS idx_pub_results_exam ON published_results (exam_id);

CREATE TABLE IF NOT EXISTS login_attempts (
  id bigserial PRIMARY KEY,
  register_no text,
  ip text,
  attempted_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_login_attempts_window ON login_attempts (register_no, ip, attempted_at);

ALTER TABLE published_results ENABLE ROW LEVEL SECURITY;
ALTER TABLE login_attempts ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON published_results FROM PUBLIC, anon, authenticated;
REVOKE ALL ON login_attempts FROM PUBLIC, anon, authenticated;
REVOKE ALL ON portal_config FROM PUBLIC, anon, authenticated;

GRANT ALL ON published_results TO service_role;
GRANT ALL ON login_attempts TO service_role;
GRANT ALL ON portal_config TO service_role;

DROP FUNCTION IF EXISTS publish_results(jsonb);

CREATE OR REPLACE FUNCTION publish_results(jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  payload jsonb := $1;
  v_item jsonb;
  v_items jsonb;
  v_count integer := 0;
  v_reg text;
  v_dob_str text;
  v_dob_hash text;
  v_pepper text;
BEGIN
  v_pepper := get_portal_pepper();

  IF jsonb_typeof(payload) = 'object' AND payload ? 'payload' THEN
    v_items := payload->'payload';
  ELSIF jsonb_typeof(payload) = 'array' THEN
    v_items := payload;
  ELSE
    RETURN jsonb_build_object('success', false, 'error', 'Invalid payload format. Expected JSON array.');
  END IF;

  FOR v_item IN SELECT * FROM jsonb_array_elements(v_items)
  LOOP
    v_reg := upper(trim(COALESCE(v_item->>'register_no', '')));
    
    IF v_item ? 'dob' AND v_item->>'dob' IS NOT NULL AND v_item->>'dob' <> '' THEN
      v_dob_str := to_char((v_item->>'dob')::date, 'YYYY-MM-DD');
    ELSE
      v_dob_str := '2000-01-01';
    END IF;

    v_dob_hash := encode(digest(v_reg || v_dob_str || v_pepper, 'sha256'), 'hex');

    INSERT INTO published_results (
      exam_id, exam_name, course, batch, register_no, student_name, dob_hash,
      subjects_json, total, percentage, grade, result_status, result_code, published_at
    ) VALUES (
      (v_item->>'exam_id')::integer,
      COALESCE(v_item->>'exam_name', 'Examination'),
      COALESCE(v_item->>'course', 'Paramedical Course'),
      COALESCE(v_item->>'batch', ''),
      v_reg,
      COALESCE(v_item->>'student_name', 'Student'),
      v_dob_hash,
      COALESCE(v_item->'subjects_json', '[]'::jsonb),
      COALESCE((v_item->>'total')::numeric, 0),
      COALESCE((v_item->>'percentage')::numeric, 0),
      COALESCE(v_item->>'grade', 'F'),
      COALESCE(v_item->>'result_status', 'Pass'),
      COALESCE(v_item->>'result_code', 'MIPS-' || (v_item->>'exam_id') || '-' || v_reg),
      now()
    )
    ON CONFLICT (exam_id, register_no)
    DO UPDATE SET
      exam_name = EXCLUDED.exam_name,
      course = EXCLUDED.course,
      batch = EXCLUDED.batch,
      student_name = EXCLUDED.student_name,
      dob_hash = EXCLUDED.dob_hash,
      subjects_json = EXCLUDED.subjects_json,
      total = EXCLUDED.total,
      percentage = EXCLUDED.percentage,
      grade = EXCLUDED.grade,
      result_status = EXCLUDED.result_status,
      result_code = EXCLUDED.result_code,
      published_at = now();

    v_count := v_count + 1;
  END LOOP;

  RETURN jsonb_build_object('success', true, 'processed', v_count);
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'error', SQLERRM);
END;
$$;

REVOKE ALL ON FUNCTION publish_results(jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION publish_results(jsonb) TO service_role;

CREATE OR REPLACE FUNCTION unpublish_exam(p_exam_id integer DEFAULT NULL, exam_id integer DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_target_id integer;
  v_deleted integer;
BEGIN
  v_target_id := COALESCE(p_exam_id, exam_id);
  IF v_target_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'exam_id is required');
  END IF;

  DELETE FROM published_results WHERE published_results.exam_id = v_target_id;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;

  RETURN jsonb_build_object('success', true, 'deleted', v_deleted);
END;
$$;

REVOKE ALL ON FUNCTION unpublish_exam(integer, integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION unpublish_exam(integer, integer) TO service_role;

CREATE OR REPLACE FUNCTION get_result(p_register_no text, p_dob date)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_reg text;
  v_dob_str text;
  v_candidate_hash text;
  v_pepper text;
  v_client_ip text;
  v_headers jsonb;
  v_fail_count integer := 0;
  v_results jsonb;
BEGIN
  v_reg := upper(trim(COALESCE(p_register_no, '')));
  IF v_reg = '' OR p_dob IS NULL THEN
    RETURN jsonb_build_object(
      'success', false, 
      'error', 'Register number or date of birth is incorrect. Please check and try again.'
    );
  END IF;

  BEGIN
    v_headers := NULLIF(current_setting('request.headers', true), '')::jsonb;
    v_client_ip := COALESCE(
      v_headers->>'cf-connecting-ip',
      split_part(v_headers->>'x-forwarded-for', ',', 1),
      v_headers->>'x-real-ip',
      'unknown'
    );
  EXCEPTION WHEN OTHERS THEN
    v_client_ip := 'unknown';
  END;

  SELECT count(*) INTO v_fail_count
  FROM login_attempts
  WHERE attempted_at >= (now() - interval '15 minutes')
    AND (
      (v_reg <> '' AND register_no = v_reg)
      OR (v_client_ip <> 'unknown' AND ip = v_client_ip)
    );

  IF v_fail_count >= 5 THEN
    RETURN jsonb_build_object(
      'success', false,
      'locked', true,
      'error', 'Too many attempts. Please try again in 15 minutes.'
    );
  END IF;

  v_pepper := get_portal_pepper();
  v_dob_str := to_char(p_dob, 'YYYY-MM-DD');
  v_candidate_hash := encode(digest(v_reg || v_dob_str || v_pepper, 'sha256'), 'hex');

  SELECT jsonb_agg(
    jsonb_build_object(
      'id', pr.id,
      'exam_id', pr.exam_id,
      'exam_name', pr.exam_name,
      'course', pr.course,
      'batch', pr.batch,
      'register_no', pr.register_no,
      'student_name', pr.student_name,
      'subjects_json', pr.subjects_json,
      'total', pr.total,
      'percentage', pr.percentage,
      'grade', pr.grade,
      'result_status', pr.result_status,
      'result_code', pr.result_code,
      'published_at', pr.published_at
    ) ORDER BY pr.published_at DESC
  ) INTO v_results
  FROM published_results pr
  WHERE pr.register_no = v_reg
    AND pr.dob_hash = v_candidate_hash;

  IF v_results IS NOT NULL AND jsonb_array_length(v_results) > 0 THEN
    DELETE FROM login_attempts
    WHERE register_no = v_reg
       OR (v_client_ip <> 'unknown' AND ip = v_client_ip);

    RETURN jsonb_build_object(
      'success', true,
      'data', v_results
    );
  END IF;

  INSERT INTO login_attempts (register_no, ip, attempted_at)
  VALUES (v_reg, v_client_ip, now());

  IF (v_fail_count + 1) >= 5 THEN
    RETURN jsonb_build_object(
      'success', false,
      'locked', true,
      'error', 'Too many attempts. Please try again in 15 minutes.'
    );
  END IF;

  RETURN jsonb_build_object(
    'success', false,
    'error', 'Register number or date of birth is incorrect. Please check and try again.'
  );
END;
$$;

GRANT EXECUTE ON FUNCTION get_result(text, date) TO anon, authenticated;
