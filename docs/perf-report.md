# MIPS ERP Performance, Cost & Free-Tier Optimization Report (O1 – O6)

> **Execution Dates**: October 20 – October 21, 2026  
> **Environment**: Supabase Cloud Free Tier (`evzehywyyqmcktszwmeg.supabase.co`) & Production Web/Desktop Builds  
> **Target Scale**: ~200 students per year  
> **Guiding Principle**: Zero regressions in features, visual design, or security permissions.

---

## 1. Executive Summary

This comprehensive engineering report documents the performance and cost optimization of **MIPS ERP** across all 6 phases (**O1 to O6**). The entire system operates smoothly within the strict constraints of the **Supabase Free Plan**:
- **Database Size**: 17 MB current (vs 500 MB limit; 3.4% utilization)
- **Egress Bandwidth**: Projected at < 250 MB / month (vs 5 GB limit; < 5% utilization)
- **Edge Function Invocations**: Minimal usage via direct RPC offloading (< 5,000 / month vs 500,000 quota)
- **Client Load Times**: Initial JS entry reduced from 166.8 KB gz to **10.3 KB gz**; total login JS payload reduced by **70.7%**.

---

## 2. Before vs. After: Per-Screen Request & Payload Numbers

Every screen and user flow was measured before optimization (O1) and after optimization (O3–O5) using dev-only network interceptors and automated budget tests ([`portal/scripts/test-perf-budgets.mjs`](file:///e:/mips_erp/portal/scripts/test-perf-budgets.mjs)).

| Screen / Flow | User Action | Baseline Requests (O1) | Optimized Requests (O6) | Baseline Payload (KB) | Optimized Payload (KB) | Latency Before (ms) | Latency After (ms) | Request Budget | Status |
| :--- | :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| **Auth: Login** | Submit Credentials | 1 | **1** | 0.19 KB | **0.19 KB** | 1,197 ms | **245 ms** | ≤ 1 | ✅ PASS |
| **Student: Initial Load** | Mount Portal / Profile | 2 | **1** | 0.30 KB | **0.04 KB** | 198 ms | **42 ms** | ≤ 1 | ✅ PASS |
| **Student: Attendance Tab** | Tab Switch / Period Data | 5 | **1** | 0.98 KB | **0.11 KB** | 442 ms | **68 ms** | ≤ 1 | ✅ PASS |
| **Student: Results Tab** | Tab Switch / Marks & Status | 2 | **1** | 0.36 KB | **0.18 KB** | 159 ms | **45 ms** | ≤ 1 | ✅ PASS |
| **Student: Fees Tab** | Tab Switch / Ledger & Balance | 3 | **1** | 0.54 KB | **0.55 KB** | 242 ms | **72 ms** | ≤ 1 | ✅ PASS |
| **Student: Timetable Tab** | Tab Switch / Daily Schedule | 2 | **1** | 0.41 KB | **0.12 KB** | 162 ms | **38 ms** | ≤ 1 | ✅ PASS |
| **Student: Notifications** | Open Notification Drawer | 1 | **1** | 0.19 KB | **0.10 KB** | 83 ms | **28 ms** | ≤ 1 | ✅ PASS |
| **Teacher: Initial Load** | Mount Teacher Area / Profile | 3 | **1** | 0.45 KB | **0.09 KB** | 645 ms | **54 ms** | ≤ 1 | ✅ PASS |
| **Teacher: Mark Attendance** | Select Batch, Date & Slot | 3 | **2** | 0.59 KB | **0.38 KB** | 236 ms | **65 ms** | ≤ 2 | ✅ PASS |
| **Teacher: Mark Attendance** | Submit Attendance Session | 1 | **1** | 0.20 KB | **0.20 KB** | 74 ms | **61 ms** | ≤ 1 | ✅ PASS |
| **Teacher: Mark Entry** | Select Exam & Roster | 3 | **2** | 0.52 KB | **0.25 KB** | 236 ms | **58 ms** | ≤ 2 | ✅ PASS |
| **Admin: Dashboard** | Load KPI Metrics & Feeds | 6 | **1** | 0.54 KB | **0.11 KB** | 1,697 ms | **92 ms** | ≤ 1 | ✅ PASS |
| **Admin: Student List** | Load Page 1 (25 items + count) | 4 | **1** | 0.54 KB | **0.11 KB** | 644 ms | **48 ms** | ≤ 1 | ✅ PASS |
| **Admin: Fee Collection** | Student Search & Ledger | 5 | **2** | 0.90 KB | **0.73 KB** | 472 ms | **110 ms** | ≤ 2 | ✅ PASS |
| **Admin: Reports** | Defaulters & Revenue Load | 3 | **1** | 0.54 KB | **0.17 KB** | 240 ms | **56 ms** | ≤ 1 | ✅ PASS |
| **Admin: Promotion Preview** | Preview Batch Promotion | 3 | **1** | 0.57 KB | **0.11 KB** | 272 ms | **49 ms** | ≤ 1 | ✅ PASS |
| **Admin: Announcements** | List Announcements | 1 | **1** | 0.19 KB | **0.09 KB** | 84 ms | **32 ms** | ≤ 1 | ✅ PASS |
| **Admin: Timetable** | Load Daily Schedule | 2 | **1** | 0.41 KB | **0.12 KB** | 172 ms | **36 ms** | ≤ 1 | ✅ PASS |

**Overall Request Volume Reduction**: From **48 requests across core flows down to 21 requests** (**-56.2% request volume reduction**).  
**Dashboard Initial Load**: Reduced from **6 queries (1,697 ms) down to 1 consolidated RPC query (92 ms)** (**94.6% faster**).

---

## 3. Database Engineering & Optimization (O2)

### 3.1. Consolidated Set-Based RPCs
Multi-request flows were consolidated into atomic, SECURITY DEFINER functions returning JSON envelopes:
- `get_admin_dashboard_summary()`: Combines student counts, fee collections, today's attendance sessions, pending change requests, and recent alerts into a single 110-byte payload.
- `get_student_portal_overview()`: Merges student enrollment, current semester, fee due status, attendance summary, and unread notification counts.
- `get_student_attendance_payload(p_student_id, p_semester)`: Returns all semester attendance metrics, session history, and shortage boundaries.
- `get_student_fee_summary(p_student_id)`: Fetches fee allocations, payment history, and pending balances in one round-trip.
- `get_teacher_today_board()`: Delivers today's timetable periods, classes marked vs pending, and class rosters.
- `get_admin_student_list(p_query, p_course_id, p_batch_id, p_status, p_limit, p_offset)`: Single keyset-paginated procedure replacing 4 independent round-trips.

### 3.2. Elimination of N+1 LATERAL Joins
- **The Bottleneck**: `student_attendance_summary` previously executed in a `LATERAL` join across student lists, causing **1,108 buffer hits and 8.76 ms per single student invocation**.
- **The Solution**: Created an incrementally maintained summary table:
  ```sql
  CREATE TABLE public.student_period_attendance_summaries (
      student_id bigint NOT NULL REFERENCES public.students(id) ON DELETE CASCADE,
      enrollment_id bigint NOT NULL REFERENCES public.student_enrollments(id) ON DELETE CASCADE,
      period_no int NOT NULL DEFAULT 1,
      period_type text NOT NULL DEFAULT 'semester',
      sessions_held int NOT NULL DEFAULT 0,
      sessions_present int NOT NULL DEFAULT 0,
      sessions_late int NOT NULL DEFAULT 0,
      sessions_absent int NOT NULL DEFAULT 0,
      sessions_leave int NOT NULL DEFAULT 0,
      attendance_percentage numeric(5,2) NOT NULL DEFAULT 100.0,
      status_band text NOT NULL DEFAULT 'ok',
      PRIMARY KEY (student_id, enrollment_id, period_no)
  );
  ```
  Updated atomically via trigger `trg_sync_period_attendance_summary` upon session submission or correction. Previews and reports now execute simple indexed B-tree lookups (`0.02 ms`), completely removing the N+1 latency spike.

### 3.3. RLS InitPlan Optimization
Wrapped auth helper calls in scalar subqueries `(SELECT auth.uid())` and `(SELECT is_admin())` across all RLS policies. PostgreSQL evaluates scalar subqueries once per query as an **InitPlan** rather than executing the helper function for every candidate table row.

### 3.4. Auto-Retention Lifecycle (`pg_cron`)
To prevent the 500 MB database quota from accumulating historical debris, an automated daily purge runs at 03:00 UTC via `pg_cron`:
- `audit_log`: Retains 12 months online; older entries pruned.
- `notifications`: Retains 90 days of read notifications.
- `login_attempts`: Retains 30 days of authentication attempts.
- `push_subscriptions`: Pruned automatically on 404/410 GCM/APNs error responses.

---

## 4. Client-Side Request Minimization (O3)

### 4.1. React (TanStack Query)
- **Tiered Stale & Garbage Collection Times**:
  - Reference data (courses, batches, grading schemes, settings): `staleTime: 60 min`, `gcTime: 24 hours`.
  - Financials & Results: `staleTime: 10 min`, `gcTime: 60 min`.
  - Realtime alerts & today's attendance: `staleTime: 30 sec`, `gcTime: 5 min`.
- **Focus Refetching**: Disabled `refetchOnWindowFocus` and `refetchOnReconnect` across static tables.
- **Realtime Lifecycle**: Exactly one Supabase Realtime channel per user, exclusively watching `notifications`. Channel automatically pauses (`unsubscribe`) when the browser tab is hidden (`document.visibilityState === 'hidden'`) and resumes on focus.

### 4.2. Flutter (Riverpod)
- **Reference Caching**: Configured `ref.keepAlive()` with in-memory TTL caching for courses, academic years, and fee templates.
- **Search Debounce**: 400 ms debounce timer requiring ≥ 2 characters before initiating network queries.
- **Direct RPC Wiring**: Updated repositories to invoke consolidated RPCs rather than chained multi-table queries.

---

## 5. Edge Functions & Push Optimization (O4)

| Edge Function | Baseline Status | Optimized Implementation | Billing Impact |
| :--- | :--- | :--- | :--- |
| `unlock-account` | Incurred Edge Function call on every admin unlock | Replaced with direct RPC `admin_unlock_account(p_user_id, ...)` | **0 Edge Function calls** |
| `login` | Executed 3 separate DB round-trips per auth attempt | Atomic `record_login_success` write + in-memory 5-minute MFA cache | **66% fewer DB queries per login** |
| `send-announcement` | Looped single Web Push requests | 50-chunk concurrent dispatcher with auto 404/410 dead endpoint pruning | **Minimal CPU time & connection reuse** |

---

## 6. Payload & Load-Time Optimization (O5)

### 6.1. JavaScript Code Splitting & Manual Chunking
Vite configuration updated with route-level `React.lazy()` and Rollup `manualChunks`:
- **App Shell Entry (`index.js`)**: Reduced from **582.4 kB (166.8 kB gz) down to 33.2 kB (10.3 kB gz)** (**94.3% reduction**).
- **Vendor Splitting**:
  - `vendor-react`: 80.4 KB gz
  - `vendor-supabase`: 57.1 KB gz
  - `vendor-query`: 10.4 KB gz
  - `vendor-icons`: 6.4 KB gz
  - Total Initial JS at Login: **170.5 KB gz** (well under the 250 KB budget).
- **PDF Isolation**: `html2pdf.js` (981.8 kB / 285.4 kB gz) dynamically isolated into an on-demand async chunk loaded only when a user clicks export.
- **Route Bundles**: `StudentArea` (17.4 KB gz) and `TeacherArea` (14.5 KB gz) load only upon authenticated navigation.

### 6.2. Assets & Image Optimization
- **Web Portal Logo**: 2455×2531 uncompressed PNG (1,755.4 KB) replaced with 512×512 WebP (**31.9 KB**, **-98.2% reduction**) and optimized PNG (**148.2 KB**, **-91.5% reduction**).
- **Flutter Logo**: 1.75 MB replaced with 148 KB optimized PNG.
- **Unused Fonts & Dependencies Purged**:
  - Purged unused `assets/fonts/` (NotoSans TTFs: 1.25 MB) from `pubspec.yaml`.
  - Removed unused `bcrypt` and redundant `riverpod` dependencies.
- **CDN WebP Thumbnails**: Implemented `transformImageUrl()` helper directing image requests to Supabase CDN transform URLs:
  - Student list avatars: `width=96, quality=75, format=webp` (~4–8 KB vs 2 MB raw).
  - Student profile hero: `width=384, quality=75, format=webp` (~18–25 KB vs 2 MB raw).

---

## 7. Guards, Monitoring & CI Budgets (O6)

### 7.1. Admin System Health Page
Implemented `SystemHealthView` in Flutter Admin (`SettingsScreen` Tab 8) powered by `admin_get_system_health()` RPC:
- **Real-Time Free-Tier Quota Cards**:
  - Database Storage: 17 MB / 500 MB (3.4%), Health: Healthy (Warning at 350 MB)
  - Egress: 5 GB budget tracking
  - Edge Functions: 500,000 monthly calls tracking
  - File Storage: 1 GB budget tracking
- **Warning Banners**: Automated visual alerts at 70% of free-plan limits.
- **Table Disk Breakdown**: Live row counts, raw heap sizes, and index sizes.
- **Retention Status**: Active indicators for audit logs, notifications, and dead push endpoints.
- **Direct Link**: Button opening the live Supabase Billing & Usage dashboard.

### 7.2. Automated CI Budget Verification

```
===============================================================
          MIPS ERP: CI PERFORMANCE BUDGET AUDIT SUMMARY        
===============================================================

1. Per-Screen Request Budgets (portal/scripts/test-perf-budgets.mjs)
   -> 18 Passed, 0 Exceeded (100% PASS)

2. Bundle Size & Isolation Budgets (tools/test_bundle_budgets.mjs)
   -> App Shell JS: 10.08 KB gz (Budget: <= 50 KB)   -> ✅ PASS
   -> Vendor React: 80.42 KB gz (Budget: <= 100 KB)  -> ✅ PASS
   -> Vendor Supabase: 57.14 KB gz (Budget: <= 80 KB)-> ✅ PASS
   -> Main CSS: 8.35 KB gz (Budget: <= 30 KB)        -> ✅ PASS
   -> PDF Isolation: html2pdf isolated async chunk   -> ✅ PASS
   -> WebP Logo: 31.21 KB (Budget: <= 50 KB)         -> ✅ PASS

3. Query-Plan & Index Verification (tools/test_query_plans.mjs)
   -> Top 20 ERP Queries Tested with enable_seqscan = off
   -> 20 Passed, 0 Unindexed Sequential Scans (100% PASS)
```

---

## 8. Verification & Test Evidence

All security and functional test suites were re-executed to prove zero regression:
- **Portal Vitest Suite**: **87 / 87 passed** across 11 test files.
- **Security & RLS Audit**: **24 / 24 passed** (`security_audit.test.ts`, `phase9d_announcements_security.test.ts`).
- **Flutter Unit Tests**: **8 / 8 passed** (`phase4_features_unit_test.dart`).
- **Flutter Code Analysis**: **0 compile or analyzer errors** (`flutter analyze`).

---

## 9. Remaining Risks & Free-Plan Operational Guidelines

1. **Student Photo Upload Volume**:
   - *Risk*: If staff upload raw camera photos (10–15 MB each), database storage for 200 students could accumulate ~2–3 GB over time.
   - *Mitigation*: Photos are stored locally on the admin workstation, and remote storage uses CDN WebP transforms (`w=96`/`w=384`, `q=75`). Upload guidelines should recommend cropping photos in the client crop dialog before upload.
2. **PostgreSQL Connection Pool**:
   - *Risk*: Direct PostgreSQL connections are limited on Supabase Free Tier (~60 direct pooler connections).
   - *Mitigation*: The React web portal and Flutter web client connect exclusively via PostgREST HTTP/2 (which uses Supabase Supavisor connection pooling and does not exhaust PostgreSQL connection slots).
3. **Daily Data Retention**:
   - *Risk*: If `pg_cron` extension is disabled or paused, `audit_log` and `notifications` will grow indefinitely.
   - *Mitigation*: `admin_get_system_health()` alerts administrators on the System Health dashboard if table sizes exceed warning thresholds.
