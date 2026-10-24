-- Migration 0029: admin_get_all_accounts RPC
CREATE OR REPLACE FUNCTION public.admin_get_all_accounts()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
BEGIN
    RETURN (
        SELECT coalesce(jsonb_agg(to_jsonb(a) ORDER BY a.created_at ASC), '[]'::jsonb)
        FROM (
            SELECT id, full_name, username, email, role, active, created_at, last_login_at
            FROM public.admin_accounts
        ) a
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_get_all_accounts() TO anon, authenticated, service_role;
