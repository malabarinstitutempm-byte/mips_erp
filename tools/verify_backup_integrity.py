#!/usr/bin/env python3
"""
MIPS ERP - Backup Archive & Integrity Auditor
Verifies SHA256 cryptographic hashes, validates JSON structure,
audits relational integrity (foreign keys), checks for illegal floating-point money,
and calculates financial ledger health scores.

Usage:
    python tools/verify_backup_integrity.py <path_to_backup_zip>
"""

import sys
import json
import zipfile
import hashlib
from pathlib import Path

def sha256_file(filepath):
    h = hashlib.sha256()
    with open(filepath, 'rb') as f:
        while chunk := f.read(65536):
            h.update(chunk)
    return h.hexdigest()

def audit_archive(zip_path):
    zip_p = Path(zip_path)
    if not zip_p.exists():
        print(f"[!] Error: File '{zip_path}' not found.")
        sys.exit(1)

    print("=================================================================")
    print(f"  MIPS ERP - Backup Integrity & Health Auditor")
    print(f"  Target Archive: {zip_p.name}")
    print(f"  File Size:      {zip_p.stat().st_size / 1024:.2f} KB")
    print("=================================================================")

    # 1. SHA256 Verification
    calculated_hash = sha256_file(zip_p)
    sha_file = zip_p.with_suffix('.zip.sha256')
    if sha_file.exists():
        with open(sha_file, 'r') as f:
            expected_hash = f.read().split()[0].strip()
        if calculated_hash.lower() == expected_hash.lower():
            print(f"[✓] SHA256 Checksum: MATCH ({calculated_hash[:16]}...)")
        else:
            print(f"[X] SHA256 Checksum: MISMATCH!")
            print(f"    Expected:   {expected_hash}")
            print(f"    Calculated: {calculated_hash}")
            sys.exit(1)
    else:
        print(f"[*] Calculated SHA256: {calculated_hash}")

    # 2. Inspect contents
    with zipfile.ZipFile(zip_p, 'r') as zf:
        file_list = zf.namelist()
        print(f"\n[*] Archive contains {len(file_list)} files.")

        data = {}
        for fname in file_list:
            if fname.endswith('.json') and fname not in ('backup_manifest.json', 'financial_reconciliation.json'):
                try:
                    with zf.open(fname) as f:
                        data[fname[:-5]] = json.loads(f.read().decode('utf-8'))
                except Exception as e:
                    print(f"  [!] Failed to parse JSON in {fname}: {e}")

    # 3. Check Floating-Point Money Invariants
    float_violations = []
    money_fields = {
        "fees": ["total_fee_paise", "paid_amount_paise", "pending_amount_paise"],
        "payments": ["amount_paise"],
        "courses": ["total_fee_paise"],
    }

    for table, fields in money_fields.items():
        records = data.get(table, [])
        for r in records:
            for fld in fields:
                val = r.get(fld)
                if val is not None and not isinstance(val, int):
                    float_violations.append((table, r.get('id'), fld, val, type(val).__name__))

    if float_violations:
        print(f"\n[X] CRITICAL: Found {len(float_violations)} floating-point or non-integer money values!")
        for v in float_violations[:5]:
            print(f"    Table {v[0]}, ID {v[1]}, Column {v[2]}: Value {v[3]} (type: {v[4]})")
    else:
        print(f"[✓] Money Integrity: 100% Integer Paise Compliant (Zero floats)")

    # 4. Foreign Key Audits
    courses_ids = {c['id'] for c in data.get('courses', []) if 'id' in c}
    batches_ids = {b['id'] for b in data.get('batches', []) if 'id' in b}
    students_ids = {s['id'] for s in data.get('students', []) if 'id' in s}
    exams_ids = {e['id'] for e in data.get('exams', []) if 'id' in e}

    orphan_students_course = [s['id'] for s in data.get('students', []) if s.get('course_id') and s.get('course_id') not in courses_ids]
    orphan_students_batch = [s['id'] for s in data.get('students', []) if s.get('batch_id') and s.get('batch_id') not in batches_ids]
    orphan_fees = [f['id'] for f in data.get('fees', []) if f.get('student_id') not in students_ids]
    orphan_payments = [p['id'] for p in data.get('payments', []) if p.get('student_id') not in students_ids]

    fk_errors = len(orphan_students_course) + len(orphan_students_batch) + len(orphan_fees) + len(orphan_payments)

    print(f"\n[*] Relational Audit Summary:")
    print(f"    - Courses Registered: {len(courses_ids)}")
    print(f"    - Batches Active:     {len(batches_ids)}")
    print(f"    - Students Active:    {len(students_ids)}")
    print(f"    - Exams Recorded:     {len(exams_ids)}")

    if fk_errors == 0:
        print(f"[✓] Foreign Key Integrity: PERFECT (0 orphaned records)")
    else:
        print(f"[!] Warning: Found {fk_errors} orphaned records across relational tables.")

    # 5. Financial Reconciliation Audit
    fees_records = data.get('fees', [])
    payments_records = data.get('payments', [])

    sum_fee_paise = sum(r.get('total_fee_paise', 0) or 0 for r in fees_records)
    sum_paid_paise = sum(r.get('paid_amount_paise', 0) or 0 for r in fees_records)
    sum_pending_paise = sum(r.get('pending_amount_paise', 0) or 0 for r in fees_records)
    actual_paid_payments = sum(p.get('amount_paise', 0) or 0 for p in payments_records if not p.get('is_cancelled') and not p.get('deleted_at'))

    variance = abs(sum_paid_paise - actual_paid_payments)

    print(f"\n[*] Financial Audit:")
    print(f"    - Total Ledger Fee:     ₹{sum_fee_paise / 100:,.2f}")
    print(f"    - Ledger Paid Sum:      ₹{sum_paid_paise / 100:,.2f}")
    print(f"    - Payments Records Sum: ₹{actual_paid_payments / 100:,.2f}")
    print(f"    - Ledger Pending Sum:   ₹{sum_pending_paise / 100:,.2f}")

    if variance == 0:
        print(f"[✓] Financial Reconciliation: EXACT MATCH (₹0.00 Variance)")
    else:
        print(f"[!] Financial Variance: ₹{variance / 100:,.2f}")

    # Health Score
    health_score = 100
    if float_violations:
        health_score -= 30
    if fk_errors > 0:
        health_score -= min(fk_errors * 2, 20)
    if variance > 0:
        health_score -= 20

    print(f"\n=================================================================")
    print(f"  BACKUP HEALTH SCORE: {max(health_score, 0)} / 100")
    print(f"  Status: {'HEALTHY & VERIFIED' if health_score >= 90 else 'ACTION REQUIRED'}")
    print("=================================================================\n")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python tools/verify_backup_integrity.py <path_to_backup_zip>")
        sys.exit(1)
    audit_archive(sys.argv[1])
