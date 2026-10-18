// supabase/functions/student-first-login/index.ts
// Student First-Time Portal Activation & Password Initialization

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { handleCors } from '../_shared/cors.ts';
import { getAdminClient, getAnonClient } from '../_shared/supabase-client.ts';
import { jsonResponse, errorResponse } from '../_shared/response.ts';
import { hashIdentifier, getClientIp } from '../_shared/crypto.ts';
import { validatePassword } from '../_shared/password-policy.ts';

const GENERIC_VERIFY_ERROR = 'Invalid registration number or date of birth. Please check your credentials or contact the college office.';
const LOCKED_MESSAGE = 'Too many failed attempts. Please contact the college office to reset your password.';

interface StudentActivationPayload {
  registration_number: string;
  date_of_birth: string;
  new_password: string;
}

/**
 * Normalizes input date to ISO YYYY-MM-DD format
 * Supports YYYY-MM-DD, DD-MM-YYYY, DD/MM/YYYY, etc.
 */
function normalizeDateOfBirth(input: string): string | null {
  if (!input || typeof input !== 'string') return null;
  const trimmed = input.trim();

  // Format 1: YYYY-MM-DD
  if (/^\d{4}-\d{2}-\d{2}$/.test(trimmed)) {
    return trimmed;
  }

  // Format 2: DD-MM-YYYY or DD/MM/YYYY
  const parts = trimmed.split(/[-/.]/);
  if (parts.length === 3) {
    if (parts[0].length === 2 && parts[1].length === 2 && parts[2].length === 4) {
      const day = parts[0];
      const month = parts[1];
      const year = parts[2];
      return `${year}-${month}-${day}`;
    }
  }

  return null;
}

