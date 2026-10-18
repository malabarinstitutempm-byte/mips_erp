// src/components/common/ErrorRetry.tsx
// Reusable Error & Retry View

import React from 'react';
import { AlertCircle, RefreshCw } from 'lucide-react';

interface ErrorRetryProps {
  message?: string;
  onRetry: () => void;
  isRetrying?: boolean;
}

export const ErrorRetry: React.FC<ErrorRetryProps> = ({
  message = 'Failed to load information. Please verify your connection and try again.',
  onRetry,
  isRetrying = false,
}) => {
  return (
    <div className="bg-white rounded-card-lg border border-error-border p-6 sm:p-8 text-center max-w-md mx-auto" role="alert">
      <div className="w-12 h-12 rounded-2xl bg-error-bg text-error-accent flex items-center justify-center mx-auto mb-3">
        <AlertCircle className="w-6 h-6" />
      </div>
      <h3 className="font-sora font-bold text-base text-navy">Unable to Load Data</h3>
      <p className="text-xs text-muted mt-1 leading-relaxed">{message}</p>
      <div className="mt-5">
        <button
          type="button"
          onClick={onRetry}
          disabled={isRetrying}
          className="inline-flex items-center gap-2 px-5 py-2.5 rounded-btn font-sora font-semibold text-xs text-white bg-primary hover:bg-primary-hover shadow-primary-btn transition-all disabled:opacity-50 min-h-touch"
        >
          <RefreshCw className={`w-3.5 h-3.5 ${isRetrying ? 'animate-spin' : ''}`} />
          <span>{isRetrying ? 'Retrying...' : 'Try Again'}</span>
        </button>
      </div>
    </div>
  );
};
