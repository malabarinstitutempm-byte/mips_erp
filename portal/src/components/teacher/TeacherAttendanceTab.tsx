// src/components/teacher/TeacherAttendanceTab.tsx
// Faculty Attendance Portal: 3-step Primary Course Flow, Live Today's Board, My Sessions & Race-Safe Concurrency

import React, { useState, useEffect, useMemo } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  teacherService,
  PrimaryCourseWithBatches,
  SlotStatusItem,
  StudentAttendanceEntry,
  AttendanceSessionState,
  TeacherMySessionItem,
} from '../../services/teacherService';
import { formatDate, formatDateTime } from '../../lib/formatters';
import { LoadingSkeleton } from '../common/LoadingSkeleton';
import { EmptyState } from '../common/EmptyState';
import { ErrorRetry } from '../common/ErrorRetry';
import {
  CalendarCheck,
  Sun,
  Moon,
  Users,
  Search,
  CheckCircle2,
  Clock,
  AlertTriangle,
  Lock,
  Send,
  XCircle,
  HelpCircle,
  AlertCircle,
  Check,
  X,
  History,
  LayoutGrid,
  Ban,
  ChevronRight,
  BookOpen,
  Calendar,
  Sparkles,
} from 'lucide-react';
import { useOnlineStatus } from '../../context/OnlineStatusContext';

interface TeacherAttendanceTabProps {
  teacherId: number;
}

const NO_CLASS_REASONS = [
  'Institutional Holiday',
  'General Strike / Hartal',
  'Faculty on Approved Leave',
  'University Examination Day',
  'Clinical Training / Camp',
  'Inclement Weather / Emergency',
  'Other Administrative Reason',
];

