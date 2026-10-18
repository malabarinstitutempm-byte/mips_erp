// supabase/functions/_shared/supabase-client.ts
// Standard Supabase Client Factory for Edge Functions

import { createClient, SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.45.4';
import { getEnv } from './env.ts';

/**
 * Creates an elevated Supabase client with the service role key.
 * Used strictly for admin operations (creating users, setting auth passwords, logging audits).
 * Lives ONLY in Edge Function execution contexts.
 */
export function getAdminClient(): SupabaseClient {
  const supabaseUrl = getEnv('SUPABASE_URL');
  const serviceRoleKey = getEnv('SUPABASE_SERVICE_ROLE_KEY');

  if (!supabaseUrl || !serviceRoleKey) {
    throw new Error('Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY environment variables.');
  }

  return createClient(supabaseUrl, serviceRoleKey, {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
  });
}

/**
 * Creates an unauthenticated Supabase client with the anon public key.
 * Used for verifying credentials via auth.signInWithPassword without service role privileges.
 */
export function getAnonClient(): SupabaseClient {
  const supabaseUrl = getEnv('SUPABASE_URL');
  const anonKey = getEnv('SUPABASE_ANON_KEY');

  if (!supabaseUrl || !anonKey) {
    throw new Error('Missing SUPABASE_URL or SUPABASE_ANON_KEY environment variables.');
  }

  return createClient(supabaseUrl, anonKey, {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
  });
}

/**
 * Creates a client scoped to the caller's JWT token.
 * Used to verify the identity and permissions of the request sender.
 */
export function getUserClient(authHeader: string | null): SupabaseClient {
  const supabaseUrl = getEnv('SUPABASE_URL');
  const anonKey = getEnv('SUPABASE_ANON_KEY');

  if (!supabaseUrl || !anonKey) {
    throw new Error('Missing SUPABASE_URL or SUPABASE_ANON_KEY environment variables.');
  }

  return createClient(supabaseUrl, anonKey, {
    global: {
      headers: authHeader ? { Authorization: authHeader } : {},
    },
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
  });
}
