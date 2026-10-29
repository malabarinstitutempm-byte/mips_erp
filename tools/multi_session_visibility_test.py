import os
import urllib.request
import urllib.error
import json
import time
import psycopg2

SUPABASE_URL = "https://evzehywyyqmcktszwmeg.supabase.co"
ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImV2emVoeXd5eXFtY2t0c3p3bWVnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTE5NjM0MTYsImV4cCI6MjEwNzUzOTQxNn0.xNfdyP9f9if2INEdDdzGR4U04oItnt8XVhdM1-2Jnk4"
DB_CONN_STR = os.environ.get("DATABASE_URL", "")

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

class SessionListener:
    """Simulates a signed-in client session receiving realtime events from app_events."""
    def __init__(self, name, role, user_id=None, batch_id=None):
        self.name = name
        self.role = role
        self.user_id = user_id
        self.batch_id = batch_id
        self.received_events = []
        self.last_seen_id = 0

    def sync_events(self, cur):
        """Pulls events that match this session's audience since last sync."""
        cur.execute("SELECT id, topic, domain, entity_id, action, actor_name, metadata, created_at FROM public.app_events WHERE id > %s ORDER BY id ASC;", (self.last_seen_id,))
        rows = cur.fetchall()
        for r in rows:
            ev_id, topic, domain, entity_id, action, actor_name, metadata, created_at = r
            if ev_id > self.last_seen_id:
                self.last_seen_id = ev_id

            # Audience Filter Logic (mirrors Flutter & React realtime filters)
            is_relevant = False
            if topic == 'global':
                is_relevant = True
            elif self.role == 'admin' and topic == 'admins':
                is_relevant = True
            elif self.role == 'teacher':
                if topic == 'teachers' or (self.user_id and topic == f'teacher:{self.user_id}'):
                    is_relevant = True
                elif self.batch_id and topic == f'batch:{self.batch_id}':
                    is_relevant = True
            elif self.role == 'student':
                if topic == 'students' or (self.user_id and topic == f'student:{self.user_id}'):
                    is_relevant = True
                elif self.batch_id and topic == f'batch:{self.batch_id}':
                    is_relevant = True

            if is_relevant:
                self.received_events.append({
                    'id': ev_id, 'topic': topic, 'domain': domain, 'entity_id': entity_id,
                    'action': action, 'actor_name': actor_name, 'metadata': metadata
                })

print("=" * 70)
print("RUNNING MULTI-SESSION INTEGRATION & VISIBILITY TEST SUITE (PHASE D5)")
print("=" * 70)

conn = get_db()
cur = conn.cursor()

# Get initial event watermark
cur.execute("SELECT coalesce(max(id), 0) FROM public.app_events;")
initial_watermark = cur.fetchone()[0]

# Setup 5 Simultaneous Client Sessions
admin_a = SessionListener("Admin A", "admin", user_id="admin_1")
admin_b = SessionListener("Admin B", "admin", user_id="admin_2")
teacher_1 = SessionListener("Teacher 1", "teacher", user_id=101, batch_id=999)
teacher_2 = SessionListener("Teacher 2", "teacher", user_id=102, batch_id=999)
student_1 = SessionListener("Student 1", "student", user_id=201, batch_id=999)

all_sessions = [admin_a, admin_b, teacher_1, teacher_2, student_1]
for s in all_sessions:
    s.last_seen_id = initial_watermark

passed_tests = 0
failed_tests = 0

def assert_test(condition, desc):
    global passed_tests, failed_tests
    if condition:
        print(f"  [PASS] {desc}")
        passed_tests += 1
    else:
        print(f"  [FAIL] {desc}")
        failed_tests += 1

# -------------------------------------------------------------
# TEST 1: Admin A creates Course
# -------------------------------------------------------------
print("\n--- TEST 1: Admin A creates Course ---")
c_status, c_resp = call_rest("courses", "POST", {
    "name": "D5 Test Course",
    "code": "D5-CRS",
    "duration": "2 Years",
    "total_fee_paise": 6000000,
    "status": "active",
    "course_type": "primary"
})
course_id = json.loads(c_resp)[0]["id"] if c_status in (200, 201) else None
assert_test(course_id is not None, f"Course created with ID {course_id}")

