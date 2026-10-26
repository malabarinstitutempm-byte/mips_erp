// src/services/studentService.ts
// Student Portal Data Fetching Layer with RLS Compliance & Lazy Loading

import { supabase } from '../lib/supabase';
import { accountSyncService } from './accountSyncService';
import type { AttendanceSummary, NotificationItem, StudentProfile, SemesterSummary } from '../types';

export interface ExamResultRecord {
  id: number;
  examId: number;
  examName: string;
  examCode: string;
  courseId: number;
  courseName: string;
  courseType?: 'primary' | 'skill';
  courseStructure?: 'semester' | 'year' | 'single';
  periodType?: 'semester' | 'year' | 'single';
  periodNo?: number;
  periodDisplay?: string;
  batchName: string;
  publishedAt: string;
  totalMarks: number;
  maxMarks: number;
  percentage: number;
  grade: string;
  status: 'PASS' | 'FAIL' | 'WITHHELD';
  resultCode: string;
  subjects: {
    subjectId: number;
    subjectName: string;
    subjectCode: string;
    obtainedMarks: number;
    maxMarks: number;
    passMarks: number;
    isPass: boolean;
    isAbsent: boolean;
  }[];
}

export interface StudentFeeLedger {
  summary: {
    totalFeePaise: number;
    paidAmountPaise: number;
    pendingAmountPaise: number;
    primaryFeePaise: number;
    primaryPaidPaise: number;
    primaryPendingPaise: number;
    skillFeePaise: number;
    skillPaidPaise: number;
    skillPendingPaise: number;
  };
  items: {
    id: number;
    title: string;
    kind: string;
    courseName?: string;
    amountPaise: number;
    paidAmountPaise: number;
    pendingAmountPaise: number;
    dueDate: string | null;
    status: 'Paid' | 'Due' | 'Overdue';
  }[];
  payments: {
    id: number;
    receiptNumber: string;
    date: string;
    amountPaise: number;
    paymentMode: string;
    referenceNumber: string | null;
  }[];
  lastUpdated: string;
}

export interface CalendarSessionDay {
  date: string; // YYYY-MM-DD
  slot: 'morning' | 'evening';
  status: 'present' | 'absent' | 'late' | 'leave' | 'no_class';
}

export interface StudentEnrollmentInfo {
  enrollmentId: number;
  courseId: number;
  courseName: string;
  courseType: 'primary' | 'skill';
  courseStructure?: 'semester' | 'year' | 'single';
  attendanceBasis?: 'semester' | 'year' | 'none';
  durationYears?: number;
  batchId: number;
  batchName: string;
  status?: 'active' | 'completed' | 'discontinued' | 'tc_issued' | string;
  completedOn?: string | null;
  currentSemester?: number;
  currentYear?: number;
}

export interface TimetableSchedule {
  timetableId: number;
  batchId: number;
  batchName: string;
  courseName: string;
  courseType: 'primary' | 'skill';
  academicYear: string;
  effectiveFrom: string;
  publishedAt: string;
  entries: {
    id: number;
    weekday: number; // 1 = Mon ... 6 = Sat
    slot: 'morning' | 'evening';
    startTime: string;
    endTime: string;
    subjectName: string;
    teacherName: string;
    room: string;
  }[];
}

