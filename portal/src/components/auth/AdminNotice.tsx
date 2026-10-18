// src/components/auth/AdminNotice.tsx
// Redirect / Notice Screen for Institutional Administrators

import React from 'react';
import { useAuth } from '../../context/AuthContext';
import { ShieldCheck, ExternalLink, LogOut } from 'lucide-react';
import { EcgLine } from '../common/EcgLine';

export const AdminNotice: React.FC = () => {
  const { logout } = useAuth();

  return (
    <div className="min-h-screen bg-pageBg flex flex-col justify-between selection:bg-focusRing selection:text-navy">
      <header className="bg-navy pt-8 pb-14 px-4 text-center relative overflow-hidden">
        <div className="max-w-md mx-auto relative z-10">
          <div className="w-12 h-12 rounded-2xl bg-white/10 text-white flex items-center justify-center mx-auto mb-3 shadow-inner">
            <ShieldCheck className="w-6 h-6 text-teal" />
          </div>
          <h1 className="font-sora font-bold text-xl sm:text-2xl text-white">
            Administrator Access Detected
          </h1>
          <p className="text-xs sm:text-sm text-navy-text mt-1">
            This portal is designated for students and teachers.
          </p>
        </div>
        <div className="absolute bottom-0 left-0 right-0">
          <EcgLine />
        </div>
      </header>

      <main className="flex-1 -mt-6 px-4 pb-12 flex justify-center">
        <div className="w-full max-w-md bg-white rounded-card-lg border border-cardBorder shadow-login-card p-6 sm:p-8 text-center">
          <div className="w-14 h-14 rounded-2xl bg-amber-50 text-amber-700 border border-amber-200 flex items-center justify-center mx-auto mb-4">
            <ShieldCheck className="w-7 h-7" />
          </div>

          <h2 className="font-sora font-bold text-lg text-navy">
            Administrators use the admin app
          </h2>
          <p className="text-xs text-muted mt-2 leading-relaxed">
            Administrative functions, course management, fee ledgers, and institutional reporting are managed through the dedicated MIPS ERP Admin Application.
          </p>

          <div className="mt-6 space-y-3">
            <a
              href="/"
              className="w-full py-3 px-4 rounded-btn font-sora font-bold text-sm text-white bg-primary hover:bg-primary-hover shadow-primary-btn transition-all flex items-center justify-center gap-2 min-h-touch"
            >
              <span>Launch Admin App</span>
              <ExternalLink className="w-4 h-4" />
            </a>

            <button
              type="button"
              onClick={logout}
              className="w-full py-3 px-4 rounded-btn font-sora font-bold text-sm text-error-accent bg-error-bg hover:bg-red-100 border border-error-border transition-all flex items-center justify-center gap-2 min-h-touch"
            >
              <LogOut className="w-4 h-4" />
              <span>Sign Out</span>
            </button>
          </div>
        </div>
      </main>

      <footer className="py-4 text-center text-xs text-muted border-t border-cardBorder bg-white">
        © {new Date().getFullYear()} Malabar Institute of Paramedical Science
      </footer>
    </div>
  );
};
