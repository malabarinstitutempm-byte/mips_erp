# MIPS ERP - Create & Change Flow Trace Report (Phase D1)

Date: 2026-10-26
Environment: Supabase PostgreSQL (AWS ap-south-1), Flutter Admin (Desktop/Web), React Portal (`portal/`)

---

## 1. Executive Summary & Root Cause Overview

Empirical investigation and reproduction of all 14 create and change flows revealed two critical architectural root causes responsible for data not appearing in lists and failing cross-user visibility:

1. **Universal RPC "Access Denied" Due to Decoupled Authentication**:
   - 55+ stored procedures (RPCs) across PostgreSQL enforce an administrative check:
     `IF NOT is_admin() THEN RAISE EXCEPTION 'Access denied. Administrator privilege required...'; END IF;`
   - The PostgreSQL helper function `is_admin()` evaluates:
     `SELECT 1 FROM public.profiles WHERE profiles.user_id = auth.uid() AND profiles.role = 'admin' ...`
   - However, both the Flutter Admin app and the React Teacher/Student Portal authenticate users against custom credential tables (`admin_accounts` and `portal_credentials` via `portal_verify_login`) **without generating a Supabase GoTrue Auth session**.
   - As a consequence, `auth.uid()` evaluates to `NULL` on every single client request made with the standard `anon` JWT.
   - Every administrative RPC (`import_students`, `save_marks`, `record_payment`, `send_announcement`, `save_daily_timetable`, `add_student_skill_course`, `submit_attendance`, `promote_semester`, `admin_unlock_account`, etc.) fails immediately with HTTP 400 (`P0001: Access denied`).

2. **Swallowed Errors and Phantom In-Memory Fallback Stores**:
   - Because RPCs fail, client repository methods caught errors in `catch (e) { debugPrint(...); ... }`.
   - Instead of displaying a hard failure, repositories routed saves into temporary Dart/JS in-memory stores (`FeesFallbackStore`, `_fallbackMarks`, `_fallbackAnnouncements`, `_fallbackBatches`, `_fallbackStudents`).
   - The user who performed the action saw an optimistic "Success" toast and an in-memory updated view.
   - PostgreSQL received **0 rows**.
   - Any page refresh or view by a second signed-in user found **no data**.
   - Additionally, empty database states previously triggered hardcoded fallback mock metrics (e.g. ₹24.8L fee totals).

---

## 2. Comprehensive Flow Trace Details

### Flow 1: Course (with Semester/Year Subjects)
- **Path**: `lib/features/courses/add_edit_course_screen.dart` -> `coursesProvider` (`lib/features/courses/courses_provider.dart`) -> `SupabaseCourseRepository.createCourse` & `addCourseSubject` (`lib/core/repositories/supabase/supabase_course_repository.dart`) -> `POST /rest/v1/courses` & `POST /rest/v1/course_subjects` -> PostgreSQL `public.courses`, `public.course_subjects` -> `coursesProvider` list query (`SELECT * FROM courses ORDER BY name ASC`) -> `course_list_screen.dart`.
- **(a) Request Sent**: Yes (Direct REST POST to `courses` and `course_subjects`).
- **(b) Response / Error**: `201 Created` with created course payload.
- **(c) Postgres Row Exists**: Yes (`courses` and `course_subjects` verified in DB).
- **(d) List Query Returns It**: Yes, for the creator session.
- **(e) Second Signed-in User Visibility**: **No**. Other admins and teacher pickers do not receive real-time invalidation. Riverpod providers stay stale until manually refreshed.
- **Classification**: **SAVED BUT STALE (no refresh)**.

---