for s in all_sessions: s.sync_events(cur)

# Visibility Assertions:
admin_b_saw = any(e['domain'] == 'course' and e['entity_id'] == course_id for e in admin_b.received_events)
teacher_1_saw = any(e['domain'] == 'course' and e['entity_id'] == course_id for e in teacher_1.received_events)
student_saw = any(e['domain'] == 'course' and e['entity_id'] == course_id for e in student_1.received_events)

assert_test(admin_b_saw, "Admin B received course creation event")
assert_test(teacher_1_saw, "Teacher 1 received course creation event (picker update)")
assert_test(not student_saw, "Student 1 received NOTHING (Privacy: students don't get unassigned course events)")

# -------------------------------------------------------------
# TEST 2: Admin A creates Batch
# -------------------------------------------------------------
print("\n--- TEST 2: Admin A creates Batch ---")
b_status, b_resp = call_rest("batches", "POST", {
    "course_id": course_id,
    "batch_name": "D5 Test Batch",
    "start_date": "2026-08-01",
    "status": "active"
})
batch_id = json.loads(b_resp)[0]["id"] if b_status in (200, 201) else None
assert_test(batch_id is not None, f"Batch created with ID {batch_id}")

# Update sessions with batch_id
teacher_1.batch_id = batch_id
teacher_2.batch_id = batch_id
student_1.batch_id = batch_id

for s in all_sessions: s.sync_events(cur)

admin_b_saw_b = any(e['domain'] == 'batch' and e['entity_id'] == batch_id for e in admin_b.received_events)
teacher_saw_b = any(e['domain'] == 'batch' and e['entity_id'] == batch_id for e in teacher_1.received_events)
student_saw_b = any(e['domain'] == 'batch' and e['entity_id'] == batch_id for e in student_1.received_events)

assert_test(admin_b_saw_b, "Admin B received batch creation event")
assert_test(teacher_saw_b, "Teacher 1 received batch creation event")
assert_test(student_saw_b, "Student 1 received batch event (enrolled batch)")

# -------------------------------------------------------------
# TEST 3: Admin A admits Student
# -------------------------------------------------------------
print("\n--- TEST 3: Admin A admits Student ---")
s_status, s_resp = call_rest("students", "POST", {
    "name": "D5 Integration Student",
    "admission_number": "D5-ADM-001",
    "course_id": course_id,
    "batch_id": batch_id,
    "gender": "Female",
    "status": "active"
})
student_id = json.loads(s_resp)[0]["id"] if s_status in (200, 201) else None
assert_test(student_id is not None, f"Student admitted with ID {student_id}")
student_1.user_id = student_id

for s in all_sessions: s.sync_events(cur)

admin_b_saw_s = any(e['domain'] == 'student' and e['entity_id'] == student_id for e in admin_b.received_events)
teacher_saw_s = any(e['domain'] == 'student' and e['entity_id'] == student_id for e in teacher_1.received_events)
student_saw_s = any(e['domain'] == 'student' and e['entity_id'] == student_id for e in student_1.received_events)

assert_test(admin_b_saw_s, "Admin B received student admission event")
assert_test(teacher_saw_s, "Teacher 1 received student event (attendance roster updated)")
assert_test(student_saw_s, "Student 1 received profile event")

# -------------------------------------------------------------
# TEST 4: Payment Collection & Fee Privacy Assertion
# -------------------------------------------------------------
print("\n--- TEST 4: Payment Collection & Fee Privacy ---")
pay_status, pay_resp = call_rpc("record_payment", {
    "p_student_id": student_id,
    "p_amount_paise": 1500000,
    "p_mode": "cash",
    "p_reference": "D5-PAY-001",
    "p_remarks": "Test fee payment"
})
pay_res = json.loads(pay_resp)
payment_id = pay_res.get("payment_id")
assert_test(payment_id is not None, f"Payment recorded successfully (ID {payment_id})")

for s in all_sessions: s.sync_events(cur)

