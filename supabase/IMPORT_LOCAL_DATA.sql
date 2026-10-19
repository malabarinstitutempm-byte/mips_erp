-- =============================================================================
-- MIPS ERP - Master Data Import from Desktop SQLite DB to Supabase
-- Run this script in Supabase SQL Editor AFTER RUN_IN_SUPABASE_ALL_MIGRATIONS.sql
-- =============================================================================

-- 1. Settings
INSERT INTO settings (key, value) VALUES ('institution_name', 'Malabar Institute of Paramedical Science') ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
INSERT INTO settings (key, value) VALUES ('institution_address', 'CH Centre, Malappuram, Kerala - 676519') ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
INSERT INTO settings (key, value) VALUES ('receipt_prefix', 'REC-') ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;

-- 2. Academic Years
ALTER TABLE IF EXISTS academic_years ADD COLUMN IF NOT EXISTS start_date date, ADD COLUMN IF NOT EXISTS end_date date;
INSERT INTO academic_years (id, legacy_id, year_name, is_current) OVERRIDING SYSTEM VALUE VALUES (1, 1, '2026-2027', true) ON CONFLICT (id) DO UPDATE SET year_name = EXCLUDED.year_name;

-- 3. Universities
INSERT INTO universities (id, legacy_id, name) OVERRIDING SYSTEM VALUE VALUES (1, 1, 'BSS / Kerala University of Health Sciences') ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name;

-- 4. Courses
INSERT INTO courses (id, legacy_id, name, code, university_id, duration, total_fee_paise, description, status, structure) OVERRIDING SYSTEM VALUE VALUES (1, 1, 'Diploma in Medical Laboratory Technology (DMLT)', 'DMLT', 1, '2 Years', 4500000, NULL, 'active', 'year') ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, total_fee_paise = EXCLUDED.total_fee_paise;
INSERT INTO courses (id, legacy_id, name, code, university_id, duration, total_fee_paise, description, status, structure) OVERRIDING SYSTEM VALUE VALUES (2, 2, 'Diploma in X-Ray Technology', 'DXT', 1, '2 Years', 4000000, NULL, 'active', 'year') ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, total_fee_paise = EXCLUDED.total_fee_paise;
INSERT INTO courses (id, legacy_id, name, code, university_id, duration, total_fee_paise, description, status, structure) OVERRIDING SYSTEM VALUE VALUES (3, 3, 'drit', '4561', 1, '2year', 0, NULL, 'active', 'year') ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, total_fee_paise = EXCLUDED.total_fee_paise;
INSERT INTO courses (id, legacy_id, name, code, university_id, duration, total_fee_paise, description, status, structure) OVERRIDING SYSTEM VALUE VALUES (4, 4, 'vwregrrf', '132312', 1, '3', 0, NULL, 'active', 'year') ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, total_fee_paise = EXCLUDED.total_fee_paise;

-- 5. Batches
INSERT INTO batches (id, legacy_id, course_id, batch_name, start_date, end_date) OVERRIDING SYSTEM VALUE VALUES (1, 1, 1, 'DMLT Batch A', '2026-06-01', '2027-05-31') ON CONFLICT (id) DO UPDATE SET batch_name = EXCLUDED.batch_name;
INSERT INTO batches (id, legacy_id, course_id, batch_name, start_date, end_date) OVERRIDING SYSTEM VALUE VALUES (2, 2, 2, 'DXT Batch A', '2026-06-01', '2027-05-31') ON CONFLICT (id) DO UPDATE SET batch_name = EXCLUDED.batch_name;

