// supabase/functions/reset-password/index.ts
// Administrative Credential Reset for Teachers and Students

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { handleCors } from '../_shared/cors.ts';
import { jsonResponse, errorResponse } from '../_shared/response.ts';
import { requireAdmin } from '../_shared/auth-guard.ts';
import { generateStrongPassword, validatePassword } from '../_shared/password-policy.ts';

interface ResetPasswordPayload {
  user_id?: string;
  identifier?: string;
  role?: 'teacher' | 'student';
  mode?: 'generate' | 'custom' | 'first_login';
  temp_password?: string;
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
    const body: ResetPasswordPayload = await req.json().catch(() => ({}));
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

          // If no profile exists yet for this student
          if (!targetUserId) {
            if (body.mode === 'generate' || body.mode === 'custom') {
              const standardReg = (s.registration_number || s.admission_number || cleanIdent).toLowerCase().trim();
              const studentEmail = `${standardReg}@students.mips.invalid`;
              let tempPassword = '';
              if (body.mode === 'custom' && body.temp_password) {
                const policy = validatePassword(body.temp_password);
                if (!policy.valid) {
                  return errorResponse(policy.reason || 'Password policy violation.', 400, undefined, req);
                }
                tempPassword = body.temp_password;
              } else {
                tempPassword = generateStrongPassword(12);
              }

              const { data: authUser, error: authErr } = await adminClient.auth.admin.createUser({
                email: studentEmail,
                password: tempPassword,
                email_confirm: true,
                user_metadata: { role: 'student', name: s.name, registration_number: standardReg },
              });

              if (authErr || !authUser.user) {
                return errorResponse(`Failed to initialize student account: ${authErr?.message}`, 500, undefined, req);
              }

              await adminClient.from('profiles').insert({
                user_id: authUser.user.id,
                role: 'student',
                student_id: s.id,
                active: true,
                must_change_password: true,
                first_login_required: false,
                failed_attempts: 0,
              });

              await adminClient.rpc('log_admin_action', {
                p_action: 'RESET_STUDENT_PASSWORD',
                p_target: authUser.user.id,
                p_details: {
                  student_id: s.id,
                  registration_number: standardReg,
                  mode: body.mode,
                  action: 'Initial temporary password provisioned by administrator',
                },
              });

              return jsonResponse(
                {
                  success: true,
                  message: 'Temporary password generated for student account.',
                  user_id: authUser.user.id,
                  role: 'student',
                  temporary_password: tempPassword,
                  must_change_password: true,
                },
                201,
                req
              );
            } else {
              // Mode: first_login - already uninitialized
              return jsonResponse(
                {
                  success: true,
                  message: 'Student account is not yet activated. The student will verify with their Date of Birth on their first login.',
                  role: 'student',
                  first_login_required: true,
                },
                200,
                req
              );
            }
          }
        }
      }
    }

    if (!targetUserId) {
      return errorResponse('Valid target user_id (or identifier and role) is required.', 400, undefined, req);
    }

    // 3. Query Target Profile
    const { data: targetProfile, error: profileFetchError } = await adminClient
      .from('profiles')
      .select('user_id, role, active, student_id, teacher_id')
      .eq('user_id', targetUserId)
      .maybeSingle();

    if (profileFetchError || !targetProfile) {
      return errorResponse('Target user profile not found.', 404, undefined, req);
    }

    // 4. Role-Specific Reset Workflow
    if (targetProfile.role === 'teacher') {
      // Fetch teacher username/name for policy validation
      let teacherUsername = '';
      let teacherName = '';
      if (targetProfile.teacher_id) {
        const { data: tData } = await adminClient
          .from('teachers')
          .select('name, login_username')
          .eq('id', targetProfile.teacher_id)
          .maybeSingle();
        if (tData) {
          teacherUsername = tData.login_username ?? '';
          teacherName = tData.name ?? '';
        }
      }

      // Determine Temporary Password: generate or custom
      let tempPassword = '';
      if (body.mode === 'custom' && body.temp_password) {
        const policy = validatePassword(body.temp_password, {
          username: teacherUsername,
          name: teacherName,
        });
        if (!policy.valid) {
          return errorResponse(policy.reason || 'Password policy violation.', 400, undefined, req);
        }
        tempPassword = body.temp_password;
      } else {
        tempPassword = generateStrongPassword(12);
      }

      const { error: updateAuthError } = await adminClient.auth.admin.updateUserById(targetUserId, {
        password: tempPassword,
      });

      if (updateAuthError) {
        return errorResponse(`Failed to update Auth password: ${updateAuthError.message}`, 500, undefined, req);
      }

      // Revoke all existing sessions
      try {
        await adminClient.auth.admin.signOut(targetUserId);
      } catch (signOutErr) {
        console.warn('Session revocation notice:', signOutErr);
      }

      // Update Profile state
      await adminClient
        .from('profiles')
        .update({
          must_change_password: true,
          failed_attempts: 0,
          locked_at: null,
          active: true,
          updated_at: new Date().toISOString(),
        })
        .eq('user_id', targetUserId);

      // Audit Log (Zero secrets in log)
      await adminClient.rpc('log_admin_action', {
        p_action: 'RESET_TEACHER_PASSWORD',
        p_target: targetUserId,
        p_details: {
          target_user_id: targetUserId,
          role: 'teacher',
          mode: body.mode || 'generate',
          action: 'Temporary password issued and must_change_password set',
        },
      });

      return jsonResponse(
        {
          success: true,
          message: 'Teacher password reset successfully.',
          user_id: targetUserId,
          role: 'teacher',
          temporary_password: tempPassword,
          must_change_password: true,
        },
        200,
        req
      );

    } else if (targetProfile.role === 'student') {
      if (body.mode === 'generate' || body.mode === 'custom') {
        // Mode: Set Temporary Password (Admin generated or typed)
        let tempPassword = '';
        if (body.mode === 'custom' && body.temp_password) {
          const policy = validatePassword(body.temp_password);
          if (!policy.valid) {
            return errorResponse(policy.reason || 'Password policy violation.', 400, undefined, req);
          }
          tempPassword = body.temp_password;
        } else {
          tempPassword = generateStrongPassword(12);
        }

        const { error: updateAuthError } = await adminClient.auth.admin.updateUserById(targetUserId, {
          password: tempPassword,
        });

        if (updateAuthError) {
          return errorResponse(`Failed to reset Auth credentials: ${updateAuthError.message}`, 500, undefined, req);
        }

        try {
          await adminClient.auth.admin.signOut(targetUserId);
        } catch (signOutErr) {
          console.warn('Session revocation notice:', signOutErr);
        }

        await adminClient
          .from('profiles')
          .update({
            first_login_required: false,
            must_change_password: true,
            failed_attempts: 0,
            locked_at: null,
            active: true,
            updated_at: new Date().toISOString(),
          })
          .eq('user_id', targetUserId);

        await adminClient.rpc('log_admin_action', {
          p_action: 'RESET_STUDENT_PASSWORD',
          p_target: targetUserId,
          p_details: {
            target_user_id: targetUserId,
            role: 'student',
            mode: body.mode,
            action: 'Temporary password issued, forced change at next login',
          },
        });

        return jsonResponse(
          {
            success: true,
            message: 'Student temporary password set successfully.',
            user_id: targetUserId,
            role: 'student',
            temporary_password: tempPassword,
            must_change_password: true,
          },
          200,
          req
        );
      } else {
        // Mode: Reset to first login (Student verifies with DOB)
        const randomInvalidSecret = `${crypto.randomUUID()}-${crypto.randomUUID()}`;

        const { error: updateAuthError } = await adminClient.auth.admin.updateUserById(targetUserId, {
          password: randomInvalidSecret,
        });

        if (updateAuthError) {
          return errorResponse(`Failed to reset Auth credentials: ${updateAuthError.message}`, 500, undefined, req);
        }

        // Revoke all active sessions
        try {
          await adminClient.auth.admin.signOut(targetUserId);
        } catch (signOutErr) {
          console.warn('Session revocation notice:', signOutErr);
        }

        // Update Profile state
        await adminClient
          .from('profiles')
          .update({
            first_login_required: true,
            must_change_password: false,
            failed_attempts: 0,
            locked_at: null,
            active: true,
            updated_at: new Date().toISOString(),
          })
          .eq('user_id', targetUserId);

        // Audit Log
        await adminClient.rpc('log_admin_action', {
          p_action: 'RESET_STUDENT_PASSWORD',
          p_target: targetUserId,
          p_details: {
            target_user_id: targetUserId,
            role: 'student',
            mode: 'first_login',
            action: 'Credentials invalidated; student requires DOB verification on next login',
          },
        });

        return jsonResponse(
          {
            success: true,
            message: 'Student password reset. The student must verify using their Date of Birth on their next login to choose a new password.',
            user_id: targetUserId,
            role: 'student',
            first_login_required: true,
          },
          200,
          req
        );
      }
    } else if (targetProfile.role === 'admin') {
      // Admin Reset: Generate temporary password
      const tempPassword = generateStrongPassword(14);

      await adminClient.auth.admin.updateUserById(targetUserId, {
        password: tempPassword,
      });

      try {
        await adminClient.auth.admin.signOut(targetUserId);
      } catch {
        // ignore
      }

      await adminClient
        .from('profiles')
        .update({
          must_change_password: true,
          failed_attempts: 0,
          locked_at: null,
          active: true,
          updated_at: new Date().toISOString(),
        })
        .eq('user_id', targetUserId);

      await adminClient.rpc('log_admin_action', {
        p_action: 'RESET_ADMIN_PASSWORD',
        p_target: targetUserId,
        p_details: {
          target_user_id: targetUserId,
          role: 'admin',
        },
      });

      return jsonResponse(
        {
          success: true,
          message: 'Administrator password reset successfully.',
          user_id: targetUserId,
          role: 'admin',
          temporary_password: tempPassword,
          must_change_password: true,
        },
        200,
        req
      );
    }

    return errorResponse(`Unsupported role '${targetProfile.role}'.`, 400, undefined, req);

  } catch (error) {
    return errorResponse(
      `Internal server error: ${error instanceof Error ? error.message : String(error)}`,
      500,
      undefined,
      req
    );
  }
});
