// portal/src/lib/perfLogger.ts
// Development-only Supabase Request Performance Instrumentation

export interface PerfLogEntry {
  id: string;
  timestamp: string;
  screen: string;
  action: string;
  method: string;
  target: string;
  tableOrRpc: string;
  columns: string | null;
  queryParams: Record<string, string>;
  requestBytes: number;
  responseBytes: number;
  rowCount: number;
  durationMs: number;
  status: number;
}

export interface ScreenBudget {
  screen: string;
  maxRequests: number;
  maxPayloadBytes: number;
}

class PerfLogger {
  private currentScreen = 'AppInit';
  private currentAction = 'InitialLoad';
  private logs: PerfLogEntry[] = [];
  private enabled: boolean = true;

  constructor() {
    if (typeof window !== 'undefined') {
      (window as any).__MIPS_PERF__ = this;
    }
  }

  public setScreen(screen: string, action: string = 'ScreenLoad') {
    this.currentScreen = screen;
    this.currentAction = action;
  }

  public setAction(action: string) {
    this.currentAction = action;
  }

  public getScreen(): string {
    return this.currentScreen;
  }

  public getAction(): string {
    return this.currentAction;
  }

  public getLogs(): PerfLogEntry[] {
    return [...this.logs];
  }

  public clearLogs() {
    this.logs = [];
  }

  public getLogsForScreen(screen: string): PerfLogEntry[] {
    return this.logs.filter((l) => l.screen === screen);
  }

  public recordLog(entry: PerfLogEntry) {
    this.logs.push(entry);

    // Development Console Logging
    if (import.meta.env.DEV) {
      const sizeKb = (entry.responseBytes / 1024).toFixed(2);
      const cols = entry.columns ? ` [cols: ${entry.columns}]` : '';
      console.log(
        `%c[PERF]%c [${entry.screen}] ${entry.method} ${entry.tableOrRpc} -> ${entry.rowCount} rows, ${sizeKb} KB, ${entry.durationMs.toFixed(1)}ms${cols}`,
        'color: #0ea5e9; font-weight: bold;',
        'color: #64748b;'
      );
    }
  }

  public getSummaryByScreen(): Record<
    string,
    {
      requestCount: number;
      totalPayloadBytes: number;
      totalDurationMs: number;
      endpoints: Record<string, number>;
    }
  > {
    const summary: Record<
      string,
      {
        requestCount: number;
        totalPayloadBytes: number;
        totalDurationMs: number;
        endpoints: Record<string, number>;
      }
    > = {};

    for (const log of this.logs) {
      if (!summary[log.screen]) {
        summary[log.screen] = {
          requestCount: 0,
          totalPayloadBytes: 0,
          totalDurationMs: 0,
          endpoints: {},
        };
      }
      const s = summary[log.screen];
      s.requestCount++;
      s.totalPayloadBytes += log.responseBytes;
      s.totalDurationMs += log.durationMs;
      s.endpoints[log.tableOrRpc] = (s.endpoints[log.tableOrRpc] || 0) + 1;
    }

    return summary;
  }
}

export const perfLogger = new PerfLogger();

/**
 * Creates an instrumented fetch wrapper for Supabase Client
 */
export function createInstrumentedFetch(baseFetch: typeof fetch = fetch): typeof fetch {
  return async (input: RequestInfo | URL, init?: RequestInit): Promise<Response> => {
    const startTime = performance.now();
    const urlStr = typeof input === 'string' ? input : input instanceof URL ? input.toString() : input.url;
    const method = init?.method || (typeof input === 'object' && 'method' in input ? input.method : 'GET');

    let requestBytes = 0;
    if (init?.body) {
      if (typeof init.body === 'string') {
        requestBytes = new TextEncoder().encode(init.body).length;
      } else if (init.body instanceof Blob) {
        requestBytes = init.body.size;
      }
    }

    let response: Response;
    try {
      response = await baseFetch(input, init);
    } catch (err) {
      const durationMs = performance.now() - startTime;
      perfLogger.recordLog({
        id: crypto.randomUUID(),
        timestamp: new Date().toISOString(),
        screen: perfLogger.getScreen(),
        action: perfLogger.getAction(),
        method,
        target: urlStr,
        tableOrRpc: parseEndpointName(urlStr),
        columns: parseColumns(urlStr),
        queryParams: parseQueryParams(urlStr),
        requestBytes,
        responseBytes: 0,
        rowCount: 0,
        durationMs,
        status: 0,
      });
      throw err;
    }

    const durationMs = performance.now() - startTime;

    // Clone response to inspect body without consuming the original stream
    const clone = response.clone();
    let responseBytes = 0;
    let rowCount = 0;

    try {
      const text = await clone.text();
      responseBytes = new TextEncoder().encode(text).length;
      if (text.trim().startsWith('{') || text.trim().startsWith('[')) {
        const json = JSON.parse(text);
        if (Array.isArray(json)) {
          rowCount = json.length;
        } else if (json && typeof json === 'object') {
          rowCount = 1;
        }
      }
    } catch (_) {
      // Content-Length header fallback
      const cl = response.headers.get('content-length');
      if (cl) responseBytes = parseInt(cl, 10);
    }

    perfLogger.recordLog({
      id: crypto.randomUUID(),
      timestamp: new Date().toISOString(),
      screen: perfLogger.getScreen(),
      action: perfLogger.getAction(),
      method,
      target: urlStr,
      tableOrRpc: parseEndpointName(urlStr),
      columns: parseColumns(urlStr),
      queryParams: parseQueryParams(urlStr),
      requestBytes,
      responseBytes,
      rowCount,
      durationMs,
      status: response.status,
    });

    return response;
  };
}

function parseEndpointName(urlStr: string): string {
  try {
    const url = new URL(urlStr);
    const path = url.pathname;
    if (path.includes('/rest/v1/rpc/')) {
      return `rpc:${path.split('/rest/v1/rpc/')[1].split('/')[0]}`;
    }
    if (path.includes('/rest/v1/')) {
      return `table:${path.split('/rest/v1/')[1].split('/')[0]}`;
    }
    if (path.includes('/auth/v1/')) {
      return `auth:${path.split('/auth/v1/')[1].split('/')[0]}`;
    }
    if (path.includes('/functions/v1/')) {
      return `edge:${path.split('/functions/v1/')[1].split('/')[0]}`;
    }
    return path;
  } catch (_) {
    return urlStr;
  }
}

function parseColumns(urlStr: string): string | null {
  try {
    const url = new URL(urlStr);
    return url.searchParams.get('select');
  } catch (_) {
    return null;
  }
}

function parseQueryParams(urlStr: string): Record<string, string> {
  const result: Record<string, string> = {};
  try {
    const url = new URL(urlStr);
    url.searchParams.forEach((val, key) => {
      result[key] = val;
    });
  } catch (_) {}
  return result;
}
