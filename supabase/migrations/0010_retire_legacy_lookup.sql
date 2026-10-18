-- 0010_retire_legacy_lookup.sql
-- Sub-phase 6E: Security Hardening & Retirement of Legacy Public Results Lookup
--
-- Explicitly revokes all anonymous access to marks, examination results,
-- student profiles, and any legacy get_result function, ensuring that results
-- can only ever be queried by authenticated student sessions via Row-Level Security.

-- 1. Drop any legacy public results lookup functions
DROP FUNCTION IF EXISTS public.get_result(text, date);
DROP FUNCTION IF EXISTS public.get_result(text, text);
DROP FUNCTION IF EXISTS public.get_result(text);
DROP FUNCTION IF EXISTS public.get_result();

-- 2. Revoke execute privileges on calculation & internal functions from anon
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM pg_proc p
        JOIN pg_namespace n ON p.pronamespace = n.oid
        WHERE n.nspname = 'public' AND p.proname = 'compute_results'
    ) THEN
        REVOKE ALL ON FUNCTION public.compute_results FROM anon, public;
        GRANT EXECUTE ON FUNCTION public.compute_results TO authenticated;
    END IF;

    IF EXISTS (
        SELECT 1 FROM pg_proc p
        JOIN pg_namespace n ON p.pronamespace = n.oid
        WHERE n.nspname = 'public' AND p.proname = 'publish_results'
    ) THEN
        REVOKE ALL ON FUNCTION public.publish_results FROM anon, public;
        GRANT EXECUTE ON FUNCTION public.publish_results TO authenticated;
    END IF;
END $$;

-- 3. Confirm revocation of table access for anon role
REVOKE ALL ON TABLE public.marks FROM anon;
REVOKE ALL ON TABLE public.results FROM anon;
REVOKE ALL ON TABLE public.students FROM anon;
REVOKE ALL ON TABLE public.student_enrollments FROM anon;
REVOKE ALL ON TABLE public.attendance_records FROM anon;
REVOKE ALL ON TABLE public.fee_items FROM anon;
REVOKE ALL ON TABLE public.payments FROM anon;

-- 4. Audit Log Documentation
COMMENT ON TABLE public.results IS 'Official computed exam results. Access is strictly restricted to authenticated students (own published records) and administrators via Row Level Security (RLS). Public unauthenticated lookup has been retired.';