-- 6. Students
INSERT INTO students (id, legacy_id, admission_number, registration_number, name, dob, gender, phone, email, address, admission_date, course_id, batch_id, university_id, academic_year_id, status) OVERRIDING SYSTEM VALUE VALUES (1, 1, 'ADM-2026-0001', NULL, 'Mohammed Shafi', '2005-05-15', 'Male', '9876543210', NULL, 'Malappuram, Kerala', '2026-06-05', 1, 1, 1, 1, 'active') ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, phone = EXCLUDED.phone;
INSERT INTO students (id, legacy_id, admission_number, registration_number, name, dob, gender, phone, email, address, admission_date, course_id, batch_id, university_id, academic_year_id, status) OVERRIDING SYSTEM VALUE VALUES (2, 2, 'ADM-2026-0002', NULL, 'Fathima Sana', '2005-05-15', 'Male', '9876543211', NULL, 'Malappuram, Kerala', '2026-06-05', 1, 1, 1, 1, 'active') ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, phone = EXCLUDED.phone;
INSERT INTO students (id, legacy_id, admission_number, registration_number, name, dob, gender, phone, email, address, admission_date, course_id, batch_id, university_id, academic_year_id, status) OVERRIDING SYSTEM VALUE VALUES (3, 3, 'ADM-2026-0003', NULL, 'Rahul Krishna', '2005-05-15', 'Male', '9876543212', NULL, 'Malappuram, Kerala', '2026-06-05', 1, 1, 1, 1, 'active') ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, phone = EXCLUDED.phone;
INSERT INTO students (id, legacy_id, admission_number, registration_number, name, dob, gender, phone, email, address, admission_date, course_id, batch_id, university_id, academic_year_id, status) OVERRIDING SYSTEM VALUE VALUES (4, 4, 'ADM-2026-0004', NULL, 'Aisha Nida', '2005-05-15', 'Male', '9876543213', NULL, 'Malappuram, Kerala', '2026-06-05', 2, 2, 1, 1, 'active') ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, phone = EXCLUDED.phone;
INSERT INTO students (id, legacy_id, admission_number, registration_number, name, dob, gender, phone, email, address, admission_date, course_id, batch_id, university_id, academic_year_id, status) OVERRIDING SYSTEM VALUE VALUES (5, 5, 'ADM-2026-0005', NULL, 'Vishnu Prasad', '2005-05-15', 'Male', '9876543214', NULL, 'Malappuram, Kerala', '2026-06-05', 2, 2, 1, 1, 'active') ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, phone = EXCLUDED.phone;
INSERT INTO students (id, legacy_id, admission_number, registration_number, name, dob, gender, phone, email, address, admission_date, course_id, batch_id, university_id, academic_year_id, status) OVERRIDING SYSTEM VALUE VALUES (6, 6, 'ADM-2026-0006', '52145522333', 'mohammed hisham ck', NULL, 'Male', '4523654123', NULL, NULL, '2026-06-05', 1, 1, 1, 1, 'active') ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, phone = EXCLUDED.phone;
INSERT INTO students (id, legacy_id, admission_number, registration_number, name, dob, gender, phone, email, address, admission_date, course_id, batch_id, university_id, academic_year_id, status) OVERRIDING SYSTEM VALUE VALUES (7, 7, 'ADM-2026-0007', 'tagiore', 'hiusdihswidhswd', NULL, 'Male', '554226412', NULL, NULL, '2026-06-05', 2, 1, 1, 1, 'active') ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, phone = EXCLUDED.phone;
INSERT INTO students (id, legacy_id, admission_number, registration_number, name, dob, gender, phone, email, address, admission_date, course_id, batch_id, university_id, academic_year_id, status) OVERRIDING SYSTEM VALUE VALUES (8, 8, 'ADM-2026-0008', 'iuhiuhiuhi', 'iutr7tttut87oi', NULL, 'Male', '7512365478', NULL, NULL, '2026-06-05', 2, 1, 1, 1, 'active') ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, phone = EXCLUDED.phone;
INSERT INTO students (id, legacy_id, admission_number, registration_number, name, dob, gender, phone, email, address, admission_date, course_id, batch_id, university_id, academic_year_id, status) OVERRIDING SYSTEM VALUE VALUES (9, 9, 'ADM-2026-0009', 'ferferfer', 'iorfirfnefjr', NULL, 'Male', '7512542132', NULL, NULL, '2026-06-05', 2, 1, 1, 1, 'active') ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, phone = EXCLUDED.phone;
INSERT INTO students (id, legacy_id, admission_number, registration_number, name, dob, gender, phone, email, address, admission_date, course_id, batch_id, university_id, academic_year_id, status) OVERRIDING SYSTEM VALUE VALUES (10, 10, 'ADM-2026-0010', 'tagore', 'trhtehtht', NULL, 'Male', '85422664415', NULL, NULL, '2026-06-05', 3, 1, 1, 1, 'active') ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, phone = EXCLUDED.phone;
INSERT INTO students (id, legacy_id, admission_number, registration_number, name, dob, gender, phone, email, address, admission_date, course_id, batch_id, university_id, academic_year_id, status) OVERRIDING SYSTEM VALUE VALUES (11, 11, 'ADM-2026-0011', 'tagore', 'hashim', '2005-01-16', 'Male', '85412365895', NULL, NULL, '2026-06-05', 3, 1, 1, 1, 'active') ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, phone = EXCLUDED.phone;

