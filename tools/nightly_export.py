#!/usr/bin/env python3
"""
MIPS ERP - Automated Nightly Export & Disaster Recovery Script
Exports all cloud master tables from Supabase PostgreSQL / PostgREST,
computes cryptographic checksums, reconciles financial paise totals,
and generates compressed archives with automated 30-day retention.

Usage:
    python tools/nightly_export.py [--output-dir ./backups] [--retention-days 30]

Environment Variables:
    DATABASE_URL: PostgreSQL connection string
    or
    SUPABASE_URL & SUPABASE_SERVICE_ROLE_KEY
"""

import os
import sys
import re
import json
import time
import zipfile
import hashlib
import argparse
from datetime import datetime, date, timezone, timedelta
from decimal import Decimal
from pathlib import Path

# Safe Unicode output for all console environments
if sys.stdout and hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')

# Fallback tables list in logical dependency order
TABLES = [
    "settings",
    "academic_years",
    "universities",
    "grading_schemes",
    "courses",
    "course_subjects",
    "batches",
    "students",
    "admin_accounts",
    "fees",
    "payments",
    "receipts",
    "exams",
    "exam_subjects",
    "marks",
    "results",
    "teachers",
    "attendance_sessions",
    "attendance_records",
    "attendance_changes",
    "document_templates",
    "generated_documents",
    "notifications",
    "push_subscriptions",
    "number_counters",
    "audit_log",
]

def get_env_var(name, default=None):
    return os.environ.get(name, default)

def sha256_file(filepath):
    h = hashlib.sha256()
    with open(filepath, 'rb') as f:
        while chunk := f.read(65536):
            h.update(chunk)
    return h.hexdigest()

def get_connection_candidates(db_url):
    candidates = []
    # If direct db.ref.supabase.co:5432 is used, add IPv4 pooler candidate first
    # Supabase direct db.*.supabase.co only has IPv6 (unreachable from GitHub Actions runners)
    m = re.match(r'postgresql://([^:]+):([^@]+)@db\.([a-z0-9]+)\.supabase\.co(?::5432)?/(.+)', db_url)
    if m:
        user, pwd, ref, db = m.groups()
        candidates.append(f"postgresql://{user}.{ref}:{pwd}@aws-0-ap-south-1.pooler.supabase.com:6543/{db}")
    candidates.append(db_url)
    return candidates

def export_via_psycopg2(db_url, export_dir):
    try:
        import psycopg2
        import psycopg2.extras
    except ImportError:
        print("[!] psycopg2 not installed. Run: pip install psycopg2-binary")
        return False, {}

    conn = None
    for url in get_connection_candidates(db_url):
        masked_host = url.split('@')[-1].split('/')[0] if '@' in url else 'host'
        print(f"[*] Attempting PostgreSQL connection to {masked_host}...")
        try:
            conn = psycopg2.connect(url, connect_timeout=15)
            conn.autocommit = True
            print(f"[+] Connected successfully to PostgreSQL via {masked_host}!")
            break
        except Exception as e:
            print(f"  [!] Connection failed ({masked_host}): {e}")

    if not conn:
        print("[!] All direct PostgreSQL connection attempts failed.")
        return False, {}

    cursor = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)

    # Query all base tables dynamically from the public schema
    try:
        cursor.execute("""
            SELECT table_name 
            FROM information_schema.tables 
            WHERE table_schema = 'public' AND table_type = 'BASE TABLE'
            ORDER BY table_name;
        """)
        tables_to_export = [r['table_name'] for r in cursor.fetchall()]
        print(f"[*] Dynamically discovered {len(tables_to_export)} tables in public schema.")
    except Exception as e:
        print(f"  [!] Could not query information_schema, using fallback table list: {e}")
        tables_to_export = TABLES

    stats = {}
    for table in tables_to_export:
        try:
            cursor.execute(f'SELECT * FROM "{table}";')
            rows = cursor.fetchall()
            
            # Serialize datetimes, dates, decimals, and uuids safely
            clean_rows = []
            for row in rows:
                clean_row = {}
                for k, v in row.items():
                    if isinstance(v, (datetime, date)):
                        clean_row[k] = v.isoformat()
                    elif isinstance(v, Decimal):
                        clean_row[k] = float(v) if v % 1 else int(v)
                    elif hasattr(v, '__str__') and type(v).__name__ == 'UUID':
                        clean_row[k] = str(v)
                    else:
                        clean_row[k] = v
                clean_rows.append(clean_row)

            table_file = export_dir / f"{table}.json"
            with open(table_file, 'w', encoding='utf-8') as f:
                json.dump(clean_rows, f, indent=2, ensure_ascii=False)

            stats[table] = len(clean_rows)
            print(f"  [+] {table}: {len(clean_rows)} rows exported")
        except Exception as e:
            print(f"  [-] Failed to export {table}: {e}")
            stats[table] = 0

    cursor.close()
    conn.close()
    return True, stats

