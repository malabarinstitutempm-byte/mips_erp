// src/App.tsx
// Main Application Routing, Guards, Offline Handling, PWA Updates & Lazy Route Splitting

import React, { Suspense } from 'react';
import { BrowserRouter, Routes, Route, Navigate, useNavigate } from 'react-router-dom';
import { useAuth } from './context/AuthContext';
import { OnlineStatusProvider } from './context/OnlineStatusContext';
import { OfflineBanner } from './components/common/OfflineBanner';
import { PwaUpdatePrompt } from './components/common/PwaUpdatePrompt';
import { AlertCircle, X } from 'lucide-react';
// Lazy-load route bundles and auth screens to keep initial client payload under 150 KB gzipped
const StudentArea = React.lazy(() =>
  import('./components/student/StudentArea').then((m) => ({ default: m.StudentArea }))
);
const TeacherArea = React.lazy(() =>
  import('./components/teacher/TeacherArea').then((m) => ({ default: m.TeacherArea }))
);
const LoginScreen = React.lazy(() =>
  import('./components/auth/LoginScreen').then((m) => ({ default: m.LoginScreen }))
);
const ForcePasswordChange = React.lazy(() =>
  import('./components/auth/ForcePasswordChange').then((m) => ({ default: m.ForcePasswordChange }))
);
const AdminNotice = React.lazy(() =>
  import('./components/auth/AdminNotice').then((m) => ({ default: m.AdminNotice }))
);
const PushPromptModal = React.lazy(() =>
  import('./components/notifications/PushPromptModal').then((m) => ({ default: m.PushPromptModal }))
);

function AppLoadingSpinner({ label = 'Connecting to MIPS Portal...' }: { label?: string }) {
  return (
    <div className="min-h-screen bg-pageBg flex items-center justify-center p-4">
      <div className="flex flex-col items-center gap-3">
        <div className="w-10 h-10 border-4 border-primary border-t-transparent rounded-full animate-spin" />
        <p className="font-sora text-sm font-semibold text-navy">{label}</p>
      </div>
    </div>
  );
}

function ProtectedRoute({
  allowedRole,
  children,
}: {
  allowedRole: 'student' | 'teacher';
  children: React.ReactNode;
}) {
  const { user, loading } = useAuth();

  if (loading) {
    return <AppLoadingSpinner />;
  }

  if (!user) {
    return <Navigate to="/login" replace />;
  }

  // Intercept if password must be changed
  if (user.must_change_password || user.first_login_required) {
    return (
      <Suspense fallback={<AppLoadingSpinner />}>
        <ForcePasswordChange onSuccess={() => {}} />
      </Suspense>
    );
  }

  // If administrator
  if (user.role === 'admin') {
    return (
      <Suspense fallback={<AppLoadingSpinner />}>
        <AdminNotice />
      </Suspense>
    );
  }

  // Guard against cross-role navigation
  if (user.role !== allowedRole) {
    return <Navigate to={user.role === 'teacher' ? '/teacher' : '/student'} replace />;
  }

  return <>{children}</>;
}

export function AppRoutes() {
  const {
    user,
    loading,
    inactivityWarning,
    clearInactivityWarning,
    isPushModalOpen,
    setIsPushModalOpen,
  } = useAuth();

  if (loading) {
    return <AppLoadingSpinner />;
  }

  return (
    <div className="relative min-h-screen bg-pageBg flex flex-col">
      {/* Offline Status Alert Banner */}
      <OfflineBanner />

      {/* PWA Service Worker Update Prompt */}
      <PwaUpdatePrompt />

      {/* Opt-in Push Notification Prompt Modal */}
      {user && (
        <Suspense fallback={null}>
          <PushPromptModal
            userId={user.id}
            isOpen={isPushModalOpen}
            onClose={() => setIsPushModalOpen(false)}
          />
        </Suspense>
      )}

      {/* 5-Day Inactivity Warning Notification */}
      {inactivityWarning && (
        <div
          className="fixed top-4 left-1/2 -translate-x-1/2 z-50 w-[90%] max-w-md bg-warning-bg border border-warning-border text-warning-text p-3.5 rounded-input shadow-lg flex items-center justify-between text-xs animate-slide-down"
          role="alert"
        >
          <div className="flex items-center gap-2">
            <AlertCircle className="w-4 h-4 shrink-0 text-amber-700" />
            <span className="font-medium">You were signed out due to 5 days of inactivity.</span>
          </div>
          <button
            type="button"
            onClick={clearInactivityWarning}
            className="p-1 rounded-lg hover:bg-amber-100 transition-colors"
            aria-label="Dismiss warning"
          >
            <X className="w-4 h-4" />
          </button>
        </div>
      )}

      <Routes>
        <Route
          path="/login"
          element={
            <Suspense fallback={<AppLoadingSpinner />}>
              {user ? (
                user.must_change_password || user.first_login_required ? (
                  <ForcePasswordChange onSuccess={() => {}} />
                ) : user.role === 'admin' ? (
                  <AdminNotice />
                ) : (
                  <Navigate to={user.role === 'teacher' ? '/teacher' : '/student'} replace />
                )
              ) : (
                <LoginScreen
                  onSuccess={() => {
                    // Will automatically route on state transition
                  }}
                />
              )}
            </Suspense>
          }
        />

        <Route
          path="/admin"
          element={
            <Suspense fallback={<AppLoadingSpinner />}>
              <AdminNotice />
            </Suspense>
          }
        />

        <Route
          path="/student/*"
          element={
            <ProtectedRoute allowedRole="student">
              <Suspense fallback={<AppLoadingSpinner label="Loading Student Portal..." />}>
                <StudentArea />
              </Suspense>
            </ProtectedRoute>
          }
        />

        <Route
          path="/teacher/*"
          element={
            <ProtectedRoute allowedRole="teacher">
              <Suspense fallback={<AppLoadingSpinner label="Loading Faculty Portal..." />}>
                <TeacherArea />
              </Suspense>
            </ProtectedRoute>
          }
        />

        {/* Catch-all route */}
        <Route
          path="*"
          element={
            user ? (
              <Navigate
                to={user.role === 'teacher' ? '/teacher' : user.role === 'admin' ? '/admin' : '/student'}
                replace
              />
            ) : (
              <Navigate to="/login" replace />
            )
          }
        />
      </Routes>
    </div>
  );
}

export default function App() {
  return (
    <OnlineStatusProvider>
      <BrowserRouter>
        <AppRoutes />
      </BrowserRouter>
    </OnlineStatusProvider>
  );
}
