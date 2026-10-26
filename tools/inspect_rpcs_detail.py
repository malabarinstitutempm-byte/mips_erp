import psycopg2
conn = psycopg2.connect('postgresql://postgres.evzehywyyqmcktszwmeg:AnzTzOTXxapp1Dys@aws-0-ap-south-1.pooler.supabase.com:6543/postgres', connect_timeout=15)
cur = conn.cursor()

rpcs = ['record_payment', 'save_marks', 'submit_attendance', 'send_announcement', 
        'save_daily_timetable', 'add_student_skill_course', 'promote_semester', 'admin_unlock_account']

for rpc in rpcs:
    cur.execute("SELECT prosrc FROM pg_proc WHERE proname = %s;", (rpc,))
    rows = cur.fetchall()
    print(f"=== RPC: {rpc} (found {len(rows)}) ===")
    for r in rows:
        lines = r[0].split('\n')
        # print first 25 lines and any line containing auth.uid
        for l in lines[:20]:
            print("  ", l)
        for l in lines[20:]:
            if 'auth.' in l or 'created_by' in l:
                print("   [AUTH]", l)
    print()

conn.close()
