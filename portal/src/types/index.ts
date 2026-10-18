// src/types/index.ts
// Comprehensive domain types for MIPS Teacher & Student Portal

export type UserRole = 'student' | 'teacher' | 'admin';

export interface UserProfile {
  user_id: string;
  role: UserRole;
  active: boolean;
  student_id: number | null;
  teacher_id: number | null;
  failed_attempts: number;
  locked_at: string | null;
  must_change_password?: boolean;
  first_login_required?: boolean;
  created_at?: string;
  updated_at?: string;
}

export interface AuthUser {
  id: string;
  email?: string;
  role: UserRole;
  must_change_password?: boolean;
  first_login_required?: boolean;
  mfa_required?: boolean;
}

export interface StudentProfile {
  id: number;
  admission_number: string;
  registration_number: string | null;
  name: string;
  dob: string | null;
  phone: string | null;
  gender: string;
  course_id: number;
  batch_id: number;
  course_name?: string;
  batch_name?: string;
  batch_status?: 'active' | 'completed' | string;
  status: 'active' | 'completed' | 'discontinued' | 'tc_issued' | string;
  completed_on?: string | null;
  access_until?: string | null;
  skill_course_id?: number | null;
  skill_course_name?: string | null;
  skill_batch_id?: number | null;
  skill_batch_name?: string | null;
  current_semester?: number;
  current_year?: number;
}

export interface TeacherProfile {
  id: number;
  name: string;
  login_username: string;
  phone: string | null;
  email: string | null;
  status: string;
}

export interface LoginFailureDetails {
  requires_captcha?: boolean;
  is_locked?: boolean;
  attempts_remaining?: number;
}

export interface AuthResponse {
  success: boolean;
  error?: string;
  details?: LoginFailureDetails;
  user?: AuthUser;
}

export interface NotificationItem {
  id: number;
  category: 'programme' | 'exam' | 'fee_reminder' | 'timetable' | 'general';
  title: string;
  message: string;
  read_at: string | null;
  created_at: string;
  action_url?: string;
}

export interface SemesterSummary {
  semester_no: number;
  academic_year: number;
  start_date: string;
  end_date: string | null;
  is_current: boolean;
  sessions_held: number;
  present: number;
  late: number;
  absent: number;
  leave: number;
  percentage: number;
  met_minimum: boolean;
  semester_status: 'active' | 'closed' | string;
}

export interface AttendanceSummary {
  student_id: number;
  enrollment_id: number;
  course_name: string;
  batch_name: string;
  semester_no?: number;
  met_minimum?: boolean;
  is_current?: boolean;
  sessions_held: number;
  present: number;
  late: number;
  absent: number;
  leave: number;
  weighted_present: number;
  percentage: number;
  status_band: 'ok' | 'low' | 'shortage';
  can_miss_more: number;
  recover_sessions: number;
  morning_held: number;
  morning_present: number;
  morning_percentage: number;
  evening_held: number;
  evening_present: number;
  evening_percentage: number;
  deduction_absent_pts: number;
  deduction_late_pts: number;
}
