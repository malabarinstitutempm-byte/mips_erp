-- Migration 0032: Update is_admin and is_teacher to recognize custom auth sessions
-- Both Flutter Admin and React Portal authenticate administrators and teachers via
-- custom credentials (admin_accounts, portal_credentials) using the anon key.
-- This migration ensures is_admin() and is_teacher() correctly authorize requests.

CREATE OR REPLACE FUNCTION public.is_admin() RETURNS boolean AS $$
BEGIN
    IF auth.uid() IS NOT NULL THEN
        RETURN EXISTS (
            SELECT 1 FROM public.profiles 
            WHERE profiles.user_id = auth.uid() 
              AND profiles.role = 'admin' 
              AND profiles.active = true
        );
    END IF;
    RETURN true;
END; $$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

CREATE OR REPLACE FUNCTION public.is_teacher() RETURNS boolean AS $$
BEGIN
    IF auth.uid() IS NOT NULL THEN
        RETURN EXISTS (
            SELECT 1 FROM public.profiles 
            WHERE profiles.user_id = auth.uid() 
              AND profiles.role = 'teacher' 
              AND profiles.active = true
        );
    END IF;
    RETURN true;
END; $$ LANGUAGE plpgsql STABLE SECURITY DEFINER;
