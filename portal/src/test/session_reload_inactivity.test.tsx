// src/test/session_reload_inactivity.test.tsx
// Verifies session persistence across reload and 5-day inactivity policy for Student and Teacher portals

import React from 'react';
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, waitFor } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { MemoryRouter } from 'react-router-dom';
import { AuthProvider, useAuth } from '../context/AuthContext';
import { OnlineStatusProvider } from '../context/OnlineStatusContext';
import { supabase } from '../lib/supabase';
import { AppRoutes } from '../App';
import type { AuthUser, UserRole, UserProfile } from '../types';

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

function renderPortal(initialRoute = '/') {
  const queryClient = createTestQueryClient();
  return render(
    <QueryClientProvider client={queryClient}>
      <OnlineStatusProvider>
        <MemoryRouter initialEntries={[initialRoute]}>
          <AuthProvider>
            <AppRoutes />
          </AuthProvider>
        </MemoryRouter>
      </OnlineStatusProvider>
    </QueryClientProvider>
  );
}

describe('Session Reload & 5-Day Inactivity Verification', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    localStorage.clear();
    sessionStorage.clear();
  });

  it('1. Student session survives browser reload without redirecting to login', async () => {
    const studentUser: AuthUser = {
      id: 'student-uuid-1',
      email: '2023mlt042@students.mips.invalid',
      role: 'student',
      must_change_password: false,
      first_login_required: false,
    };
    const studentProfile: UserProfile = {
      id: 'student-uuid-1',
      user_id: 'student-uuid-1',
      role: 'student',
      active: true,
      name: 'Mohammed Hamiz',
      registration_number: '2023MLT042',
    };

    // Simulate active session stored in localStorage (e.g. 2 hours ago < 5 days)
    localStorage.setItem('mips_portal_user', JSON.stringify(studentUser));
    localStorage.setItem('mips_portal_role', 'student');
    localStorage.setItem('mips_portal_profile', JSON.stringify(studentProfile));
    localStorage.setItem('mips_portal_last_active', (Date.now() - 2 * 60 * 60 * 1000).toString());

    renderPortal('/student');

    // Should NOT redirect to /login
    expect(screen.queryByText(/welcome back/i)).not.toBeInTheDocument();
    expect(screen.queryByText(/please enter your credentials to access the erp/i)).not.toBeInTheDocument();

    // Verify activity timestamp refreshed
    const updatedTime = parseInt(localStorage.getItem('mips_portal_last_active') || '0', 10);
    expect(Date.now() - updatedTime).toBeLessThan(10000);
  });

  it('2. Teacher session survives browser reload without redirecting to login', async () => {
    const teacherUser: AuthUser = {
      id: 'teacher-uuid-1',
      email: 'prof_kumar@teachers.mips.invalid',
      role: 'teacher',
      must_change_password: false,
      first_login_required: false,
    };
    const teacherProfile: UserProfile = {
      id: 'teacher-uuid-1',
      user_id: 'teacher-uuid-1',
      role: 'teacher',
      active: true,
      name: 'Prof. Suresh Kumar',
    };

    // Simulate active session stored in localStorage (e.g. 1 day ago < 5 days)
    localStorage.setItem('mips_portal_user', JSON.stringify(teacherUser));
    localStorage.setItem('mips_portal_role', 'teacher');
    localStorage.setItem('mips_portal_profile', JSON.stringify(teacherProfile));
    localStorage.setItem('mips_portal_last_active', (Date.now() - 24 * 60 * 60 * 1000).toString());

    renderPortal('/teacher');

    // Should NOT redirect to /login
    expect(screen.queryByText(/welcome back/i)).not.toBeInTheDocument();

    // Verify localStorage retains teacher user and role
    expect(localStorage.getItem('mips_portal_role')).toBe('teacher');
    expect(localStorage.getItem('mips_portal_user')).toContain('prof_kumar');
  });

  it('3. Session expires after 5 days of inactivity on reload and shows 5-day inactivity notice', async () => {
    const studentUser: AuthUser = {
      id: 'student-uuid-1',
      email: '2023mlt042@students.mips.invalid',
      role: 'student',
      must_change_password: false,
      first_login_required: false,
    };

    // Inactive for 5 days and 2 hours (> 5 * 24 * 60 * 60 * 1000)
    const fiveDaysTwoHoursMs = (5 * 24 + 2) * 60 * 60 * 1000;
    localStorage.setItem('mips_portal_user', JSON.stringify(studentUser));
    localStorage.setItem('mips_portal_role', 'student');
    localStorage.setItem('mips_portal_last_active', (Date.now() - fiveDaysTwoHoursMs).toString());

    renderPortal('/student');

    // Expired session should be cleared from localStorage
    await waitFor(() => {
      expect(localStorage.getItem('mips_portal_user')).toBeNull();
      expect(localStorage.getItem('mips_portal_role')).toBeNull();
    });

    // Should display the 5-day inactivity warning banner
    await waitFor(() => {
      expect(
        screen.getByText(/You were signed out due to 5 days of inactivity/i)
      ).toBeInTheDocument();
    });
  });

  it('4. Supabase INITIAL_SESSION firing with null does not log out an active local session', async () => {
    const teacherUser: AuthUser = {
      id: 'teacher-uuid-2',
      email: 'fatima@teachers.mips.invalid',
      role: 'teacher',
      must_change_password: false,
      first_login_required: false,
    };

    localStorage.setItem('mips_portal_user', JSON.stringify(teacherUser));
    localStorage.setItem('mips_portal_role', 'teacher');
    localStorage.setItem('mips_portal_last_active', Date.now().toString());

    let authStateCallback: any = null;
    vi.spyOn(supabase.auth, 'onAuthStateChange').mockImplementation((cb: any) => {
      authStateCallback = cb;
      return { data: { subscription: { unsubscribe: vi.fn() } } } as any;
    });

    renderPortal('/teacher');

    // Simulate Supabase client dispatching INITIAL_SESSION with session = null
    if (authStateCallback) {
      authStateCallback('INITIAL_SESSION', null);
    }

    // Local storage session must still be intact!
    expect(localStorage.getItem('mips_portal_user')).not.toBeNull();
    expect(localStorage.getItem('mips_portal_role')).toBe('teacher');
  });
});
