// src/components/auth/ForcePasswordChange.tsx
// Forced Password Update Screen for Temporary Passwords & Admin Resets

import React, { useState } from 'react';
import { useAuth } from '../../context/AuthContext';
import { evaluatePasswordPolicy } from '../../lib/passwordPolicy';
import { KeyRound, Lock, Eye, EyeOff, AlertCircle, Check, CheckCircle2, LogOut } from 'lucide-react';
import { EcgLine } from '../common/EcgLine';

interface ForcePasswordChangeProps {
  onSuccess: () => void;
}

export const ForcePasswordChange: React.FC<ForcePasswordChangeProps> = ({ onSuccess }) => {
  const { user, profile, setPassword, logout } = useAuth();
  const [newPassword, setNewPassword] = useState('');
  const [confirmPassword, setConfirmPassword] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');

  const contextData = {
    username: user?.email?.split('@')[0],
  };

  const policy = evaluatePasswordPolicy(newPassword, contextData);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError('');

    if (!policy.isValid) {
      setError(policy.errors[0] || 'Password does not meet institutional requirements.');
      return;
    }

    if (newPassword !== confirmPassword) {
      setError('Passwords do not match.');
      return;
    }

    setLoading(true);
    const res = await setPassword(newPassword);
    setLoading(false);

    if (res.success) {
      onSuccess();
    } else {
      setError(res.error || 'Failed to update password. Please try again.');
    }
  };

  return (
    <div className="min-h-screen bg-pageBg flex flex-col justify-between selection:bg-focusRing selection:text-navy">
      {/* Navy Header with ECG line */}
      <header className="bg-navy pt-8 pb-14 px-4 relative overflow-hidden">
        <div className="max-w-md mx-auto text-center relative z-10">
          <div className="w-12 h-12 rounded-2xl bg-white/10 text-white flex items-center justify-center mx-auto mb-3 shadow-inner">
            <KeyRound className="w-6 h-6 text-teal" />
          </div>
          <h1 className="font-sora font-bold text-xl sm:text-2xl text-white">
            Set Your Permanent Password
          </h1>
          <p className="text-xs sm:text-sm text-navy-text mt-1">
            {profile?.role === 'teacher'
              ? 'Your temporary login credentials must be replaced with a secure password.'
              : 'Institutional security requires setting a new password before proceeding.'}
          </p>
        </div>
        <div className="absolute bottom-0 left-0 right-0">
          <EcgLine />
        </div>
      </header>

      {/* Overlapping Content Card */}
      <main className="flex-1 -mt-6 px-4 pb-12 flex justify-center">
        <div className="w-full max-w-md bg-white rounded-card-lg border border-cardBorder shadow-login-card p-6 sm:p-8">
          {error && (
            <div
              className="mb-5 p-3.5 bg-error-bg border border-error-border rounded-input flex items-start gap-2.5 text-xs text-error-text"
              role="alert"
              aria-live="assertive"
            >
              <AlertCircle className="w-4 h-4 shrink-0 text-error-accent mt-0.5" />
              <span>{error}</span>
            </div>
          )}

          <form onSubmit={handleSubmit} className="space-y-4">
            <div>
              <label htmlFor="new-pass-field" className="block text-xs font-bold text-navy mb-1.5">
                New Password
              </label>
              <div className="relative">
                <Lock className="w-4 h-4 text-muted absolute left-3.5 top-3.5" aria-hidden="true" />
                <input
                  id="new-pass-field"
                  type={showPassword ? 'text' : 'password'}
                  required
                  placeholder="Enter new password"
                  value={newPassword}
                  onChange={(e) => setNewPassword(e.target.value)}
                  className="w-full pl-10 pr-11 py-2.5 text-sm rounded-input border border-inputBorder focus:outline-none focus:ring-2 focus:ring-focusRing min-h-touch"
                />
                <button
                  type="button"
                  onClick={() => setShowPassword(!showPassword)}
                  className="absolute right-2 top-2 p-1.5 text-muted hover:text-navy rounded-lg"
                  aria-label={showPassword ? 'Hide password' : 'Show password'}
                >
                  {showPassword ? <EyeOff className="w-4 h-4" /> : <Eye className="w-4 h-4" />}
                </button>
              </div>

              {/* Inline Password Rules */}
              <div className="mt-2.5 p-3 bg-surface rounded-input text-xs space-y-1.5">
                <p className="font-semibold text-navy text-[11px] mb-1">Password Requirements:</p>
                <div className={`flex items-center gap-1.5 ${policy.rules.length ? 'text-success-text' : 'text-muted'}`}>
                  {policy.rules.length ? <Check className="w-3.5 h-3.5 text-success-text" /> : <span>•</span>}
                  <span>At least 8 characters</span>
                </div>
                <div className={`flex items-center gap-1.5 ${policy.rules.notUsername ? 'text-success-text' : 'text-error-accent'}`}>
                  {policy.rules.notUsername ? <Check className="w-3.5 h-3.5 text-success-text" /> : <span>•</span>}
                  <span>Not your username</span>
                </div>
              </div>
            </div>

            <div>
              <label htmlFor="confirm-pass-field" className="block text-xs font-bold text-navy mb-1.5">
                Confirm New Password
              </label>
              <div className="relative">
                <Lock className="w-4 h-4 text-muted absolute left-3.5 top-3.5" aria-hidden="true" />
                <input
                  id="confirm-pass-field"
                  type="password"
                  required
                  placeholder="Re-enter password"
                  value={confirmPassword}
                  onChange={(e) => setConfirmPassword(e.target.value)}
                  className="w-full pl-10 pr-3.5 py-2.5 text-sm rounded-input border border-inputBorder focus:outline-none focus:ring-2 focus:ring-focusRing min-h-touch"
                />
              </div>
            </div>

            <div className="pt-3 space-y-3">
              <button
                type="submit"
                disabled={loading}
                className="w-full py-3 rounded-btn font-sora font-bold text-sm text-white bg-primary hover:bg-primary-hover shadow-primary-btn transition-all disabled:opacity-50 min-h-touch flex items-center justify-center gap-2"
              >
                {loading ? (
                  <>
                    <div className="w-4 h-4 border-2 border-white border-t-transparent rounded-full animate-spin" />
                    <span>Updating Password...</span>
                  </>
                ) : (
                  <>
                    <CheckCircle2 className="w-4 h-4" />
                    <span>Save Password & Continue</span>
                  </>
                )}
              </button>

              <button
                type="button"
                onClick={logout}
                className="w-full py-2.5 text-xs font-medium text-muted hover:text-navy transition-colors flex items-center justify-center gap-1.5"
              >
                <LogOut className="w-3.5 h-3.5" />
                <span>Cancel & Sign Out</span>
              </button>
            </div>
          </form>
        </div>
      </main>

      <footer className="py-4 text-center text-xs text-muted border-t border-cardBorder bg-white">
        © {new Date().getFullYear()} Malabar Institute of Paramedical Science
      </footer>
    </div>
  );
};
