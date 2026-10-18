// src/components/common/EcgLine.tsx
// Thin teal ECG heartbeat vector line for navy headers

import React from 'react';

export const EcgLine: React.FC<{ className?: string }> = ({ className = '' }) => {
  return (
    <svg
      viewBox="0 0 300 32"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
      className={`w-full h-4 overflow-visible pointer-events-none ${className}`}
      aria-hidden="true"
    >
      <path
        d="M0 16 H80 L88 8 L98 24 L108 3 L118 28 L126 12 L134 16 H300"
        stroke="#19B5A5"
        strokeWidth="2.2"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  );
};
