// src/components/auth/TurnstileWidget.tsx
// Cloudflare Turnstile explicit widget rendering

import React, { useEffect, useRef } from 'react';

interface TurnstileWidgetProps {
  siteKey: string;
  onVerify: (token: string) => void;
  onExpire?: () => void;
  onError?: () => void;
}

declare global {
  interface Window {
    turnstile?: {
      render: (
        container: HTMLElement | string,
        params: {
          sitekey: string;
          callback: (token: string) => void;
          'expired-callback'?: () => void;
          'error-callback'?: () => void;
          theme?: 'light' | 'dark' | 'auto';
        }
      ) => string;
      reset: (widgetId: string) => void;
      remove: (widgetId: string) => void;
    };
  }
}

export const TurnstileWidget: React.FC<TurnstileWidgetProps> = ({
  siteKey,
  onVerify,
  onExpire,
  onError,
}) => {
  const containerRef = useRef<HTMLDivElement>(null);
  const widgetIdRef = useRef<string | null>(null);

  useEffect(() => {
    let interval: NodeJS.Timeout | null = null;

    function mountTurnstile() {
      if (!window.turnstile || !containerRef.current) return false;

      try {
        if (widgetIdRef.current) {
          window.turnstile.remove(widgetIdRef.current);
        }

        widgetIdRef.current = window.turnstile.render(containerRef.current, {
          sitekey: siteKey,
          callback: (token: string) => {
            onVerify(token);
          },
          'expired-callback': () => {
            onExpire?.();
          },
          'error-callback': () => {
            onError?.();
          },
          theme: 'light',
        });
        return true;
      } catch (e) {
        console.error('Turnstile mount error:', e);
        return false;
      }
    }

    if (!mountTurnstile()) {
      interval = setInterval(() => {
        if (mountTurnstile() && interval) {
          clearInterval(interval);
        }
      }, 300);
    }

    return () => {
      if (interval) clearInterval(interval);
      if (widgetIdRef.current && window.turnstile) {
        try {
          window.turnstile.remove(widgetIdRef.current);
        } catch {
          // ignore
        }
      }
    };
  }, [siteKey, onVerify, onExpire, onError]);

  return (
    <div className="flex justify-center my-3" aria-live="polite">
      <div ref={containerRef} className="min-h-[65px]" />
    </div>
  );
};
