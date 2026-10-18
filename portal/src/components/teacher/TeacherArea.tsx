// src/components/teacher/TeacherArea.tsx
// Complete Teacher Portal Container with Attendance, Marks Entry, Personal Timetable & Profile

import React, { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { useAuth } from '../../context/AuthContext';
import { teacherService } from '../../services/teacherService';
import { PortalHeader, TabItem } from '../layout/PortalHeader';
import { NotificationDrawer } from '../notifications/NotificationDrawer';
import { TeacherAttendanceTab } from './TeacherAttendanceTab';
import { TeacherMarksTab } from './TeacherMarksTab';
import { TeacherTimetableTab } from './TeacherTimetableTab';
import { TeacherProfileTab } from './TeacherProfileTab';
import { LoadingSkeleton } from '../common/LoadingSkeleton';
import { ErrorRetry } from '../common/ErrorRetry';
import { CheckSquare, Award, Calendar, User } from 'lucide-react';

const TEACHER_TABS: TabItem[] = [
  { id: 'attendance', label: 'Attendance', icon: <CheckSquare className="w-4 h-4" /> },
  { id: 'timetable', label: 'Timetable', icon: <Calendar className="w-4 h-4" /> },
  { id: 'profile', label: 'Profile', icon: <User className="w-4 h-4" /> },
];

export const TeacherArea: React.FC = () => {
  const { user } = useAuth();
  const [activeTab, setActiveTab] = useState('attendance');
  const [isNotificationOpen, setIsNotificationOpen] = useState(false);

  // Fetch Teacher Profile & Allocations
  const {
    data: teacherProfile,
    isLoading,
    error,
    refetch,
    isFetching,
  } = useQuery({
    queryKey: ['teacherProfile', user?.id],
    queryFn: () => (user?.id ? teacherService.getTeacherProfile(user.id) : Promise.reject('No user')),
    enabled: Boolean(user?.id),
  });

  return (
    <div className="min-h-screen bg-pageBg flex flex-col selection:bg-focusRing selection:text-navy">
      {/* Top Header with Tab Navigation and Notification Bell */}
      <PortalHeader
        tabs={TEACHER_TABS}
        activeTab={activeTab}
        onTabChange={(tabId) => setActiveTab(tabId)}
        onOpenNotifications={() => setIsNotificationOpen(true)}
      />

      {/* Slide-out Notification Drawer */}
      <NotificationDrawer
        isOpen={isNotificationOpen}
        onClose={() => setIsNotificationOpen(false)}
        onNavigateTab={(tabId) => setActiveTab(tabId)}
      />

      {/* Main Content Area - Overlaps Navy Header slightly */}
      <main className="flex-1 -mt-3 px-4 sm:px-6 pb-12">
        <div className="max-w-[1040px] mx-auto">
          {isLoading ? (
            <LoadingSkeleton type="card" rows={5} />
          ) : error || !teacherProfile ? (
            <ErrorRetry
              message="Failed to load faculty credentials. Please verify your connection."
              onRetry={() => refetch()}
              isRetrying={isFetching}
            />
          ) : (
            <>
              {activeTab === 'attendance' && (
                <TeacherAttendanceTab teacherId={teacherProfile.id} />
              )}

              {activeTab === 'timetable' && (
                <TeacherTimetableTab
                  teacherId={teacherProfile.id}
                  teacherName={teacherProfile.name}
                />
              )}

              {activeTab === 'profile' && (
                <TeacherProfileTab profile={teacherProfile} />
              )}
            </>
          )}
        </div>
      </main>

      <footer className="py-4 text-center text-xs text-muted border-t border-cardBorder bg-white">
        © {new Date().getFullYear()} Malabar Institute of Paramedical Science. Faculty Portal.
      </footer>
    </div>
  );
};
