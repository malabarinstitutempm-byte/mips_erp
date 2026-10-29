import os
import psycopg2

conn = psycopg2.connect(os.environ.get("DATABASE_URL", ""), connect_timeout=15)
cur = conn.cursor()
cur.execute("SELECT prosrc FROM pg_proc WHERE proname = 'admin_upsert_teacher';")
print(cur.fetchone()[0])
conn.close()
