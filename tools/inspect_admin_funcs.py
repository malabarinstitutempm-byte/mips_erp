import psycopg2

conn = psycopg2.connect('postgresql://postgres.evzehywyyqmcktszwmeg:AnzTzOTXxapp1Dys@aws-0-ap-south-1.pooler.supabase.com:6543/postgres', connect_timeout=15)
cur = conn.cursor()
cur.execute("""
SELECT proname, prosrc 
FROM pg_proc p 
JOIN pg_namespace n ON p.pronamespace = n.oid 
WHERE n.nspname = 'public' AND proname IN ('is_admin', 'is_teacher', 'require_admin_mfa', 'admin_check');
""")
for row in cur.fetchall():
    print(f'=== FUNCTION: {row[0]} ===')
    print(row[1])
    print()

cur.execute("""
SELECT proname 
FROM pg_proc p 
JOIN pg_namespace n ON p.pronamespace = n.oid 
WHERE n.nspname = 'public' AND (prosrc ILIKE '%is_admin%' OR prosrc ILIKE '%is_teacher%');
""")
print('=== FUNCTIONS CALLING is_admin or is_teacher ===')
funcs = [r[0] for r in cur.fetchall()]
print(', '.join(funcs))

conn.close()
