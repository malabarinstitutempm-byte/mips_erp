# MIPS ERP — Cloud Database Migration & Deployment Guide (Phase 1)

This guide provides instructions for deploying the **MIPS ERP** PostgreSQL database on Supabase, verifying security policies, executing the local SQLite data migration, and verifying financial reconciliation.

---

## 📁 Migration Deliverables Directory Structure

```text
mips_erp/
├── supabase/
│   ├── migrations/
│   │   ├── 0001_schema.sql        # Sub-phase 1A: Core tables, enums, audit triggers & indexes
│   │   ├── 0002_functions.sql     # Sub-phase 1B: Security Definer functions & business rules
│   │   └── 0003_rls.sql           # Sub-phase 1C: Row Level Security, anon revokes & views
│   └── tests/
│       └── rls_tests.sql          # Sub-phase 1C: Automated RLS & Negative isolation tests
├── tools/
│   └── migrate_sqlite_to_postgres.py # Sub-phase 1D: SQLite -> PostgreSQL migration engine
└── README.md
```

---

## 🛠️ Prerequisites

1. **Supabase Dev Project**:
   - Create a separate, dedicated **DEV** Supabase project for testing.
   - Do **NOT** run migrations directly on a production project.
   - Obtain your database connection string (from Supabase Dashboard &rarr; **Project Settings** &rarr; **Database** &rarr; **Connection string** &rarr; **URI** or **Transaction Pooler**).
2. **Python 3.10+**:
   - Install database adapter:
     ```powershell
     pip install psycopg2-binary
     ```
3. **Local SQLite Backup**:
   - Keep a copy of `mips_erp.db` safely backed up.

---

## 🚀 Step 1: Apply SQL Migrations to Your Supabase DEV Project

Apply the migrations in order using either the **Supabase Dashboard SQL Editor** or via `psql` / Supabase CLI.

