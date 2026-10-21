// src/components/teacher/TeacherMarksTab.tsx
// Teacher Examination Marks Entry with Live Validation, Auto-advance, Real-time Statistics & Submission Confirmation

import React, { useState, useEffect, useMemo, useRef } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  teacherService,
  ExamOption,
  ExamSubjectOption,
  StudentMarkItem,
} from '../../services/teacherService';
import { LoadingSkeleton } from '../common/LoadingSkeleton';
import { EmptyState } from '../common/EmptyState';
import { ErrorRetry } from '../common/ErrorRetry';
import {
  Award,
  BookOpen,
  CheckCircle2,
  AlertCircle,
  Search,
  Save,
  Send,
  Sparkles,
  TrendingUp,
  Percent,
  Check,
  X,
  FileCheck,
} from 'lucide-react';

import { useOnlineStatus } from '../../context/OnlineStatusContext';

interface TeacherMarksTabProps {
  teacherId: number;
}

export const TeacherMarksTab: React.FC<TeacherMarksTabProps> = ({ teacherId }) => {
  const queryClient = useQueryClient();
  const { isOnline } = useOnlineStatus();

  // Selection Filters
  const [selectedExamId, setSelectedExamId] = useState<number | null>(null);
  const [selectedSubjectId, setSelectedSubjectId] = useState<number | null>(null);
  const [searchQuery, setSearchQuery] = useState('');

  // Marks State Map: studentId -> { marks: number | string, isAbsent: boolean }
  const [studentMarksState, setStudentMarksState] = useState<
    Record<number, { marks: string; isAbsent: boolean }>
  >({});

  // UI Modals & Notifications
  const [isSubmitModalOpen, setIsSubmitModalOpen] = useState(false);
  const [feedback, setFeedback] = useState<{ type: 'success' | 'error'; message: string } | null>(
    null
  );

  // Input refs for auto-advancing to next input on Enter
  const inputRefs = useRef<Record<number, HTMLInputElement | null>>({});

  // 1. Fetch Teacher Assigned Batches
  const { data: batches = [] } = useQuery({
    queryKey: ['teacherAssignedBatches', teacherId],
    queryFn: () => teacherService.getAssignedBatches(teacherId),
  });

  const batchIds = useMemo(() => batches.map((b) => b.batchId), [batches]);

  // 2. Fetch Exams for Teacher's Batches (draft or mark_entry)
  const {
    data: exams = [],
    isLoading: loadingExams,
    error: examsError,
  } = useQuery({
    queryKey: ['teacherExams', batchIds],
    queryFn: () => teacherService.getTeacherExams(batchIds),
    enabled: batchIds.length > 0,
  });

  // Set default selected exam
  useEffect(() => {
    if (exams.length > 0 && selectedExamId === null) {
      setSelectedExamId(exams[0].id);
    }
  }, [exams, selectedExamId]);

  const selectedExam: ExamOption | undefined = exams.find((e) => e.id === selectedExamId);

  // 3. Fetch Subjects for Selected Exam
  const {
    data: examSubjects = [],
    isLoading: loadingSubjects,
  } = useQuery({
    queryKey: ['examSubjects', selectedExamId],
    queryFn: () => (selectedExamId ? teacherService.getExamSubjects(selectedExamId) : Promise.resolve([])),
    enabled: Boolean(selectedExamId),
  });

  // Set default subject when loaded
  useEffect(() => {
    if (examSubjects.length > 0) {
      // Keep existing subject if valid for this exam, otherwise default to first
      if (!selectedSubjectId || !examSubjects.some((s) => s.id === selectedSubjectId)) {
        setSelectedSubjectId(examSubjects[0].id);
      }
    } else {
      setSelectedSubjectId(null);
    }
  }, [examSubjects, selectedExamId]);

  const selectedSubject: ExamSubjectOption | undefined = examSubjects.find(
    (s) => s.id === selectedSubjectId
  );

  // 4. Fetch Students for Exam's Batch
  const {
    data: students = [],
    isLoading: loadingStudents,
  } = useQuery({
    queryKey: ['batchStudents', selectedExam?.batchId],
    queryFn: () =>
      selectedExam?.batchId
        ? teacherService.getBatchStudents(selectedExam.batchId)
        : Promise.resolve([]),
    enabled: Boolean(selectedExam?.batchId),
  });

  // 5. Fetch Existing Marks for (Exam, Subject)
  const {
    data: existingMarks = {},
    isLoading: loadingMarks,
    refetch: refetchMarks,
  } = useQuery({
    queryKey: ['examSubjectMarks', selectedExamId, selectedSubjectId],
    queryFn: () =>
      selectedExamId && selectedSubjectId
        ? teacherService.getExistingMarks(selectedExamId, selectedSubjectId)
        : Promise.resolve({}),
    enabled: Boolean(selectedExamId && selectedSubjectId),
  });

  // Synchronize state when students or existing marks change
  useEffect(() => {
    if (students.length === 0) return;

    setStudentMarksState((prev) => {
      const initialMap: Record<number, { marks: string; isAbsent: boolean }> = {};
      students.forEach((s) => {
        if (prev[s.id] && (prev[s.id].marks !== '' || prev[s.id].isAbsent)) {
          initialMap[s.id] = prev[s.id];
          return;
        }
        const existing = existingMarks[s.id];
        if (existing) {
          initialMap[s.id] = {
            marks: existing.marksObtained !== null ? String(existing.marksObtained) : '',
            isAbsent: existing.isAbsent,
          };
        } else {
          initialMap[s.id] = { marks: '', isAbsent: false };
        }
      });
      return initialMap;
    });
  }, [students, existingMarks, selectedSubjectId]);

  // Handle Mark Change
  const handleMarkChange = (studentId: number, val: string) => {
    setStudentMarksState((prev) => ({
      ...prev,
      [studentId]: {
        ...prev[studentId],
        marks: val,
        isAbsent: false, // uncheck absent if entering marks
      },
    }));
  };

  // Handle Absent Toggle
  const handleAbsentToggle = (studentId: number, isAbsent: boolean) => {
    setStudentMarksState((prev) => ({
      ...prev,
      [studentId]: {
        marks: isAbsent ? '0' : prev[studentId]?.marks === '0' ? '' : prev[studentId]?.marks || '',
        isAbsent,
      },
    }));
  };

  // Filter students by search
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

  // Max and Pass marks
  const maxMarks = selectedSubject?.maxMarks || 100;
  const passMarks = selectedSubject?.passMarks || 40;

  // Validation Check: Any invalid marks?
  const invalidStudents = useMemo(() => {
    const invalidIds: number[] = [];
    students.forEach((s) => {
      const item = studentMarksState[s.id];
      if (item && !item.isAbsent && item.marks !== '') {
        const num = Number(item.marks);
        if (isNaN(num) || num < 0 || num > maxMarks) {
          invalidIds.push(s.id);
        }
      }
    });
    return invalidIds;
  }, [students, studentMarksState, maxMarks]);

  // Live Statistics Calculation
  const liveStats = useMemo(() => {
    let enteredCount = 0;
    let absentCount = 0;
    let totalScore = 0;
    let scoreCount = 0;
    let highest = -Infinity;
    let lowest = Infinity;
    let passCount = 0;

    students.forEach((s) => {
      const item = studentMarksState[s.id];
      if (!item) return;

      if (item.isAbsent) {
        enteredCount++;
        absentCount++;
      } else if (item.marks !== '' && !isNaN(Number(item.marks))) {
        const score = Number(item.marks);
        if (score >= 0 && score <= maxMarks) {
          enteredCount++;
          scoreCount++;
          totalScore += score;
          if (score > highest) highest = score;
          if (score < lowest) lowest = score;
          if (score >= passMarks) passCount++;
        }
      }
    });

    const average = scoreCount > 0 ? (totalScore / scoreCount).toFixed(1) : '—';
    return {
      enteredCount,
      totalStudents: students.length,
      absentCount,
      average,
      highest: highest !== -Infinity ? highest : '—',
      lowest: lowest !== Infinity ? lowest : '—',
      passCount,
    };
  }, [students, studentMarksState, maxMarks, passMarks]);

  // Keyboard Navigation: Enter key advances to next student's input
  const handleKeyDown = (e: React.KeyboardEvent, index: number) => {
    if (e.key === 'Enter') {
      e.preventDefault();
      const nextStudent = filteredStudents[index + 1];
      if (nextStudent && inputRefs.current[nextStudent.id]) {
        inputRefs.current[nextStudent.id]?.focus();
      }
    }
  };

  // Mutations
  const saveMarksMutation = useMutation({
    mutationFn: async (isFinalSubmission: boolean) => {
      if (!selectedExamId || !selectedSubjectId) return;

      const marksPayload: StudentMarkItem[] = students.map((s) => {
        const state = studentMarksState[s.id] || { marks: '', isAbsent: false };
        const num = state.marks !== '' ? Number(state.marks) : null;
        return {
          studentId: s.id,
          name: s.name,
          registrationNumber: s.registrationNumber,
          admissionNumber: s.admissionNumber,
          marksObtained: state.isAbsent ? null : num,
          isAbsent: state.isAbsent,
        };
      });

      return teacherService.saveOrSubmitMarks(
        selectedExamId,
        selectedSubjectId,
        marksPayload,
        isFinalSubmission
      );
    },
    onSuccess: (_, isFinal) => {
      queryClient.invalidateQueries({
        queryKey: ['examSubjectMarks', selectedExamId, selectedSubjectId],
      });
      setIsSubmitModalOpen(false);
      setFeedback({
        type: 'success',
        message: isFinal
          ? `Official marks submitted successfully for ${selectedSubject?.subjectName || 'Subject'}.`
          : `Marks draft saved successfully.`,
      });
      setTimeout(() => setFeedback(null), 4000);
    },
    onError: (err: any) => {
      setFeedback({
        type: 'error',
        message: err.message || 'Failed to save marks. Please review entered scores.',
      });
    },
  });

  if (loadingExams) {
    return <LoadingSkeleton type="card" rows={4} />;
  }

  if (exams.length === 0) {
    return (
      <EmptyState
        title="No Active Exams Scheduled"
        description="There are currently no exams in draft or mark entry mode for the batches you teach. Once an exam is scheduled by the administration, you can enter marks here."
        icon="award"
      />
    );
  }

  return (
    <div className="space-y-6">
      {/* Top Filter Bar: Exam & Subject Selector */}
      <div className="bg-white rounded-card-lg border border-cardBorder shadow-card p-5 sm:p-6">
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
          {/* Exam Selector */}
          <div>
            <label className="block text-xs font-bold font-sora text-navy uppercase tracking-wider mb-1.5">
              Select Examination
            </label>
            <select
              value={selectedExamId || ''}
              onChange={(e) => setSelectedExamId(Number(e.target.value))}
              className="w-full px-3.5 py-2.5 text-base sm:text-sm rounded-input border border-inputBorder focus:outline-none focus:ring-2 focus:ring-focusRing focus:border-primary text-navy bg-white min-h-touch"
            >
              {exams.map((exam) => (
                <option key={exam.id} value={exam.id}>
                  {exam.name} ({exam.examCode}) • {exam.courseName} - {exam.batchName}
                </option>
              ))}
            </select>
          </div>

          {/* Subject Selector */}
          <div>
            <label className="block text-xs font-bold font-sora text-navy uppercase tracking-wider mb-1.5">
              Select Subject
            </label>
            <select
              value={selectedSubjectId || ''}
              onChange={(e) => setSelectedSubjectId(Number(e.target.value))}
              disabled={loadingSubjects || examSubjects.length === 0}
              className="w-full px-3.5 py-2.5 text-base sm:text-sm rounded-input border border-inputBorder focus:outline-none focus:ring-2 focus:ring-focusRing focus:border-primary text-navy bg-white min-h-touch disabled:opacity-50"
            >
              {examSubjects.map((sub) => (
                <option key={sub.id} value={sub.id}>
                  {sub.subjectName} (Max: {sub.maxMarks}, Pass: {sub.passMarks})
                </option>
              ))}
            </select>
          </div>
        </div>

        {/* Selected Subject Rules Banner */}
        {selectedSubject && (
          <div className="mt-4 pt-4 border-t border-cardBorder flex flex-wrap items-center justify-between gap-3 text-xs">
            <div className="flex items-center gap-2">
              <span className="px-2.5 py-1 rounded-full bg-primary/10 text-primary font-bold">
                Max Marks: {selectedSubject.maxMarks}
              </span>
              <span className="px-2.5 py-1 rounded-full bg-emerald-100 text-emerald-800 font-bold">
                Pass Marks: {selectedSubject.passMarks}
              </span>
            </div>
            <span className="text-muted text-[11px]">
              * Press <kbd className="px-1.5 py-0.5 rounded bg-surface border font-mono">Enter</kbd> to advance to the next student.
            </span>
          </div>
        )}

        {/* Notification Feedback */}
        {feedback && (
          <div
            className={`mt-4 p-3.5 rounded-xl border flex items-center justify-between text-xs ${
              feedback.type === 'success'
                ? 'bg-success-bg border-success-text/20 text-success-text'
                : 'bg-error-bg border-error-border text-error-text'
            }`}
          >
            <div className="flex items-center gap-2">
              {feedback.type === 'success' ? (
                <CheckCircle2 className="w-4 h-4 flex-shrink-0" />
              ) : (
                <AlertCircle className="w-4 h-4 flex-shrink-0" />
              )}
              <span>{feedback.message}</span>
            </div>
            <button
              type="button"
              onClick={() => setFeedback(null)}
              className="p-1 hover:opacity-70"
            >
              <X className="w-4 h-4" />
            </button>
          </div>
        )}
      </div>

      {/* Live Statistics Cards */}
      <div className="grid grid-cols-2 sm:grid-cols-5 gap-3">
        <div className="bg-white rounded-card-lg border border-cardBorder p-4 shadow-card">
          <span className="text-[10px] font-bold text-muted uppercase tracking-wider block">
            Entered
          </span>
          <div className="font-sora font-extrabold text-lg text-navy mt-1">
            {liveStats.enteredCount} / {liveStats.totalStudents}
          </div>
          <span className="text-[11px] text-muted">
            {liveStats.absentCount} marked absent
          </span>
        </div>

        <div className="bg-white rounded-card-lg border border-cardBorder p-4 shadow-card">
          <span className="text-[10px] font-bold text-muted uppercase tracking-wider block">
            Average Score
          </span>
          <div className="font-sora font-extrabold text-lg text-primary mt-1">
            {liveStats.average}
          </div>
          <span className="text-[11px] text-muted">Excludes absentees</span>
        </div>

        <div className="bg-white rounded-card-lg border border-cardBorder p-4 shadow-card">
          <span className="text-[10px] font-bold text-muted uppercase tracking-wider block">
            Highest Mark
          </span>
          <div className="font-sora font-extrabold text-lg text-emerald-700 mt-1">
            {liveStats.highest}
          </div>
          <span className="text-[11px] text-muted">Max: {maxMarks}</span>
        </div>

        <div className="bg-white rounded-card-lg border border-cardBorder p-4 shadow-card">
          <span className="text-[10px] font-bold text-muted uppercase tracking-wider block">
            Lowest Mark
          </span>
          <div className="font-sora font-extrabold text-lg text-amber-700 mt-1">
            {liveStats.lowest}
          </div>
          <span className="text-[11px] text-muted">Min: 0</span>
        </div>

        <div className="bg-white rounded-card-lg border border-cardBorder p-4 shadow-card col-span-2 sm:col-span-1">
          <span className="text-[10px] font-bold text-muted uppercase tracking-wider block">
            Pass Count
          </span>
          <div className="font-sora font-extrabold text-lg text-navy mt-1">
            {liveStats.passCount}
          </div>
          <span className="text-[11px] text-muted">Cutoff: {passMarks}+</span>
        </div>
      </div>

      {/* Marks Entry Sheet */}
      <div className="bg-white rounded-card-lg border border-cardBorder shadow-card p-5 sm:p-6 space-y-4">
        {/* Search */}
        <div className="relative max-w-sm pb-2">
          <input
            type="text"
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            placeholder="Search candidate name or register number..."
            className="w-full pl-9 pr-3.5 py-2 text-base sm:text-xs rounded-input border border-inputBorder focus:outline-none focus:ring-2 focus:ring-focusRing focus:border-primary text-navy"
          />
          <Search className="w-4 h-4 text-muted absolute left-3 top-1/2 -translate-y-1/2" />
        </div>

        {/* Student Marks Table */}
        {loadingStudents ? (
          <LoadingSkeleton type="table" rows={6} />
        ) : filteredStudents.length === 0 ? (
          <div className="py-12 text-center text-xs text-muted">
            No students found in this batch.
          </div>
        ) : (
          <div className="divide-y divide-cardBorder">
            {filteredStudents.map((student, idx) => {
              const state = studentMarksState[student.id] || { marks: '', isAbsent: false };
              const num = state.marks !== '' ? Number(state.marks) : null;
              const isInvalid =
                !state.isAbsent &&
                state.marks !== '' &&
                (isNaN(Number(state.marks)) || Number(state.marks) < 0 || Number(state.marks) > maxMarks);

              const isPass = num !== null && num >= passMarks && !state.isAbsent;

              return (
                <div
                  key={student.id}
                  className={`py-3.5 flex flex-col sm:flex-row sm:items-center justify-between gap-3 px-2 rounded-xl transition-colors ${
                    isInvalid ? 'bg-error-bg/30' : 'hover:bg-surface/50'
                  }`}
                >
                  {/* Candidate Info */}
                  <div className="flex items-center gap-3 min-w-0">
                    <span className="text-xs font-bold font-sora text-muted w-6 text-right">
                      {idx + 1}.
                    </span>
                    <div className="truncate">
                      <h4 className="font-sora font-semibold text-sm text-navy truncate">
                        {student.name}
                      </h4>
                      <p className="text-[11px] text-muted truncate">
                        Reg: {student.registrationNumber || student.admissionNumber} • Adm: #{student.admissionNumber}
                      </p>
                    </div>
                  </div>

                  {/* Input Fields & Absent Checkbox */}
                  <div className="flex items-center gap-3 self-end sm:self-center">
                    {/* Absent Toggle Checkbox */}
                    <label className="flex items-center gap-1.5 cursor-pointer text-xs font-semibold text-slate-600 select-none min-h-touch">
                      <input
                        type="checkbox"
                        checked={state.isAbsent}
                        onChange={(e) => handleAbsentToggle(student.id, e.target.checked)}
                        className="w-4 h-4 rounded text-primary focus:ring-focusRing"
                      />
                      <span>Absent</span>
                    </label>

                    {/* Numeric Marks Input */}
                    <div className="relative">
                      <input
                        ref={(el) => (inputRefs.current[student.id] = el)}
                        type="number"
                        inputMode="decimal"
                        min={0}
                        max={maxMarks}
                        step="any"
                        disabled={state.isAbsent}
                        value={state.isAbsent ? '0' : state.marks}
                        onChange={(e) => handleMarkChange(student.id, e.target.value)}
                        onKeyDown={(e) => handleKeyDown(e, idx)}
                        placeholder={`0 – ${maxMarks}`}
                        className={`w-24 sm:w-28 px-2 sm:px-3 py-2 text-base sm:text-sm text-right font-sora font-bold rounded-input border transition-all min-h-touch ${
                          state.isAbsent
                            ? 'bg-slate-100 text-slate-400 border-slate-200'
                            : isInvalid
                            ? 'border-error-border ring-2 ring-error-border/40 text-error-text bg-white'
                            : 'border-inputBorder text-navy focus:outline-none focus:ring-2 focus:ring-focusRing focus:border-primary bg-white'
                        }`}
                      />
                      {isInvalid && (
                        <span className="absolute -bottom-4 right-0 text-[10px] text-error-text font-bold">
                          Max {maxMarks}
                        </span>
                      )}
                    </div>

                    {/* Result Status Indicator */}
                    <div className="w-16 text-center">
                      {state.isAbsent ? (
                        <span className="text-[11px] font-bold text-rose-700 bg-rose-50 px-2 py-0.5 rounded-full border border-rose-200">
                          ABS
                        </span>
                      ) : state.marks !== '' && !isInvalid ? (
                        <span
                          className={`text-[11px] font-bold px-2 py-0.5 rounded-full ${
                            isPass
                              ? 'text-emerald-800 bg-emerald-50 border border-emerald-200'
                              : 'text-amber-800 bg-amber-50 border border-amber-200'
                          }`}
                        >
                          {isPass ? 'PASS' : 'FAIL'}
                        </span>
                      ) : (
                        <span className="text-[11px] text-muted">—</span>
                      )}
                    </div>
                  </div>
                </div>
              );
            })}
          </div>
        )}

        {/* Sticky Actions Bar */}
        <div className="pt-4 border-t border-cardBorder flex flex-col sm:flex-row sm:items-center justify-between gap-3 sticky bottom-2 bg-white/95 backdrop-blur-md p-3.5 rounded-2xl shadow-card border">
          <div className="text-xs text-muted">
            {invalidStudents.length > 0 ? (
              <span className="text-error-accent font-bold">
                ⚠️ {invalidStudents.length} invalid score(s) detected. Fix errors before submitting.
              </span>
            ) : (
              <span>All entered marks must be verified before official submission.</span>
            )}
          </div>

          <div className="grid grid-cols-2 sm:flex items-center gap-2 w-full sm:w-auto">
            <button
              type="button"
              onClick={() => saveMarksMutation.mutate(false)}
              disabled={saveMarksMutation.isPending || invalidStudents.length > 0}
              className="inline-flex items-center justify-center gap-1.5 px-4 py-2.5 rounded-button text-xs font-semibold text-navy bg-surface hover:bg-slate-200 transition-colors min-h-touch disabled:opacity-50 w-full sm:w-auto"
            >
              <Save className="w-3.5 h-3.5" />
              <span>{saveMarksMutation.isPending ? 'Saving...' : 'Save Draft'}</span>
            </button>

            <button
              type="button"
              onClick={() => setIsSubmitModalOpen(true)}
              disabled={saveMarksMutation.isPending || invalidStudents.length > 0 || !isOnline}
              title={!isOnline ? 'Connect to the internet to submit.' : undefined}
              className="inline-flex items-center justify-center gap-1.5 px-5 py-2.5 rounded-button text-xs font-semibold text-white bg-primary hover:bg-primary-hover transition-colors shadow-sm min-h-touch disabled:opacity-50 w-full sm:w-auto"
            >
              <Send className="w-3.5 h-3.5" />
              <span>Submit Marks</span>
            </button>
          </div>
        </div>
      </div>

      {/* Confirmation Modal on Submit */}
      {isSubmitModalOpen && (
        <div
          role="dialog"
          aria-modal="true"
          className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-navy/60 backdrop-blur-sm animate-fade-in"
        >
          <div className="w-full max-w-md bg-white rounded-card-lg border border-cardBorder shadow-2xl p-6 relative max-h-[90dvh] overflow-y-auto">
            <div className="flex items-center gap-3 mb-3">
              <div className="p-2.5 rounded-xl bg-primary/10 text-primary">
                <FileCheck className="w-5 h-5" />
              </div>
              <div>
                <h3 className="font-sora font-bold text-base text-navy">
                  Confirm Marks Submission
                </h3>
                <p className="text-xs text-muted">
                  {selectedExam?.name} • {selectedSubject?.subjectName}
                </p>
              </div>
            </div>

            <div className="p-4 rounded-xl bg-surface border border-cardBorder space-y-2 text-xs my-4">
              <div className="flex items-center justify-between">
                <span className="text-muted">Total Entered:</span>
                <strong className="font-sora text-navy">
                  {liveStats.enteredCount} of {liveStats.totalStudents} students
                </strong>
              </div>
              <div className="flex items-center justify-between">
                <span className="text-muted">Marked Absent:</span>
                <strong className="font-sora text-rose-700">{liveStats.absentCount}</strong>
              </div>
              <div className="flex items-center justify-between">
                <span className="text-muted">Class Average:</span>
                <strong className="font-sora text-primary">{liveStats.average}</strong>
              </div>
              <div className="flex items-center justify-between">
                <span className="text-muted">Pass Count:</span>
                <strong className="font-sora text-emerald-700">{liveStats.passCount} passed</strong>
              </div>
            </div>

            <p className="text-[11px] text-muted leading-relaxed mb-4">
              Once submitted, marks will be recorded into the official student ledger and prepared for grading compilation. Confirm submission?
            </p>

            <div className="flex flex-col-reverse sm:flex-row items-stretch sm:items-center justify-end gap-2 pt-2 border-t border-cardBorder">
              <button
                type="button"
                onClick={() => setIsSubmitModalOpen(false)}
                className="px-4 py-2.5 rounded-button text-xs font-semibold text-muted hover:text-navy hover:bg-surface min-h-touch flex items-center justify-center w-full sm:w-auto"
              >
                Cancel
              </button>
              <button
                type="button"
                onClick={() => saveMarksMutation.mutate(true)}
                disabled={saveMarksMutation.isPending}
                className="px-5 py-2.5 rounded-button text-xs font-semibold text-white bg-primary hover:bg-primary-hover shadow-sm min-h-touch flex items-center justify-center gap-2 w-full sm:w-auto"
              >
                {saveMarksMutation.isPending ? (
                  <>
                    <div className="w-3.5 h-3.5 border-2 border-white border-t-transparent rounded-full animate-spin" />
                    <span>Submitting...</span>
                  </>
                ) : (
                  <span>Confirm & Submit</span>
                )}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};
