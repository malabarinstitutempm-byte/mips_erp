import psycopg2
conn = psycopg2.connect("postgresql://postgres.evzehywyyqmcktszwmeg:AnzTzOTXxapp1Dys@aws-0-ap-south-1.pooler.supabase.com:6543/postgres", connect_timeout=15)
cur = conn.cursor()
cur.execute("SELECT prosrc FROM pg_proc WHERE proname = 'admin_upsert_teacher';")
print(cur.fetchone()[0])
conn.close()