serve(async (req: Request) => {
  const corsResponse = handleCors(req);
  if (corsResponse) return corsResponse;

  if (req.method !== 'POST') {
    return errorResponse('Method not allowed. Use POST.', 405, undefined, req);
  }

  try {
    const body: StudentActivationPayload = await req.json().catch(() => ({}));
    const { registration_number, date_of_birth, new_password } = body;

    if (!registration_number || typeof registration_number !== 'string' || registration_number.trim().length === 0) {
      return errorResponse('Registration number is required.', 400, undefined, req);
    }

    if (!date_of_birth || typeof date_of_birth !== 'string') {
      return errorResponse('Date of birth is required.', 400, undefined, req);
    }

    if (!new_password || typeof new_password !== 'string') {
      return errorResponse('New password is required.', 400, undefined, req);
    }

    const cleanRegNo = registration_number.trim().toLowerCase();
    const identifierHash = await hashIdentifier(cleanRegNo);
    const clientIp = getClientIp(req);
    const adminClient = getAdminClient();
    const anonClient = getAnonClient();

    // 1. Evaluate Lockout Metrics
    const { data: metrics } = await adminClient.rpc('get_login_failure_metrics', {
      p_identifier_hash: identifierHash,
      p_ip: clientIp,
    });

    if (metrics?.is_locked) {
      return errorResponse(LOCKED_MESSAGE, 403, { is_locked: true }, req);
    }

    // 2. Query Student Master Record
    const { data: student, error: studentError } = await adminClient
      .from('students')
      .select('id, admission_number, registration_number, name, dob, status')
      .or(`registration_number.ilike.${cleanRegNo},admission_number.ilike.${cleanRegNo}`)
      .is('deleted_at', null)
      .maybeSingle();

    if (studentError || !student) {
      await adminClient.rpc('record_login_attempt', {
        p_identifier_hash: identifierHash,
        p_ip: clientIp,
        p_success: false,
      });
      return errorResponse(GENERIC_VERIFY_ERROR, 401, undefined, req);
    }

    if (student.status !== 'active') {
      return errorResponse(
        `Account cannot be activated. Current student status is: ${student.status}. Contact office.`,
        403,
        undefined,
        req
      );
    }

    // 3. Verify Date of Birth Mismatch
    const normalizedInputDob = normalizeDateOfBirth(date_of_birth);
    if (!normalizedInputDob || !student.dob || student.dob !== normalizedInputDob) {
      // Record failed attempt
      await adminClient.rpc('record_login_attempt', {
        p_identifier_hash: identifierHash,
        p_ip: clientIp,
        p_success: false,
      });

      // Update failed attempts on existing profile if one exists
      const { data: existingProf } = await adminClient
        .from('profiles')
        .select('user_id, failed_attempts')
        .eq('student_id', student.id)
        .maybeSingle();

      if (existingProf) {
        const newFailed = (existingProf.failed_attempts || 0) + 1;
        await adminClient
          .from('profiles')
          .update({
            failed_attempts: newFailed,
            locked_at: newFailed >= 5 ? new Date().toISOString() : null,
          })
          .eq('user_id', existingProf.user_id);
      }

      return errorResponse(GENERIC_VERIFY_ERROR, 401, undefined, req);
    }

    // 4. Check if Student is eligible for First Login / Password Initialization
    const { data: existingProfile } = await adminClient
      .from('profiles')
      .select('user_id, active, first_login_required, locked_at')
      .eq('student_id', student.id)
      .maybeSingle();

    if (existingProfile && !existingProfile.first_login_required) {
      return errorResponse(
        'This account is already initialized. Please log in directly with your password, or contact the college office to request a reset.',
        400,
        undefined,
        req
      );
    }

    // 5. Validate Password against MIPS Password Policy
    const passwordValidation = validatePassword(new_password, {
      registrationNumber: student.registration_number || student.admission_number,
      dob: student.dob,
      name: student.name,
    });

    if (!passwordValidation.valid) {
      return errorResponse(passwordValidation.reason || 'Password policy violation.', 400, undefined, req);
    }

    // 6. Generate Synthetic Student Email
    const standardReg = (student.registration_number || student.admission_number).toLowerCase().trim();
    const studentEmail = `${standardReg}@students.mips.invalid`;

    let targetUserId: string;

    if (existingProfile && existingProfile.user_id) {
      // User exists in auth and profile, updating password
      targetUserId = existingProfile.user_id;

      const { error: updateAuthError } = await adminClient.auth.admin.updateUserById(targetUserId, {
        password: new_password,
      });

      if (updateAuthError) {
        return errorResponse(`Failed to update password: ${updateAuthError.message}`, 500, undefined, req);
      }

      await adminClient
        .from('profiles')
        .update({
          first_login_required: false,
          must_change_password: false,
          failed_attempts: 0,
          locked_at: null,
          active: true,
          last_login_at: new Date().toISOString(),
        })
        .eq('user_id', targetUserId);

    } else {
      // First time provision in Supabase Auth
      const { data: authUser, error: createAuthError } = await adminClient.auth.admin.createUser({
        email: studentEmail,
        password: new_password,
        email_confirm: true,
        user_metadata: {
          role: 'student',
          name: student.name,
          registration_number: student.registration_number || student.admission_number,
        },
      });

      if (createAuthError || !authUser.user) {
        return errorResponse(`Failed to initialize account: ${createAuthError?.message}`, 500, undefined, req);
      }

      targetUserId = authUser.user.id;

      const { error: profileError } = await adminClient
        .from('profiles')
        .insert({
          user_id: targetUserId,
          role: 'student',
          student_id: student.id,
          teacher_id: null,
          active: true,
          must_change_password: false,
          first_login_required: false,
          failed_attempts: 0,
          last_login_at: new Date().toISOString(),
        });

      if (profileError) {
        await adminClient.auth.admin.deleteUser(targetUserId);
        return errorResponse(`Failed to link student profile: ${profileError.message}`, 500, undefined, req);
      }
    }

    // 7. Sign in immediately to provide live session
    const { data: sessionData, error: signInError } = await anonClient.auth.signInWithPassword({
      email: studentEmail,
      password: new_password,
    });

    if (signInError) {
      console.warn('First login sign-in warning:', signInError);
    }

    // 8. Record success in attempt tracking
    await adminClient.rpc('record_login_attempt', {
      p_identifier_hash: identifierHash,
      p_ip: clientIp,
      p_success: true,
    });

    // 9. Log Audit Entry
    await adminClient.from('audit_log').insert({
      table_name: 'students',
      record_id: student.id.toString(),
      action: 'UPDATE',
      new_data: {
        event: 'STUDENT_FIRST_LOGIN_INITIALIZED',
        student_id: student.id,
        user_id: targetUserId,
        registration_number: standardReg,
      },
      actor: targetUserId,
    });

    return jsonResponse(
      {
        success: true,
        message: 'Account successfully initialized and password set. You are now logged in.',
        session: sessionData?.session || null,
        student: {
          id: student.id,
          name: student.name,
          registration_number: standardReg,
          email: studentEmail,
        },
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