-- 7. Student Enrollments
INSERT INTO student_enrollments (student_id, course_id, batch_id, kind, status) VALUES (1, 1, 1, 'primary', 'active') ON CONFLICT DO NOTHING;
INSERT INTO student_enrollments (student_id, course_id, batch_id, kind, status) VALUES (2, 1, 1, 'primary', 'active') ON CONFLICT DO NOTHING;
INSERT INTO student_enrollments (student_id, course_id, batch_id, kind, status) VALUES (3, 1, 1, 'primary', 'active') ON CONFLICT DO NOTHING;
INSERT INTO student_enrollments (student_id, course_id, batch_id, kind, status) VALUES (4, 2, 2, 'primary', 'active') ON CONFLICT DO NOTHING;
INSERT INTO student_enrollments (student_id, course_id, batch_id, kind, status) VALUES (5, 2, 2, 'primary', 'active') ON CONFLICT DO NOTHING;
INSERT INTO student_enrollments (student_id, course_id, batch_id, kind, status) VALUES (6, 1, 1, 'primary', 'active') ON CONFLICT DO NOTHING;
INSERT INTO student_enrollments (student_id, course_id, batch_id, kind, status) VALUES (7, 2, 1, 'primary', 'active') ON CONFLICT DO NOTHING;
INSERT INTO student_enrollments (student_id, course_id, batch_id, kind, status) VALUES (8, 2, 1, 'primary', 'active') ON CONFLICT DO NOTHING;
INSERT INTO student_enrollments (student_id, course_id, batch_id, kind, status) VALUES (9, 2, 1, 'primary', 'active') ON CONFLICT DO NOTHING;
INSERT INTO student_enrollments (student_id, course_id, batch_id, kind, status) VALUES (10, 3, 1, 'primary', 'active') ON CONFLICT DO NOTHING;
INSERT INTO student_enrollments (student_id, course_id, batch_id, kind, status) VALUES (11, 3, 1, 'primary', 'active') ON CONFLICT DO NOTHING;