### Flow 2: Batch (with First `batch_periods` Row)
- **Path**: `lib/features/batches/add_batch_screen.dart` -> `batchesProvider` (`lib/features/batches/batches_provider.dart`) -> `SupabaseBatchRepository.createBatch` (`lib/core/repositories/supabase/supabase_batch_repository.dart`) -> `POST /rest/v1/batches` -> PostgreSQL `public.batches` (triggers `trg_batch_create_first_period` creating `public.batch_periods`) -> `batchesProvider` (`SELECT batches.*, courses(name) FROM batches`) -> `batch_list_screen.dart`.
- **(a) Request Sent**: Yes (REST POST to `batches`).
- **(b) Response / Error**: `201 Created`.
- **(c) Postgres Row Exists**: Yes (`batches` row created; DB trigger automatically creates `batch_periods` with `period_number: 1`).
- **(d) List Query Returns It**: Yes, for creator session.
- **(e) Second Signed-in User Visibility**: **No**. Second admin or teacher batch dropdown does not update without manual reload.
- **Classification**: **SAVED BUT STALE (no refresh)**.

---

### Flow 3: Student Admission (Enrollment & Fee Item)
- **Path**: `lib/features/students/add_student_screen.dart` -> `studentsProvider` (`lib/features/students/students_provider.dart`) -> `SupabaseStudentRepository.createStudent` (`lib/core/repositories/supabase/supabase_student_repository.dart`) -> `POST /rest/v1/students` -> PostgreSQL `public.students` (triggers `trg_student_auto_enroll_and_fee` inserting `student_enrollments`, `fees`, and `fee_items`) -> `studentsProvider` (`SELECT * FROM students ...`) -> `student_list_screen.dart`.
- **(a) Request Sent**: Yes (REST POST to `students`).
- **(b) Response / Error**: `201 Created`.
- **(c) Postgres Row Exists**: Yes. Row exists in `students`, `student_enrollments`, `fees`, and `fee_items`. (Note: Previous FK failure on `batch_id: ?? 1` and case-sensitive gender check fixed in Migration 0031).
- **(d) List Query Returns It**: Yes for creator session.
- **(e) Second Signed-in User Visibility**: **No**. Second admin and teacher attendance rosters do not receive live updates.
- **Classification**: **SAVED BUT STALE (no refresh)**.

---

### Flow 4: Excel Import
- **Path**: `lib/features/students/import_students_screen.dart` -> `ImportService` (`lib/features/students/import_service.dart`) -> `SupabaseStudentRepository.importStudents` -> `RPC /rest/v1/rpc/import_students` -> PostgreSQL function `import_students()` -> `studentsProvider` -> `student_list_screen.dart`.
- **(a) Request Sent**: Yes (HTTP POST to `/rpc/import_students`).
- **(b) Response / Error**: `400 Bad Request`:
  `{"code":"P0001","details":null,"hint":null,"message":"Access denied. Only administrators can import students."}`
- **(c) Postgres Row Exists**: **No** (0 rows written).
- **(d) List Query Returns It**: **No**.
- **(e) Second Signed-in User Visibility**: **No**.
- **Classification**: **NOT PERMITTED (RLS or admin check)**.

---

### Flow 5: Teacher Provisioning
- **Path**: `lib/features/teachers/add_teacher_screen.dart` -> `teachersProvider` (`lib/features/teachers/teachers_provider.dart`) -> `SupabaseTeacherAdminRepository.createTeacher` (`lib/core/repositories/supabase/supabase_teacher_admin_repository.dart`) -> `RPC /rest/v1/rpc/admin_upsert_teacher` -> PostgreSQL `public.teachers` & `public.portal_credentials` -> `SupabaseTeacherAdminRepository.getTeachers()` -> `teacher_list_screen.dart`.
- **(a) Request Sent**: Yes (RPC call to `admin_upsert_teacher`).
- **(b) Response / Error**: `200 OK` (success payload with teacher object).
- **(c) Postgres Row Exists**: Yes (Rows created in `teachers` and `portal_credentials`).
- **(d) List Query Returns It**: Yes for the creator session.
- **(e) Second Signed-in User Visibility**: **No**. Other admins' teacher tables and account lists remain unrefreshed.
- **Classification**: **SAVED BUT STALE (no refresh)**.

---

