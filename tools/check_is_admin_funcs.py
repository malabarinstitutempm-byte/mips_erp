import psycopg2

conn = psycopg2.connect('postgresql://postgres.evzehywyyqmcktszwmeg:AnzTzOTXxapp1Dys@aws-0-ap-south-1.pooler.supabase.com:6543/postgres', connect_timeout=15)
cur = conn.cursor()
cur.execute("SELECT proname FROM pg_proc WHERE prosrc ILIKE '%is_admin()%' OR prosrc ILIKE '%is_admin %';")
for r in cur.fetchall():
    print(r[0])
conn.close()
