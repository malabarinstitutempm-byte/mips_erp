import os
import psycopg2

conn = psycopg2.connect(os.environ.get("DATABASE_URL", ""), connect_timeout=15)
cur = conn.cursor()

rpcs = ['import_students', 'undo_import', 'portal_verify_login', 'submit_attendance', 'mark_attendance']
for rpc in rpcs:
    cur.execute("SELECT proname, prosrc FROM pg_proc WHERE proname = %s;", (rpc,))
    rows = cur.fetchall()
    print(f"=== RPC {rpc} ===")
    if rows:
        print(rows[0][1][:400], '...')
    else:
        print("NOT FOUND!")

conn.close()
