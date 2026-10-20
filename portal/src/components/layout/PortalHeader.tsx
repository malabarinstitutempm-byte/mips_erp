// src/components/layout/PortalHeader.tsx
// Unified Navy Header with ECG Accent, User Info, Notifications, and Tab Bar

import React from 'react';
import { useAuth } from '../../context/AuthContext';
import { EcgLine } from '../common/EcgLine';
import { Bell, LogOut, User } from 'lucide-react';

export interface TabItem {
  id: string;
  label: string;
  icon?: React.ReactNode;
}

interface PortalHeaderProps {
  tabs: TabItem[];
  activeTab: string;
  onTabChange: (tabId: string) => void;
  onOpenNotifications?: () => void;
  subtitle?: string;
}

export const PortalHeader: React.FC<PortalHeaderProps> = ({
  tabs,
  activeTab,
  onTabChange,
  onOpenNotifications,
  subtitle,
}) => {
  const { user, profile, unreadCount, logout } = useAuth();
  const tabNavRef = React.useRef<HTMLElement>(null);
  const activeTabRef = React.useRef<HTMLButtonElement>(null);

  React.useEffect(() => {
    if (activeTabRef.current && tabNavRef.current) {
      activeTabRef.current.scrollIntoView({
        behavior: 'smooth',
        block: 'nearest',
        inline: 'center',
      });
    }
  }, [activeTab]);

  const displayName = profile?.role === 'teacher'
    ? 'Teacher Portal'
    : 'Student Portal';

  const [showLogoutConfirm, setShowLogoutConfirm] = React.useState(false);

  return (
    <header className="bg-navy pt-[max(1rem,env(safe-area-inset-top))] pb-6 px-4 sm:px-6 relative text-white">
      {/* Top Bar: Brand Logo & User Info */}
      <div className="max-w-[1040px] mx-auto flex items-center justify-between pb-3 relative z-10">
        <div className="flex items-center gap-2.5 min-w-0 flex-1 mr-2">
          <img
            src="/logo.png"
            alt="MIPS Logo"
            className="w-9 h-9 sm:w-10 sm:h-10 shrink-0 object-contain rounded-xl bg-white/10 p-1"
            onError={(e) => {
              e.currentTarget.style.display = 'none';
            }}
          />
          <div className="min-w-0 flex-1">
            <div className="flex items-center gap-1.5 flex-wrap">
              <h1 className="font-sora font-bold text-sm sm:text-lg tracking-tight leading-tight truncate">
                MIPS {displayName}
              </h1>
              {subtitle && (
                <span className="px-2 py-0.5 rounded-full text-[10px] sm:text-xs font-semibold bg-white/15 text-teal border border-teal/30 shrink-0">
                  {subtitle}
                </span>
              )}
            </div>
            <p className="text-[11px] sm:text-xs text-navy-text truncate">
              {user?.email || profile?.role?.toUpperCase()}
            </p>
          </div>
        </div>

        {/* Action Controls */}
        <div className="flex items-center gap-2 shrink-0">
          {/* Notification Bell with Badge */}
          <button
            type="button"
            onClick={onOpenNotifications}
            className="relative p-2.5 rounded-xl bg-white/10 hover:bg-white/20 text-white transition-colors min-h-touch min-w-touch flex items-center justify-center focus:outline-none focus:ring-2 focus:ring-focusRing"
            aria-label={`Notifications, ${unreadCount} unread`}
          >
            <Bell className="w-5 h-5" />
            {unreadCount > 0 && (
              <span className="absolute -top-1 -right-1 min-w-[20px] h-5 px-1 bg-error-accent text-white font-sora font-bold text-[10px] rounded-full flex items-center justify-center border-2 border-navy animate-pulse">
                {unreadCount > 99 ? '99+' : unreadCount}
              </span>
            )}
          </button>

          {/* Clearly visible Log Out Button with >= 44x44 touch target */}
          <button
            type="button"
            onClick={() => setShowLogoutConfirm(true)}
            className="px-3 py-2 rounded-xl bg-white/10 hover:bg-red-500/25 text-white transition-all min-h-touch min-w-touch flex items-center gap-1.5 text-xs font-sora font-semibold focus:outline-none focus:ring-2 focus:ring-focusRing border border-white/10 cursor-pointer"
            aria-label="Log Out"
            title="Log Out"
          >
            <LogOut className="w-4 h-4 text-red-300" />
            <span className="hidden sm:inline">Log Out</span>
          </button>
        </div>
      </div>

      {/* Confirmation Modal */}
      {showLogoutConfirm && (
        <div className="fixed inset-0 z-50 bg-black/60 backdrop-blur-sm flex items-center justify-center p-4">
          <div className="bg-white rounded-card-lg max-w-sm w-full p-6 text-navy shadow-2xl border border-cardBorder animate-in fade-in zoom-in-95 duration-150">
            <div className="flex items-center gap-3 text-red-600 mb-3">
              <div className="p-2.5 rounded-full bg-red-100 shrink-0">
                <LogOut className="w-5 h-5 text-red-600" />
              </div>
              <h3 className="font-sora font-bold text-base">Confirm Sign Out</h3>
            </div>
            <p className="text-xs text-muted leading-relaxed mb-6">
              Are you sure you want to sign out of the portal? Your session will end, push notifications will be unregistered, and cached state will be cleared.
            </p>
            <div className="flex items-center justify-end gap-3">
              <button
                type="button"
                onClick={() => setShowLogoutConfirm(false)}
                className="px-4 py-2.5 rounded-btn text-xs font-semibold text-muted hover:bg-slate-100 transition-colors min-h-touch"
              >
                Cancel
              </button>
              <button
                type="button"
                onClick={async () => {
                  setShowLogoutConfirm(false);
                  await logout();
                  window.location.replace('/login');
                }}
                className="px-4 py-2.5 rounded-btn text-xs font-semibold text-white bg-red-600 hover:bg-red-700 shadow-md transition-colors min-h-touch flex items-center gap-1.5 cursor-pointer"
              >
                <LogOut className="w-3.5 h-3.5" />
                <span>Sign Out</span>
              </button>
            </div>
          </div>
        </div>
      )}

      {/* ECG Heartbeat Divider Line */}
      <div className="max-w-[1040px] mx-auto my-1">
        <EcgLine />
      </div>

      {/* Horizontally Scrollable Tab Bar with Snap & Active-Tab Auto-Scroll */}
      <div className="max-w-[1040px] mx-auto mt-2">
        <nav
          ref={tabNavRef}
          className="flex gap-2 overflow-x-auto no-scrollbar py-1 scroll-smooth snap-x snap-mandatory"
          role="tablist"
          aria-label="Portal Navigation Tabs"
        >
          {tabs.map((tab) => {
            const isActive = tab.id === activeTab;
            return (
              <button
                key={tab.id}
                ref={isActive ? activeTabRef : null}
                role="tab"
                aria-selected={isActive}
                onClick={() => onTabChange(tab.id)}
                className={`snap-start shrink-0 flex items-center gap-2 px-3.5 sm:px-4 py-2.5 rounded-btn font-sora font-semibold text-xs sm:text-sm whitespace-nowrap transition-all min-h-touch ${
                  isActive
                    ? 'bg-teal text-navy shadow-md font-bold ring-2 ring-teal/30'
                    : 'bg-white/10 text-white hover:bg-white/20'
                }`}
              >
                {tab.icon}
                <span>{tab.label}</span>
              </button>
            );
          })}
        </nav>
      </div>
    </header>
  );
};