### Flow 6: Exam Creation
- **Path**: `lib/features/exams/add_exam_dialog.dart` -> `examsProvider` (`lib/features/exams/exams_provider.dart`) -> `SupabaseExamRepository.createExam` (`lib/core/repositories/supabase/supabase_exam_repository.dart`) -> `POST /rest/v1/exams` & `POST /rest/v1/exam_subjects` -> PostgreSQL `public.exams`, `public.exam_subjects` -> `examsProvider` -> `exams_screen.dart`.
- **(a) Request Sent**: Yes (Direct REST POST).
- **(b) Response / Error**: `201 Created`.
- **(c) Postgres Row Exists**: Yes.
- **(d) List Query Returns It**: Yes for creator session.
- **(e) Second Signed-in User Visibility**: **No**. Second admin does not see exam without manual reload; student portal does not receive exam notification.
- **Classification**: **SAVED BUT STALE (no refresh)**.

---

### Flow 7: Mark Entry
- **Path**: `lib/features/exams/mark_entry_screen.dart` -> `markEntryProvider` -> `SupabaseMarkRepository.saveMarks` (`lib/core/repositories/supabase/supabase_mark_repository.dart`) -> `RPC /rest/v1/rpc/save_marks` -> PostgreSQL `public.marks` -> Exam details / Student result list.
- **(a) Request Sent**: Yes (RPC call to `save_marks`).
- **(b) Response / Error**: `400 Bad Request`:
  `{"code":"P0001","details":null,"hint":null,"message":"Access denied. Administrator privilege required to enter marks."}`
- **(c) Postgres Row Exists**: **No** (0 rows written).
- **(d) List Query Returns It**: In PostgreSQL: **No**. In Flutter app: UI fell back to in-memory `_fallbackMarks`, showing phantom data to creator only.
- **(e) Second Signed-in User Visibility**: **No**.
- **Classification**: **SAVED LOCALLY (In-memory fallback) / NOT PERMITTED**.

---

### Flow 8: Payment and Receipt
- **Path**: `lib/features/fees/record_payment_dialog.dart` -> `feesProvider` (`lib/features/fees/fees_provider.dart`) -> `SupabaseFeeRepository.addPayment` (`lib/core/repositories/supabase/supabase_fee_repository.dart`) -> `RPC /rest/v1/rpc/record_payment` -> PostgreSQL `public.payments`, `public.receipts`, `public.fees` -> `recentPaymentsProvider` / `pendingFeesProvider` -> `fees_screen.dart`.
- **(a) Request Sent**: Yes (RPC call to `record_payment`).
- **(b) Response / Error**: `400 Bad Request`:
  `{"code":"P0001","details":null,"hint":null,"message":"Access denied. Administrator privilege required to record payments."}`
- **(c) Postgres Row Exists**: **No** (0 rows written to `payments` or `receipts`).
- **(d) List Query Returns It**: In PostgreSQL: **No**. In Flutter app: Repository caught error and called `FeesFallbackStore.recordPayment(...)`, displaying a synthetic receipt to the user.
- **(e) Second Signed-in User Visibility**: **No**. Second admin and affected student's Fees tab showed nothing.
- **Classification**: **SAVED LOCALLY (In-memory `FeesFallbackStore`) / NOT PERMITTED**.

---

### Flow 9: Announcement
- **Path**: `lib/features/announcements/send_announcement_dialog.dart` -> `announcementsProvider` -> `SupabaseAnnouncementRepository.sendAnnouncement` (`lib/core/repositories/supabase/supabase_announcement_repository.dart`) -> `RPC /rest/v1/rpc/send_announcement` -> PostgreSQL `public.announcements`, `public.announcement_recipients` -> `announcementsProvider` -> Announcement list.
- **(a) Request Sent**: Yes (RPC call to `send_announcement`).
- **(b) Response / Error**: `400 Bad Request`:
  `{"code":"P0001","details":null,"hint":null,"message":"Access denied. Administrator privilege required."}`
- **(c) Postgres Row Exists**: **No** (0 rows).
- **(d) List Query Returns It**: In PostgreSQL: **No**. In Flutter: Repository caught error and appended to static `_fallbackAnnouncements`.
- **(e) Second Signed-in User Visibility**: **No**. Recipient students and teachers never received announcements.
- **Classification**: **SAVED LOCALLY (In-memory fallback) / NOT PERMITTED**.

