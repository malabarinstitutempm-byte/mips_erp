import os
import psycopg2

conn = psycopg2.connect(os.environ.get("DATABASE_URL", ""), connect_timeout=15)
cur = conn.cursor()

# Check publication supabase_realtime
cur.execute("SELECT pubname FROM pg_publication;")
pubs = [r[0] for r in cur.fetchall()]
print("Publications:", pubs)

if "supabase_realtime" in pubs:
    cur.execute("""
    SELECT schemaname, tablename 
    FROM pg_publication_tables 
    WHERE pubname = 'supabase_realtime';
    """)
    tables = [f"{r[0]}.{r[1]}" for r in cur.fetchall()]
    print("supabase_realtime tables (count=" + str(len(tables)) + "):")
    print(", ".join(tables))

# Check pg_net extension
cur.execute("SELECT extname FROM pg_extension;")
exts = [r[0] for r in cur.fetchall()]
print("\nExtensions:", ", ".join(exts))

conn.close()
