// supabase/functions/login/index.ts
// Secure Login Endpoint with Brute-Force Protection, Sliding Window Lockout & Turnstile CAPTCHA

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { handleCors } from '../_shared/cors.ts';
import { getAdminClient, getAnonClient } from '../_shared/supabase-client.ts';
import { jsonResponse, errorResponse } from '../_shared/response.ts';
import { hashIdentifier, getClientIp } from '../_shared/crypto.ts';
import { verifyTurnstileToken } from '../_shared/turnstile.ts';

const LOCKED_MESSAGE = 'Too many failed attempts. Please contact the college office to reset your password.';
const GENERIC_AUTH_ERROR = 'Register number or password is incorrect.';

interface LoginPayload {
  identifier: string;
  password: string;
  captcha_token?: string;
}

serve(async (req: Request) => {
  const corsResponse = handleCors(req);
  if (corsResponse) return corsResponse;

  if (req.method !== 'POST') {
    return errorResponse('Method not allowed. Use POST.', 405, undefined, req);
  }

  try {
    const body: LoginPayload = await req.json().catch(() => ({}));
    const { identifier, password, captcha_token } = body;

    if (!identifier || typeof identifier !== 'string' || identifier.trim().length === 0) {
      return errorResponse('Registration number, username, or email is required.', 400, undefined, req);
    }

    if (!password || typeof password !== 'string') {
      return errorResponse('Password is required.', 400, undefined, req);
    }

    const cleanIdentifier = identifier.trim().toLowerCase();
    const identifierHash = await hashIdentifier(cleanIdentifier);
    const clientIp = getClientIp(req);
    const adminClient = getAdminClient();
    const anonClient = getAnonClient();

    // 1. Evaluate Current Lockout & CAPTCHA Thresholds
    const { data: metrics, error: metricsError } = await adminClient.rpc('get_login_failure_metrics', {
      p_identifier_hash: identifierHash,
      p_ip: clientIp,
    });

    if (metricsError) {
      console.error('Error fetching login metrics:', metricsError);
    }

    if (metrics?.is_locked) {
      return errorResponse(LOCKED_MESSAGE, 403, { is_locked: true }, req);
    }

    if (metrics?.requires_captcha) {
      if (!captcha_token) {
        return errorResponse(
          'Security verification required. Please complete the CAPTCHA.',
          400,
          { requires_captcha: true },
          req
        );
      }

      const turnstile = await verifyTurnstileToken(captcha_token, clientIp);
      if (!turnstile.success) {
        return errorResponse(
          turnstile.error || 'CAPTCHA verification failed.',
          400,
          { requires_captcha: true },
          req
        );
      }
    }

    // 2. Resolve Auth Synthetic or Real Email
    let authEmail = cleanIdentifier;
    let resolvedRole: 'admin' | 'teacher' | 'student' | null = null;
    let targetProfileId: string | null = null;

    if (cleanIdentifier.includes('@')) {
      // Real email (used by admins or direct email login)
      authEmail = cleanIdentifier;
      const { data: userProfList } = await adminClient.rpc('get_profile_by_email', {
        p_email: cleanIdentifier,
      });

      const userProf = Array.isArray(userProfList) && userProfList.length > 0 ? userProfList[0] : null;

      if (userProf) {
        targetProfileId = userProf.user_id;
        resolvedRole = userProf.role;
      }
    } else {
      // Check teachers table first
      const { data: teacher } = await adminClient
        .from('teachers')
        .select('id, login_username, status')
        .ilike('login_username', cleanIdentifier)
        .maybeSingle();

      if (teacher) {
        authEmail = `${teacher.login_username.toLowerCase()}@teachers.mips.invalid`;
        resolvedRole = 'teacher';
        const { data: prof } = await adminClient
          .from('profiles')
          .select('user_id, active, locked_at, failed_attempts')
          .eq('teacher_id', teacher.id)
          .maybeSingle();
        if (prof) targetProfileId = prof.user_id;
      } else {
        // Check students table (by registration_number or admission_number)
        const { data: student } = await adminClient
          .from('students')
          .select('id, registration_number, admission_number, status')
          .or(`registration_number.ilike.${cleanIdentifier},admission_number.ilike.${cleanIdentifier}`)
          .is('deleted_at', null)
          .maybeSingle();

        if (student) {
          const regNumber = (student.registration_number || student.admission_number).toLowerCase();
          authEmail = `${regNumber}@students.mips.invalid`;
          resolvedRole = 'student';
          const { data: prof } = await adminClient
            .from('profiles')
            .select('user_id, active, locked_at, failed_attempts')
            .eq('student_id', student.id)
            .maybeSingle();
          if (prof) targetProfileId = prof.user_id;
        } else {
          // Unknown identifier: use synthetic student format so attempt fails authentically
          authEmail = `${cleanIdentifier.replace(/[^a-z0-9]/g, '')}@students.mips.invalid`;
        }
      }
    }

    // 3. Check if Resolved Profile is already explicitly locked or deactivated
    if (targetProfileId) {
      const { data: existingProf } = await adminClient
        .from('profiles')
        .select('active, locked_at, failed_attempts')
        .eq('user_id', targetProfileId)
        .single();

      if (existingProf && (!existingProf.active || existingProf.locked_at !== null)) {
        await adminClient.rpc('record_login_attempt', {
          p_identifier_hash: identifierHash,
          p_ip: clientIp,
          p_success: false,
        });
        return errorResponse(LOCKED_MESSAGE, 403, { is_locked: true }, req);
      }
    }

    // 4. Authenticate Credentials via Supabase Auth
    const { data: authData, error: signInError } = await anonClient.auth.signInWithPassword({
      email: authEmail,
      password,
    });

    if (signInError || !authData.user) {
      // Record failure uniformly for both known and unknown identifiers
      await adminClient.rpc('record_login_attempt', {
        p_identifier_hash: identifierHash,
        p_ip: clientIp,
        p_success: false,
      });

      // If user profile is identified, increment failed attempts in profiles
      if (targetProfileId) {
        const { data: currentProf } = await adminClient
          .from('profiles')
          .select('failed_attempts')
          .eq('user_id', targetProfileId)
          .single();

        const newFailed = (currentProf?.failed_attempts || 0) + 1;
        const shouldLock = newFailed >= 5;

        await adminClient
          .from('profiles')
          .update({
            failed_attempts: newFailed,
            locked_at: shouldLock ? new Date().toISOString() : null,
          })
          .eq('user_id', targetProfileId);
      }

      // Re-evaluate metrics to decide response
      const { data: updatedMetrics } = await adminClient.rpc('get_login_failure_metrics', {
        p_identifier_hash: identifierHash,
        p_ip: clientIp,
      });

      if (updatedMetrics?.is_locked) {
        return errorResponse(LOCKED_MESSAGE, 403, { is_locked: true }, req);
      }

      return errorResponse(
        GENERIC_AUTH_ERROR,
        401,
        {
          requires_captcha: updatedMetrics?.requires_captcha ?? false,
          attempts_remaining: updatedMetrics?.attempts_remaining ?? 0,
        },
        req
      );
    }

    // 5. Successful Auth Credentials: Validate Profile Status
    const { data: profile, error: profileError } = await adminClient
      .from('profiles')
      .select('user_id, role, active, must_change_password, first_login_required, locked_at, access_until')
      .eq('user_id', authData.user.id)
      .single();

    if (profileError || !profile || !profile.active || profile.locked_at !== null) {
      // Account deactivated or locked
      await adminClient.rpc('record_login_attempt', {
        p_identifier_hash: identifierHash,
        p_ip: clientIp,
        p_success: false,
      });
      return errorResponse(LOCKED_MESSAGE, 403, { is_locked: true }, req);
    }

    // Phase 9E: Reject completed students whose access_until window has expired
    if (profile.role === 'student' && profile.access_until) {
      const todayStr = new Date().toISOString().split('T')[0];
      if (profile.access_until < todayStr) {
        await adminClient.rpc('record_login_attempt', {
          p_identifier_hash: identifierHash,
          p_ip: clientIp,
          p_success: false,
        });
        return errorResponse(
          'Your access has ended. Please contact the college office.',
          403,
          { access_ended: true },
          req
        );
      }
    }

    // 6. Reset Failed Attempts and Record Successful Attempt
    await adminClient.rpc('record_login_attempt', {
      p_identifier_hash: identifierHash,
      p_ip: clientIp,
      p_success: true,
    });

    await adminClient
      .from('profiles')
      .update({
        failed_attempts: 0,
        locked_at: null,
        last_login_at: new Date().toISOString(),
      })
      .eq('user_id', authData.user.id);

    // 7. Check if Admin MFA is required
    let mfaRequired = false;
    if (profile.role === 'admin') {
      const { data: mfaSetting } = await adminClient
        .from('settings')
        .select('value')
        .eq('key', 'require_admin_mfa')
        .maybeSingle();

      if (mfaSetting?.value === 'true') {
        mfaRequired = true;
      }
    }

    return jsonResponse(
      {
        success: true,
        message: 'Login successful.',
        session: authData.session,
        user: {
          id: authData.user.id,
          email: authData.user.email,
          role: profile.role,
          must_change_password: profile.must_change_password,
          first_login_required: profile.first_login_required,
          mfa_required: mfaRequired,
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
