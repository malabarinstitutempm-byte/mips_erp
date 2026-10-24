// src/test/account_reset_and_teacher_activation.test.tsx
// Automated Test Suite: Password Invalidation on Reset & Teacher First-Time Activation

import React from 'react';
import { describe, it, expect, beforeEach, vi } from 'vitest';
import { render, screen, fireEvent, waitFor, act } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { MemoryRouter } from 'react-router-dom';
import { AuthProvider, useAuth } from '../context/AuthContext';
import { FirstLoginModal } from '../components/auth/FirstLoginModal';
import { accountSyncService } from '../services/accountSyncService';
import { supabase } from '../lib/supabase';

function TestConsumer({ onReady }: { onReady: (auth: ReturnType<typeof useAuth>) => void }) {
  const auth = useAuth();
  React.useEffect(() => {
    onReady(auth);
  }, [auth, onReady]);
  return <div>Auth Consumer</div>;
}

function renderAuth(onReady: (auth: ReturnType<typeof useAuth>) => void) {
  const queryClient = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={queryClient}>
      <MemoryRouter>
        <AuthProvider>
          <TestConsumer onReady={onReady} />
        </AuthProvider>
      </MemoryRouter>
    </QueryClientProvider>
  );
}

describe('Account Reset & First-Time Verification Tests', () => {
  beforeEach(() => {
    localStorage.clear();
    vi.restoreAllMocks();

    // Mock realtime channel to prevent real node WebSocket connections
    vi.spyOn(supabase, 'channel').mockReturnValue({
      on: vi.fn().mockReturnThis(),
      subscribe: vi.fn().mockReturnThis(),
    } as any);
    vi.spyOn(supabase, 'removeChannel').mockImplementation(() => {});
  });

  it('1. Old password is rejected when account is reset to first login', async () => {
    let authContext: any = null;
    renderAuth((a) => {
      authContext = a;
    });

    await waitFor(() => expect(authContext).not.toBeNull());

    // Simulate Admin resetting student '2023mlt042' to First Login
    await act(async () => {
      await accountSyncService.resetToFirstLogin('2023mlt042', 'student');
    });

    // Attempt login with old default password
    let loginRes: any;
    await act(async () => {
      loginRes = await authContext.login('2023mlt042', 'Student#Pass2026');
    });

    // Must be rejected!
    expect(loginRes.success).toBe(false);
    expect(loginRes.error).toContain('Account requires first-time activation');
  });

  it('2. Student can activate via first login, establishing a new password that replaces the old one', async () => {
    let authContext: any = null;
    renderAuth((a) => {
      authContext = a;
    });

    await waitFor(() => expect(authContext).not.toBeNull());

    // Admin reset student
    await act(async () => {
      await accountSyncService.resetToFirstLogin('2023mlt042', 'student');
    });

    // Student activates with DOB (15/08/2004) and new secure password
    let activateRes: any;
    await act(async () => {
      activateRes = await authContext.studentFirstLogin(
        '2023mlt042',
        '15/08/2004',
        'MyNewPass#2026'
      );
    });

    expect(activateRes.success).toBe(true);
    expect(activateRes.user?.role).toBe('student');

    // Now try logging in with the OLD password
    let oldLoginRes: any;
    await act(async () => {
      oldLoginRes = await authContext.login('2023mlt042', 'Student#Pass2026');
    });
    expect(oldLoginRes.success).toBe(false);
    expect(oldLoginRes.error).toBe('Invalid password.');

    // Log in with NEW password
    let newLoginRes: any;
    await act(async () => {
      newLoginRes = await authContext.login('2023mlt042', 'MyNewPass#2026');
    });
    expect(newLoginRes.success).toBe(true);
    expect(newLoginRes.user?.role).toBe('student');
  });

  it('3. Admin temporary password invalidates old password and allows only temporary password', async () => {
    let authContext: any = null;
    renderAuth((a) => {
      authContext = a;
    });

    await waitFor(() => expect(authContext).not.toBeNull());

    // Admin sets temporary password
    await act(async () => {
      await accountSyncService.setTemporaryPassword('2023mlt042', 'TempKey#9999!', 'student');
    });

    // Attempt login with old password fails
    let oldRes: any;
    await act(async () => {
      oldRes = await authContext.login('2023mlt042', 'Student#Pass2026');
    });
    expect(oldRes.success).toBe(false);
    expect(oldRes.error).toContain('Invalid password');

    // Attempt login with temporary password succeeds and flags must_change_password
    let tempRes: any;
    await act(async () => {
      tempRes = await authContext.login('2023mlt042', 'TempKey#9999!');
    });
    expect(tempRes.success).toBe(true);
    expect(tempRes.user?.must_change_password).toBe(true);
  });

  it('4. Teacher first-time activation succeeds with valid username and phone', async () => {
    await accountSyncService.updateAccount('prof_kumar', {
      identifier: 'prof_kumar',
      role: 'teacher',
      name: 'Prof. Suresh Kumar',
      phone: '9845001122',
      status: 'active',
      firstLoginRequired: true,
    });

    let authContext: any = null;
    renderAuth((a) => {
      authContext = a;
    });

    await waitFor(() => expect(authContext).not.toBeNull());

    // Teacher prof_kumar (phone in records is 9845001122) activates
    let res: any;
    await act(async () => {
      res = await authContext.teacherFirstLogin(
        'prof_kumar',
        '9845001122',
        'ProfNewSecret#2026'
      );
    });

    expect(res.success).toBe(true);
    expect(res.user?.role).toBe('teacher');

    // Old teacher password Teacher#Pass2026 is invalidated!
    let oldLogin: any;
    await act(async () => {
      oldLogin = await authContext.login('prof_kumar', 'WrongOldPass#2026');
    });
    expect(oldLogin.success).toBe(false);
    expect(oldLogin.error).toBe('Invalid password.');

    // New teacher password succeeds!
    let newLogin: any;
    await act(async () => {
      newLogin = await authContext.login('prof_kumar', 'ProfNewSecret#2026');
    });
    expect(newLogin.success).toBe(true);
    expect(newLogin.user?.role).toBe('teacher');
  });

  it('5. Teacher first-time activation fails when phone number does not match records', async () => {
    await accountSyncService.updateAccount('prof_kumar', {
      identifier: 'prof_kumar',
      role: 'teacher',
      name: 'Prof. Suresh Kumar',
      phone: '9845001122',
      status: 'active',
      firstLoginRequired: true,
    });

    let authContext: any = null;
    renderAuth((a) => {
      authContext = a;
    });

    await waitFor(() => expect(authContext).not.toBeNull());

    // Teacher enters incorrect mobile number
    let res: any;
    await act(async () => {
      res = await authContext.teacherFirstLogin(
        'prof_kumar',
        '9999988888',
        'ProfNewSecret#2026'
      );
    });

    expect(res.success).toBe(false);
    expect(res.error).toContain('Registered mobile number does not match');
  });

  it('6. FirstLoginModal renders tabs for both Student and Teacher activation', () => {
    const queryClient = new QueryClient();
    render(
      <QueryClientProvider client={queryClient}>
        <MemoryRouter>
          <AuthProvider>
            <FirstLoginModal isOpen={true} onClose={() => {}} onSuccess={() => {}} />
          </AuthProvider>
        </MemoryRouter>
      </QueryClientProvider>
    );

    // Both tabs must be visible
    expect(screen.getByRole('tab', { name: /student activation/i })).toBeDefined();
    expect(screen.getByRole('tab', { name: /teacher activation/i })).toBeDefined();

    // Student fields active initially
    expect(screen.getByLabelText(/registration or admission number/i)).toBeDefined();
    expect(screen.getByLabelText(/date of birth/i)).toBeDefined();

    // Click Teacher Activation tab
    fireEvent.click(screen.getByRole('tab', { name: /teacher activation/i }));

    // Teacher fields should appear
    expect(screen.getByLabelText(/staff username/i)).toBeDefined();
    expect(screen.getByLabelText(/registered mobile number/i)).toBeDefined();
  });

  it('7. AttendanceTab displays that day\'s attendance first without a monthly calendar grid', async () => {
    const { AttendanceTab } = await import('../components/student/AttendanceTab');
    const queryClient = new QueryClient({ defaultOptions: { queries: { retry: false } } });

    render(
      <QueryClientProvider client={queryClient}>
        <MemoryRouter>
          <AuthProvider>
            <AttendanceTab
              studentId={1}
              enrollments={[
                {
                  enrollmentId: 10,
                  courseId: 1,
                  courseName: 'DMLT',
                  courseType: 'primary',
                  batchId: 2,
                  batchName: 'Batch 2024-26',
                },
              ]}
            />
          </AuthProvider>
        </MemoryRouter>
      </QueryClientProvider>
    );

    // "Today's Attendance" must be shown first
    await waitFor(() => {
      expect(screen.getByText("Today's Attendance")).toBeInTheDocument();
    });

    // Morning and Evening sessions must be visible
    expect(screen.getByText('Morning Session')).toBeInTheDocument();
    expect(screen.getByText('Evening Session')).toBeInTheDocument();

    // Date selector field must be present
    const dateInput = screen.getByLabelText(/choose attendance date/i);
    expect(dateInput).toBeInTheDocument();

    // NO monthly calendar grid header
    expect(screen.queryByText('Session Calendar')).not.toBeInTheDocument();
  });

  it('8. Student can select date to view day-wise attendance and return to today', async () => {
    const { AttendanceTab } = await import('../components/student/AttendanceTab');
    const queryClient = new QueryClient({ defaultOptions: { queries: { retry: false } } });

    render(
      <QueryClientProvider client={queryClient}>
        <MemoryRouter>
          <AuthProvider>
            <AttendanceTab
              studentId={1}
              enrollments={[
                {
                  enrollmentId: 10,
                  courseId: 1,
                  courseName: 'DMLT',
                  courseType: 'primary',
                  batchId: 2,
                  batchName: 'Batch 2024-26',
                },
              ]}
            />
          </AuthProvider>
        </MemoryRouter>
      </QueryClientProvider>
    );

    await waitFor(() => {
      expect(screen.getByText("Today's Attendance")).toBeInTheDocument();
    });

    // Pick past date 2026-10-15
    const dateInput = screen.getByLabelText(/choose attendance date/i);
    fireEvent.change(dateInput, { target: { value: '2026-10-15' } });

    // Heading switches to Day-wise Attendance and shows Back to Today
    await waitFor(() => {
      expect(screen.getByText('Day-wise Attendance')).toBeInTheDocument();
      expect(screen.getByText('Back to Today')).toBeInTheDocument();
    });

    // Click Back to Today
    fireEvent.click(screen.getByText('Back to Today'));

    // Returns to Today's Attendance
    await waitFor(() => {
      expect(screen.getByText("Today's Attendance")).toBeInTheDocument();
    });
  });
});
