// src/components/teacher/TeacherTimetableTab.tsx
// Phase 10C: Teacher Daily Timetable (Tomorrow by default, Today toggle, All rows with My Classes Highlighted & Toggle, PDF export)

import React, { useState, useRef, useMemo } from 'react';
import { useQuery } from '@tanstack/react-query';
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
  Filter,
  CheckCircle2,
  ArrowRight,
  ArrowLeft,
  Sparkles,
  Layers,
} from 'lucide-react';

interface TeacherTimetableTabProps {
  teacherId: number;
  teacherName: string;
}

export const TeacherTimetableTab: React.FC<TeacherTimetableTabProps> = ({
  teacherId,
  teacherName,
}) => {
  const printPdfRef = useRef<HTMLDivElement>(null);
  const [isExportingPdf, setIsExportingPdf] = useState(false);

  // Day offset: 1 = Tomorrow (Default), 0 = Today
  const [dayOffset, setDayOffset] = useState<number>(1);

  // "My classes only" toggle
  const [myClassesOnly, setMyClassesOnly] = useState<boolean>(false);

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

  // Helper to determine if a class belongs to the logged-in teacher
  const isTeacherClass = (entry: DailyTimetableEntryItem): boolean => {
    if (!teacherName || !entry.teacherName) return false;
    const cleanTeacher = teacherName
      .toLowerCase()
      .replace(/^(prof\.|dr\.|mr\.|mrs\.|ms\.)\s*/, '')
      .trim();
    const cleanEntry = entry.teacherName
      .toLowerCase()
      .replace(/^(prof\.|dr\.|mr\.|mrs\.|ms\.)\s*/, '')
      .trim();

    return cleanTeacher.includes(cleanEntry) || cleanEntry.includes(cleanTeacher);
  };

  // Filter and sort entries
  const displayedEntries = useMemo(() => {
    if (!timetableData?.entries) return [];
    let list = [...timetableData.entries];

    if (myClassesOnly) {
      list = list.filter((e) => isTeacherClass(e));
    }

    return list;
  }, [timetableData, myClassesOnly, teacherName]);

  const totalMyClasses = useMemo(() => {
    if (!timetableData?.entries) return 0;
    return timetableData.entries.filter((e) => isTeacherClass(e)).length;
  }, [timetableData, teacherName]);

  const handleDownloadPdf = async () => {
    if (!printPdfRef.current) return;
    setIsExportingPdf(true);
    try {
      const filename = `MIPS_Faculty_Timetable_${dayInfo.dateStr}_${teacherName.replace(/\s+/g, '_')}`;
      await exportElementToPdf(printPdfRef.current, filename, {
        orientation: 'landscape',
        margin: [8, 10, 8, 10],
      });
    } catch (err) {
      console.error('Failed to export faculty timetable PDF:', err);
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
        message="Unable to load faculty timetable. Please try again."
        onRetry={() => refetch()}
        isRetrying={isFetching}
      />
    );
  }

  return (
    <div className="space-y-6">
      {/* Top Header Card */}
      <div className="bg-white rounded-2xl border border-cardBorder p-4 sm:p-5 shadow-sm flex flex-col sm:flex-row sm:items-center justify-between gap-4">
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
            Faculty schedule for all departments with personal lecture highlights
          </p>

          {/* Small text link to toggle Today / Tomorrow */}
          {showTodayLink && (
            <div className="mt-2">
              {dayOffset === 1 ? (
                <button
                  type="button"
                  onClick={() => setDayOffset(0)}
                  className="inline-flex items-center gap-1.5 text-xs sm:text-sm font-semibold text-brand hover:text-navy hover:underline transition-colors py-0.5 rounded-lg"
                >
                  <span>Today's timetable</span>
                  <ArrowRight className="w-3.5 h-3.5" />
                </button>
              ) : (
                <button
                  type="button"
                  onClick={() => setDayOffset(1)}
                  className="inline-flex items-center gap-1.5 text-xs sm:text-sm font-semibold text-brand hover:text-navy hover:underline transition-colors py-0.5 rounded-lg"
                >
                  <ArrowLeft className="w-3.5 h-3.5" />
                  <span>Tomorrow's timetable</span>
                </button>
              )}
            </div>
          )}
        </div>

        {/* Action Controls: "My Classes Only" switch + PDF Download */}
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-2.5 w-full sm:w-auto">
          {/* "My classes only" toggle */}
          <button
            type="button"
            onClick={() => setMyClassesOnly((prev) => !prev)}
            className={`inline-flex items-center justify-center gap-2 px-3.5 py-2.5 rounded-xl text-xs sm:text-sm font-semibold transition-all border min-h-touch w-full sm:w-auto ${
              myClassesOnly
                ? 'bg-emerald-600 text-white border-emerald-600 shadow-sm'
                : 'bg-white hover:bg-slate-50 text-slate-700 border-cardBorder'
            }`}
          >
            <CheckCircle2 className="w-4 h-4" />
            <span>My classes only ({totalMyClasses})</span>
          </button>

          {/* PDF Download Button */}
          <button
            type="button"
            onClick={handleDownloadPdf}
            disabled={isExportingPdf || !timetableData?.isPublished || displayedEntries.length === 0}
            className={`inline-flex items-center justify-center gap-2 px-3.5 py-2.5 rounded-xl text-xs sm:text-sm font-semibold transition-all shadow-sm min-h-touch w-full sm:w-auto ${
              !timetableData?.isPublished || displayedEntries.length === 0
                ? 'bg-slate-100 text-slate-400 cursor-not-allowed border border-slate-200'
                : 'bg-white hover:bg-slate-50 text-navy border border-cardBorder hover:border-slate-300'
            }`}
          >
            <Download className="w-4 h-4 text-brand" />
            <span>{isExportingPdf ? 'Exporting...' : 'Download PDF'}</span>
          </button>
        </div>
      </div>

      {/* Main Content Area */}
      {!timetableData?.isPublished ? (
        <EmptyState
          title={
            dayOffset === 1
              ? "Tomorrow's timetable hasn't been published yet."
              : "Today's timetable hasn't been published yet."
          }
          description="The administrative office has not published the institutional daily timetable for this date yet."
          icon="calendar"
        />
      ) : displayedEntries.length === 0 ? (
        <EmptyState
          title="No Classes Found"
          description={
            myClassesOnly
              ? "You do not have any classes assigned on this date. Toggle off 'My classes only' to view the full departmental schedule."
              : "No classes are scheduled for this day."
          }
          icon="calendar"
        />
      ) : (
        <div className="space-y-3">
          {displayedEntries.map((entry) => {
            const isMine = isTeacherClass(entry);

            return (
              <div
                key={entry.id}
                className={`rounded-2xl border p-4 sm:p-5 shadow-sm transition-all ${
                  isMine
                    ? 'bg-emerald-50/40 border-emerald-300 border-l-4 border-l-emerald-600 hover:shadow-md'
                    : 'bg-white border-cardBorder hover:shadow-md'
                }`}
              >
                <div className="flex flex-wrap items-center justify-between gap-2 pb-3 border-b border-slate-100">
                  <div className="flex items-center gap-2 text-navy font-bold text-sm sm:text-base">
                    <Clock className={`w-4 h-4 ${isMine ? 'text-emerald-700' : 'text-brand'}`} />
                    <span>
                      {entry.startTime} – {entry.endTime}
                    </span>
                  </div>

                  <div className="flex items-center gap-2">
                    {isMine && (
                      <span className="px-2.5 py-0.5 rounded-full text-xs font-bold bg-emerald-100 text-emerald-800 border border-emerald-300 flex items-center gap-1">
                        <Sparkles className="w-3 h-3 text-emerald-600" />
                        <span>Your Class</span>
                      </span>
                    )}
                    <span className="px-2.5 py-0.5 rounded-full text-xs font-bold bg-indigo-50 text-indigo-700 border border-indigo-100">
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
                      <span
                        className={`font-semibold ${
                          isMine ? 'text-emerald-900 font-bold' : 'text-slate-700'
                        }`}
                      >
                        {entry.teacherName}
                      </span>
                    </div>
                    <div className="flex items-center gap-1.5">
                      <MapPin className="w-4 h-4 text-slate-400" />
                      <span className="text-slate-800 font-semibold">{entry.classRoom}</span>
                    </div>
                  </div>
                </div>
              </div>
            );
          })}
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
              Faculty Daily Timetable • {dayInfo.heading}
            </p>
            <p className="text-xs text-slate-500 mt-0.5">Faculty: {teacherName}</p>
          </div>

          <table className="w-full text-left text-xs border-collapse">
            <thead>
              <tr className="bg-slate-100 border-b border-slate-300">
                <th className="py-2.5 px-3 font-bold text-slate-700">TIME</th>
                <th className="py-2.5 px-3 font-bold text-slate-700">COURSE & YEAR</th>
                <th className="py-2.5 px-3 font-bold text-slate-700">SUBJECT</th>
                <th className="py-2.5 px-3 font-bold text-slate-700">FACULTY</th>
                <th className="py-2.5 px-3 font-bold text-slate-700">ROOM</th>
              </tr>
            </thead>
            <tbody>
              {displayedEntries.map((e, idx) => {
                const isMine = isTeacherClass(e);
                return (
                  <tr
                    key={e.id}
                    className={`border-b border-slate-200 ${
                      isMine ? 'bg-emerald-50/60 font-semibold' : idx % 2 === 1 ? 'bg-slate-50' : 'bg-white'
                    }`}
                  >
                    <td className="py-2.5 px-3 text-slate-900 whitespace-nowrap">
                      {e.startTime} – {e.endTime}
                    </td>
                    <td className="py-2.5 px-3 text-slate-700">
                      {e.courseName} ({e.year})
                    </td>
                    <td className="py-2.5 px-3 text-slate-900">{e.subjectName}</td>
                    <td className="py-2.5 px-3 text-slate-700">
                      {e.teacherName} {isMine && '(You)'}
                    </td>
                    <td className="py-2.5 px-3 text-slate-800">{e.classRoom}</td>
                  </tr>
                );
              })}
            </tbody>
          </table>

          <div className="mt-8 pt-4 border-t border-slate-200 flex justify-between text-[11px] text-slate-500">
            <span>Generated on {new Date().toLocaleDateString('en-IN')}</span>
            <span>MIPS Faculty Portal</span>
          </div>
        </div>
      </div>
    </div>
  );
};
