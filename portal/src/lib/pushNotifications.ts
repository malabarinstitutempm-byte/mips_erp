// src/lib/pushNotifications.ts
// Web Push Notifications Registration, VAPID Handling & Graceful Degradation

import { supabase } from './supabase';

// Helper to convert VAPID public key from URL-safe Base64 to Uint8Array
function urlBase64ToUint8Array(base64String: string): Uint8Array {
  const padding = '='.repeat((4 - (base64String.length % 4)) % 4);
  const base64 = (base64String + padding).replace(/-/g, '+').replace(/_/g, '/');
  const rawData = window.atob(base64);
  const outputArray = new Uint8Array(rawData.length);
  for (let i = 0; i < rawData.length; ++i) {
    outputArray[i] = rawData.charCodeAt(i);
  }
  return outputArray;
}

export interface PushStatus {
  isSupported: boolean;
  permission: NotificationPermission;
  isSubscribed: boolean;
}

export const pushNotificationService = {
  // Check if push notifications are supported on this device/browser
  isPushSupported(): boolean {
    return (
      typeof window !== 'undefined' &&
      'serviceWorker' in navigator &&
      'PushManager' in window &&
      'Notification' in window
    );
  },

  // Get current status
  async getStatus(): Promise<PushStatus> {
    if (!this.isPushSupported()) {
      return {
        isSupported: false,
        permission: 'denied',
        isSubscribed: false,
      };
    }

    try {
      const permission = Notification.permission;
      const registration = await navigator.serviceWorker.ready;
      const subscription = await registration.pushManager.getSubscription();

      return {
        isSupported: true,
        permission,
        isSubscribed: Boolean(subscription),
      };
    } catch {
      return {
        isSupported: false,
        permission: 'denied',
        isSubscribed: false,
      };
    }
  },

  // Subscribe to Web Push and save to Supabase push_subscriptions table
  async subscribeUser(userId: string): Promise<{ success: boolean; error?: string }> {
    if (!this.isPushSupported()) {
      return { success: false, error: 'Push notifications are not supported on this browser.' };
    }

    try {
      // 1. Request permission
      const permission = await Notification.requestPermission();
      if (permission !== 'granted') {
        return {
          success: false,
          error: 'Push notification permission was denied. You can re-enable it in browser site settings.',
        };
      }

      // 2. Get VAPID public key
      const vapidKey = import.meta.env.VITE_VAPID_PUBLIC_KEY;
      const registration = await navigator.serviceWorker.ready;

      let subscription: PushSubscription;
      if (vapidKey) {
        subscription = await registration.pushManager.subscribe({
          userVisibleOnly: true,
          applicationServerKey: urlBase64ToUint8Array(vapidKey),
        });
      } else {
        // Fallback for development if VAPID key is not set
        subscription = await registration.pushManager.subscribe({
          userVisibleOnly: true,
        });
      }

      // 3. Extract keys
      const subJson = subscription.toJSON();
      const p256dh = subJson.keys?.p256dh || '';
      const auth = subJson.keys?.auth || '';

      if (!p256dh || !auth) {
        return { success: false, error: 'Failed to extract cryptographic subscription keys.' };
      }

      // 4. Save to Supabase push_subscriptions
      const { error: dbError } = await supabase.from('push_subscriptions').upsert(
        {
          user_id: userId,
          endpoint: subscription.endpoint,
          p256dh,
          auth,
          created_at: new Date().toISOString(),
        },
        { onConflict: 'endpoint' }
      );

      if (dbError) {
        console.warn('Failed to persist push subscription to database:', dbError);
        // Do not throw; the user still granted permission
      }

      return { success: true };
    } catch (err: any) {
      console.warn('Push subscription failed gracefully:', err);
      return {
        success: false,
        error: err.message || 'Failed to complete push subscription.',
      };
    }
  },

  // Unsubscribe
  async unsubscribeUser(): Promise<boolean> {
    if (!this.isPushSupported()) return false;
    try {
      const registration = await navigator.serviceWorker.ready;
      const subscription = await registration.pushManager.getSubscription();
      if (subscription) {
        await supabase
          .from('push_subscriptions')
          .delete()
          .eq('endpoint', subscription.endpoint);
        await subscription.unsubscribe();
        return true;
      }
      return false;
    } catch {
      return false;
    }
  },
};
