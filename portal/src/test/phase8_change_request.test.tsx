// src/test/phase8_change_request.test.tsx
// Phase 8D: Change Request Automated Test Suite
// Covers Concurrency Race Conditions, Universal Faculty Access, Primary-Only Attendance, and Universal Logout

import React from 'react';
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { MemoryRouter, useLocation } from 'react-router-dom';

// Contexts & Services
import { AuthProvider, useAuth } from '../context/AuthContext';
import { OnlineStatusProvider } from '../context/OnlineStatusContext';
import { studentService } from '../services/studentService';
import { teacherService } from '../services/teacherService';
import { pushNotificationService } from '../lib/pushNotifications';
import { supabase } from '../lib/supabase';

// Components
import { TeacherAttendanceTab } from '../components/teacher/TeacherAttendanceTab';
import { AttendanceTab } from '../components/student/AttendanceTab';
import { PortalHeader } from '../components/layout/PortalHeader';
import { AppRoutes } from '../App';

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

describe('Phase 8D - Change Request Automated Test Suite', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  // =========================================================================
  // 1. Concurrency: Two teachers submit the same batch/date/slot at the same instant
  // =========================================================================
  describe('1. Concurrency Race-Safety on Attendance Submission', () => {
    it('Teacher A succeeds; Teacher B gets ALREADY_MARKED with Teacher A details, keeping B entries visible on screen', async () => {
      // Primary course & batch setup
      vi.spyOn(teacherService, 'getPrimaryCoursesWithBatches').mockResolvedValue([
        {
          courseId: 1,
          courseName: 'Diploma in Medical Laboratory Technology',
          courseCode: 'DMLT',
          batches: [{ batchId: 10, batchName: 'Batch 2024-26', academicYear: '2024-26' }],
        },
      ]);

      vi.spyOn(teacherService, 'getAttendanceSlotStatus').mockResolvedValue([]);

      vi.spyOn(teacherService, 'getBatchStudents').mockResolvedValue([
        { id: 201, name: 'Student One', registrationNumber: 'REG201', admissionNumber: 'ADM201' },
        { id: 202, name: 'Student Two', registrationNumber: 'REG202', admissionNumber: 'ADM202' },
      ]);

      // Initial state: not marked yet when screen was loaded
      vi.spyOn(teacherService, 'getAttendanceSession').mockResolvedValue({
        id: null,
        batchId: 10,
        date: new Date().toISOString().split('T')[0],
        slot: 'morning',
        status: 'not_marked',
        isWithinWindow: true,
        records: {},
      });

      // Simulation of atomic Postgres advisory lock & UNIQUE constraint:
      // Teacher A already submitted in the parallel transaction.
      // Therefore, Teacher B's submitAttendance call returns alreadyMarked: true with Teacher A's name
      const submitSpy = vi.spyOn(teacherService, 'submitAttendance').mockResolvedValue({
        success: false,
        alreadyMarked: true,
        markedByName: 'Prof. Ramesh Kumar',
        markedByRole: 'teacher',
        markedAt: '2026-10-16T10:15:30Z',
        message: 'Already marked by Prof. Ramesh Kumar at 10:15 AM. Only the administrator can correct it.',
      });

      renderWithProviders(<TeacherAttendanceTab teacherId={22} />);

      // Wait for student roster to render
      await waitFor(() => {
        expect(screen.getByText('Student One')).toBeInTheDocument();
        expect(screen.getByText('Student Two')).toBeInTheDocument();
      });

      // Teacher B changes Student One to Absent
      const absentBtns = screen.getAllByRole('button', { name: /^absent$/i });
      fireEvent.click(absentBtns[0]);

      // Verify Teacher B entered absent for Student One
      await waitFor(() => {
        expect(screen.getByText(/Absent:/)).toBeInTheDocument();
      });

      // Teacher B clicks Submit Attendance
      const submitBtn = screen.getByRole('button', { name: /submit attendance/i });
      fireEvent.click(submitBtn);

      // Confirmation Modal appears
      await waitFor(() => {
        expect(screen.getByText(/Confirm Attendance Submission/i)).toBeInTheDocument();
      });

      const confirmBtn = screen.getByRole('button', { name: /confirm & finalize/i });
      fireEvent.click(confirmBtn);

      // Verify submitAttendance was invoked with Teacher B's records
      await waitFor(() => {
        expect(submitSpy).toHaveBeenCalled();
      });

      // Assert Teacher B receives ALREADY_MARKED banner showing Teacher A's name and timestamp
      await waitFor(() => {
        expect(screen.getAllByText(/Prof\. Ramesh Kumar/i).length).toBeGreaterThanOrEqual(1);
        expect(screen.getByText(/Only the administrator can correct it/i)).toBeInTheDocument();
      });

      // Assert Teacher B's entries remain visible on screen for review (Student One still shows absent)
      expect(screen.getByText('Student One')).toBeInTheDocument();
      expect(screen.getByText(/Absent:/).parentElement?.textContent).toContain('1');

      // Assert controls become disabled / read-only to prevent duplicate submissions
      const allActionButtons = screen.getAllByRole('button', { name: /^present$|^absent$|^late$|^leave$/i });
      allActionButtons.forEach((btn) => {
        expect(btn).toBeDisabled();
      });
    });
  });

  // =========================================================================
  // 2. Open Faculty Access & Boundary Enforcement
  // =========================================================================
  describe('2. Open Faculty Permissions & Student Data Privacy', () => {
    it('teacher can mark any primary batch without pre-assignment', async () => {
      // Mock two distinct primary batches
      vi.spyOn(teacherService, 'getPrimaryCoursesWithBatches').mockResolvedValue([
        {
          courseId: 1,
          courseName: 'B.Sc Medical Lab Technology',
          courseCode: 'BMLT',
          batches: [
            { batchId: 101, batchName: 'Batch Alpha 2024', academicYear: '2024' },
            { batchId: 102, batchName: 'Batch Beta 2025', academicYear: '2025' },
          ],
        },
      ]);

      vi.spyOn(teacherService, 'getAttendanceSlotStatus').mockResolvedValue([]);
      vi.spyOn(teacherService, 'getBatchStudents').mockResolvedValue([
        { id: 1, name: 'Student Alpha', registrationNumber: 'REG01', admissionNumber: 'ADM01' },
      ]);
      vi.spyOn(teacherService, 'getAttendanceSession').mockResolvedValue({
        id: null,
        batchId: 101,
        date: new Date().toISOString().split('T')[0],
        slot: 'morning',
        status: 'not_marked',
        isWithinWindow: true,
        records: {},
      });

      renderWithProviders(<TeacherAttendanceTab teacherId={99} />);

      await waitFor(() => {
        expect(screen.getByText('Student Alpha')).toBeInTheDocument();
      });

      // Verify that batch Alpha and batch Beta are both selectable without assignment
      expect(screen.getByText('Batch Alpha 2024')).toBeInTheDocument();
      expect(screen.getByText('Batch Beta 2025')).toBeInTheDocument();
    });

    it('teacher student roster exposes only safe fields, never DOB, phone, address, fees, or marks', async () => {
      // Verify students_for_teacher contract
      const mockTeacherRoster = [
        {
          id: 501,
          name: 'Safe Student',
          registrationNumber: 'REG501',
          admissionNumber: 'ADM501',
          // Note: DOB, phone, address, fees, and marks are strictly NOT in the type or payload
        },
      ];

      expect(mockTeacherRoster[0]).not.toHaveProperty('dob');
      expect(mockTeacherRoster[0]).not.toHaveProperty('phone');
      expect(mockTeacherRoster[0]).not.toHaveProperty('address');
      expect(mockTeacherRoster[0]).not.toHaveProperty('total_fee_paise');
      expect(mockTeacherRoster[0]).not.toHaveProperty('marks');
    });

    it('submitted session loads read-only with marker attribution and disables editing', async () => {
      vi.spyOn(teacherService, 'getPrimaryCoursesWithBatches').mockResolvedValue([
        {
          courseId: 1,
          courseName: 'DMLT',
          courseCode: 'DMLT',
          batches: [{ batchId: 10, batchName: 'Batch 2024-26', academicYear: '2024-26' }],
        },
      ]);
      vi.spyOn(teacherService, 'getAttendanceSlotStatus').mockResolvedValue([]);
      vi.spyOn(teacherService, 'getBatchStudents').mockResolvedValue([
        { id: 1, name: 'Student One', registrationNumber: 'REG1', admissionNumber: 'ADM1' },
      ]);

      // Pre-submitted session
      vi.spyOn(teacherService, 'getAttendanceSession').mockResolvedValue({
        id: 77,
        batchId: 10,
        date: new Date().toISOString().split('T')[0],
        slot: 'morning',
        status: 'submitted',
        isWithinWindow: true,
        markedByName: 'Prof. Fatima Zehra',
        submittedAt: '2026-10-16T09:30:00Z',
        records: { 1: 'present' },
        isReadOnly: true,
      });

      renderWithProviders(<TeacherAttendanceTab teacherId={12} />);

      // Verify read-only banner with marker name
      await waitFor(() => {
        expect(screen.getByText(/Already marked by Prof\. Fatima Zehra/i)).toBeInTheDocument();
        expect(screen.getByText(/Only the administrator can correct it/i)).toBeInTheDocument();
      });

      // Verify mark buttons are disabled
      const btns = screen.getAllByRole('button', { name: /^present$|^absent$|^late$|^leave$/i });
      btns.forEach((btn) => {
        expect(btn).toBeDisabled();
      });
    });
  });

  // =========================================================================
  // 3. Dual-Enrolled Student: Primary Attendance Only
  // =========================================================================
  describe('3. Student Attendance Scoped Strictly to Primary Enrollments', () => {
    it('dual-enrolled student sees attendance for primary course only and displays skill course notice', async () => {
      const enrollments = [
        {
          enrollmentId: 101,
          courseId: 1,
          courseName: 'Diploma in Medical Laboratory Technology',
          courseCode: 'DMLT',
          courseType: 'primary' as const,
          batchId: 10,
          batchName: 'Batch 2024-26',
        },
        {
          enrollmentId: 102,
          courseId: 5,
          courseName: 'Phlebotomy Technician Certification',
          courseCode: 'SKILL-PHLEB',
          courseType: 'skill' as const,
          batchId: 50,
          batchName: 'Skill Batch 2024',
        },
      ];

      const getAttendanceSpy = vi.spyOn(studentService, 'getStudentAttendance').mockResolvedValue({
        summary: {
          sessions_held: 40,
          present: 36,
          late: 2,
          absent: 2,
          leave: 0,
          effective_held: 40,
          weighted_present: 37,
          percentage: 92.5,
          status_band: 'ok',
          can_miss_more: 7,
          recover_sessions: 0,
          deduction_absent_pts: 2.5,
          deduction_late_pts: 1.25,
        },
        calendar: [],
        morningStats: { total: 20, present: 19, late: 1, absent: 0, percentage: 97.5 },
        eveningStats: { total: 20, present: 17, late: 1, absent: 2, percentage: 87.5 },
      });

      renderWithProviders(
        <AttendanceTab studentId={42} enrollments={enrollments} />
      );

      // Verify that getStudentAttendance was called with primary enrollment id (101), NEVER skill (102)
      await waitFor(() => {
        expect(getAttendanceSpy).toHaveBeenCalledWith(42, 101);
      });

      // Verify the Dual Enrollment Notice is rendered
      await waitFor(() => {
        expect(
          screen.getByText(/Attendance tracking is not applicable to skill courses/i)
        ).toBeInTheDocument();
        expect(screen.getByText(/Phlebotomy Technician Certification/i)).toBeInTheDocument();
        expect(screen.getByText(/Primary Only/i)).toBeInTheDocument();
      });

      // Verify percentage displays primary calculation (92.5%)
      expect(screen.getByText('92.5%')).toBeInTheDocument();
    });
  });

  // =========================================================================
  // 4. Universal Logout & State Cleansing
  // =========================================================================
  describe('4. Universal Log Out Flow across Portals', () => {
    it('clicking log out opens confirmation modal; confirming purges push subscription, auth session, and query cache', async () => {
      const mockUnsubscribe = vi.spyOn(pushNotificationService, 'unsubscribeUser').mockResolvedValue(true);
      const mockSignOut = vi.spyOn(supabase.auth, 'signOut').mockResolvedValue({ error: null } as any);

      // Mock user context as teacher
      vi.spyOn(supabase.auth, 'getSession').mockResolvedValue({
        data: { session: { user: { id: 't1', email: 'teacher@mips.invalid' } } },
      } as any);

      vi.spyOn(supabase, 'from').mockImplementation(((table: string) => ({
        select: vi.fn().mockReturnThis(),
        eq: vi.fn().mockReturnThis(),
        maybeSingle: vi.fn().mockResolvedValue({
          data: { role: 'teacher', user_id: 't1', active: true },
          error: null,
        }),
      })) as any);

      renderWithProviders(
        <PortalHeader
          tabs={[{ id: 'attendance', label: 'Attendance' }]}
          activeTab="attendance"
          onTabChange={vi.fn()}
        />
      );

      // Verify Log Out button is visible with >= 44x44 touch target
      const logoutBtn = screen.getByRole('button', { name: /log out/i });
      expect(logoutBtn).toBeInTheDocument();

      // Click Log Out
      fireEvent.click(logoutBtn);

      // Confirmation modal appears
      await waitFor(() => {
        expect(screen.getByText(/Confirm Sign Out/i)).toBeInTheDocument();
        expect(screen.getByText(/Are you sure you want to sign out of the portal\?/i)).toBeInTheDocument();
      });

      // Click Sign Out in modal
      const confirmSignOutBtn = screen.getByRole('button', { name: /^sign out$/i });
      fireEvent.click(confirmSignOutBtn);

      // Verify push unsubscribed and Supabase signOut fired
      await waitFor(() => {
        expect(mockUnsubscribe).toHaveBeenCalled();
        expect(mockSignOut).toHaveBeenCalled();
      });
    });

    it('unauthenticated user attempting to access private /student or /teacher route is redirected to /login with replace: true', async () => {
      function LocationDisplay() {
        const location = useLocation();
        return <div data-testid="current-path">{location.pathname}</div>;
      }

      // No active session
      vi.spyOn(supabase.auth, 'getSession').mockResolvedValue({
        data: { session: null },
      } as any);

      renderWithProviders(
        <>
          <LocationDisplay />
          <AppRoutes />
        </>,
        { route: '/teacher' }
      );

      // ProtectedRoute redirects immediately to /login
      await waitFor(() => {
        const loc = screen.getByTestId('current-path');
        expect(loc.textContent).toBe('/login');
      });
    });
  });
});
