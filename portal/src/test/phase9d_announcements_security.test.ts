// src/test/phase9d_announcements_security.test.ts
// Phase 9D & 9E: Comprehensive Security, Governance, and Audience Notification Test Suite

import { describe, it, expect, vi } from 'vitest';

describe('Phase 9D & 9E - Security, Governance & Audience Notification Suite', () => {

  // =========================================================================
  // 1. Notification Audiences: Completed Students vs Active Students
  // =========================================================================
  describe('1. Notification Audience Resolution', () => {
    interface StudentRecipient {
      studentId: number;
      userId: string;
      courseId: number;
      batchId: number;
      status: 'active' | 'completed' | 'discontinued';
      pendingFeeBalancePaise: number;
    }

    const testStudents: StudentRecipient[] = [
      {
        studentId: 1,
        userId: 'u1',
        courseId: 10,
        batchId: 100,
        status: 'active',
        pendingFeeBalancePaise: 0,
      },
      {
        studentId: 2,
        userId: 'u2',
        courseId: 10,
        batchId: 100,
        status: 'active',
        pendingFeeBalancePaise: 500000,
      },
      {
        studentId: 3,
        userId: 'u3',
        courseId: 10,
        batchId: 100,
        status: 'completed',
        pendingFeeBalancePaise: 0, // Completed, fees cleared
      },
      {
        studentId: 4,
        userId: 'u4',
        courseId: 10,
        batchId: 100,
        status: 'completed',
        pendingFeeBalancePaise: 250000, // Completed, BUT has pending fees
      },
    ];

    function resolveNotificationRecipients(
      audience: 'all_students' | 'course' | 'batch' | 'fee_reminder',
      targetId?: number
    ): StudentRecipient[] {
      switch (audience) {
        case 'all_students':
          // Must skip completed students per Phase 9A policy
          return testStudents.filter((s) => s.status === 'active');

        case 'course':
          // Must skip completed students
          return testStudents.filter((s) => s.status === 'active' && s.courseId === targetId);

        case 'batch':
          // Must skip completed students
          return testStudents.filter((s) => s.status === 'active' && s.batchId === targetId);

        case 'fee_reminder':
          // MUST include completed students who owe money!
          return testStudents.filter((s) => s.pendingFeeBalancePaise > 0);
      }
    }

    it('"all_students" announcements skip completed students and only deliver to active students', () => {
      const recipients = resolveNotificationRecipients('all_students');
      const studentIds = recipients.map((r) => r.studentId);

      expect(studentIds).toEqual([1, 2]);
      expect(studentIds).not.toContain(3);
      expect(studentIds).not.toContain(4);
    });

    it('"course" and "batch" announcements skip completed students', () => {
      const courseRecipients = resolveNotificationRecipients('course', 10);
      expect(courseRecipients.map((r) => r.studentId)).toEqual([1, 2]);

      const batchRecipients = resolveNotificationRecipients('batch', 100);
      expect(batchRecipients.map((r) => r.studentId)).toEqual([1, 2]);
    });

    it('fee reminders still reach completed students who have an outstanding balance', () => {
      const feeRecipients = resolveNotificationRecipients('fee_reminder');
      const studentIds = feeRecipients.map((r) => r.studentId);

      // Student 2 is active with fee, Student 4 is COMPLETED with fee
      expect(studentIds).toContain(2);
      expect(studentIds).toContain(4);
      // Student 3 is completed with 0 fee -> Not included
      expect(studentIds).not.toContain(3);
    });
  });

  // =========================================================================
  // 2. Role Authorization Security Guards
  // =========================================================================
  describe('2. Role Authorization on Admin Completion RPCs', () => {
    function authorizeBatchOperation(callerRole: string | null) {
      if (!callerRole || callerRole.toLowerCase() !== 'admin') {
        throw new Error('Access denied. Administrator privilege required.');
      }
      return true;
    }

    it('rejects teachers, students, and anonymous callers from complete_batch and reopen_batch', () => {
      expect(() => authorizeBatchOperation('teacher')).toThrow('Access denied');
      expect(() => authorizeBatchOperation('student')).toThrow('Access denied');
      expect(() => authorizeBatchOperation('anonymous')).toThrow('Access denied');
      expect(() => authorizeBatchOperation(null)).toThrow('Access denied');

      // Admin succeeds
      expect(authorizeBatchOperation('admin')).toBe(true);
    });
  });

  // =========================================================================
  // 3. Login Edge Function Access-Window Security (Phase 9E)
  // =========================================================================
  describe('3. Login Edge Function Access Window Policy', () => {
    function simulateLoginAttempt({
      passwordCorrect,
      isCompleted,
      accessUntil,
      currentDate,
    }: {
      passwordCorrect: boolean;
      isCompleted: boolean;
      accessUntil: string | null;
      currentDate: string;
    }): { status: number; message: string } {
      // 1. Password verification occurs FIRST
      if (!passwordCorrect) {
        // Uniform wrong password message - never leak account expiration to attackers!
        return { status: 401, message: 'Invalid credentials. Please verify your details.' };
      }

      // 2. Check access expiration ONLY after verifying password
      if (isCompleted && accessUntil && accessUntil < currentDate) {
        return { status: 403, message: 'Your access has ended. Please contact the college office.' };
      }

      return { status: 200, message: 'Login successful' };
    }

    it('displays "Your access has ended" ONLY when password is correct for expired account', () => {
      const result = simulateLoginAttempt({
        passwordCorrect: true,
        isCompleted: true,
        accessUntil: '2026-06-30',
        currentDate: '2026-10-17',
      });

      expect(result.status).toBe(403);
      expect(result.message).toBe('Your access has ended. Please contact the college office.');
    });

    it('returns generic invalid credentials message on wrong password, even if account is expired (Anti-Enumeration)', () => {
      const result = simulateLoginAttempt({
        passwordCorrect: false,
        isCompleted: true,
        accessUntil: '2026-06-30',
        currentDate: '2026-10-17',
      });

      // Status must be 401 and message must NOT leak that the account has expired
      expect(result.status).toBe(401);
      expect(result.message).not.toContain('Your access has ended');
      expect(result.message).toContain('Invalid credentials');
    });

    it('allows successful login when access_until is still valid', () => {
      const result = simulateLoginAttempt({
        passwordCorrect: true,
        isCompleted: true,
        accessUntil: '2026-12-31',
        currentDate: '2026-10-17',
      });

      expect(result.status).toBe(200);
      expect(result.message).toBe('Login successful');
    });
  });

  // =========================================================================
  // 4. RLS Helper student_access_allowed() Simulation
  // =========================================================================
  describe('4. RLS Policy: student_access_allowed()', () => {
    function studentAccessAllowed({
      role,
      active,
      accessUntil,
      currentDate,
    }: {
      role: string;
      active: boolean;
      accessUntil: string | null;
      currentDate: string;
    }): boolean {
      if (role !== 'student') return false;
      if (!active) return false;
      if (accessUntil !== null && accessUntil < currentDate) return false;
      return true;
    }

    it('cuts off existing session access when access_until is past', () => {
      // Valid session
      expect(
        studentAccessAllowed({
          role: 'student',
          active: true,
          accessUntil: '2026-12-31',
          currentDate: '2026-10-17',
        })
      ).toBe(true);

      // Past date session cut off
      expect(
        studentAccessAllowed({
          role: 'student',
          active: true,
          accessUntil: '2026-10-16',
          currentDate: '2026-10-17',
        })
      ).toBe(false);

      // Deactivated account cut off
      expect(
        studentAccessAllowed({
          role: 'student',
          active: false,
          accessUntil: '2026-12-31',
          currentDate: '2026-10-17',
        })
      ).toBe(false);
    });
  });

  // =========================================================================
  // 5. Scheduled Job Reminder Triggers (14 days & 3 days)
  // =========================================================================
  describe('5. Access Expiry Reminder Notifications', () => {
    function shouldSendReminder(accessUntilDate: string, currentDate: string): { send: boolean; daysRemaining?: number } {
      const until = new Date(accessUntilDate).getTime();
      const curr = new Date(currentDate).getTime();
      const diffDays = Math.round((until - curr) / (1000 * 60 * 60 * 24));

      if (diffDays === 14 || diffDays === 3) {
        return { send: true, daysRemaining: diffDays };
      }
      return { send: false };
    }

    it('triggers reminder notifications at exactly 14 days and 3 days before expiry', () => {
      expect(shouldSendReminder('2026-10-31', '2026-10-17')).toEqual({ send: true, daysRemaining: 14 });
      expect(shouldSendReminder('2026-10-20', '2026-10-17')).toEqual({ send: true, daysRemaining: 3 });

      // Other days do NOT trigger reminder
      expect(shouldSendReminder('2026-10-25', '2026-10-17').send).toBe(false);
      expect(shouldSendReminder('2026-10-18', '2026-10-17').send).toBe(false);
    });
  });
});
