import React from 'react';
import { useAuth } from '../context/AuthContext';
import { Bell, LogOut, GraduationCap, UserCheck, ShieldCheck } from 'lucide-react';

export default function Navbar({ onToggleNotifications, notificationsOpen }) {
  const { user, profile, role, unreadNotifications, logout } = useAuth();

  const getRoleBadge = () => {
    switch (role) {
      case 'teacher':
        return (
          <span className="inline-flex items-center gap-1 px-2.5 py-1 rounded-full text-xs font-semibold bg-emerald-50 text-emerald-700 border border-emerald-200">
            <UserCheck className="w-3.5 h-3.5" />
            Faculty / Teacher
          </span>
        );
      case 'student':
        return (
          <span className="inline-flex items-center gap-1 px-2.5 py-1 rounded-full text-xs font-semibold bg-blue-50 text-blue-700 border border-blue-200">
            <GraduationCap className="w-3.5 h-3.5" />
            Student Portal
          </span>
        );
      case 'admin':
        return (
          <span className="inline-flex items-center gap-1 px-2.5 py-1 rounded-full text-xs font-semibold bg-amber-50 text-amber-700 border border-amber-200">
            <ShieldCheck className="w-3.5 h-3.5" />
            Administrator
          </span>
        );
      default:
        return null;
    }
  };

  return (
    <header className="sticky top-0 z-40 bg-white border-b border-[#E1E8F2] shadow-sm">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 h-16 flex items-center justify-between">
        {/* Brand & Logo */}
        <div className="flex items-center gap-3">
          <div className="w-10 h-10 rounded-xl bg-[#0B2A4A] flex items-center justify-center text-white font-bold text-lg shadow-sm">
            M
          </div>
          <div>
            <div className="flex items-center gap-2">
              <span className="font-sora font-bold text-[#0B2A4A] text-base sm:text-lg tracking-tight">
                MIPS ERP
              </span>
              {getRoleBadge()}
            </div>
            <p className="text-xs text-[#5B6B7F] hidden sm:block">
              Malabar Institute of Paramedical Science
            </p>
          </div>
        </div>

        {/* User Actions */}
        <div className="flex items-center gap-3">
          {/* Notifications Button */}
          <button
            type="button"
            onClick={onToggleNotifications}
            className={`relative p-2 rounded-xl transition-colors border ${
              notificationsOpen
                ? 'bg-[#EBF2FC] text-[#1F5FBF] border-[#BBD3F5]'
                : 'text-[#5B6B7F] hover:bg-slate-50 border-transparent hover:border-[#E1E8F2]'
            }`}
            title="Notifications"
          >
            <Bell className="w-5 h-5" />
            {unreadNotifications > 0 && (
              <span className="absolute -top-1 -right-1 flex h-5 w-5 items-center justify-center rounded-full bg-red-600 text-[10px] font-bold text-white shadow-sm animate-pulse">
                {unreadNotifications > 9 ? '9+' : unreadNotifications}
              </span>
            )}
          </button>

          {/* User Profile Info */}
          <div className="hidden md:flex flex-col text-right">
            <span className="text-xs font-bold text-[#0B2A4A] truncate max-w-[180px]">
              {user?.email?.split('@')[0]}
            </span>
            <span className="text-[11px] text-[#5B6B7F]">
              {profile?.is_active ? 'Active Session' : 'Account'}
            </span>
          </div>

          {/* Logout Button */}
          <button
            type="button"
            onClick={logout}
            className="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-xl text-xs font-semibold text-red-600 hover:text-red-700 hover:bg-red-50 border border-transparent hover:border-red-200 transition-colors"
            title="Sign Out"
          >
            <LogOut className="w-4 h-4" />
            <span className="hidden sm:inline">Sign Out</span>
          </button>
        </div>
      </div>
    </header>
  );
}
