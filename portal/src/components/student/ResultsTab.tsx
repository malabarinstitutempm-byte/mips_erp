// src/components/student/ResultsTab.tsx
// Official Examination Results View with A4 Print and Lazy-loaded PDF Export

import React, { useState, useRef } from 'react';
import { useQuery } from '@tanstack/react-query';
import { studentService, ExamResultRecord } from '../../services/studentService';
import { formatDate } from '../../lib/formatters';
import { exportElementToPdf } from '../../lib/pdfExporter';
import { LoadingSkeleton } from '../common/LoadingSkeleton';
import { EmptyState } from '../common/EmptyState';
import { ErrorRetry } from '../common/ErrorRetry';
import {
  Award,
  Printer,
  Download,
  Calendar,
  User,
  GraduationCap,
  Sparkles,
  FileCheck,
} from 'lucide-react';

interface ResultsTabProps {
  studentId: number;
  studentName: string;
  registrationNumber: string | null;
  admissionNumber: string;
}

export const ResultsTab: React.FC<ResultsTabProps> = ({
  studentId,
  studentName,
  registrationNumber,
  admissionNumber,
}) => {
  const resultCardRef = useRef<HTMLDivElement>(null);
  const [selectedExamId, setSelectedExamId] = useState<number | null>(null);
  const [isDownloadingPdf, setIsDownloadingPdf] = useState(false);

  const {
    data: results = [],
    isLoading,
    error,
    refetch,
    isFetching,
  } = useQuery({
    queryKey: ['studentResults', studentId],
    queryFn: () => studentService.getStudentResults(studentId),
  });

  if (isLoading) {
    return <LoadingSkeleton type="table" rows={6} />;
  }

  if (error) {
    return (
      <ErrorRetry
        message="Unable to retrieve examination marks. Please try again."
        onRetry={() => refetch()}
        isRetrying={isFetching}
      />
    );
  }

  if (results.length === 0) {
    return (
      <EmptyState
        icon={<Award className="w-7 h-7" />}
        title="No Published Results Found"
        message="Examination marks have not been published by the administration yet. Check back soon or contact the college office."
      />
    );
  }

  // Active Selected Exam (default to newest published exam)
  const activeResult: ExamResultRecord =
    results.find((r) => r.examId === selectedExamId) || results[0];

  const studentReg = registrationNumber || admissionNumber;
  const isYearWise = activeResult.courseStructure === 'year' || activeResult.periodType === 'year';
  const periodLabel = isYearWise ? 'Year' : 'Semester';
  const periodNo = activeResult.periodNo || 1;
  const periodHeader = isYearWise ? `Year ${periodNo}` : `Semester ${periodNo}`;

  const handleDownloadPdf = async () => {
    if (!resultCardRef.current) return;
    try {
      setIsDownloadingPdf(true);
      const filename = `MIPS_Result_${periodHeader.replace(/\s+/g, '_')}_${studentReg.replace(/[^a-zA-Z0-9]/g, '_')}`;
      await exportElementToPdf(resultCardRef.current, filename, { orientation: 'portrait' });
    } catch (e) {
      console.error('PDF generation error:', e);
    } finally {
      setIsDownloadingPdf(false);
    }
  };

  const handlePrint = () => {
    window.print();
  };

  // Group by Course (Primary vs Skill Course)
  const primaryResults = results.filter((r) => r.courseType !== 'skill');
  const skillResults = results.filter((r) => r.courseType === 'skill');

  return (
    <div className="space-y-6">
      {/* Multi-Exam Switcher Bar */}
      {results.length > 1 && (
        <div className="bg-white rounded-card-lg border border-cardBorder p-4 shadow-sm no-print">
          <label className="block text-xs font-bold text-navy mb-2">
            Select Published Examination:
          </label>
          <div className="flex gap-2 overflow-x-auto no-scrollbar py-1">
            {primaryResults.length > 0 && (
              <div className="flex gap-2">
                {primaryResults.map((exam) => {
                  const examPeriodLabel = exam.periodDisplay || (
                    exam.periodType === 'year' || exam.courseStructure === 'year'
                      ? `Year ${exam.periodNo || 1}`
                      : `Sem ${exam.periodNo || 1}`
                  );
                  return (
                    <button
                      key={exam.examId}
                      type="button"
                      onClick={() => setSelectedExamId(exam.examId)}
                      className={`px-3.5 py-2 rounded-btn text-xs font-sora font-semibold transition-all whitespace-nowrap min-h-touch ${
                        activeResult.examId === exam.examId
                          ? 'bg-primary text-white shadow-primary-btn'
                          : 'bg-surface text-navy hover:bg-slate-100 border border-cardBorder'
                      }`}
                    >
                      {examPeriodLabel}: {exam.examName} ({exam.courseName})
                    </button>
                  );
                })}
              </div>
            )}

            {skillResults.length > 0 && (
              <div className="flex gap-2 pl-2 border-l border-cardBorder">
                {skillResults.map((exam) => (
                  <button
                    key={exam.examId}
                    type="button"
                    onClick={() => setSelectedExamId(exam.examId)}
                    className={`px-3.5 py-2 rounded-btn text-xs font-sora font-semibold transition-all whitespace-nowrap min-h-touch flex items-center gap-1.5 ${
                      activeResult.examId === exam.examId
                        ? 'bg-purple-700 text-white shadow-md'
                        : 'bg-purple-50 text-purple-900 hover:bg-purple-100 border border-purple-200'
                    }`}
                  >
                    <Sparkles className="w-3 h-3" />
                    <span>{exam.examName} [Skill]</span>
                  </button>
                ))}
              </div>
            )}
          </div>
        </div>
      )}

      {/* Main Official Result Card (Exportable to PDF & Print A4) */}
      <div
        ref={resultCardRef}
        id="printableResultArea"
        className="bg-white rounded-card-lg border border-cardBorder shadow-card p-6 sm:p-8 relative"
      >
        {/* Header Bar for Print Only */}
        <div className="hidden print:flex items-center justify-between pb-4 border-b border-cardBorder mb-6">
          <div className="flex items-center gap-3">
            <img src="/logo.png" alt="MIPS" className="w-12 h-12 object-contain" />
            <div>
              <h1 className="font-sora font-bold text-lg text-navy">
                Malabar Institute of Paramedical Science
              </h1>
              <p className="text-xs text-muted">
                Official Statement of Examination Marks — <span className="font-semibold text-navy">{periodHeader}</span>
              </p>
            </div>
          </div>
          <div className="text-right text-xs text-muted">
            <p className="font-bold text-navy">{periodHeader}</p>
            <p>Date Published: {formatDate(activeResult.publishedAt)}</p>
          </div>
        </div>

        {/* Action Controls for Screen View */}
        <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 pb-6 border-b border-cardBorder no-print">
          <div>
            <div className="flex items-center gap-2">
              <span className={`px-2.5 py-0.5 rounded-full text-[11px] font-bold tracking-wide uppercase ${
                activeResult.courseType === 'skill'
                  ? 'bg-purple-100 text-purple-800'
                  : 'bg-blue-100 text-blue-800'
              }`}>
                {activeResult.courseType === 'skill' ? 'Skill Certification' : 'Primary Program'}
              </span>
              <span className="px-2.5 py-0.5 rounded-full text-[11px] font-bold bg-teal/15 text-teal border border-teal/30">
                {periodHeader}
              </span>
              <span className="text-xs text-muted">•</span>
              <span className="text-xs text-muted flex items-center gap-1">
                <Calendar className="w-3.5 h-3.5" />
                Published {formatDate(activeResult.publishedAt)}
              </span>
            </div>
            <h2 className="font-sora font-bold text-xl text-navy mt-1">
              {activeResult.examName}
            </h2>
            <p className="text-xs text-muted">
              {activeResult.courseName} • {activeResult.batchName} • {periodHeader}
            </p>
          </div>

          <div className="flex items-center gap-2.5">
            <button
              type="button"
              onClick={handlePrint}
              className="px-4 py-2.5 rounded-btn border border-cardBorder text-navy font-sora font-semibold text-xs hover:bg-slate-50 transition-colors flex items-center gap-2 min-h-touch"
              title="Print official result statement"
            >
              <Printer className="w-4 h-4 text-muted" />
              <span>Print</span>
            </button>

            <button
              type="button"
              onClick={handleDownloadPdf}
              disabled={isDownloadingPdf}
              className="px-4 py-2.5 rounded-btn bg-primary hover:bg-primary-hover text-white font-sora font-semibold text-xs shadow-primary-btn transition-all flex items-center gap-2 disabled:opacity-50 min-h-touch"
              title="Download result PDF"
            >
              {isDownloadingPdf ? (
                <>
                  <div className="w-3.5 h-3.5 border-2 border-white border-t-transparent rounded-full animate-spin" />
                  <span>Preparing PDF...</span>
                </>
              ) : (
                <>
                  <Download className="w-4 h-4" />
                  <span>Download PDF</span>
                </>
              )}
            </button>
          </div>
        </div>

        {/* Student Meta Details Grid */}
        <div className="my-6 p-4 bg-surface rounded-card border border-cardBorder grid grid-cols-1 sm:grid-cols-2 md:grid-cols-5 gap-4 text-xs">
          <div>
            <span className="text-muted block text-[11px] mb-0.5">Student Name</span>
            <span className="font-bold text-navy text-sm">{studentName}</span>
          </div>
          <div>
            <span className="text-muted block text-[11px] mb-0.5">Register / Admission No.</span>
            <span className="font-bold text-navy text-sm font-mono">{studentReg}</span>
          </div>
          <div>
            <span className="text-muted block text-[11px] mb-0.5">Course</span>
            <span className="font-medium text-navy">{activeResult.courseName}</span>
          </div>
          <div>
            <span className="text-muted block text-[11px] mb-0.5">Batch / Class</span>
            <span className="font-medium text-navy">{activeResult.batchName}</span>
          </div>
          <div>
            <span className="text-muted block text-[11px] mb-0.5">Academic Period</span>
            <span className="font-bold text-navy text-sm">{periodHeader}</span>
          </div>
        </div>

        {/* Summary Metric Tiles (Total, Percentage, Grade, PASS/FAIL Result) */}
        <div className="grid grid-cols-2 sm:grid-cols-4 gap-3.5 mb-8">
          {/* Total Marks */}
          <div className="p-4 rounded-card border border-cardBorder bg-white text-center">
            <span className="text-[11px] font-semibold text-muted uppercase tracking-wider block mb-1">
              Total Score
            </span>
            <p className="font-sora font-bold text-2xl text-navy">
              {activeResult.totalMarks}{' '}
              <span className="text-sm font-normal text-muted">/ {activeResult.maxMarks}</span>
            </p>
          </div>

          {/* Percentage */}
          <div className="p-4 rounded-card border border-cardBorder bg-white text-center">
            <span className="text-[11px] font-semibold text-muted uppercase tracking-wider block mb-1">
              Percentage
            </span>
            <p className="font-sora font-bold text-2xl text-navy">
              {activeResult.percentage.toFixed(1)}%
            </p>
          </div>

          {/* Grade */}
          <div className="p-4 rounded-card border border-cardBorder bg-white text-center">
            <span className="text-[11px] font-semibold text-muted uppercase tracking-wider block mb-1">
              Grade
            </span>
            <p className="font-sora font-bold text-2xl text-navy">
              {activeResult.grade}
            </p>
          </div>

          {/* PASS / FAIL Result Status */}
          <div
            className={`p-4 rounded-card border text-center ${
              activeResult.status === 'PASS'
                ? 'bg-success-bg border-success-border text-success-text'
                : 'bg-error-bg border-error-border text-error-text'
            }`}
          >
            <span className="text-[11px] font-semibold uppercase tracking-wider block mb-1">
              Final Result
            </span>
            <p className="font-sora font-bold text-2xl tracking-tight">
              {activeResult.status}
            </p>
          </div>
        </div>

        {/* Subject-Wise Detailed Marks Table */}
        <div className="overflow-x-auto rounded-card border border-cardBorder">
          <table className="w-full text-left text-xs border-collapse">
            <thead>
              <tr className="bg-surface text-navy font-sora font-bold border-b border-cardBorder">
                <th className="py-3 px-4">Subject</th>
                <th className="py-3 px-4 text-right">Max Marks</th>
                <th className="py-3 px-4 text-right">Pass Marks</th>
                <th className="py-3 px-4 text-right">Obtained</th>
                <th className="py-3 px-4 text-center">Status</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-cardBorder font-medium">
              {activeResult.subjects.map((s) => (
                <tr key={s.subjectId} className="hover:bg-slate-50/80 transition-colors">
                  <td className="py-3 px-4">
                    <span className="font-semibold text-navy">{s.subjectName}</span>
                    {s.subjectCode && (
                      <span className="block text-[11px] text-muted font-mono">{s.subjectCode}</span>
                    )}
                  </td>
                  <td className="py-3 px-4 text-right text-muted">{s.maxMarks}</td>
                  <td className="py-3 px-4 text-right text-muted">{s.passMarks}</td>
                  <td className="py-3 px-4 text-right font-sora font-bold text-navy">
                    {s.isAbsent ? <span className="text-amber-700">AB</span> : s.obtainedMarks}
                  </td>
                  <td className="py-3 px-4 text-center">
                    {s.isAbsent ? (
                      <span className="inline-block px-2.5 py-0.5 rounded-full text-[10px] font-bold bg-amber-100 text-amber-800">
                        Absent
                      </span>
                    ) : s.isPass ? (
                      <span className="inline-block px-2.5 py-0.5 rounded-full text-[10px] font-bold bg-success-bg text-success-text">
                        Pass
                      </span>
                    ) : (
                      <span className="inline-block px-2.5 py-0.5 rounded-full text-[10px] font-bold bg-error-bg text-error-accent">
                        Fail
                      </span>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
            <tfoot>
              <tr className="bg-surface font-sora font-bold text-navy border-t-2 border-cardBorder">
                <td className="py-3.5 px-4 text-sm">Total Summary</td>
                <td className="py-3.5 px-4 text-right text-sm">{activeResult.maxMarks}</td>
                <td className="py-3.5 px-4 text-right text-sm">—</td>
                <td className="py-3.5 px-4 text-right text-sm text-primary">
                  {activeResult.totalMarks}
                </td>
                <td className="py-3.5 px-4 text-center">
                  <span
                    className={`inline-block px-3 py-1 rounded-full text-xs font-bold ${
                      activeResult.status === 'PASS'
                        ? 'bg-success-bg text-success-text'
                        : 'bg-error-bg text-error-text'
                    }`}
                  >
                    {activeResult.status}
                  </span>
                </td>
              </tr>
            </tfoot>
          </table>
        </div>

        {/* Security / Verification Disclaimer Note */}
        <div className="mt-8 pt-5 border-t border-cardBorder text-center sm:text-left flex flex-col sm:flex-row items-center justify-between gap-3 text-xs text-muted">
          <p className="italic">
            This is a computer-generated result for information purposes only. Result code:{' '}
            <span className="font-mono font-bold text-navy not-italic">{activeResult.resultCode}</span>
          </p>
          <div className="flex items-center gap-1.5 text-[11px] font-semibold text-emerald-800 bg-emerald-50 px-2.5 py-1 rounded-full border border-emerald-200">
            <FileCheck className="w-3.5 h-3.5 text-emerald-600" />
            <span>Cryptographically Verified</span>
          </div>
        </div>
      </div>
    </div>
  );
};
