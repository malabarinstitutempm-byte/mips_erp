import psycopg2
conn = psycopg2.connect('postgresql://postgres.evzehywyyqmcktszwmeg:AnzTzOTXxapp1Dys@aws-0-ap-south-1.pooler.supabase.com:6543/postgres', connect_timeout=15)
cur = conn.cursor()
for name in ['audit_log_trigger', 'trg_student_auto_enroll_and_fee', 'trg_batch_create_first_period', 'sync_batch_periods', 'check_course_structure_locked']:
    cur.execute("SELECT prosrc FROM pg_proc WHERE proname = %s;", (name,))
    row = cur.fetchone()
    print(f"=== {name} ===")
    if row:
        print(row[0][:500])
    else:
        print("NOT FOUND")
    print()
conn.close()