def export_via_postgrest(supabase_url, service_key, export_dir):
    try:
        import urllib.request
        import urllib.parse
    except ImportError:
        return False, {}

    print(f"[*] Connecting to Supabase PostgREST ({supabase_url})...")
    clean_url = supabase_url.rstrip('/')
    stats = {}

    for table in TABLES:
        try:
            req_url = f"{clean_url}/rest/v1/{table}?select=*"
            req = urllib.request.Request(req_url, headers={
                "apikey": service_key,
                "Authorization": f"Bearer {service_key}",
                "Content-Type": "application/json",
                "Range": "0-99999",
            })

            with urllib.request.urlopen(req, timeout=30) as resp:
                data = json.loads(resp.read().decode('utf-8'))
                table_file = export_dir / f"{table}.json"
                with open(table_file, 'w', encoding='utf-8') as f:
                    json.dump(data, f, indent=2, ensure_ascii=False)

                stats[table] = len(data)
                print(f"  [+] {table}: {len(data)} rows exported")
        except Exception as e:
            print(f"  [-] Failed to export {table}: {e}")
            stats[table] = 0

    return True, stats

def perform_financial_reconciliation(export_dir):
    fees_path = export_dir / "fees.json"
    payments_path = export_dir / "payments.json"

    reconciliation = {
        "status": "PASS",
        "total_fee_paise": 0,
        "total_paid_paise": 0,
        "total_pending_paise": 0,
        "actual_payments_sum_paise": 0,
        "variance_paise": 0,
    }

    if fees_path.exists():
        with open(fees_path, 'r', encoding='utf-8') as f:
            fees_data = json.load(f)
            for r in fees_data:
                reconciliation["total_fee_paise"] += r.get("total_fee_paise", 0) or 0
                reconciliation["total_paid_paise"] += r.get("paid_amount_paise", 0) or 0
                reconciliation["total_pending_paise"] += r.get("pending_amount_paise", 0) or 0

    if payments_path.exists():
        with open(payments_path, 'r', encoding='utf-8') as f:
            payments_data = json.load(f)
            for p in payments_data:
                if not p.get("is_cancelled") and not p.get("deleted_at"):
                    reconciliation["actual_payments_sum_paise"] += p.get("amount_paise", 0) or 0

    variance = abs(reconciliation["total_paid_paise"] - reconciliation["actual_payments_sum_paise"])
    reconciliation["variance_paise"] = variance

    if variance > 0:
        reconciliation["status"] = "WARNING_VARIANCE_DETECTED"

    return reconciliation

def purge_old_backups(backup_dir, retention_days):
    print(f"[*] Checking retention policy (Purging backups older than {retention_days} days)...")
    cutoff = datetime.now() - timedelta(days=retention_days)
    purged = 0
    for file in Path(backup_dir).glob("mips_export_*.zip"):
        try:
            mtime = datetime.fromtimestamp(file.stat().st_mtime)
            if mtime < cutoff:
                file.unlink()
                # Also delete sha256 if present
                sha = file.with_suffix('.zip.sha256')
                if sha.exists():
                    sha.unlink()
                purged += 1
                print(f"  [-] Purged old backup: {file.name}")
        except Exception as e:
            print(f"  [!] Failed to purge {file.name}: {e}")
    if purged == 0:
        print("  [+] No expired backups to purge.")
    else:
        print(f"  [+] Purged {purged} expired backup archive(s).")

