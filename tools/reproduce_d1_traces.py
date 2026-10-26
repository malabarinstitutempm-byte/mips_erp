import urllib.request
import urllib.error
import json
import psycopg2

SUPABASE_URL = "https://evzehywyyqmcktszwmeg.supabase.co"
ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImV2emVoeXd5eXFtY2t0c3p3bWVnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTE5NjM0MTYsImV4cCI6MjEwNzUzOTQxNn0.xNfdyP9f9if2INEdDdzGR4U04oItnt8XVhdM1-2Jnk4"
DB_CONN_STR = "postgresql://postgres.evzehywyyqmcktszwmeg:AnzTzOTXxapp1Dys@aws-0-ap-south-1.pooler.supabase.com:6543/postgres"

def get_db():
    return psycopg2.connect(DB_CONN_STR, connect_timeout=15)

def call_rest(path, method="GET", payload=None):
    url = f"{SUPABASE_URL}/rest/v1/{path}"
    headers = {
        "apikey": ANON_KEY,
        "Authorization": f"Bearer {ANON_KEY}",
        "Content-Type": "application/json",
        "Prefer": "return=representation"
    }
    data = json.dumps(payload).encode('utf-8') if payload is not None else None
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req) as resp:
            return resp.status, resp.read().decode()
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()
    except Exception as e:
        return 0, str(e)

def call_rpc(rpc_name, payload=None):
    url = f"{SUPABASE_URL}/rest/v1/rpc/{rpc_name}"
    headers = {
        "apikey": ANON_KEY,
        "Authorization": f"Bearer {ANON_KEY}",
        "Content-Type": "application/json",
    }
    data = json.dumps(payload or {}).encode('utf-8')
    req = urllib.request.Request(url, data=data, headers=headers, method="POST")
    try:
        with urllib.request.urlopen(req) as resp:
            return resp.status, resp.read().decode()
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()
    except Exception as e:
        return 0, str(e)

results = {}

conn = get_db()
cur = conn.cursor()

print("=" * 60)
print("RUNNING REPRODUCIBILITY TRACES FOR D1")
print("=" * 60)

# Flow 1: Course with subjects
print("\n--- 1. Course with subjects ---")
status, resp = call_rest("courses", "POST", {
    "name": "D1 Trace Course",
    "code": "D1-CRS",
    "duration": "2 Years",
    "total_fee_paise": 6000000,
    "status": "active",
    "course_type": "primary",
    "structure": "semester"
})
print("Course POST:", status, resp[:120])
course_id = None
if status in (200, 201):
    c_data = json.loads(resp)
    course_id = c_data[0]["id"]
    # Subjects
    sub_status, sub_resp = call_rest("course_subjects", "POST", [{
        "course_id": course_id,
        "subject_name": "Subject 1",
        "subject_code": "SUB101",
        "period_no": 1,
        "max_marks": 100,
        "pass_marks": 40
    }])
    print("Subjects POST:", sub_status, sub_resp[:120])

cur.execute("SELECT count(*) FROM courses WHERE code = 'D1-CRS';")
in_pg = cur.fetchone()[0] > 0
print(f"In Postgres: {in_pg}")
list_status, list_resp = call_rest("courses?select=id,name,code&code=eq.D1-CRS")
in_list = "D1-CRS" in list_resp
print(f"In List query: {in_list}")
results["course"] = {"status": status, "in_pg": in_pg, "in_list": in_list}

# Flow 2: Batch (with first batch_periods row)
print("\n--- 2. Batch with first batch_periods row ---")
batch_status, batch_resp = call_rest("batches", "POST", {
    "course_id": course_id or 1,
    "batch_name": "D1 Trace Batch",
    "start_date": "2026-08-01",
    "status": "active",
    "period_type": "semester",
    "current_semester": 1,
    "current_period": 1
})
print("Batch POST:", batch_status, batch_resp[:120])
batch_id = None
if batch_status in (200, 201):
    b_data = json.loads(batch_resp)
    batch_id = b_data[0]["id"]

cur.execute("SELECT count(*) FROM batches WHERE batch_name = 'D1 Trace Batch';")
batch_in_pg = cur.fetchone()[0] > 0
cur.execute("SELECT count(*) FROM batch_periods WHERE batch_id = %s;", (batch_id or -1,))
period_in_pg = cur.fetchone()[0] > 0
print(f"Batch in Postgres: {batch_in_pg}, batch_periods row in Postgres: {period_in_pg}")
list_status, list_resp = call_rest("batches?select=id,batch_name&batch_name=eq.D1 Trace Batch")
in_batch_list = "D1 Trace Batch" in list_resp
results["batch"] = {"status": batch_status, "in_pg": batch_in_pg, "period_in_pg": period_in_pg, "in_list": in_batch_list}

