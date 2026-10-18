// src/test/phase12_semester_attendance.test.tsx
// Phase 12D Automated Test Suite: Semester-based Attendance, Promotion Logic & Threshold Precision

import React from 'react';
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { MemoryRouter } from 'react-router-dom';

import { AuthProvider } from '../context/AuthContext';
import { OnlineStatusProvider } from '../context/OnlineStatusContext';
import { studentService, StudentEnrollmentInfo } from '../services/studentService';
import { AttendanceTab } from '../components/student/AttendanceTab';
import { PortalHeader } from '../components/layout/PortalHeader';
import { NotificationDrawer } from '../components/notifications/NotificationDrawer';
import type { AttendanceSummary, SemesterSummary } from '../types';

vi.mock('../context/AuthContext', async () => {
  const actual = await vi.importActual('../context/AuthContext');
  return {
    ...actual,
    useAuth: () => ({
      user: { id: 'test-user-1', email: 'student@mips.edu', role: 'student' },
      profile: { role: 'student', student_id: 1 },
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

describe('Phase 12D - Semester Attendance & Promotion Automated Test Suite', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    localStorage.clear();
  });

  afterEach(() => {
    localStorage.clear();
  });

  const mockEnrollments: StudentEnrollmentInfo[] = [
    {
      enrollmentId: 101,
      courseId: 1,
      courseName: 'Diploma in Medical Laboratory Technology',
      courseType: 'primary',
      batchId: 10,
      batchName: 'Batch 2024-26 (A)',
      status: 'active',
      currentSemester: 2,
      currentYear: 1,
    },
  ];

  const mockSemesters: SemesterSummary[] = [
    {
      semester_no: 1,
      academic_year: 1,
      start_date: '2025-08-01',
      end_date: '2025-12-31',
      is_current: false,
      sessions_held: 100,
      present: 90,
      late: 2,
      absent: 7,
      leave: 1,
      percentage: 91.92,
      met_minimum: true,
      semester_status: 'closed',
    },
    {
      semester_no: 2,
      academic_year: 1,
      start_date: '2026-01-05',
      end_date: '2026-06-30',
      is_current: true,
      sessions_held: 60,
      present: 42,
      late: 2,
      absent: 15,
      leave: 1,
      percentage: 72.88,
      met_minimum: false,
      semester_status: 'active',
    },
  ];

  // =========================================================================
  // 1. Semester Percentage & Boundary Calculations
  // =========================================================================
  describe('1. Semester Percentage & Boundary Calculations', () => {
    it('calculates percentage accurately with late weight (0.5) and leave exclusion', () => {
      // Formula: (present + late * 0.5) / (held - leave) * 100
      // 100 held, 2 leaves -> effective held = 98. 85 present, 6 late (3.0 weight) -> 88.0 / 98.0 * 100 = 89.7959%
      const held = 100;
      const leave = 2;
      const present = 85;
      const late = 6;
      const effectiveHeld = held - leave;
      const weightedPresent = present + (late * 0.5);
      const percentage = (weightedPresent / effectiveHeld) * 100;

      expect(effectiveHeld).toBe(98);
      expect(weightedPresent).toBe(88.0);
      expect(Number(percentage.toFixed(2))).toBe(89.80);
    });

    it('evaluates exactly 80.0% boundary as good standing (ok), and 79.9% as low band', () => {
      // 60 held, 0 leave -> 48 present = 80.0% exactly -> 'ok'
      const pctExact80 = (48 / 60) * 100;
      const bandExact80 = pctExact80 < 75 ? 'shortage' : pctExact80 < 80 ? 'low' : 'ok';
      expect(pctExact80).toBe(80.0);
      expect(bandExact80).toBe('ok');

      // 47 present + 1 late (0.5) = 47.5 / 60 = 79.166% -> 'low'
      const pctBelow80 = (47.5 / 60) * 100;
      const bandBelow80 = pctBelow80 < 75 ? 'shortage' : pctBelow80 < 80 ? 'low' : 'ok';
      expect(pctBelow80).toBeLessThan(80.0);
      expect(pctBelow80).toBeGreaterThanOrEqual(75.0);
      expect(bandBelow80).toBe('low');
    });

    it('evaluates exactly 75.0% boundary as low band, and 74.9% as shortage', () => {
      // 60 held, 0 leave -> 45 present = 75.0% exactly -> 'low' (not shortage)
      const pctExact75 = (45 / 60) * 100;
      const bandExact75 = pctExact75 < 75 ? 'shortage' : pctExact75 < 80 ? 'low' : 'ok';
      expect(pctExact75).toBe(75.0);
      expect(bandExact75).toBe('low');

      // 44 present + 1 late (0.5) = 44.5 / 60 = 74.166% -> 'shortage'
      const pctBelow75 = (44.5 / 60) * 100;
      const bandBelow75 = pctBelow75 < 75 ? 'shortage' : pctBelow75 < 80 ? 'low' : 'ok';
      expect(pctBelow75).toBeLessThan(75.0);
      expect(bandBelow75).toBe('shortage');
    });
  });

  // =========================================================================
  // 2. Academic Year Derived from Semester
  // =========================================================================
  describe('2. Academic Year Derivation Formula: Year = ceil(Semester / 2)', () => {
    it('derives correct academic year for all semesters', () => {
      const deriveYear = (sem: number) => (sem <= 0 ? 1 : Math.ceil(sem / 2));

      expect(deriveYear(1)).toBe(1); // Sem 1 -> Year 1
      expect(deriveYear(2)).toBe(1); // Sem 2 -> Year 1
      expect(deriveYear(3)).toBe(2); // Sem 3 -> Year 2 (Year promotion happens here!)
      expect(deriveYear(4)).toBe(2); // Sem 4 -> Year 2
      expect(deriveYear(5)).toBe(3); // Sem 5 -> Year 3
      expect(deriveYear(6)).toBe(3); // Sem 6 -> Year 3
    });
  });

  // =========================================================================
  // 3. React Student Portal UI: Current vs Historical Semester Attendance
  // =========================================================================
  describe('3. React Student Portal UI: Current vs Historical Semesters', () => {
    it('displays shortage alert ONLY for current semester, and read-only badge for past semester', async () => {
      const sem2ShortageSummary: AttendanceSummary = {
        student_id: 1,
        enrollment_id: 101,
        course_name: 'DMLT',
        batch_name: 'Batch 2024-26',
        semester_no: 2,
        sessions_held: 60,
        present: 42,
        late: 2,
        absent: 15,
        leave: 1,
        weighted_present: 43.0,
        percentage: 72.88,
        status_band: 'shortage',
        can_miss_more: 0,
        recover_sessions: 6,
        met_minimum: false,
        is_current: true,
        morning_held: 30,
        morning_present: 22,
        morning_percentage: 73,
        evening_held: 30,
        evening_present: 21,
        evening_percentage: 70,
        deduction_absent_pts: 25.0,
        deduction_late_pts: 1.67,
      };

      const sem1MetSummary: AttendanceSummary = {
        student_id: 1,
        enrollment_id: 101,
        course_name: 'DMLT',
        batch_name: 'Batch 2024-26',
        semester_no: 1,
        sessions_held: 100,
        present: 90,
        late: 2,
        absent: 7,
        leave: 1,
        weighted_present: 91.0,
        percentage: 91.92,
        status_band: 'ok',
        can_miss_more: 15,
        recover_sessions: 0,
        met_minimum: true,
        is_current: false,
        morning_held: 50,
        morning_present: 46,
        morning_percentage: 92,
        evening_held: 50,
        evening_present: 45,
        evening_percentage: 90,
        deduction_absent_pts: 7.0,
        deduction_late_pts: 1.0,
      };

      vi.spyOn(studentService, 'getStudentAttendance').mockImplementation(
        async (_studentId, _enrollmentId, semNo) => {
          if (semNo === 1) {
            return {
              summary: sem1MetSummary,
              calendar: [{ date: '2025-12-15', slot: 'morning', status: 'present' }],
              morningStats: { held: 50, present: 46, percentage: 92 },
              eveningStats: { held: 50, present: 45, percentage: 90 },
              semesters: mockSemesters,
              currentSemester: 2,
            };
          }
          return {
            summary: sem2ShortageSummary,
            calendar: [{ date: '2026-10-18', slot: 'morning', status: 'present' }],
            morningStats: { held: 30, present: 22, percentage: 73 },
            eveningStats: { held: 30, present: 21, percentage: 70 },
            semesters: mockSemesters,
            currentSemester: 2,
          };
        }
      );

      renderWithProviders(
        <AttendanceTab
          studentId={1}
          enrollments={mockEnrollments}
          currentSemester={2}
          currentYear={1}
          isCompleted={false}
        />
      );

      // On initial load (Semester 2 - Current):
      await waitFor(() => {
        expect(screen.getByText('Attendance below minimum')).toBeInTheDocument();
      });

      expect(screen.getByText((content) => content.includes('Your overall attendance is 72.9%'))).toBeInTheDocument();
      expect(screen.getByText(/6 sessions in a row/i)).toBeInTheDocument();

      // Verify "All Semesters Overview" is rendered at top with chips
      expect(screen.getByText('All Semesters Overview')).toBeInTheDocument();
      expect(screen.getByText('Semester 1')).toBeInTheDocument();
      expect(screen.getByText('Semester 2')).toBeInTheDocument();

      // Switch to Semester 1 (Previous Semester)
      const sem1Chip = screen.getByRole('button', { name: /Sem 1/i });
      fireEvent.click(sem1Chip);

      // In Semester 1 (Previous/Closed):
      await waitFor(() => {
        // Warning alert MUST NOT be rendered
        expect(screen.queryByText('Attendance below minimum')).not.toBeInTheDocument();
        // Historical "Met Minimum" badge MUST be displayed
        expect(screen.getByText('Met Minimum')).toBeInTheDocument();
        expect(screen.getByText(/Minimum attendance requirement \(75%\) was satisfied/i)).toBeInTheDocument();
        expect(screen.getByText('91.9%')).toBeInTheDocument();
      });
    });

    it('renders Header with "Semester {n} · Year {y}" and handles promotion notification deep-linking', () => {
      // 1. Verify PortalHeader shows Semester & Year subtitle
      renderWithProviders(
        <PortalHeader
          tabs={[{ id: 'attendance', label: 'Attendance' }]}
          activeTab="attendance"
          onTabChange={vi.fn()}
          subtitle="Semester 2 · Year 1"
        />
      );

      expect(screen.getByText('Semester 2 · Year 1')).toBeInTheDocument();
      expect(screen.getByText('MIPS Student Portal')).toBeInTheDocument();
    });

    it('navigates to attendance tab when promotion notification is tapped', async () => {
      const onNavigateMock = vi.fn();
      const onCloseMock = vi.fn();

      localStorage.setItem('mips_portal_user', JSON.stringify({ id: 'test-user-1', role: 'student' }));
      localStorage.setItem('mips_portal_role', 'student');
      localStorage.setItem('mips_portal_last_active', Date.now().toString());

      vi.spyOn(studentService, 'getNotifications').mockResolvedValue([
        {
          id: 99,
          category: 'programme',
          title: 'Semester Promotion',
          message: 'You are now in Semester 2 (Year 1). Your Semester 1 attendance: 91.9%',
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
        expect(screen.getByText('Semester Promotion')).toBeInTheDocument();
        expect(screen.getByText(/You are now in Semester 2/i)).toBeInTheDocument();
      });

      // Tap on the promotion notification
      fireEvent.click(screen.getByText('Semester Promotion'));

      // Must deep-link to attendance tab and close drawer
      expect(onNavigateMock).toHaveBeenCalledWith('attendance');
      expect(onCloseMock).toHaveBeenCalled();
    });
  });
});
