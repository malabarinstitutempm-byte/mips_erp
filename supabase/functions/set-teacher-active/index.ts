// supabase/functions/set-teacher-active/index.ts
// Teacher Deactivation & Reactivation Lifecycle Management

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { handleCors } from '../_shared/cors.ts';
import { jsonResponse, errorResponse } from '../_shared/response.ts';
import { requireAdmin } from '../_shared/auth-guard.ts';

interface SetTeacherActivePayload {
  teacher_id: number;
  active: boolean;
  reassign_to?: number;
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
    const body: SetTeacherActivePayload = await req.json().catch(() => ({}));
    const { teacher_id, active, reassign_to } = body;

    if (!teacher_id || typeof teacher_id !== 'number') {
      return errorResponse('Valid teacher_id is required.', 400, undefined, req);
    }

    if (typeof active !== 'boolean') {
      return errorResponse("'active' boolean flag is required.", 400, undefined, req);
    }

    // 3. Verify Teacher Existence
    const { data: teacher, error: teacherError } = await adminClient
      .from('teachers')
      .select('id, name, login_username, status')
      .eq('id', teacher_id)
      .maybeSingle();

    if (teacherError || !teacher) {
      return errorResponse('Teacher record not found.', 404, undefined, req);
    }

    // 4. Resolve Linked Profile & User ID
    const { data: profile } = await adminClient
      .from('profiles')
      .select('user_id, active')
      .eq('teacher_id', teacher_id)
      .maybeSingle();

    let openDraftSessions: unknown[] = [];
    let reassignedCount = 0;

    if (!active) {
      // =======================================================================
      // DEACTIVATION WORKFLOW
      // =======================================================================

      // Step A: Ban Auth User & Revoke Sessions
      if (profile?.user_id) {
        try {
          await adminClient.auth.admin.updateUserById(profile.user_id, {
            ban_duration: '876000h', // Effectively permanent until unbanned
          });
          await adminClient.auth.admin.signOut(profile.user_id);
        } catch (authErr) {
          console.warn('Auth user ban warning:', authErr);
        }
      }

      // Step B: Update Profiles Table
      await adminClient
        .from('profiles')
        .update({
          active: false,
          locked_at: new Date().toISOString(),
          updated_at: new Date().toISOString(),
        })
        .eq('teacher_id', teacher_id);

      // Step C: Update Teachers Table
      await adminClient
        .from('teachers')
        .update({
          status: 'inactive',
          deactivated_at: new Date().toISOString(),
          deactivated_by: adminUserId,
        })
        .eq('id', teacher_id);

      // Step D: Find any Draft Sessions left open by this teacher
      // Note: Attendance session history and submitted 'marked_by' are permanently preserved.
      const { data: draftSessions } = await adminClient
        .from('attendance_sessions')
        .select('id, batch_id, subject_id, date, period, status, marked_by')
        .eq('marked_by', teacher_id)
        .eq('status', 'draft');

      openDraftSessions = draftSessions || [];

      // Step E: Optional Reassignment of Open Draft Sessions
      if (reassign_to && typeof reassign_to === 'number') {
        const { data: targetTeacher } = await adminClient
          .from('teachers')
          .select('id, name, status')
          .eq('id', reassign_to)
          .eq('status', 'active')
          .maybeSingle();

        if (!targetTeacher) {
          return errorResponse('Target reassign_to teacher not found or is inactive.', 400, undefined, req);
        }

        // Reassign open draft sessions so the new teacher can complete them
        if (openDraftSessions.length > 0) {
          await adminClient
            .from('attendance_sessions')
            .update({ marked_by: targetTeacher.id })
            .eq('marked_by', teacher_id)
            .eq('status', 'draft');
        }
      }

    } else {
      // =======================================================================
      // REACTIVATION WORKFLOW
      // =======================================================================

      // Step A: Lift Auth User Ban
      if (profile?.user_id) {
        try {
          await adminClient.auth.admin.updateUserById(profile.user_id, {
            ban_duration: 'none',
          });
        } catch (authErr) {
          console.warn('Auth user unban warning:', authErr);
        }
      }

      // Step B: Reactivate Profile
      await adminClient
        .from('profiles')
        .update({
          active: true,
          locked_at: null,
          failed_attempts: 0,
          updated_at: new Date().toISOString(),
        })
        .eq('teacher_id', teacher_id);

      // Step C: Reactivate Teacher Record
      await adminClient
        .from('teachers')
        .update({
          status: 'active',
          deactivated_at: null,
          deactivated_by: null,
        })
        .eq('id', teacher_id);
    }

    // 5. Audit Log
    await adminClient.rpc('log_admin_action', {
      p_action: active ? 'REACTIVATE_TEACHER' : 'DEACTIVATE_TEACHER',
      p_target: teacher_id.toString(),
      p_details: {
        teacher_id,
        action: active ? 'reactivate' : 'deactivate',
        reassigned_to: reassign_to || null,
        open_draft_sessions_count: openDraftSessions.length,
      },
    });

    return jsonResponse(
      {
        success: true,
        message: active
          ? `Teacher '${teacher.name}' has been successfully reactivated.`
          : `Teacher '${teacher.name}' has been deactivated. Auth sessions revoked.`,
        teacher_id,
        active,
        open_draft_sessions: openDraftSessions,
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
