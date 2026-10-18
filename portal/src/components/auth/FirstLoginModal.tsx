// src/components/auth/FirstLoginModal.tsx
// First-time student and teacher portal activation dialog

import React, { useState } from 'react';
import { useAuth } from '../../context/AuthContext';
import { formatDobInput } from '../../lib/formatters';
import { evaluatePasswordPolicy } from '../../lib/passwordPolicy';
import {
  Sparkles,
  X,
  AlertCircle,
  Lock,
  Calendar,
  IdCard,
  Eye,
  EyeOff,
  Check,
  CheckCircle2,
  Phone,
  User,
  GraduationCap,
  Briefcase,
} from 'lucide-react';

interface FirstLoginModalProps {
  isOpen: boolean;
  onClose: () => void;
  onSuccess: () => void;
}

export const FirstLoginModal: React.FC<FirstLoginModalProps> = ({ isOpen, onClose, onSuccess }) => {
  const { studentFirstLogin, teacherFirstLogin } = useAuth();
  const [accountType, setAccountType] = useState<'student' | 'teacher'>('student');

  // Student form state
  const [regNo, setRegNo] = useState('');
  const [dob, setDob] = useState('');

  // Teacher form state
  const [username, setUsername] = useState('');
  const [phone, setPhone] = useState('');

  // Password state
  const [password, setPassword] = useState('');
  const [confirmPassword, setConfirmPassword] = useState('');
  const [showPass, setShowPass] = useState(false);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');

  if (!isOpen) return null;

  const policy = evaluatePasswordPolicy(
    password,
    accountType === 'student'
      ? { registrationNumber: regNo, dob }
      : { username }
  );

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError('');

    if (!policy.isValid) {
      setError(policy.errors[0] || 'Password does not meet institutional requirements.');
      return;
    }

    if (password !== confirmPassword) {
      setError('Passwords do not match.');
      return;
    }

    setLoading(true);

    try {
      if (accountType === 'student') {
        const res = await studentFirstLogin(regNo, dob, password);
        setLoading(false);
        if (res.success) {
          onSuccess();
        } else {
          setError(
            res.error ||
              'Invalid registration number or date of birth. Please check your credentials or contact the college office.'
          );
        }
      } else {
        const res = await teacherFirstLogin(username, phone, password);
        setLoading(false);
        if (res.success) {
          onSuccess();
        } else {
          setError(
            res.error ||
              'Invalid teacher username or registered mobile number. Please check your credentials or contact administration.'
          );
        }
      }
    } catch (err: any) {
      setLoading(false);
      setError(err?.message || 'Activation failed. Please try again.');
    }
  };

  const handleTabChange = (type: 'student' | 'teacher') => {
    setAccountType(type);
    setError('');
    setPassword('');
    setConfirmPassword('');
  };

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-navy/60 backdrop-blur-sm animate-fade-in"
      role="dialog"
      aria-modal="true"
      aria-labelledby="first-login-title"
    >
      <div className="w-full max-w-md bg-white rounded-card-lg border border-cardBorder shadow-2xl p-6 sm:p-8 relative max-h-[90vh] overflow-y-auto">
        <div className="flex items-center justify-between pb-4 border-b border-slate-100">
          <div className="flex items-center gap-2.5">
            <div className="w-9 h-9 rounded-xl bg-primary/10 text-primary flex items-center justify-center">
              <Sparkles className="w-5 h-5" />
            </div>
            <div>
              <h3 id="first-login-title" className="font-sora font-bold text-lg text-navy">
                First Time Portal Activation
              </h3>
              <p className="text-xs text-muted">Initialize your verified credentials</p>
            </div>
          </div>
          <button
            type="button"
            onClick={onClose}
            className="p-2 rounded-xl text-muted hover:text-navy hover:bg-slate-100 transition-colors min-h-touch min-w-touch flex items-center justify-center"
            aria-label="Close dialog"
          >
            <X className="w-5 h-5" />
          </button>
        </div>

        {/* Role Segmented Switcher */}
        <div className="mt-4 p-1 bg-slate-100 rounded-xl grid grid-cols-2 gap-1" role="tablist">
          <button
            type="button"
            role="tab"
            aria-selected={accountType === 'student'}
            onClick={() => handleTabChange('student')}
            className={`py-2 px-3 rounded-lg text-xs font-bold transition-all flex items-center justify-center gap-1.5 ${
              accountType === 'student'
                ? 'bg-white text-navy shadow-sm'
                : 'text-slate-500 hover:text-navy hover:bg-white/50'
            }`}
          >
            <GraduationCap className="w-4 h-4" />
            <span>Student Activation</span>
          </button>

          <button
            type="button"
            role="tab"
            aria-selected={accountType === 'teacher'}
            onClick={() => handleTabChange('teacher')}
            className={`py-2 px-3 rounded-lg text-xs font-bold transition-all flex items-center justify-center gap-1.5 ${
              accountType === 'teacher'
                ? 'bg-white text-navy shadow-sm'
                : 'text-slate-500 hover:text-navy hover:bg-white/50'
            }`}
          >
            <Briefcase className="w-4 h-4" />
            <span>Teacher Activation</span>
          </button>
        </div>

        <p className="text-xs text-muted mt-3 leading-relaxed">
          {accountType === 'student'
            ? 'Verify your identity with your official Register Number and Date of Birth to establish your permanent password.'
            : 'Verify your identity with your official Staff Username and Registered Mobile Number to establish your password.'}
        </p>

        {error && (
          <div
            className="mt-4 p-3 bg-error-bg border border-error-border rounded-input flex items-start gap-2.5 text-xs text-error-text"
            role="alert"
            aria-live="assertive"
          >
            <AlertCircle className="w-4 h-4 shrink-0 text-error-accent mt-0.5" />
            <span className="leading-tight">{error}</span>
          </div>
        )}

        <form onSubmit={handleSubmit} className="mt-4 space-y-3.5">
          {accountType === 'student' ? (
            <>
              <div>
                <label htmlFor="modal-reg-no" className="block text-xs font-bold text-navy mb-1">
                  Registration or Admission Number
                </label>
                <div className="relative">
                  <IdCard className="w-4 h-4 text-muted absolute left-3.5 top-3.5" aria-hidden="true" />
                  <input
                    id="modal-reg-no"
                    type="text"
                    required
                    autoComplete="off"
                    placeholder="e.g. 2023MLT042 or ADM-2026-0001"
                    value={regNo}
                    onChange={(e) => setRegNo(e.target.value)}
                    className="w-full pl-10 pr-3.5 py-2.5 text-sm rounded-input border border-inputBorder focus:outline-none focus:ring-2 focus:ring-focusRing min-h-touch"
                  />
                </div>
              </div>

              <div>
                <label htmlFor="modal-dob" className="block text-xs font-bold text-navy mb-1">
                  Date of Birth (DD/MM/YYYY)
                </label>
                <div className="relative">
                  <Calendar className="w-4 h-4 text-muted absolute left-3.5 top-3.5" aria-hidden="true" />
                  <input
                    id="modal-dob"
                    type="text"
                    required
                    inputMode="numeric"
                    placeholder="DD/MM/YYYY"
                    value={dob}
                    onChange={(e) => setDob(formatDobInput(e.target.value))}
                    className="w-full pl-10 pr-3.5 py-2.5 text-sm rounded-input border border-inputBorder focus:outline-none focus:ring-2 focus:ring-focusRing min-h-touch font-mono"
                  />
                </div>
              </div>
            </>
          ) : (
            <>
              <div>
                <label htmlFor="modal-username" className="block text-xs font-bold text-navy mb-1">
                  Staff Username
                </label>
                <div className="relative">
                  <User className="w-4 h-4 text-muted absolute left-3.5 top-3.5" aria-hidden="true" />
                  <input
                    id="modal-username"
                    type="text"
                    required
                    autoComplete="off"
                    placeholder="e.g. prof_kumar or fatima_noor"
                    value={username}
                    onChange={(e) => setUsername(e.target.value)}
                    className="w-full pl-10 pr-3.5 py-2.5 text-sm rounded-input border border-inputBorder focus:outline-none focus:ring-2 focus:ring-focusRing min-h-touch"
                  />
                </div>
              </div>

              <div>
                <label htmlFor="modal-phone" className="block text-xs font-bold text-navy mb-1">
                  Registered Mobile Number
                </label>
                <div className="relative">
                  <Phone className="w-4 h-4 text-muted absolute left-3.5 top-3.5" aria-hidden="true" />
                  <input
                    id="modal-phone"
                    type="tel"
                    required
                    inputMode="numeric"
                    maxLength={14}
                    placeholder="e.g. 9845001122"
                    value={phone}
                    onChange={(e) => setPhone(e.target.value)}
                    className="w-full pl-10 pr-3.5 py-2.5 text-sm rounded-input border border-inputBorder focus:outline-none focus:ring-2 focus:ring-focusRing min-h-touch font-mono"
                  />
                </div>
              </div>
            </>
          )}

          <div>
            <label htmlFor="modal-pass" className="block text-xs font-bold text-navy mb-1">
              Create New Password
            </label>
            <div className="relative">
              <Lock className="w-4 h-4 text-muted absolute left-3.5 top-3.5" aria-hidden="true" />
              <input
                id="modal-pass"
                type={showPass ? 'text' : 'password'}
                required
                placeholder="At least 8 characters"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                className="w-full pl-10 pr-11 py-2.5 text-sm rounded-input border border-inputBorder focus:outline-none focus:ring-2 focus:ring-focusRing min-h-touch"
              />
              <button
                type="button"
                onClick={() => setShowPass(!showPass)}
                className="absolute right-2 top-2 p-1.5 text-muted hover:text-navy rounded-lg"
                aria-label={showPass ? 'Hide password' : 'Show password'}
              >
                {showPass ? <EyeOff className="w-4 h-4" /> : <Eye className="w-4 h-4" />}
              </button>
            </div>

            {/* Inline Password Rules */}
            {password.length > 0 && (
              <div className="mt-2 p-2.5 bg-surface rounded-input text-[11px] space-y-1">
                <div className={`flex items-center gap-1.5 ${policy.rules.length ? 'text-success-text' : 'text-muted'}`}>
                  {policy.rules.length ? <Check className="w-3.5 h-3.5 text-success-text" /> : <span className="w-3.5 h-3.5 inline-block text-center">•</span>}
                  <span>8+ characters</span>
                </div>
                {accountType === 'student' && (
                  <>
                    <div className={`flex items-center gap-1.5 ${policy.rules.notRegNo ? 'text-success-text' : 'text-error-accent'}`}>
                      {policy.rules.notRegNo ? <Check className="w-3.5 h-3.5 text-success-text" /> : <span className="w-3.5 h-3.5 inline-block text-center">•</span>}
                      <span>Not your register or admission number</span>
                    </div>
                    <div className={`flex items-center gap-1.5 ${policy.rules.notDob ? 'text-success-text' : 'text-error-accent'}`}>
                      {policy.rules.notDob ? <Check className="w-3.5 h-3.5 text-success-text" /> : <span className="w-3.5 h-3.5 inline-block text-center">•</span>}
                      <span>Not your birth date or birth year</span>
                    </div>
                  </>
                )}
                {accountType === 'teacher' && (
                  <div className={`flex items-center gap-1.5 ${policy.rules.notUsername ? 'text-success-text' : 'text-error-accent'}`}>
                    {policy.rules.notUsername ? <Check className="w-3.5 h-3.5 text-success-text" /> : <span className="w-3.5 h-3.5 inline-block text-center">•</span>}
                    <span>Not your staff username</span>
                  </div>
                )}
              </div>
            )}
          </div>

          <div>
            <label htmlFor="modal-confirm-pass" className="block text-xs font-bold text-navy mb-1">
              Confirm Password
            </label>
            <div className="relative">
              <Lock className="w-4 h-4 text-muted absolute left-3.5 top-3.5" aria-hidden="true" />
              <input
                id="modal-confirm-pass"
                type="password"
                required
                placeholder="Re-enter password"
                value={confirmPassword}
                onChange={(e) => setConfirmPassword(e.target.value)}
                className="w-full pl-10 pr-3.5 py-2.5 text-sm rounded-input border border-inputBorder focus:outline-none focus:ring-2 focus:ring-focusRing min-h-touch"
              />
            </div>
          </div>

          <div className="pt-2">
            <button
              type="submit"
              disabled={loading}
              className="w-full py-3 rounded-btn font-sora font-bold text-sm text-white bg-primary hover:bg-primary-hover shadow-primary-btn transition-all disabled:opacity-50 min-h-touch flex items-center justify-center gap-2"
            >
              {loading ? (
                <>
                  <div className="w-4 h-4 border-2 border-white border-t-transparent rounded-full animate-spin" />
                  <span>Activating Account...</span>
                </>
              ) : (
                <>
                  <CheckCircle2 className="w-4 h-4" />
                  <span>Activate & Proceed</span>
                </>
              )}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
};
