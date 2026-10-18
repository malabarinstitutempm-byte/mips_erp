// src/components/teacher/TeacherProfileTab.tsx
// Faculty Profile Screen with Assigned Batches/Subjects, Password Management & Sign Out

import React, { useState } from 'react';
import { useAuth } from '../../context/AuthContext';
import { TeacherProfile } from '../../services/teacherService';
import { evaluatePasswordPolicy } from '../../lib/passwordPolicy';
import {
  User,
  KeyRound,
  LogOut,
  Mail,
  Phone,
  GraduationCap,
  BookOpen,
  CheckCircle2,
  AlertCircle,
  Eye,
  EyeOff,
  ShieldCheck,
  Building,
  Hash,
  X,
  Bell,
} from 'lucide-react';
import { pushNotificationService } from '../../lib/pushNotifications';

interface TeacherProfileTabProps {
  profile: TeacherProfile;
}

export const TeacherProfileTab: React.FC<TeacherProfileTabProps> = ({ profile }) => {
  const { user, logout, setPassword, setIsPushModalOpen } = useAuth();
  const [isPasswordModalOpen, setIsPasswordModalOpen] = useState(false);
  const [pushStatus, setPushStatus] = useState<{ isSupported: boolean; isSubscribed: boolean } | null>(null);

  React.useEffect(() => {
    pushNotificationService.getStatus().then((st) => {
      setPushStatus({ isSupported: st.isSupported, isSubscribed: st.isSubscribed });
    });
  }, []);

  // Password Change State
  const [newPassword, setNewPassword] = useState('');
  const [confirmPassword, setConfirmPassword] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [feedback, setFeedback] = useState<{ type: 'success' | 'error'; message: string } | null>(
    null
  );

  const policyCheck = evaluatePasswordPolicy(newPassword, {
    username: user?.username || profile.loginUsername,
  });

  const passwordsMatch = newPassword.length > 0 && newPassword === confirmPassword;
  const isSubmitDisabled = !policyCheck.isValid || !passwordsMatch || isSubmitting;

  const handlePasswordSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (isSubmitDisabled) return;

    setIsSubmitting(true);
    setFeedback(null);

    try {
      const res = await setPassword(newPassword);
      if (res.success) {
        setFeedback({
          type: 'success',
          message: 'Faculty password updated successfully. Use your new password on next login.',
        });
        setNewPassword('');
        setConfirmPassword('');
      } else {
        setFeedback({
          type: 'error',
          message: res.error || 'Failed to update password. Please check requirements.',
        });
      }
    } catch (err: any) {
      setFeedback({
        type: 'error',
        message: err.message || 'An unexpected error occurred while updating password.',
      });
    } finally {
      setIsSubmitting(false);
    }
  };

  return (
    <div className="space-y-6">
      {/* Faculty Profile Overview Card */}
      <div className="bg-white rounded-card-lg border border-cardBorder shadow-card p-6 sm:p-8">
        <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-6 pb-6 border-b border-cardBorder">
          <div className="flex items-center gap-4">
            <div className="w-16 h-16 rounded-2xl bg-navy text-white flex items-center justify-center font-sora font-extrabold text-2xl shadow-sm">
              {profile.name ? profile.name.charAt(0).toUpperCase() : 'T'}
            </div>
            <div>
              <div className="flex items-center gap-2">
                <h2 className="font-sora font-bold text-xl text-navy">{profile.name}</h2>
                <span
                  className={`px-2.5 py-0.5 text-[11px] font-bold rounded-full uppercase tracking-wider ${
                    profile.status === 'active'
                      ? 'bg-success-bg text-success-text'
                      : 'bg-warning-bg text-warning-text'
                  }`}
                >
                  {profile.status}
                </span>
              </div>
              <p className="text-xs text-muted mt-1">
                Faculty ID: #{profile.id} • Teaching Staff
              </p>
            </div>
          </div>

          {/* Quick Actions */}
          <div className="flex flex-wrap items-center gap-2">
            <button
              type="button"
              onClick={() => {
                setFeedback(null);
                setNewPassword('');
                setConfirmPassword('');
                setIsPasswordModalOpen(true);
              }}
              className="inline-flex items-center gap-2 px-4 py-2.5 rounded-button text-xs font-semibold text-primary bg-primary/10 hover:bg-primary/20 transition-colors min-h-touch focus:outline-none focus:ring-2 focus:ring-focusRing"
            >
              <KeyRound className="w-4 h-4" />
              <span>Change Password</span>
            </button>

            {pushStatus?.isSupported && (
              <button
                type="button"
                onClick={() => setIsPushModalOpen(true)}
                className={`inline-flex items-center gap-2 px-4 py-2.5 rounded-button text-xs font-semibold transition-colors min-h-touch focus:outline-none focus:ring-2 focus:ring-focusRing ${
                  pushStatus.isSubscribed
                    ? 'text-emerald-700 bg-emerald-50 hover:bg-emerald-100 border border-emerald-200'
                    : 'text-teal bg-teal/10 hover:bg-teal/20'
                }`}
              >
                <Bell className="w-4 h-4" />
                <span>{pushStatus.isSubscribed ? 'Push Alerts Active' : 'Enable Push Alerts'}</span>
              </button>
            )}

            <button
              type="button"
              onClick={logout}
              className="inline-flex items-center gap-2 px-4 py-2.5 rounded-button text-xs font-semibold text-error-text bg-error-bg hover:bg-error-bg/80 border border-error-border transition-colors min-h-touch focus:outline-none focus:ring-2 focus:ring-focusRing"
            >
              <LogOut className="w-4 h-4" />
              <span>Sign Out</span>
            </button>
          </div>
        </div>

        {/* Detailed Credentials Grid */}
        <div className="grid grid-cols-1 md:grid-cols-2 gap-6 pt-6">
          {/* Institutional Identifiers */}
          <div className="space-y-4">
            <h3 className="font-sora font-bold text-sm text-navy uppercase tracking-wider">
              Faculty Credentials
            </h3>

            <div className="bg-surface rounded-2xl p-4 border border-cardBorder space-y-3 text-xs">
              <div className="flex items-center justify-between py-1 border-b border-cardBorder/60">
                <span className="text-muted flex items-center gap-1.5">
                  <Hash className="w-3.5 h-3.5 text-primary" />
                  Employee Login Code
                </span>
                <span className="font-sora font-bold text-navy">{profile.loginUsername}</span>
              </div>

              <div className="flex items-center justify-between py-1 border-b border-cardBorder/60">
                <span className="text-muted flex items-center gap-1.5">
                  <ShieldCheck className="w-3.5 h-3.5 text-teal" />
                  Account Role
                </span>
                <span className="font-medium text-navy">Faculty / Teacher</span>
              </div>

              <div className="flex items-center justify-between py-1">
                <span className="text-muted flex items-center gap-1.5">
                  <Building className="w-3.5 h-3.5 text-primary" />
                  Institution
                </span>
                <span className="font-medium text-navy">MIPS Campus</span>
              </div>
            </div>
          </div>

          {/* Contact Details */}
          <div className="space-y-4">
            <h3 className="font-sora font-bold text-sm text-navy uppercase tracking-wider">
              Contact Details
            </h3>

            <div className="bg-surface rounded-2xl p-4 border border-cardBorder space-y-3 text-xs">
              <div className="flex items-center justify-between py-1 border-b border-cardBorder/60">
                <span className="text-muted flex items-center gap-1.5">
                  <Phone className="w-3.5 h-3.5 text-primary" />
                  Official Phone
                </span>
                <span className="font-sora font-semibold text-navy">
                  {profile.phone || 'Not recorded'}
                </span>
              </div>

              <div className="flex items-center justify-between py-1">
                <span className="text-muted flex items-center gap-1.5">
                  <Mail className="w-3.5 h-3.5 text-primary" />
                  Portal Email
                </span>
                <span className="font-medium text-navy">{user?.email || 'Not recorded'}</span>
              </div>
            </div>

            <p className="text-[11px] text-muted leading-relaxed">
              * To modify personal contact details or official designations, please contact the campus administrative office.
            </p>
          </div>
        </div>

        {/* Teaching Allocations: Universal Primary Course Access */}
        <div className="mt-8 pt-6 border-t border-cardBorder">
          <h3 className="font-sora font-bold text-sm text-navy uppercase tracking-wider mb-2">
            Academic Scope & Permissions
          </h3>
          <p className="text-xs text-muted mb-4">
            Per institutional policy, faculty members are not restricted to assigned batches. Every active teacher has open access to mark attendance for any primary course batch across the campus.
          </p>

          <div className="p-4 rounded-2xl bg-surface border border-cardBorder flex items-start gap-3">
            <div className="p-2.5 rounded-xl bg-teal/15 text-teal shrink-0 mt-0.5">
              <GraduationCap className="w-5 h-5" />
            </div>
            <div>
              <h4 className="font-sora font-bold text-xs text-navy">
                Open Primary Course Attendance
              </h4>
              <p className="text-xs text-muted mt-1 leading-relaxed">
                You can mark attendance for Morning and Evening slots of any active primary course batch. When any faculty member marks a slot, it becomes read-only for all other teachers to prevent duplicate submissions.
              </p>
            </div>
          </div>
        </div>
      </div>

      {/* Change Password Dialog Modal */}
      {isPasswordModalOpen && (
        <div
          role="dialog"
          aria-modal="true"
          className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-navy/60 backdrop-blur-sm animate-fade-in"
        >
          <div className="w-full max-w-md bg-white rounded-card-lg border border-cardBorder shadow-2xl p-6 sm:p-7 relative">
            {/* Modal Header */}
            <div className="flex items-center justify-between pb-4 border-b border-cardBorder">
              <div className="flex items-center gap-2.5">
                <div className="p-2 rounded-xl bg-primary/10 text-primary">
                  <KeyRound className="w-5 h-5" />
                </div>
                <div>
                  <h3 className="font-sora font-bold text-base text-navy">Change Faculty Password</h3>
                  <p className="text-xs text-muted">Update your portal access credentials</p>
                </div>
              </div>

              <button
                type="button"
                onClick={() => setIsPasswordModalOpen(false)}
                className="p-1.5 rounded-lg text-slate-400 hover:text-slate-600 hover:bg-slate-100 transition-colors"
                aria-label="Close dialog"
              >
                <X className="w-5 h-5" />
              </button>
            </div>

            {/* Notification / Feedback Banner */}
            {feedback && (
              <div
                className={`mt-4 p-3.5 rounded-xl border flex items-start gap-2.5 text-xs ${
                  feedback.type === 'success'
                    ? 'bg-success-bg border-success-text/20 text-success-text'
                    : 'bg-error-bg border-error-border text-error-text'
                }`}
                role="alert"
                aria-live="polite"
              >
                {feedback.type === 'success' ? (
                  <CheckCircle2 className="w-4 h-4 flex-shrink-0 mt-0.5" />
                ) : (
                  <AlertCircle className="w-4 h-4 flex-shrink-0 mt-0.5" />
                )}
                <span>{feedback.message}</span>
              </div>
            )}

            {/* Form */}
            <form onSubmit={handlePasswordSubmit} className="mt-4 space-y-4">
              <div>
                <label className="block text-xs font-semibold text-navy mb-1.5">
                  New Password
                </label>
                <div className="relative">
                  <input
                    type={showPassword ? 'text' : 'password'}
                    value={newPassword}
                    onChange={(e) => setNewPassword(e.target.value)}
                    placeholder="Enter 8+ character password"
                    required
                    className="w-full px-3.5 py-2.5 pr-10 text-sm rounded-input border border-inputBorder focus:outline-none focus:ring-2 focus:ring-focusRing focus:border-primary text-navy"
                  />
                  <button
                    type="button"
                    onClick={() => setShowPassword(!showPassword)}
                    className="absolute right-2.5 top-1/2 -translate-y-1/2 text-slate-400 hover:text-slate-600 p-1"
                    aria-label={showPassword ? 'Hide password' : 'Show password'}
                  >
                    {showPassword ? <EyeOff className="w-4 h-4" /> : <Eye className="w-4 h-4" />}
                  </button>
                </div>
              </div>

              <div>
                <label className="block text-xs font-semibold text-navy mb-1.5">
                  Confirm New Password
                </label>
                <input
                  type={showPassword ? 'text' : 'password'}
                  value={confirmPassword}
                  onChange={(e) => setConfirmPassword(e.target.value)}
                  placeholder="Re-enter your new password"
                  required
                  className="w-full px-3.5 py-2.5 text-sm rounded-input border border-inputBorder focus:outline-none focus:ring-2 focus:ring-focusRing focus:border-primary text-navy"
                />
                {confirmPassword && !passwordsMatch && (
                  <p className="text-[11px] text-error-text mt-1">Passwords do not match.</p>
                )}
              </div>

              {/* Inline Password Rules */}
              <div className="p-3.5 bg-surface rounded-xl border border-cardBorder space-y-1.5 text-[11px]">
                <p className="font-semibold text-navy mb-1">Password Requirements:</p>
                <div className="flex items-center gap-1.5">
                  <span
                    className={`w-1.5 h-1.5 rounded-full ${
                      policyCheck.rules.length ? 'bg-success-text' : 'bg-slate-300'
                    }`}
                  />
                  <span className={policyCheck.rules.length ? 'text-navy' : 'text-muted'}>
                    At least 8 characters long
                  </span>
                </div>
                <div className="flex items-center gap-1.5">
                  <span
                    className={`w-1.5 h-1.5 rounded-full ${
                      policyCheck.rules.notUsername ? 'bg-success-text' : 'bg-slate-300'
                    }`}
                  />
                  <span className={policyCheck.rules.notUsername ? 'text-navy' : 'text-muted'}>
                    Must not contain your login code or username
                  </span>
                </div>
              </div>

              {/* Actions */}
              <div className="flex items-center justify-end gap-2 pt-3 border-t border-cardBorder">
                <button
                  type="button"
                  onClick={() => setIsPasswordModalOpen(false)}
                  className="px-4 py-2.5 rounded-button text-xs font-semibold text-muted hover:text-navy hover:bg-surface transition-colors min-h-touch"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  disabled={isSubmitDisabled}
                  className="px-5 py-2.5 rounded-button text-xs font-semibold text-white bg-primary hover:bg-primary-hover disabled:opacity-50 transition-colors shadow-sm min-h-touch flex items-center gap-2"
                >
                  {isSubmitting ? (
                    <>
                      <div className="w-3.5 h-3.5 border-2 border-white border-t-transparent rounded-full animate-spin" />
                      <span>Updating...</span>
                    </>
                  ) : (
                    <span>Save Password</span>
                  )}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
};
