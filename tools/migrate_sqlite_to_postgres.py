#!/usr/bin/env python3
"""
MIPS ERP Database Migration Tool: SQLite to Supabase PostgreSQL
=============================================================
Phase 1D: Reads local SQLite master database (mips_erp.db, read-only)
and loads data into Supabase Postgres as the single cloud master database.

Features:
- Read-only SQLite ingestion (?mode=ro)
- Dry-run mode: Comprehensive data anomaly & integrity analysis
- Preserves original integer IDs and sets legacy_id
- Converts all currency to integer paise (bigint)
- Normalizes enums and date stamps
- Single atomic transaction with automatic rollback on error
- Resets Postgres identity sequences and syncs number_counters
- Post-migration reconciliation report (row counts & paise totals)
- Zero secret logging
"""

import os
import sys
import argparse
import sqlite3
import re
from datetime import datetime
from urllib.parse import urlparse, urlunparse

try:
    import psycopg2
    from psycopg2.extras import execute_batch, RealDictCursor
except ImportError:
    psycopg2 = None


def redact_url(url: str) -> str:
    """Masks password in database connection strings for safe logging."""
    if not url:
        return "<EMPTY>"
    try:
        parsed = urlparse(url)
        if parsed.password:
            netloc = parsed.netloc.replace(f":{parsed.password}@", ":****@")
            return urlunparse(parsed._replace(netloc=netloc))
        return url
    except Exception:
        return "<REDACTED_URL>"


def parse_date(date_val):
    """Normalizes ISO timestamp strings to standard YYYY-MM-DD dates."""
    if not date_val:
        return None
    val_str = str(date_val).strip()
    if 'T' in val_str:
        val_str = val_str.split('T')[0]
    elif ' ' in val_str:
        val_str = val_str.split(' ')[0]
    
    # Verify YYYY-MM-DD
    if re.match(r'^\d{4}-\d{2}-\d{2}$', val_str):
        return val_str
    return None


