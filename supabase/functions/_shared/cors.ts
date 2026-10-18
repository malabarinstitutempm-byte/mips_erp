// supabase/functions/_shared/cors.ts
// Cross-Origin Resource Sharing (CORS) Configuration with Origin Restriction

import { getEnv } from './env.ts';

export function getCorsHeaders(req?: Request): Record<string, string> {
  const allowedOriginsEnv = getEnv('ALLOWED_ORIGINS');
  const requestOrigin = req?.headers.get('origin');

  let allowOrigin = '*';

  if (allowedOriginsEnv && allowedOriginsEnv.trim().length > 0) {
    const allowedList = allowedOriginsEnv
      .split(',')
      .map(o => o.trim().toLowerCase())
      .filter(Boolean);

    if (requestOrigin) {
      const lowerOrigin = requestOrigin.toLowerCase();
      if (allowedList.includes(lowerOrigin) || allowedList.includes('*')) {
        allowOrigin = requestOrigin;
      } else {
        // Fallback for non-matching origin when restriction is enabled
        allowOrigin = allowedList[0] || 'null';
      }
    } else {
      allowOrigin = allowedList[0] || '*';
    }
  } else if (requestOrigin) {
    // If ALLOWED_ORIGINS not explicitly set, reflect request origin (development convenience)
    allowOrigin = requestOrigin;
  }

  return {
    'Access-Control-Allow-Origin': allowOrigin,
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
    'Access-Control-Allow-Methods': 'POST, GET, OPTIONS, PUT, DELETE, PATCH',
    'Access-Control-Max-Age': '86400',
  };
}

// Default fallback headers
export const corsHeaders = getCorsHeaders();

export function handleCors(req: Request): Response | null {
  if (req.method === 'OPTIONS') {
    return new Response('ok', {
      status: 204,
      headers: getCorsHeaders(req),
    });
  }
  return null;
}
