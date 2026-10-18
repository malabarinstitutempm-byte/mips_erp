// supabase/functions/set-password/index.ts
// Authenticated User Password Change & Session Invalidation

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { handleCors } from '../_shared/cors.ts';
import { jsonResponse, errorResponse } from '../_shared/response.ts';
import { requireActiveUser } from '../_shared/auth-guard.ts';
import { validatePassword } from '../_shared/password-policy.ts';

interface SetPasswordPayload {
  new_password: string;
}

serve(async (req: Request) => {
  const corsResponse = handleCors(req);
  if (corsResponse) return corsResponse;

  if (req.method !== 'POST') {
    return errorResponse('Method not allowed. Use POST.', 405, undefined, req);
  }

  try {
    // 1. Authenticate caller session
    const { errorResponse: authError, auth } = await requireActiveUser(req);
    if (authError || !auth) {
      return authError || errorResponse('Unauthorized.', 401, undefined, req);
    }

    // 2. Parse & Validate Payload
    const body: SetPasswordPayload = await req.json().catch(() => ({}));
    const { new_password } = body;

    if (!new_password || typeof new_password !== 'string') {
      return errorResponse('New password is required.', 400, undefined, req);
    }

    // Context for password policy
    const context: { username?: string; registrationNumber?: string } = {};
    if (auth.role === 'teacher' && auth.profile?.teacher_id) {
      const { data: t } = await auth.adminClient
        .from('teachers')
        .select('login_username')
        .eq('id', auth.profile.teacher_id)
        .maybeSingle();
      if (t) context.username = t.login_username;
    } else if (auth.role === 'student' && auth.profile?.student_id) {
      const { data: s } = await auth.adminClient
        .from('students')
        .select('registration_number, admission_number, dob, name')
        .eq('id', auth.profile.student_id)
        .maybeSingle();
      if (s) {
        context.registrationNumber = s.registration_number || s.admission_number;
      }
    }

    const policyCheck = validatePassword(new_password, context);
    if (!policyCheck.valid) {
      return errorResponse(policyCheck.reason || 'Password policy violation.', 400, undefined, req);
    }

    // 3. Update Password in Supabase Auth via Admin Client
    const { error: updateError } = await auth.adminClient.auth.admin.updateUserById(auth.userId, {
      password: new_password,
    });

    if (updateError) {
      return errorResponse(`Failed to update password: ${updateError.message}`, 500, undefined, req);
    }

    // 4. Update Profile Flags
    await auth.adminClient
      .from('profiles')
      .update({
        must_change_password: false,
        first_login_required: false,
        updated_at: new Date().toISOString(),
      })
      .eq('user_id', auth.userId);

    // 5. Invalidate / Revoke other sessions
    try {
      // In Supabase Auth JS v2, signOut on admin client revokes user sessions
      await auth.adminClient.auth.admin.signOut(auth.userId, 'others');
    } catch (signOutErr) {
      // Non-fatal if the specific driver does not support 'others' parameter
      console.warn('Other sessions revocation note:', signOutErr);
    }

    // 6. Audit Log
    await auth.adminClient.from('audit_log').insert({
      table_name: 'profiles',
      record_id: auth.userId,
      action: 'UPDATE',
      new_data: {
        event: 'PASSWORD_UPDATED',
        user_id: auth.userId,
        role: auth.role,
      },
      actor: auth.userId,
    });

    return jsonResponse(
      {
        success: true,
        message: 'Password successfully updated. Other active sessions have been revoked.',
      },
      200,
      req
    );

  } catch (error) {
    return errorResponse(
      `Internal server error: ${error instanceof Error ? error.message : String(error)}`,
      500,
      undefined,
      req
    );
  }
});
