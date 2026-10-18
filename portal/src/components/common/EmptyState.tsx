// src/components/common/EmptyState.tsx
// Reusable empty state view with stroke icons

import React from 'react';

interface EmptyStateProps {
  icon: React.ReactNode;
  title: string;
  message: string;
  action?: {
    label: string;
    onClick: () => void;
  };
}

export const EmptyState: React.FC<EmptyStateProps> = ({ icon, title, message, action }) => {
  return (
    <div className="bg-white rounded-card-lg border border-cardBorder p-8 sm:p-12 text-center max-w-md mx-auto">
      <div className="w-14 h-14 rounded-2xl bg-surface text-primary flex items-center justify-center mx-auto mb-4 border border-cardBorder">
        {icon}
      </div>
      <h3 className="font-sora font-bold text-base sm:text-lg text-navy">{title}</h3>
      <p className="text-xs sm:text-sm text-muted mt-1.5 leading-relaxed">{message}</p>
      {action && (
        <div className="mt-5">
          <button
            type="button"
            onClick={action.onClick}
            className="px-5 py-2.5 rounded-btn font-sora font-semibold text-xs text-white bg-primary hover:bg-primary-hover shadow-primary-btn transition-all min-h-touch"
          >
            {action.label}
          </button>
        </div>
      )}
    </div>
  );
};
