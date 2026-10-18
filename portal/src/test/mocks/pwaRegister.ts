// src/test/mocks/pwaRegister.ts
import { useState } from 'react';

export function useRegisterSW(options?: any) {
  const [needRefresh, setNeedRefresh] = useState(false);
  const [offlineReady, setOfflineReady] = useState(false);
  return {
    needRefresh: [needRefresh, setNeedRefresh] as [boolean, (val: boolean) => void],
    offlineReady: [offlineReady, setOfflineReady] as [boolean, (val: boolean) => void],
    updateServiceWorker: async (_reload?: boolean) => {},
  };
}
