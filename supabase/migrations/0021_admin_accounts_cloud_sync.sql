-- =============================================================================
-- Migration 0021: Admin Accounts Cloud Sync
-- Provides a synchronized cloud table for administrator accounts managed via
-- the MIPS Admin App (Settings -> Administrator Accounts) so that any admin
-- created inside the app can immediately log in from ANY device or browser.
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.admin_accounts (
    id text PRIMARY KEY,
    full_name text NOT NULL,
    username text UNIQUE NOT NULL,
    email text,
    role text NOT NULL DEFAULT 'Super Administrator',
    password text NOT NULL,
    active boolean NOT NULL DEFAULT true,
    last_login_at text,
    created_at text NOT NULL
);

-- Enable Row Level Security
ALTER TABLE public.admin_accounts ENABLE ROW LEVEL SECURITY;

-- Allow anon and authenticated clients to read and manage admin accounts
DROP POLICY IF EXISTS p_admin_accounts_all ON public.admin_accounts;
CREATE POLICY p_admin_accounts_all ON public.admin_accounts
    FOR ALL TO anon, authenticated
    USING (true)
    WITH CHECK (true);

-- Seed default master administrator accounts if table is empty
INSERT INTO public.admin_accounts (id, full_name, username, email, role, password, active, created_at, last_login_at)
VALUES 
  ('a0000000-0000-0000-0000-000000000001', 'System Administrator', 'admin', 'admin@mipsedu.in', 'Super Administrator', 'admin123', true, now()::text, 'Active Now'),
  ('a0000000-0000-0000-0000-000000000002', 'Office Administrative Desk', 'office', 'office@mipsedu.in', 'Office Administrator', 'office123', true, now()::text, 'Yesterday')
ON CONFLICT (username) DO NOTHING;
