// src/components/notifications/PushPromptModal.tsx
// Opt-in Push Notification Prompt Modal shown on 2nd login or from Profile settings

import React, { useState } from 'react';
import { pushNotificationService } from '../../lib/pushNotifications';
import { Bell, Sparkles, X, CheckCircle2, AlertCircle } from 'lucide-react';

interface PushPromptModalProps {
  userId: string;
  isOpen: boolean;
  onClose: () => void;
  onSuccess?: () => void;
}

export const PushPromptModal: React.FC<PushPromptModalProps> = ({
  userId,
  isOpen,
  onClose,
  onSuccess,
}) => {
  const [loading, setLoading] = useState(false);
  const [feedback, setFeedback] = useState<{ type: 'success' | 'error'; message: string } | null>(
    null
  );

  if (!isOpen) return null;

  const handleSubscribe = async () => {
    setLoading(true);
    setFeedback(null);

    const res = await pushNotificationService.subscribeUser(userId);
    setLoading(false);

    if (res.success) {
      setFeedback({
        type: 'success',
        message: 'Push notifications enabled successfully! You will receive alerts on this device.',
      });
      setTimeout(() => {
        onSuccess?.();
        onClose();
      }, 1500);
    } else {
      setFeedback({
        type: 'error',
        message: res.error || 'Unable to enable push notifications on this device.',
      });
    }
  };

  return (
    <div
      role="dialog"
      aria-modal="true"
      className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-navy/60 backdrop-blur-sm animate-fade-in"
    >
      <div className="w-full max-w-md bg-white rounded-card-lg border border-cardBorder shadow-2xl p-6 sm:p-7 relative">
        <button
          type="button"
          onClick={onClose}
          className="absolute top-4 right-4 p-1.5 rounded-lg text-slate-400 hover:text-slate-600 hover:bg-slate-100 transition-colors"
          aria-label="Close"
        >
          <X className="w-5 h-5" />
        </button>

        <div className="flex items-center gap-3 mb-4">
          <div className="p-3 rounded-2xl bg-teal/15 text-teal">
            <Bell className="w-6 h-6" />
          </div>
          <div>
            <h3 className="font-sora font-bold text-lg text-navy">
              Stay Informed with Instant Alerts
            </h3>
            <p className="text-xs text-muted">Never miss important campus updates</p>
          </div>
        </div>

        <p className="text-xs text-slate-600 leading-relaxed mb-4">
          Enable push notifications on your phone or computer to receive real-time updates when:
        </p>

        <div className="space-y-2 mb-5">
          <div className="flex items-start gap-2.5 p-2.5 rounded-xl bg-surface border border-cardBorder text-xs">
            <span className="w-2 h-2 rounded-full bg-primary mt-1.5 flex-shrink-0" />
            <span className="text-navy">
              Official semester & practical exam results are published.
            </span>
          </div>
          <div className="flex items-start gap-2.5 p-2.5 rounded-xl bg-surface border border-cardBorder text-xs">
            <span className="w-2 h-2 rounded-full bg-amber-500 mt-1.5 flex-shrink-0" />
            <span className="text-navy">
              Attendance shortage warnings or low-attendance reminders occur.
            </span>
          </div>
          <div className="flex items-start gap-2.5 p-2.5 rounded-xl bg-surface border border-cardBorder text-xs">
            <span className="w-2 h-2 rounded-full bg-teal mt-1.5 flex-shrink-0" />
            <span className="text-navy">
              Weekly class timetables and classroom changes are updated.
            </span>
          </div>
        </div>

        {feedback && (
          <div
            className={`mb-4 p-3 rounded-xl border flex items-center gap-2 text-xs ${
              feedback.type === 'success'
                ? 'bg-success-bg border-success-text/20 text-success-text'
                : 'bg-error-bg border-error-border text-error-text'
            }`}
          >
            {feedback.type === 'success' ? (
              <CheckCircle2 className="w-4 h-4 flex-shrink-0" />
            ) : (
              <AlertCircle className="w-4 h-4 flex-shrink-0" />
            )}
            <span>{feedback.message}</span>
          </div>
        )}

        <div className="flex items-center justify-end gap-2 pt-2">
          <button
            type="button"
            onClick={onClose}
            className="px-4 py-2.5 rounded-button text-xs font-semibold text-muted hover:text-navy hover:bg-surface min-h-touch"
          >
            Not Now
          </button>
          <button
            type="button"
            onClick={handleSubscribe}
            disabled={loading}
            className="px-5 py-2.5 rounded-button text-xs font-semibold text-white bg-primary hover:bg-primary-hover shadow-sm min-h-touch flex items-center gap-2 disabled:opacity-50"
          >
            {loading ? (
              <>
                <div className="w-3.5 h-3.5 border-2 border-white border-t-transparent rounded-full animate-spin" />
                <span>Enabling...</span>
              </>
            ) : (
              <>
                <Sparkles className="w-4 h-4" />
                <span>Enable Notifications</span>
              </>
            )}
          </button>
        </div>
      </div>
    </div>
  );
};
