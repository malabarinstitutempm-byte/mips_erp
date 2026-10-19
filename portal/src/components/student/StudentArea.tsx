// src/components/student/StudentArea.tsx
// Complete Student Portal Container with Real-time Tab Switching, Notifications & Deep-linking

import React, { useState, useEffect, useMemo } from 'react';
import { useQuery } from '@tanstack/react-query';
import { studentService } from '../../services/studentService';
import { PortalHeader, TabItem } from '../layout/PortalHeader';
import { NotificationDrawer } from '../notifications/NotificationDrawer';
import { ResultsTab } from './ResultsTab';
import { FeesTab } from './FeesTab';
import { AttendanceTab } from './AttendanceTab';
import { TimetableTab } from './TimetableTab';
import { ProfileTab } from './ProfileTab';
import { LoadingSkeleton } from '../common/LoadingSkeleton';
import { ErrorRetry } from '../common/ErrorRetry';
import { useAuth } from '../../context/AuthContext';
import { formatDate } from '../../lib/formatters';
import { Award, IndianRupee, CalendarCheck, Calendar, User, GraduationCap, Lock, LogOut } from 'lucide-react';

const STUDENT_TABS: TabItem[] = [
  { id: 'attendance', label: 'Attendance', icon: <CalendarCheck className="w-4 h-4" /> },
  { id: 'results', label: 'Results', icon: <Award className="w-4 h-4" /> },
  { id: 'fees', label: 'Fees', icon: <IndianRupee className="w-4 h-4" /> },
  { id: 'timetable', label: 'Timetable', icon: <Calendar className="w-4 h-4" /> },
  { id: 'profile', label: 'Profile', icon: <User className="w-4 h-4" /> },
];

