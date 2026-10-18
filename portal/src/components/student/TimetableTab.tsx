// src/components/student/TimetableTab.tsx
// Phase 10C: Student Daily Timetable (Tomorrow by default, Today toggle, Course/Year filtered, PDF export)

import React, { useState, useRef, useMemo } from 'react';
import { useQuery } from '@tanstack/react-query';
import { StudentEnrollmentInfo, studentService } from '../../services/studentService';
import { dailyTimetableService, DailyTimetableEntryItem } from '../../services/dailyTimetableService';
import { exportElementToPdf } from '../../lib/pdfExporter';
import { LoadingSkeleton } from '../common/LoadingSkeleton';
import { EmptyState } from '../common/EmptyState';
import { ErrorRetry } from '../common/ErrorRetry';
import {
  Clock,
  MapPin,
  User,
  BookOpen,
  Download,
  Calendar,
  Sparkles,
  ArrowRight,
  ArrowLeft,
  GraduationCap,
} from 'lucide-react';

interface TimetableTabProps {
  enrollments: StudentEnrollmentInfo[];
}

export const TimetableTab: React.FC<TimetableTabProps> = ({ enrollments }) => {
  const printPdfRef = useRef<HTMLDivElement>(null);
  const [isExportingPdf, setIsExportingPdf] = useState(false);
  const [scheduleType, setScheduleType] = useState<'class' | 'exam'>('class');

  // Day offset: 1 = Tomorrow (Default), 0 = Today
  const [dayOffset, setDayOffset] = useState<number>(1);

  // show_today_link setting (default: on)
  const showTodayLink = useMemo(() => {
    return localStorage.getItem('mips_show_today_link') !== 'false';
  }, []);

  // Compute Indian Standard Time (Asia/Kolkata) date and heading
  const dayInfo = useMemo(() => {
    return dailyTimetableService.getKolkataDate(dayOffset);
  }, [dayOffset]);

  // Query Daily Timetable for the target date
  const {
    data: timetableData,
    isLoading,
    error,
    refetch,
    isFetching,
  } = useQuery({
    queryKey: ['dailyTimetable', dayInfo.dateStr],
    queryFn: () => dailyTimetableService.getDailyTimetable(dayInfo.dateStr, dayInfo.heading),
  });

  // Query Exam Timetable (if user toggles to exam view)
  const batchIds = enrollments.map((e) => e.batchId).filter(Boolean);
  const { data: examTimetables = [], isLoading: isExamLoading } = useQuery({
    queryKey: ['studentExamTimetable', batchIds],
    queryFn: () => studentService.getStudentExamTimetable(batchIds),
    enabled: scheduleType === 'exam',
  });

  // Filter entries to only student's ACTIVE course(s) and year
  const activeEnrollments = useMemo(() => {
    return enrollments.filter((e) => e.status === 'active');
  }, [enrollments]);

  const studentEntries = useMemo(() => {
    if (!timetableData?.entries) return [];
    if (activeEnrollments.length === 0) return timetableData.entries;

    return timetableData.entries.filter((entry) => {
      return activeEnrollments.some((enrollment) => {
        const eCourse = (enrollment.courseName || '').toLowerCase();
        const entryCourse = (entry.courseName || '').toLowerCase();

        const courseMatches =
          eCourse.includes(entryCourse) ||
          entryCourse.includes(eCourse) ||
          (entryCourse.includes('dmlt') && eCourse.includes('dmlt')) ||
          (entryCourse.includes('drt') && eCourse.includes('drt')) ||
          (entryCourse.includes('dott') && eCourse.includes('dott'));

        if (!courseMatches) return false;

        // Year matching
        const batchName = (enrollment.batchName || '').toLowerCase();
        let studentYear = '1st Year';
        if (batchName.includes('2nd') || batchName.includes('year 2') || batchName.includes('2024')) {
          studentYear = '2nd Year';
        }

        if (entry.year && (batchName.includes('1st') || batchName.includes('2nd'))) {
          if (entry.year.toLowerCase() !== studentYear.toLowerCase()) {
            return false;
          }
        }
        return true;
      });
    });
  }, [timetableData, activeEnrollments]);

  const handleDownloadPdf = async () => {
    if (!printPdfRef.current) return;
    setIsExportingPdf(true);
    try {
      const filename = `MIPS_Timetable_${dayInfo.dateStr}`;
      await exportElementToPdf(printPdfRef.current, filename, {
        orientation: 'landscape',
        margin: [8, 10, 8, 10],
      });
    } catch (err) {
      console.error('Failed to export timetable PDF:', err);
      alert('Unable to generate timetable PDF. Please try again.');
    } finally {
      setIsExportingPdf(false);
    }
  };

  if (isLoading) {
    return <LoadingSkeleton type="card" rows={4} />;
  }

  if (error) {
    return (
      <ErrorRetry
        message="Unable to load daily timetable. Please try again."
        onRetry={() => refetch()}
        isRetrying={isFetching}
      />
    );
  }

  return (
    <div className="space-y-6">
      {/* Top Controls: Mode Switcher & Download PDF */}
      <div className="flex flex-col sm:flex-row items-start sm:items-center justify-between gap-4">
        {/* Class vs Exam Switcher */}
        <div className="flex items-center gap-2 p-1.5 bg-white rounded-2xl border border-cardBorder shadow-sm">
          <button
            type="button"
            onClick={() => setScheduleType('class')}
            className={`flex items-center gap-2 px-4 py-2 rounded-xl text-xs sm:text-sm font-semibold transition-all min-h-touch ${
              scheduleType === 'class'
                ? 'bg-navy text-white shadow-sm'
                : 'text-muted hover:text-navy hover:bg-slate-50'
            }`}
          >
            <Clock className="w-4 h-4" />
            <span>Daily Class Timetable</span>
          </button>
          <button
            type="button"
            onClick={() => setScheduleType('exam')}
            className={`flex items-center gap-2 px-4 py-2 rounded-xl text-xs sm:text-sm font-semibold transition-all min-h-touch ${
              scheduleType === 'exam'
                ? 'bg-navy text-white shadow-sm'
                : 'text-muted hover:text-navy hover:bg-slate-50'
            }`}
          >
            <Calendar className="w-4 h-4" />
            <span>Exam Schedule</span>
          </button>
        </div>

        {/* Download PDF Button */}
        {scheduleType === 'class' && (
          <button
            type="button"
            onClick={handleDownloadPdf}
            disabled={isExportingPdf || !timetableData?.isPublished || studentEntries.length === 0}
            className={`inline-flex items-center gap-2 px-4 py-2 rounded-xl text-xs sm:text-sm font-semibold transition-all shadow-sm ${
              !timetableData?.isPublished || studentEntries.length === 0
                ? 'bg-slate-100 text-slate-400 cursor-not-allowed border border-slate-200'
                : 'bg-white hover:bg-slate-50 text-navy border border-cardBorder hover:border-slate-300'
            }`}
          >
            <Download className="w-4 h-4 text-brand" />
            <span>{isExportingPdf ? 'Exporting PDF...' : 'Download PDF'}</span>
          </button>
        )}
      </div>

      {/* Main Class Timetable View */}
      {scheduleType === 'class' && (
        <div className="space-y-4">
          {/* Daily Schedule Header: Heading + Today Toggle Link */}
          <div className="bg-white rounded-2xl border border-cardBorder p-4 sm:p-5 shadow-sm flex flex-col sm:flex-row sm:items-center justify-between gap-3">
            <div>
              <div className="flex items-center gap-2">
                <h2 className="text-xl sm:text-2xl font-sora font-bold text-navy">
                  {dayInfo.heading}
                </h2>
                {timetableData?.isPublished && (
                  <span className="px-2 py-0.5 rounded-full text-[11px] font-bold bg-emerald-50 text-emerald-700 border border-emerald-200">
                    PUBLISHED
                  </span>
                )}
              </div>
              <p className="text-xs sm:text-sm text-muted mt-0.5">
                Filtered for your active course enrollment and cohort
              </p>
            </div>

            {/* Small text link to toggle Today / Tomorrow */}
            {showTodayLink && (
              <div className="pt-1 sm:pt-0">
                {dayOffset === 1 ? (
                  <button
                    type="button"
                    onClick={() => setDayOffset(0)}
                    className="inline-flex items-center gap-1.5 text-xs sm:text-sm font-semibold text-brand hover:text-navy hover:underline transition-colors py-1 px-2 rounded-lg hover:bg-blue-50/50"
                  >
                    <span>Today's timetable</span>
                    <ArrowRight className="w-3.5 h-3.5" />
                  </button>
                ) : (
                  <button
                    type="button"
                    onClick={() => setDayOffset(1)}
                    className="inline-flex items-center gap-1.5 text-xs sm:text-sm font-semibold text-brand hover:text-navy hover:underline transition-colors py-1 px-2 rounded-lg hover:bg-blue-50/50"
                  >
                    <ArrowLeft className="w-3.5 h-3.5" />
                    <span>Tomorrow's timetable</span>
                  </button>
                )}
              </div>
            )}
          </div>

          {/* Timetable Content or Empty States */}
          {!timetableData?.isPublished ? (
            <EmptyState
              title={
                dayOffset === 1
                  ? "Tomorrow's timetable hasn't been published yet."
                  : "Today's timetable hasn't been published yet."
              }
              description="The academic department has not published the class schedule for this date. Please check back later."
              icon="calendar"
            />
          ) : studentEntries.length === 0 ? (
            <EmptyState
              title="No Classes Scheduled"
              description="There are no scheduled lectures or practical sessions for your active course and year on this day."
              icon="calendar"
            />
          ) : (
            <div className="space-y-3">
              {studentEntries.map((entry) => (
                <div
                  key={entry.id}
                  className="bg-white rounded-2xl border border-cardBorder p-4 sm:p-5 shadow-sm hover:shadow-md transition-all border-l-4 border-l-brand"
                >
                  <div className="flex flex-wrap items-center justify-between gap-2 pb-3 border-b border-slate-100">
                    <div className="flex items-center gap-2 text-navy font-bold text-sm sm:text-base">
                      <Clock className="w-4 h-4 text-brand" />
                      <span>
                        {entry.startTime} – {entry.endTime}
                      </span>
                    </div>
                    <div className="flex items-center gap-2">
                      <span className="px-2.5 py-1 rounded-full text-xs font-bold bg-indigo-50 text-indigo-700 border border-indigo-100">
                        {entry.courseName} • {entry.year}
                      </span>
                    </div>
                  </div>

                  <div className="pt-3">
                    <h3 className="text-base sm:text-lg font-bold text-navy mb-2">
                      {entry.subjectName}
                    </h3>
                    <div className="flex flex-wrap items-center gap-4 text-xs sm:text-sm text-muted">
                      <div className="flex items-center gap-1.5">
                        <User className="w-4 h-4 text-slate-400" />
                        <span className="text-slate-700 font-medium">{entry.teacherName}</span>
                      </div>
                      <div className="flex items-center gap-1.5">
                        <MapPin className="w-4 h-4 text-slate-400" />
                        <span className="text-slate-800 font-semibold">{entry.classRoom}</span>
                      </div>
                    </div>
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>
      )}

      {/* Exam Timetable View */}
      {scheduleType === 'exam' && (
        <div className="space-y-4">
          <div className="bg-white rounded-2xl border border-cardBorder p-4 sm:p-5 shadow-sm">
            <h2 className="text-xl sm:text-2xl font-sora font-bold text-navy">
              Published Examination Schedule
            </h2>
            <p className="text-xs sm:text-sm text-muted mt-0.5">
              Official university and internal examination timetables
            </p>
          </div>

          {examTimetables.length === 0 ? (
            <EmptyState
              title="No Exam Timetables Published"
              description="There are currently no active or published examination timetables for your enrolled cohorts."
              icon="calendar"
            />
          ) : (
            <div className="space-y-3">
              {examTimetables.map((exam) => (
                <div
                  key={exam.id}
                  className="bg-white rounded-2xl border border-cardBorder p-4 sm:p-5 shadow-sm"
                >
                  <div className="flex items-center justify-between pb-2 border-b border-slate-100">
                    <span className="font-bold text-navy text-sm sm:text-base">
                      {exam.examName} ({exam.examCode})
                    </span>
                    <span className="text-xs px-2.5 py-1 rounded-full font-semibold bg-purple-50 text-purple-700 border border-purple-100">
                      {exam.examDate}
                    </span>
                  </div>
                  <div className="pt-2 text-xs sm:text-sm text-muted flex items-center justify-between">
                    <span>{exam.subjectName}</span>
                    <span className="font-medium text-slate-700">
                      {exam.startTime} – {exam.endTime} ({exam.hallName})
                    </span>
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>
      )}

      {/* Hidden Printable Container for High-Resolution PDF Export */}
      <div className="hidden">
        <div
          ref={printPdfRef}
          className="p-8 bg-white text-slate-900 font-sans"
          style={{ width: '1000px' }}
        >
          <div className="text-center pb-4 border-b-2 border-slate-800 mb-6">
            <h1 className="text-2xl font-bold uppercase tracking-wider text-slate-900">
              Malabar Institute of Paramedical Science
            </h1>
            <p className="text-sm text-slate-600 mt-1">
              Official Class Timetable • {dayInfo.heading}
            </p>
          </div>

          <table className="w-full text-left text-xs border-collapse">
            <thead>
              <tr className="bg-slate-100 border-b border-slate-300">
                <th className="py-2.5 px-3 font-bold text-slate-700">TIME</th>
                <th className="py-2.5 px-3 font-bold text-slate-700">COURSE & YEAR</th>
                <th className="py-2.5 px-3 font-bold text-slate-700">SUBJECT</th>
                <th className="py-2.5 px-3 font-bold text-slate-700">TEACHER</th>
                <th className="py-2.5 px-3 font-bold text-slate-700">ROOM</th>
              </tr>
            </thead>
            <tbody>
              {studentEntries.map((e, idx) => (
                <tr
                  key={e.id}
                  className={`border-b border-slate-200 ${idx % 2 === 1 ? 'bg-slate-50' : 'bg-white'}`}
                >
                  <td className="py-2.5 px-3 font-bold text-slate-900 whitespace-nowrap">
                    {e.startTime} – {e.endTime}
                  </td>
                  <td className="py-2.5 px-3 text-slate-700 font-medium">
                    {e.courseName} ({e.year})
                  </td>
                  <td className="py-2.5 px-3 font-bold text-slate-900">{e.subjectName}</td>
                  <td className="py-2.5 px-3 text-slate-700">{e.teacherName}</td>
                  <td className="py-2.5 px-3 font-semibold text-slate-800">{e.classRoom}</td>
                </tr>
              ))}
            </tbody>
          </table>

          <div className="mt-8 pt-4 border-t border-slate-200 flex justify-between text-[11px] text-slate-500">
            <span>Generated on {new Date().toLocaleDateString('en-IN')}</span>
            <span>MIPS Academic ERP System</span>
          </div>
        </div>
      </div>
    </div>
  );
};
