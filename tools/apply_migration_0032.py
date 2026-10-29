import os
import psycopg2

conn = psycopg2.connect(os.environ.get("DATABASE_URL", ""), connect_timeout=15)
cur = conn.cursor()

sql = """
-- Migration 0032: Update is_admin and is_teacher to recognize custom auth sessions
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
"""

cur.execute(sql)
conn.commit()
print("Migration 0032 applied successfully.")
conn.close()
