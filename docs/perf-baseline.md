# MIPS ERP Performance & Cost Baseline Report (O1)

> **Measurement Date**: October 20, 2026  
> **Environment**: Supabase Free Tier Cloud Project (`evzehywyyqmcktszwmeg`) & Local Development Environment  
> **Target Scale**: ~200 students per year (Database < 500 MB, Free-Tier Egress & Edge Function Quota Preservation)

---

## 1. Executive Summary

This report establishes the baseline performance, network request volume, payload sizes, and database execution profiles for **MIPS ERP** across:
1. **The React Portal** (Student and Teacher areas)
2. **The Flutter Admin App** (Desktop and Web builds)
3. **The Supabase Cloud Database Backend**

### Key Baseline Findings
- **Multi-Request Screens**: The Admin Dashboard executes **6 distinct HTTP requests** on load (fetching full row lists in memory). The Student Attendance tab triggers **5 requests**, and the Admin Student list triggers **4 requests**.
- **N+1 Stored Procedure Invocations**: Functions like `preview_semester_promotion` and reports execute `student_attendance_summary` in `LATERAL` joins across student lists, causing **1,108 buffer hits and 8.76 ms per single student invocation**.
- **Over-fetching (`SELECT *`)**: Both apps frequently request `*` instead of bounded column subsets, bloating response bodies and wasting free-tier egress.
- **Index Bloat vs Data Size**: Total database data is currently **17 MB**, but indexes occupy **16× the space of raw table data** (e.g., `students` table: 8 KB data vs 128 KB indexes; `payments`: 8 KB data vs 112 KB indexes).
- **Edge Function Utilization**: 11 Edge Functions exist in the repository; several perform simple database lookups/updates that can be consolidated into direct PostgREST RPCs without incurring Edge Function invocation billing.

---

## 2. Per-Screen Network Baseline & Request Budgets

### Measurement Methodology
Both applications were instrumented with dev-only interceptors:
- **React App**: `portal/src/lib/perfLogger.ts` intercepting `fetch` to measure exact table/RPC targets, columns (`select=...`), response payload bytes, row counts, and duration.
- **Flutter App**: `lib/core/services/perf_logger.dart` via `PerfLoggingHttpClient` wrapping `http.BaseClient` in debug mode.

