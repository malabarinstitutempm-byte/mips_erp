// portal/src/services/realtimeSyncService.ts
// Cross-User Visibility Realtime Layer (Phase D4)

import { QueryClient } from '@tanstack/react-query';
import { supabase } from '../lib/supabase';
import type { AuthUser, UserRole } from '../types';

export class RealtimeSyncService {
  private channel: any = null;
  private queryClient: QueryClient | null = null;
  private user: AuthUser | null = null;
  private role: UserRole | null = null;
  private onDeactivateCallback?: () => void;

  public init(
    queryClient: QueryClient,
    user: AuthUser | null,
    role: UserRole | null,
    onDeactivate?: () => void
  ) {
    this.queryClient = queryClient;
    this.user = user;
    this.role = role;
    this.onDeactivateCallback = onDeactivate;

    if (!user || !role) {
      this.cleanup();
      return;
    }

    this.subscribe();

    // Tab visibility handling (conserve connections on free plan)
    document.removeEventListener('visibilitychange', this.handleVisibilityChange);
    document.addEventListener('visibilitychange', this.handleVisibilityChange);
  }

  private handleVisibilityChange = () => {
    if (document.hidden) {
      this.cleanup();
    } else {
      // Re-subscribe and refetch when user refocuses
      if (this.user && this.role && this.queryClient) {
        this.subscribe();
        this.refetchActiveQueries();
      }
    }
  };

  private subscribe() {
    this.cleanup();

    this.channel = supabase
      .channel('public:app_events')
      .on(
        'postgres_changes',
        { event: 'INSERT', schema: 'public', table: 'app_events' },
        (payload: any) => {
          this.handleEvent(payload.new);
        }
      )
      .subscribe((status: string) => {
        if (status === 'SUBSCRIBED') {
          console.log('[Portal Realtime] Subscribed to app_events');
        }
      });
  }

  private handleEvent(record: any) {
    if (!record || !this.queryClient || !this.user) return;

    const topic = record.topic || '';
    const domain = record.domain || '';
    const action = record.action || '';
    const actorName = record.actor_name || 'Administrator';
    const metadata = record.metadata || {};

    const studentId = (this.user as any).student_id || (this.user as any).id;
    const teacherId = (this.user as any).teacher_id || (this.user as any).id;
    const batchId = (this.user as any).batch_id;

    // Audience check
    const isForMe =
      topic === 'global' ||
      (this.role === 'teacher' && (topic === 'teachers' || topic === `teacher:${teacherId}`)) ||
      (this.role === 'student' &&
        (topic === 'students' || topic === `student:${studentId}` || (batchId && topic === `batch:${batchId}`)));

    if (!isForMe) return;

    console.log(`[Portal Realtime] Event received: ${domain}.${action} by ${actorName}`);

    // Invalidate specific queries based on domain
    switch (domain) {
      case 'course':
        this.queryClient.invalidateQueries({ queryKey: ['courses'] });
        break;

      case 'batch':
        this.queryClient.invalidateQueries({ queryKey: ['batches'] });
        this.queryClient.invalidateQueries({ queryKey: ['teacherBatches'] });
        break;

      case 'student':
        if (this.role === 'student') {
          this.queryClient.invalidateQueries({ queryKey: ['studentProfile'] });
        }
        break;

      case 'payment':
        if (this.role === 'student') {
          this.queryClient.invalidateQueries({ queryKey: ['studentFees'] });
        }
        break;

      case 'attendance':
        if (this.role === 'teacher') {
          this.queryClient.invalidateQueries({ queryKey: ['teacherSessions'] });
          this.queryClient.invalidateQueries({ queryKey: ['attendanceSlotStatus'] });
        } else if (this.role === 'student') {
          this.queryClient.invalidateQueries({ queryKey: ['studentAttendance'] });
        }
        break;

      case 'exam':
        if (this.role === 'student') {
          this.queryClient.invalidateQueries({ queryKey: ['studentResults'] });
          this.queryClient.invalidateQueries({ queryKey: ['notifications'] });
        }
        break;

      case 'timetable':
        if (this.role === 'teacher') {
          this.queryClient.invalidateQueries({ queryKey: ['teacherTimetable'] });
        } else if (this.role === 'student') {
          this.queryClient.invalidateQueries({ queryKey: ['studentTimetable'] });
        }
        break;

      case 'announcement':
        this.queryClient.invalidateQueries({ queryKey: ['notifications'] });
        break;

      case 'account':
        if (action === 'deactivate') {
          if (this.onDeactivateCallback) {
            this.onDeactivateCallback();
          }
        }
        break;
    }
  }

  private refetchActiveQueries() {
    if (!this.queryClient) return;
    this.queryClient.refetchQueries({ type: 'active' });
  }

  public cleanup() {
    if (this.channel) {
      supabase.removeChannel(this.channel);
      this.channel = null;
    }
  }
}

export const realtimeSyncService = new RealtimeSyncService();
