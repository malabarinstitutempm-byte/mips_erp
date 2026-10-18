// src/test/phase9c_completed_students.test.tsx
// Phase 9C Automated Test Suite: Completed Students, Access Window & Teacher Attendance Batch Filter

import React from 'react';
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { MemoryRouter } from 'react-router-dom';

// Contexts & Services
import { AuthProvider, useAuth } from '../context/AuthContext';
import { OnlineStatusProvider } from '../context/OnlineStatusContext';
import { studentService, StudentEnrollmentInfo } from '../services/studentService';
import { teacherService } from '../services/teacherService';
import { supabase } from '../lib/supabase';

// Components
import { StudentArea } from '../components/student/StudentArea';
import { AttendanceTab } from '../components/student/AttendanceTab';
import { TeacherAttendanceTab } from '../components/teacher/TeacherAttendanceTab';
import type { AttendanceSummary, StudentProfile } from '../types';

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

describe('Phase 9C - Completed Student & Teacher Attendance Portal Suite', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  // =========================================================================
  // 1. Teacher Attendance Pickers: Active Primary Batches Only
  // =========================================================================
  describe('1. Teacher Attendance Pickers: Active Primary Batches Only', () => {
    it('only loads active primary batches and hides completed batches from selection', async () => {
      // Mock getPrimaryCoursesWithBatches returning active batches only
      vi.spyOn(teacherService, 'getPrimaryCoursesWithBatches').mockResolvedValue([
        {
          courseId: 1,
          courseName: 'Diploma in Medical Laboratory Technology',
          courseCode: 'DMLT',
          batches: [
            { batchId: 101, batchName: 'Batch 2024-26 (Active)', academicYear: '2024-26' },
          ],
        },
      ]);

      vi.spyOn(teacherService, 'getAttendanceSlotStatus').mockResolvedValue([]);
      vi.spyOn(teacherService, 'getBatchStudents').mockResolvedValue([
        { id: 1, name: 'Active Student A', registrationNumber: 'REG01', admissionNumber: 'ADM01' },
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

      renderWithProviders(<TeacherAttendanceTab teacherId={10} />);

      await waitFor(() => {
        expect(screen.getByText('Batch 2024-26 (Active)')).toBeInTheDocument();
      });

      // Confirm completed batch is NOT present
      expect(screen.queryByText('Batch 2022-24 (Completed)')).not.toBeInTheDocument();
    });
  });

  // =========================================================================
  // 2. Student Portal: Completed Student Banner and Timetable Suppression
  // =========================================================================
  describe('2. Student Portal: Completed Student Banner & Navigation', () => {
    const mockCompletedProfile: StudentProfile = {
      id: 50,
      admission_number: 'ADM-2024-0050',
      registration_number: '2024MLT050',
      name: 'Zayan Ahmed',
      dob: '2004-05-15',
      phone: '9847123456',
      gender: 'Male',
      course_id: 1,
      batch_id: 101,
      course_name: 'Diploma in Medical Laboratory Technology',
      batch_name: 'Batch 2024-26',
      status: 'completed',
      completed_on: '2026-06-30',
      access_until: '2026-12-31',
    };

    const mockCompletedEnrollments: StudentEnrollmentInfo[] = [
      {
        enrollmentId: 501,
        courseId: 1,
        courseName: 'Diploma in Medical Laboratory Technology',
        courseType: 'primary',
        batchId: 101,
        batchName: 'Batch 2024-26',
        status: 'completed',
        completedOn: '2026-06-30',
      },
    ];

    it('displays completion banner with completed_on date and access validity', async () => {
      vi.spyOn(studentService, 'getStudentProfile').mockResolvedValue({
        profile: mockCompletedProfile,
        enrollments: mockCompletedEnrollments,
      });

      renderWithProviders(<StudentArea />);

      await waitFor(() => {
        expect(screen.getByText(/Course completed on/i)).toBeInTheDocument();
      });

      // Verify date is displayed
      expect(screen.getByText(/30\/06\/2026/)).toBeInTheDocument();

      // Verify access validity notice is shown
      expect(screen.getByText(/Portal access is valid until/i)).toBeInTheDocument();
    });

    it('hides the Timetable tab for completed students while keeping Results, Fees, and Attendance', async () => {
      vi.spyOn(studentService, 'getStudentProfile').mockResolvedValue({
        profile: mockCompletedProfile,
        enrollments: mockCompletedEnrollments,
      });

      renderWithProviders(<StudentArea />);

      await waitFor(() => {
        expect(screen.getByText('Attendance')).toBeInTheDocument();
      });

      expect(screen.getByText('Results')).toBeInTheDocument();
      expect(screen.getByText('Fees')).toBeInTheDocument();
      expect(screen.getByText('Profile')).toBeInTheDocument();

      // Timetable tab MUST be hidden
      expect(screen.queryByText('Timetable')).not.toBeInTheDocument();
    });
  });

  // =========================================================================
  // 3. Attendance Tab: Low-attendance Alerts Hidden for Completed Students
  // =========================================================================
  describe('3. Attendance Tab: Alerts Hidden for Completed Students', () => {
    const mockShortageSummary: AttendanceSummary = {
      student_id: 50,
      enrollment_id: 501,
      course_name: 'DMLT',
      batch_name: 'Batch 2024-26',
      sessions_held: 100,
      present: 60,
      late: 10,
      absent: 30,
      leave: 0,
      weighted_present: 65,
      percentage: 65.0,
      status_band: 'shortage',
      can_miss_more: 0,
      recover_sessions: 40,
      morning_held: 50,
      morning_present: 32,
      morning_percentage: 64.0,
      evening_held: 50,
      evening_present: 33,
      evening_percentage: 66.0,
      deduction_absent_pts: 30,
      deduction_late_pts: 5,
    };

    const mockEnrollments: StudentEnrollmentInfo[] = [
      {
        enrollmentId: 501,
        courseId: 1,
        courseName: 'DMLT',
        courseType: 'primary',
        batchId: 101,
        batchName: 'Batch 2024-26',
        status: 'completed',
        completedOn: '2026-06-30',
      },
    ];

    it('suppresses shortage and low attendance warning alerts when isCompleted=true, while attendance percentage remains visible', async () => {
      vi.spyOn(studentService, 'getStudentAttendance').mockResolvedValue({
        summary: mockShortageSummary,
        calendar: [],
        morningStats: { held: 50, present: 32, percentage: 64.0 },
        eveningStats: { held: 50, present: 33, percentage: 66.0 },
      });

      renderWithProviders(
        <AttendanceTab
          studentId={50}
          enrollments={mockEnrollments}
          isCompleted={true}
        />
      );

      await waitFor(() => {
        expect(screen.getByText('65.0%')).toBeInTheDocument();
      });

      // Shortage alert banner MUST NOT be present
      expect(screen.queryByText('Attendance below minimum')).not.toBeInTheDocument();
      expect(screen.queryByText(/Attend.*sessions in a row/i)).not.toBeInTheDocument();
    });

    it('displays shortage alert for active (non-completed) students', async () => {
      vi.spyOn(studentService, 'getStudentAttendance').mockResolvedValue({
        summary: mockShortageSummary,
        calendar: [],
        morningStats: { held: 50, present: 32, percentage: 64.0 },
        eveningStats: { held: 50, present: 33, percentage: 66.0 },
      });

      renderWithProviders(
        <AttendanceTab
          studentId={50}
          enrollments={mockEnrollments}
          isCompleted={false}
        />
      );

      await waitFor(() => {
        expect(screen.getByText('Attendance below minimum')).toBeInTheDocument();
      });
      expect(screen.getByText(/Your overall attendance is 65.0%/i)).toBeInTheDocument();
    });
  });

  // =========================================================================
  // 4. Access Window Expiration (Phase 9E)
  // =========================================================================
  describe('4. Access Window Expiration (Phase 9E)', () => {
    it('shows dedicated "Access Has Ended" screen with Sign Out button when access_until is past', async () => {
      const expiredProfile: StudentProfile = {
        id: 70,
        admission_number: 'ADM-2023-0070',
        registration_number: '2023MLT070',
        name: 'Expired Student',
        dob: '2003-01-01',
        phone: '9847999999',
        gender: 'Female',
        course_id: 1,
        batch_id: 100,
        status: 'completed',
        completed_on: '2025-12-31',
        access_until: '2026-03-31', // Past date relative to test year 2026-10-17
      };

      vi.spyOn(studentService, 'getStudentProfile').mockResolvedValue({
        profile: expiredProfile,
        enrollments: [],
      });

      renderWithProviders(<StudentArea />);

      await waitFor(() => {
        expect(screen.getByText('Access Has Ended')).toBeInTheDocument();
      });

      expect(
        screen.getByText('Your access has ended. Please contact the college office.')
      ).toBeInTheDocument();

      const signOutBtn = screen.getByRole('button', { name: /Sign Out/i });
      expect(signOutBtn).toBeInTheDocument();
    });
  });
});
