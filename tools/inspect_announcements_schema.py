import psycopg2
conn = psycopg2.connect("postgresql://postgres.evzehywyyqmcktszwmeg:AnzTzOTXxapp1Dys@aws-0-ap-south-1.pooler.supabase.com:6543/postgres", connect_timeout=15)
cur = conn.cursor()
cur.execute("SELECT column_name, is_nullable, data_type FROM information_schema.columns WHERE table_name = 'announcements';")
for r in cur.fetchall():
    print(r)
conn.close()
