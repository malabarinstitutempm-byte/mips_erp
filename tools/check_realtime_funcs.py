import os
import psycopg2

conn = psycopg2.connect(os.environ.get("DATABASE_URL", ""), connect_timeout=15)
cur = conn.cursor()

cur.execute("""
SELECT nspname, proname 
FROM pg_proc p 
JOIN pg_namespace n ON p.pronamespace = n.oid 
WHERE proname ILIKE '%broadcast%' OR proname ILIKE '%realtime%';
""")
for r in cur.fetchall():
    print(r)

cur.execute("SELECT nspname FROM pg_namespace;")
print("\nNamespaces:", [r[0] for r in cur.fetchall()])

conn.close()