-- 8. Fees
INSERT INTO fees (id, legacy_id, student_id, total_fee_paise, paid_amount_paise, pending_amount_paise) OVERRIDING SYSTEM VALUE VALUES (1, 1, 1, 4500000, 1000000, 3500000) ON CONFLICT (id) DO UPDATE SET paid_amount_paise = EXCLUDED.paid_amount_paise, pending_amount_paise = EXCLUDED.pending_amount_paise;
INSERT INTO fees (id, legacy_id, student_id, total_fee_paise, paid_amount_paise, pending_amount_paise) OVERRIDING SYSTEM VALUE VALUES (2, 2, 2, 4500000, 1000000, 3500000) ON CONFLICT (id) DO UPDATE SET paid_amount_paise = EXCLUDED.paid_amount_paise, pending_amount_paise = EXCLUDED.pending_amount_paise;
INSERT INTO fees (id, legacy_id, student_id, total_fee_paise, paid_amount_paise, pending_amount_paise) OVERRIDING SYSTEM VALUE VALUES (3, 3, 3, 4500000, 1000000, 3500000) ON CONFLICT (id) DO UPDATE SET paid_amount_paise = EXCLUDED.paid_amount_paise, pending_amount_paise = EXCLUDED.pending_amount_paise;
INSERT INTO fees (id, legacy_id, student_id, total_fee_paise, paid_amount_paise, pending_amount_paise) OVERRIDING SYSTEM VALUE VALUES (4, 4, 4, 4000000, 1000000, 3000000) ON CONFLICT (id) DO UPDATE SET paid_amount_paise = EXCLUDED.paid_amount_paise, pending_amount_paise = EXCLUDED.pending_amount_paise;
INSERT INTO fees (id, legacy_id, student_id, total_fee_paise, paid_amount_paise, pending_amount_paise) OVERRIDING SYSTEM VALUE VALUES (5, 5, 5, 4000000, 1000000, 3000000) ON CONFLICT (id) DO UPDATE SET paid_amount_paise = EXCLUDED.paid_amount_paise, pending_amount_paise = EXCLUDED.pending_amount_paise;
INSERT INTO fees (id, legacy_id, student_id, total_fee_paise, paid_amount_paise, pending_amount_paise) OVERRIDING SYSTEM VALUE VALUES (6, 6, 6, 4500000, 1100000, 3400000) ON CONFLICT (id) DO UPDATE SET paid_amount_paise = EXCLUDED.paid_amount_paise, pending_amount_paise = EXCLUDED.pending_amount_paise;
INSERT INTO fees (id, legacy_id, student_id, total_fee_paise, paid_amount_paise, pending_amount_paise) OVERRIDING SYSTEM VALUE VALUES (7, 7, 7, 4000000, 4000000, 0) ON CONFLICT (id) DO UPDATE SET paid_amount_paise = EXCLUDED.paid_amount_paise, pending_amount_paise = EXCLUDED.pending_amount_paise;
INSERT INTO fees (id, legacy_id, student_id, total_fee_paise, paid_amount_paise, pending_amount_paise) OVERRIDING SYSTEM VALUE VALUES (8, 8, 8, 4000000, 0, 4000000) ON CONFLICT (id) DO UPDATE SET paid_amount_paise = EXCLUDED.paid_amount_paise, pending_amount_paise = EXCLUDED.pending_amount_paise;
INSERT INTO fees (id, legacy_id, student_id, total_fee_paise, paid_amount_paise, pending_amount_paise) OVERRIDING SYSTEM VALUE VALUES (9, 9, 9, 4000000, 0, 4000000) ON CONFLICT (id) DO UPDATE SET paid_amount_paise = EXCLUDED.paid_amount_paise, pending_amount_paise = EXCLUDED.pending_amount_paise;
INSERT INTO fees (id, legacy_id, student_id, total_fee_paise, paid_amount_paise, pending_amount_paise) OVERRIDING SYSTEM VALUE VALUES (10, 10, 10, 0, 0, 0) ON CONFLICT (id) DO UPDATE SET paid_amount_paise = EXCLUDED.paid_amount_paise, pending_amount_paise = EXCLUDED.pending_amount_paise;
INSERT INTO fees (id, legacy_id, student_id, total_fee_paise, paid_amount_paise, pending_amount_paise) OVERRIDING SYSTEM VALUE VALUES (11, 11, 11, 0, 0, 0) ON CONFLICT (id) DO UPDATE SET paid_amount_paise = EXCLUDED.paid_amount_paise, pending_amount_paise = EXCLUDED.pending_amount_paise;

