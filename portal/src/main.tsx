// src/main.tsx
// React 19 Entrypoint with TanStack Query and Global Providers

import React from 'react';
import ReactDOM from 'react-dom/client';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import App from './App';
import { AuthProvider } from './context/AuthContext';
import './style.css';

const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: 1000 * 60 * 5, // 5 minutes default
      gcTime: 1000 * 60 * 30, // 30 minutes in GC cache
      retry: 1,
      refetchOnWindowFocus: false,
      refetchOnReconnect: false,
    },
  },
});

// O3 Optimization: Granular caching rules by data volatility
// 1. Static / Reference data: long cache (30-60 mins)
queryClient.setQueryDefaults(['studentProfile'], {
  staleTime: 1000 * 60 * 30,
  gcTime: 1000 * 60 * 60,
  refetchOnWindowFocus: false,
  refetchOnReconnect: false,
});
queryClient.setQueryDefaults(['teacherProfile'], {
  staleTime: 1000 * 60 * 30,
  gcTime: 1000 * 60 * 60,
  refetchOnWindowFocus: false,
  refetchOnReconnect: false,
});
queryClient.setQueryDefaults(['courses'], {
  staleTime: 1000 * 60 * 30,
  gcTime: 1000 * 60 * 60,
  refetchOnWindowFocus: false,
  refetchOnReconnect: false,
});
queryClient.setQueryDefaults(['batches'], {
  staleTime: 1000 * 60 * 30,
  gcTime: 1000 * 60 * 60,
  refetchOnWindowFocus: false,
  refetchOnReconnect: false,
});
queryClient.setQueryDefaults(['teacherBatches'], {
  staleTime: 1000 * 60 * 30,
  gcTime: 1000 * 60 * 60,
  refetchOnWindowFocus: false,
  refetchOnReconnect: false,
});
queryClient.setQueryDefaults(['settings'], {
  staleTime: 1000 * 60 * 60,
  gcTime: 1000 * 60 * 120,
  refetchOnWindowFocus: false,
  refetchOnReconnect: false,
});

// 2. Results and Fees: medium cache (5-10 mins)
queryClient.setQueryDefaults(['studentFees'], {
  staleTime: 1000 * 60 * 5,
  gcTime: 1000 * 60 * 30,
  refetchOnWindowFocus: false,
  refetchOnReconnect: false,
});
queryClient.setQueryDefaults(['studentResults'], {
  staleTime: 1000 * 60 * 5,
  gcTime: 1000 * 60 * 30,
  refetchOnWindowFocus: false,
  refetchOnReconnect: false,
});
queryClient.setQueryDefaults(['studentTimetable'], {
  staleTime: 1000 * 60 * 10,
  gcTime: 1000 * 60 * 30,
  refetchOnWindowFocus: false,
  refetchOnReconnect: false,
});
queryClient.setQueryDefaults(['teacherTimetable'], {
  staleTime: 1000 * 60 * 10,
  gcTime: 1000 * 60 * 30,
  refetchOnWindowFocus: false,
  refetchOnReconnect: false,
});

// 3. Volatile / Real-time: notifications and today's attendance (30s-1 min)
queryClient.setQueryDefaults(['notifications'], {
  staleTime: 1000 * 30,
  gcTime: 1000 * 60 * 5,
  refetchOnWindowFocus: true,
  refetchOnReconnect: true,
});
queryClient.setQueryDefaults(['studentAttendance'], {
  staleTime: 1000 * 60,
  gcTime: 1000 * 60 * 10,
  refetchOnWindowFocus: true,
  refetchOnReconnect: true,
});
queryClient.setQueryDefaults(['teacherSessions'], {
  staleTime: 1000 * 60,
  gcTime: 1000 * 60 * 10,
  refetchOnWindowFocus: true,
  refetchOnReconnect: true,
});

const container = document.getElementById('root') || document.getElementById('app');

if (container) {
  ReactDOM.createRoot(container).render(
    <React.StrictMode>
      <QueryClientProvider client={queryClient}>
        <AuthProvider>
          <App />
        </AuthProvider>
      </QueryClientProvider>
    </React.StrictMode>
  );
}
