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

// Granular caching rules with focus refetch safety net
queryClient.setQueryDefaults(['studentProfile'], {
  staleTime: 1000 * 30, // 30 seconds
  gcTime: 1000 * 60 * 15,
  refetchOnWindowFocus: true,
  refetchOnReconnect: true,
});
queryClient.setQueryDefaults(['teacherProfile'], {
  staleTime: 1000 * 30,
  gcTime: 1000 * 60 * 15,
  refetchOnWindowFocus: true,
  refetchOnReconnect: true,
});
queryClient.setQueryDefaults(['courses'], {
  staleTime: 1000 * 30,
  gcTime: 1000 * 60 * 15,
  refetchOnWindowFocus: true,
  refetchOnReconnect: true,
});
queryClient.setQueryDefaults(['batches'], {
  staleTime: 1000 * 30,
  gcTime: 1000 * 60 * 15,
  refetchOnWindowFocus: true,
  refetchOnReconnect: true,
});
queryClient.setQueryDefaults(['teacherBatches'], {
  staleTime: 1000 * 30,
  gcTime: 1000 * 60 * 15,
  refetchOnWindowFocus: true,
  refetchOnReconnect: true,
});
queryClient.setQueryDefaults(['settings'], {
  staleTime: 1000 * 60 * 5,
  gcTime: 1000 * 60 * 30,
  refetchOnWindowFocus: true,
  refetchOnReconnect: true,
});

// 2. Results and Fees: medium cache
queryClient.setQueryDefaults(['studentFees'], {
  staleTime: 1000 * 30,
  gcTime: 1000 * 60 * 15,
  refetchOnWindowFocus: true,
  refetchOnReconnect: true,
});
queryClient.setQueryDefaults(['studentResults'], {
  staleTime: 1000 * 30,
  gcTime: 1000 * 60 * 15,
  refetchOnWindowFocus: true,
  refetchOnReconnect: true,
});
queryClient.setQueryDefaults(['studentTimetable'], {
  staleTime: 1000 * 60,
  gcTime: 1000 * 60 * 15,
  refetchOnWindowFocus: true,
  refetchOnReconnect: true,
});
queryClient.setQueryDefaults(['teacherTimetable'], {
  staleTime: 1000 * 60,
  gcTime: 1000 * 60 * 15,
  refetchOnWindowFocus: true,
  refetchOnReconnect: true,
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
