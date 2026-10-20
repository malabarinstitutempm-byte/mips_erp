// src/components/student/FeesTab.tsx
// Fees status, installment ledger, and official payment receipt downloader

import React, { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { studentService, StudentFeeLedger } from '../../services/studentService';
import { formatCurrency, formatDate, formatDateTime } from '../../lib/formatters';
import { exportElementToPdf } from '../../lib/pdfExporter';
import { LoadingSkeleton } from '../common/LoadingSkeleton';
import { EmptyState } from '../common/EmptyState';
import { ErrorRetry } from '../common/ErrorRetry';
import {
  IndianRupee,
  Calendar,
  Download,
  AlertTriangle,
  CheckCircle2,
  Clock,
  Building2,
  Receipt,
  FileCheck,
} from 'lucide-react';

interface FeesTabProps {
  studentId: number;
  studentName: string;
  registrationNumber: string | null;
  admissionNumber: string;
  courseName?: string;
  batchName?: string;
}

export const FeesTab: React.FC<FeesTabProps> = ({
  studentId,
  studentName,
  registrationNumber,
  admissionNumber,
  courseName = 'Primary Program',
  batchName = 'Batch',
}) => {
  const [downloadingReceiptId, setDownloadingReceiptId] = useState<number | null>(null);

  const {
    data: feeData,
    isLoading,
    error,
    refetch,
    isFetching,
  } = useQuery<StudentFeeLedger>({
    queryKey: ['studentFees', studentId],
    queryFn: () => studentService.getStudentFees(studentId),
  });

  if (isLoading) {
    return <LoadingSkeleton type="card" rows={4} />;
  }

  if (error || !feeData) {
    return (
      <ErrorRetry
        message="Unable to load fee ledger details. Please try again."
        onRetry={() => refetch()}
        isRetrying={isFetching}
      />
    );
  }

  const { summary, items, payments, lastUpdated } = feeData;
  const studentReg = registrationNumber || admissionNumber;

  const handleDownloadReceipt = async (p: typeof payments[0]) => {
    try {
      setDownloadingReceiptId(p.id);

      // Construct a clean, isolated DOM element for the receipt PDF
      const receiptContainer = document.createElement('div');
      receiptContainer.style.padding = '24px';
      receiptContainer.style.fontFamily = '"Plus Jakarta Sans", sans-serif';
      receiptContainer.style.color = '#0B2A4A';
      receiptContainer.style.background = '#ffffff';

      receiptContainer.innerHTML = `
        <div style="border: 2px solid #0B2A4A; border-radius: 12px; padding: 24px;">
          <div style="display: flex; justify-content: space-between; align-items: center; border-bottom: 2px solid #E1E8F2; padding-bottom: 16px;">
            <div>
              <h1 style="font-family: Sora, sans-serif; font-size: 20px; font-weight: bold; margin: 0; color: #0B2A4A;">
                Malabar Institute of Paramedical Science
              </h1>
              <p style="font-size: 11px; color: #5B6B7F; margin: 4px 0 0 0;">
                Official Fee Payment Receipt • Computer Generated
              </p>
            </div>
            <div style="text-align: right;">
              <span style="font-family: monospace; font-weight: bold; font-size: 14px; color: #1F5FBF;">
                ${p.receiptNumber}
              </span>
              <p style="font-size: 11px; color: #5B6B7F; margin: 2px 0 0 0;">
                Date: ${formatDate(p.date)}
              </p>
            </div>
          </div>

          <div style="margin-top: 18px; display: grid; grid-template-columns: 1fr 1fr; gap: 12px; font-size: 12px; background: #F3F6FB; padding: 14px; border-radius: 8px;">
            <div><strong>Student Name:</strong> ${studentName}</div>
            <div><strong>Reg / Adm No:</strong> ${studentReg}</div>
            <div><strong>Program:</strong> ${courseName}</div>
            <div><strong>Payment Mode:</strong> ${p.paymentMode}</div>
            ${p.referenceNumber ? `<div><strong>Ref Number:</strong> ${p.referenceNumber}</div>` : ''}
          </div>

          <div style="margin-top: 24px;">
            <table style="width: 100%; border-collapse: collapse; font-size: 12px;">
              <thead>
                <tr style="background: #0B2A4A; color: white;">
                  <th style="padding: 10px; text-align: left;">Description</th>
                  <th style="padding: 10px; text-align: right;">Amount (₹)</th>
                </tr>
              </thead>
              <tbody>
                <tr style="border-bottom: 1px solid #E1E8F2;">
                  <td style="padding: 12px 10px;">Tuition / Academic Institutional Fee Installment</td>
                  <td style="padding: 12px 10px; text-align: right; font-weight: bold; font-size: 14px;">
                    ${formatCurrency(p.amountPaise)}
                  </td>
                </tr>
              </tbody>
              <tfoot>
                <tr style="background: #F3F6FB; font-weight: bold; font-size: 13px;">
                  <td style="padding: 12px 10px;">Total Paid Amount</td>
                  <td style="padding: 12px 10px; text-align: right; color: #0B5D3B;">
                    ${formatCurrency(p.amountPaise)}
                  </td>
                </tr>
              </tfoot>
            </table>
          </div>

          <div style="margin-top: 36px; display: flex; justify-content: space-between; align-items: flex-end; font-size: 11px; color: #5B6B7F;">
            <div>
              <p style="margin: 0;">Verified through Supabase Institutional ERP Master.</p>
              <p style="margin: 2px 0 0 0;">This document is valid without physical seal.</p>
            </div>
            <div style="text-align: center;">
              <div style="border-bottom: 1px solid #0B2A4A; width: 140px; margin-bottom: 4px;"></div>
              <span>Authorized Signatory</span>
            </div>
          </div>
        </div>
      `;

      document.body.appendChild(receiptContainer);
      const filename = `MIPS_Receipt_${p.receiptNumber.replace(/[^a-zA-Z0-9]/g, '_')}`;
      await exportElementToPdf(receiptContainer, filename, { orientation: 'portrait' });
      document.body.removeChild(receiptContainer);
    } catch (e) {
      console.error('Receipt download error:', e);
    } finally {
      setDownloadingReceiptId(null);
    }
  };

  return (
    <div className="space-y-6">
      {/* 1. Big "Balance to pay" Hero Card */}
      <div className="bg-white rounded-card-lg border border-cardBorder shadow-card p-6 sm:p-8">
        <div className="flex flex-col md:flex-row md:items-center justify-between gap-6 pb-6 border-b border-cardBorder">
          <div>
            <span className="text-xs font-bold uppercase tracking-wider text-muted block mb-1">
              Outstanding Amount
            </span>
            <div className="flex items-baseline gap-2">
              <span className={`font-sora font-bold text-3xl sm:text-4xl ${
                summary.pendingAmountPaise > 0 ? 'text-primary' : 'text-success-text'
              }`}>
                {formatCurrency(summary.pendingAmountPaise)}
              </span>
              <span className="text-xs text-muted">Balance to Pay</span>
            </div>
          </div>

          <div className="flex items-center gap-3">
            <div className="text-right">
              <span className="text-[11px] text-muted block">Fee Clearance Status</span>
              <span
                className={`inline-flex items-center gap-1.5 px-3 py-1 rounded-full text-xs font-bold ${
                  summary.pendingAmountPaise === 0
                    ? 'bg-success-bg text-success-text border border-success-border'
                    : 'bg-amber-50 text-amber-800 border border-amber-200'
                }`}
              >
                {summary.pendingAmountPaise === 0 ? (
                  <>
                    <CheckCircle2 className="w-3.5 h-3.5" />
                    <span>Cleared in Full</span>
                  </>
                ) : (
                  <>
                    <Clock className="w-3.5 h-3.5" />
                    <span>Payment Due</span>
                  </>
                )}
              </span>
            </div>
          </div>
        </div>

        {/* Financial Metrics Summary (Total, Paid, Balance) */}
        <div className="grid grid-cols-1 sm:grid-cols-3 gap-4 pt-6">
          <div className="p-4 rounded-card bg-surface border border-cardBorder">
            <span className="text-[11px] text-muted font-medium block mb-1">Total Fee</span>
            <p className="font-sora font-bold text-xl text-navy">
              {formatCurrency(summary.totalFeePaise)}
            </p>
          </div>

          <div className="p-4 rounded-card bg-success-bg/40 border border-success-border">
            <span className="text-[11px] text-success-text font-medium block mb-1">Total Paid</span>
            <p className="font-sora font-bold text-xl text-success-text">
              {formatCurrency(summary.paidAmountPaise)}
            </p>
          </div>

          <div className="p-4 rounded-card bg-surface border border-cardBorder">
            <span className="text-[11px] text-muted font-medium block mb-1">Total Outstanding</span>
            <p className="font-sora font-bold text-xl text-primary">
              {formatCurrency(summary.pendingAmountPaise)}
            </p>
          </div>
        </div>

        {/* Per-Course Breakdown (Primary Program vs Skill Course) */}
        {summary.skillFeePaise > 0 && (
          <div className="mt-6 pt-5 border-t border-cardBorder">
            <h4 className="font-sora font-bold text-xs uppercase tracking-wider text-muted mb-3">
              Per-Course Fee Breakdown
            </h4>
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-3.5">
              {/* Primary Program */}
              <div className="p-3.5 rounded-card border border-cardBorder bg-white flex items-center justify-between">
                <div>
                  <span className="font-sora font-bold text-xs text-navy block">Primary Course</span>
                  <span className="text-[11px] text-muted">
                    Paid {formatCurrency(summary.primaryPaidPaise)} of {formatCurrency(summary.primaryFeePaise)}
                  </span>
                </div>
                <div className="text-right">
                  <span className="text-xs font-sora font-bold text-navy block">
                    {formatCurrency(summary.primaryPendingPaise)}
                  </span>
                  <span className="text-[10px] text-muted">Pending</span>
                </div>
              </div>

              {/* Skill Certification Course */}
              <div className="p-3.5 rounded-card border border-purple-200 bg-purple-50/40 flex items-center justify-between">
                <div>
                  <span className="font-sora font-bold text-xs text-purple-900 block">
                    Optional Skill Course
                  </span>
                  <span className="text-[11px] text-purple-700">
                    Paid {formatCurrency(summary.skillPaidPaise)} of {formatCurrency(summary.skillFeePaise)}
                  </span>
                </div>
                <div className="text-right">
                  <span className="text-xs font-sora font-bold text-purple-900 block">
                    {formatCurrency(summary.skillPendingPaise)}
                  </span>
                  <span className="text-[10px] text-purple-600">Pending</span>
                </div>
              </div>
            </div>
          </div>
        )}

        {/* Institutional Payment Guidance Note */}
        <div className="mt-6 p-3.5 bg-amber-50/70 border border-amber-200 rounded-input flex items-start gap-3 text-xs text-amber-900">
          <Building2 className="w-4 h-4 text-amber-700 shrink-0 mt-0.5" />
          <div className="leading-relaxed">
            <p className="font-semibold">Fee Payment Instructions</p>
            <p className="text-[11px] mt-0.5 text-amber-800">
              Online payments are currently disabled. To pay your outstanding fees or installments, please visit the college office during administrative hours (09:00 AM – 04:00 PM).
            </p>
          </div>
        </div>
      </div>

      {/* 2. Fee Items / Installments Ledger */}
      <div className="bg-white rounded-card-lg border border-cardBorder shadow-card p-6 sm:p-8">
        <div className="flex items-center justify-between pb-4 border-b border-cardBorder mb-4">
          <h3 className="font-sora font-bold text-base text-navy">
            Scheduled Installments
          </h3>
          <span className="text-[11px] text-muted">
            Last updated: {formatDateTime(lastUpdated)}
          </span>
        </div>

        {items.length === 0 ? (
          <p className="text-xs text-muted py-4 text-center">No fee installments scheduled.</p>
        ) : (
          <>
            {/* Desktop / Tablet View: Full Table */}
            <div className="hidden md:block overflow-x-auto rounded-card border border-cardBorder">
              <table className="w-full text-left text-xs border-collapse">
                <thead>
                  <tr className="bg-surface text-navy font-sora font-bold border-b border-cardBorder">
                    <th className="py-3 px-4">Installment</th>
                    <th className="py-3 px-4">Due Date</th>
                    <th className="py-3 px-4 text-right">Total Amount</th>
                    <th className="py-3 px-4 text-right">Paid</th>
                    <th className="py-3 px-4 text-right">Balance</th>
                    <th className="py-3 px-4 text-center">Status</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-cardBorder font-medium">
                  {items.map((item) => (
                    <tr key={item.id} className="hover:bg-slate-50/80 transition-colors">
                      <td className="py-3 px-4">
                        <span className="font-semibold text-navy">{item.title}</span>
                        {item.courseName && (
                          <span className="block text-[11px] text-muted">{item.courseName}</span>
                        )}
                      </td>
                      <td className="py-3 px-4 text-muted whitespace-nowrap">
                        {formatDate(item.dueDate)}
                      </td>
                      <td className="py-3 px-4 text-right text-navy">
                        {formatCurrency(item.amountPaise)}
                      </td>
                      <td className="py-3 px-4 text-right text-success-text">
                        {formatCurrency(item.paidAmountPaise)}
                      </td>
                      <td className="py-3 px-4 text-right font-sora font-bold text-navy">
                        {formatCurrency(item.pendingAmountPaise)}
                      </td>
                      <td className="py-3 px-4 text-center">
                        <span
                          className={`inline-block px-2.5 py-0.5 rounded-full text-[10px] font-bold ${
                            item.status === 'Paid'
                              ? 'bg-success-bg text-success-text'
                              : item.status === 'Overdue'
                              ? 'bg-error-bg text-error-accent'
                              : 'bg-amber-100 text-amber-800'
                          }`}
                        >
                          {item.status}
                        </span>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>

            {/* Mobile View: Installment Cards */}
            <div className="md:hidden space-y-3">
              {items.map((item) => (
                <div
                  key={item.id}
                  className="p-4 bg-white rounded-card border border-cardBorder shadow-sm space-y-3"
                >
                  <div className="flex items-start justify-between gap-2">
                    <div className="min-w-0 flex-1">
                      <h4 className="font-semibold text-navy text-sm break-words">{item.title}</h4>
                      {item.courseName && (
                        <span className="text-[11px] text-muted block mt-0.5">{item.courseName}</span>
                      )}
                    </div>
                    <span
                      className={`inline-block px-2.5 py-0.5 rounded-full text-[10px] font-bold shrink-0 ${
                        item.status === 'Paid'
                          ? 'bg-success-bg text-success-text'
                          : item.status === 'Overdue'
                          ? 'bg-error-bg text-error-accent'
                          : 'bg-amber-100 text-amber-800'
                      }`}
                    >
                      {item.status}
                    </span>
                  </div>

                  <div className="flex items-center gap-1.5 text-xs text-muted">
                    <Calendar className="w-3.5 h-3.5 text-slate-400" />
                    <span>Due Date: <strong className="text-navy">{formatDate(item.dueDate)}</strong></span>
                  </div>

                  <div className="grid grid-cols-3 gap-2 pt-2 border-t border-slate-100 text-center">
                    <div className="p-2 rounded-lg bg-surface">
                      <span className="block text-[10px] font-medium text-muted uppercase">Total</span>
                      <span className="font-sora font-semibold text-xs text-navy">
                        {formatCurrency(item.amountPaise)}
                      </span>
                    </div>
                    <div className="p-2 rounded-lg bg-success-bg/30">
                      <span className="block text-[10px] font-medium text-success-text uppercase">Paid</span>
                      <span className="font-sora font-semibold text-xs text-success-text">
                        {formatCurrency(item.paidAmountPaise)}
                      </span>
                    </div>
                    <div className="p-2 rounded-lg bg-surface border border-slate-200">
                      <span className="block text-[10px] font-medium text-muted uppercase">Balance</span>
                      <span className="font-sora font-bold text-xs text-navy">
                        {formatCurrency(item.pendingAmountPaise)}
                      </span>
                    </div>
                  </div>
                </div>
              ))}
            </div>
          </>
        )}
      </div>

      {/* 3. Official Payment History & Receipt Download */}
      <div className="bg-white rounded-card-lg border border-cardBorder shadow-card p-6 sm:p-8">
        <h3 className="font-sora font-bold text-base text-navy mb-4">
          Payment History & Receipts
        </h3>

        {payments.length === 0 ? (
          <div className="py-8 text-center text-xs text-muted">
            <Receipt className="w-8 h-8 text-slate-300 mx-auto mb-2" />
            <p>No payment records found on file.</p>
          </div>
        ) : (
          <div className="space-y-3">
            {payments.map((p) => (
              <div
                key={p.id}
                className="p-4 rounded-card border border-cardBorder bg-white flex flex-col sm:flex-row sm:items-center justify-between gap-3 hover:border-slate-300 transition-all"
              >
                <div>
                  <div className="flex flex-wrap items-center gap-2">
                    <span className="font-mono font-bold text-xs text-navy break-all">
                      {p.receiptNumber}
                    </span>
                    <span className="text-xs text-muted">•</span>
                    <span className="text-xs text-muted">{formatDate(p.date)}</span>
                  </div>
                  <p className="text-xs text-muted mt-1">
                    Mode: <span className="font-semibold text-navy">{p.paymentMode}</span>
                    {p.referenceNumber && (
                      <span className="font-mono text-[11px] ml-2 text-slate-500 break-all">
                        (Ref: {p.referenceNumber})
                      </span>
                    )}
                  </p>
                </div>

                <div className="flex items-center justify-between sm:justify-end gap-4 pt-2 sm:pt-0 border-t sm:border-0 border-slate-100">
                  <span className="font-sora font-bold text-base text-success-text">
                    {formatCurrency(p.amountPaise)}
                  </span>

                  <button
                    type="button"
                    onClick={() => handleDownloadReceipt(p)}
                    disabled={downloadingReceiptId === p.id}
                    className="px-3.5 py-2 rounded-btn bg-surface hover:bg-slate-100 border border-cardBorder text-navy font-sora font-semibold text-xs flex items-center justify-center gap-1.5 transition-colors disabled:opacity-50 min-h-touch"
                    title="Download receipt PDF"
                  >
                    {downloadingReceiptId === p.id ? (
                      <>
                        <div className="w-3 h-3 border-2 border-primary border-t-transparent rounded-full animate-spin" />
                        <span>Preparing...</span>
                      </>
                    ) : (
                      <>
                        <Download className="w-3.5 h-3.5 text-primary" />
                        <span>Receipt PDF</span>
                      </>
                    )}
                  </button>
                </div>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
};