export const TeacherAttendanceTab: React.FC<TeacherAttendanceTabProps> = ({ teacherId }) => {
  const queryClient = useQueryClient();
  const { isOnline } = useOnlineStatus();

  // Top Section Switcher: 'mark' | 'today_board' | 'my_sessions'
  const [activeSection, setActiveSection] = useState<'mark' | 'today_board' | 'my_sessions'>('mark');

  // Guided Marking Flow State
  const todayStr = new Date().toISOString().split('T')[0];
  const [selectedCourseId, setSelectedCourseId] = useState<number | null>(null);
  const [selectedBatchId, setSelectedBatchId] = useState<number | null>(null);
  const [selectedDate, setSelectedDate] = useState<string>(todayStr);
  const [selectedSlot, setSelectedSlot] = useState<'morning' | 'evening'>('morning');

  // Interactive Student Marking State
  const [searchQuery, setSearchQuery] = useState('');
  const [studentMarks, setStudentMarks] = useState<Record<number, 'present' | 'late' | 'absent' | 'leave'>>({});
  const [isSubmitModalOpen, setIsSubmitModalOpen] = useState(false);
  const [isNoClassModalOpen, setIsNoClassModalOpen] = useState(false);
  const [noClassReason, setNoClassReason] = useState(NO_CLASS_REASONS[0]);

  // Race condition or server banner state
  const [alreadyMarkedBanner, setAlreadyMarkedBanner] = useState<{
    markedBy: string;
    markedAt?: string;
    role?: string;
    message?: string;
  } | null>(null);

  const [feedbackMessage, setFeedbackMessage] = useState<{ type: 'success' | 'error'; text: string } | null>(null);

  // 1. Fetch Primary Courses & Batches (Universal open access)
  const {
    data: primaryCourses = [],
    isLoading: loadingCourses,
    error: coursesError,
    refetch: refetchCourses,
  } = useQuery({
    queryKey: ['teacherPrimaryCourses'],
    queryFn: () => teacherService.getPrimaryCoursesWithBatches(),
  });

  // Automatically select first course when loaded
  useEffect(() => {
    if (primaryCourses.length > 0 && selectedCourseId === null) {
      setSelectedCourseId(primaryCourses[0].courseId);
    }
  }, [primaryCourses, selectedCourseId]);

  // Batches for chosen course
  const currentCourse = useMemo(
    () => primaryCourses.find((c) => c.courseId === selectedCourseId),
    [primaryCourses, selectedCourseId]
  );
  const courseBatches = currentCourse?.batches || [];

  // Automatically select first batch when course changes
  useEffect(() => {
    if (courseBatches.length > 0) {
      if (!selectedBatchId || !courseBatches.some((b) => b.batchId === selectedBatchId)) {
        setSelectedBatchId(courseBatches[0].batchId);
      }
    } else {
      setSelectedBatchId(null);
    }
  }, [courseBatches, selectedBatchId]);

  // 2. Fetch Live Today's Slot Status Board
  const {
    data: slotStatuses = [],
    isLoading: loadingSlotStatus,
    refetch: refetchSlotStatus,
  } = useQuery({
    queryKey: ['attendanceSlotStatus', selectedDate],
    queryFn: () => teacherService.getAttendanceSlotStatus(selectedDate),
    refetchInterval: 30000, // Live poll every 30s
  });

  // Map slot status per batch
  const batchSlotStatusMap = useMemo(() => {
    const map = new Map<number, { morning?: SlotStatusItem; evening?: SlotStatusItem }>();
    slotStatuses.forEach((item) => {
      const entry = map.get(item.batch_id) || {};
      if (item.slot === 'morning') entry.morning = item;
      if (item.slot === 'evening') entry.evening = item;
      map.set(item.batch_id, entry);
    });
    return map;
  }, [slotStatuses]);

  // 3. Fetch Enrolled Students for Selected Batch
  const {
    data: students = [],
    isLoading: loadingStudents,
  } = useQuery({
    queryKey: ['batchStudents', selectedBatchId],
    queryFn: () => (selectedBatchId ? teacherService.getBatchStudents(selectedBatchId) : Promise.resolve([])),
    enabled: Boolean(selectedBatchId),
  });

  // 4. Fetch Session State for (selectedBatchId, selectedDate, selectedSlot)
  const {
    data: sessionState,
    isLoading: loadingSession,
    refetch: refetchSession,
  } = useQuery({
    queryKey: ['attendanceSession', selectedBatchId, selectedDate, selectedSlot],
    queryFn: () =>
      selectedBatchId
        ? teacherService.getAttendanceSession(selectedBatchId, selectedDate, selectedSlot)
        : Promise.resolve(null),
    enabled: Boolean(selectedBatchId),
  });

  // 5. Fetch "My Sessions"
  const {
    data: mySessions = [],
    isLoading: loadingMySessions,
    refetch: refetchMySessions,
  } = useQuery({
    queryKey: ['teacherMySessions', teacherId],
    queryFn: () => teacherService.getMySessions(teacherId),
    enabled: activeSection === 'my_sessions',
  });

  // Synchronize student marks map and read-only status
  useEffect(() => {
    if (!students || students.length === 0) return;

    const initialMap: Record<number, 'present' | 'late' | 'absent' | 'leave'> = {};
    students.forEach((s) => {
      if (sessionState?.records && sessionState.records[s.id]) {
        initialMap[s.id] = sessionState.records[s.id].status;
      } else {
        initialMap[s.id] = 'present';
      }
    });

    setStudentMarks(initialMap);

    // If session is already submitted or no_class, setup the read-only banner
    if (sessionState && ['submitted', 'locked', 'no_class'].includes(sessionState.status)) {
      setAlreadyMarkedBanner({
        markedBy: sessionState.markedByName || 'Administrator',
        markedAt: sessionState.submittedAt,
        message: sessionState.status === 'no_class'
          ? `Marked as "No Class" (${sessionState.noClassReason || 'Holiday'}) by ${sessionState.markedByName || 'Faculty'}. Only the administrator can correct it.`
          : `Already marked by ${sessionState.markedByName || 'Faculty'} at ${sessionState.submittedAt ? formatDateTime(sessionState.submittedAt) : 'N/A'}. Only the administrator can correct it.`,
      });
    } else {
      setAlreadyMarkedBanner(null);
    }
  }, [sessionState, students]);

  // Quick Action: Mark All Present
  const handleMarkAllPresent = () => {
    if (isReadOnly) return;
    const allPresent: Record<number, 'present' | 'late' | 'absent' | 'leave'> = {};
    students.forEach((s) => {
      allPresent[s.id] = 'present';
    });
    setStudentMarks(allPresent);
  };

  // Toggle individual mark
  const handleToggleMark = (studentId: number, status: 'present' | 'late' | 'absent' | 'leave') => {
    if (isReadOnly) return;
    setStudentMarks((prev) => ({
      ...prev,
      [studentId]: status,
    }));
  };

  // Submit Attendance Mutation
  const submitMutation = useMutation({
    mutationFn: async (args: { noClass?: boolean; reason?: string }) => {
      if (!selectedBatchId) throw new Error('No batch selected.');
      const entries: StudentAttendanceEntry[] = students.map((s) => ({
        studentId: s.id,
        name: s.name,
        registrationNumber: s.registrationNumber,
        admissionNumber: s.admissionNumber,
        status: studentMarks[s.id] || 'present',
      }));

      return await teacherService.submitAttendance(
        selectedBatchId,
        selectedDate,
        selectedSlot,
        entries,
        args.noClass || false,
        args.reason
      );
    },
    onSuccess: (result) => {
      setIsSubmitModalOpen(false);
      setIsNoClassModalOpen(false);

      if (result.alreadyMarked) {
        // Race condition: another faculty marked it!
        setAlreadyMarkedBanner({
          markedBy: result.markedByName || 'Another Faculty',
          markedAt: result.markedAt,
          role: result.markedByRole,
          message: result.message || `Already marked by ${result.markedByName}. Only the administrator can correct it.`,
        });
        setFeedbackMessage({
          type: 'error',
          text: `Slot was already marked by ${result.markedByName}. Your entries remain on screen for review but were not committed.`,
        });
      } else {
        setFeedbackMessage({
          type: 'success',
          text: `Attendance successfully recorded! (${result.recordsMarked} student records finalized)`,
        });
        queryClient.invalidateQueries({ queryKey: ['attendanceSession'] });
        queryClient.invalidateQueries({ queryKey: ['attendanceSlotStatus'] });
        queryClient.invalidateQueries({ queryKey: ['teacherMySessions'] });
      }
    },
    onError: (err: any) => {
      setFeedbackMessage({
        type: 'error',
        text: err.message || 'Failed to submit attendance session. Please retry.',
      });
    },
  });

  const isReadOnly = Boolean(alreadyMarkedBanner) || sessionState?.isReadOnly;

  // Filter students for search query
  const filteredStudents = useMemo(() => {
    if (!searchQuery.trim()) return students;
    const q = searchQuery.toLowerCase().trim();
    return students.filter(
      (s) =>
        s.name.toLowerCase().includes(q) ||
        (s.registrationNumber && s.registrationNumber.toLowerCase().includes(q)) ||
        s.admissionNumber.toLowerCase().includes(q)
    );
  }, [students, searchQuery]);

  // Breakdown statistics
  const breakdown = useMemo(() => {
    let present = 0;
    let late = 0;
    let absent = 0;
    let leave = 0;

    students.forEach((s) => {
      const st = studentMarks[s.id] || 'present';
      if (st === 'present') present++;
      else if (st === 'late') late++;
      else if (st === 'absent') absent++;
      else if (st === 'leave') leave++;
    });

    const total = students.length;
    const effectivePresent = present + late * 0.5;
    const percentage = total > 0 ? ((effectivePresent / total) * 100).toFixed(1) : '100.0';

    return { total, present, late, absent, leave, percentage };
  }, [students, studentMarks]);

  // Quick switch from Today's Board to Mark slot
  const handleMarkSlotFromBoard = (batchId: number, slot: 'morning' | 'evening') => {
    const batch = primaryCourses.flatMap((c) => c.batches).find((b) => b.batchId === batchId);
    if (batch) {
      const course = primaryCourses.find((c) => c.batches.some((b) => b.batchId === batchId));
      if (course) setSelectedCourseId(course.courseId);
      setSelectedBatchId(batchId);
      setSelectedSlot(slot);
      setSelectedDate(todayStr);
      setActiveSection('mark');
    }
  };

  return (
    <div className="space-y-6">
      {/* Top Header Card with Section Switcher */}
      <div className="bg-white rounded-card-lg border border-cardBorder p-5 shadow-sm">
        <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
          <div>
            <h2 className="font-sora font-bold text-lg text-navy flex items-center gap-2">
              <CalendarCheck className="w-5 h-5 text-primary" />
              <span>Campus Attendance Management</span>
            </h2>
            <p className="text-xs text-muted mt-0.5">
              Primary Course Batches &bull; Universal Faculty Permission &bull; Shared Slot States
            </p>
          </div>

          {/* Section Navigation Tabs */}
          <div className="flex gap-2 bg-slate-100 p-1 rounded-btn self-start sm:self-auto">
            <button
              type="button"
              onClick={() => setActiveSection('mark')}
              className={`px-3.5 py-2 rounded-btn text-xs font-sora font-semibold transition-all flex items-center gap-1.5 min-h-touch ${
                activeSection === 'mark'
                  ? 'bg-white text-navy shadow-sm'
                  : 'text-muted hover:text-navy'
              }`}
            >
              <CalendarCheck className="w-3.5 h-3.5 text-primary" />
              <span>Mark Attendance</span>
            </button>

            <button
              type="button"
              onClick={() => setActiveSection('today_board')}
              className={`px-3.5 py-2 rounded-btn text-xs font-sora font-semibold transition-all flex items-center gap-1.5 min-h-touch ${
                activeSection === 'today_board'
                  ? 'bg-white text-navy shadow-sm'
                  : 'text-muted hover:text-navy'
              }`}
            >
              <LayoutGrid className="w-3.5 h-3.5 text-teal" />
              <span>Today's Board</span>
            </button>

            <button
              type="button"
              onClick={() => setActiveSection('my_sessions')}
              className={`px-3.5 py-2 rounded-btn text-xs font-sora font-semibold transition-all flex items-center gap-1.5 min-h-touch ${
                activeSection === 'my_sessions'
                  ? 'bg-white text-navy shadow-sm'
                  : 'text-muted hover:text-navy'
              }`}
            >
              <History className="w-3.5 h-3.5 text-navy" />
              <span>My Marked Sessions</span>
            </button>
          </div>
        </div>

        {/* Global Feedback Banner */}
        {feedbackMessage && (
          <div
            className={`mt-4 p-3.5 rounded-card flex items-center justify-between text-xs animate-in fade-in duration-200 ${
              feedbackMessage.type === 'success'
                ? 'bg-emerald-50 text-emerald-800 border border-emerald-200'
                : 'bg-rose-50 text-rose-800 border border-rose-200'
            }`}
          >
            <div className="flex items-center gap-2">
              {feedbackMessage.type === 'success' ? (
                <CheckCircle2 className="w-4 h-4 text-emerald-600 shrink-0" />
              ) : (
                <AlertCircle className="w-4 h-4 text-rose-600 shrink-0" />
              )}
              <span>{feedbackMessage.text}</span>
            </div>
            <button
              type="button"
              onClick={() => setFeedbackMessage(null)}
              className="text-muted hover:text-navy p-1"
            >
              <X className="w-4 h-4" />
            </button>
          </div>
        )}
      </div>

      {/* =========================================================================
          SECTION 1: MARK ATTENDANCE GUIDED FLOW
         ========================================================================= */}
      {activeSection === 'mark' && (
        <div className="space-y-6">
          {/* Step 1 & 2: Course & Batch Selection Card */}
          <div className="bg-white rounded-card-lg border border-cardBorder p-5 shadow-sm space-y-4">
            <div className="border-b border-cardBorder pb-3">
              <h3 className="font-sora font-bold text-sm text-navy uppercase tracking-wider flex items-center gap-2">
                <BookOpen className="w-4 h-4 text-primary" />
                <span>Step 1 &bull; Select Primary Course</span>
              </h3>
              <p className="text-xs text-muted mt-0.5">
                Attendance is strictly restricted to primary courses. Skill courses do not track attendance.
              </p>

              {/* Course Selector Buttons */}
              <div className="flex flex-wrap gap-2 mt-3">
                {primaryCourses.map((c) => (
                  <button
                    key={c.courseId}
                    type="button"
                    onClick={() => {
                      setSelectedCourseId(c.courseId);
                      setSelectedBatchId(null);
                    }}
                    className={`px-3.5 py-2 rounded-btn text-xs font-sora font-semibold transition-all min-h-touch ${
                      selectedCourseId === c.courseId
                        ? 'bg-navy text-white shadow-md'
                        : 'bg-surface text-navy hover:bg-slate-100 border border-cardBorder'
                    }`}
                  >
                    <span>{c.courseName}</span>
                    {c.courseCode && (
                      <span className="ml-1.5 opacity-70 font-mono text-[10px]">[{c.courseCode}]</span>
                    )}
                  </button>
                ))}
              </div>
            </div>

            {/* Step 2: Batch Selection with Today's Live Status Chips */}
            <div>
              <h3 className="font-sora font-bold text-sm text-navy uppercase tracking-wider flex items-center gap-2">
                <Users className="w-4 h-4 text-teal" />
                <span>Step 2 &bull; Select Batch & Review Slot Status</span>
              </h3>
              <p className="text-xs text-muted mt-0.5">
                Each batch row reflects live completion states for today's Morning and Evening slots.
              </p>

              {courseBatches.length === 0 ? (
                <div className="p-4 rounded-xl bg-slate-50 border border-dashed border-cardBorder text-xs text-muted text-center mt-3">
                  No active batches found for the selected course.
                </div>
              ) : (
                <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-3 mt-3">
                  {courseBatches.map((b) => {
                    const isSelected = selectedBatchId === b.batchId;
                    const statuses = batchSlotStatusMap.get(b.batchId);
                    const mState = statuses?.morning?.state || 'not_marked';
                    const eState = statuses?.evening?.state || 'not_marked';

                    return (
                      <div
                        key={b.batchId}
                        onClick={() => setSelectedBatchId(b.batchId)}
                        className={`p-4 rounded-xl border text-xs cursor-pointer transition-all ${
                          isSelected
                            ? 'bg-primary/5 border-primary shadow-sm ring-2 ring-primary/20'
                            : 'bg-surface hover:bg-slate-50 border-cardBorder'
                        }`}
                      >
                        <div className="flex items-center justify-between mb-2">
                          <span className="font-sora font-bold text-navy text-sm">{b.batchName}</span>
                          <span className="px-2 py-0.5 rounded-full bg-slate-100 text-slate-700 text-[10px] font-mono">
                            {b.academicYear || 'Active'}
                          </span>
                        </div>

                        {/* Today's Status Badges */}
                        <div className="space-y-1.5 pt-1 border-t border-cardBorder/60 text-[11px]">
                          {/* Morning */}
                          <div className="flex items-center justify-between">
                            <span className="text-muted flex items-center gap-1">
                              <Sun className="w-3 h-3 text-amber-500" />
                              Morning:
                            </span>
                            {mState === 'submitted' ? (
                              <span className="px-2 py-0.5 rounded-full bg-emerald-100 text-emerald-800 font-bold text-[10px] flex items-center gap-1">
                                <CheckCircle2 className="w-2.5 h-2.5" />
                                Marked ({statuses?.morning?.marked_by})
                              </span>
                            ) : mState === 'no_class' ? (
                              <span className="px-2 py-0.5 rounded-full bg-slate-200 text-slate-700 font-bold text-[10px] flex items-center gap-1">
                                <Ban className="w-2.5 h-2.5" />
                                No Class
                              </span>
                            ) : (
                              <span className="px-2 py-0.5 rounded-full bg-amber-100 text-amber-800 font-bold text-[10px] flex items-center gap-1">
                                <Clock className="w-2.5 h-2.5" />
                                Not Marked
                              </span>
                            )}
                          </div>

                          {/* Evening */}
                          <div className="flex items-center justify-between">
                            <span className="text-muted flex items-center gap-1">
                              <Moon className="w-3 h-3 text-indigo-500" />
                              Evening:
                            </span>
                            {eState === 'submitted' ? (
                              <span className="px-2 py-0.5 rounded-full bg-emerald-100 text-emerald-800 font-bold text-[10px] flex items-center gap-1">
                                <CheckCircle2 className="w-2.5 h-2.5" />
                                Marked ({statuses?.evening?.marked_by})
                              </span>
                            ) : eState === 'no_class' ? (
                              <span className="px-2 py-0.5 rounded-full bg-slate-200 text-slate-700 font-bold text-[10px] flex items-center gap-1">
                                <Ban className="w-2.5 h-2.5" />
                                No Class
                              </span>
                            ) : (
                              <span className="px-2 py-0.5 rounded-full bg-amber-100 text-amber-800 font-bold text-[10px] flex items-center gap-1">
                                <Clock className="w-2.5 h-2.5" />
                                Not Marked
                              </span>
                            )}
                          </div>
                        </div>
                      </div>
                    );
                  })}
                </div>
              )}
            </div>

            {/* Step 3: Date & Slot Segmented Control */}
            {selectedBatchId && (
              <div className="pt-4 border-t border-cardBorder flex flex-col sm:flex-row items-stretch sm:items-center justify-between gap-4">
                {/* Date Picker (Default Today, no future dates) */}
                <div className="flex items-center gap-2">
                  <label className="text-xs font-bold text-navy flex items-center gap-1.5 shrink-0">
                    <Calendar className="w-3.5 h-3.5 text-primary" />
                    <span>Session Date:</span>
                  </label>
                  <input
                    type="date"
                    value={selectedDate}
                    max={todayStr}
                    onChange={(e) => setSelectedDate(e.target.value)}
                    className="px-3 py-2 rounded-input border border-cardBorder text-xs text-navy font-sora font-medium focus:outline-none focus:ring-2 focus:ring-focusRing min-h-touch bg-surface"
                  />
                </div>

                {/* Morning / Evening Segmented Control */}
                <div className="flex gap-2 bg-slate-100 p-1 rounded-btn self-start sm:self-auto">
                  <button
                    type="button"
                    onClick={() => setSelectedSlot('morning')}
                    className={`px-4 py-2 rounded-btn text-xs font-sora font-semibold transition-all flex items-center gap-2 min-h-touch ${
                      selectedSlot === 'morning'
                        ? 'bg-white text-navy shadow-sm'
                        : 'text-muted hover:text-navy'
                    }`}
                  >
                    <Sun className={`w-3.5 h-3.5 ${selectedSlot === 'morning' ? 'text-amber-500' : ''}`} />
                    <span>Morning Slot (09:00 - 12:30)</span>
                  </button>

                  <button
                    type="button"
                    onClick={() => setSelectedSlot('evening')}
                    className={`px-4 py-2 rounded-btn text-xs font-sora font-semibold transition-all flex items-center gap-2 min-h-touch ${
                      selectedSlot === 'evening'
                        ? 'bg-white text-navy shadow-sm'
                        : 'text-muted hover:text-navy'
                    }`}
                  >
                    <Moon className={`w-3.5 h-3.5 ${selectedSlot === 'evening' ? 'text-indigo-500' : ''}`} />
                    <span>Evening Slot (13:30 - 16:30)</span>
                  </button>
                </div>
              </div>
            )}
          </div>

          {/* READ-ONLY / ALREADY MARKED ALERT BANNER */}
          {alreadyMarkedBanner && (
            <div
              className="p-4 rounded-card-lg bg-amber-50 border border-amber-300 text-amber-900 shadow-sm flex items-start gap-3"
              role="alert"
            >
              <div className="p-2 rounded-full bg-amber-200 text-amber-900 shrink-0 mt-0.5">
                <Lock className="w-5 h-5" />
              </div>
              <div className="flex-1">
                <h4 className="font-sora font-bold text-sm text-amber-950">
                  Session Locked &bull; Read-Only View
                </h4>
                <p className="text-xs text-amber-900 mt-1 leading-relaxed font-medium">
                  {alreadyMarkedBanner.message ||
                    `Already marked by ${alreadyMarkedBanner.markedBy} at ${alreadyMarkedBanner.markedAt ? formatDateTime(alreadyMarkedBanner.markedAt) : 'recorded time'}. Only the administrator can correct it.`}
                </p>
                <span className="inline-block mt-2 px-2.5 py-1 rounded-md bg-amber-200/80 text-[11px] font-semibold text-amber-950">
                  Editing disabled. Contact administrator for attendance adjustments.
                </span>
              </div>
            </div>
          )}

          {/* Student Marking Table Card */}
          {selectedBatchId && (
            <div className="bg-white rounded-card-lg border border-cardBorder p-5 shadow-sm space-y-4">
              {/* Table Controls Header */}
              <div className="flex flex-col sm:flex-row items-stretch sm:items-center justify-between gap-3 pb-3 border-b border-cardBorder">
                <div className="flex items-center gap-3">
                  <div className="relative flex-1 sm:w-64">
                    <Search className="w-4 h-4 text-muted absolute left-3 top-1/2 -translate-y-1/2" />
                    <input
                      type="text"
                      placeholder="Search student or register no..."
                      value={searchQuery}
                      onChange={(e) => setSearchQuery(e.target.value)}
                      className="w-full pl-9 pr-3 py-2 rounded-input border border-cardBorder text-xs text-navy focus:outline-none focus:ring-2 focus:ring-focusRing min-h-touch bg-surface"
                    />
                  </div>
                  <span className="text-xs text-muted">
                    {filteredStudents.length} of {students.length} students
                  </span>
                </div>

                {/* Quick Action: Mark All Present */}
                {!isReadOnly && (
                  <button
                    type="button"
                    onClick={handleMarkAllPresent}
                    className="px-3.5 py-2 rounded-btn text-xs font-sora font-semibold text-emerald-800 bg-emerald-100 hover:bg-emerald-200 border border-emerald-300 transition-colors flex items-center justify-center gap-1.5 min-h-touch self-start sm:self-auto cursor-pointer"
                  >
                    <Check className="w-3.5 h-3.5" />
                    <span>Mark All Present</span>
                  </button>
                )}
              </div>

              {/* Student Rows */}
              {loadingStudents || loadingSession ? (
                <LoadingSkeleton type="card" rows={6} />
              ) : filteredStudents.length === 0 ? (
                <EmptyState
                  title="No students found"
                  description={searchQuery ? 'No student matched your search query.' : 'No active students enrolled in this batch.'}
                />
              ) : (
                <div className="space-y-2">
                  {filteredStudents.map((student, idx) => {
                    const currentStatus = studentMarks[student.id] || 'present';

                    return (
                      <div
                        key={student.id}
                        className="p-3.5 rounded-xl border border-cardBorder bg-surface hover:bg-slate-50/80 transition-colors flex flex-col sm:flex-row sm:items-center justify-between gap-3 text-xs"
                      >
                        {/* Student Details */}
                        <div className="flex items-center gap-3">
                          <span className="w-6 text-[11px] font-mono text-muted text-right">
                            {idx + 1}.
                          </span>
                          <div>
                            <span className="font-sora font-bold text-navy text-sm block">
                              {student.name}
                            </span>
                            <span className="text-[11px] text-muted">
                              Adm: {student.admissionNumber}
                              {student.registrationNumber && ` &bull; Reg: ${student.registrationNumber}`}
                            </span>
                          </div>
                        </div>

                        {/* Status Button Group */}
                        <div className="flex items-center gap-1.5 self-end sm:self-auto">
                          {/* Present */}
                          <button
                            type="button"
                            disabled={isReadOnly}
                            onClick={() => handleToggleMark(student.id, 'present')}
                            className={`px-3 py-1.5 rounded-btn font-sora text-xs font-bold transition-all min-h-touch min-w-[70px] ${
                              currentStatus === 'present'
                                ? 'bg-emerald-600 text-white shadow-sm ring-2 ring-emerald-300'
                                : 'bg-white border border-cardBorder text-slate-700 hover:bg-emerald-50'
                            } ${isReadOnly ? 'opacity-70 cursor-not-allowed' : 'cursor-pointer'}`}
                          >
                            Present
                          </button>

                          {/* Late */}
                          <button
                            type="button"
                            disabled={isReadOnly}
                            onClick={() => handleToggleMark(student.id, 'late')}
                            className={`px-3 py-1.5 rounded-btn font-sora text-xs font-bold transition-all min-h-touch min-w-[70px] ${
                              currentStatus === 'late'
                                ? 'bg-amber-600 text-white shadow-sm ring-2 ring-amber-300'
                                : 'bg-white border border-cardBorder text-slate-700 hover:bg-amber-50'
                            } ${isReadOnly ? 'opacity-70 cursor-not-allowed' : 'cursor-pointer'}`}
                          >
                            Late
                          </button>

                          {/* Absent */}
                          <button
                            type="button"
                            disabled={isReadOnly}
                            onClick={() => handleToggleMark(student.id, 'absent')}
                            className={`px-3 py-1.5 rounded-btn font-sora text-xs font-bold transition-all min-h-touch min-w-[70px] ${
                              currentStatus === 'absent'
                                ? 'bg-rose-600 text-white shadow-sm ring-2 ring-rose-300'
                                : 'bg-white border border-cardBorder text-slate-700 hover:bg-rose-50'
                            } ${isReadOnly ? 'opacity-70 cursor-not-allowed' : 'cursor-pointer'}`}
                          >
                            Absent
                          </button>

                          {/* Leave */}
                          <button
                            type="button"
                            disabled={isReadOnly}
                            onClick={() => handleToggleMark(student.id, 'leave')}
                            className={`px-3 py-1.5 rounded-btn font-sora text-xs font-bold transition-all min-h-touch min-w-[70px] ${
                              currentStatus === 'leave'
                                ? 'bg-slate-600 text-white shadow-sm ring-2 ring-slate-300'
                                : 'bg-white border border-cardBorder text-slate-700 hover:bg-slate-100'
                            } ${isReadOnly ? 'opacity-70 cursor-not-allowed' : 'cursor-pointer'}`}
                          >
                            Leave
                          </button>
                        </div>
                      </div>
                    );
                  })}
                </div>
              )}

              {/* Bottom Summary & Actions Bar */}
              <div className="pt-4 border-t border-cardBorder flex flex-col sm:flex-row items-stretch sm:items-center justify-between gap-4">
                {/* Statistics Breakdown */}
                <div className="flex flex-wrap items-center gap-3 text-xs">
                  <span className="font-bold text-navy">
                    <span>Total:</span> {breakdown.total}
                  </span>
                  <span className="text-emerald-700 font-semibold">
                    <span>Present:</span> {breakdown.present}
                  </span>
                  <span className="text-amber-700 font-semibold">
                    <span>Late:</span> {breakdown.late}
                  </span>
                  <span className="text-rose-700 font-semibold">
                    <span>Absent:</span> {breakdown.absent}
                  </span>
                  <span className="text-slate-600 font-semibold">
                    <span>Leave:</span> {breakdown.leave}
                  </span>
                  <span className="px-2 py-0.5 rounded-full bg-primary/10 text-primary font-bold text-[11px]">
                    Effective: {breakdown.percentage}%
                  </span>
                </div>

                {/* Submission Actions */}
                {!isReadOnly ? (
                  <div className="flex items-center gap-2.5">
                    <button
                      type="button"
                      onClick={() => setIsNoClassModalOpen(true)}
                      className="px-4 py-2.5 rounded-btn text-xs font-sora font-semibold text-slate-700 bg-slate-100 hover:bg-slate-200 transition-colors min-h-touch flex items-center gap-1.5 cursor-pointer"
                    >
                      <Ban className="w-3.5 h-3.5" />
                      <span>Mark No Class</span>
                    </button>

                    <button
                      type="button"
                      disabled={students.length === 0 || submitMutation.isPending}
                      onClick={() => setIsSubmitModalOpen(true)}
                      className="px-5 py-2.5 rounded-btn text-xs font-sora font-bold text-white bg-primary hover:bg-primary-hover shadow-primary-btn transition-all min-h-touch flex items-center gap-2 cursor-pointer disabled:opacity-50"
                    >
                      <Send className="w-3.5 h-3.5" />
                      <span>Submit Attendance</span>
                    </button>
                  </div>
                ) : (
                  <div className="flex items-center gap-1.5 text-xs text-muted italic">
                    <Lock className="w-3.5 h-3.5" />
                    <span>Attendance locked for this slot</span>
                  </div>
                )}
              </div>
            </div>
          )}
        </div>
      )}

      {/* =========================================================================
          SECTION 2: TODAY'S LIVE ATTENDANCE BOARD
         ========================================================================= */}
      {activeSection === 'today_board' && (
        <div className="bg-white rounded-card-lg border border-cardBorder p-5 shadow-sm space-y-4">
          <div className="flex items-center justify-between pb-3 border-b border-cardBorder">
            <div>
              <h3 className="font-sora font-bold text-sm text-navy uppercase tracking-wider flex items-center gap-2">
                <LayoutGrid className="w-4 h-4 text-teal" />
                <span>Today's Campus-Wide Slot Completion Board</span>
              </h3>
              <p className="text-xs text-muted mt-0.5">
                Live monitoring across all active primary batches for date: {formatDate(selectedDate)}
              </p>
            </div>

            <button
              type="button"
              onClick={() => refetchSlotStatus()}
              className="px-3 py-1.5 rounded-btn text-xs font-semibold text-primary bg-primary/10 hover:bg-primary/20 transition-colors flex items-center gap-1.5 min-h-touch cursor-pointer"
            >
              <Clock className="w-3.5 h-3.5" />
              <span>Refresh Status</span>
            </button>
          </div>

          {loadingSlotStatus ? (
            <LoadingSkeleton type="card" rows={5} />
          ) : slotStatuses.length === 0 ? (
            <EmptyState
              title="No primary batches found"
              description="No active primary batches configured in the system."
            />
          ) : (
            <div className="overflow-x-auto no-scrollbar">
              <table className="w-full text-left text-xs text-navy border-collapse">
                <thead>
                  <tr className="border-b border-cardBorder bg-slate-50/80 text-[11px] font-sora font-bold text-muted uppercase">
                    <th className="py-3 px-4">Course</th>
                    <th className="py-3 px-4">Batch</th>
                    <th className="py-3 px-4">Slot</th>
                    <th className="py-3 px-4">State</th>
                    <th className="py-3 px-4">Marked By</th>
                    <th className="py-3 px-4">Timestamp</th>
                    <th className="py-3 px-4 text-right">Action</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-cardBorder/60">
                  {slotStatuses.map((slot) => {
                    const isSubmitted = slot.state === 'submitted';
                    const isNoClass = slot.state === 'no_class';
                    const isNotMarked = slot.state === 'not_marked';

                    return (
                      <tr key={`${slot.batch_id}-${slot.slot}`} className="hover:bg-slate-50/60 transition-colors">
                        <td className="py-3.5 px-4 font-sora font-bold text-navy">
                          {slot.course_name}
                        </td>
                        <td className="py-3.5 px-4 font-semibold text-slate-700">
                          {slot.batch_name}
                        </td>
                        <td className="py-3.5 px-4">
                          <span className="capitalize font-mono font-medium">
                            {slot.slot}
                          </span>
                        </td>
                        <td className="py-3.5 px-4">
                          {isSubmitted ? (
                            <span className="px-2.5 py-1 rounded-full bg-emerald-100 text-emerald-800 font-bold text-[10px] flex items-center gap-1 w-fit">
                              <CheckCircle2 className="w-3 h-3 text-emerald-600" />
                              Submitted
                            </span>
                          ) : isNoClass ? (
                            <span className="px-2.5 py-1 rounded-full bg-slate-200 text-slate-700 font-bold text-[10px] flex items-center gap-1 w-fit">
                              <Ban className="w-3 h-3 text-slate-500" />
                              No Class
                            </span>
                          ) : (
                            <span className="px-2.5 py-1 rounded-full bg-amber-100 text-amber-800 font-bold text-[10px] flex items-center gap-1 w-fit">
                              <Clock className="w-3 h-3 text-amber-600" />
                              Not Marked
                            </span>
                          )}
                        </td>
                        <td className="py-3.5 px-4 text-slate-700 font-medium">
                          {slot.marked_by || '—'}
                        </td>
                        <td className="py-3.5 px-4 text-muted text-[11px]">
                          {slot.marked_at ? formatDateTime(slot.marked_at) : '—'}
                        </td>
                        <td className="py-3.5 px-4 text-right">
                          {isNotMarked ? (
                            <button
                              type="button"
                              onClick={() => handleMarkSlotFromBoard(slot.batch_id, slot.slot)}
                              className="px-3 py-1.5 rounded-btn text-xs font-semibold text-white bg-primary hover:bg-primary-hover shadow-sm transition-all min-h-touch cursor-pointer"
                            >
                              Mark Slot
                            </button>
                          ) : (
                            <span className="text-[11px] text-muted italic flex items-center justify-end gap-1">
                              <Lock className="w-3 h-3" />
                              Locked
                            </span>
                          )}
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          )}
        </div>
      )}

      {/* =========================================================================
          SECTION 3: MY MARKED SESSIONS
         ========================================================================= */}
      {activeSection === 'my_sessions' && (
        <div className="bg-white rounded-card-lg border border-cardBorder p-5 shadow-sm space-y-4">
          <div className="flex items-center justify-between pb-3 border-b border-cardBorder">
            <div>
              <h3 className="font-sora font-bold text-sm text-navy uppercase tracking-wider flex items-center gap-2">
                <History className="w-4 h-4 text-navy" />
                <span>My Marked Attendance Sessions</span>
              </h3>
              <p className="text-xs text-muted mt-0.5">
                Past attendance sessions submitted under your faculty identity
              </p>
            </div>

            <button
              type="button"
              onClick={() => refetchMySessions()}
              className="px-3 py-1.5 rounded-btn text-xs font-semibold text-primary bg-primary/10 hover:bg-primary/20 transition-colors flex items-center gap-1.5 min-h-touch cursor-pointer"
            >
              <Clock className="w-3.5 h-3.5" />
              <span>Refresh</span>
            </button>
          </div>

          {loadingMySessions ? (
            <LoadingSkeleton type="card" rows={4} />
          ) : mySessions.length === 0 ? (
            <EmptyState
              title="No sessions marked yet"
              description="You have not finalized any attendance sessions under your account."
            />
          ) : (
            <div className="overflow-x-auto no-scrollbar">
              <table className="w-full text-left text-xs text-navy border-collapse">
                <thead>
                  <tr className="border-b border-cardBorder bg-slate-50/80 text-[11px] font-sora font-bold text-muted uppercase">
                    <th className="py-3 px-4">Date</th>
                    <th className="py-3 px-4">Course</th>
                    <th className="py-3 px-4">Batch</th>
                    <th className="py-3 px-4">Slot</th>
                    <th className="py-3 px-4">Status</th>
                    <th className="py-3 px-4">Students Recorded</th>
                    <th className="py-3 px-4">Submitted At</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-cardBorder/60">
                  {mySessions.map((session) => (
                    <tr key={session.id} className="hover:bg-slate-50/60 transition-colors">
                      <td className="py-3.5 px-4 font-sora font-bold text-navy">
                        {formatDate(session.date)}
                      </td>
                      <td className="py-3.5 px-4 font-semibold text-slate-700">
                        {session.courseName}
                      </td>
                      <td className="py-3.5 px-4 font-medium text-slate-700">
                        {session.batchName}
                      </td>
                      <td className="py-3.5 px-4 capitalize font-mono">
                        {session.slot}
                      </td>
                      <td className="py-3.5 px-4">
                        {session.status === 'no_class' ? (
                          <span className="px-2.5 py-0.5 rounded-full bg-slate-200 text-slate-700 font-bold text-[10px]">
                            No Class ({session.noClassReason || 'Holiday'})
                          </span>
                        ) : (
                          <span className="px-2.5 py-0.5 rounded-full bg-emerald-100 text-emerald-800 font-bold text-[10px]">
                            Submitted
                          </span>
                        )}
                      </td>
                      <td className="py-3.5 px-4 font-mono font-bold text-slate-700">
                        {session.recordsCount || students.length}
                      </td>
                      <td className="py-3.5 px-4 text-muted text-[11px]">
                        {session.submittedAt ? formatDateTime(session.submittedAt) : '—'}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </div>
      )}

      {/* CONFIRMATION MODAL: SUBMIT ATTENDANCE */}
      {isSubmitModalOpen && (
        <div className="fixed inset-0 z-50 bg-black/60 backdrop-blur-sm flex items-center justify-center p-4">
          <div className="bg-white rounded-card-lg max-w-md w-full p-6 text-navy shadow-2xl border border-cardBorder animate-in fade-in zoom-in-95 duration-150 space-y-4">
            <div className="flex items-center gap-3 text-primary pb-2 border-b border-cardBorder">
              <div className="p-2.5 rounded-full bg-primary/10">
                <Send className="w-5 h-5 text-primary" />
              </div>
              <div>
                <h3 className="font-sora font-bold text-base">Confirm Attendance Submission</h3>
                <p className="text-xs text-muted">
                  {currentCourse?.courseName} &bull; {selectedSlot.toUpperCase()} slot
                </p>
              </div>
            </div>

            <p className="text-xs text-slate-700 leading-relaxed">
              You are about to finalize attendance for <strong>{breakdown.total} students</strong> on <strong>{formatDate(selectedDate)}</strong>:
            </p>

            <div className="p-3.5 rounded-xl bg-slate-50 border border-cardBorder grid grid-cols-2 gap-2 text-xs">
              <div>
                <span className="text-muted">Present:</span>{' '}
                <strong className="text-emerald-700">{breakdown.present}</strong>
              </div>
              <div>
                <span className="text-muted">Late:</span>{' '}
                <strong className="text-amber-700">{breakdown.late}</strong>
              </div>
              <div>
                <span className="text-muted">Absent:</span>{' '}
                <strong className="text-rose-700">{breakdown.absent}</strong>
              </div>
              <div>
                <span className="text-muted">Leave:</span>{' '}
                <strong className="text-slate-700">{breakdown.leave}</strong>
              </div>
            </div>

            <div className="p-3 rounded-lg bg-amber-50 border border-amber-200 text-[11px] text-amber-900 flex items-start gap-2">
              <AlertTriangle className="w-4 h-4 text-amber-600 shrink-0 mt-0.5" />
              <span>
                Once submitted, this slot will be locked and read-only for all faculty. Only the administrator can correct submitted records.
              </span>
            </div>

            <div className="flex items-center justify-end gap-3 pt-2">
              <button
                type="button"
                disabled={submitMutation.isPending}
                onClick={() => setIsSubmitModalOpen(false)}
                className="px-4 py-2.5 rounded-btn text-xs font-semibold text-muted hover:bg-slate-100 transition-colors min-h-touch"
              >
                Cancel
              </button>
              <button
                type="button"
                disabled={submitMutation.isPending}
                onClick={() => submitMutation.mutate({ noClass: false })}
                className="px-5 py-2.5 rounded-btn text-xs font-semibold text-white bg-primary hover:bg-primary-hover shadow-md transition-all min-h-touch flex items-center gap-1.5 cursor-pointer disabled:opacity-50"
              >
                {submitMutation.isPending ? (
                  <span>Submitting...</span>
                ) : (
                  <>
                    <Check className="w-4 h-4" />
                    <span>Confirm & Finalize</span>
                  </>
                )}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* CONFIRMATION MODAL: MARK NO CLASS */}
      {isNoClassModalOpen && (
        <div className="fixed inset-0 z-50 bg-black/60 backdrop-blur-sm flex items-center justify-center p-4">
          <div className="bg-white rounded-card-lg max-w-md w-full p-6 text-navy shadow-2xl border border-cardBorder animate-in fade-in zoom-in-95 duration-150 space-y-4">
            <div className="flex items-center gap-3 text-slate-800 pb-2 border-b border-cardBorder">
              <div className="p-2.5 rounded-full bg-slate-100">
                <Ban className="w-5 h-5 text-slate-700" />
              </div>
              <div>
                <h3 className="font-sora font-bold text-base">Mark "No Class" Session</h3>
                <p className="text-xs text-muted">
                  Record an official zero-session slot with administrative rationale
                </p>
              </div>
            </div>

            <div>
              <label className="text-xs font-bold text-navy block mb-1.5">
                Select Official Reason:
              </label>
              <select
                value={noClassReason}
                onChange={(e) => setNoClassReason(e.target.value)}
                className="w-full px-3 py-2.5 rounded-input border border-cardBorder text-xs text-navy focus:outline-none focus:ring-2 focus:ring-focusRing min-h-touch bg-surface"
              >
                {NO_CLASS_REASONS.map((r) => (
                  <option key={r} value={r}>
                    {r}
                  </option>
                ))}
              </select>
            </div>

            <p className="text-xs text-muted leading-relaxed">
              No class sessions do not negatively affect student attendance percentages. This slot will be marked as "No Class" across the entire institution.
            </p>

            <div className="flex items-center justify-end gap-3 pt-2">
              <button
                type="button"
                disabled={submitMutation.isPending}
                onClick={() => setIsNoClassModalOpen(false)}
                className="px-4 py-2.5 rounded-btn text-xs font-semibold text-muted hover:bg-slate-100 transition-colors min-h-touch"
              >
                Cancel
              </button>
              <button
                type="button"
                disabled={submitMutation.isPending}
                onClick={() => submitMutation.mutate({ noClass: true, reason: noClassReason })}
                className="px-5 py-2.5 rounded-btn text-xs font-semibold text-white bg-slate-800 hover:bg-slate-900 shadow-md transition-all min-h-touch flex items-center gap-1.5 cursor-pointer disabled:opacity-50"
              >
                {submitMutation.isPending ? (
                  <span>Recording...</span>
                ) : (
                  <>
                    <Check className="w-4 h-4" />
                    <span>Confirm No Class</span>
                  </>
                )}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};
