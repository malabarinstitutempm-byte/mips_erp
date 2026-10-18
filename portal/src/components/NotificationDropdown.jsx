import React, { useState, useEffect } from 'react';
import { supabase } from '../supabaseClient';
import { useAuth } from '../context/AuthContext';
import { Bell, CheckCheck, Clock, ExternalLink, ShieldAlert, Sparkles, X } from 'lucide-react';

export default function NotificationDropdown({ isOpen, onClose }) {
  const { user, refreshUnread } = useAuth();
  const [notifications, setNotifications] = useState([]);
  const [loading, setLoading] = useState(false);
  const [pushStatus, setPushStatus] = useState('default'); // 'default' | 'granted' | 'denied'

  const fetchNotifications = async () => {
    if (!user?.id) return;
    setLoading(true);
    try {
      const { data, error } = await supabase
        .from('notifications')
        .select('*')
        .eq('user_id', user.id)
        .order('created_at', { ascending: false })
        .limit(20);

      if (!error && data) {
        setNotifications(data);
      }
    } catch (err) {
      console.error('Error fetching notifications:', err);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    if (isOpen) {
      fetchNotifications();
    }
  }, [isOpen, user?.id]);

  useEffect(() => {
    if ('Notification' in window) {
      setPushStatus(Notification.permission);
    }
  }, []);

  const markAsRead = async (id) => {
    try {
      await supabase
        .from('notifications')
        .update({ read_at: new Date().toISOString() })
        .eq('id', id);

      setNotifications((prev) =>
        prev.map((n) => (n.id === id ? { ...n, read_at: new Date().toISOString() } : n))
      );
      refreshUnread();
    } catch (_) {}
  };

  const markAllAsRead = async () => {
    if (!user?.id) return;
    try {
      await supabase
        .from('notifications')
        .update({ read_at: new Date().toISOString() })
        .eq('user_id', user.id)
        .is('read_at', null);

      setNotifications((prev) =>
        prev.map((n) => ({ ...n, read_at: n.read_at || new Date().toISOString() }))
      );
      refreshUnread();
    } catch (_) {}
  };

  const requestPushPermission = async () => {
    if (!('Notification' in window)) return;
    try {
      const permission = await Notification.requestPermission();
      setPushStatus(permission);
      if (permission === 'granted' && user?.id) {
        // Register push subscription record
        await supabase.from('push_subscriptions').upsert({
          user_id: user.id,
          endpoint: 'web-browser-' + navigator.userAgent.substring(0, 50),
          keys: { browser: navigator.userAgent, registered_at: new Date().toISOString() },
        });
      }
    } catch (err) {
      console.error('Push permission error:', err);
    }
  };

  if (!isOpen) return null;

  return (
    <div className="fixed inset-y-0 right-0 z-50 w-full max-w-sm bg-white shadow-2xl border-l border-[#E1E8F2] flex flex-col">
      {/* Drawer Header */}
      <div className="p-4 border-b border-[#E1E8F2] flex items-center justify-between bg-slate-50">
        <div className="flex items-center gap-2">
          <Bell className="w-5 h-5 text-[#1F5FBF]" />
          <h3 className="font-sora font-bold text-[#0B2A4A] text-base">Notifications</h3>
        </div>
        <div className="flex items-center gap-2">
          <button
            type="button"
            onClick={markAllAsRead}
            className="text-xs font-semibold text-[#1F5FBF] hover:underline flex items-center gap-1"
            title="Mark all as read"
          >
            <CheckCheck className="w-3.5 h-3.5" />
            Mark all read
          </button>
          <button
            type="button"
            onClick={onClose}
            className="p-1.5 text-slate-400 hover:text-slate-600 rounded-lg hover:bg-slate-200"
          >
            <X className="w-4 h-4" />
          </button>
        </div>
      </div>

      {/* Push Notifications Enable Banner */}
      {pushStatus !== 'granted' && 'Notification' in window && (
        <div className="p-3 bg-blue-50 border-b border-blue-100 flex items-center justify-between">
          <div className="flex items-center gap-2">
            <Sparkles className="w-4 h-4 text-[#1F5FBF]" />
            <span className="text-xs text-blue-900 font-medium">Enable browser alerts?</span>
          </div>
          <button
            type="button"
            onClick={requestPushPermission}
            className="px-2.5 py-1 text-xs font-bold text-white bg-[#1F5FBF] hover:bg-[#174EA0] rounded-md shadow-sm"
          >
            Enable
          </button>
        </div>
      )}

      {/* Notification List */}
      <div className="flex-1 overflow-y-auto divide-y divide-slate-100">
        {loading ? (
          <div className="p-8 text-center text-sm text-[#5B6B7F]">Loading notifications...</div>
        ) : notifications.length === 0 ? (
          <div className="p-8 text-center flex flex-col items-center justify-center">
            <Bell className="w-10 h-10 text-slate-300 mb-2" />
            <p className="text-sm font-semibold text-[#0B2A4A]">No notifications yet</p>
            <p className="text-xs text-[#5B6B7F] mt-1">
              You'll be notified here when exam results, fee receipts, or attendance notices are posted.
            </p>
          </div>
        ) : (
          notifications.map((n) => {
            const isUnread = !n.read_at;
            return (
              <div
                key={n.id}
                onClick={() => isUnread && markAsRead(n.id)}
                className={`p-4 transition-colors cursor-pointer ${
                  isUnread ? 'bg-blue-50/50 hover:bg-blue-50' : 'hover:bg-slate-50'
                }`}
              >
                <div className="flex items-start justify-between gap-2">
                  <div className="flex items-start gap-2">
                    {isUnread && (
                      <span className="w-2 h-2 rounded-full bg-[#1F5FBF] mt-1.5 shrink-0" />
                    )}
                    <div>
                      <h4 className="text-xs font-bold text-[#0B2A4A]">{n.title}</h4>
                      <p className="text-xs text-[#5B6B7F] mt-0.5">{n.body}</p>
                    </div>
                  </div>
                </div>
                <div className="flex items-center justify-between mt-2 pl-4">
                  <span className="text-[10px] text-slate-400 flex items-center gap-1">
                    <Clock className="w-3 h-3" />
                    {new Date(n.created_at).toLocaleDateString('en-GB', {
                      day: '2-digit',
                      month: 'short',
                      hour: '2-digit',
                      minute: '2-digit',
                    })}
                  </span>
                  {n.link && (
                    <a
                      href={n.link}
                      target="_blank"
                      rel="noopener noreferrer"
                      className="text-[11px] text-[#1F5FBF] hover:underline flex items-center gap-0.5"
                    >
                      View <ExternalLink className="w-3 h-3" />
                    </a>
                  )}
                </div>
              </div>
            );
          })
        )}
      </div>
    </div>
  );
}