---

### Flow 10: Daily Timetable
- **Path**: `portal/src/pages/DailyTimetable.tsx` / Flutter Timetable Screen -> `portal/src/services/dailyTimetableService.ts` / `supabase_timetable_repository.dart` -> `RPC /rest/v1/rpc/save_daily_timetable` -> PostgreSQL `public.daily_timetables`, `public.daily_timetable_entries` -> `fetchDailyTimetable` -> Timetable grid.
- **(a) Request Sent**: Yes (RPC call to `save_daily_timetable`).
- **(b) Response / Error**: `400 Bad Request`:
  `{"code":"P0001","details":null,"hint":null,"message":"Access denied. Only administrators can modify daily timetables."}`
- **(c) Postgres Row Exists**: **No** (0 rows written).
- **(d) List Query Returns It**: **No**.
- **(e) Second Signed-in User Visibility**: **No**. Students and teachers saw empty or stale timetables.
- **Classification**: **NOT PERMITTED (RLS or admin check)**.

---

### Flow 11: Skill-Course Enrollment
- **Path**: `lib/features/students/student_details_screen.dart` (Enroll skill course) -> `studentsProvider` -> `SupabaseStudentRepository.addSkillCourse` (`lib/core/repositories/supabase/supabase_student_repository.dart`) -> `RPC /rest/v1/rpc/add_student_skill_course` -> PostgreSQL `public.student_enrollments`, `public.fee_items` -> `getStudentEnrollments` -> Student Details Course list.
- **(a) Request Sent**: Yes (RPC call to `add_student_skill_course`).
- **(b) Response / Error**: `400 Bad Request`:
  `{"code":"P0001","details":null,"hint":null,"message":"Access denied. Administrator privilege required."}`
- **(c) Postgres Row Exists**: **No** (0 rows).
- **(d) List Query Returns It**: **No**.
- **(e) Second Signed-in User Visibility**: **No**.
- **Classification**: **NOT PERMITTED (RLS or admin check)**.

---

### Flow 12: Attendance Submit and Correction
- **Path**: `portal/src/pages/AttendanceMarking.tsx` / Flutter Admin Attendance -> `portal/src/services/teacherService.ts` / `SupabaseAttendanceAdminRepository` -> `RPC /rest/v1/rpc/submit_attendance` -> PostgreSQL `public.attendance_sessions`, `public.attendance_records` -> `getAttendanceSessions` -> Attendance review / student attendance summary.
- **(a) Request Sent**: Yes (RPC call to `submit_attendance`).
- **(b) Response / Error**: `400 Bad Request`:
  `{"code":"P0001","details":null,"hint":null,"message":"Access denied. Only registered teachers or administrators can submit attendance."}`
- **(c) Postgres Row Exists**: **No** (0 rows).
- **(d) List Query Returns It**: **No**.
- **(e) Second Signed-in User Visibility**: **No**. Other teachers did not see slot marked; admins saw unmarked session.
- **Classification**: **NOT PERMITTED (RLS or admin check)**.

---

### Flow 13: Batch Completion & Promotion
- **Path**: `lib/features/batches/batch_details_screen.dart` -> `batchesProvider` -> `SupabaseBatchRepository.promoteBatch` (`lib/core/repositories/supabase/supabase_batch_repository.dart`) -> `RPC /rest/v1/rpc/promote_semester` -> PostgreSQL `public.batches`, `public.batch_periods` -> `batchesProvider` -> Batch details header.
- **(a) Request Sent**: Yes (RPC call to `promote_semester`).
- **(b) Response / Error**: `400 Bad Request`:
  `{"code":"P0001","details":null,"hint":null,"message":"Access denied. Administrator privilege required to promote batches."}`
- **(c) Postgres Row Exists**: **No** (`current_semester` in PostgreSQL remains unchanged).
- **(d) List Query Returns It**: In PostgreSQL: **No**. In Flutter: Saved only in `_fallbackBatches`.
- **(e) Second Signed-in User Visibility**: **No**.
- **Classification**: **SAVED LOCALLY (In-memory fallback) / NOT PERMITTED**.

