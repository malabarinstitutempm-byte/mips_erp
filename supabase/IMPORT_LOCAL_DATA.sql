-- =============================================================================
-- MIPS ERP - Import Existing Data from Local Desktop SQLite to Supabase
-- Run this script AFTER running RUN_IN_SUPABASE_ALL_MIGRATIONS.sql
-- =============================================================================

-- 1. Settings
INSERT INTO settings (key, value) VALUES ('institution_name', 'Malabar Institute of Paramedical Science') ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
INSERT INTO settings (key, value) VALUES ('institution_address', 'CH Centre, Malappuram, Kerala - 676519') ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
INSERT INTO settings (key, value) VALUES ('receipt_prefix', 'REC-') ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;

-- 2. Academic Years
INSERT INTO academic_years (id, legacy_id, year_name, start_date, end_date, is_current) OVERRIDING SYSTEM VALUE VALUES (1, 1, '2026-2027', '2026-06-01', '2027-05-31', true) ON CONFLICT (id) DO NOTHING;

-- 3. Universities
INSERT INTO universities (id, legacy_id, name) OVERRIDING SYSTEM VALUE VALUES (1, 1, 'BSS / Kerala University of Health Sciences') ON CONFLICT (id) DO NOTHING;

-- 4. Courses
INSERT INTO courses (id, legacy_id, name, code, university_id, duration, total_fee_paise, description, status, structure, deleted_at) OVERRIDING SYSTEM VALUE VALUES (1, 1, 'Diploma in Medical Laboratory Technology (DMLT)', 'DMLT', 1, '2 Years', 4500000, '', 'active', 'year', NULL) ON CONFLICT (id) DO NOTHING;
INSERT INTO courses (id, legacy_id, name, code, university_id, duration, total_fee_paise, description, status, structure, deleted_at) OVERRIDING SYSTEM VALUE VALUES (2, 2, 'Diploma in X-Ray Technology', 'DXT', 1, '2 Years', 4000000, '', 'active', 'year', NULL) ON CONFLICT (id) DO NOTHING;
INSERT INTO courses (id, legacy_id, name, code, university_id, duration, total_fee_paise, description, status, structure, deleted_at) OVERRIDING SYSTEM VALUE VALUES (3, 3, 'drit', '4561', 1, '2year', 50000000, '', 'active', 'year', NULL) ON CONFLICT (id) DO NOTHING;
INSERT INTO courses (id, legacy_id, name, code, university_id, duration, total_fee_paise, description, status, structure, deleted_at) OVERRIDING SYSTEM VALUE VALUES (4, 4, 'vwregrrf', '132312', 1, '3', 12000000, '', 'active', 'year', NULL) ON CONFLICT (id) DO NOTHING;

-- 5. Batches
INSERT INTO batches (id, legacy_id, course_id, batch_name, start_date, end_date, deleted_at) OVERRIDING SYSTEM VALUE VALUES (1, 1, 1, 'DMLT Batch A', '2026-06-01', '2027-05-31', NULL) ON CONFLICT (id) DO NOTHING;
INSERT INTO batches (id, legacy_id, course_id, batch_name, start_date, end_date, deleted_at) OVERRIDING SYSTEM VALUE VALUES (2, 2, 2, 'DXT Batch A', '2026-06-01', '2027-05-31', NULL) ON CONFLICT (id) DO NOTHING;

