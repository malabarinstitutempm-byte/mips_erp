import psycopg2

conn = psycopg2.connect("postgresql://postgres.evzehywyyqmcktszwmeg:AnzTzOTXxapp1Dys@aws-0-ap-south-1.pooler.supabase.com:6543/postgres", connect_timeout=15)
cur = conn.cursor()
cur.execute("SELECT trigger_name, event_manipulation, event_object_table, action_statement FROM information_schema.triggers WHERE event_object_table IN ('batches', 'students', 'courses');")
for r in cur.fetchall():
    print(r)
conn.close()
