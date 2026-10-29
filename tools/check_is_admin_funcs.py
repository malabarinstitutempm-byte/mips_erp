import os
import psycopg2

conn = psycopg2.connect(os.environ.get("DATABASE_URL", ""), connect_timeout=15)
cur = conn.cursor()
cur.execute("SELECT proname FROM pg_proc WHERE prosrc ILIKE '%is_admin()%' OR prosrc ILIKE '%is_admin %';")
for r in cur.fetchall():
    print(r[0])
conn.close()
