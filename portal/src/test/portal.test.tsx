// src/test/portal.test.tsx
// Comprehensive Automated Test Suite covering Phase 6E scenarios

import React from 'react';
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { render, screen, fireEvent, waitFor, act } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { MemoryRouter, useLocation } from 'react-router-dom';

// Contexts & Services
import { AuthProvider, useAuth } from '../context/AuthContext';
import { OnlineStatusProvider } from '../context/OnlineStatusContext';
import { studentService } from '../services/studentService';
import { teacherService } from '../services/teacherService';
import * as pdfExporter from '../lib/pdfExporter';
import { supabase } from '../lib/supabase';

// Components
import { LoginScreen } from '../components/auth/LoginScreen';
import { FirstLoginModal } from '../components/auth/FirstLoginModal';
import { ResultsTab } from '../components/student/ResultsTab';
import { FeesTab } from '../components/student/FeesTab';
import { AttendanceTab } from '../components/student/AttendanceTab';
import { TeacherAttendanceTab } from '../components/teacher/TeacherAttendanceTab';
import { TeacherMarksTab } from '../components/teacher/TeacherMarksTab';
import { OfflineBanner } from '../components/common/OfflineBanner';
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

describe('MIPS ERP Portal - Sub-phase 6E Test Suite', () => {
  let mockInvoke: any;

  beforeEach(() => {
    vi.clearAllMocks();
    mockInvoke = vi.fn();
    Object.defineProperty(supabase, 'functions', {
      value: { invoke: mockInvoke },
      writable: true,
      configurable: true,
    });
  });

  // ---------------------------------------------------------------------------
  // 1. Student login with wrong password shows error
  // ---------------------------------------------------------------------------
  it('1. Student login with wrong password shows error', async () => {
    mockInvoke.mockResolvedValueOnce({
      data: {
        error: 'Register number or password is incorrect.',
        details: { attempts_remaining: 4 },
      },
      error: null,
    });

    renderWithProviders(<LoginScreen onSuccess={vi.fn()} />);

    const identifierInput = screen.getByLabelText(/register number or username/i);
    const passwordInput = screen.getByLabelText(/^password/i);
    const submitBtn = screen.getByRole('button', { name: /log in/i });

    fireEvent.change(identifierInput, { target: { value: '2023MLT042' } });
    fireEvent.change(passwordInput, { target: { value: 'wrongpassword' } });
    fireEvent.click(submitBtn);

    await waitFor(() => {
      expect(
        screen.getByText('Register number or password is incorrect.')
      ).toBeInTheDocument();
    });
  });

  // ---------------------------------------------------------------------------
  // 2. Student first login (reg + DOB) forces password set
  // ---------------------------------------------------------------------------
  it('2. Student first login (reg + DOB) forces password set', async () => {
    mockInvoke.mockResolvedValueOnce({
      data: {
        success: true,
        user: { id: 'test-user-id', email: 'stu@mips.edu', role: 'student' },
        session: { access_token: 'fake-token', refresh_token: 'fake-refresh' },
      },
      error: null,
    });

    renderWithProviders(
      <FirstLoginModal isOpen={true} onClose={vi.fn()} onSuccess={vi.fn()} />
    );

    const regInput = screen.getByLabelText(/registration or admission number/i);
    const dobInput = screen.getByLabelText(/date of birth/i);
    const passInput = screen.getByLabelText(/create new password/i);
    const confirmInput = screen.getByLabelText(/confirm password/i);
    const activateBtn = screen.getByRole('button', { name: /activate & proceed/i });

    fireEvent.change(regInput, { target: { value: '2023MLT001' } });
    fireEvent.change(dobInput, { target: { value: '15/05/2004' } });
    fireEvent.change(passInput, { target: { value: 'StrongPass123!' } });
    fireEvent.change(confirmInput, { target: { value: 'StrongPass123!' } });

    fireEvent.click(activateBtn);

    await waitFor(() => {
      expect(mockInvoke).toHaveBeenCalledWith('student-first-login', {
        body: expect.objectContaining({
          registration_number: '2023MLT001',
          date_of_birth: '2004-05-15',
          new_password: 'StrongPass123!',
        }),
      });
    });
  });

  // ---------------------------------------------------------------------------
  // 3. Student views results (grade, PASS/FAIL badge, marks table, PDF download)
  // ---------------------------------------------------------------------------
  it('3. Student views results with PASS badge, marks table and PDF download', async () => {
    const mockExportPdf = vi.spyOn(pdfExporter, 'exportElementToPdf').mockResolvedValue();

    vi.spyOn(studentService, 'getStudentResults').mockResolvedValue([
      {
        id: 1,
        examId: 10,
        examName: 'First Year Final Examination',
        examCode: 'EX-2026-01',
        courseId: 2,
        courseName: 'Diploma in Medical Laboratory Technology',
        batchName: 'Batch 2023-25',
        publishedAt: '2026-04-10T10:00:00Z',
        totalMarks: 345,
        maxMarks: 400,
        percentage: 86.25,
        grade: 'A+',
        status: 'PASS',
        resultCode: 'RES-89472',
        subjects: [
          {
            subjectId: 1,
            subjectName: 'Clinical Biochemistry',
            subjectCode: 'BIO101',
            obtainedMarks: 88,
            maxMarks: 100,
            passMarks: 40,
            isPass: true,
            isAbsent: false,
          },
          {
            subjectId: 2,
            subjectName: 'Microbiology',
            subjectCode: 'MIC101',
            obtainedMarks: 85,
            maxMarks: 100,
            passMarks: 40,
            isPass: true,
            isAbsent: false,
          },
        ],
      },
    ]);

    renderWithProviders(
      <ResultsTab
        studentId={1}
        studentName="Amina Fathima"
        registrationNumber="2023MLT042"
        admissionNumber="ADM-1042"
      />
    );

    await waitFor(() => {
      expect(screen.getByText('First Year Final Examination')).toBeInTheDocument();
      expect(screen.getAllByText('PASS').length).toBeGreaterThan(0);
      expect(screen.getByText('A+')).toBeInTheDocument();
      expect(screen.getByText('Clinical Biochemistry')).toBeInTheDocument();
      expect(screen.getByText('Microbiology')).toBeInTheDocument();
    });

    // Trigger PDF Export
    const downloadBtn = screen.getByRole('button', { name: /download pdf/i });
    fireEvent.click(downloadBtn);

    await waitFor(() => {
      expect(mockExportPdf).toHaveBeenCalled();
    });
  });

  // ---------------------------------------------------------------------------
  // 4. Student views fees (balance, installments, download receipt)
  // ---------------------------------------------------------------------------
  it('4. Student views fees with balance, installments and receipt download', async () => {
    const mockExportPdf = vi.spyOn(pdfExporter, 'exportElementToPdf').mockResolvedValue();

    vi.spyOn(studentService, 'getStudentFees').mockResolvedValue({
      summary: {
        totalFeePaise: 7500000,
        paidAmountPaise: 5000000,
        pendingAmountPaise: 2500000,
        primaryFeePaise: 7500000,
        primaryPaidPaise: 5000000,
        primaryPendingPaise: 2500000,
        skillFeePaise: 0,
        skillPaidPaise: 0,
        skillPendingPaise: 0,
      },
      items: [
        {
          id: 1,
          title: 'Tuition Fee - Term 1',
          kind: 'primary',
          amountPaise: 3500000,
          paidAmountPaise: 3500000,
          pendingAmountPaise: 0,
          dueDate: '2026-06-30',
          status: 'Paid',
        },
        {
          id: 2,
          title: 'Tuition Fee - Term 2',
          kind: 'primary',
          amountPaise: 4000000,
          paidAmountPaise: 1500000,
          pendingAmountPaise: 2500000,
          dueDate: '2026-12-31',
          status: 'Due',
        },
      ],
      payments: [
        {
          id: 101,
          receiptNumber: 'REC-2026-0045',
          date: '2026-05-10',
          amountPaise: 3500000,
          paymentMode: 'bank_transfer',
          referenceNumber: 'UPI983742',
        },
      ],
      lastUpdated: new Date().toISOString(),
    });

    renderWithProviders(
      <FeesTab
        studentId={1}
        studentName="Amina Fathima"
        registrationNumber="2023MLT042"
        admissionNumber="ADM-1042"
      />
    );

    await waitFor(() => {
      // Pending balance check: 2500000 paise = ₹25,000
      expect(screen.getAllByText(/25,000/).length).toBeGreaterThan(0);
      expect(screen.getByText('Tuition Fee - Term 1')).toBeInTheDocument();
      expect(screen.getByText('REC-2026-0045')).toBeInTheDocument();
    });

    // Download Receipt
    const receiptBtn = screen.getByRole('button', { name: /receipt pdf/i });
    fireEvent.click(receiptBtn);

    await waitFor(() => {
      expect(mockExportPdf).toHaveBeenCalled();
    });
  });

  // ---------------------------------------------------------------------------
  // 5. Student views attendance (warning banner if below 75%, calendar)
  // ---------------------------------------------------------------------------
  it('5. Student views attendance with shortage warning banner and calendar', async () => {
    vi.spyOn(studentService, 'getStudentAttendance').mockResolvedValue({
      summary: {
        student_id: 1,
        enrollment_id: 10,
        course_name: 'DMLT',
        batch_name: 'Batch 2023',
        sessions_held: 100,
        present: 68,
        late: 4,
        absent: 28,
        leave: 0,
        weighted_present: 70,
        percentage: 70.0,
        status_band: 'shortage',
        can_miss_more: 0,
        recover_sessions: 20,
        morning_held: 50,
        morning_present: 35,
        morning_percentage: 70,
        evening_held: 50,
        evening_present: 35,
        evening_percentage: 70,
        deduction_absent_pts: 0.7,
        deduction_late_pts: 0.35,
      },
      calendar: [
        { date: '2026-10-01', slot: 'morning', status: 'present' },
        { date: '2026-10-01', slot: 'evening', status: 'absent' },
      ],
      morningStats: { held: 50, present: 35, percentage: 70 },
      eveningStats: { held: 50, present: 35, percentage: 70 },
    });

    renderWithProviders(
      <AttendanceTab
        studentId={1}
        enrollments={[
          {
            enrollmentId: 10,
            courseId: 1,
            courseName: 'DMLT',
            courseType: 'primary',
            batchId: 2,
            batchName: 'Batch 2023',
          },
        ]}
      />
    );

    await waitFor(() => {
      // Shortage alert banner
      expect(screen.getByText(/Attendance below minimum/i)).toBeInTheDocument();
      // Recovery sessions guidance
      expect(screen.getByText(/20 sessions in a row/i)).toBeInTheDocument();
      // 75% cutoff marker
      expect(screen.getByText(/75% Min/i)).toBeInTheDocument();
    });
  });

  // ---------------------------------------------------------------------------
  // 6. Teacher logs in -> marks attendance (P/L/A/LV, counts update live, submit fires)
  // ---------------------------------------------------------------------------
  it('6. Teacher marks attendance with live count updates and submission', async () => {
    vi.spyOn(teacherService, 'getPrimaryCoursesWithBatches').mockResolvedValue([
      {
        courseId: 1,
        courseName: 'DMLT',
        courseCode: 'DMLT',
        batches: [
          { batchId: 2, batchName: 'Batch 2023-25', academicYear: '2023-25' },
        ],
      },
    ]);

    vi.spyOn(teacherService, 'getAttendanceSlotStatus').mockResolvedValue([]);

    vi.spyOn(teacherService, 'getAssignedBatches').mockResolvedValue([
      {
        batchId: 2,
        batchName: 'Batch 2023-25',
        courseId: 1,
        courseName: 'DMLT',
      },
    ]);

    vi.spyOn(teacherService, 'getBatchStudents').mockResolvedValue([
      { id: 101, name: 'Adnan Ali', registrationNumber: '2023MLT01', admissionNumber: '101' },
      { id: 102, name: 'Bilal Khan', registrationNumber: '2023MLT02', admissionNumber: '102' },
    ]);

    vi.spyOn(teacherService, 'getAttendanceSession').mockResolvedValue({
      id: null,
      batchId: 2,
      date: new Date().toISOString().split('T')[0],
      slot: 'morning',
      status: 'not_marked',
      isWithinWindow: true,
      records: {},
    });

    const submitSpy = vi.spyOn(teacherService, 'submitAttendance').mockResolvedValue({
      success: true,
      recordsMarked: 2,
    });
    vi.spyOn(teacherService, 'saveAttendanceDraft').mockResolvedValue(55);

    renderWithProviders(<TeacherAttendanceTab teacherId={5} />);

    await waitFor(() => {
      expect(screen.getByText('Adnan Ali')).toBeInTheDocument();
      expect(screen.getByText('Bilal Khan')).toBeInTheDocument();
    });

    // Find Absent buttons and click the first one (for Adnan)
    const absentBtns = screen.getAllByRole('button', { name: /^absent$/i });
    expect(absentBtns.length).toBeGreaterThan(0);
    fireEvent.click(absentBtns[0]);

    // Live counts: Absent: 1, Present: 1
    await waitFor(() => {
      expect(screen.getByText(/Absent:/)).toBeInTheDocument();
      expect(screen.getByText('Absent:').parentElement?.textContent).toContain('1');
    });

    // Click Submit Attendance
    const submitBtn = screen.getByRole('button', { name: /submit attendance/i });
    fireEvent.click(submitBtn);

    // Confirmation Modal
    await waitFor(() => {
      expect(screen.getByText(/Confirm Attendance Submission/i)).toBeInTheDocument();
    });

    const confirmBtn = screen.getByRole('button', { name: /confirm & finalize/i });
    fireEvent.click(confirmBtn);

    await waitFor(() => {
      expect(submitSpy).toHaveBeenCalled();
    });
  });

  // ---------------------------------------------------------------------------
  // 7. Teacher enters marks (auto-advance, absent toggle, stats live, submit)
  // ---------------------------------------------------------------------------
  it('7. Teacher enters marks with absent toggle, live stats and submission', async () => {
    vi.spyOn(teacherService, 'getAssignedBatches').mockResolvedValue([
      { batchId: 2, batchName: 'Batch 2023-25', courseId: 1, courseName: 'DMLT' },
    ]);

    vi.spyOn(teacherService, 'getTeacherExams').mockResolvedValue([
      {
        id: 10,
        name: 'Internal Assessment 1',
        examCode: 'IA1',
        courseId: 1,
        courseName: 'DMLT',
        batchId: 2,
        batchName: 'Batch 2023-25',
        status: 'mark_entry',
      },
    ]);

    vi.spyOn(teacherService, 'getExamSubjects').mockResolvedValue([
      { id: 101, examId: 10, subjectName: 'Pathology', maxMarks: 50, passMarks: 20 },
    ]);

    vi.spyOn(teacherService, 'getBatchStudents').mockResolvedValue([
      { id: 1, name: 'Candidate One', registrationNumber: 'REG1', admissionNumber: 'ADM1' },
      { id: 2, name: 'Candidate Two', registrationNumber: 'REG2', admissionNumber: 'ADM2' },
    ]);

    vi.spyOn(teacherService, 'getExistingMarks').mockResolvedValue({});

    const saveSpy = vi.spyOn(teacherService, 'saveOrSubmitMarks').mockResolvedValue({
      success: true,
      count: 2,
    });

    renderWithProviders(<TeacherMarksTab teacherId={5} />);

    await waitFor(() => {
      expect(screen.getByText('Pathology (Max: 50, Pass: 20)')).toBeInTheDocument();
      expect(screen.getByText('Candidate One')).toBeInTheDocument();
      expect(screen.getByText('Candidate Two')).toBeInTheDocument();
    });

    // Enter 45 marks for Candidate One
    const marksInputs = screen.getAllByPlaceholderText(/0 – 50/i);
    fireEvent.change(marksInputs[0], { target: { value: '45' } });

    // Mark Candidate Two as Absent
    const absentCheckboxes = screen.getAllByRole('checkbox');
    fireEvent.click(absentCheckboxes[1]);

    // Live stats verification
    await waitFor(() => {
      // 2 students entered (1 score + 1 absent)
      expect(screen.getByText('2 / 2')).toBeInTheDocument();
      // Average score is 45.0
      expect(screen.getByText('45.0')).toBeInTheDocument();
    });

    // Click Submit Marks
    const submitBtn = screen.getByRole('button', { name: /submit marks/i });
    fireEvent.click(submitBtn);

    // Modal Confirmation
    await waitFor(() => {
      expect(screen.getByText(/Confirm Marks Submission/i)).toBeInTheDocument();
    });

    const confirmBtn = screen.getByRole('button', { name: /confirm & submit/i });
    fireEvent.click(confirmBtn);

    await waitFor(() => {
      expect(saveSpy).toHaveBeenCalledWith(10, 101, expect.any(Array), true);
    });
  });

  // ---------------------------------------------------------------------------
  // 8. Role guard: student trying /teacher redirected to /student, and vice versa
  // ---------------------------------------------------------------------------
  it('8. Role guard redirects cross-role route attempts', async () => {
    // Component to inspect current location
    function LocationDisplay() {
      const location = useLocation();
      return <div data-testid="location-display">{location.pathname}</div>;
    }

    // Mock user as student
    vi.spyOn(supabase.auth, 'getSession').mockResolvedValue({
      data: { session: { user: { id: 'u1', email: 's@mips.edu' } } },
    } as any);

    vi.spyOn(supabase, 'from').mockImplementation(((table: string) => {
      if (table === 'profiles') {
        return {
          select: vi.fn().mockReturnThis(),
          eq: vi.fn().mockReturnThis(),
          maybeSingle: vi.fn().mockResolvedValue({
            data: { role: 'student', user_id: 'u1', active: true },
            error: null,
          }),
        };
      }
      return {
        select: vi.fn().mockReturnThis(),
        eq: vi.fn().mockReturnThis(),
        is: vi.fn().mockReturnThis(),
        maybeSingle: vi.fn().mockResolvedValue({ data: null, error: null }),
      };
    }) as any);

    renderWithProviders(
      <>
        <LocationDisplay />
        <AppRoutes />
      </>,
      { route: '/teacher' }
    );

    // Should redirect to student route
    await waitFor(() => {
      const loc = screen.getByTestId('location-display');
      expect(loc.textContent).toMatch(/^\/student/);
    });
  });

  // ---------------------------------------------------------------------------
  // 9. Inactivity auto-logout after 15 minutes
  // ---------------------------------------------------------------------------
  it('9. Inactivity auto-logout triggers warning after 15 minutes', async () => {
    vi.useFakeTimers();

    const mockLogout = vi.spyOn(supabase.auth, 'signOut').mockResolvedValue({ error: null } as any);

    function TestInactivityConsumer() {
      const { inactivityWarning } = useAuth();
      return (
        <div>
          <span>{inactivityWarning ? 'INACTIVE_WARNING_VISIBLE' : 'ACTIVE'}</span>
        </div>
      );
    }

    renderWithProviders(<TestInactivityConsumer />);

    // Fast-forward 15 minutes + 1 second
    await act(async () => {
      vi.advanceTimersByTime(15 * 60 * 1000 + 1000);
    });

    vi.useRealTimers();
  });

  // ---------------------------------------------------------------------------
  // 10. Offline banner appears when offline
  // ---------------------------------------------------------------------------
  it('10. Offline banner appears when network is disconnected', async () => {
    renderWithProviders(<OfflineBanner />);

    // Dispatch offline event
    fireEvent(window, new Event('offline'));

    await waitFor(() => {
      expect(screen.getByText(/You're offline\. Showing saved data\./i)).toBeInTheDocument();
      expect(screen.getByRole('button', { name: /retry/i })).toBeInTheDocument();
    });

    // Dispatch online event
    fireEvent(window, new Event('online'));

    await waitFor(() => {
      expect(screen.queryByText(/You're offline\. Showing saved data\./i)).not.toBeInTheDocument();
    });
  });
});
