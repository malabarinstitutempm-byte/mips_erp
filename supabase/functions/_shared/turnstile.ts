// supabase/functions/_shared/turnstile.ts
// Cloudflare Turnstile CAPTCHA Verification

import { getEnv } from './env.ts';

export interface TurnstileVerificationResult {
  success: boolean;
  error?: string;
}

/**
 * Validates a Cloudflare Turnstile CAPTCHA token.
 * If CLOUDFLARE_TURNSTILE_SECRET_KEY is not set (e.g. dev or testing),
 * allows mock tokens or logs a warning.
 */
export async function verifyTurnstileToken(
  token: string | null | undefined,
  remoteIp?: string
): Promise<TurnstileVerificationResult> {
  if (!token || typeof token !== 'string' || token.trim().length === 0) {
    return { success: false, error: 'CAPTCHA token is required.' };
  }

  const secretKey = getEnv('CLOUDFLARE_TURNSTILE_SECRET_KEY');

  // In test / development without Turnstile configured, allow dummy test tokens
  if (!secretKey) {
    if (token === 'bypass-turnstile-dev' || token.startsWith('mock-')) {
      return { success: true };
    }
    // If no secret key is set at all, treat as development mode pass-through
    console.warn('CLOUDFLARE_TURNSTILE_SECRET_KEY not set. Allowing CAPTCHA token in development.');
    return { success: true };
  }

  try {
    const formData = new FormData();
    formData.append('secret', secretKey);
    formData.append('response', token);
    if (remoteIp) {
      formData.append('remoteip', remoteIp);
    }

    const response = await fetch('https://challenges.cloudflare.com/turnstile/v0/siteverify', {
      method: 'POST',
      body: formData,
    });

    const result = await response.json();

    if (result.success) {
      return { success: true };
    }

    return {
      success: false,
      error: `CAPTCHA verification failed: ${result['error-codes'] ? result['error-codes'].join(', ') : 'invalid-input-response'}`,
    };
  } catch (err) {
    return {
      success: false,
      error: `Failed to contact Turnstile verification service: ${err instanceof Error ? err.message : String(err)}`,
    };
  }
}
