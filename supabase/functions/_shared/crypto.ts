// supabase/functions/_shared/crypto.ts
// Crypto and Request Security Utilities

/**
 * Computes a standard SHA-256 hexadecimal hash of an identifier (email, username, reg no)
 * for uniform tracking without exposing raw identifiers.
 */
export async function hashIdentifier(identifier: string): Promise<string> {
  const normalized = identifier.trim().toLowerCase();
  const encoder = new TextEncoder();
  const data = encoder.encode(normalized);
  const hashBuffer = await crypto.subtle.digest('SHA-256', data);
  const hashArray = Array.from(new Uint8Array(hashBuffer));
  return hashArray.map(b => b.toString(16).padStart(2, '0')).join('');
}

/**
 * Extracts the real client IP address from request headers.
 */
export function getClientIp(req: Request): string {
  const cfConnectingIp = req.headers.get('cf-connecting-ip');
  if (cfConnectingIp) return cfConnectingIp.trim();

  const xForwardedFor = req.headers.get('x-forwarded-for');
  if (xForwardedFor) {
    const ips = xForwardedFor.split(',');
    return ips[0].trim();
  }

  const xRealIp = req.headers.get('x-real-ip');
  if (xRealIp) return xRealIp.trim();

  return '127.0.0.1';
}
