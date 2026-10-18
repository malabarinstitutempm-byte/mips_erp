# MIPS ERP v3.0 - Cloud Migration, Rollout & One-Batch Pilot Guide

This document outlines the step-by-step procedure to safely migrate, pilot, and operate the **MIPS ERP** with **Supabase PostgreSQL** as the single master database, while preserving local desktop storage for scanned physical documents.

---

## 1. Safety Principles & Pre-Flight Checklist

> [!IMPORTANT]
> **Safety Invariants**:
> 1. **Keep v2.0 Running as Warm Fallback**: Do not delete, overwrite, or retire your existing desktop SQLite database (`mips_erp.db`). It remains the operational fallback throughout the pilot.
> 2. **Never Commit Secrets**: Keep your Supabase `service_role` key and DB connection string in environment variables or private password managers only.
> 3. **Integer Paise Compliance**: Never store or calculate money as decimal floats. All monetary transactions must remain in integer paise.
> 4. **Physical Scanned Records**: Physical ID documents and audit histories stay on desktop SQLite only. Never upload scanned files to cloud tables.

### Pre-Flight Verification Checklist
- [ ] Local SQLite backup created and archived in a secure external drive (`backups/mips_erp_v2_baseline.db`).
- [ ] Dev Supabase project created (`evzehywyyqmcktszwmeg`).
- [ ] Database migrations executed: `0001_schema.sql`, `0002_functions.sql`, `0003_rls.sql`, `0004_auth_functions.sql`.
- [ ] Edge Functions deployed: `create-teacher`, `student-first-login`, `reset-password`, `lockout`.
- [ ] RLS tests executed and verified passing (`supabase/tests/rls_tests.sql`).

---

## 2. One-Batch Pilot Execution Plan

To eliminate operational risk, pilot the new cloud architecture with **one batch** (e.g. *Diploma in Medical Laboratory Technology - 2024*):

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                            ONE-BATCH PILOT CYCLE                            │
│                                                                             │
│  [Step 1: Pilot Batch Selection]  ──►  [Step 2: Dry-Run Migration]         │
│                                                   │                         │
│                                                   ▼                         │
│  [Step 4: Teacher Attendance Pilot] ◄── [Step 3: Admin Financial Audit]     │
│             │                                                               │
│             ▼                                                               │
│  [Step 5: Student Portal First-Login] ──► [Step 6: Evaluation & Sign-off]  │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Step 1: Pilot Batch Selection
* Cohort: **DMLT Batch 2024** (approx. 20–30 students).
* Assigned Faculty: 1–2 designated teachers.
* Subjects: 2 core semester subjects.

### Step 2: Dry-Run & Targeted Migration
Run the automated migration engine in dry-run mode first:
```bash
python tools/migrate_sqlite_to_postgres.py --sqlite-db "C:/Users/.../MIPS_ERP_Database/mips_erp.db" --dry-run
```
* Confirm that:
  - Total fees match SQLite to the exact rupee and paise.
  - No orphan foreign keys exist.
  - Zero non-integer monetary records detected.

Once verified clean, execute the migration transaction:
```bash
python tools/migrate_sqlite_to_postgres.py --sqlite-db "C:/Users/.../MIPS_ERP_Database/mips_erp.db"
```

### Step 3: Admin ERP Verification
1. Launch the Flutter Desktop ERP or Web Admin Portal (`build/web` or `flutter run -d windows`).
2. Log in with your Supabase administrator credentials.
3. Verify:
   - Students list shows the pilot batch.
   - Course fees and student ledger balance match the legacy software exactly.
   - Recording a test fee payment generates a server-side gap-free receipt number.
   - Cancellation of test receipt triggers an audit entry without deleting data.

### Step 4: Teacher Attendance Pilot
1. Ensure the pilot faculty account is active (provisioned via `create-teacher`).
2. Faculty logs into the React Portal (`/` or `portal/dist`):
   - Opens the **Teacher Attendance Portal**.
   - Selects the primary course, batch, date (today), and Morning or Evening slot.
   - Confirms student roster is loaded strictly from `students_for_teacher` (verifying no DOB, phone, address, marks, or fee records are exposed).
   - Marks attendance (*Present*, *Absent*, *Late*, *Leave*) and clicks **Submit Attendance**.
   - Confirms session is marked **Submitted** and read-only for all faculty.
   - Confirms other faculty members attempting to submit the same slot receive an `ALREADY_MARKED` notification.

### Step 5: Student First-Login & Results Verification
1. Select 3 pilot students to activate their accounts.
2. Students open the portal landing page and click **Activate account with Reg No & DOB**.
3. Student enters Registration Number and Date of Birth; sets their new password.
4. Student logs in:
   - Verifies **Academic Profile** information.
   - Verifies **Exam Results** and prints a sample Grade Card.
   - Checks **Fee Ledger** and confirms payment receipts.
   - Checks **Attendance Summary** and confirms percentage matches marked sessions.
   - Verifies that real-time notification alerts work when an admin publishes exam results.

---

## 3. Automated Nightly Export & Disaster Recovery

### Automated Daily Cloud Backups
Every night at 02:00 UTC (07:30 AM IST), GitHub Actions automatically triggers:
```yaml
# .github/workflows/nightly_export.yml
schedule:
  - cron: '0 2 * * *'
```
* Dumps all 26 ERP tables to structured JSON.
* Performs automated financial reconciliation (`total_fees == paid + pending`).
* Packages dumps into a compressed, timestamped archive: `mips_export_YYYY_MM_DD.zip`.
* Computes cryptographic SHA256 checksum and enforces a 30-day rolling retention policy.

### Local Office Workstation Backups
To run backups directly on the desktop office computer:
1. Double-click or configure Windows Task Scheduler to run:
   ```cmd
   tools\run_nightly_backup.bat
   ```
2. Archives will be written directly to `E:\mips_erp\backups\`.

### Verifying Backup Health
Run the integrity auditor on any generated backup archive:
```bash
python tools/verify_backup_integrity.py backups/mips_export_2026_10_15_020000.zip
```
Expected output:
```
=================================================================
  BACKUP HEALTH SCORE: 100 / 100
  Status: HEALTHY & VERIFIED
=================================================================
```

---

## 4. Emergency Rollback Plan

If an unexpected critical defect or network failure occurs during the pilot:

1. **Immediate Fallback**: Launch the unmodified v2.0 desktop ERP executable pointing to local SQLite.
2. **Read-Only Switch**:
   ```sql
   -- Lock cloud tables to read-only for students/teachers if needed:
   UPDATE public.settings SET value = 'true' WHERE key = 'maintenance_mode';
   ```
3. **Data Sync-Back**:
   Run `tools/nightly_export.py` to extract any payments or attendance marked during the pilot and merge them back into local SQLite.
4. **Student Communication**: Notify pilot students via notice board that maintenance is underway.
