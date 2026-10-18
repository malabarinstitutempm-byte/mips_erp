// src/test/setup.ts
// Test environment polyfills and global mocks for Vitest + jsdom

import '@testing-library/jest-dom';

// Mock window.matchMedia
Object.defineProperty(window, 'matchMedia', {
  writable: true,
  value: (query: string) => ({
    matches: false,
    media: query,
    onchange: null,
    addListener: () => {},
    removeListener: () => {},
    addEventListener: () => {},
    removeEventListener: () => {},
    dispatchEvent: () => false,
  }),
});

// Mock Notification API
class MockNotification {
  static permission: NotificationPermission = 'default';
  static requestPermission = async () => 'granted' as NotificationPermission;
}
(window as any).Notification = MockNotification;

// Mock Web Audio API
class MockAudioContext {
  currentTime = 0;
  destination = {};
  createOscillator() {
    return {
      type: 'sine',
      frequency: { setValueAtTime: () => {}, exponentialRampToValueAtTime: () => {} },
      connect: () => {},
      start: () => {},
      stop: () => {},
    };
  }
  createGain() {
    return {
      gain: { setValueAtTime: () => {}, exponentialRampToValueAtTime: () => {} },
      connect: () => {},
    };
  }
}
(window as any).AudioContext = MockAudioContext;
(window as any).webkitAudioContext = MockAudioContext;

// Mock html2pdf.js
vi.mock('html2pdf.js', () => ({
  default: () => ({
    set: function () {
      return this;
    },
    from: function () {
      return this;
    },
    save: async function () {
      return true;
    },
  }),
}));

// Mock WebSocket to prevent Node 22 undici dispatchEvent errors during Vitest runs
class MockWebSocket {
  static readonly CONNECTING = 0;
  static readonly OPEN = 1;
  static readonly CLOSING = 2;
  static readonly CLOSED = 3;
  readyState = MockWebSocket.OPEN;
  onopen: any = null;
  onclose: any = null;
  onmessage: any = null;
  onerror: any = null;
  send() {}
  close() {}
  addEventListener() {}
  removeEventListener() {}
  dispatchEvent() {
    return true;
  }
}
(globalThis as any).WebSocket = MockWebSocket;
(window as any).WebSocket = MockWebSocket;
