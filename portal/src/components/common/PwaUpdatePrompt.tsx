// src/components/common/PwaUpdatePrompt.tsx
// PWA Update Prompt: Alerts users when a new app shell or cache version is available

import React from 'react';
import { useRegisterSW } from 'virtual:pwa-register/react';
import { Sparkles, RefreshCw, X } from 'lucide-react';

export const PwaUpdatePrompt: React.FC = () => {
  const {
    needRefresh: [needRefresh, setNeedRefresh],
    updateServiceWorker,
  } = useRegisterSW({
    onRegistered(r) {
      if (r) {
        // Check for SW updates every hour
        setInterval(() => {
          r.update();
        }, 60 * 60 * 1000);
      }
    },
    onRegisterError(error) {
      console.warn('PWA Service Worker registration error:', error);
    },
  });

  if (!needRefresh) return null;

  return (
    <div
      role="alert"
      className="fixed bottom-4 right-4 z-50 max-w-sm w-full bg-navy text-white rounded-card-lg border border-teal/30 shadow-2xl p-4 animate-fade-in"
    >
      <div className="flex items-start gap-3">
        <div className="p-2 rounded-xl bg-teal/20 text-teal flex-shrink-0">
          <Sparkles className="w-5 h-5" />
        </div>
        <div className="flex-1 min-w-0">
          <h4 className="font-sora font-bold text-sm text-white leading-tight">
            Update Available
          </h4>
          <p className="text-xs text-navy-text mt-1">
            A new version of MIPS Portal is available. Reload to update.
          </p>

          <div className="flex items-center gap-2 mt-3">
            <button
              type="button"
              onClick={() => updateServiceWorker(true)}
              className="inline-flex items-center gap-1.5 px-3.5 py-1.5 rounded-lg bg-teal hover:bg-teal/90 text-navy text-xs font-bold transition-colors min-h-touch"
            >
              <RefreshCw className="w-3.5 h-3.5" />
              <span>Reload to update</span>
            </button>
            <button
              type="button"
              onClick={() => setNeedRefresh(false)}
              className="px-2.5 py-1.5 text-xs text-navy-text hover:text-white transition-colors"
            >
              Later
            </button>
          </div>
        </div>
        <button
          type="button"
          onClick={() => setNeedRefresh(false)}
          className="p-1 text-white/60 hover:text-white"
          aria-label="Dismiss notification"
        >
          <X className="w-4 h-4" />
        </button>
      </div>
    </div>
  );
};
