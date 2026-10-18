// src/components/common/LoadingSkeleton.tsx
// Unified Skeleton Loader for Lists, Cards, and Tables

import React from 'react';

export const LoadingSkeleton: React.FC<{ rows?: number; type?: 'card' | 'table' | 'list' }> = ({
  rows = 3,
  type = 'card',
}) => {
  if (type === 'table') {
    return (
      <div className="bg-white rounded-card-lg border border-cardBorder p-4 sm:p-6 space-y-4 animate-pulse">
        <div className="h-6 bg-slate-100 rounded-input w-1/4" />
        <div className="space-y-3">
          {Array.from({ length: rows }).map((_, i) => (
            <div key={i} className="flex gap-4">
              <div className="h-5 bg-slate-100 rounded w-1/3" />
              <div className="h-5 bg-slate-100 rounded w-1/4" />
              <div className="h-5 bg-slate-100 rounded w-1/4" />
              <div className="h-5 bg-slate-100 rounded w-1/6" />
            </div>
          ))}
        </div>
      </div>
    );
  }

  if (type === 'list') {
    return (
      <div className="space-y-3 animate-pulse">
        {Array.from({ length: rows }).map((_, i) => (
          <div key={i} className="bg-white rounded-card border border-cardBorder p-4 flex items-center justify-between">
            <div className="space-y-2 w-2/3">
              <div className="h-4 bg-slate-100 rounded w-3/4" />
              <div className="h-3 bg-slate-100 rounded w-1/2" />
            </div>
            <div className="h-8 bg-slate-100 rounded-btn w-20" />
          </div>
        ))}
      </div>
    );
  }

  return (
    <div className="space-y-4 animate-pulse">
      <div className="bg-white rounded-card-lg border border-cardBorder p-6 space-y-3">
        <div className="h-6 bg-slate-100 rounded-input w-1/3" />
        <div className="h-4 bg-slate-100 rounded-input w-1/2" />
        <div className="h-16 bg-slate-50 rounded-card mt-4" />
      </div>
    </div>
  );
};
