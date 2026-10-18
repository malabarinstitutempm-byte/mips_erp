// supabase/functions/_shared/auth-guard.ts
// Security Guard & Role Enforcement for Supabase Edge Functions

import { getUserClient, getAdminClient } from './supabase-client.ts';
import { errorResponse } from './response.ts';

export interface AdminAuthContext {
  userId: string;
  userEmail: string;
  role: 'admin';
  adminClient: ReturnType<typeof getAdminClient>;
}

export interface UserAuthContext {
  userId: string;
  userEmail?: string;
  role: 'admin' | 'teacher' | 'student';
  profile: Record<string, unknown>;
  adminClient: ReturnType<typeof getAdminClient>;
}

/**
 * Extracts and decodes JWT payload claims (such as aal) safely without external crypto libraries.
 */
function parseJwtClaims(token: string): Record<string, unknown> {
  try {
    const parts = token.split('.');
    if (parts.length !== 3) return {};
    const payloadBase64 = parts[1].replace(/-/g, '+').replace(/_/g, '/');
    const jsonStr = atob(payloadBase64);
    return JSON.parse(jsonStr);
  } catch {
    return {};
  }
}

/**
 * Verifies that the caller has a valid session, is an active administrator,
 * and satisfies AAL2 requirements if require_admin_mfa is enabled in settings.
 */
export async function requireAdmin(
  req: Request
): Promise<{ errorResponse?: Response; auth?: AdminAuthContext }> {
  const authHeader = req.headers.get('Authorization');
  if (!authHeader) {
    return {
      errorResponse: errorResponse('Missing or invalid Authorization header.', 401, undefined, req),
    };
  }

  const token = authHeader.replace(/^Bearer\s+/i, '').trim();
  const userClient = getUserClient(authHeader);

  // 1. Verify token with Supabase Auth
  const { data: { user }, error: authError } = await userClient.auth.getUser();
  if (authError || !user) {
    return {
      errorResponse: errorResponse('Unauthorized: Invalid or expired session token.', 401, undefined, req),
    };
  }

  const adminClient = getAdminClient();

  // 2. Fetch profile
  const { data: profile, error: profileError } = await adminClient
    .from('profiles')
    .select('role, active')
    .eq('user_id', user.id)
    .maybeSingle();

  if (profileError || !profile || profile.role !== 'admin' || !profile.active) {
    // Return generic error; never reveal whether an account exists
    return {
      errorResponse: errorResponse('Access denied. Administrator privileges required.', 403, undefined, req),
    };
  }

  // 3. Inspect MFA Setting
  const { data: mfaSetting } = await adminClient
    .from('settings')
    .select('value')
    .eq('key', 'require_admin_mfa')
    .maybeSingle();

  if (mfaSetting?.value === 'true') {
    const claims = parseJwtClaims(token);
    const aal = claims.aal;
    if (aal !== 'aal2') {
      return {
        errorResponse: errorResponse(
          'Multi-Factor Authentication (AAL2) is required for administrative operations.',
          403,
          { mfa_required: true },
          req
        ),
      };
    }
  }

  return {
    auth: {
      userId: user.id,
      userEmail: user.email || '',
      role: 'admin',
      adminClient,
    },
  };
}

/**
 * Verifies that the caller has any valid, active session (admin, teacher, or student).
 */
export async function requireActiveUser(
  req: Request
): Promise<{ errorResponse?: Response; auth?: UserAuthContext }> {
  const authHeader = req.headers.get('Authorization');
  if (!authHeader) {
    return {
      errorResponse: errorResponse('Missing or invalid Authorization header.', 401, undefined, req),
    };
  }

  const userClient = getUserClient(authHeader);
  const { data: { user }, error: authError } = await userClient.auth.getUser();

  if (authError || !user) {
    return {
      errorResponse: errorResponse('Unauthorized: Invalid or expired session token.', 401, undefined, req),
    };
  }

  const adminClient = getAdminClient();
  const { data: profile, error: profileError } = await adminClient
    .from('profiles')
    .select('*')
    .eq('user_id', user.id)
    .maybeSingle();

  if (profileError || !profile || !profile.active) {
    return {
      errorResponse: errorResponse('Account is disabled or inactive.', 403, undefined, req),
    };
  }

  return {
    auth: {
      userId: user.id,
      userEmail: user.email,
      role: profile.role,
      profile,
      adminClient,
    },
  };
}