def run_dry_run_analysis(sqlite_path: str):
    """
    Performs comprehensive data health and integrity audit on SQLite database.
    Detects duplicate admission numbers, orphan foreign keys, date issues,
    and non-integer money values.
    """
    print("\n" + "=" * 70)
    print("MIPS ERP DATA MIGRATION: DRY RUN HEALTH & INTEGRITY REPORT")
    print("=" * 70)
    print(f"Source Database: {sqlite_path}")
    print(f"Analysis Time:   {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print("-" * 70)

    if not os.path.isfile(sqlite_path):
        print(f"[ERROR] Source SQLite file not found: {sqlite_path}")
        return False

    uri = f"file:{os.path.abspath(sqlite_path)}?mode=ro"
    conn = sqlite3.connect(uri, uri=True)
    c = conn.cursor()

    has_critical_error = False

    # 1. Table Inventory & Row Counts
    print("\n[1] TABLE INVENTORY & ROW COUNTS:")
    tables_to_migrate = [
        'settings', 'academic_years', 'universities', 'courses', 'course_subjects',
        'batches', 'students', 'fees', 'payments', 'receipts', 'exams',
        'subjects', 'marks', 'results', 'grading_schemes', 'document_templates'
    ]
    
    counts = {}
    for tbl in tables_to_migrate:
        try:
            cnt = c.execute(f'SELECT COUNT(*) FROM "{tbl}"').fetchone()[0]
            counts[tbl] = cnt
            print(f"  - {tbl:<20} : {cnt:>6} records")
        except sqlite3.OperationalError:
            counts[tbl] = 0
            print(f"  - {tbl:<20} : (table not found in SQLite)")

    # 2. Duplicate Check
    print("\n[2] UNIQUE CONSTRAINT VALIDATION:")
    dups_adm = c.execute('''
        SELECT admission_number, COUNT(*) 
        FROM students 
        GROUP BY admission_number 
        HAVING COUNT(*) > 1
    ''').fetchall()

    if dups_adm:
        has_critical_error = True
        print(f"  [FAIL] Duplicate admission numbers detected: {dups_adm}")
    else:
        print("  [PASS] All student admission numbers are unique.")

    dups_rec = c.execute('''
        SELECT receipt_number, COUNT(*) 
        FROM receipts 
        GROUP BY receipt_number 
        HAVING COUNT(*) > 1
    ''').fetchall()

    if dups_rec:
        has_critical_error = True
        print(f"  [FAIL] Duplicate receipt numbers detected: {dups_rec}")
    else:
        print("  [PASS] All receipt numbers are unique.")

    # 3. Foreign Key Integrity Audit
    print("\n[3] FOREIGN KEY & ORPHAN AUDIT:")
    orphan_checks = [
        ("students -> courses", "SELECT id, admission_number, course_id FROM students WHERE course_id NOT IN (SELECT id FROM courses)"),
        ("students -> batches", "SELECT id, admission_number, batch_id FROM students WHERE batch_id NOT IN (SELECT id FROM batches)"),
        ("students -> universities", "SELECT id, admission_number, university_id FROM students WHERE university_id IS NOT NULL AND university_id NOT IN (SELECT id FROM universities)"),
        ("students -> academic_years", "SELECT id, admission_number, academic_year_id FROM students WHERE academic_year_id IS NOT NULL AND academic_year_id NOT IN (SELECT id FROM academic_years)"),
        ("batches -> courses", "SELECT id, batch_name, course_id FROM batches WHERE course_id NOT IN (SELECT id FROM courses)"),
        ("fees -> students", "SELECT id, student_id FROM fees WHERE student_id NOT IN (SELECT id FROM students)"),
        ("payments -> students", "SELECT id, student_id FROM payments WHERE student_id NOT IN (SELECT id FROM students)"),
        ("receipts -> payments", "SELECT id, payment_id FROM receipts WHERE payment_id NOT IN (SELECT id FROM payments)"),
        ("exams -> courses", "SELECT id, name, course_id FROM exams WHERE course_id NOT IN (SELECT id FROM courses)"),
        ("exams -> batches", "SELECT id, name, batch_id FROM exams WHERE batch_id NOT IN (SELECT id FROM batches)"),
        ("subjects -> exams", "SELECT id, name, exam_id FROM subjects WHERE exam_id NOT IN (SELECT id FROM exams)"),
        ("marks -> exams", "SELECT id, exam_id FROM marks WHERE exam_id NOT IN (SELECT id FROM exams)"),
        ("marks -> subjects", "SELECT id, subject_id FROM marks WHERE subject_id NOT IN (SELECT id FROM subjects)"),
        ("marks -> students", "SELECT id, student_id FROM marks WHERE student_id NOT IN (SELECT id FROM students)"),
        ("results -> exams", "SELECT id, exam_id FROM results WHERE exam_id NOT IN (SELECT id FROM exams)"),
        ("results -> students", "SELECT id, student_id FROM results WHERE student_id NOT IN (SELECT id FROM students)"),
    ]

    orphan_found = False
    for label, query in orphan_checks:
        try:
            res = c.execute(query).fetchall()
            if res:
                orphan_found = True
                has_critical_error = True
                print(f"  [FAIL] Orphan records in {label}: {len(res)} orphan(s) found!")
                for item in res[:3]:
                    print(f"         Sample: {item}")
            else:
                print(f"  [PASS] {label:<30} : 0 orphans")
        except sqlite3.OperationalError as e:
            print(f"  [SKIP] {label:<30} : table missing in source ({e})")

    # 4. Date Validation & Anomaly Detection
    print("\n[4] DATE & DATA SANITIZATION AUDIT:")
    bad_dob = c.execute("SELECT id, admission_number, dob FROM students WHERE dob IS NULL OR dob = ''").fetchall()
    if bad_dob:
        print(f"  [NOTE] {len(bad_dob)} student(s) have NULL or missing DOB (will be migrated as NULL).")
    else:
        print("  [PASS] All students have valid DOB.")

    bad_genders = c.execute("SELECT DISTINCT gender FROM students").fetchall()
    print(f"  [INFO] Distinct student genders found: {[g[0] for g in bad_genders]}")
    print("         Values not in ('Male', 'Female', 'Other') will normalize to 'Male'.")

    # 5. Financial Precision & Reconciliation Audit
    print("\n[5] FINANCIAL PRECISION AUDIT:")
    fee_tot = c.execute('''
        SELECT 
            COALESCE(SUM(total_fee_paise), 0),
            COALESCE(SUM(paid_amount_paise), 0),
            COALESCE(SUM(pending_amount_paise), 0)
        FROM fees
    ''').fetchone()

    pay_tot = c.execute('''
        SELECT COALESCE(SUM(amount_paise), 0)
        FROM payments 
        WHERE is_cancelled = 0 OR is_cancelled IS NULL
    ''').fetchone()[0]

    tot_fee, tot_paid, tot_pending = fee_tot

    print(f"  - Total Fee Obligations : {tot_fee:>12} paise (INR {tot_fee / 100:,.2f})")
    print(f"  - Total Fee Paid Ledger : {tot_paid:>12} paise (INR {tot_paid / 100:,.2f})")
    print(f"  - Total Pending Balances: {tot_pending:>12} paise (INR {tot_pending / 100:,.2f})")
    print(f"  - Total Valid Payments  : {pay_tot:>12} paise (INR {pay_tot / 100:,.2f})")

    # Reconcile Paid Ledger vs Payments
    if tot_paid == pay_tot:
        print("  [PASS] Fee Paid Ledger matches Total Payments EXACTLY to the paise.")
    else:
        diff = abs(tot_paid - pay_tot)
        print(f"  [WARN] Discrepancy between fee paid ledger and payments: {diff} paise (INR {diff / 100:,.2f})")

    if (tot_fee - tot_paid) == tot_pending:
        print("  [PASS] Total Fee - Paid = Pending balance math is 100% consistent.")
    else:
        diff = abs((tot_fee - tot_paid) - tot_pending)
        print(f"  [FAIL] Pending balance ledger calculation mismatch: {diff} paise!")
        has_critical_error = True

    print("\n" + "=" * 70)
    if has_critical_error:
        print("DRY RUN RESULT: CRITICAL ERRORS FOUND. Review output before migration.")
    else:
        print("DRY RUN RESULT: ALL INTEGRITY CHECKS PASSED. Ready for migration.")
    print("=" * 70 + "\n")

    conn.close()
    return not has_critical_error


def execute_migration(sqlite_path: str, pg_url: str):
    """
    Executes transactional database migration from SQLite into Supabase PostgreSQL.
    Guarantees:
    - Atomicity: 1 single transaction with rollback on ANY error.
    - Idempotency & Identity alignment: Keeps original IDs and updates sequences.
    - Currency precision: Integer paise everywhere.
    - Full post-migration reconciliation.
    """
    if psycopg2 is None:
        print("[ERROR] psycopg2 is not installed. Please run: pip install psycopg2-binary")
        sys.exit(1)

    print("\n" + "=" * 70)
    print("MIPS ERP DATABASE MIGRATION: SQLITE -> SUPABASE POSTGRESQL")
    print("=" * 70)
    print(f"Source Database : {sqlite_path}")
    print(f"Target Database : {redact_url(pg_url)}")
    print(f"Execution Time  : {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print("-" * 70)

    # 1. Connect to SQLite in read-only mode
    uri = f"file:{os.path.abspath(sqlite_path)}?mode=ro"
    sqlite_conn = sqlite3.connect(uri, uri=True)
    sqlite_conn.row_factory = sqlite3.Row
    s_cur = sqlite_conn.cursor()

    # 2. Connect to Postgres
    try:
        pg_conn = psycopg2.connect(pg_url)
        pg_conn.autocommit = False
        p_cur = pg_conn.cursor()
    except Exception as e:
        print(f"[FATAL] Failed to connect to PostgreSQL: {e}")
        sys.exit(1)

    try:
        print("\n>>> Step 1/6: Pre-migration Table Sanitation...")
        # Clean migrated tables in reverse dependency order inside transaction
        clean_tables = [
            'marks', 'results', 'exam_subjects', 'exams',
            'receipts', 'payments', 'fees',
            'attendance_records', 'attendance_sessions', 'teacher_assignments',
            'students', 'batches', 'course_subjects', 'courses',
            'universities', 'academic_years', 'document_templates'
        ]
        for tbl in clean_tables:
            p_cur.execute(f"TRUNCATE TABLE {tbl} RESTART IDENTITY CASCADE;")
        print("    Target tables cleanly truncated.")

        print("\n>>> Step 2/6: Migrating Core Masters & Infrastructure...")

        # 2.1 Settings
        s_rows = s_cur.execute("SELECT key, value FROM settings").fetchall()
        for r in s_rows:
            p_cur.execute("""
                INSERT INTO settings (key, value)
                VALUES (%s, %s)
                ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
            """, (r['key'], r['value']))
        print(f"    Migrated settings: {len(s_rows)} rows")

        # 2.2 Academic Years
        s_rows = s_cur.execute("SELECT id, year_name, is_current FROM academic_years").fetchall()
        for r in s_rows:
            p_cur.execute("""
                INSERT INTO academic_years (id, legacy_id, year_name, is_current)
                OVERRIDING SYSTEM VALUE
                VALUES (%s, %s, %s, %s);
            """, (r['id'], r['id'], r['year_name'], bool(r['is_current'])))
        print(f"    Migrated academic_years: {len(s_rows)} rows")

        # 2.3 Universities
        s_rows = s_cur.execute("SELECT id, name FROM universities").fetchall()
        for r in s_rows:
            p_cur.execute("""
                INSERT INTO universities (id, legacy_id, name)
                OVERRIDING SYSTEM VALUE
                VALUES (%s, %s, %s);
            """, (r['id'], r['id'], r['name']))
        print(f"    Migrated universities: {len(s_rows)} rows")

        # 2.4 Courses
        s_rows = s_cur.execute("""
            SELECT id, name, code, university_id, duration, total_fee, total_fee_paise, description, status, is_deleted 
            FROM courses
        """).fetchall()
        for r in s_rows:
            fee_paise = int(r['total_fee_paise'] if r['total_fee_paise'] is not None and r['total_fee_paise'] != 0 else round((r['total_fee'] or 0) * 100))
            del_at = datetime.now() if r['is_deleted'] == 1 else None
            p_cur.execute("""
                INSERT INTO courses (id, legacy_id, name, code, university_id, duration, total_fee_paise, description, status, deleted_at)
                OVERRIDING SYSTEM VALUE
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s);
            """, (r['id'], r['id'], r['name'], r['code'], r['university_id'], r['duration'], fee_paise, r['description'], (r['status'] or 'active').lower(), del_at))
        print(f"    Migrated courses: {len(s_rows)} rows")

        # 2.5 Course Subjects (if any)
        try:
            s_rows = s_cur.execute("""
                SELECT id, course_id, semester, subject_name, subject_code, max_marks, pass_marks 
                FROM course_subjects
            """).fetchall()
            for r in s_rows:
                p_cur.execute("""
                    INSERT INTO course_subjects (id, legacy_id, course_id, semester, subject_name, subject_code, max_marks, pass_marks)
                    OVERRIDING SYSTEM VALUE
                    VALUES (%s, %s, %s, %s, %s, %s, %s, %s);
                """, (r['id'], r['id'], r['course_id'], r['semester'], r['subject_name'], r['subject_code'], r['max_marks'], r['pass_marks']))
            print(f"    Migrated course_subjects: {len(s_rows)} rows")
        except sqlite3.OperationalError:
            pass

        # 2.6 Batches
        s_rows = s_cur.execute("""
            SELECT id, course_id, batch_name, start_date, end_date, is_deleted 
            FROM batches
        """).fetchall()
        for r in s_rows:
            del_at = datetime.now() if r['is_deleted'] == 1 else None
            p_cur.execute("""
                INSERT INTO batches (id, legacy_id, course_id, batch_name, start_date, end_date, deleted_at)
                OVERRIDING SYSTEM VALUE
                VALUES (%s, %s, %s, %s, %s, %s, %s);
            """, (r['id'], r['id'], r['course_id'], r['batch_name'], parse_date(r['start_date']), parse_date(r['end_date']), del_at))
        print(f"    Migrated batches: {len(s_rows)} rows")

        print("\n>>> Step 3/6: Migrating Students & Financial Ledgers...")

        # 3.1 Students
        s_rows = s_cur.execute("""
            SELECT id, admission_number, registration_number, name, course_id, batch_id, university_id, academic_year_id,
                   dob, gender, phone, email, address, admission_date, status, is_deleted, import_id
            FROM students
        """).fetchall()
        for r in s_rows:
            gender_val = (r['gender'] or '').strip()
            if gender_val not in ('Male', 'Female', 'Other'):
                gender_val = 'Male'
            
            status_val = (r['status'] or 'active').strip().lower()
            if status_val not in ('active', 'passed_out', 'discontinued', 'tc_issued'):
                status_val = 'active'

            del_at = datetime.now() if r['is_deleted'] == 1 else None

            p_cur.execute("""
                INSERT INTO students (
                    id, legacy_id, admission_number, registration_number, name, dob, gender, phone, email, address,
                    admission_date, course_id, batch_id, university_id, academic_year_id, status, import_id, deleted_at
                )
                OVERRIDING SYSTEM VALUE
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s);
            """, (
                r['id'], r['id'], r['admission_number'], r['registration_number'], r['name'],
                parse_date(r['dob']), gender_val, r['phone'], r['email'], r['address'],
                parse_date(r['admission_date']), r['course_id'], r['batch_id'], r['university_id'],
                r['academic_year_id'], status_val, r['import_id'], del_at
            ))
        print(f"    Migrated students: {len(s_rows)} rows")

        # 3.2 Fees Ledger
        s_rows = s_cur.execute("""
            SELECT id, student_id, total_fee, paid_amount, pending_amount, total_fee_paise, paid_amount_paise, pending_amount_paise
            FROM fees
        """).fetchall()
        for r in s_rows:
            tot_p = int(r['total_fee_paise'] if r['total_fee_paise'] is not None and r['total_fee_paise'] != 0 else round((r['total_fee'] or 0) * 100))
            paid_p = int(r['paid_amount_paise'] if r['paid_amount_paise'] is not None and r['paid_amount_paise'] != 0 else round((r['paid_amount'] or 0) * 100))
            pend_p = int(r['pending_amount_paise'] if r['pending_amount_paise'] is not None and r['pending_amount_paise'] != 0 else round((r['pending_amount'] or 0) * 100))

            p_cur.execute("""
                INSERT INTO fees (id, legacy_id, student_id, total_fee_paise, paid_amount_paise, pending_amount_paise)
                OVERRIDING SYSTEM VALUE
                VALUES (%s, %s, %s, %s, %s, %s);
            """, (r['id'], r['id'], r['student_id'], tot_p, paid_p, pend_p))
        print(f"    Migrated fees: {len(s_rows)} rows")

        # 3.3 Payments
        s_rows = s_cur.execute("""
            SELECT id, student_id, amount, amount_paise, payment_mode, reference_number, remarks, date,
                   is_cancelled, cancel_reason, cancelled_at, is_deleted
            FROM payments
        """).fetchall()
        for r in s_rows:
            amt_p = int(r['amount_paise'] if r['amount_paise'] is not None and r['amount_paise'] != 0 else round((r['amount'] or 0) * 100))
            mode_val = (r['payment_mode'] or 'cash').strip().lower()
            if mode_val not in ('cash', 'upi', 'bank_transfer', 'cheque', 'other'):
                mode_val = 'other'

            del_at = datetime.now() if r['is_deleted'] == 1 else None

            p_cur.execute("""
                INSERT INTO payments (
                    id, legacy_id, student_id, amount_paise, payment_mode, reference_number, remarks, date,
                    is_cancelled, cancel_reason, cancelled_at, deleted_at
                )
                OVERRIDING SYSTEM VALUE
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s);
            """, (
                r['id'], r['id'], r['student_id'], amt_p, mode_val, r['reference_number'], r['remarks'],
                parse_date(r['date']), bool(r['is_cancelled']), r['cancel_reason'], r['cancelled_at'], del_at
            ))
        print(f"    Migrated payments: {len(s_rows)} rows")

        # 3.4 Receipts
        s_rows = s_cur.execute("""
            SELECT id, payment_id, receipt_number
            FROM receipts
        """).fetchall()
        for r in s_rows:
            p_cur.execute("""
                INSERT INTO receipts (id, legacy_id, payment_id, receipt_number)
                OVERRIDING SYSTEM VALUE
                VALUES (%s, %s, %s, %s);
            """, (r['id'], r['id'], r['payment_id'], r['receipt_number']))
        print(f"    Migrated receipts: {len(s_rows)} rows")

        print("\n>>> Step 4/6: Migrating Examinations, Marks & Results...")

        # 4.1 Exams
        # Check published_exams lookup table in SQLite
        pub_exams = {}
        try:
            for p in s_cur.execute("SELECT exam_id, published_at FROM published_exams").fetchall():
                pub_exams[p['exam_id']] = p['published_at']
        except sqlite3.OperationalError:
            pass

        s_rows = s_cur.execute("""
            SELECT id, name, academic_year_id, course_id, batch_id, exam_date, publish_date, status, semester, is_deleted
            FROM exams
        """).fetchall()
        for r in s_rows:
            is_pub = (r['id'] in pub_exams) or ((r['status'] or '').lower() == 'published')
            exam_stat = 'published' if is_pub else 'draft'
            pub_time = pub_exams.get(r['id']) or (datetime.now() if is_pub else None)
            del_at = datetime.now() if r['is_deleted'] == 1 else None

            p_cur.execute("""
                INSERT INTO exams (
                    id, legacy_id, course_id, batch_id, academic_year_id, name, semester, exam_date,
                    publish_date, status, published_at, deleted_at
                )
                OVERRIDING SYSTEM VALUE
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s);
            """, (
                r['id'], r['id'], r['course_id'], r['batch_id'], r['academic_year_id'], r['name'],
                r['semester'], parse_date(r['exam_date']), parse_date(r['publish_date']), exam_stat, pub_time, del_at
            ))
        print(f"    Migrated exams: {len(s_rows)} rows")

        # 4.2 Exam Subjects (from SQLite `subjects`)
        s_rows = s_cur.execute("""
            SELECT id, exam_id, name, code, max_marks, pass_marks, theory_marks, practical_marks, display_order
            FROM subjects
        """).fetchall()
        for r in s_rows:
            p_cur.execute("""
                INSERT INTO exam_subjects (
                    id, legacy_id, exam_id, name, code, max_marks, pass_marks, theory_marks, practical_marks, display_order
                )
                OVERRIDING SYSTEM VALUE
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s);
            """, (
                r['id'], r['id'], r['exam_id'], r['name'], r['code'], r['max_marks'], r['pass_marks'],
                r['theory_marks'], r['practical_marks'], r['display_order'] or 0
            ))
        print(f"    Migrated exam_subjects: {len(s_rows)} rows")

        # 4.3 Marks
        s_rows = s_cur.execute("""
            SELECT id, exam_id, subject_id, student_id, marks_obtained, grade, status
            FROM marks
        """).fetchall()
        for r in s_rows:
            is_abs = (r['marks_obtained'] is None) or ((r['status'] or '').lower() == 'absent')
            p_cur.execute("""
                INSERT INTO marks (id, legacy_id, exam_id, subject_id, student_id, marks_obtained, is_absent, grade, status)
                OVERRIDING SYSTEM VALUE
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s);
            """, (r['id'], r['id'], r['exam_id'], r['subject_id'], r['student_id'], r['marks_obtained'], is_abs, r['grade'], r['status']))
        print(f"    Migrated marks: {len(s_rows)} rows")

        # 4.4 Results
        s_rows = s_cur.execute("""
            SELECT id, exam_id, student_id, total_marks, percentage, grade, status, rank
            FROM results
        """).fetchall()
        for r in s_rows:
            stat_val = (r['status'] or 'PASS').strip().upper()
            if stat_val not in ('PASS', 'FAIL', 'PENDING', 'WITHHELD'):
                stat_val = 'PASS'
            p_cur.execute("""
                INSERT INTO results (id, legacy_id, exam_id, student_id, total_marks, percentage, grade, status, rank)
                OVERRIDING SYSTEM VALUE
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s);
            """, (r['id'], r['id'], r['exam_id'], r['student_id'], r['total_marks'], r['percentage'], r['grade'], stat_val, r['rank']))
        print(f"    Migrated results: {len(s_rows)} rows")

        # 4.5 Document Templates
        s_rows = s_cur.execute("SELECT id, name, content FROM document_templates").fetchall()
        for r in s_rows:
            p_cur.execute("""
                INSERT INTO document_templates (id, legacy_id, name, content)
                OVERRIDING SYSTEM VALUE
                VALUES (%s, %s, %s, %s);
            """, (r['id'], r['id'], r['name'], r['content']))
        print(f"    Migrated document_templates: {len(s_rows)} rows")

        print("\n>>> Step 5/6: Synchronizing Identity Sequences & Number Counters...")
        seq_tables = [
            'academic_years', 'universities', 'courses', 'course_subjects', 'batches',
            'students', 'fees', 'payments', 'receipts', 'exams', 'exam_subjects',
            'marks', 'results', 'document_templates'
        ]
        for tbl in seq_tables:
            p_cur.execute(f"""
                SELECT setval(pg_get_serial_sequence('{tbl}', 'id'), COALESCE((SELECT MAX(id) FROM {tbl}), 1));
            """)
        print("    All primary key identity sequences synchronized to MAX(id).")

        # Sync number_counters for sequential generator
        # 1. Admission numbers (e.g. ADM-2026-0011)
        p_cur.execute("""
            SELECT COALESCE(MAX(
                NULLIF(regexp_replace(admission_number, '.*-(\\d+)$', '\\1'), '')::bigint
            ), 0)
            FROM students
            WHERE admission_number ~ '-\\d+$';
        """)
        max_adm = p_cur.fetchone()[0] or 0
        curr_year = datetime.now().year
        p_cur.execute("""
            INSERT INTO number_counters (kind, year, last_value)
            VALUES ('admission', %s, %s)
            ON CONFLICT (kind, year) DO UPDATE SET last_value = GREATEST(number_counters.last_value, EXCLUDED.last_value);
        """, (curr_year, max_adm))

        # 2. Receipt numbers (e.g. MIPS/2026/0005)
        p_cur.execute("""
            SELECT COALESCE(MAX(
                NULLIF(regexp_replace(receipt_number, '.*[/-](\\d+)$', '\\1'), '')::bigint
            ), 0)
            FROM receipts
            WHERE receipt_number ~ '[/-]\\d+$';
        """)
        max_rec = p_cur.fetchone()[0] or 0
        p_cur.execute("""
            INSERT INTO number_counters (kind, year, last_value)
            VALUES ('receipt', %s, %s)
            ON CONFLICT (kind, year) DO UPDATE SET last_value = GREATEST(number_counters.last_value, EXCLUDED.last_value);
        """, (curr_year, max_rec))
        print(f"    Synchronized number_counters: admission={max_adm}, receipt={max_rec} for year {curr_year}.")

        print("\n>>> Step 6/6: Verifying Reconciliation & Integrity...")
        # Reconcile Row Counts
        reconcile_tables = [
            ('settings', 'settings'),
            ('academic_years', 'academic_years'),
            ('universities', 'universities'),
            ('courses', 'courses'),
            ('batches', 'batches'),
            ('students', 'students'),
            ('fees', 'fees'),
            ('payments', 'payments'),
            ('receipts', 'receipts'),
            ('exams', 'exams'),
            ('subjects', 'exam_subjects'),
            ('marks', 'marks'),
            ('results', 'results'),
            ('document_templates', 'document_templates'),
        ]

        print("\n" + "-" * 70)
        print(f"{'Table':<25} | {'SQLite Count':>15} | {'Postgres Count':>15} | {'Status':>8}")
        print("-" * 70)
        all_counts_match = True
        for s_tbl, p_tbl in reconcile_tables:
            s_count = s_cur.execute(f'SELECT COUNT(*) FROM "{s_tbl}"').fetchone()[0]
            p_cur.execute(f'SELECT COUNT(*) FROM "{p_tbl}"')
            p_count = p_cur.fetchone()[0]
            status = "MATCH" if s_count == p_count else "MISMATCH"
            if s_count != p_count:
                all_counts_match = False
            print(f"{p_tbl:<25} | {s_count:>15} | {p_count:>15} | {status:>8}")
        print("-" * 70)

        # Reconcile Financials
        s_fee_tot = s_cur.execute('''
            SELECT 
                COALESCE(SUM(total_fee_paise), 0),
                COALESCE(SUM(paid_amount_paise), 0),
                COALESCE(SUM(pending_amount_paise), 0)
            FROM fees
        ''').fetchone()
        s_pay_tot = s_cur.execute('''
            SELECT COALESCE(SUM(amount_paise), 0)
            FROM payments WHERE is_cancelled = 0 OR is_cancelled IS NULL
        ''').fetchone()[0]

        p_cur.execute('''
            SELECT 
                COALESCE(SUM(total_fee_paise), 0),
                COALESCE(SUM(paid_amount_paise), 0),
                COALESCE(SUM(pending_amount_paise), 0)
            FROM fees
        ''')
        p_fee_tot = p_cur.fetchone()

        p_cur.execute('''
            SELECT COALESCE(SUM(amount_paise), 0)
            FROM payments WHERE is_cancelled = false
        ''')
        p_pay_tot = p_cur.fetchone()[0]

        print("\nFINANCIAL RECONCILIATION AUDIT (EXACT PAISE):")
        print("-" * 70)
        print(f"{'Metric':<25} | {'SQLite (Paise)':>15} | {'Postgres (Paise)':>16} | {'Status':>8}")
        print("-" * 70)
        print(f"{'Total Fee Obligations':<25} | {s_fee_tot[0]:>15} | {p_fee_tot[0]:>16} | {'MATCH' if s_fee_tot[0] == p_fee_tot[0] else 'MISMATCH':>8}")
        print(f"{'Total Fee Paid Ledger':<25} | {s_fee_tot[1]:>15} | {p_fee_tot[1]:>16} | {'MATCH' if s_fee_tot[1] == p_fee_tot[1] else 'MISMATCH':>8}")
        print(f"{'Total Pending Balance':<25} | {s_fee_tot[2]:>15} | {p_fee_tot[2]:>16} | {'MATCH' if s_fee_tot[2] == p_fee_tot[2] else 'MISMATCH':>8}")
        print(f"{'Total Valid Payments':<25} | {s_pay_tot:>15} | {p_pay_tot:>16} | {'MATCH' if s_pay_tot == p_pay_tot else 'MISMATCH':>8}")
        print("-" * 70)

        if not all_counts_match or s_fee_tot != p_fee_tot or s_pay_tot != p_pay_tot:
            raise Exception("Post-migration reconciliation check failed! Rolling back transaction.")

        # Commit transaction
        pg_conn.commit()
        print("\n" + "=" * 70)
        print("TRANSACTION COMMITTED: MIGRATION COMPLETED SUCCESSFULLY WITH 100% RECONCILIATION!")
        print("=" * 70 + "\n")

    except Exception as e:
        pg_conn.rollback()
        print(f"\n[FATAL ERROR DURING MIGRATION] Transaction rolled back safely: {e}")
        raise
    finally:
        sqlite_conn.close()
        pg_conn.close()


def main():
    parser = argparse.ArgumentParser(description="MIPS ERP SQLite to Supabase Postgres Migration Engine")
    parser.add_argument(
        "--sqlite-path",
        default=os.path.join(os.path.expanduser("~"), "Documents", "MIPS_ERP_Database", "mips_erp.db"),
        help="Path to source SQLite database file"
    )
    parser.add_argument(
        "--db-url",
        default=None,
        help="PostgreSQL connection string (or use SUPABASE_DB_URL / DATABASE_URL env var)"
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Run health and integrity analysis on SQLite data without connecting to or modifying Postgres"
    )

    args = parser.parse_args()

    # Dry-run execution
    if args.dry_run:
        success = run_dry_run_analysis(args.sqlite_path)
        sys.exit(0 if success else 1)

    # Database URL determination
    db_url = args.db_url or os.environ.get("SUPABASE_DB_URL") or os.environ.get("DATABASE_URL")
    if not db_url:
        print("[ERROR] No target database URL provided.")
        print("Specify --db-url or set the SUPABASE_DB_URL environment variable.")
        print("Example: set SUPABASE_DB_URL=postgresql://postgres.xxx:yyy@aws-0-ap-south-1.pooler.supabase.com:6543/postgres")
        sys.exit(1)

    # First run dry run audit before actual migration
    print("Running pre-migration integrity audit...")
    if not run_dry_run_analysis(args.sqlite_path):
        print("[ERROR] Pre-migration dry-run audit detected issues. Aborting.")
        sys.exit(1)

    # Execute migration
    execute_migration(args.sqlite_path, db_url)


if __name__ == "__main__":
    main()
