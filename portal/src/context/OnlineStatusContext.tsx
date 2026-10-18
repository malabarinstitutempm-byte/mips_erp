// src/context/OnlineStatusContext.tsx
// Global Network Online / Offline Detection Context

import React, { createContext, useContext, useState, useEffect } from 'react';

interface OnlineStatusContextType {
  isOnline: boolean;
  checkConnection: () => Promise<boolean>;
}

const OnlineStatusContext = createContext<OnlineStatusContextType>({
  isOnline: true,
  checkConnection: async () => true,
});

export const OnlineStatusProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const [isOnline, setIsOnline] = useState<boolean>(
    typeof navigator !== 'undefined' ? navigator.onLine : true
  );

  const checkConnection = async (): Promise<boolean> => {
    try {
      // Check head request to logo or origin with cache-busting
      const res = await fetch(`/logo.png?_t=${Date.now()}`, { method: 'HEAD', cache: 'no-store' });
      const online = res.ok;
      setIsOnline(online);
      return online;
    } catch {
      setIsOnline(false);
      return false;
    }
  };

  useEffect(() => {
    const handleOnline = () => {
      setIsOnline(true);
      checkConnection();
    };

    const handleOffline = () => {
      setIsOnline(false);
    };

    window.addEventListener('online', handleOnline);
    window.addEventListener('offline', handleOffline);

    return () => {
      window.removeEventListener('online', handleOnline);
      window.removeEventListener('offline', handleOffline);
    };
  }, []);

  return (
    <OnlineStatusContext.Provider value={{ isOnline, checkConnection }}>
      {children}
    </OnlineStatusContext.Provider>
  );
};

export function useOnlineStatus() {
  return useContext(OnlineStatusContext);
}