# Flow 3: Student admission (enrollment and fee item)
print("\n--- 3. Student admission (enrollment and fee item) ---")
stud_status, stud_resp = call_rest("students", "POST", {
    "name": "D1 Trace Student",
    "admission_number": "D1-ADM-001",
    "course_id": course_id,
    "batch_id": batch_id,
    "gender": "Male",
    "status": "active"
})
print("Student POST:", stud_status, stud_resp[:120])
student_id = None
if stud_status in (200, 201):
    s_data = json.loads(stud_resp)
    student_id = s_data[0]["id"]

cur.execute("SELECT count(*) FROM students WHERE admission_number = 'D1-ADM-001';")
stud_in_pg = cur.fetchone()[0] > 0
cur.execute("SELECT count(*) FROM student_enrollments WHERE student_id = %s;", (student_id or -1,))
enr_in_pg = cur.fetchone()[0] > 0
cur.execute("SELECT count(*) FROM fees WHERE student_id = %s;", (student_id or -1,))
fees_in_pg = cur.fetchone()[0] > 0
cur.execute("SELECT count(*) FROM fee_items WHERE student_id = %s;", (student_id or -1,))
fee_items_in_pg = cur.fetchone()[0] > 0
print(f"Student in Postgres: {stud_in_pg}, Enrollment: {enr_in_pg}, Fees row: {fees_in_pg}, Fee item: {fee_items_in_pg}")
results["student_admission"] = {
    "status": stud_status,
    "stud_in_pg": stud_in_pg,
    "enr_in_pg": enr_in_pg,
    "fees_in_pg": fees_in_pg,
    "fee_items_in_pg": fee_items_in_pg
}

# Flow 4: Excel Import RPC
print("\n--- 4. Excel Import RPC ---")
imp_status, imp_resp = call_rpc("import_students", {
    "p_students": [{
        "name": "Excel Student 1",
        "admission_number": "EXCEL-001",
        "course_id": course_id,
        "batch_id": batch_id,
        "gender": "Male"
    }]
})
print("import_students RPC:", imp_status, imp_resp[:160])
cur.execute("SELECT count(*) FROM students WHERE admission_number = 'EXCEL-001';")
excel_in_pg = cur.fetchone()[0] > 0
results["excel_import"] = {"status": imp_status, "in_pg": excel_in_pg, "resp": imp_resp}

# Flow 5: Teacher
print("\n--- 5. Teacher provisioning ---")
t_status, t_resp = call_rpc("admin_upsert_teacher", {
    "p_name": "D1 Trace Teacher",
    "p_username": "d1_teacher",
    "p_phone": "9876543210",
    "p_temp_password": "Temp@1234"
})
print("admin_upsert_teacher RPC:", t_status, t_resp[:160])
cur.execute("SELECT count(*) FROM teachers WHERE login_username = 'd1_teacher';")
teacher_in_pg = cur.fetchone()[0] > 0
teacher_id = None
if teacher_in_pg:
    cur.execute("SELECT id FROM teachers WHERE login_username = 'd1_teacher';")
    teacher_id = cur.fetchone()[0]
cur.execute("SELECT count(*) FROM portal_credentials WHERE identifier = 'd1_teacher';")
cred_in_pg = cur.fetchone()[0] > 0
print(f"Teacher in Postgres: {teacher_in_pg}, Credentials in Postgres: {cred_in_pg}")
results["teacher"] = {"status": t_status, "in_pg": teacher_in_pg, "cred_in_pg": cred_in_pg}

# Flow 6: Exam
print("\n--- 6. Exam creation ---")
exam_status, exam_resp = call_rest("exams", "POST", {
    "name": "D1 Semester 1 Exam",
    "course_id": course_id,
    "batch_id": batch_id,
    "semester": 1,
    "academic_year_id": 1,
    "exam_date": "2026-11-01",
    "status": "draft"
})
print("Exam POST:", exam_status, exam_resp[:120])
exam_id = None
if exam_status in (200, 201):
    ex_data = json.loads(exam_resp)
    exam_id = ex_data[0]["id"]
    call_rest("exam_subjects", "POST", [{
        "exam_id": exam_id,
        "name": "Subject 1",
        "code": "SUB101",
        "max_marks": 100,
        "pass_marks": 40
    }])
cur.execute("SELECT count(*) FROM exams WHERE name = 'D1 Semester 1 Exam';")
exam_in_pg = cur.fetchone()[0] > 0
print(f"Exam in Postgres: {exam_in_pg}")
results["exam"] = {"status": exam_status, "in_pg": exam_in_pg}

