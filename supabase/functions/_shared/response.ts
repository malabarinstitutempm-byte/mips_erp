// supabase/functions/_shared/response.ts
// Standardized JSON HTTP Response Helpers

import { getCorsHeaders } from './cors.ts';

export function jsonResponse(
  data: Record<string, unknown>,
  status = 200,
  req?: Request
): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      ...getCorsHeaders(req),
      'Content-Type': 'application/json',
    },
  });
}

/**
 * Strips PII, passwords, tokens, emails, and phone numbers from logs
 */
export function sanitizeLogData(input: unknown): string {
  if (!input) return '';
  const str = typeof input === 'string' ? input : JSON.stringify(input);
  return str
    .replace(/Bearer\s+[a-zA-Z0-9._-]+/gi, 'Bearer [REDACTED]')
    .replace(/(password|temp_password|secret|service_role_key)["':\s]+([^"',}\s]+)/gi, '$1: "[REDACTED]"')
    .replace(/[a-zA-Z0-9_.+-]+@[a-zA-Z0-9-]+\.[a-zA-Z0-9-.]+/gi, '[EMAIL_REDACTED]')
    .replace(/(?:\+91|0)?[6-9]\d{9}/g, '[PHONE_REDACTED]');
}

export function errorResponse(
  message: string,
  status = 400,
  details?: unknown,
  req?: Request
): Response {
  if (status >= 500) {
    console.error(`[SERVER_ERROR ${status}]:`, sanitizeLogData(message), details ? sanitizeLogData(details) : '');
  }

  return new Response(
    JSON.stringify({
      success: false,
      error: message,
      ...(details ? { details } : {}),
    }),
    {
      status,
      headers: {
        ...getCorsHeaders(req),
        'Content-Type': 'application/json',
      },
    }
  );
}

