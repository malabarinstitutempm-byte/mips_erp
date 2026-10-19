// src/lib/supabase.ts
// Supabase Client Initialization for Portal App

import { createClient } from '@supabase/supabase-js';

const DEFAULT_SUPABASE_URL = 'https://evzehywyyqmcktszwmeg.supabase.co';
const DEFAULT_SUPABASE_ANON_KEY =
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImV2emVoeXd5eXFtY2t0c3p3bWVnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTE5NjM0MTYsImV4cCI6MjEwNzUzOTQxNn0.xNfdyP9f9if2INEdDdzGR4U04oItnt8XVhdM1-2Jnk4';

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL || DEFAULT_SUPABASE_URL;
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY || DEFAULT_SUPABASE_ANON_KEY;

export const supabase = createClient(supabaseUrl, supabaseAnonKey, {
  auth: {
    persistSession: true,
    autoRefreshToken: true,
    detectSessionInUrl: false,
  },
});