# Flow 7: Mark Entry RPC
print("\n--- 7. Mark Entry RPC ---")
cur.execute("SELECT id FROM exam_subjects WHERE exam_id = %s LIMIT 1;", (exam_id or -1,))
ex_sub_row = cur.fetchone()
ex_sub_id = ex_sub_row[0] if ex_sub_row else 1
mark_status, mark_resp = call_rpc("save_marks", {
    "p_exam_id": exam_id or 1,
    "p_marks": [{
        "subject_id": ex_sub_id,
        "student_id": student_id or 1,
        "marks_obtained": 75.0,
        "is_absent": False
    }]
})
print("save_marks RPC:", mark_status, mark_resp[:160])
cur.execute("SELECT count(*) FROM marks WHERE exam_id = %s;", (exam_id or -1,))
marks_in_pg = cur.fetchone()[0] > 0
print(f"Marks in Postgres: {marks_in_pg}")
results["mark_entry"] = {"status": mark_status, "in_pg": marks_in_pg, "resp": mark_resp}

# Flow 8: Payment and receipt
print("\n--- 8. Payment and receipt RPC ---")
pay_status, pay_resp = call_rpc("record_payment", {
    "p_student_id": student_id or 1,
    "p_amount_paise": 1000000,
    "p_mode": "cash",
    "p_reference": "D1-REF-001",
    "p_remarks": "First installment"
})
print("record_payment RPC:", pay_status, pay_resp[:160])
cur.execute("SELECT count(*) FROM payments WHERE reference_number = 'D1-REF-001';")
pay_in_pg = cur.fetchone()[0] > 0
print(f"Payment in Postgres: {pay_in_pg}")
results["payment"] = {"status": pay_status, "in_pg": pay_in_pg, "resp": pay_resp}

# Flow 9: Announcement RPC
print("\n--- 9. Announcement RPC ---")
ann_status, ann_resp = call_rpc("send_announcement", {
    "p_payload": {
        "category": "general",
        "title": "D1 Announcement",
        "body": "Test Announcement for D1",
        "audience_type": "all_students",
        "audience_ids": [],
        "min_balance_paise": 0,
        "dry_run": False
    }
})
print("send_announcement RPC:", ann_status, ann_resp[:160])
cur.execute("SELECT count(*) FROM announcements WHERE title = 'D1 Announcement';")
ann_in_pg = cur.fetchone()[0] > 0
print(f"Announcement in Postgres: {ann_in_pg}")
results["announcement"] = {"status": ann_status, "in_pg": ann_in_pg, "resp": ann_resp}

# Flow 10: Daily Timetable RPC
print("\n--- 10. Daily Timetable RPC ---")
tt_status, tt_resp = call_rpc("save_daily_timetable", {
    "p_date": "2026-10-27",
    "p_entries": [{
        "course_name": "D1 Trace Course",
        "year": "1st Year",
        "teacher_name": "D1 Trace Teacher",
        "subject_name": "Subject 1",
        "class_room": "Room 101",
        "start_time": "09:30",
        "end_time": "10:30",
        "sort_order": 1
    }]
})
print("save_daily_timetable RPC:", tt_status, tt_resp[:160])
cur.execute("SELECT count(*) FROM daily_timetables WHERE date = '2026-10-27';")
tt_in_pg = cur.fetchone()[0] > 0
print(f"Daily Timetable in Postgres: {tt_in_pg}")
results["daily_timetable"] = {"status": tt_status, "in_pg": tt_in_pg, "resp": tt_resp}

# Flow 11: Skill-course enrollment RPC
print("\n--- 11. Skill-course enrollment RPC ---")
# Need a skill course
cur.execute("INSERT INTO courses (name, code, course_type, total_fee_paise, status) VALUES ('Skill Python', 'SK-PY', 'skill', 500000, 'active') RETURNING id;")
skill_course_id = cur.fetchone()[0]
cur.execute("INSERT INTO batches (course_id, batch_name, status) VALUES (%s, 'Skill Batch 1', 'active') RETURNING id;", (skill_course_id,))
skill_batch_id = cur.fetchone()[0]
conn.commit()

skill_status, skill_resp = call_rpc("add_student_skill_course", {
    "p_student_id": student_id or 1,
    "p_course_id": skill_course_id,
    "p_batch_id": skill_batch_id,
    "p_fee_paise": 500000
})
print("add_student_skill_course RPC:", skill_status, skill_resp[:160])
cur.execute("SELECT count(*) FROM student_enrollments WHERE student_id = %s AND course_id = %s;", (student_id or 1, skill_course_id))
skill_in_pg = cur.fetchone()[0] > 0
print(f"Skill Enrollment in Postgres: {skill_in_pg}")
results["skill_course"] = {"status": skill_status, "in_pg": skill_in_pg, "resp": skill_resp}

