# MIPS ERP v2.0 to Production Supabase Cutover Runbook & Checklist

This runbook outlines the exact sequence of steps to migrate institutional data from the local SQLite desktop database (`v2.0`) to the Production Supabase PostgreSQL backend without data loss or downtime confusion.

---

## 1. Pre-Cutover Preparation (T-2 Days)

- [ ] **Target Supabase Environment Ready**:
  - All migrations applied (`0001_initial_schema.sql` through `0014_primary_attendance_and_open_faculty.sql`).
  - Edge Functions deployed and secrets configured (`JWT_SECRET`, `TURNSTILE_SECRET_KEY`, `WEB_PUSH_PRIVATE_KEY`).
  - Production database connection string (`DATABASE_URL`) tested.
- [ ] **Dry Run Ingestion**:
  - Run dry-run audit against office database copy:
    ```bash
    python tools/migrate_sqlite_to_postgres.py --dry-run
    # or
    dart run tools/cutover_migration.dart --dry-run
    ```
  - Verify that:
    - 0 duplicate admission numbers.
    - 0 duplicate receipt numbers.
    - 0 orphan fee/payment/mark records.
    - Currency values are cleanly cast to integer paise.
- [ ] **Office Staff Notification**:
  - Inform principal and accountant of the planned 2-hour freeze window (e.g., Saturday 4:00 PM – 6:00 PM).

---

## 2. Cutover Freeze Window (T-0, Day of Migration)

- [ ] **Step 2.1: Halt Local Office Activity**:
  - Close all instances of MIPS ERP v2.0 on the office PC.
  - Verify no background process is holding an open file handle on `mips_erp.db`.
- [ ] **Step 2.2: Cold Snapshot Creation**:
  - Copy `mips_erp.db` to cold storage:
    ```bash
    copy "C:\Users\hp\Documents\MIPS_ERP_Database\mips_erp.db" "C:\Users\hp\Documents\MIPS_ERP_Database\Backups\mips_erp_v2_COLD_SNAPSHOT.db"
    ```
  - Set cold file to read-only attribute:
    ```powershell
    attrib +R "C:\Users\hp\Documents\MIPS_ERP_Database\Backups\mips_erp_v2_COLD_SNAPSHOT.db"
    ```
  - Run freeze check:
    ```bash
    dart run tools/cutover_migration.dart --freeze-check
    ```
  - Record the SHA-256 snapshot hash in the physical institutional logbook.

---

## 3. Production Migration Execution (T+15 Minutes)

- [ ] **Step 3.1: Execute Cutover Ingestion**:
  ```bash
  python tools/migrate_sqlite_to_postgres.py --sqlite-path "C:\Users\hp\Documents\MIPS_ERP_Database\Backups\mips_erp_v2_COLD_SNAPSHOT.db" --db-url "$PRODUCTION_DB_URL"
  # or
  dart run tools/cutover_migration.dart --execute
  ```
- [ ] **Step 3.2: Automated Pre-Commit Reconciliation**:
  The migration runs within a single atomic PostgreSQL transaction. Before committing, the migration script verifies:
  - 100% table row count match across all 14 core entities.
  - Exact match of `Total Fee Obligations (paise)`: `7,50,00,000` paise.
  - Exact match of `Total Fee Paid Ledger (paise)`: `6,25,00,000` paise.
  - Exact match of `Total Pending Balance (paise)`: `1,25,00,000` paise.
  - Receipt sequence counter synced to `REC-YYYY-XXXXX`.
  - Admission sequence counter synced to `MIPS-YYYY-XXXXX`.

---

## 4. Post-Cutover Verification (T+45 Minutes)

- [ ] **Desktop Admin App (Flutter Desktop)**:
  - Launch app connected to Production Supabase URL.
  - Check **System Health Card** on Dashboard:
    - 0 unassigned/orphaned records.
    - Click **"Backup Now"** to generate initial post-cutover encrypted cloud dump (`MIPS_Backup_YYYY-MM-DD_HH-mm-ss.zip`).
    - Click **"Copy backup to another folder or drive"** to verify USB archival copy.
- [ ] **Web Admin & Portal (React / Flutter Web)**:
  - Verify admin login with TOTP/password.
  - Verify student login with register number + DOB.
  - Verify exam results view for published exams.
  - Verify fee balance and payment history.
- [ ] **Teacher Portal**:
  - Verify teacher login and open attendance marking access across all primary course batches.
  - Verify Today's Attendance Board displays live morning/evening slot statuses.

---

## 5. Rollback Plan (In Case of Unrecoverable Blocker)

If a critical issue occurs during migration or smoke testing:
1. **Local SQLite Remains Untouched**:
   - The cold snapshot `mips_erp.db` was mounted read-only and remains 100% intact with zero modifications.
2. **Re-Open Legacy System**:
   - Re-open MIPS ERP v2.0 desktop software on the office PC.
   - Inform office staff to resume local fee collection and attendance.
3. **Purge Partial Cloud Data**:
   - Execute:
     ```bash
     supabase db reset --linked
     ```
   - All migrations will re-apply cleanly, resetting cloud state to empty schema.
4. **Post-Mortem**:
   - Analyze transaction rollback logs before scheduling next window.