### Option A: Via Supabase Dashboard SQL Editor (Recommended)
1. Open your Supabase Project Dashboard &rarr; **SQL Editor**.
2. Run [`supabase/migrations/0001_schema.sql`](file:///E:/mips_erp/supabase/migrations/0001_schema.sql):
   - Sets up custom types (`user_role`, `payment_mode`, `attendance_status`, etc.).
   - Creates all 27 tables with foreign keys, checks, and `legacy_id`.
   - Attaches `set_updated_at` and `audit_log_trigger` triggers.
   - Seeds default settings and grading schemes.
3. Run [`supabase/migrations/0002_functions.sql`](file:///E:/mips_erp/supabase/migrations/0002_functions.sql):
   - Deploys `SECURITY DEFINER` functions with fixed `search_path`.
   - Gap-free counter `next_number(kind, year)`.
   - Transactional payment processor `record_payment(...)` with overpayment guard.
   - Attendance submission `submit_attendance(...)` & correction audit `correct_attendance(...)`.
   - Grading & result computation `compute_results(exam_id)`.
   - Exam publish / unpublish with notification generation.
4. Run [`supabase/migrations/0003_rls.sql`](file:///E:/mips_erp/supabase/migrations/0003_rls.sql):
   - Completely revokes access from `anon` / public keys.
   - Enables RLS on all tables.
   - Creates secure views: `students_for_teacher`, `student_profile_view`, and `student_payments_view`.
   - Enforces role isolation for admins, teachers, and students.
   - Ensures immutable audit logs (`audit_log`, `attendance_changes`).

### Option B: Via psql CLI
```powershell
$DB_URL = "postgresql://postgres.[PROJECT_REF]:[PASSWORD]@aws-0-ap-south-1.pooler.supabase.com:6543/postgres"

psql $DB_URL -f supabase/migrations/0001_schema.sql
psql $DB_URL -f supabase/migrations/0002_functions.sql
psql $DB_URL -f supabase/migrations/0003_rls.sql
```

---

## 🧪 Step 2: Run Automated RLS & Security Policy Tests

Run the comprehensive test script to verify that all access boundaries are impenetrable:

```powershell
psql $DB_URL -f supabase/tests/rls_tests.sql
```
*(Or copy the contents of [`supabase/tests/rls_tests.sql`](file:///E:/mips_erp/supabase/tests/rls_tests.sql) directly into the Supabase SQL Editor and click **Run**).*

### What this test verifies:
- **Test 1 (Student Isolation)**: Proves Student 1 can only see their own profile, fees, and published results. Cannot see Student 2's records, cannot see draft results, and cannot see administrative payment remarks.
- **Test 2 (Teacher Isolation)**: Proves Teacher A can only see students in assigned batches via `students_for_teacher`. Direct queries on `students` table return 0 rows. Cannot see unassigned batches, DOB, phone, address, or fees.
- **Test 3 (Anon Lockdown)**: Proves `anon` / unauthenticated requests cannot read any tables (`students`, `settings`, `courses`, `results`, `fees`).
- **Test 4 (Audit Immutability)**: Proves `UPDATE` and `DELETE` on `audit_log` and `attendance_changes` are rejected with `insufficient_privilege`.
- **Test 5 (Overpayment Guard)**: Proves payments exceeding student fee obligations are strictly rejected by `record_payment()`.
- **Rollback Guarantee**: The test script automatically rolls back after execution, leaving the test database clean.

---

## 🔍 Step 3: Run the Migration Dry-Run

Before touching the PostgreSQL database, execute the dry-run audit to inspect the local SQLite data:

```powershell
python tools/migrate_sqlite_to_postgres.py --dry-run
```

You can optionally specify a custom SQLite file path:
```powershell
python tools/migrate_sqlite_to_postgres.py --sqlite-path "C:\path\to\mips_erp.db" --dry-run
```

### What the dry-run audits:
1. **Row inventory**: Records in all 16 SQLite tables.
2. **Duplicate check**: Asserts unique admission and receipt numbers.
3. **Foreign key orphans**: Checks student course/batch mappings, fee links, payment links, and marks.
4. **Data sanitization**: Checks missing dates and normalizes genders.
5. **Financial precision**: Verifies that `Total Fee Paid Ledger == Total Valid Payments` and `Total Fees - Paid == Pending Balance` down to the exact paise.

---

## 🚚 Step 4: Execute the Data Migration

Once the dry run passes, execute the live migration:

### 1. Set your Supabase connection string as an environment variable:
```powershell
$env:SUPABASE_DB_URL="postgresql://postgres.[PROJECT_REF]:[PASSWORD]@aws-0-ap-south-1.pooler.supabase.com:6543/postgres"
```

### 2. Run the migration script:
```powershell
python tools/migrate_sqlite_to_postgres.py
```

### Guarantees during execution:
- **Read-Only SQLite Source**: SQLite is opened with `?mode=ro`, guaranteeing your source database cannot be altered.
- **Atomic Transaction**: The entire migration runs inside a single Postgres transaction. If any error occurs, all changes roll back immediately.
- **ID Preservation**: Preserves original integer IDs (`id`) and populates `legacy_id`.
- **Sequence Synchronization**: Resets PostgreSQL identity sequences to `MAX(id)` so future inserts continue seamlessly.
- **Sequential Counters**: Initializes `number_counters` for running admission and receipt numbers.
- **Zero Secret Exposure**: Connection strings and passwords are redacted in terminal logs.

---

## 📊 Step 5: Post-Migration Reconciliation & Verification

The migration tool automatically produces a reconciliation report upon completion:

### Row Count Reconciliation
| Table | SQLite Count | Postgres Count | Status |
| :--- | :--- | :--- | :--- |
| `settings` | 3 | 3 | MATCH |
| `academic_years` | 1 | 1 | MATCH |
| `universities` | 1 | 1 | MATCH |
| `courses` | 4 | 4 | MATCH |
| `batches` | 2 | 2 | MATCH |
| `students` | 11 | 11 | MATCH |
| `fees` | 11 | 11 | MATCH |
| `payments` | 10 | 10 | MATCH |
| `receipts` | 6 | 6 | MATCH |
| `exams` | 7 | 7 | MATCH |
| `exam_subjects` | 12 | 12 | MATCH |
| `marks` | 6 | 6 | MATCH |
| `results` | 1 | 1 | MATCH |
| `document_templates`| 2 | 2 | MATCH |

### Financial Reconciliation (Exact Paise)
| Metric | SQLite | PostgreSQL | Status |
| :--- | :--- | :--- | :--- |
| **Total Fee Obligations** | 38,000,000 paise (₹3,80,000.00) | 38,000,000 paise (₹3,80,000.00) | MATCH |
| **Total Fee Paid Ledger** | 10,100,000 paise (₹1,01,000.00) | 10,100,000 paise (₹1,01,000.00) | MATCH |
| **Total Pending Balances**| 27,900,000 paise (₹2,79,000.00) | 27,900,000 paise (₹2,79,000.00) | MATCH |
| **Total Valid Payments**  | 10,100,000 paise (₹1,01,000.00) | 10,100,000 paise (₹1,01,000.00) | MATCH |

---

## 🔐 Phase 2: Accounts & Edge Functions

Phase 2 introduces Supabase Edge Functions and database routines for secure account provisioning, first-time portal activation, password recovery, and brute-force lockout protection.

### Directory Structure
```text
mips_erp/
├── supabase/
│   ├── migrations/
│   │   ├── ...
│   │   └── 0004_auth_functions.sql    # Lockout tracking & admin unlock routines
│   ├── functions/
│   │   ├── _shared/
│   │   │   ├── cors.ts                # Cross-Origin Resource Sharing handler
│   │   │   ├── supabase-client.ts     # Admin & User client factories
│   │   │   └── response.ts            # Standard JSON response helpers
│   │   ├── create-teacher/            # Admin provisioning for teachers
│   │   ├── student-first-login/       # First-time portal activation for students
│   │   ├── reset-password/            # Admin reset & student self-service reset
│   │   └── lockout/                   # Brute-force protection & account unlock
│   └── tests/
│       ├── rls_tests.sql
│       └── auth_tests.sql             # Automated lockout & credential tests
```

---

### Edge Function Specifications

#### 1. `create-teacher` (Admin Only)
- **Endpoint**: `POST /functions/v1/create-teacher`
- **Headers**: `Authorization: Bearer <ADMIN_JWT>`
- **Payload**:
  ```json
  {
    "name": "Prof. Mohammed Alvi",
    "login_username": "alvi_teacher",
    "phone": "9876543210",
    "email": "alvi@mips.edu",
    "password": "TeacherPassword123!",
    "assignments": [
      { "course_id": 1, "batch_id": 1, "subject_id": 1 }
    ]
  }
  ```
- **Actions**:
  1. Verifies caller is an active administrator.
  2. Creates Auth user via Supabase Admin API.
  3. Inserts into `public.teachers`.
  4. Inserts into `public.profiles` (`role = 'teacher'`, `must_change_password = true`).
  5. Inserts initial course/batch/subject assignments into `public.teacher_assignments`.

#### 2. `student-first-login` (Public / Student Portal)
- **Endpoint**: `POST /functions/v1/student-first-login`
- **Payload**:
  ```json
  {
    "admission_number": "ADM-2026-0001",
    "dob": "2005-05-15",
    "new_password": "MyStrongPassword@2026",
    "email": "student@gmail.com",
    "phone": "9876543210"
  }
  ```
- **Actions**:
  1. Verifies matching student in `public.students` (`admission_number` + `dob` + `status = 'active'`).
  2. Ensures student has not already activated an account.
  3. Creates user in Supabase Auth.
  4. Links `public.profiles` (`role = 'student'`, `must_change_password = false`).
  5. Instantly signs in and returns an active session token (`access_token`, `refresh_token`).

#### 3. `reset-password` (Admin & Student Self-Service)
- **Endpoint**: `POST /functions/v1/reset-password`
- **Admin Mode**:
  ```json
  {
    "mode": "admin",
    "target_identifier": "ADM-2026-0001",
    "target_role": "student",
    "new_password": "TempPassword123!"
  }
  ```
- **Student Self-Service Mode**:
  ```json
  {
    "mode": "student_self",
    "admission_number": "ADM-2026-0001",
    "dob": "2005-05-15",
    "phone": "9876543210",
    "new_password": "NewStrongPassword@2026"
  }
  ```

#### 4. `lockout` (Brute-Force Safeguard)
- **Endpoint**: `POST /functions/v1/lockout`
- **Actions**:
  - `action: "check"`: Returns current lockout status and remaining lockout duration.
  - `action: "record_failed"`: Increments failed attempts. After 5 consecutive failures, triggers 15-minute lockout.
  - `action: "record_success"`: Resets failed attempts to 0.
  - `action: "unlock"`: Admin-only manual account unlock.

---

### Deploying Edge Functions via Supabase CLI
```powershell
supabase functions deploy create-teacher --no-verify-jwt
supabase functions deploy student-first-login --no-verify-jwt
supabase functions deploy reset-password --no-verify-jwt
supabase functions deploy lockout --no-verify-jwt
```
*(Note: Functions handle their own authorization and validation internally).*

---

### Running Phase 2 Auth Tests
```powershell
psql $DB_URL -f supabase/tests/auth_tests.sql
```
*(Validates lockout after 5 failed attempts, verifies non-admin rejection, validates admin unlock, and rolls back cleanly).*

---

## 📱 Next Steps: Phase 3 (Flutter Desktop ERP)
- Swap local SQLite queries in `mips_erp` for the Supabase Flutter client.
- Implement Administrator cloud login screen with session caching.
- Preserve local desktop scanning and ID document storage while syncing all core data to Supabase.