-- 9. Payments
INSERT INTO payments (id, legacy_id, student_id, amount_paise, payment_mode, reference_number, remarks, date, is_cancelled, cancel_reason) OVERRIDING SYSTEM VALUE VALUES (1, 1, 1, 1000000, 'cash', 'CASH-1', 'First Installment', '2026-06-10', false, NULL) ON CONFLICT (id) DO UPDATE SET amount_paise = EXCLUDED.amount_paise;
INSERT INTO payments (id, legacy_id, student_id, amount_paise, payment_mode, reference_number, remarks, date, is_cancelled, cancel_reason) OVERRIDING SYSTEM VALUE VALUES (2, 2, 2, 1000000, 'cash', 'CASH-1', 'First Installment', '2026-06-10', false, NULL) ON CONFLICT (id) DO UPDATE SET amount_paise = EXCLUDED.amount_paise;
INSERT INTO payments (id, legacy_id, student_id, amount_paise, payment_mode, reference_number, remarks, date, is_cancelled, cancel_reason) OVERRIDING SYSTEM VALUE VALUES (3, 3, 3, 1000000, 'cash', 'CASH-1', 'First Installment', '2026-06-10', false, NULL) ON CONFLICT (id) DO UPDATE SET amount_paise = EXCLUDED.amount_paise;
INSERT INTO payments (id, legacy_id, student_id, amount_paise, payment_mode, reference_number, remarks, date, is_cancelled, cancel_reason) OVERRIDING SYSTEM VALUE VALUES (4, 4, 4, 1000000, 'cash', 'CASH-1', 'First Installment', '2026-06-10', false, NULL) ON CONFLICT (id) DO UPDATE SET amount_paise = EXCLUDED.amount_paise;
INSERT INTO payments (id, legacy_id, student_id, amount_paise, payment_mode, reference_number, remarks, date, is_cancelled, cancel_reason) OVERRIDING SYSTEM VALUE VALUES (5, 5, 5, 1000000, 'cash', 'CASH-1', 'First Installment', '2026-06-10', false, NULL) ON CONFLICT (id) DO UPDATE SET amount_paise = EXCLUDED.amount_paise;
INSERT INTO payments (id, legacy_id, student_id, amount_paise, payment_mode, reference_number, remarks, date, is_cancelled, cancel_reason) OVERRIDING SYSTEM VALUE VALUES (6, 6, 6, 400000, 'cash', 'ewfwefqerf', '', '2026-10-12T14:45:32.365387', false, NULL) ON CONFLICT (id) DO UPDATE SET amount_paise = EXCLUDED.amount_paise;
INSERT INTO payments (id, legacy_id, student_id, amount_paise, payment_mode, reference_number, remarks, date, is_cancelled, cancel_reason) OVERRIDING SYSTEM VALUE VALUES (7, 7, 7, 1000000, 'cash', '655265262', '', '2026-10-14T11:17:34.550781', false, NULL) ON CONFLICT (id) DO UPDATE SET amount_paise = EXCLUDED.amount_paise;
INSERT INTO payments (id, legacy_id, student_id, amount_paise, payment_mode, reference_number, remarks, date, is_cancelled, cancel_reason) OVERRIDING SYSTEM VALUE VALUES (8, 8, 7, 3000000, 'cash', '', '', '2026-10-14T11:18:04.582898', false, NULL) ON CONFLICT (id) DO UPDATE SET amount_paise = EXCLUDED.amount_paise;
INSERT INTO payments (id, legacy_id, student_id, amount_paise, payment_mode, reference_number, remarks, date, is_cancelled, cancel_reason) OVERRIDING SYSTEM VALUE VALUES (9, 9, 6, 500000, 'cash', '', '', '2026-10-14T11:43:31.768869', false, NULL) ON CONFLICT (id) DO UPDATE SET amount_paise = EXCLUDED.amount_paise;
INSERT INTO payments (id, legacy_id, student_id, amount_paise, payment_mode, reference_number, remarks, date, is_cancelled, cancel_reason) OVERRIDING SYSTEM VALUE VALUES (10, 10, 6, 200000, 'cash', '', 'admission fee', '2026-10-14T11:47:20.342948', false, NULL) ON CONFLICT (id) DO UPDATE SET amount_paise = EXCLUDED.amount_paise;