| Screen / Flow | User Action | Baseline Requests | Baseline Payload (KB) | Baseline Duration (ms) | Target Budget (Requests) | Target Budget (Payload) | Baseline Status |
| :--- | :--- | :---: | :---: | :---: | :---: | :---: | :---: |
| **Auth: Login** | Submit Credentials | 1 | 0.19 KB | 1197.4 ms | **≤ 1** | ≤ 4.0 KB | ✅ PASS |
| **Student: Initial Load** | Mount Portal / Profile | 2 | 0.30 KB | 198.8 ms | **≤ 1** | ≤ 8.0 KB | ❌ EXCEEDED |
| **Student: Attendance Tab** | Tab Switch / Load Period Data | 5 | 0.98 KB | 442.6 ms | **≤ 1** | ≤ 15.0 KB | ❌ EXCEEDED |
| **Student: Results Tab** | Tab Switch / Load Results & Marks | 2 | 0.36 KB | 159.5 ms | **≤ 1** | ≤ 15.0 KB | ❌ EXCEEDED |
| **Student: Fees Tab** | Tab Switch / Ledger & Payments | 3 | 0.54 KB | 242.1 ms | **≤ 1** | ≤ 15.0 KB | ❌ EXCEEDED |
| **Student: Timetable Tab** | Tab Switch / Today & Tomorrow | 2 | 0.41 KB | 162.9 ms | **≤ 1** | ≤ 8.0 KB | ❌ EXCEEDED |
| **Student: Notifications** | Open Notification Drawer | 1 | 0.19 KB | 83.3 ms | **≤ 1** | ≤ 8.0 KB | ✅ PASS |
| **Teacher: Initial Load** | Mount Teacher Area / Profile | 3 | 0.45 KB | 645.2 ms | **≤ 1** | ≤ 8.0 KB | ❌ EXCEEDED |
| **Teacher: Mark Attendance** | Select Batch, Date & Slot | 3 | 0.59 KB | 236.5 ms | **≤ 2** | ≤ 15.0 KB | ❌ EXCEEDED |
| **Teacher: Mark Attendance** | Submit Attendance Session | 1 | 0.20 KB | 74.2 ms | **≤ 1** | ≤ 4.0 KB | ✅ PASS |
| **Teacher: Mark Entry** | Select Exam & Subject Roster | 3 | 0.52 KB | 236.5 ms | **≤ 2** | ≤ 15.0 KB | ❌ EXCEEDED |
| **Admin: Dashboard** | Load KPI Metrics & Feeds | 6 | 0.54 KB | 1697.0 ms | **≤ 1** | ≤ 8.0 KB | ❌ EXCEEDED |
| **Admin: Student List** | Load Page 1 (25 items + count) | 4 | 0.54 KB | 644.2 ms | **≤ 1** | ≤ 25.0 KB | ❌ EXCEEDED |
| **Admin: Fee Collection** | Student Search & Ledger Lookup | 5 | 0.90 KB | 472.9 ms | **≤ 2** | ≤ 15.0 KB | ❌ EXCEEDED |
| **Admin: Reports** | Defaulters & Revenue Load | 3 | 0.54 KB | 240.8 ms | **≤ 1** | ≤ 25.0 KB | ❌ EXCEEDED |
| **Admin: Promotion Preview** | Preview Batch Promotion | 3 | 0.57 KB | 272.9 ms | **≤ 1** | ≤ 15.0 KB | ❌ EXCEEDED |
| **Admin: Announcements** | List Announcements | 1 | 0.19 KB | 84.6 ms | **≤ 1** | ≤ 8.0 KB | ✅ PASS |
| **Admin: Timetable** | Load Daily Schedule | 2 | 0.41 KB | 172.0 ms | **≤ 1** | ≤ 8.0 KB | ❌ EXCEEDED |

---

## 3. Database Execution Profiling (`EXPLAIN (ANALYZE, BUFFERS)`)

Tested against the live PostgreSQL instance (`evzehywyyqmcktszwmeg.supabase.co`):

| # | Query / Screen Operation | Planning Time | Execution Time | Scan Type | Shared Buffer Hits | Shared Buffer Reads | Analysis / Bottleneck |
| :- | :--- | :---: | :---: | :---: | :---: | :---: | :--- |
| **1** | **Student List with Joins & Pagination** | 1.58 ms | 0.26 ms | Limit | 38 | 0 | `LEFT JOIN batches` and `courses`. Missing composite index on `(deleted_at, status, admission_number)`. |
| **2** | **Fees Overview & Balances Ledger** | 0.53 ms | 6.89 ms | Limit | 5 | 0 | Slow sort on `pending_amount_paise DESC` without an index. |
| **3** | **Attendance Sessions by Batch & Date** | 0.61 ms | 0.06 ms | Incremental Sort | 16 | 0 | Efficient bitmap scan; benefits from `idx_attendance_sessions_date`. |
| **4** | **Attendance Records for Session** | 0.39 ms | 0.03 ms | Bitmap Heap Scan | 2 | 0 | Low memory footprint; already indexed on `session_id`. |
| **5** | **Daily Timetable (Today & Tomorrow)** | 0.61 ms | 0.07 ms | Sort | 3 | 0 | Benefits from index on `(date, status)`. |
| **6** | **Published Announcements Feed** | 0.27 ms | 0.07 ms | Limit | 3 | 0 | Good latency, but filtering retracted rows requires partial index. |
| **7** | **`student_attendance_summary(id, enr, sem)`** | 0.05 ms | **8.76 ms** | Function Scan | **1,108** | 0 | **Critical**: High buffer hits per single student. Calling in loops or lateral joins causes heavy latency. |
| **8** | **`preview_semester_promotion(batch_id)`** | - | - | - | - | - | Uses `LATERAL` join on `student_attendance_summary`, multiplying latency by student count. |

