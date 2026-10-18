// src/components/common/OfflineBanner.tsx
// Persistent banner displayed when the browser is disconnected from the network

import React, { useState } from 'react';
import { useOnlineStatus } from '../../context/OnlineStatusContext';
import { WifiOff, RefreshCw } from 'lucide-react';

export const OfflineBanner: React.FC = () => {
  const { isOnline, checkConnection } = useOnlineStatus();
  const [isRetrying, setIsRetrying] = useState(false);

  if (isOnline) return null;

  const handleRetry = async () => {
    setIsRetrying(true);
    await checkConnection();
    setTimeout(() => setIsRetrying(false), 500);
  };

  return (
    <div
      role="status"
      aria-live="polite"
      className="bg-amber-600 text-white px-4 py-2.5 text-xs font-semibold flex items-center justify-between shadow-md transition-all z-50 sticky top-0"
    >
      <div className="flex items-center gap-2 max-w-[1040px] mx-auto w-full justify-between">
        <div className="flex items-center gap-2">
          <WifiOff className="w-4 h-4 text-amber-200 animate-pulse flex-shrink-0" />
          <span>You're offline. Showing saved data.</span>
        </div>

        <button
          type="button"
          onClick={handleRetry}
          disabled={isRetrying}
          className="inline-flex items-center gap-1.5 px-3 py-1 rounded-lg bg-white/20 hover:bg-white/30 active:bg-white/40 transition-colors text-white text-[11px] font-bold min-h-[32px] focus:outline-none focus:ring-2 focus:ring-white"
        >
          <RefreshCw className={`w-3.5 h-3.5 ${isRetrying ? 'animate-spin' : ''}`} />
          <span>{isRetrying ? 'Checking...' : 'Retry'}</span>
        </button>
      </div>
    </div>
  );
};
