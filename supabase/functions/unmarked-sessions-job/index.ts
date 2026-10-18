// supabase/functions/unmarked-sessions-job/index.ts
// Scheduled Job (19:30 IST / 14:00 UTC): Prepare End-of-Day Unmarked Slots & Admin Alert

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { handleCors } from '../_shared/cors.ts';
import { getAdminClient } from '../_shared/supabase-client.ts';
import { jsonResponse, errorResponse } from '../_shared/response.ts';
import { requireAdmin } from '../_shared/auth-guard.ts';

serve(async (req: Request) => {
  const corsResponse = handleCors(req);
  if (corsResponse) return corsResponse;

  if (req.method !== 'POST' && req.method !== 'GET') {
    return errorResponse('Method not allowed. Use GET or POST.', 405, undefined, req);
  }

  try {
    // Enforce Service Role or Admin Authentication
    const authHeader = req.headers.get('Authorization');
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    const isServiceCall = serviceRoleKey && authHeader === `Bearer ${serviceRoleKey}`;

    if (!isServiceCall) {
      const { errorResponse: authError, auth } = await requireAdmin(req);
      if (authError || !auth) {
        return authError || errorResponse('Unauthorized. Admin privilege or service role key required.', 401, undefined, req);
      }
    }

    const adminClient = getAdminClient();
    const url = new URL(req.url);
    const dateParam = url.searchParams.get('date');

    const targetDate = dateParam || new Date().toISOString().split('T')[0];

    // Invoke RPC function prepare_unmarked_slots_dashboard
    const { data, error } = await adminClient.rpc('prepare_unmarked_slots_dashboard', {
      p_date: targetDate,
    });

    if (error) {
      console.error('[unmarked-sessions-job] RPC error:', error);
      return errorResponse(`Failed to prepare unmarked slots: ${error.message}`, 500, undefined, req);
    }

    console.log(`[unmarked-sessions-job] Prepared unmarked slots for ${targetDate}:`, data);

    return jsonResponse(
      {
        success: true,
        message: 'End-of-day unmarked sessions processed successfully.',
        data,
      },
      200,
      undefined,
      req
    );
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : String(err);
    console.error('[unmarked-sessions-job] Unexpected error:', err);
    return errorResponse(`Internal error: ${msg}`, 500, undefined, req);
  }
});
