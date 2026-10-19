import sqlite3
import os

db_path = os.path.join(os.path.expanduser("~"), "Documents", "MIPS_ERP_Database", "mips_erp.db")
conn = sqlite3.connect(db_path)
conn.row_factory = sqlite3.Row
c = conn.cursor()

out_path = os.path.join("supabase", "IMPORT_LOCAL_DATA.sql")
with open(out_path, "w", encoding="utf-8") as f:
    f.write("-- =============================================================================\n")
    f.write("-- MIPS ERP - Import Existing Data from Local Desktop SQLite to Supabase\n")
    f.write("-- Run this script AFTER running RUN_IN_SUPABASE_ALL_MIGRATIONS.sql\n")
    f.write("-- =============================================================================\n\n")

    # Settings
    f.write("-- 1. Settings\n")
    for r in c.execute("SELECT key, value FROM settings").fetchall():
        k = r["key"].replace("'", "''")
        v = (r["value"] or "").replace("'", "''")
        f.write(f"INSERT INTO settings (key, value) VALUES ('{k}', '{v}') ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;\n")
    f.write("\n")

    # Academic Years
    f.write("-- 2. Academic Years\n")
    for r in c.execute("SELECT id, year_name, is_current FROM academic_years").fetchall():
        is_cur = "true" if r["is_current"] == 1 else "false"
        f.write(f"INSERT INTO academic_years (id, legacy_id, year_name, start_date, end_date, is_current) OVERRIDING SYSTEM VALUE VALUES ({r['id']}, {r['id']}, '{r['year_name']}', '2026-06-01', '2027-05-31', {is_cur}) ON CONFLICT (id) DO NOTHING;\n")
    f.write("\n")

    # Universities
    f.write("-- 3. Universities\n")
    for r in c.execute("SELECT id, name FROM universities").fetchall():
        name = r["name"].replace("'", "''")
        f.write(f"INSERT INTO universities (id, legacy_id, name) OVERRIDING SYSTEM VALUE VALUES ({r['id']}, {r['id']}, '{name}') ON CONFLICT (id) DO NOTHING;\n")
    f.write("\n")

    # Courses
    f.write("-- 4. Courses\n")
    for r in c.execute("SELECT id, name, code, university_id, duration, total_fee, total_fee_paise, description, status, is_deleted FROM courses").fetchall():
        name = r["name"].replace("'", "''")
        code = (r["code"] or "").replace("'", "''")
        dur = r["duration"] or "2 Years"
        fee_p = int(r["total_fee_paise"] if r["total_fee_paise"] and r["total_fee_paise"] != 0 else round((r["total_fee"] or 0) * 100))
        desc = (r["description"] or "").replace("'", "''")
        st = (r["status"] or "active").lower()
        del_clause = "now()" if r["is_deleted"] == 1 else "NULL"
        f.write(f"INSERT INTO courses (id, legacy_id, name, code, university_id, duration, total_fee_paise, description, status, structure, deleted_at) OVERRIDING SYSTEM VALUE VALUES ({r['id']}, {r['id']}, '{name}', '{code}', {r['university_id']}, '{dur}', {fee_p}, '{desc}', '{st}', 'year', {del_clause}) ON CONFLICT (id) DO NOTHING;\n")
    f.write("\n")

    # Batches
    f.write("-- 5. Batches\n")
    for r in c.execute("SELECT id, course_id, batch_name, start_date, end_date, is_deleted FROM batches").fetchall():
        bname = r["batch_name"].replace("'", "''")
        sdate = f"'{r['start_date']}'" if r["start_date"] else "NULL"
        edate = f"'{r['end_date']}'" if r["end_date"] else "NULL"
        del_clause = "now()" if r["is_deleted"] == 1 else "NULL"
        f.write(f"INSERT INTO batches (id, legacy_id, course_id, batch_name, start_date, end_date, deleted_at) OVERRIDING SYSTEM VALUE VALUES ({r['id']}, {r['id']}, {r['course_id']}, '{bname}', {sdate}, {edate}, {del_clause}) ON CONFLICT (id) DO NOTHING;\n")
    f.write("\n")

    # Students & Enrollments
    f.write("-- 6. Students & Enrollments\n")
    for r in c.execute("SELECT * FROM students").fetchall():
        adm = (r["admission_number"] or "").replace("'", "''")
        reg_escaped = r["registration_number"].replace("'", "''") if r["registration_number"] else None
        reg = f"'{reg_escaped}'" if reg_escaped else "NULL"
        sname = (r["name"] or "").replace("'", "''")
        dob = f"'{r['dob']}'" if r["dob"] else "NULL"
        phone_escaped = r["phone"].replace("'", "''") if r["phone"] else None
        phone = f"'{phone_escaped}'" if phone_escaped else "NULL"
        email_escaped = r["email"].replace("'", "''") if r["email"] else None
        email = f"'{email_escaped}'" if email_escaped else "NULL"
        addr_escaped = r["address"].replace("'", "''") if r["address"] else None
        addr = f"'{addr_escaped}'" if addr_escaped else "NULL"
        adm_date = f"'{r['admission_date']}'" if r["admission_date"] else "CURRENT_DATE"
        gender = "Male" if (r["gender"] or "") not in ("Male", "Female", "Other") else r["gender"]
        status = "active"
        del_clause = "now()" if r["is_deleted"] == 1 else "NULL"
        f.write(f"INSERT INTO students (id, legacy_id, admission_number, registration_number, name, dob, gender, phone, email, address, admission_date, status, deleted_at) OVERRIDING SYSTEM VALUE VALUES ({r['id']}, {r['id']}, '{adm}', {reg}, '{sname}', {dob}, '{gender}', {phone}, {email}, {addr}, {adm_date}, '{status}', {del_clause}) ON CONFLICT (id) DO NOTHING;\n")
        f.write(f"INSERT INTO enrollments (student_id, course_id, batch_id, academic_year_id, status) VALUES ({r['id']}, {r['course_id']}, {r['batch_id']}, {r['academic_year_id']}, '{status}') ON CONFLICT (student_id, course_id, batch_id) DO NOTHING;\n")
    f.write("\n")

    # Resynchronize Sequences
    f.write("-- 7. Resynchronize Identity Sequences\n")
    for seq in ["courses", "batches", "students", "universities", "academic_years"]:
        f.write(f"SELECT setval(pg_get_serial_sequence('{seq}', 'id'), coalesce(max(id), 1)) FROM {seq};\n")

print(f"Generated {out_path} successfully from {db_path}!")
