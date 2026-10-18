// supabase/functions/set-student-active/index.ts
// Student Login Deactivation & Reactivation Lifecycle Management

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { handleCors } from '../_shared/cors.ts';
import { jsonResponse, errorResponse } from '../_shared/response.ts';
import { requireAdmin } from '../_shared/auth-guard.ts';

interface SetStudentActivePayload {
  student_id: number;
  active: boolean;
}

serve(async (req: Request) => {
  const corsResponse = handleCors(req);
  if (corsResponse) return corsResponse;

  if (req.method !== 'POST' && req.method !== 'PUT') {
    return errorResponse('Method not allowed. Use POST or PUT.', 405, undefined, req);
  }

  try {
    // 1. Enforce Admin Access & MFA Verification
    const { errorResponse: authError, auth } = await requireAdmin(req);
    if (authError || !auth) {
      return authError || errorResponse('Forbidden.', 403, undefined, req);
    }

    const { adminClient, userId: adminUserId } = auth;

    // 2. Parse & Validate Payload
    const body: SetStudentActivePayload = await req.json().catch(() => ({}));
    const { student_id, active } = body;

    if (!student_id || typeof student_id !== 'number') {
      return errorResponse('Valid student_id is required.', 400, undefined, req);
    }

    if (typeof active !== 'boolean') {
      return errorResponse("'active' boolean flag is required.", 400, undefined, req);
    }

    // 3. Verify Student Existence
    const { data: student, error: studentError } = await adminClient
      .from('students')
      .select('id, name, registration_number, admission_number, status')
      .eq('id', student_id)
      .maybeSingle();

    if (studentError || !student) {
      return errorResponse('Student record not found.', 404, undefined, req);
    }

    // 4. Resolve Linked Profile & User ID
    const { data: profile } = await adminClient
      .from('profiles')
      .select('user_id, active')
      .eq('student_id', student_id)
      .maybeSingle();

    if (!active) {
      // Deactivate Auth User & Revoke Sessions
      if (profile?.user_id) {
        try {
          await adminClient.auth.admin.updateUserById(profile.user_id, {
            ban_duration: '876000h',
          });
          await adminClient.auth.admin.signOut(profile.user_id);
        } catch (authErr) {
          console.warn('Student auth ban warning:', authErr);
        }
      }

      if (profile) {
        await adminClient
          .from('profiles')
          .update({
            active: false,
            locked_at: new Date().toISOString(),
            updated_at: new Date().toISOString(),
          })
          .eq('student_id', student_id);
      }

      await adminClient
        .from('students')
        .update({
          status: 'inactive',
          updated_at: new Date().toISOString(),
        })
        .eq('id', student_id);

    } else {
      // Reactivate Auth User
      if (profile?.user_id) {
        try {
          await adminClient.auth.admin.updateUserById(profile.user_id, {
            ban_duration: 'none',
          });
        } catch (authErr) {
          console.warn('Student auth unban warning:', authErr);
        }
      }

      if (profile) {
        await adminClient
          .from('profiles')
          .update({
            active: true,
            locked_at: null,
            failed_attempts: 0,
            updated_at: new Date().toISOString(),
          })
          .eq('student_id', student_id);
      }

      await adminClient
        .from('students')
        .update({
          status: 'active',
          updated_at: new Date().toISOString(),
        })
        .eq('id', student_id);
    }

    // 5. Audit Log (Zero Secrets in Log)
    await adminClient.rpc('log_admin_action', {
      p_action: active ? 'REACTIVATE_STUDENT_LOGIN' : 'DEACTIVATE_STUDENT_LOGIN',
      p_target: student_id.toString(),
      p_details: {
        student_id,
        student_name: student.name,
        registration_number: student.registration_number || student.admission_number,
        action: active ? 'reactivate' : 'deactivate',
      },
    });

    return jsonResponse(
      {
        success: true,
        message: active
          ? `Student '${student.name}' account has been reactivated.`
          : `Student '${student.name}' account has been deactivated. Active login sessions terminated.`,
        student_id,
        active,
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