-- 10. Receipts
INSERT INTO receipts (id, legacy_id, payment_id, receipt_number) OVERRIDING SYSTEM VALUE VALUES (1, 1, 5, 'REC-8BBE94E9') ON CONFLICT (id) DO UPDATE SET receipt_number = EXCLUDED.receipt_number;
INSERT INTO receipts (id, legacy_id, payment_id, receipt_number) OVERRIDING SYSTEM VALUE VALUES (2, 2, 6, 'MIPS/2026/0001') ON CONFLICT (id) DO UPDATE SET receipt_number = EXCLUDED.receipt_number;
INSERT INTO receipts (id, legacy_id, payment_id, receipt_number) OVERRIDING SYSTEM VALUE VALUES (3, 3, 7, 'MIPS/2026/0002') ON CONFLICT (id) DO UPDATE SET receipt_number = EXCLUDED.receipt_number;
INSERT INTO receipts (id, legacy_id, payment_id, receipt_number) OVERRIDING SYSTEM VALUE VALUES (4, 4, 8, 'MIPS/2026/0003') ON CONFLICT (id) DO UPDATE SET receipt_number = EXCLUDED.receipt_number;
INSERT INTO receipts (id, legacy_id, payment_id, receipt_number) OVERRIDING SYSTEM VALUE VALUES (5, 5, 9, 'MIPS/2026/0004') ON CONFLICT (id) DO UPDATE SET receipt_number = EXCLUDED.receipt_number;
INSERT INTO receipts (id, legacy_id, payment_id, receipt_number) OVERRIDING SYSTEM VALUE VALUES (6, 6, 10, 'MIPS/2026/0005') ON CONFLICT (id) DO UPDATE SET receipt_number = EXCLUDED.receipt_number;

-- 11. Grading Schemes
INSERT INTO grading_schemes (id, min_percent, max_percent, grade, is_pass) OVERRIDING SYSTEM VALUE VALUES (13, 90.0, 100.0, 'A+', true) ON CONFLICT (id) DO UPDATE SET grade = EXCLUDED.grade;
INSERT INTO grading_schemes (id, min_percent, max_percent, grade, is_pass) OVERRIDING SYSTEM VALUE VALUES (14, 80.0, 89.99, 'A', true) ON CONFLICT (id) DO UPDATE SET grade = EXCLUDED.grade;
INSERT INTO grading_schemes (id, min_percent, max_percent, grade, is_pass) OVERRIDING SYSTEM VALUE VALUES (15, 70.0, 79.99, 'B+', true) ON CONFLICT (id) DO UPDATE SET grade = EXCLUDED.grade;
INSERT INTO grading_schemes (id, min_percent, max_percent, grade, is_pass) OVERRIDING SYSTEM VALUE VALUES (16, 60.0, 69.99, 'B', true) ON CONFLICT (id) DO UPDATE SET grade = EXCLUDED.grade;
INSERT INTO grading_schemes (id, min_percent, max_percent, grade, is_pass) OVERRIDING SYSTEM VALUE VALUES (17, 50.0, 59.99, 'C+', true) ON CONFLICT (id) DO UPDATE SET grade = EXCLUDED.grade;
INSERT INTO grading_schemes (id, min_percent, max_percent, grade, is_pass) OVERRIDING SYSTEM VALUE VALUES (18, 40.0, 49.99, 'C', true) ON CONFLICT (id) DO UPDATE SET grade = EXCLUDED.grade;
INSERT INTO grading_schemes (id, min_percent, max_percent, grade, is_pass) OVERRIDING SYSTEM VALUE VALUES (19, 0.0, 39.99, 'F', false) ON CONFLICT (id) DO UPDATE SET grade = EXCLUDED.grade;

-- 12. Exams
INSERT INTO exams (id, legacy_id, name, academic_year_id, course_id, batch_id, exam_date, publish_date, status, semester) OVERRIDING SYSTEM VALUE VALUES (1, 1, 'jejjedjfd', 1, 2, 1, '2026-10-06T13:21:44.395814', NULL, 'draft', NULL) ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, status = EXCLUDED.status;
INSERT INTO exams (id, legacy_id, name, academic_year_id, course_id, batch_id, exam_date, publish_date, status, semester) OVERRIDING SYSTEM VALUE VALUES (2, 2, 'final exam 2026', 1, 2, 1, '2026-10-12T10:56:21.408646', NULL, 'draft', NULL) ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, status = EXCLUDED.status;
INSERT INTO exams (id, legacy_id, name, academic_year_id, course_id, batch_id, exam_date, publish_date, status, semester) OVERRIDING SYSTEM VALUE VALUES (4, 4, 'regrgrgr', 1, 2, 1, '2026-10-12T11:13:52.366877', NULL, 'draft', NULL) ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, status = EXCLUDED.status;
INSERT INTO exams (id, legacy_id, name, academic_year_id, course_id, batch_id, exam_date, publish_date, status, semester) OVERRIDING SYSTEM VALUE VALUES (5, 5, 'frforjjrfjr', 1, 3, 1, '2026-10-12T11:14:36.593787', NULL, 'draft', NULL) ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, status = EXCLUDED.status;
INSERT INTO exams (id, legacy_id, name, academic_year_id, course_id, batch_id, exam_date, publish_date, status, semester) OVERRIDING SYSTEM VALUE VALUES (7, 7, 'final test new', 1, 3, 1, '2026-10-13T13:27:39.072305', '2026-10-13T13:28:22.174525', 'draft', NULL) ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, status = EXCLUDED.status;

