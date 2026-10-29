import os
import psycopg2

conn = psycopg2.connect(os.environ.get("DATABASE_URL", ""), connect_timeout=15)
cur = conn.cursor()
cur.execute("SELECT count(*) FROM public.profiles;")
print(f"Total profiles: {cur.fetchone()[0]}")
cur.execute("SELECT id, user_id, role, active, email FROM public.profiles LIMIT 10;")
for r in cur.fetchall():
    print(r)

cur.execute("SELECT count(*) FROM auth.users;")
print(f"Total auth.users: {cur.fetchone()[0]}")
cur.execute("SELECT id, email FROM auth.users LIMIT 10;")
for r in cur.fetchall():
    print(r)

cur.execute("SELECT count(*) FROM admin_accounts;")
print(f"Total admin_accounts: {cur.fetchone()[0]}")
cur.execute("SELECT id, username, email, is_active FROM admin_accounts LIMIT 10;")
for r in cur.fetchall():
    print(r)

conn.close()
