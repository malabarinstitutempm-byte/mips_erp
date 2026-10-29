import os
import psycopg2
conn = psycopg2.connect(os.environ.get("DATABASE_URL", ""), connect_timeout=15)
cur = conn.cursor()
cur.execute("SELECT column_name, data_type FROM information_schema.columns WHERE table_name = 'attendance_sessions';")
for r in cur.fetchall():
    print(r)
conn.close()