export const studentService = {
  // 1. Student Profile & Enrolled Batches
  async getStudentProfile(studentIdInput?: string | number): Promise<{ profile: StudentProfile; enrollments: StudentEnrollmentInfo[] }> {
    try {
      let targetStudentId: number | null = null;
      if (studentIdInput !== undefined && studentIdInput !== null) {
        const cleanStr = String(studentIdInput).replace('s_', '');
        const n = parseInt(cleanStr, 10);
        if (!isNaN(n) && n > 0) targetStudentId = n;
      }
      if (!targetStudentId) {
        try {
          const stored = localStorage.getItem('mips_portal_user');
          if (stored) {
            const u = JSON.parse(stored);
            const cleanStr = String(u.id || '').replace('s_', '');
            const n = parseInt(cleanStr, 10);
            if (!isNaN(n) && n > 0) targetStudentId = n;
          }
        } catch (_) {}
      }

      let rpcData: any = null;
      if (targetStudentId) {
        const { data, error } = await supabase.rpc('get_portal_student_overview', {
          p_student_id: targetStudentId,
        });
        if (!error && data && !data.error && data.profile) {
          rpcData = data;
        }
      }

      if (!rpcData) {
        const { data, error } = await supabase.rpc('get_student_portal_overview');
        if (!error && data && !data.error && data.profile) {
          rpcData = data;
        }
      }

      if (rpcData && rpcData.profile) {
        const profileView = rpcData.profile;
        const rawEnrollments = rpcData.enrollments || [];
        const enrollments: StudentEnrollmentInfo[] = rawEnrollments.map((e: any) => {
          const sem = Number(e.current_semester || 1);
          const yr = Number(e.current_year || (sem > 0 ? Math.ceil(sem / 2) : 1));
          return {
            enrollmentId: e.enrollment_id || 0,
            courseId: e.course_id,
            courseName: e.course_name || profileView.course_name || 'Course',
            courseType: (e.course_type || 'primary') as 'primary' | 'skill',
            courseStructure: (e.course_structure || 'semester') as 'semester' | 'year' | 'single',
            attendanceBasis: (e.attendance_basis || e.course_structure || 'semester') as 'semester' | 'year' | 'none',
            durationYears: Number(e.duration_years || 2),
            batchId: e.batch_id,
            batchName: e.batch_name || profileView.batch_name || 'Batch',
            status: e.status || 'active',
            completedOn: e.completed_on || null,
            currentSemester: sem,
            currentYear: yr,
          };
        });

        if (enrollments.length === 0 && profileView.course_id) {
          enrollments.push({
            enrollmentId: 0,
            courseId: profileView.course_id,
            courseName: profileView.course_name || 'Primary Course',
            courseType: 'primary',
            courseStructure: 'semester',
            attendanceBasis: 'semester',
            durationYears: 2,
            batchId: profileView.batch_id || 0,
            batchName: profileView.batch_name || 'Main Batch',
            status: profileView.status || 'active',
            completedOn: profileView.completed_on || null,
            currentSemester: 1,
            currentYear: 1,
          });
        }

        const primaryEnrollment = enrollments.find((e) => e.courseType === 'primary') || enrollments[0];
        const skillEnrollment = enrollments.find((e) => e.courseType === 'skill');

        const activeSemester = primaryEnrollment?.currentSemester || 1;
        const activeYear = primaryEnrollment?.currentYear || Math.ceil(activeSemester / 2);

        const profile: StudentProfile = {
          id: profileView.id,
          admission_number: profileView.admission_number,
          registration_number: profileView.registration_number,
          name: profileView.name,
          dob: profileView.dob || null,
          phone: profileView.phone,
          gender: profileView.gender,
          course_id: primaryEnrollment?.courseId || profileView.course_id,
          batch_id: primaryEnrollment?.batchId || profileView.batch_id,
          course_name: primaryEnrollment?.courseName || profileView.course_name,
          batch_name: primaryEnrollment?.batchName || profileView.batch_name,
          batch_status: profileView.batch_status || 'active',
          status: profileView.status || 'active',
          completed_on: profileView.completed_on || null,
          access_until: profileView.access_until || null,
          skill_course_id: skillEnrollment?.courseId,
          skill_course_name: skillEnrollment?.courseName,
          skill_batch_id: skillEnrollment?.batchId,
          skill_batch_name: skillEnrollment?.batchName,
          current_semester: activeSemester,
          current_year: activeYear,
          course_structure: primaryEnrollment?.courseStructure || 'semester',
          attendance_basis: primaryEnrollment?.attendanceBasis || 'semester',
          duration_years: primaryEnrollment?.durationYears || 2,
        };

        return { profile, enrollments };
      }

      // Fallback: direct table queries
      const { data: profileView, error } = await supabase
        .from('student_profile_view')
        .select('*')
        .maybeSingle();

      if (!error && profileView) {
        // Fetch enrollments (Primary & Skill) including completed
        const { data: enrollmentsData } = await supabase
          .from('student_enrollments')
          .select(`
            id,
            course_id,
            batch_id,
            kind,
            status,
            completed_on,
            courses ( id, name, course_type, structure, attendance_basis, duration_years ),
            batches ( id, batch_name, status, completed_on, current_semester, current_year )
          `)
          .eq('student_id', profileView.id)
          .is('deleted_at', null);

        const enrollments: StudentEnrollmentInfo[] = (enrollmentsData || []).map((e: any) => {
          const sem = Number(e.batches?.current_semester || 1);
          const yr = Number(e.batches?.current_year || (sem > 0 ? Math.ceil(sem / 2) : 1));
          return {
            enrollmentId: e.id,
            courseId: e.course_id,
            courseName: e.courses?.name || profileView.course_name || 'Course',
            courseType: (e.courses?.course_type || e.kind || 'primary') as 'primary' | 'skill',
            courseStructure: (e.courses?.structure || 'semester') as 'semester' | 'year' | 'single',
            attendanceBasis: (e.courses?.attendance_basis || e.courses?.structure || 'semester') as 'semester' | 'year' | 'none',
            durationYears: Number(e.courses?.duration_years || 1),
            batchId: e.batch_id,
            batchName: e.batches?.batch_name || profileView.batch_name || 'Batch',
            status: e.status || 'active',
            completedOn: e.completed_on || null,
            currentSemester: sem,
            currentYear: yr,
          };
        });

        if (enrollments.length === 0 && profileView.course_id) {
          enrollments.push({
            enrollmentId: 0,
            courseId: profileView.course_id,
            courseName: profileView.course_name || 'Primary Course',
            courseType: 'primary',
            courseStructure: 'semester',
            attendanceBasis: 'semester',
            durationYears: 2,
            batchId: profileView.batch_id || 0,
            batchName: profileView.batch_name || 'Main Batch',
            status: profileView.status || 'active',
            completedOn: profileView.completed_on || null,
            currentSemester: 1,
            currentYear: 1,
          });
        }

        const primaryEnrollment = enrollments.find((e) => e.courseType === 'primary') || enrollments[0];
        const skillEnrollment = enrollments.find((e) => e.courseType === 'skill');

        const activeSemester = primaryEnrollment?.currentSemester || 1;
        const activeYear = primaryEnrollment?.currentYear || Math.ceil(activeSemester / 2);

        const profile: StudentProfile = {
          id: profileView.id,
          admission_number: profileView.admission_number,
          registration_number: profileView.registration_number,
          name: profileView.name,
          dob: profileView.dob || null,
          phone: profileView.phone,
          gender: profileView.gender,
          course_id: primaryEnrollment?.courseId || profileView.course_id,
          batch_id: primaryEnrollment?.batchId || profileView.batch_id,
          course_name: primaryEnrollment?.courseName || profileView.course_name,
          batch_name: primaryEnrollment?.batchName || profileView.batch_name,
          batch_status: profileView.batch_status || 'active',
          status: profileView.status || 'active',
          completed_on: profileView.completed_on || null,
          access_until: profileView.access_until || null,
          skill_course_id: skillEnrollment?.courseId,
          skill_course_name: skillEnrollment?.courseName,
          skill_batch_id: skillEnrollment?.batchId,
          skill_batch_name: skillEnrollment?.batchName,
          current_semester: activeSemester,
          current_year: activeYear,
          course_structure: primaryEnrollment?.courseStructure || 'semester',
          attendance_basis: primaryEnrollment?.attendanceBasis || 'semester',
          duration_years: primaryEnrollment?.durationYears || 2,
        };

        return { profile, enrollments };
      }
    } catch (_) {}

    // Synced account fallback for offline or local dev testing
    try {
      const stored = localStorage.getItem('mips_portal_user');
      let u: any = null;
      if (stored) u = JSON.parse(stored);
      const cleanId = (u?.email || u?.identifier || u?.id || '').split('@')[0].replace('s_', '').toLowerCase();
      const sync = accountSyncService.getAccount(cleanId);
      if (sync) {
        return {
          profile: {
            id: sync.id || 1,
            admission_number: sync.identifier?.toUpperCase() || 'ADM-2026-0001',
            registration_number: sync.registrationNumber || sync.identifier?.toUpperCase() || null,
            name: sync.name || 'Student Member',
            dob: sync.dob || null,
            phone: sync.phone || '',
            gender: sync.gender || 'Not Specified',
            course_id: sync.courseId || 1,
            batch_id: sync.batchId || 1,
            course_name: sync.courseName || 'Paramedical Sciences',
            batch_name: sync.batchName || 'Batch A',
            batch_status: 'active',
            status: sync.status || 'active',
            completed_on: null,
            access_until: null,
            current_semester: 1,
            current_year: 1,
          },
          enrollments: [],
        };
      }
    } catch (_) {}

    let userIdentifier = 'Student Member';
    try {
      const stored = localStorage.getItem('mips_portal_user');
      if (stored) {
        const u = JSON.parse(stored);
        userIdentifier = (u?.email || u?.identifier || u?.id || '').split('@')[0].replace('s_', '').toUpperCase() || 'Student Member';
      }
    } catch (_) {}

    const cleanProfile: StudentProfile = {
      id: 0,
      admission_number: userIdentifier,
      registration_number: null,
      name: userIdentifier,
      dob: null,
      phone: '',
      gender: 'Not Specified',
      course_id: 0,
      batch_id: 0,
      course_name: '',
      batch_name: '',
      batch_status: 'active',
      status: 'active',
      completed_on: null,
      access_until: null,
      current_semester: 1,
      current_year: 1,
    };

    return { profile: cleanProfile, enrollments: [] };
  },

  // 2. Examination Results
  async getStudentResults(studentId: number): Promise<ExamResultRecord[]> {
    try {
      // Read student results for published exams
      const { data: results, error: resultsError } = await supabase
        .from('results')
        .select(`
          id,
          exam_id,
          student_id,
          total_marks,
          percentage,
          grade,
          status,
          period_type,
          period_no,
          exams (
            id,
            name,
            course_id,
            batch_id,
            status,
            period_type,
            period_no,
            semester,
            published_at,
            created_at,
            courses ( id, name, course_type, structure ),
            batches ( id, batch_name )
          )
        `)
        .eq('student_id', studentId)
        .is('deleted_at', null)
        .order('id', { ascending: false });

      if (!resultsError && results && results.length > 0) {
        // Filter to published exams only
        const publishedResults = results.filter((r: any) => r.exams && r.exams.status === 'published');
        if (publishedResults.length > 0) {
          const examIds = publishedResults.map((r: any) => r.exam_id);

          // Fetch marks breakdown for these exams
          const { data: marks } = await supabase
            .from('marks')
            .select(`
              id,
              exam_id,
              subject_id,
              marks_obtained,
              is_absent,
              exam_subjects ( id, name, code, max_marks, pass_marks )
            `)
            .eq('student_id', studentId)
            .in('exam_id', examIds)
            .is('deleted_at', null);

          const examResults: ExamResultRecord[] = publishedResults.map((r: any) => {
            const examMarks = (marks || []).filter((m: any) => m.exam_id === r.exam_id);
            let maxMarks = 0;

            const subjectBreakdown = examMarks.map((m: any) => {
              const subMax = Number(m.exam_subjects?.max_marks || 100);
              const subPass = Number(m.exam_subjects?.pass_marks || 40);
              const obtained = m.is_absent ? 0 : Number(m.marks_obtained || 0);
              maxMarks += subMax;

              return {
                subjectId: m.subject_id,
                subjectName: m.exam_subjects?.name || 'Subject',
                subjectCode: m.exam_subjects?.code || '',
                obtainedMarks: obtained,
                maxMarks: subMax,
                passMarks: subPass,
                isPass: !m.is_absent && obtained >= subPass,
                isAbsent: Boolean(m.is_absent),
              };
            });

            const examCode = `EX-${r.exam_id}`;
            const resultCode = `${examCode}-S${studentId}`;
            const courseStructure = (r.exams?.courses?.structure || 'semester') as 'semester' | 'year' | 'single';
            const periodType = (r.period_type || r.exams?.period_type || (courseStructure === 'year' ? 'year' : 'semester')) as 'semester' | 'year' | 'single';
            const periodNo = r.period_no ?? r.exams?.period_no ?? 1;
            const periodDisplay = periodType === 'year' ? `Year ${periodNo}` : `Semester ${periodNo}`;

            return {
              id: r.id,
              examId: r.exam_id,
              examName: r.exams?.name || (periodType === 'year' ? `Year ${periodNo} Examination` : `Semester ${periodNo} Examination`),
              examCode,
              courseId: r.exams?.course_id || 0,
              courseName: r.exams?.courses?.name || 'Course',
              courseType: (r.exams?.courses?.course_type || 'primary') as 'primary' | 'skill',
              courseStructure,
              periodType,
              periodNo,
              periodDisplay,
              batchName: r.exams?.batches?.batch_name || 'Batch',
              publishedAt: r.exams?.published_at || r.exams?.created_at || new Date().toISOString(),
              totalMarks: Number(r.total_marks || 0),
              maxMarks: maxMarks > 0 ? maxMarks : 100,
              percentage: Number(r.percentage || 0),
              grade: r.grade || 'P',
              status: (r.status || 'PASS') as 'PASS' | 'FAIL' | 'WITHHELD',
              resultCode,
              subjects: subjectBreakdown,
            };
          });

          return examResults;
        }
      }
    } catch (_) {}

    return [];
  },

  // 3. Fees Ledger & Receipts
  async getStudentFees(studentId: number): Promise<StudentFeeLedger> {
    try {
      // O3 Optimization: Consolidated RPC returns summary + items + payments in 1 query
      const { data: rpcData, error: rpcErr } = await supabase.rpc('get_student_fee_summary', {
        p_student_id: studentId,
      });

      if (!rpcErr && rpcData) {
        const todayStr = new Date().toISOString().split('T')[0];
        const rawItems = rpcData.items || [];
        const items = rawItems.map((fi: any) => {
          const amount = Number(fi.amount_paise || 0);
          const paid = Number(fi.paid_amount_paise || 0);
          const pending = Number(fi.pending_amount_paise != null ? fi.pending_amount_paise : Math.max(0, amount - paid));
          let status: 'Paid' | 'Due' | 'Overdue' = 'Due';
          if (pending === 0) {
            status = 'Paid';
          } else if (fi.due_date && fi.due_date < todayStr) {
            status = 'Overdue';
          }

          return {
            id: fi.id,
            title: fi.label || fi.title || 'Tuition Fee Installment',
            kind: fi.kind || 'tuition',
            courseName: fi.course_name,
            amountPaise: amount,
            paidAmountPaise: paid,
            pendingAmountPaise: pending,
            dueDate: fi.due_date,
            status,
          };
        });

        const rawPayments = rpcData.payments || [];
        const payments = rawPayments.map((p: any) => ({
          id: p.id,
          receiptNumber: p.receipt_number || `REC-${String(p.id).padStart(4, '0')}`,
          date: p.payment_date,
          amountPaise: Number(p.amount_paise || 0),
          paymentMode: p.payment_mode || 'Cash',
          referenceNumber: p.reference_number || null,
        }));

        const total = Number(rpcData.total_fee_paise || 0);
        const paid = Number(rpcData.paid_amount_paise || 0);
        const pending = Number(rpcData.pending_amount_paise != null ? rpcData.pending_amount_paise : Math.max(0, total - paid));

        return {
          summary: {
            totalFeePaise: total,
            paidAmountPaise: paid,
            pendingAmountPaise: pending,
            primaryFeePaise: total,
            primaryPaidPaise: paid,
            primaryPendingPaise: pending,
            skillFeePaise: 0,
            skillPaidPaise: 0,
            skillPendingPaise: 0,
          },
          items,
          payments,
          lastUpdated: rpcData.last_updated || new Date().toISOString(),
        };
      }

      // Fallback: direct table queries
      // 3.1. Financial Summary
      const { data: summaryData } = await supabase
        .from('view_student_fee_summary')
        .select('*')
        .eq('student_id', studentId)
        .maybeSingle();

      const summary = {
        totalFeePaise: Number(summaryData?.total_fee_paise || 0),
        paidAmountPaise: Number(summaryData?.paid_amount_paise || 0),
        pendingAmountPaise: Number(summaryData?.pending_amount_paise || 0),
        primaryFeePaise: Number(summaryData?.primary_fee_paise || 0),
        primaryPaidPaise: Number(summaryData?.primary_paid_paise || 0),
        primaryPendingPaise: Number(summaryData?.primary_pending_paise || 0),
        skillFeePaise: Number(summaryData?.skill_fee_paise || 0),
        skillPaidPaise: Number(summaryData?.skill_paid_paise || 0),
        skillPendingPaise: Number(summaryData?.skill_pending_paise || 0),
      };

      // 3.2. Fee Items (Installments)
      const { data: feeItemsData, error: itemsError } = await supabase
        .from('fee_items')
        .select(`
          id,
          title,
          kind,
          amount_paise,
          paid_amount_paise,
          due_date,
          student_enrollments (
            kind,
            courses ( name )
          )
        `)
        .eq('student_id', studentId)
        .is('deleted_at', null)
        .order('due_date', { ascending: true });

      if (itemsError) throw itemsError;

      const todayStr = new Date().toISOString().split('T')[0];

      const items = (feeItemsData || []).map((fi: any) => {
        const pending = Math.max(0, Number(fi.amount_paise || 0) - Number(fi.paid_amount_paise || 0));
        let status: 'Paid' | 'Due' | 'Overdue' = 'Due';
        if (pending === 0) {
          status = 'Paid';
        } else if (fi.due_date && fi.due_date < todayStr) {
          status = 'Overdue';
        }

        return {
          id: fi.id,
          title: fi.title || 'Tuition Fee Installment',
          kind: fi.kind || 'tuition',
          courseName: fi.student_enrollments?.courses?.name,
          amountPaise: Number(fi.amount_paise || 0),
          paidAmountPaise: Number(fi.paid_amount_paise || 0),
          pendingAmountPaise: pending,
          dueDate: fi.due_date,
          status,
        };
      });

      // 3.3. Payment History (student_payments_view strictly excludes administrative remarks)
      const { data: paymentsData, error: paymentsError } = await supabase
        .from('student_payments_view')
        .select(`
          id,
          receipt_number,
          date,
          amount_paise,
          payment_mode,
          reference_number
        `)
        .eq('student_id', studentId)
        .order('date', { ascending: false });

      if (paymentsError) throw paymentsError;

      const payments = (paymentsData || []).map((p: any) => ({
        id: p.id,
        receiptNumber: p.receipt_number || `REC-${p.id}`,
        date: p.date,
        amountPaise: Number(p.amount_paise || 0),
        paymentMode: p.payment_mode || 'Cash',
        referenceNumber: p.reference_number,
      }));

      if (items.length > 0 || payments.length > 0) {
        return {
          summary,
          items,
          payments,
          lastUpdated: new Date().toISOString(),
        };
      }
    } catch (_) {}

    return {
      summary: {
        totalFeePaise: 0,
        paidAmountPaise: 0,
        pendingAmountPaise: 0,
        primaryFeePaise: 0,
        primaryPaidPaise: 0,
        primaryPendingPaise: 0,
        skillFeePaise: 0,
        skillPaidPaise: 0,
        skillPendingPaise: 0,
      },
      items: [],
      payments: [],
      lastUpdated: new Date().toISOString(),
    };
  },

  // 4. Attendance Summary & Calendar Sessions (Semester-wise or Year-wise)
  async getStudentAttendance(
    studentId: number,
    enrollmentId?: number,
    semesterNo?: number
  ): Promise<{
    summary: AttendanceSummary;
    calendar: CalendarSessionDay[];
    morningStats: { held: number; present: number; percentage: number };
    eveningStats: { held: number; present: number; percentage: number };
    semesters: SemesterSummary[];
    currentSemester: number;
  }> {
    try {
      // Check if course has year structure or year attendance basis
      let isYearBasis = false;
      let batchId: number | null = null;
      if (enrollmentId) {
        const { data: enr } = await supabase
          .from('student_enrollments')
          .select('batch_id, courses ( structure, attendance_basis )')
          .eq('id', enrollmentId)
          .maybeSingle();
        batchId = enr?.batch_id || null;
        const c: any = enr?.courses;
        if (c?.attendance_basis === 'year' || c?.structure === 'year') {
          isYearBasis = true;
        }
      } else {
        const { data: stu } = await supabase
          .from('students')
          .select('batch_id, courses ( structure, attendance_basis )')
          .eq('id', studentId)
          .maybeSingle();
        batchId = stu?.batch_id || null;
        const c: any = stu?.courses;
        if (c?.attendance_basis === 'year' || c?.structure === 'year') {
          isYearBasis = true;
        }
      }

      // 4.1. Semesters Summary RPC (lists all semesters/periods for this student)
      let semesters: SemesterSummary[] = [];
      const { data: semRows } = await supabase.rpc('student_semesters_summary', {
        p_student_id: studentId,
        p_enrollment_id: enrollmentId || null,
      });

      if (semRows && semRows.length > 0) {
        semesters = semRows.map((s: any) => ({
          semester_no: Number(s.semester_no),
          academic_year: Number(s.year_no || s.academic_year || Math.ceil(Number(s.semester_no) / 2)),
          period_type: isYearBasis ? 'year' : 'semester',
          period_no: Number(s.semester_no),
          start_date: s.start_date,
          end_date: s.end_date || null,
          is_current: Boolean(s.is_current),
          sessions_held: Number(s.sessions_held || 0),
          present: Number(s.present || s.present_count || 0),
          late: Number(s.late || s.late_count || 0),
          absent: Number(s.absent || s.absent_count || 0),
          leave: Number(s.leave || s.leave_count || 0),
          percentage: Number(s.percentage || 0),
          met_minimum: Boolean(s.met_minimum),
          semester_status: s.semester_status || s.status || 'active',
        }));
      }

      // If year-basis course returned empty from legacy student_semesters_summary, fetch from batch_periods
      if (semesters.length === 0 && batchId) {
        const { data: periods } = await supabase
          .from('batch_periods')
          .select('*')
          .eq('batch_id', batchId)
          .eq('period_type', isYearBasis ? 'year' : 'semester')
          .order('period_no', { ascending: true });

        if (periods && periods.length > 0) {
          semesters = periods.map((p: any) => ({
            semester_no: Number(p.period_no),
            academic_year: isYearBasis ? Number(p.period_no) : Math.ceil(Number(p.period_no) / 2),
            period_type: p.period_type,
            period_no: Number(p.period_no),
            start_date: p.start_date,
            end_date: p.end_date || null,
            is_current: p.status === 'active',
            sessions_held: 0,
            present: 0,
            late: 0,
            absent: 0,
            leave: 0,
            percentage: 100,
            met_minimum: true,
            semester_status: p.status || 'active',
          }));
        }
      }

      const currentSemObj = semesters.find((s) => s.is_current);
      const activeCurrentSemester = currentSemObj?.semester_no || (semesters.length > 0 ? semesters[semesters.length - 1].semester_no : 1);
      const requestedSemesterNo = semesterNo || activeCurrentSemester;

      // 4.2. Attendance Summary RPC for the requested semester/period
      const { data: summaryRows, error: summaryError } = await supabase.rpc(
        'student_attendance_summary',
        {
          p_student_id: studentId,
          p_enrollment_id: enrollmentId || null,
          p_semester_no: requestedSemesterNo,
        }
      );

      if (summaryError) throw summaryError;
      const raw = (summaryRows && summaryRows.length > 0) ? summaryRows[0] : null;

      // 4.3. Query Individual Attendance Sessions & Marked Records for Calendar
      let query = supabase
        .from('attendance_records')
        .select(`
          status,
          attendance_sessions!inner (
            id,
            date,
            slot,
            status,
            batch_id,
            semester_no,
            period_type,
            period_no
          )
        `)
        .eq('student_id', studentId);

      if (requestedSemesterNo) {
        if (isYearBasis) {
          query = query.or(`period_no.eq.${requestedSemesterNo},semester_no.eq.${requestedSemesterNo * 2}`);
        } else {
          query = query.or(`period_no.eq.${requestedSemesterNo},semester_no.eq.${requestedSemesterNo}`);
        }
      }

      const { data: recordsData } = await query;

      const calendar: CalendarSessionDay[] = [];
      let mHeld = 0;
      let mPres = 0;
      let eHeld = 0;
      let ePres = 0;

      (recordsData || []).forEach((r: any) => {
        const s = r.attendance_sessions;
        if (!s) return;
        const slot = s.slot === 'evening' ? 'evening' : 'morning';
        const isNoClass = s.status === 'no_class';

        let recStatus: 'present' | 'absent' | 'late' | 'leave' | 'no_class' = 'present';
        if (isNoClass) {
          recStatus = 'no_class';
        } else {
          recStatus = (r.status || 'present').toLowerCase() as any;
        }

        calendar.push({
          date: s.date,
          slot,
          status: recStatus,
        });

        // Split morning vs evening
        if (!isNoClass) {
          if (slot === 'morning') {
            mHeld++;
            if (recStatus === 'present' || recStatus === 'late') mPres++;
          } else {
            eHeld++;
            if (recStatus === 'present' || recStatus === 'late') ePres++;
          }
        }
      });

      const isCurrent = raw ? Boolean(raw.is_current) : (requestedSemesterNo === activeCurrentSemester);

      const summary: AttendanceSummary = {
        student_id: studentId,
        enrollment_id: enrollmentId || 0,
        course_name: '',
        batch_name: '',
        semester_no: requestedSemesterNo,
        met_minimum: raw ? Boolean(raw.met_minimum) : Number(raw?.percentage || 0) >= 75,
        is_current: isCurrent,
        sessions_held: Number(raw?.sessions_held || 0),
        present: Number(raw?.present_count || 0),
        late: Number(raw?.late_count || 0),
        absent: Number(raw?.absent_count || 0),
        leave: Number(raw?.leave_count || 0),
        weighted_present: Number(raw?.weighted_present || 0),
        percentage: Number(raw?.percentage || 100),
        status_band: (raw?.status_band || 'ok') as 'ok' | 'low' | 'shortage',
        can_miss_more: Number(raw?.can_miss_more || 0),
        recover_sessions: Number(raw?.recover_sessions || 0),
        morning_held: mHeld,
        morning_present: mPres,
        morning_percentage: mHeld > 0 ? Math.round((mPres / mHeld) * 100) : 100,
        evening_held: eHeld,
        evening_present: ePres,
        evening_percentage: eHeld > 0 ? Math.round((ePres / eHeld) * 100) : 100,
        deduction_absent_pts: Number(raw?.absent_impact_pct || 0),
        deduction_late_pts: Number(raw?.late_impact_pct || 0),
      };

      if (raw || calendar.length > 0 || semesters.length > 0) {
        return {
          summary,
          calendar,
          morningStats: {
            held: mHeld,
            present: mPres,
            percentage: summary.morning_percentage,
          },
          eveningStats: {
            held: eHeld,
            present: ePres,
            percentage: summary.evening_percentage,
          },
          semesters,
          currentSemester: activeCurrentSemester,
        };
      }
    } catch (_) {}

    return {
      summary: {
        student_id: studentId,
        enrollment_id: enrollmentId || 0,
        course_name: '',
        batch_name: '',
        semester_no: semesterNo || 1,
        met_minimum: true,
        is_current: true,
        sessions_held: 0,
        present: 0,
        late: 0,
        absent: 0,
        leave: 0,
        weighted_present: 0,
        percentage: 0,
        status_band: 'ok',
        can_miss_more: 0,
        recover_sessions: 0,
        morning_held: 0,
        morning_present: 0,
        morning_percentage: 0,
        evening_held: 0,
        evening_present: 0,
        evening_percentage: 0,
        deduction_absent_pts: 0,
        deduction_late_pts: 0,
      },
      calendar: [],
      morningStats: { held: 0, present: 0, percentage: 0 },
      eveningStats: { held: 0, present: 0, percentage: 0 },
      semesters: [],
      currentSemester: semesterNo || 1,
    };
  },

  // 5. Weekly Timetable
  async getStudentTimetable(batchIds: number[]): Promise<TimetableSchedule[]> {
    if (batchIds.length === 0) return [];

    try {
      const { data: timetables, error } = await supabase
        .from('timetables')
        .select(`
          id,
          batch_id,
          academic_year,
          effective_from,
          published_at,
          created_at,
          batches (
            id,
            batch_name,
            courses ( id, name, course_type )
          ),
          timetable_entries (
            id,
            weekday,
            slot,
            start_time,
            end_time,
            room,
            course_subjects ( id, subject_name, subject_code ),
            teachers ( id, name )
          )
        `)
        .in('batch_id', batchIds)
        .eq('status', 'published')
        .is('deleted_at', null);

      if (!error && timetables && timetables.length > 0) {
        return timetables.map((t: any) => ({
          timetableId: t.id,
          batchId: t.batch_id,
          batchName: t.batches?.batch_name || 'Batch',
          courseName: t.batches?.courses?.name || 'Course',
          courseType: (t.batches?.courses?.course_type || 'primary') as 'primary' | 'skill',
          academicYear: t.academic_year || 'Current Academic Year',
          effectiveFrom: t.effective_from || t.created_at,
          publishedAt: t.published_at || t.created_at,
          entries: (t.timetable_entries || []).map((e: any) => ({
            id: e.id,
            weekday: Number(e.weekday),
            slot: (e.slot || 'morning') as 'morning' | 'evening',
            startTime: e.start_time?.slice(0, 5) || '09:00',
            endTime: e.end_time?.slice(0, 5) || '10:00',
            subjectName: e.course_subjects?.subject_name || 'Subject',
            teacherName: e.teachers?.name || 'Faculty',
            room: e.room || 'Room 101',
          })),
        }));
      }
    } catch (_) {}

    return [];
  },

  // 6. Notifications
  async getNotifications(userId: string): Promise<NotificationItem[]> {
    try {
      const { data, error } = await supabase
        .from('notifications')
        .select('*')
        .eq('user_id', userId)
        .order('created_at', { ascending: false })
        .limit(50);

      if (!error && data && data.length > 0) {
        return data.map((n: any) => ({
          id: n.id,
          category: (n.category || 'general') as any,
          title: n.title,
          message: n.message,
          read_at: n.read_at,
          created_at: n.created_at,
          action_url: n.action_url,
        }));
      }
    } catch (_) {}

    return [];
  },

  async markNotificationRead(id: number): Promise<void> {
    try {
      await supabase
        .from('notifications')
        .update({ read_at: new Date().toISOString() })
        .eq('id', id);
    } catch (_) {}
  },

  async markAllNotificationsRead(userId: string): Promise<void> {
    try {
      await supabase
        .from('notifications')
        .update({ read_at: new Date().toISOString() })
        .eq('user_id', userId)
        .is('read_at', null);
    } catch (_) {}
  },

  // 7. Student Examination Timetable
  async getStudentExamTimetable(batchIds: number[]): Promise<StudentExamTimetableEntry[]> {
    try {
      const { data, error } = await supabase
        .from('exam_subjects')
        .select(`
          id,
          name,
          code,
          exam_date,
          start_time,
          end_time,
          room,
          instructions,
          exams!inner (
            id,
            name,
            batch_id,
            status,
            batches ( batch_name, courses ( name ) )
          )
        `)
        .in('exams.batch_id', batchIds.length > 0 ? batchIds : [1]);

      if (!error && data && data.length > 0) {
        return data.map((d: any) => ({
          id: d.id,
          examId: d.exams?.id,
          examName: d.exams?.name || 'Term Examination',
          batchId: d.exams?.batch_id,
          batchName: d.exams?.batches?.batch_name || 'Batch',
          courseName: d.exams?.batches?.courses?.name || 'Primary Course',
          subjectName: d.name,
          subjectCode: d.code,
          examDate: d.exam_date || '2026-11-02',
          startTime: d.start_time?.slice(0, 5) || '10:00',
          endTime: d.end_time?.slice(0, 5) || '13:00',
          room: d.room || 'Main Examination Hall A',
          instructions: d.instructions || 'Reporting time: 30 minutes before exam start. Hall ticket mandatory.',
        }));
      }
    } catch (_) {}

    return [];
  },
};

export interface StudentExamTimetableEntry {
  id: number;
  examId: number;
  examName: string;
  batchId: number;
  batchName: string;
  courseName: string;
  subjectName: string;
  subjectCode: string;
  examDate: string;
  startTime: string;
  endTime: string;
  room: string;
  instructions: string;
}

