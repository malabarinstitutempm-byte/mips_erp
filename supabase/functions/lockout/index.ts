// supabase/functions/lockout/index.ts
// Legacy/Compatibility Bridge: Account Lockout & Administrative Account Unlock

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { handleCors } from '../_shared/cors.ts';
import { getAdminClient } from '../_shared/supabase-client.ts';
import { jsonResponse, errorResponse } from '../_shared/response.ts';
import { hashIdentifier, getClientIp } from '../_shared/crypto.ts';
import { requireAdmin } from '../_shared/auth-guard.ts';

interface LockoutActionPayload {
  action: 'check' | 'record_failed' | 'record_success' | 'unlock';
  user_id?: string;
  identifier?: string;
  role?: 'admin' | 'teacher' | 'student';
}

serve(async (req: Request) => {
  const corsResponse = handleCors(req);
  if (corsResponse) return corsResponse;

  if (req.method !== 'POST') {
    return errorResponse('Method not allowed. Use POST.', 405, undefined, req);
  }

  try {
    // 1. Enforce Admin Access & MFA Verification
    const { errorResponse: authError, auth } = await requireAdmin(req);
    if (authError || !auth) {
      return authError || errorResponse('Forbidden.', 403, undefined, req);
    }

    const body: LockoutActionPayload = await req.json().catch(() => ({}));
    const { action, identifier, role } = body;
    let userId = body.user_id;
    const adminClient = auth.adminClient;

    // Resolve userId from identifier if not directly passed
    if (!userId && identifier) {
      const cleanIdent = identifier.trim().toLowerCase();

      if (cleanIdent.includes('@')) {
        const { data: usersData } = await adminClient.auth.admin.listUsers();
        const found = usersData?.users?.find(u => u.email?.toLowerCase() === cleanIdent);
        if (found) userId = found.id;
      }

      if (!userId && (!role || role === 'student')) {
        const { data: student } = await adminClient
          .from('students')
          .select('id')
          .or(`registration_number.ilike.${cleanIdent},admission_number.ilike.${cleanIdent}`)
          .maybeSingle();

        if (student) {
          const { data: prof } = await adminClient
            .from('profiles')
            .select('user_id')
            .eq('student_id', student.id)
            .maybeSingle();
          if (prof) userId = prof.user_id;
        }
      }

      if (!userId && (!role || role === 'teacher')) {
        const { data: teacher } = await adminClient
          .from('teachers')
          .select('id')
          .ilike('login_username', cleanIdent)
          .maybeSingle();

        if (teacher) {
          const { data: prof } = await adminClient
            .from('profiles')
            .select('user_id')
            .eq('teacher_id', teacher.id)
            .maybeSingle();
          if (prof) userId = prof.user_id;
        }
      }
    }

    if (!userId && action !== 'check') {
      return errorResponse('User could not be resolved from parameters.', 404, undefined, req);
    }

    if (action === 'check') {
      if (!identifier && !userId) {
        return errorResponse('Either user_id or identifier is required for check.', 400, undefined, req);
      }
      const hash = await hashIdentifier(identifier || userId || '');
      const ip = getClientIp(req);
      const { data: metrics } = await adminClient.rpc('get_login_failure_metrics', {
        p_identifier_hash: hash,
        p_ip: ip,
      });

      return jsonResponse({
        success: true,
        user_id: userId,
        metrics,
      }, 200, req);
    }

    if (action === 'unlock') {
      const { errorResponse: authError } = await requireAdmin(req);
      if (authError) return authError;

      await adminClient
        .from('profiles')
        .update({
          failed_attempts: 0,
          locked_at: null,
          active: true,
          updated_at: new Date().toISOString(),
        })
        .eq('user_id', userId);

      await adminClient.rpc('log_admin_action', {
        p_action: 'UNLOCK_ACCOUNT',
        p_target: userId!,
        p_details: { action: 'unlock_via_lockout_endpoint' },
      });

      return jsonResponse({
        success: true,
        message: 'Account unlocked.',
        user_id: userId,
      }, 200, req);
    }

    return errorResponse(`Action '${action}' not supported. Use dedicated edge functions (login, unlock-account).`, 400, undefined, req);

  } catch (error) {
    return errorResponse(
      `Internal server error: ${error instanceof Error ? error.message : String(error)}`,
      500,
      undefined,
      req
    );
  }
});