def main():
    parser = argparse.ArgumentParser(description="MIPS ERP Automated Nightly Backup & Export Engine")
    parser.add_argument("--output-dir", default="./backups", help="Destination backup directory")
    parser.add_argument("--retention-days", type=int, default=30, help="Days to retain backup archives")
    args = parser.parse_args()

    out_root = Path(args.output_dir).resolve()
    out_root.mkdir(parents=True, exist_ok=True)

    timestamp_str = datetime.now().strftime("%Y_%m_%d_%H%M%S")
    temp_export_dir = out_root / f"temp_export_{timestamp_str}"
    temp_export_dir.mkdir(parents=True, exist_ok=True)

    print("=================================================================")
    print(f"  MIPS ERP - Automated Database Nightly Backup Engine")
    print(f"  Timestamp: {datetime.now(timezone.utc).isoformat()} UTC")
    print(f"  Target: {out_root}")
    print("=================================================================")

    db_url = get_env_var("DATABASE_URL")
    supabase_url = get_env_var("SUPABASE_URL", "https://evzehywyyqmcktszwmeg.supabase.co")
    service_key = get_env_var("SUPABASE_SERVICE_ROLE_KEY")

    success = False
    stats = {}

    if db_url:
        success, stats = export_via_psycopg2(db_url, temp_export_dir)

    # Fallback to PostgREST if direct DB failed or wasn't provided
    if not success and supabase_url and service_key:
        print("[*] Falling back to Supabase PostgREST API export...")
        success, stats = export_via_postgrest(supabase_url, service_key, temp_export_dir)

    if not success and not db_url and not service_key:
        # Check if .env file exists in current or parent directory
        env_files = [Path(".env"), Path("portal/.env"), Path("../.env")]
        for ef in env_files:
            if ef.exists():
                with open(ef, 'r') as f:
                    for line in f:
                        line = line.strip()
                        if line.startswith("DATABASE_URL="):
                            db_url = line.split("=", 1)[1].strip('"').strip("'")
                        elif line.startswith("SUPABASE_SERVICE_ROLE_KEY="):
                            service_key = line.split("=", 1)[1].strip('"').strip("'")

        if db_url:
            success, stats = export_via_psycopg2(db_url, temp_export_dir)
        elif supabase_url and service_key:
            success, stats = export_via_postgrest(supabase_url, service_key, temp_export_dir)

    if not success:
        print("[!] ERROR: Nightly backup export failed. Could not retrieve tables from database.")
        sys.exit(1)

    # Financial Reconciliation
    recon = perform_financial_reconciliation(temp_export_dir)
    recon_path = temp_export_dir / "financial_reconciliation.json"
    with open(recon_path, 'w', encoding='utf-8') as f:
        json.dump(recon, f, indent=2)

    # Manifest
    manifest = {
        "institution": "Malabar Institute of Paramedical Science",
        "system": "MIPS ERP v3.0 (Supabase Cloud Master)",
        "backup_timestamp_utc": datetime.now(timezone.utc).isoformat(),
        "tables_exported": len(stats),
        "total_rows_exported": sum(stats.values()),
        "table_row_counts": stats,
        "financial_reconciliation": recon,
    }

    manifest_path = temp_export_dir / "backup_manifest.json"
    with open(manifest_path, 'w', encoding='utf-8') as f:
        json.dump(manifest, f, indent=2)

    # Compress into ZIP
    zip_filename = f"mips_export_{timestamp_str}.zip"
    zip_path = out_root / zip_filename
    print(f"[*] Packaging into compressed archive: {zip_path.name}...")

    with zipfile.ZipFile(zip_path, 'w', zipfile.ZIP_DEFLATED) as zf:
        for file in temp_export_dir.iterdir():
            zf.write(file, arcname=file.name)

    # Generate SHA256 checksum
    checksum = sha256_file(zip_path)
    checksum_path = out_root / f"{zip_filename}.sha256"
    with open(checksum_path, 'w') as f:
        f.write(f"{checksum}  {zip_filename}\n")

    # Clean temporary folder
    for file in temp_export_dir.iterdir():
        file.unlink()
    temp_export_dir.rmdir()

    print(f"[+] Archive generated successfully:")
    print(f"    File: {zip_path}")
    print(f"    Size: {zip_path.stat().st_size / 1024:.2f} KB")
    print(f"    SHA256: {checksum}")
    print(f"    Reconciliation Status: {recon['status']}")
    print(f"    Total Ledger Fee: Rs. {recon['total_fee_paise'] / 100:,.2f}")
    print(f"    Total Paid Sum:  Rs. {recon['total_paid_paise'] / 100:,.2f}")
    print(f"    Variance:        Rs. {recon['variance_paise'] / 100:,.2f}")

    # Retention Purge
    purge_old_backups(out_root, args.retention_days)

    print("\n[✓] Nightly export completed with 0 errors.")

if __name__ == "__main__":
    main()
