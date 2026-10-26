import psycopg2

conn = psycopg2.connect('postgresql://postgres.evzehywyyqmcktszwmeg:AnzTzOTXxapp1Dys@aws-0-ap-south-1.pooler.supabase.com:6543/postgres', connect_timeout=15)
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
