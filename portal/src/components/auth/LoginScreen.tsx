// src/components/auth/LoginScreen.tsx
// MIPS Portal Master Authentication Screen

import React, { useState } from 'react';
import { useAuth } from '../../context/AuthContext';
import { TurnstileWidget } from './TurnstileWidget';
import { EcgLine } from '../common/EcgLine';
import { Lock, User, Eye, EyeOff, AlertCircle, ArrowRight, ShieldAlert } from 'lucide-react';

interface LoginScreenProps {
  onSuccess?: () => void;
}

export const LoginScreen: React.FC<LoginScreenProps> = ({ onSuccess }) => {
  const { login } = useAuth();
  const [identifier, setIdentifier] = useState('');
  const [password, setPassword] = useState('');
  const [showPassword, setShowPassword] = useState(false);

  // Failure and Lockout Tracking
  const [failedAttempts, setFailedAttempts] = useState(0);
  const [isLocked, setIsLocked] = useState(false);
  const [requiresCaptcha, setRequiresCaptcha] = useState(false);
  const [captchaToken, setCaptchaToken] = useState<string>('');

  // UI States
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const turnstileSiteKey = import.meta.env.VITE_TURNSTILE_SITE_KEY || '1x00000000000000000000AA';

  const shouldShowTurnstile = requiresCaptcha || failedAttempts >= 2;

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (isLocked) return;

    setError(null);
    setLoading(true);

    if (shouldShowTurnstile && !captchaToken) {
      setLoading(false);
      setError('Security verification required. Please complete the CAPTCHA.');
      return;
    }

    const res = await login(identifier, password, captchaToken || undefined);
    setLoading(false);

    if (res.success) {
      setFailedAttempts(0);
      onSuccess?.();
    } else {
      const newCount = failedAttempts + 1;
      setFailedAttempts(newCount);

      if (res.details?.is_locked) {
        setIsLocked(true);
        setError('Too many failed attempts. Please contact the college office to reset your password.');
      } else if (res.details?.requires_captcha || newCount >= 2) {
        setRequiresCaptcha(true);
        setError(res.error || 'Register number or password is incorrect.');
      } else {
        setError(res.error || 'Register number or password is incorrect.');
      }
    }
  };

  return (
    <div className="min-h-screen bg-pageBg flex flex-col justify-between selection:bg-focusRing selection:text-navy">
      {/* Navy Header with ECG Heartbeat Line */}
      <header className="bg-navy pt-8 pb-14 px-4 sm:px-6 relative overflow-hidden">
        <div className="max-w-md mx-auto text-center relative z-10">
          <div className="inline-flex items-center justify-center p-2 mb-3 bg-white/10 rounded-2xl shadow-inner">
            <img
              src="/logo.png"
              alt="MIPS Logo"
              className="w-12 h-12 object-contain rounded-xl"
              onError={(e) => {
                // Fallback white rounded square with 'M'
                e.currentTarget.style.display = 'none';
                const parent = e.currentTarget.parentElement;
                if (parent) {
                  parent.innerHTML = '<div class="w-12 h-12 rounded-xl bg-white text-navy font-sora font-bold text-xl flex items-center justify-center">M</div>';
                }
              }}
            />
          </div>
          <h1 className="font-sora font-bold text-xl sm:text-2xl text-white tracking-tight">
            MIPS Portal
          </h1>
          <p className="text-xs sm:text-sm text-navy-text mt-1">
            Malabar Institute of Paramedical Science
          </p>
        </div>

        {/* ECG Heartbeat Accent */}
        <div className="absolute bottom-0 left-0 right-0">
          <EcgLine />
        </div>
      </header>

      {/* Main Login Card - Overlaps Navy Header slightly */}
      <main className="flex-1 -mt-6 px-4 pb-12 flex justify-center">
        <div className="w-full max-w-md bg-white rounded-card-lg border border-cardBorder shadow-login-card p-6 sm:p-8">
          <div className="mb-5 text-center sm:text-left">
            <h2 className="font-sora font-bold text-lg sm:text-xl text-navy">
              Sign In to Your Account
            </h2>
            <p className="text-xs text-muted mt-1">
              Enter your credentials to access examination results, fees, attendance and timetable.
            </p>
          </div>

          {/* Error Banner with aria-live */}
          {error && (
            <div
              className={`mb-5 p-3.5 rounded-input border flex items-start gap-2.5 text-xs ${
                isLocked
                  ? 'bg-error-bg border-error-border text-error-text'
                  : 'bg-error-bg border-error-border text-error-text'
              }`}
              role="alert"
              aria-live="assertive"
            >
              {isLocked ? (
                <ShieldAlert className="w-4 h-4 shrink-0 text-error-accent mt-0.5" />
              ) : (
                <AlertCircle className="w-4 h-4 shrink-0 text-error-accent mt-0.5" />
              )}
              <span className="leading-tight font-medium">{error}</span>
            </div>
          )}

          <form onSubmit={handleSubmit} className="space-y-4">
            {/* Identifier Field */}
            <div>
              <label htmlFor="login-identifier" className="block text-xs font-bold text-navy mb-1.5">
                Register number or username
              </label>
              <div className="relative">
                <User className="w-4 h-4 text-muted absolute left-3.5 top-3.5" aria-hidden="true" />
                <input
                  id="login-identifier"
                  type="text"
                  required
                  disabled={isLocked}
                  autoComplete="username"
                  placeholder="e.g. MIPS/2024/001 or staff username"
                  value={identifier}
                  onChange={(e) => setIdentifier(e.target.value)}
                  className="w-full pl-10 pr-3.5 py-2.5 text-sm rounded-input border border-inputBorder focus:outline-none focus:ring-2 focus:ring-focusRing min-h-touch disabled:bg-slate-100 disabled:cursor-not-allowed transition-all"
                />
              </div>
            </div>

            {/* Password Field */}
            <div>
              <label htmlFor="login-password" className="block text-xs font-bold text-navy mb-1.5">
                Password
              </label>
              <div className="relative">
                <Lock className="w-4 h-4 text-muted absolute left-3.5 top-3.5" aria-hidden="true" />
                <input
                  id="login-password"
                  type={showPassword ? 'text' : 'password'}
                  required
                  disabled={isLocked}
                  autoComplete="current-password"
                  placeholder="Enter your password"
                  value={password}
                  onChange={(e) => setPassword(e.target.value)}
                  className="w-full pl-10 pr-11 py-2.5 text-sm rounded-input border border-inputBorder focus:outline-none focus:ring-2 focus:ring-focusRing min-h-touch disabled:bg-slate-100 disabled:cursor-not-allowed transition-all"
                />
                <button
                  type="button"
                  disabled={isLocked}
                  onClick={() => setShowPassword(!showPassword)}
                  className="absolute right-2 top-2 p-1.5 text-muted hover:text-navy rounded-lg focus:outline-none focus:ring-2 focus:ring-focusRing"
                  aria-label={showPassword ? 'Hide password' : 'Show password'}
                >
                  {showPassword ? <EyeOff className="w-4 h-4" /> : <Eye className="w-4 h-4" />}
                </button>
              </div>
            </div>

            {/* Cloudflare Turnstile (Appears from 3rd failure or server request) */}
            {shouldShowTurnstile && !isLocked && (
              <div className="py-1">
                <TurnstileWidget
                  siteKey={turnstileSiteKey}
                  onVerify={(token) => setCaptchaToken(token)}
                  onExpire={() => setCaptchaToken('')}
                  onError={() => setError('Security verification error. Please refresh.')}
                />
              </div>
            )}

            {/* Submit Button */}
            <button
              type="submit"
              disabled={loading || isLocked}
              className="w-full py-3 rounded-btn font-sora font-bold text-sm text-white bg-primary hover:bg-primary-hover shadow-primary-btn transition-all disabled:opacity-50 min-h-touch flex items-center justify-center gap-2"
            >
              {loading ? (
                <>
                  <div className="w-4 h-4 border-2 border-white border-t-transparent rounded-full animate-spin" />
                  <span>Checking...</span>
                </>
              ) : isLocked ? (
                <span>Account Locked</span>
              ) : (
                <>
                  <span>Log in</span>
                  <ArrowRight className="w-4 h-4" />
                </>
              )}
            </button>


          </form>

        </div>
      </main>

      {/* Footer */}
      <footer className="py-4 px-4 text-center text-xs text-muted border-t border-cardBorder bg-white">
        <p>Result not showing? Contact the college office.</p>
        <p className="mt-1 text-[11px] text-slate-400">
          © {new Date().getFullYear()} Malabar Institute of Paramedical Science
        </p>
      </footer>
    </div>
  );
};