-- 13. Exam Subjects
INSERT INTO exam_subjects (id, legacy_id, exam_id, name, code, max_marks, pass_marks, display_order) OVERRIDING SYSTEM VALUE VALUES (1, 1, 1, 'efwefewfwefew', '123', 100.0, 40.0, 0) ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name;
INSERT INTO exam_subjects (id, legacy_id, exam_id, name, code, max_marks, pass_marks, display_order) OVERRIDING SYSTEM VALUE VALUES (2, 2, 1, 'ewefewfew', '456', 100.0, 40.0, 1) ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name;
INSERT INTO exam_subjects (id, legacy_id, exam_id, name, code, max_marks, pass_marks, display_order) OVERRIDING SYSTEM VALUE VALUES (3, 3, 2, 'jpforjgpjrg', 'rt', 100.0, 40.0, 0) ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name;
INSERT INTO exam_subjects (id, legacy_id, exam_id, name, code, max_marks, pass_marks, display_order) OVERRIDING SYSTEM VALUE VALUES (4, 4, 2, 'gtgtgtre', 'ml', 100.0, 40.0, 1) ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name;
INSERT INTO exam_subjects (id, legacy_id, exam_id, name, code, max_marks, pass_marks, display_order) OVERRIDING SYSTEM VALUE VALUES (5, 5, 3, 'thgtgetg', '123', 100.0, 40.0, 0) ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name;
INSERT INTO exam_subjects (id, legacy_id, exam_id, name, code, max_marks, pass_marks, display_order) OVERRIDING SYSTEM VALUE VALUES (6, 6, 4, '2rfwrw', '343', 100.0, 40.0, 0) ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name;
INSERT INTO exam_subjects (id, legacy_id, exam_id, name, code, max_marks, pass_marks, display_order) OVERRIDING SYSTEM VALUE VALUES (7, 7, 5, 'r2rrqerew4', '332432', 100.0, 40.0, 0) ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name;
INSERT INTO exam_subjects (id, legacy_id, exam_id, name, code, max_marks, pass_marks, display_order) OVERRIDING SYSTEM VALUE VALUES (8, 8, 5, 'fgwerfrwfw', '3221', 100.0, 40.0, 1) ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name;
INSERT INTO exam_subjects (id, legacy_id, exam_id, name, code, max_marks, pass_marks, display_order) OVERRIDING SYSTEM VALUE VALUES (9, 9, 6, 'rgfdef', '232', 100.0, 40.0, 0) ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name;
INSERT INTO exam_subjects (id, legacy_id, exam_id, name, code, max_marks, pass_marks, display_order) OVERRIDING SYSTEM VALUE VALUES (10, 10, 6, 'adsfdfds', '234444', 100.0, 40.0, 1) ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name;
INSERT INTO exam_subjects (id, legacy_id, exam_id, name, code, max_marks, pass_marks, display_order) OVERRIDING SYSTEM VALUE VALUES (11, 11, 7, 'rgetgtrgtr', '102', 100.0, 40.0, 0) ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name;
INSERT INTO exam_subjects (id, legacy_id, exam_id, name, code, max_marks, pass_marks, display_order) OVERRIDING SYSTEM VALUE VALUES (12, 12, 7, 'next', '103', 100.0, 40.0, 1) ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name;