-- 6. Students & Enrollments
INSERT INTO students (id, legacy_id, admission_number, registration_number, name, dob, gender, phone, email, address, admission_date, status, deleted_at) OVERRIDING SYSTEM VALUE VALUES (1, 1, 'ADM-2026-0001', NULL, 'Mohammed Shafi', '2005-05-15', 'Male', '9876543210', NULL, 'Malappuram, Kerala', '2026-06-05', 'active', NULL) ON CONFLICT (id) DO NOTHING;
INSERT INTO enrollments (student_id, course_id, batch_id, academic_year_id, status) VALUES (1, 1, 1, 1, 'active') ON CONFLICT (student_id, course_id, batch_id) DO NOTHING;
INSERT INTO students (id, legacy_id, admission_number, registration_number, name, dob, gender, phone, email, address, admission_date, status, deleted_at) OVERRIDING SYSTEM VALUE VALUES (2, 2, 'ADM-2026-0002', NULL, 'Fathima Sana', '2005-05-15', 'Male', '9876543211', NULL, 'Malappuram, Kerala', '2026-06-05', 'active', NULL) ON CONFLICT (id) DO NOTHING;
INSERT INTO enrollments (student_id, course_id, batch_id, academic_year_id, status) VALUES (2, 1, 1, 1, 'active') ON CONFLICT (student_id, course_id, batch_id) DO NOTHING;
INSERT INTO students (id, legacy_id, admission_number, registration_number, name, dob, gender, phone, email, address, admission_date, status, deleted_at) OVERRIDING SYSTEM VALUE VALUES (3, 3, 'ADM-2026-0003', NULL, 'Rahul Krishna', '2005-05-15', 'Male', '9876543212', NULL, 'Malappuram, Kerala', '2026-06-05', 'active', NULL) ON CONFLICT (id) DO NOTHING;
INSERT INTO enrollments (student_id, course_id, batch_id, academic_year_id, status) VALUES (3, 1, 1, 1, 'active') ON CONFLICT (student_id, course_id, batch_id) DO NOTHING;
INSERT INTO students (id, legacy_id, admission_number, registration_number, name, dob, gender, phone, email, address, admission_date, status, deleted_at) OVERRIDING SYSTEM VALUE VALUES (4, 4, 'ADM-2026-0004', NULL, 'Aisha Nida', '2005-05-15', 'Male', '9876543213', NULL, 'Malappuram, Kerala', '2026-06-05', 'active', NULL) ON CONFLICT (id) DO NOTHING;
INSERT INTO enrollments (student_id, course_id, batch_id, academic_year_id, status) VALUES (4, 2, 2, 1, 'active') ON CONFLICT (student_id, course_id, batch_id) DO NOTHING;
INSERT INTO students (id, legacy_id, admission_number, registration_number, name, dob, gender, phone, email, address, admission_date, status, deleted_at) OVERRIDING SYSTEM VALUE VALUES (5, 5, 'ADM-2026-0005', NULL, 'Vishnu Prasad', '2005-05-15', 'Male', '9876543214', NULL, 'Malappuram, Kerala', '2026-06-05', 'active', NULL) ON CONFLICT (id) DO NOTHING;
INSERT INTO enrollments (student_id, course_id, batch_id, academic_year_id, status) VALUES (5, 2, 2, 1, 'active') ON CONFLICT (student_id, course_id, batch_id) DO NOTHING;
INSERT INTO students (id, legacy_id, admission_number, registration_number, name, dob, gender, phone, email, address, admission_date, status, deleted_at) OVERRIDING SYSTEM VALUE VALUES (6, 6, 'ADM-2026-0006', '52145522333', 'mohammed hisham ck', NULL, 'Male', '4523654123', NULL, NULL, CURRENT_DATE, 'active', NULL) ON CONFLICT (id) DO NOTHING;
INSERT INTO enrollments (student_id, course_id, batch_id, academic_year_id, status) VALUES (6, 1, 1, 1, 'active') ON CONFLICT (student_id, course_id, batch_id) DO NOTHING;
INSERT INTO students (id, legacy_id, admission_number, registration_number, name, dob, gender, phone, email, address, admission_date, status, deleted_at) OVERRIDING SYSTEM VALUE VALUES (7, 7, 'ADM-2026-0007', 'tagiore', 'hiusdihswidhswd', NULL, 'Male', '554226412', NULL, NULL, CURRENT_DATE, 'active', NULL) ON CONFLICT (id) DO NOTHING;
INSERT INTO enrollments (student_id, course_id, batch_id, academic_year_id, status) VALUES (7, 2, 1, 1, 'active') ON CONFLICT (student_id, course_id, batch_id) DO NOTHING;
INSERT INTO students (id, legacy_id, admission_number, registration_number, name, dob, gender, phone, email, address, admission_date, status, deleted_at) OVERRIDING SYSTEM VALUE VALUES (8, 8, 'ADM-2026-0008', 'iuhiuhiuhi', 'iutr7tttut87oi', NULL, 'Male', '7512365478', NULL, NULL, CURRENT_DATE, 'active', NULL) ON CONFLICT (id) DO NOTHING;
INSERT INTO enrollments (student_id, course_id, batch_id, academic_year_id, status) VALUES (8, 2, 1, 1, 'active') ON CONFLICT (student_id, course_id, batch_id) DO NOTHING;
INSERT INTO students (id, legacy_id, admission_number, registration_number, name, dob, gender, phone, email, address, admission_date, status, deleted_at) OVERRIDING SYSTEM VALUE VALUES (9, 9, 'ADM-2026-0009', 'ferferfer', 'iorfirfnefjr', NULL, 'Male', '7512542132', NULL, NULL, CURRENT_DATE, 'active', NULL) ON CONFLICT (id) DO NOTHING;
INSERT INTO enrollments (student_id, course_id, batch_id, academic_year_id, status) VALUES (9, 2, 1, 1, 'active') ON CONFLICT (student_id, course_id, batch_id) DO NOTHING;
INSERT INTO students (id, legacy_id, admission_number, registration_number, name, dob, gender, phone, email, address, admission_date, status, deleted_at) OVERRIDING SYSTEM VALUE VALUES (10, 10, 'ADM-2026-0010', 'tagore', 'trhtehtht', NULL, 'Male', '85422664415', NULL, NULL, CURRENT_DATE, 'active', NULL) ON CONFLICT (id) DO NOTHING;
INSERT INTO enrollments (student_id, course_id, batch_id, academic_year_id, status) VALUES (10, 3, 1, 1, 'active') ON CONFLICT (student_id, course_id, batch_id) DO NOTHING;
INSERT INTO students (id, legacy_id, admission_number, registration_number, name, dob, gender, phone, email, address, admission_date, status, deleted_at) OVERRIDING SYSTEM VALUE VALUES (11, 11, 'ADM-2026-0011', 'tagore', 'hashim', '2005-01-16', 'Male', '85412365895', NULL, NULL, CURRENT_DATE, 'active', NULL) ON CONFLICT (id) DO NOTHING;
INSERT INTO enrollments (student_id, course_id, batch_id, academic_year_id, status) VALUES (11, 3, 1, 1, 'active') ON CONFLICT (student_id, course_id, batch_id) DO NOTHING;

-- 7. Resynchronize Identity Sequences
SELECT setval(pg_get_serial_sequence('courses', 'id'), coalesce(max(id), 1)) FROM courses;
SELECT setval(pg_get_serial_sequence('batches', 'id'), coalesce(max(id), 1)) FROM batches;
SELECT setval(pg_get_serial_sequence('students', 'id'), coalesce(max(id), 1)) FROM students;
SELECT setval(pg_get_serial_sequence('universities', 'id'), coalesce(max(id), 1)) FROM universities;
SELECT setval(pg_get_serial_sequence('academic_years', 'id'), coalesce(max(id), 1)) FROM academic_years;