---

### Flow 14: Password Reset and Unlock
- **Path**: `lib/features/teachers/teacher_details_screen.dart` -> `teachersProvider` -> `SupabaseTeacherAdminRepository.unlockAccount` -> `RPC /rest/v1/rpc/admin_unlock_account` -> PostgreSQL `public.portal_credentials` (`failed_attempts`, `locked_until`) -> Account status badge.
- **(a) Request Sent**: Yes (RPC call to `admin_unlock_account`).
- **(b) Response / Error**: `400 Bad Request`:
  `{"code":"P0001","details":null,"hint":null,"message":"Access denied. Administrator privileges required."}`
- **(c) Postgres Row Exists**: **No** (Locked status unchanged).
- **(d) List Query Returns It**: **No**.
- **(e) Second Signed-in User Visibility**: **No** (Teacher cannot log in).
- **Classification**: **NOT PERMITTED (RLS or admin check)**.

---

## 3. Failure Classification Matrix

| Action | (a) Request Sent | (b) Exact Response / Error | (c) Row in Postgres | (d) Returned by List | (e) Visible to 2nd User | Failure Classification |
|---|---|---|---|---|---|---|
| **1. Course (with subjects)** | Yes (REST POST) | 201 Created | Yes | Yes (Creator) | No (Stale) | **SAVED BUT STALE** |
| **2. Batch (with batch_periods)** | Yes (REST POST) | 201 Created | Yes (Trigger) | Yes (Creator) | No (Stale) | **SAVED BUT STALE** |
| **3. Student Admission** | Yes (REST POST) | 201 Created | Yes (Trigger) | Yes (Creator) | No (Stale) | **SAVED BUT STALE** |
| **4. Excel Import** | Yes (RPC) | 400: `P0001 Access denied` | No | No | No | **NOT PERMITTED** |
| **5. Teacher Provisioning** | Yes (RPC) | 200 OK | Yes | Yes (Creator) | No (Stale) | **SAVED BUT STALE** |
| **6. Exam Creation** | Yes (REST POST) | 201 Created | Yes | Yes (Creator) | No (Stale) | **SAVED BUT STALE** |
| **7. Mark Entry** | Yes (RPC) | 400: `P0001 Access denied` | No | No (Local cache only) | No | **SAVED LOCALLY / NOT PERMITTED** |
| **8. Payment and Receipt** | Yes (RPC) | 400: `P0001 Access denied` | No | No (`FeesFallbackStore`) | No | **SAVED LOCALLY / NOT PERMITTED** |
| **9. Announcement** | Yes (RPC) | 400: `P0001 Access denied` | No | No (`_fallbackAnnouncements`)| No | **SAVED LOCALLY / NOT PERMITTED** |
| **10. Daily Timetable** | Yes (RPC) | 400: `P0001 Access denied` | No | No | No | **NOT PERMITTED** |
| **11. Skill Course Enrollment** | Yes (RPC) | 400: `P0001 Access denied` | No | No | No | **NOT PERMITTED** |
| **12. Attendance Submit/Correction**| Yes (RPC) | 400: `P0001 Access denied` | No | No | No | **NOT PERMITTED** |
| **13. Batch Promotion/Completion** | Yes (RPC) | 400: `P0001 Access denied` | No | No (`_fallbackBatches`) | No | **SAVED LOCALLY / NOT PERMITTED** |
| **14. Password Reset & Unlock** | Yes (RPC) | 400: `P0001 Access denied` | No | No | No | **NOT PERMITTED** |

---

## 4. Phase D1 Remediation Completed
1. Cleaned mock fallback data in `lib/core/repositories/supabase/fees_fallback_store.dart` (`getMetrics` now calculates real zeros instead of ₹24.8L).
2. Cleaned mock fallback metrics and sample payments in `lib/features/fees/fees_provider.dart` (`recentPaymentsProvider`, `feeMetricsProvider`, `studentPaymentsProvider`, `studentFeeDetailsProvider` now return true database values or clean zeros/empty arrays).
3. Documented full trace in `docs/create-flow-trace.md`.