-- 14. Marks
INSERT INTO marks (id, legacy_id, exam_id, subject_id, student_id, marks_obtained, is_absent) OVERRIDING SYSTEM VALUE VALUES (3, 3, 6, 10, 10, 50.0, false) ON CONFLICT (id) DO UPDATE SET marks_obtained = EXCLUDED.marks_obtained;
INSERT INTO marks (id, legacy_id, exam_id, subject_id, student_id, marks_obtained, is_absent) OVERRIDING SYSTEM VALUE VALUES (4, 4, 6, 10, 11, 50.0, false) ON CONFLICT (id) DO UPDATE SET marks_obtained = EXCLUDED.marks_obtained;
INSERT INTO marks (id, legacy_id, exam_id, subject_id, student_id, marks_obtained, is_absent) OVERRIDING SYSTEM VALUE VALUES (5, 5, 7, 11, 10, 50.0, false) ON CONFLICT (id) DO UPDATE SET marks_obtained = EXCLUDED.marks_obtained;
INSERT INTO marks (id, legacy_id, exam_id, subject_id, student_id, marks_obtained, is_absent) OVERRIDING SYSTEM VALUE VALUES (6, 6, 7, 12, 10, 50.0, false) ON CONFLICT (id) DO UPDATE SET marks_obtained = EXCLUDED.marks_obtained;
INSERT INTO marks (id, legacy_id, exam_id, subject_id, student_id, marks_obtained, is_absent) OVERRIDING SYSTEM VALUE VALUES (7, 7, 7, 11, 11, 45.0, false) ON CONFLICT (id) DO UPDATE SET marks_obtained = EXCLUDED.marks_obtained;
INSERT INTO marks (id, legacy_id, exam_id, subject_id, student_id, marks_obtained, is_absent) OVERRIDING SYSTEM VALUE VALUES (8, 8, 7, 12, 11, 30.0, false) ON CONFLICT (id) DO UPDATE SET marks_obtained = EXCLUDED.marks_obtained;

-- 15. Results
INSERT INTO results (id, legacy_id, exam_id, student_id, total_marks, percentage, grade, status, rank) OVERRIDING SYSTEM VALUE VALUES (1, 1, 7, 10, 100.0, 50.0, 'C+', 'Pass', 1) ON CONFLICT (id) DO UPDATE SET total_marks = EXCLUDED.total_marks;

-- 16. Reset Identity Sequences
SELECT setval(pg_get_serial_sequence('academic_years', 'id'), coalesce(max(id), 1)) FROM academic_years;
SELECT setval(pg_get_serial_sequence('universities', 'id'), coalesce(max(id), 1)) FROM universities;
SELECT setval(pg_get_serial_sequence('courses', 'id'), coalesce(max(id), 1)) FROM courses;
SELECT setval(pg_get_serial_sequence('batches', 'id'), coalesce(max(id), 1)) FROM batches;
SELECT setval(pg_get_serial_sequence('students', 'id'), coalesce(max(id), 1)) FROM students;
SELECT setval(pg_get_serial_sequence('fees', 'id'), coalesce(max(id), 1)) FROM fees;
SELECT setval(pg_get_serial_sequence('payments', 'id'), coalesce(max(id), 1)) FROM payments;
SELECT setval(pg_get_serial_sequence('receipts', 'id'), coalesce(max(id), 1)) FROM receipts;
SELECT setval(pg_get_serial_sequence('grading_schemes', 'id'), coalesce(max(id), 1)) FROM grading_schemes;
SELECT setval(pg_get_serial_sequence('exams', 'id'), coalesce(max(id), 1)) FROM exams;
SELECT setval(pg_get_serial_sequence('exam_subjects', 'id'), coalesce(max(id), 1)) FROM exam_subjects;
SELECT setval(pg_get_serial_sequence('marks', 'id'), coalesce(max(id), 1)) FROM marks;
SELECT setval(pg_get_serial_sequence('results', 'id'), coalesce(max(id), 1)) FROM results;