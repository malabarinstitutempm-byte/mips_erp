// supabase/functions/create-teacher/index.ts
// Provision Teacher Account (Admin Only)

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { handleCors } from '../_shared/cors.ts';
import { jsonResponse, errorResponse } from '../_shared/response.ts';
import { requireAdmin } from '../_shared/auth-guard.ts';
import { generateStrongPassword, validatePassword } from '../_shared/password-policy.ts';

interface CreateTeacherPayload {
  name: string;
  phone?: string;
  username: string;
  temp_password?: string;
}

serve(async (req: Request) => {
  const corsResponse = handleCors(req);
  if (corsResponse) return corsResponse;

  if (req.method !== 'POST') {
    return errorResponse('Method not allowed. Use POST.', 405, undefined, req);
  }

  try {
    // 1. Enforce Admin Role & MFA Verification
    const { errorResponse: authError, auth } = await requireAdmin(req);
    if (authError || !auth) {
      return authError || errorResponse('Forbidden.', 403, undefined, req);
    }

    const { adminClient, userId: adminUserId } = auth;

    // 2. Parse & Validate Payload
    const body: CreateTeacherPayload = await req.json().catch(() => ({}));
    const { name, phone, username, temp_password } = body;

    if (!name || typeof name !== 'string' || name.trim().length === 0) {
      return errorResponse('Teacher name is required.', 400, undefined, req);
    }

    if (!username || typeof username !== 'string' || username.trim().length < 3) {
      return errorResponse('Username must be at least 3 characters long.', 400, undefined, req);
    }

    const cleanUsername = username.trim().toLowerCase();
    if (!/^[a-z0-9_.-]+$/.test(cleanUsername)) {
      return errorResponse('Username can only contain alphanumeric characters, underscores, dots, or dashes.', 400, undefined, req);
    }

    // Determine Temporary Password
    let finalTempPassword = temp_password;
    if (finalTempPassword) {
      const policy = validatePassword(finalTempPassword, { username: cleanUsername, name: name.trim() });
      if (!policy.valid) {
        return errorResponse(policy.reason || 'Password policy violation.', 400, undefined, req);
      }
    } else {
      finalTempPassword = generateStrongPassword(12);
    }

    // 3. Synthetic Teacher Email
    const teacherEmail = `${cleanUsername}@teachers.mips.invalid`;

    // 4. Check for Existing Teacher
    const { data: existingTeacher } = await adminClient
      .from('teachers')
      .select('id')
      .eq('login_username', cleanUsername)
      .maybeSingle();

    if (existingTeacher) {
      return errorResponse(`Username '${cleanUsername}' is already assigned to a teacher.`, 409, undefined, req);
    }

    // 5. Create Auth Account in Supabase Auth
    const { data: authUser, error: createAuthError } = await adminClient.auth.admin.createUser({
      email: teacherEmail,
      password: finalTempPassword,
      email_confirm: true,
      user_metadata: {
        role: 'teacher',
        name: name.trim(),
        username: cleanUsername,
      },
    });

    if (createAuthError || !authUser.user) {
      return errorResponse(`Failed to create Auth account: ${createAuthError?.message}`, 500, undefined, req);
    }

    const newUserId = authUser.user.id;

    // 6. Insert Teacher Record
    const { data: teacherRecord, error: teacherInsertError } = await adminClient
      .from('teachers')
      .insert({
        name: name.trim(),
        phone: phone ? phone.trim() : null,
        login_username: cleanUsername,
        status: 'active',
      })
      .select('id, name, phone, login_username, status')
      .single();

    if (teacherInsertError || !teacherRecord) {
      await adminClient.auth.admin.deleteUser(newUserId);
      return errorResponse(`Failed to insert teacher record: ${teacherInsertError?.message}`, 500, undefined, req);
    }

    // 7. Insert Profile Record
    const { error: profileError } = await adminClient
      .from('profiles')
      .insert({
        user_id: newUserId,
        role: 'teacher',
        teacher_id: teacherRecord.id,
        student_id: null,
        active: true,
        must_change_password: true,
        first_login_required: false,
        failed_attempts: 0,
      });

    if (profileError) {
      await adminClient.auth.admin.deleteUser(newUserId);
      return errorResponse(`Failed to link user profile: ${profileError.message}`, 500, undefined, req);
    }

    // 8. Structured Audit Logging (Zero Secrets in Log)
    await adminClient.rpc('log_admin_action', {
      p_action: 'CREATE_TEACHER',
      p_target: teacherRecord.id.toString(),
      p_details: {
        teacher_id: teacherRecord.id,
        username: cleanUsername,
        assigned_user_id: newUserId,
      },
    });

    // 9. Return Temporary Password Once in Response Only
    return jsonResponse(
      {
        success: true,
        message: 'Teacher account provisioned successfully.',
        teacher: {
          id: teacherRecord.id,
          user_id: newUserId,
          name: teacherRecord.name,
          login_username: teacherRecord.login_username,
          phone: teacherRecord.phone,
          email: teacherEmail,
          temporary_password: finalTempPassword,
          must_change_password: true,
        },
      },
      201,
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