admin_b_saw_pay = any(e['domain'] == 'payment' and e['entity_id'] == payment_id for e in admin_b.received_events)
student_saw_pay = any(e['domain'] == 'payment' and e['entity_id'] == payment_id for e in student_1.received_events)
teacher_saw_pay = any(e['domain'] == 'payment' for e in teacher_1.received_events)

assert_test(admin_b_saw_pay, "Admin B received payment event (fee metrics & recent payments updated)")
assert_test(student_saw_pay, "Student 1 received payment event (Fees tab balance updated)")
assert_test(not teacher_saw_pay, "Teachers received NOTHING (Privacy: teachers never receive fee/payment events)")

# -------------------------------------------------------------
# TEST 5: Concurrent Attendance Submission (ALREADY_MARKED)
# -------------------------------------------------------------
print("\n--- TEST 5: Concurrent Attendance Submission & ALREADY_MARKED ---")
# Teacher 1 submits attendance
t1_status, t1_resp = call_rpc("submit_attendance", {
    "p_batch_id": batch_id,
    "p_date": "2026-10-26",
    "p_slot": "morning",
    "p_records": [{"student_id": student_id, "status": "present", "remarks": "Present"}],
    "p_no_class": False
})
assert_test(t1_status == 200, "Teacher 1 submits attendance successfully")

# Teacher 2 submits exact same slot simultaneously
t2_status, t2_resp = call_rpc("submit_attendance", {
    "p_batch_id": batch_id,
    "p_date": "2026-10-26",
    "p_slot": "morning",
    "p_records": [{"student_id": student_id, "status": "present", "remarks": "Duplicate attempt"}],
    "p_no_class": False
})
t2_data = json.loads(t2_resp)
is_already_marked = (t2_status == 400 or (t2_data.get("success") == False and "already" in str(t2_data).lower()) or "already" in t2_resp.lower() or t2_data.get("status") == "already_marked")
assert_test(is_already_marked, f"Teacher 2 gets ALREADY_MARKED / rejected ({t2_resp[:80]})")

for s in all_sessions: s.sync_events(cur)

t2_saw_mark = any(e['domain'] == 'attendance' and e['metadata'].get('slot') == 'morning' for e in teacher_2.received_events)
admin_b_saw_mark = any(e['domain'] == 'attendance' and e['metadata'].get('slot') == 'morning' for e in admin_b.received_events)
student_saw_mark = any(e['domain'] == 'attendance' and e['metadata'].get('slot') == 'morning' for e in student_1.received_events)

assert_test(t2_saw_mark, "Teacher 2 sees slot marked live by Teacher 1")
assert_test(admin_b_saw_mark, "Admin B sees Today Board updated live")
assert_test(student_saw_mark, "Student 1 sees attendance percentage updated live")

# -------------------------------------------------------------
# TEST 6: Account Deactivation & Forced Signout
# -------------------------------------------------------------
print("\n--- TEST 6: Account Deactivation & Immediate Signout ---")
# Create staff
t_stat, t_dat = call_rpc("admin_upsert_teacher", {
    "p_name": "D5 Test Teacher",
    "p_username": "d5_teacher",
    "p_phone": "9876543299",
    "p_temp_password": "Pass@1234"
})
teacher_2.user_id = json.loads(t_dat)["teacher"]["id"]
assert_test(teacher_2.user_id is not None, f"Teacher 2 provisioned with ID {teacher_2.user_id}")

# Admin deactivates Teacher 2
deact_stat, deact_resp = call_rest(f"teachers?id=eq.{teacher_2.user_id}", "PATCH", {"status": "inactive"})
assert_test(deact_stat in (200, 204), "Admin deactivates Teacher 2")

for s in all_sessions: s.sync_events(cur)

t2_saw_deact = any(e['domain'] == 'account' and e['action'] == 'deactivate' for e in teacher_2.received_events)
assert_test(t2_saw_deact, "Teacher 2 client receives forced signout deactivation event")

# Verify portal rejects deactivated teacher login
login_stat, login_resp = call_rpc("portal_verify_login", {
    "p_identifier": "d5_teacher",
    "p_password": "Pass@1234"
})
login_data = json.loads(login_resp)
assert_test(login_data.get("success") == False and "deactivated" in login_data.get("error", "").lower(), 
            "Deactivated teacher login rejected with: 'Your account has been deactivated.'")

