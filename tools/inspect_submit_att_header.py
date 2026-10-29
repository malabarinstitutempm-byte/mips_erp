import os
import psycopg2
conn = psycopg2.connect(os.environ.get("DATABASE_URL", ""), connect_timeout=15)
cur = conn.cursor()
cur.execute("SELECT prosrc FROM pg_proc WHERE proname = 'submit_attendance';")
lines = cur.fetchone()[0].split('\n')
for i, l in enumerate(lines[60:95]):
    print(i+60, l)
conn.close()