export const StudentArea: React.FC = () => {
  const { logout } = useAuth();
  const [activeTab, setActiveTab] = useState('attendance');
  const [isNotificationOpen, setIsNotificationOpen] = useState(false);

  // Fetch Student Profile and active/completed enrollments (Primary & Skill)
  const {
    data: studentData,
    isLoading,
    error,
    refetch,
    isFetching,
  } = useQuery({
    queryKey: ['studentProfile'],
    queryFn: () => studentService.getStudentProfile(),
  });

  const todayStr = new Date().toISOString().split('T')[0];
  const accessUntil = studentData?.profile?.access_until;
  const isAccessExpired = Boolean(accessUntil && accessUntil < todayStr);

  const isStudentCompleted = studentData?.profile?.status === 'completed';
  const completedEnrollments = useMemo(() => {
    return (studentData?.enrollments || []).filter(
      (e) => e.status === 'completed' || isStudentCompleted
    );
  }, [studentData?.enrollments, isStudentCompleted]);

  // Hide the Timetable tab for completed students
  const visibleTabs = useMemo(() => {
    if (isStudentCompleted) {
      return STUDENT_TABS.filter((t) => t.id !== 'timetable');
    }
    return STUDENT_TABS;
  }, [isStudentCompleted]);

  // If student is completed and on timetable, redirect to attendance
  useEffect(() => {
    if (isStudentCompleted && activeTab === 'timetable') {
      setActiveTab('attendance');
    }
  }, [isStudentCompleted, activeTab]);

  // Dedicated "Access Has Ended" screen when past access_until (Phase 9E)
  if (isAccessExpired) {
    return (
      <div className="min-h-screen bg-pageBg flex flex-col items-center justify-center p-4 selection:bg-focusRing selection:text-navy">
        <div className="max-w-md w-full bg-white rounded-card-lg border border-cardBorder shadow-card p-8 text-center space-y-4">
          <div className="w-16 h-16 mx-auto rounded-full bg-rose-50 border border-rose-100 flex items-center justify-center text-rose-600 shadow-sm">
            <Lock className="w-7 h-7" />
          </div>
          <h2 className="text-xl font-sora font-bold text-navy">Access Has Ended</h2>
          <p className="text-sm text-muted leading-relaxed">
            Your access has ended. Please contact the college office.
          </p>
          <div className="pt-2">
            <button
              onClick={() => logout()}
              className="inline-flex items-center justify-center gap-2 px-6 py-2.5 bg-navy text-white text-sm font-semibold rounded-card hover:bg-navy-dark transition-colors shadow-sm"
            >
              <LogOut className="w-4 h-4" />
              Sign Out
            </button>
          </div>
        </div>
      </div>
    );
  }

  const currentSemester = studentData?.profile?.current_semester || 1;
  const currentYear = studentData?.profile?.current_year || (currentSemester > 0 ? Math.ceil(currentSemester / 2) : 1);
  const isYearWise = studentData?.profile?.course_structure === 'year';
  const headerSubtitle = isStudentCompleted
    ? 'Completed'
    : isYearWise
    ? `Year ${currentYear}`
    : `Semester ${currentSemester} · Year ${currentYear}`;

  return (
    <div className="min-h-screen bg-pageBg flex flex-col selection:bg-focusRing selection:text-navy">
      {/* Top Header with Tab Navigation and Notification Bell */}
      <PortalHeader
        tabs={visibleTabs}
        activeTab={activeTab}
        onTabChange={(tabId) => setActiveTab(tabId)}
        onOpenNotifications={() => setIsNotificationOpen(true)}
        subtitle={headerSubtitle}
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
          ) : error || !studentData ? (
            <ErrorRetry
              message="Failed to load student profile details. Please verify your connection."
              onRetry={() => refetch()}
              isRetrying={isFetching}
            />
          ) : (
            <>
              {/* Completed Student / Enrollment Banner */}
              {isStudentCompleted ? (
                <div className="mb-6 p-4 bg-sky-50 border border-sky-200 rounded-card-lg shadow-sm flex items-start gap-3.5">
                  <div className="p-2 rounded-xl bg-sky-100 text-sky-700 shrink-0 mt-0.5">
                    <GraduationCap className="w-5 h-5" />
                  </div>
                  <div className="flex-1 min-w-0">
                    <div className="flex flex-wrap items-center justify-between gap-2">
                      <h3 className="font-sora font-bold text-sm text-sky-950">
                        Course completed on {formatDate(studentData.profile.completed_on || completedEnrollments[0]?.completedOn || todayStr)}
                      </h3>
                      <span className="px-2.5 py-0.5 rounded-full text-[10px] font-bold uppercase tracking-wider bg-sky-200 text-sky-900">
                        Completed
                      </span>
                    </div>
                    <p className="mt-1 text-xs text-sky-800 leading-relaxed">
                      Congratulations on completing your program! Your results, marks cards, fee receipts, and attendance history remain accessible for your records.
                    </p>
                    {studentData.profile.access_until && (
                      <div className="mt-2 text-xs font-medium text-sky-900 bg-sky-100/70 rounded-md px-2.5 py-1.5 inline-block">
                        Portal access is valid until <span className="font-bold">{formatDate(studentData.profile.access_until)}</span>. Please download your results and receipts before this date.
                      </div>
                    )}
                  </div>
                </div>
              ) : completedEnrollments.length > 0 ? (
                completedEnrollments.map((enr) => (
                  <div key={enr.enrollmentId} className="mb-4 p-3.5 bg-sky-50 border border-sky-200 rounded-card-lg shadow-sm flex items-start gap-3">
                    <GraduationCap className="w-5 h-5 text-sky-700 shrink-0 mt-0.5" />
                    <div className="flex-1 min-w-0">
                      <div className="font-sora font-semibold text-xs text-sky-950">
                        Course completed on {formatDate(enr.completedOn || todayStr)} ({enr.courseName})
                      </div>
                      <p className="text-[11px] text-sky-800 mt-0.5">
                        Academic enrollment for {enr.batchName} has been marked completed.
                      </p>
                    </div>
                  </div>
                ))
              ) : null}

              {activeTab === 'results' && (
                <ResultsTab
                  studentId={studentData.profile.id}
                  studentName={studentData.profile.name}
                  registrationNumber={studentData.profile.registration_number}
                  admissionNumber={studentData.profile.admission_number}
                />
              )}

              {activeTab === 'fees' && (
                <FeesTab
                  studentId={studentData.profile.id}
                  studentName={studentData.profile.name}
                  registrationNumber={studentData.profile.registration_number}
                  admissionNumber={studentData.profile.admission_number}
                  courseName={studentData.profile.course_name}
                  batchName={studentData.profile.batch_name}
                />
              )}

              {activeTab === 'attendance' && (
                <AttendanceTab
                  studentId={studentData.profile.id}
                  enrollments={studentData.enrollments}
                  isCompleted={isStudentCompleted || studentData.enrollments.some((e) => e.courseType === 'primary' && e.status === 'completed')}
                  currentSemester={currentSemester}
                  currentYear={currentYear}
                />
              )}

              {activeTab === 'timetable' && (
                <TimetableTab enrollments={studentData.enrollments} />
              )}

              {activeTab === 'profile' && (
                <ProfileTab
                  profile={studentData.profile}
                  enrollments={studentData.enrollments}
                />
              )}
            </>
          )}
        </div>
      </main>

      <footer className="py-4 text-center text-xs text-muted border-t border-cardBorder bg-white">
        © {new Date().getFullYear()} Malabar Institute of Paramedical Science. All rights reserved.
      </footer>
    </div>
  );
};
