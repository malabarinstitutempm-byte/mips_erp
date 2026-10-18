// src/components/notifications/NotificationDrawer.tsx
// Notification slide-out drawer with deep-linking & mark-as-read

import React from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { useAuth } from '../../context/AuthContext';
import { studentService } from '../../services/studentService';
import { formatDate, formatDateTime } from '../../lib/formatters';
import {
  Bell,
  X,
  Award,
  IndianRupee,
  Clock,
  Calendar,
  Info,
  CheckCheck,
  AlertCircle,
  ExternalLink,
} from 'lucide-react';
import type { NotificationItem } from '../../types';

interface NotificationDrawerProps {
  isOpen: boolean;
  onClose: () => void;
  onNavigateTab: (tabId: string) => void;
}

export const NotificationDrawer: React.FC<NotificationDrawerProps> = ({
  isOpen,
  onClose,
  onNavigateTab,
}) => {
  const { user, refreshNotifications } = useAuth();
  const queryClient = useQueryClient();

  const { data: notifications = [], isLoading, error, refetch } = useQuery({
    queryKey: ['notifications', user?.id],
    queryFn: () => (user?.id ? studentService.getNotifications(user.id) : Promise.resolve([])),
    enabled: isOpen && Boolean(user?.id),
  });

  const markReadMutation = useMutation({
    mutationFn: (id: number) => studentService.markNotificationRead(id),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['notifications', user?.id] });
      refreshNotifications();
    },
  });

  const markAllReadMutation = useMutation({
    mutationFn: () => (user?.id ? studentService.markAllNotificationsRead(user.id) : Promise.resolve()),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['notifications', user?.id] });
      refreshNotifications();
    },
  });

  if (!isOpen) return null;

  const handleNotificationClick = (item: NotificationItem) => {
    if (!item.read_at) {
      markReadMutation.mutate(item.id);
    }

    // Deep-link matching prompt rule:
    // exam published -> Results, fee reminder -> Fees, timetable -> Timetable, low attendance / promotion -> Attendance
    const cat = item.category?.toLowerCase() || '';
    const title = item.title?.toLowerCase() || '';
    const msg = item.message?.toLowerCase() || '';

    if (cat === 'exam' || title.includes('result') || title.includes('exam')) {
      onNavigateTab('results');
    } else if (cat === 'fee_reminder' || title.includes('fee') || title.includes('balance')) {
      onNavigateTab('fees');
    } else if (cat === 'timetable' || title.includes('timetable') || title.includes('schedule')) {
      onNavigateTab('timetable');
    } else if (
      title.includes('attendance') ||
      title.includes('shortage') ||
      title.includes('promotion') ||
      title.includes('semester') ||
      msg.includes('semester') ||
      msg.includes('promotion')
    ) {
      onNavigateTab('attendance');
    }

    onClose();
  };

  const getCategoryIcon = (category: string) => {
    switch (category) {
      case 'exam':
        return <Award className="w-4 h-4 text-primary" />;
      case 'fee_reminder':
        return <IndianRupee className="w-4 h-4 text-emerald-600" />;
      case 'timetable':
        return <Clock className="w-4 h-4 text-indigo-600" />;
      case 'programme':
        return <Calendar className="w-4 h-4 text-purple-600" />;
      default:
        return <Info className="w-4 h-4 text-teal" />;
    }
  };

  const unreadCount = notifications.filter((n) => !n.read_at).length;

  return (
    <div
      className="fixed inset-0 z-50 overflow-hidden bg-navy/50 backdrop-blur-sm animate-fade-in"
      role="dialog"
      aria-modal="true"
      aria-labelledby="notification-drawer-title"
    >
      <div className="absolute inset-y-0 right-0 max-w-full flex pl-10">
        <div className="w-screen max-w-md bg-white border-l border-cardBorder shadow-2xl flex flex-col">
          {/* Header */}
          <div className="px-5 py-4 border-b border-cardBorder bg-surface flex items-center justify-between">
            <div className="flex items-center gap-2.5">
              <div className="w-8 h-8 rounded-xl bg-navy text-white flex items-center justify-center">
                <Bell className="w-4 h-4 text-teal" />
              </div>
              <div>
                <h3 id="notification-drawer-title" className="font-sora font-bold text-sm text-navy">
                  Notifications
                </h3>
                <p className="text-[11px] text-muted">
                  {unreadCount > 0 ? `${unreadCount} unread broadcast(s)` : 'All caught up'}
                </p>
              </div>
            </div>

            <div className="flex items-center gap-1">
              {unreadCount > 0 && (
                <button
                  type="button"
                  onClick={() => markAllReadMutation.mutate()}
                  disabled={markAllReadMutation.isPending}
                  className="px-2.5 py-1.5 rounded-lg text-xs font-semibold text-primary hover:bg-primary/10 transition-colors flex items-center gap-1.5"
                  title="Mark all as read"
                >
                  <CheckCheck className="w-3.5 h-3.5" />
                  <span className="hidden sm:inline">Mark all read</span>
                </button>
              )}
              <button
                type="button"
                onClick={onClose}
                className="p-2 rounded-xl text-muted hover:text-navy hover:bg-slate-200/60 transition-colors"
                aria-label="Close notifications"
              >
                <X className="w-5 h-5" />
              </button>
            </div>
          </div>

          {/* List Content */}
          <div className="flex-1 overflow-y-auto p-4 space-y-2.5">
            {isLoading ? (
              <div className="space-y-3 p-4 animate-pulse">
                <div className="h-14 bg-slate-100 rounded-input" />
                <div className="h-14 bg-slate-100 rounded-input" />
                <div className="h-14 bg-slate-100 rounded-input" />
              </div>
            ) : error ? (
              <div className="p-6 text-center">
                <AlertCircle className="w-8 h-8 text-error-accent mx-auto mb-2" />
                <p className="text-xs text-muted mb-3">Failed to load notifications.</p>
                <button
                  type="button"
                  onClick={() => refetch()}
                  className="text-xs font-bold text-primary hover:underline"
                >
                  Retry
                </button>
              </div>
            ) : notifications.length === 0 ? (
              <div className="py-16 text-center px-4">
                <div className="w-12 h-12 rounded-2xl bg-slate-100 text-muted flex items-center justify-center mx-auto mb-3">
                  <Bell className="w-6 h-6" />
                </div>
                <h4 className="font-sora font-semibold text-sm text-navy">No Announcements Yet</h4>
                <p className="text-xs text-muted mt-1 max-w-xs mx-auto">
                  Institutional messages, examination notices, and fee reminders will appear here.
                </p>
              </div>
            ) : (
              notifications.map((item) => {
                const isUnread = !item.read_at;
                return (
                  <div
                    key={item.id}
                    onClick={() => handleNotificationClick(item)}
                    className={`p-3.5 rounded-input border transition-all cursor-pointer relative ${
                      isUnread
                        ? 'bg-primary/5 border-primary/20 hover:border-primary/40 shadow-sm'
                        : 'bg-white border-cardBorder hover:border-slate-300'
                    }`}
                  >
                    <div className="flex items-start gap-3">
                      <div className="w-8 h-8 rounded-lg bg-surface border border-cardBorder flex items-center justify-center shrink-0 mt-0.5">
                        {getCategoryIcon(item.category)}
                      </div>

                      <div className="flex-1 min-w-0">
                        <div className="flex items-center justify-between gap-2">
                          <h4 className={`text-xs font-sora truncate ${isUnread ? 'font-bold text-navy' : 'font-medium text-slate-800'}`}>
                            {item.title}
                          </h4>
                          <span className="text-[10px] text-muted shrink-0 whitespace-nowrap">
                            {formatDateTime(item.created_at)}
                          </span>
                        </div>

                        <p className="text-xs text-muted mt-1 leading-relaxed line-clamp-3">
                          {item.message}
                        </p>

                        <div className="mt-2 flex items-center gap-1 text-[11px] font-semibold text-primary">
                          <span>View details</span>
                          <ExternalLink className="w-3 h-3" />
                        </div>
                      </div>

                      {isUnread && (
                        <div className="w-2 h-2 rounded-full bg-primary shrink-0 mt-1.5" />
                      )}
                    </div>
                  </div>
                );
              })
            )}
          </div>
        </div>
      </div>
    </div>
  );
};
