// supabase/functions/unlock-account/index.ts
// Administrative Account Unlock & Lockout Counter Reset

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { handleCors } from '../_shared/cors.ts';
import { jsonResponse, errorResponse } from '../_shared/response.ts';
import { requireAdmin } from '../_shared/auth-guard.ts';

interface UnlockAccountPayload {
  user_id?: string;
  identifier?: string;
  role?: 'teacher' | 'student';
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

    const { adminClient } = auth;

    // 2. Parse & Resolve Target User ID
    const body: UnlockAccountPayload = await req.json().catch(() => ({}));
    let targetUserId = body.user_id;

    if (!targetUserId && body.identifier && body.role) {
      const cleanIdent = body.identifier.trim().toLowerCase();
      if (body.role === 'teacher') {
        const { data: t } = await adminClient
          .from('teachers')
          .select('id')
          .ilike('login_username', cleanIdent)
          .maybeSingle();

        if (t) {
          const { data: p } = await adminClient
            .from('profiles')
            .select('user_id')
            .eq('teacher_id', t.id)
            .maybeSingle();
          targetUserId = p?.user_id;
        }
      } else if (body.role === 'student') {
        const { data: s } = await adminClient
          .from('students')
          .select('id')
          .or(`registration_number.ilike.${cleanIdent},admission_number.ilike.${cleanIdent}`)
          .maybeSingle();

        if (s) {
          const { data: p } = await adminClient
            .from('profiles')
            .select('user_id')
            .eq('student_id', s.id)
            .maybeSingle();
          targetUserId = p?.user_id;
        }
      }
    }

    // 3. Delegate to consolidated atomic RPC function admin_unlock_account
    const { data: rpcRes, error: rpcErr } = await adminClient.rpc('admin_unlock_account', {
      p_user_id: targetUserId || null,
      p_identifier: body.identifier || null,
      p_role: body.role || null,
    });

    if (rpcErr || !rpcRes?.success) {
      return errorResponse(rpcErr?.message || rpcRes?.error || 'Failed to unlock account.', 400, undefined, req);
    }

    return jsonResponse(rpcRes, 200, req);

  } catch (error) {
    return errorResponse(
      `Internal server error: ${error instanceof Error ? error.message : String(error)}`,
      500,
      undefined,
      req
    );
  }
});
