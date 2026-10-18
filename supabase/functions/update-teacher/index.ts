// supabase/functions/update-teacher/index.ts
// Administrative Teacher Information and Course/Subject Assignment Updates

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { handleCors } from '../_shared/cors.ts';
import { jsonResponse, errorResponse } from '../_shared/response.ts';
import { requireAdmin } from '../_shared/auth-guard.ts';

interface UpdateTeacherPayload {
  teacher_id: number;
  fields?: {
    name?: string;
    phone?: string;
    username?: string;
  };
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

    const { adminClient } = auth;

    // 2. Parse & Validate Payload
    const body: UpdateTeacherPayload = await req.json().catch(() => ({}));
    const { teacher_id, fields } = body;

    if (!teacher_id || typeof teacher_id !== 'number') {
      return errorResponse('Valid teacher_id is required.', 400, undefined, req);
    }

    // 3. Verify Teacher Record
    const { data: existingTeacher, error: teacherFetchError } = await adminClient
      .from('teachers')
      .select('id, name, phone, login_username, status')
      .eq('id', teacher_id)
      .maybeSingle();

    if (teacherFetchError || !existingTeacher) {
      return errorResponse('Teacher not found.', 404, undefined, req);
    }

    const updates: Record<string, unknown> = {};

    // 4. Validate & Process Field Updates
    if (fields) {
      if (fields.name !== undefined) {
        if (typeof fields.name !== 'string' || fields.name.trim().length === 0) {
          return errorResponse('Name cannot be empty.', 400, undefined, req);
        }
        updates.name = fields.name.trim();
      }

      if (fields.phone !== undefined) {
        updates.phone = fields.phone ? fields.phone.trim() : null;
      }

      if (fields.username !== undefined) {
        const cleanUser = fields.username.trim().toLowerCase();
        if (cleanUser.length < 3 || !/^[a-z0-9_.-]+$/.test(cleanUser)) {
          return errorResponse('Invalid username format. Must be at least 3 alphanumeric characters.', 400, undefined, req);
        }

        if (cleanUser !== existingTeacher.login_username.toLowerCase()) {
          // Check conflict
          const { data: conflict } = await adminClient
            .from('teachers')
            .select('id')
            .eq('login_username', cleanUser)
            .neq('id', teacher_id)
            .maybeSingle();

          if (conflict) {
            return errorResponse(`Username '${cleanUser}' is already taken.`, 409, undefined, req);
          }

          updates.login_username = cleanUser;

          // Update Auth user email & metadata
          const { data: teacherProfile } = await adminClient
            .from('profiles')
            .select('user_id')
            .eq('teacher_id', teacher_id)
            .maybeSingle();

          if (teacherProfile?.user_id) {
            const newSyntheticEmail = `${cleanUser}@teachers.mips.invalid`;
            await adminClient.auth.admin.updateUserById(teacherProfile.user_id, {
              email: newSyntheticEmail,
              user_metadata: { username: cleanUser, name: updates.name || existingTeacher.name },
            });
          }
        }
      }
    }

    // Apply Teacher Updates
    if (Object.keys(updates).length > 0) {
      const { error: updateError } = await adminClient
        .from('teachers')
        .update(updates)
        .eq('id', teacher_id);

      if (updateError) {
        return errorResponse(`Failed to update teacher: ${updateError.message}`, 500, undefined, req);
      }
    }

    // 5. Log Admin Audit Action
    await adminClient.rpc('log_admin_action', {
      p_action: 'UPDATE_TEACHER',
      p_target: teacher_id.toString(),
      p_details: {
        teacher_id,
        updated_fields: Object.keys(updates),
      },
    });

    // 6. Fetch refreshed teacher record
    const { data: updatedTeacher } = await adminClient
      .from('teachers')
      .select('id, name, phone, login_username, status')
      .eq('id', teacher_id)
      .single();

    return jsonResponse(
      {
        success: true,
        message: 'Teacher details updated successfully.',
        teacher: updatedTeacher,
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
