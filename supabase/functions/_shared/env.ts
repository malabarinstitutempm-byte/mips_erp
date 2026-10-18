// supabase/functions/_shared/env.ts
// Universal Environment Variable Getter (Deno Edge Functions & Node.js/tsx)

export function getEnv(key: string): string | undefined {
  if (typeof Deno !== 'undefined' && Deno.env) {
    return Deno.env.get(key);
  }
  if (typeof process !== 'undefined' && process.env) {
    return process.env[key];
  }
  return undefined;
}