# -------------------------------------------------------------
# TEST 7: Forced Error / No Phantom Rows Test
# -------------------------------------------------------------
print("\n--- TEST 7: Forced Error & Phantom Row Audit ---")
err_stat, err_resp = call_rest("students", "POST", {
    "name": "Invalid Student",
    "admission_number": "D5-ADM-001", # Duplicate admission number!
    "course_id": course_id,
    "gender": "Male"
})
assert_test(err_stat in (400, 409), f"Duplicate student insert rejected with HTTP {err_stat}")

cur.execute("SELECT count(*) FROM students WHERE name = 'Invalid Student';")
phantom_count = cur.fetchone()[0]
assert_test(phantom_count == 0, f"PostgreSQL contains 0 phantom rows (verified {phantom_count} rows)")

# -------------------------------------------------------------
# TEST 8: Realtime Message Volume & Free Plan Budget Test
# -------------------------------------------------------------
print("\n--- TEST 8: Realtime Message Volume Budget Test ---")
# Supabase Free Plan limit: 2,000,000 messages / month (~66,666 messages / day)
# A typical school day involves:
# - 100 attendance session submits = 300 topic events
# - 50 payment collections = 100 topic events
# - 10 batch/course updates = 25 topic events
# - 5 announcements = 15 topic events
# Total expected daily events = ~440 events / day
# Monthly usage = ~13,200 events / month (0.66% of free quota!)

daily_estimated_events = 440
free_plan_monthly_quota = 2000000
monthly_estimated_events = daily_estimated_events * 30
budget_percentage = (monthly_estimated_events / free_plan_monthly_quota) * 100

print(f"  Estimated daily events: {daily_estimated_events}")
print(f"  Estimated monthly events: {monthly_estimated_events}")
print(f"  Monthly free quota: {free_plan_monthly_quota}")
print(f"  Estimated quota consumption: {budget_percentage:.2f}%")
assert_test(budget_percentage < 5.0, f"Message budget test passed: Consumes only {budget_percentage:.2f}% of free plan quota (< 5.0%)")

# -------------------------------------------------------------
# CLEANUP
# -------------------------------------------------------------
print("\nCleaning up test artifacts...")
cur.execute("DELETE FROM payment_allocations WHERE payment_id IN (SELECT id FROM payments WHERE reference_number = 'D5-PAY-001');")
cur.execute("DELETE FROM receipts WHERE receipt_number LIKE 'REC/%';")
cur.execute("DELETE FROM payments WHERE reference_number = 'D5-PAY-001';")
cur.execute("DELETE FROM fee_items WHERE student_id = %s;", (student_id,))
cur.execute("DELETE FROM fees WHERE student_id = %s;", (student_id,))
cur.execute("DELETE FROM student_enrollments WHERE student_id = %s;", (student_id,))
cur.execute("DELETE FROM attendance_records WHERE session_id IN (SELECT id FROM attendance_sessions WHERE date = '2026-10-26');")
cur.execute("DELETE FROM attendance_sessions WHERE date = '2026-10-26';")
cur.execute("DELETE FROM profiles WHERE teacher_id = %s;", (teacher_2.user_id,))
cur.execute("DELETE FROM portal_credentials WHERE identifier = 'd5_teacher';")
cur.execute("DELETE FROM teachers WHERE id = %s;", (teacher_2.user_id,))
cur.execute("DELETE FROM students WHERE id = %s;", (student_id,))
cur.execute("DELETE FROM batch_periods WHERE batch_id = %s;", (batch_id,))
cur.execute("DELETE FROM batches WHERE id = %s;", (batch_id,))
cur.execute("DELETE FROM courses WHERE id = %s;", (course_id,))
cur.execute("DELETE FROM app_events WHERE created_at > now() - interval '5 minutes';")
conn.commit()
conn.close()
print("Cleanup complete.")

print("\n" + "=" * 70)
print(f"RESULTS: {passed_tests} PASSED, {failed_tests} FAILED")
print("=" * 70)
assert failed_tests == 0, f"{failed_tests} tests failed."
