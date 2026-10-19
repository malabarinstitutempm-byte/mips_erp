// src/test/phase14c_year_wise_student_portal.test.tsx
// Phase 14C Automated Test Suite: Year-wise Courses in React Student Portal

import React from 'react';
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { MemoryRouter } from 'react-router-dom';

import { AuthProvider } from '../context/AuthContext';
import { OnlineStatusProvider } from '../context/OnlineStatusContext';
import { studentService, StudentEnrollmentInfo, ExamResultRecord } from '../services/studentService';
import { ResultsTab } from '../components/student/ResultsTab';
import { AttendanceTab } from '../components/student/AttendanceTab';
import { PortalHeader } from '../components/layout/PortalHeader';
import { NotificationDrawer } from '../components/notifications/NotificationDrawer';
import * as pdfExporter from '../lib/pdfExporter';
import type { AttendanceSummary, SemesterSummary } from '../types';

vi.mock('../context/AuthContext', async () => {
  const actual = await vi.importActual('../context/AuthContext');
  return {
    ...actual,
    useAuth: () => ({
      user: { id: 'test-user-year-1', email: 'yearstudent@mips.edu', role: 'student' },
      profile: { role: 'student', student_id: 10 },
      unreadCount: 1,
      refreshNotifications: vi.fn(),
      logout: vi.fn(),
    }),
  };
});

function createTestQueryClient() {
  return new QueryClient({
    defaultOptions: {
      queries: {
        retry: false,
        staleTime: Infinity,
      },
    },
  });
}

function renderWithProviders(ui: React.ReactElement, { route = '/' } = {}) {
  const queryClient = createTestQueryClient();
  return render(
    <QueryClientProvider client={queryClient}>
      <OnlineStatusProvider>
        <MemoryRouter initialEntries={[route]}>
          <AuthProvider>{ui}</AuthProvider>
        </MemoryRouter>
      </OnlineStatusProvider>
    </QueryClientProvider>
  );
}