# Flow 12: Attendance submit and correction RPC
print("\n--- 12. Attendance submit & correction RPC ---")
att_status, att_resp = call_rpc("submit_attendance", {
    "p_batch_id": batch_id or 1,
    "p_date": "2026-10-26",
    "p_slot": "morning",
    "p_records": [{
        "student_id": student_id or 1,
        "status": "present",
        "remarks": "On time"
    }],
    "p_no_class": False
})
print("submit_attendance RPC:", att_status, att_resp[:160])
cur.execute("SELECT count(*) FROM attendance_sessions WHERE batch_id = %s AND date = '2026-10-26';", (batch_id or 1,))
att_in_pg = cur.fetchone()[0] > 0
print(f"Attendance in Postgres: {att_in_pg}")
results["attendance"] = {"status": att_status, "in_pg": att_in_pg, "resp": att_resp}

# Flow 13: Batch completion & promotion RPC
print("\n--- 13. Batch promotion & completion RPC ---")
prom_status, prom_resp = call_rpc("promote_semester", {
    "p_batch_id": batch_id or 1,
    "p_closing_end_date": "2026-11-30",
    "p_new_start_date": "2026-12-01"
})
print("promote_semester RPC:", prom_status, prom_resp[:160])
cur.execute("SELECT current_semester FROM batches WHERE id = %s;", (batch_id or 1,))
b_sem = cur.fetchone()
print(f"Batch semester after promotion: {b_sem}")
results["batch_promotion"] = {"status": prom_status, "resp": prom_resp, "sem": b_sem}

# Flow 14: Password reset & unlock RPC
print("\n--- 14. Password reset & unlock RPC ---")
unlock_status, unlock_resp = call_rpc("admin_unlock_account", {
    "p_role": "teacher",
    "p_identifier": "d1_teacher"
})
print("admin_unlock_account RPC:", unlock_status, unlock_resp[:160])
results["unlock"] = {"status": unlock_status, "resp": unlock_resp}

# Clean up all created test records
print("\nCleaning up test rows...")
cur.execute("DELETE FROM payment_allocations WHERE payment_id IN (SELECT id FROM payments WHERE reference_number = 'D1-REF-001');")
cur.execute("DELETE FROM receipts WHERE receipt_number LIKE 'REC/%';")
cur.execute("DELETE FROM payments WHERE reference_number = 'D1-REF-001';")
cur.execute("DELETE FROM fee_items WHERE student_id IN (SELECT id FROM students WHERE admission_number IN ('D1-ADM-001', 'EXCEL-001'));")
cur.execute("DELETE FROM fees WHERE student_id IN (SELECT id FROM students WHERE admission_number IN ('D1-ADM-001', 'EXCEL-001'));")
cur.execute("DELETE FROM student_enrollments WHERE student_id IN (SELECT id FROM students WHERE admission_number IN ('D1-ADM-001', 'EXCEL-001'));")
cur.execute("DELETE FROM marks WHERE exam_id IN (SELECT id FROM exams WHERE name = 'D1 Semester 1 Exam');")
cur.execute("DELETE FROM exam_subjects WHERE exam_id IN (SELECT id FROM exams WHERE name = 'D1 Semester 1 Exam');")
cur.execute("DELETE FROM exams WHERE name = 'D1 Semester 1 Exam';")
cur.execute("DELETE FROM attendance_records WHERE session_id IN (SELECT id FROM attendance_sessions WHERE date = '2026-10-26');")
cur.execute("DELETE FROM attendance_sessions WHERE date = '2026-10-26';")
cur.execute("DELETE FROM daily_timetable_entries WHERE daily_timetable_id IN (SELECT id FROM daily_timetables WHERE date = '2026-10-27');")
cur.execute("DELETE FROM daily_timetables WHERE date = '2026-10-27';")
cur.execute("DELETE FROM announcements WHERE title = 'D1 Announcement';")
cur.execute("DELETE FROM profiles WHERE teacher_id IN (SELECT id FROM teachers WHERE login_username = 'd1_teacher');")
cur.execute("DELETE FROM portal_credentials WHERE identifier = 'd1_teacher';")
cur.execute("DELETE FROM teachers WHERE login_username = 'd1_teacher';")
cur.execute("DELETE FROM students WHERE admission_number IN ('D1-ADM-001', 'EXCEL-001');")
cur.execute("DELETE FROM batch_periods WHERE batch_id IN (SELECT id FROM batches WHERE batch_name IN ('D1 Trace Batch', 'Skill Batch 1'));")
cur.execute("DELETE FROM batches WHERE batch_name IN ('D1 Trace Batch', 'Skill Batch 1');")
cur.execute("DELETE FROM course_subjects WHERE course_id IN (SELECT id FROM courses WHERE code IN ('D1-CRS', 'SK-PY'));")
cur.execute("DELETE FROM courses WHERE code IN ('D1-CRS', 'SK-PY');")
conn.commit()
conn.close()
print("Cleanup complete.")