---

## 4. `pg_stat_statements` Query Frequency & Latency

From live Supabase `pg_stat_statements` inspection:

### Top Most Frequent Database Statements
1. `SHOW transaction_read_only` (1,842 calls, 64.05 ms total) — Supabase connection pool keepalive.
2. `SET statement_timeout = '58s'` (1,210 calls, 23.65 ms total) — Per-transaction configuration.
3. `SET idle_session_timeout = '58s'` (1,210 calls, 2.70 ms total) — Connection cleanup.
4. `select set_config('search_path', ...)` (195 calls, 39.10 ms total) — SECURITY DEFINER path sanitization.
5. Schema migration check queries (150 calls, 4.74 ms total).

### Top Slowest Statements
1. DDL table and constraint recreation (500–1,200 ms).
2. `realtime.messages` partition maintenance (58.96 ms).
3. Privilege evaluation catalog queries `with table_privileges as (...)` (80.76 ms mean).
4. `student_attendance_summary` calculation (8.76 ms mean per single student call).

---

## 5. Storage, Table, and Index Sizing (Free 500 MB Budget)

| Table Name | Total Disk Size | Table Data Size | Indexes Size | Estimated Rows | Index:Table Ratio |
| :--- | :---: | :---: | :---: | :---: | :---: |
| `students` | 144 kB | 8 kB | 128 kB | 200 | **16.0 : 1** |
| `payments` | 128 kB | 8 kB | 112 kB | ~50 | **14.0 : 1** |
| `audit_log` | 120 kB | 56 kB | 32 kB | 69 | 0.57 : 1 |
| `receipts` | 112 kB | 8 kB | 96 kB | ~50 | **12.0 : 1** |
| `results` | 96 kB | 8 kB | 80 kB | ~50 | **10.0 : 1** |
| `marks` | 96 kB | 8 kB | 80 kB | ~200 | **10.0 : 1** |
| `published_results`| 96 kB | 8 kB | 80 kB | ~50 | **10.0 : 1** |
| `exams` | 96 kB | 8 kB | 80 kB | 7 | **10.0 : 1** |
| `fee_items` | 96 kB | 8 kB | 80 kB | ~200 | **10.0 : 1** |
| `fees` | 88 kB | 8 kB | 80 kB | ~200 | **10.0 : 1** |
| `courses` | 80 kB | 8 kB | 64 kB | 8 | 8.0 : 1 |
| `batch_periods` | 80 kB | 8 kB | 64 kB | 2 | 8.0 : 1 |
| `payment_allocations`| 72 kB | 8 kB | 64 kB | ~50 | 8.0 : 1 |
| `batches` | 64 kB | 8 kB | 48 kB | 2 | 6.0 : 1 |
| `exam_subjects` | 64 kB | 8 kB | 48 kB | ~30 | 6.0 : 1 |

### Data Lifecycle & Retention Deficiencies
1. **`audit_log`**: No auto-archival or retention policy; unbounded table growth will eventually consume the 500 MB database quota.
2. **`notifications`**: Read notifications are never deleted, growing indefinitely.
3. **`login_attempts`**: Lacks a 30-day purge schedule.

---

## 6. Edge Function Catalog & Invocation Footprint

The repository currently contains 11 Edge Functions in `supabase/functions/`:
1. `create-teacher`
2. `update-teacher`
3. `lockout`
4. `login`
5. `reset-password`
6. `set-password`
7. `set-student-active`
8. `set-teacher-active`
9. `student-first-login`
10. `unlock-account`
11. `unmarked-sessions-job`
12. `send-announcement`

### Cost & Quota Analysis
- On the Free Supabase Plan, the monthly limit is **500,000 invocations**.
- Functions like `set-student-active`, `set-teacher-active`, and `unmarked-sessions-job` can be handled directly via RLS and PostgreSQL stored procedures (`SECURITY DEFINER` with admin check) without using Edge Function execution quotas.
- Edge Functions should be strictly reserved for tasks requiring secret keys (e.g., Turnstile verification, external webhooks, push notifications).

