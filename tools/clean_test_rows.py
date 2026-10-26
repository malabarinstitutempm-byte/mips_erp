import psycopg2

conn = psycopg2.connect("postgresql://postgres.evzehywyyqmcktszwmeg:AnzTzOTXxapp1Dys@aws-0-ap-south-1.pooler.supabase.com:6543/postgres", connect_timeout=15)
conn.autocommit = True
cur = conn.cursor()

# Clean in child-to-parent order
cur.execute("DELETE FROM fee_items WHERE student_id IN (SELECT id FROM students WHERE admission_number IN ('D1-ADM-001', 'EXCEL-001'));")
cur.execute("DELETE FROM fees WHERE student_id IN (SELECT id FROM students WHERE admission_number IN ('D1-ADM-001', 'EXCEL-001'));")
cur.execute("DELETE FROM student_enrollments WHERE student_id IN (SELECT id FROM students WHERE admission_number IN ('D1-ADM-001', 'EXCEL-001'));")
cur.execute("DELETE FROM students WHERE admission_number IN ('D1-ADM-001', 'EXCEL-001');")
cur.execute("DELETE FROM exam_subjects WHERE exam_id IN (SELECT id FROM exams WHERE name = 'D1 Semester 1 Exam');")
cur.execute("DELETE FROM exams WHERE name = 'D1 Semester 1 Exam';")
cur.execute("DELETE FROM batch_periods WHERE batch_id IN (SELECT id FROM batches WHERE batch_name IN ('D1 Trace Batch', 'Skill Batch 1'));")
cur.execute("DELETE FROM batches WHERE batch_name IN ('D1 Trace Batch', 'Skill Batch 1');")
cur.execute("DELETE FROM course_subjects WHERE course_id IN (SELECT id FROM courses WHERE code IN ('D1-CRS', 'SK-PY'));")
cur.execute("DELETE FROM courses WHERE code IN ('D1-CRS', 'SK-PY');")
cur.execute("DELETE FROM portal_credentials WHERE identifier = 'd1_teacher';")
cur.execute("DELETE FROM teachers WHERE login_username = 'd1_teacher';")

print("Cleaned all D1 test rows successfully.")
conn.close()
