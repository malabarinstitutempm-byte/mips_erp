-- Migration 0031: Grant Anon and Authenticated permissions and RLS policies across all public tables
-- Reason: Administrators authenticate via admin_accounts and use anonKey for Supabase PostgREST client.

GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;
GRANT ALL ON ALL TABLES IN SCHEMA public TO anon, authenticated, service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO anon, authenticated, service_role;
GRANT ALL ON ALL ROUTINES IN SCHEMA public TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON ROUTINES TO anon, authenticated, service_role;

-- Relax students constraints:
-- 1. batch_id can be nullable so students can be enrolled before batch creation
ALTER TABLE public.students ALTER COLUMN batch_id DROP NOT NULL;

-- 2. Gender check is case-insensitive ('male', 'female', 'other')
ALTER TABLE public.students DROP CONSTRAINT IF EXISTS students_gender_check;
ALTER TABLE public.students ADD CONSTRAINT students_gender_check CHECK (gender IS NULL OR lower(gender) IN ('male', 'female', 'other'));

-- Apply permissive RLS policies for anon and authenticated across all public tables
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN (
        SELECT tablename 
        FROM pg_tables 
        WHERE schemaname = 'public'
    ) LOOP
        EXECUTE format('DROP POLICY IF EXISTS p_%I_anon_authenticated_all ON public.%I;', r.tablename, r.tablename);
        EXECUTE format('CREATE POLICY p_%I_anon_authenticated_all ON public.%I FOR ALL TO anon, authenticated USING (true) WITH CHECK (true);', r.tablename, r.tablename);
    END LOOP;
END $$;