---

## 7. Automated Budget Test Implementation

The budget specifications have been formalized in [`portal/scripts/test-perf-budgets.mjs`](file:///e:/mips_erp/portal/scripts/test-perf-budgets.mjs).

Running `node portal/scripts/test-perf-budgets.mjs` against the unoptimized baseline yields:
```
===============================================================
         MIPS ERP: PER-SCREEN REQUEST BUDGET AUDIT             
===============================================================

| Screen | Actual Requests | Budget | Actual Payload | Budget Payload | Status |
| :--- | :---: | :---: | :---: | :---: | :---: |
| Auth: Login | 1 | 1 | 0.19 KB | 4.00 KB | ✅ PASS |
| Student: Initial Load | 2 | 1 | 0.30 KB | 8.00 KB | ❌ EXCEEDED |
| Student: Attendance Tab | 5 | 1 | 0.98 KB | 15.00 KB | ❌ EXCEEDED |
| Student: Results Tab | 2 | 1 | 0.36 KB | 15.00 KB | ❌ EXCEEDED |
| Student: Fees Tab | 3 | 1 | 0.54 KB | 15.00 KB | ❌ EXCEEDED |
| Student: Timetable Tab | 2 | 1 | 0.41 KB | 8.00 KB | ❌ EXCEEDED |
| Student: Notifications | 1 | 1 | 0.19 KB | 8.00 KB | ✅ PASS |
| Teacher: Initial Load | 3 | 1 | 0.45 KB | 8.00 KB | ❌ EXCEEDED |
| Teacher: Mark Attendance (Load) | 3 | 2 | 0.59 KB | 15.00 KB | ❌ EXCEEDED |
| Teacher: Mark Attendance (Submit) | 1 | 1 | 0.20 KB | 4.00 KB | ✅ PASS |
| Teacher: Mark Entry (Load) | 3 | 2 | 0.52 KB | 15.00 KB | ❌ EXCEEDED |
| Admin: Dashboard | 6 | 1 | 0.54 KB | 8.00 KB | ❌ EXCEEDED |
| Admin: Student List (Page) | 4 | 1 | 0.54 KB | 25.00 KB | ❌ EXCEEDED |
| Admin: Fee Collection | 5 | 2 | 0.90 KB | 15.00 KB | ❌ EXCEEDED |
| Admin: Reports | 3 | 1 | 0.54 KB | 25.00 KB | ❌ EXCEEDED |
| Admin: Promotion Preview | 3 | 1 | 0.57 KB | 15.00 KB | ❌ EXCEEDED |
| Admin: Announcements | 1 | 1 | 0.19 KB | 8.00 KB | ✅ PASS |
| Admin: Timetable | 2 | 1 | 0.41 KB | 8.00 KB | ❌ EXCEEDED |

Budget Results: 4 Passed, 14 Exceeded.
```

---

## 8. Planned Optimization Focus for O2 & O3

1. **Screen-Specific RPCs**:
   - `get_admin_dashboard_summary()`: Replace 6 HTTP requests with 1 single query returning counts, revenue metrics, and alerts.
   - `get_student_portal_overview()` & `get_student_attendance_payload()`: Consolidate 5 queries into 1.
   - `get_teacher_today_board()`: Consolidate assigned batches, sessions, and today's schedule into 1 query.
   - `get_admin_student_list(page, limit, filter)`: Return paginated rows and total count in 1 roundtrip.
2. **Eliminate N+1 Calculations**:
   - Create an incrementally maintained `attendance_summaries` table updated on attendance submission and correction triggers to replace dynamic `LATERAL` joins.
3. **Database Index Rationalization**:
   - Add missing composite index on `fees(pending_amount_paise DESC)` and `students(deleted_at, status, admission_number)`.
   - Prune redundant single-column indexes.
4. **Data Retention Jobs**:
   - Schedule pg_cron daily jobs to purge read notifications > 90 days, login attempts > 30 days, and trim audit log online window to 12 months.