describe('Phase 14C - Year-wise Courses in React Student Portal', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    localStorage.clear();
  });

  afterEach(() => {
    localStorage.clear();
  });

  const mockYearWiseEnrollments: StudentEnrollmentInfo[] = [
    {
      enrollmentId: 201,
      courseId: 5,
      courseName: 'Bachelor in Medical Imaging Technology [BMIT]',
      courseType: 'primary',
      courseStructure: 'year',
      attendanceBasis: 'year',
      durationYears: 3,
      batchId: 20,
      batchName: 'Batch 2024-27 (Year-wise)',
      status: 'active',
      currentSemester: 2,
      currentYear: 1,
    },
  ];

  const mockYearResult: ExamResultRecord = {
    id: 501,
    examId: 101,
    examName: 'Year 1 Annual Examination - 2026',
    examCode: 'BMIT-Y1-2026',
    courseId: 5,
    courseName: 'Bachelor in Medical Imaging Technology',
    courseType: 'primary',
    courseStructure: 'year',
    periodType: 'year',
    periodNo: 1,
    periodDisplay: 'Year 1',
    batchName: 'Batch 2024-27 (Year-wise)',
    publishedAt: '2026-05-15T10:00:00Z',
    totalMarks: 375,
    maxMarks: 500,
    percentage: 75.0,
    grade: 'A',
    status: 'PASS',
    resultCode: 'BMIT-Y1-2026-S10',
    subjects: [
      {
        subjectId: 1,
        subjectName: 'Human Anatomy & Physiology',
        subjectCode: 'BMIT-101',
        obtainedMarks: 75,
        maxMarks: 100,
        passMarks: 40,
        isPass: true,
        isAbsent: false,
      },
      {
        subjectId: 2,
        subjectName: 'Radiation Physics & Protection',
        subjectCode: 'BMIT-102',
        obtainedMarks: 80,
        maxMarks: 100,
        passMarks: 40,
        isPass: true,
        isAbsent: false,
      },
      {
        subjectId: 3,
        subjectName: 'Radiographic Photography & Film Processing',
        subjectCode: 'BMIT-103',
        obtainedMarks: 70,
        maxMarks: 100,
        passMarks: 40,
        isPass: true,
        isAbsent: false,
      },
      {
        subjectId: 4,
        subjectName: 'Basic Principles of Radiography',
        subjectCode: 'BMIT-104',
        obtainedMarks: 78,
        maxMarks: 100,
        passMarks: 40,
        isPass: true,
        isAbsent: false,
      },
      {
        subjectId: 5,
        subjectName: 'Practical & Viva Radiography - Year 1',
        subjectCode: 'BMIT-105',
        obtainedMarks: 72,
        maxMarks: 100,
        passMarks: 40,
        isPass: true,
        isAbsent: false,
      },
    ],
  };

  const mockYearSemesters: SemesterSummary[] = [
    {
      semester_no: 1,
      academic_year: 1,
      period_type: 'year',
      period_no: 1,
      start_date: '2025-08-01',
      end_date: null,
      is_current: true,
      sessions_held: 220,
      present: 190,
      late: 10,
      absent: 18,
      leave: 2,
      percentage: 89.45,
      met_minimum: true,
      semester_status: 'active',
    },
  ];

  const mockYearAttendanceSummary: AttendanceSummary = {
    student_id: 10,
    enrollment_id: 201,
    course_name: 'Bachelor in Medical Imaging Technology',
    batch_name: 'Batch 2024-27 (Year-wise)',
    semester_no: 1,
    sessions_held: 220,
    present: 190,
    late: 10,
    absent: 18,
    leave: 2,
    weighted_present: 195.0,
    percentage: 89.45,
    status_band: 'ok',
    can_miss_more: 31,
    recover_sessions: 0,
    met_minimum: true,
    is_current: true,
    morning_held: 110,
    morning_present: 98,
    morning_percentage: 89,
    evening_held: 110,
    evening_present: 97,
    evening_percentage: 88,
    deduction_absent_pts: 8.26,
    deduction_late_pts: 2.29,
  };

  // =========================================================================
  // 1. Results Tab for Year-wise Courses
  // =========================================================================
  describe('1. Results Tab for Year-wise Courses', () => {
    it('displays "Year 1" badges, all 5 subjects in one sheet, and exports PDF with "Year_1"', async () => {
      const mockExportPdf = vi.spyOn(pdfExporter, 'exportElementToPdf').mockResolvedValue();
      vi.spyOn(studentService, 'getStudentResults').mockResolvedValue([mockYearResult]);

      renderWithProviders(
        <ResultsTab
          studentId={10}
          studentName="Ibrahim Kutty"
          registrationNumber="2024BMIT010"
          admissionNumber="ADM-2024-0010"
        />
      );

      await waitFor(() => {
        expect(screen.getByText('Year 1 Annual Examination - 2026')).toBeInTheDocument();
        expect(screen.getAllByText(/Year 1/i).length).toBeGreaterThan(0);
        expect(screen.getByText('Human Anatomy & Physiology')).toBeInTheDocument();
        expect(screen.getByText('Radiation Physics & Protection')).toBeInTheDocument();
        expect(screen.getByText('Radiographic Photography & Film Processing')).toBeInTheDocument();
        expect(screen.getByText('Basic Principles of Radiography')).toBeInTheDocument();
        expect(screen.getByText('Practical & Viva Radiography - Year 1')).toBeInTheDocument();
      });

      // Check PDF Export button triggers filename with "Year_1"
      const downloadBtn = screen.getByRole('button', { name: /download pdf/i });
      fireEvent.click(downloadBtn);

      await waitFor(() => {
        expect(mockExportPdf).toHaveBeenCalled();
        const callArgs = mockExportPdf.mock.calls[0];
        expect(callArgs[1]).toContain('MIPS_Result_Year_1');
      });
    });
  });

  // =========================================================================
  // 2. Attendance Tab for Year-wise Courses
  // =========================================================================
  describe('2. Attendance Tab for Year-wise Courses', () => {
    it('labels selectors as "Year:", shows "All Academic Years Overview", and references Year in headings', async () => {
      vi.spyOn(studentService, 'getStudentAttendance').mockResolvedValue({
        summary: mockYearAttendanceSummary,
        calendar: [
          { date: '2026-03-10', slot: 'morning', status: 'present' },
          { date: '2026-03-10', slot: 'evening', status: 'present' },
        ],
        morningStats: { held: 110, present: 98, percentage: 89 },
        eveningStats: { held: 110, present: 97, percentage: 88 },
        semesters: mockYearSemesters,
        currentSemester: 1,
      });

      renderWithProviders(
        <AttendanceTab
          studentId={10}
          enrollments={mockYearWiseEnrollments}
          currentSemester={2}
          currentYear={1}
        />
      );

      await waitFor(() => {
        // Section 1: All Academic Years Overview
        expect(screen.getByText('All Academic Years Overview')).toBeInTheDocument();
        // Section 2: Year Selector chip
        expect(screen.getByText('Year:')).toBeInTheDocument();
        expect(screen.getAllByRole('button', { name: /year 1/i }).length).toBeGreaterThanOrEqual(1);
        // Section 5: Overall Attendance
        expect(screen.getByText('Year 1 Overall Attendance')).toBeInTheDocument();
        // Section 6: Breakdown explanation
        expect(screen.getByText(/Each unexcused absence reduced your Year 1 percentage/i)).toBeInTheDocument();
      });
    });
  });

  // =========================================================================
  // 3. Portal Header & Notifications Deep-linking for Year-wise Courses
  // =========================================================================
  describe('3. Portal Header & Notifications Deep-linking', () => {
    it('renders PortalHeader with "Year 1" for year-wise course', () => {
      renderWithProviders(
        <PortalHeader
          tabs={[{ id: 'attendance', label: 'Attendance' }]}
          activeTab="attendance"
          onTabChange={vi.fn()}
          subtitle="Year 1"
        />
      );

      expect(screen.getByText('Year 1')).toBeInTheDocument();
      expect(screen.getByText('MIPS Student Portal')).toBeInTheDocument();
    });

    it('navigates to attendance tab when academic year promotion notification is tapped', async () => {
      const onNavigateMock = vi.fn();
      const onCloseMock = vi.fn();

      localStorage.setItem('mips_portal_user', JSON.stringify({ id: 'test-user-year-1', role: 'student' }));
      localStorage.setItem('mips_portal_role', 'student');
      localStorage.setItem('mips_portal_last_active', Date.now().toString());

      vi.spyOn(studentService, 'getNotifications').mockResolvedValue([
        {
          id: 102,
          category: 'programme',
          title: 'Academic Year Promotion',
          message: 'Congratulations! You have been promoted to Year 2 for BMIT.',
          read_at: null,
          created_at: new Date().toISOString(),
        },
      ]);
      vi.spyOn(studentService, 'markNotificationRead').mockResolvedValue(true);

      renderWithProviders(
        <NotificationDrawer
          isOpen={true}
          onClose={onCloseMock}
          onNavigateTab={onNavigateMock}
        />
      );

      await waitFor(() => {
        expect(screen.getByText('Academic Year Promotion')).toBeInTheDocument();
        expect(screen.getByText(/promoted to Year 2/i)).toBeInTheDocument();
      });

      // Tap on the academic year promotion notification
      fireEvent.click(screen.getByText('Academic Year Promotion'));

      // Must deep-link to attendance tab and close drawer
      expect(onNavigateMock).toHaveBeenCalledWith('attendance');
      expect(onCloseMock).toHaveBeenCalled();
    });

    it('navigates to results tab when year-wise exam result notification is tapped', async () => {
      const onNavigateMock = vi.fn();
      const onCloseMock = vi.fn();

      localStorage.setItem('mips_portal_user', JSON.stringify({ id: 'test-user-year-1', role: 'student' }));
      localStorage.setItem('mips_portal_role', 'student');
      localStorage.setItem('mips_portal_last_active', Date.now().toString());

      vi.spyOn(studentService, 'getNotifications').mockResolvedValue([
        {
          id: 103,
          category: 'exam',
          title: 'Year 1 Result Published',
          message: 'Year 1 results for BMIT Annual Exam are now published.',
          read_at: null,
          created_at: new Date().toISOString(),
        },
      ]);
      vi.spyOn(studentService, 'markNotificationRead').mockResolvedValue(true);

      renderWithProviders(
        <NotificationDrawer
          isOpen={true}
          onClose={onCloseMock}
          onNavigateTab={onNavigateMock}
        />
      );

      await waitFor(() => {
        expect(screen.getByText('Year 1 Result Published')).toBeInTheDocument();
      });

      // Tap on the year result notification
      fireEvent.click(screen.getByText('Year 1 Result Published'));

      // Must deep-link to results tab
      expect(onNavigateMock).toHaveBeenCalledWith('results');
      expect(onCloseMock).toHaveBeenCalled();
    });
  });
});
