// scripts/create_admin.ts
// CLI Utility to Bootstrap Administrator Accounts for MIPS ERP
// Usage: npx tsx scripts/create_admin.ts --email=admin@example.com --name="Principal"

import { createClient } from '@supabase/supabase-js';
import * as fs from 'node:fs';
import * as path from 'node:path';
import * as crypto from 'node:crypto';

/**
 * Loads .env file if available in the current or parent directories.
 */
function loadDotenv(): void {
  const envPaths = [
    path.resolve(process.cwd(), '.env'),
    path.resolve(process.cwd(), '..', '.env'),
  ];

  for (const envPath of envPaths) {
    if (fs.existsSync(envPath)) {
      try {
        const content = fs.readFileSync(envPath, 'utf8');
        for (const line of content.split('\n')) {
          const trimmed = line.trim();
          if (!trimmed || trimmed.startsWith('#')) continue;
          const equalIndex = trimmed.indexOf('=');
          if (equalIndex > 0) {
            const key = trimmed.slice(0, equalIndex).trim();
            const val = trimmed.slice(equalIndex + 1).trim().replace(/^["']|["']$/g, '');
            if (!process.env[key]) {
              process.env[key] = val;
            }
          }
        }
      } catch (err) {
        console.warn(`Could not read .env at ${envPath}:`, err);
      }
      break;
    }
  }
}

/**
 * Parses CLI flags like --email=admin@mips.edu or -e admin@mips.edu
 */
function parseArgs(args: string[]): Record<string, string> {
  const parsed: Record<string, string> = {};
  for (let i = 0; i < args.length; i++) {
    const arg = args[i];
    if (arg.startsWith('--')) {
      if (arg.includes('=')) {
        const [k, ...v] = arg.slice(2).split('=');
        parsed[k] = v.join('=');
      } else {
        const k = arg.slice(2);
        if (i + 1 < args.length && !args[i + 1].startsWith('-')) {
          parsed[k] = args[++i];
        } else {
          parsed[k] = 'true';
        }
      }
    } else if (arg.startsWith('-')) {
      const k = arg.slice(1);
      if (i + 1 < args.length && !args[i + 1].startsWith('-')) {
        parsed[k] = args[++i];
      }
    }
  }
  return parsed;
}

/**
 * Generates a high-entropy temporary password for initial admin login.
 */
function generateSecurePassword(length = 16): string {
  const upper = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
  const lower = 'abcdefghijkmnopqrstuvwxyz';
  const digits = '23456789';
  const symbols = '!@#$%^&*_-+=';
  const all = upper + lower + digits + symbols;

  const bytes = crypto.randomBytes(length);
  const chars = [
    upper[bytes[0] % upper.length],
    lower[bytes[1] % lower.length],
    digits[bytes[2] % digits.length],
    symbols[bytes[3] % symbols.length],
  ];

  for (let i = 4; i < length; i++) {
    chars.push(all[bytes[i] % all.length]);
  }

  // Fisher-Yates shuffle
  for (let i = chars.length - 1; i > 0; i--) {
    const j = bytes[i] % (i + 1);
    [chars[i], chars[j]] = [chars[j], chars[i]];
  }

  return chars.join('');
}

async function main(): Promise<void> {
  loadDotenv();

  const args = parseArgs(process.argv.slice(2));
  const email = (args.email || args.e || '').trim();
  const name = (args.name || args.n || 'Administrator').trim();
  const explicitPassword = args.password || args.p;

  if (!email || !email.includes('@')) {
    console.error('Error: A valid administrator email address is required.');
    console.error('Usage: npx tsx scripts/create_admin.ts --email=admin@example.com --name="Principal" [--password="..."]');
    process.exit(1);
  }

  if (email.toLowerCase().endsWith('.invalid')) {
    console.error('Error: Administrators must use real emails. The .invalid domain is reserved for synthetic student/teacher accounts.');
    process.exit(1);
  }

  const supabaseUrl = process.env.SUPABASE_URL;
  const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

  if (!supabaseUrl || !serviceRoleKey) {
    console.error('Error: Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY.');
    console.error('Please define these in your environment or in a .env file.');
    process.exit(1);
  }

  const supabase = createClient(supabaseUrl, serviceRoleKey, {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
  });

  const temporaryPassword = explicitPassword && explicitPassword.length >= 8
    ? explicitPassword
    : generateSecurePassword(16);

  console.log(`Connecting to Supabase at: ${supabaseUrl}`);

  // 1. Check if auth user already exists
  let userId: string;
  const cleanEmail = email.toLowerCase();

  const { data: listData, error: listError } = await supabase.auth.admin.listUsers();
  if (listError) {
    console.error('Failed to query existing auth users:', listError.message);
    process.exit(1);
  }

  const existingUser = listData.users.find(u => u.email?.toLowerCase() === cleanEmail);

  if (existingUser) {
    console.log(`User '${cleanEmail}' already exists in auth.users (${existingUser.id}). Resetting credentials...`);
    userId = existingUser.id;

    const { error: updateError } = await supabase.auth.admin.updateUserById(userId, {
      password: temporaryPassword,
      email_confirm: true,
      user_metadata: {
        role: 'admin',
        name,
      },
    });

    if (updateError) {
      console.error('Failed to update auth user:', updateError.message);
      process.exit(1);
    }
  } else {
    console.log(`Creating new auth user for '${cleanEmail}'...`);
    const { data: newUser, error: createError } = await supabase.auth.admin.createUser({
      email: cleanEmail,
      password: temporaryPassword,
      email_confirm: true,
      user_metadata: {
        role: 'admin',
        name,
      },
    });

    if (createError || !newUser.user) {
      console.error('Failed to create auth user:', createError?.message);
      process.exit(1);
    }

    userId = newUser.user.id;
  }

  // 2. Upsert profile with role = admin, active = true, must_change_password = true
  const { error: profileError } = await supabase
    .from('profiles')
    .upsert(
      {
        user_id: userId,
        role: 'admin',
        active: true,
        must_change_password: true,
        first_login_required: false,
        failed_attempts: 0,
        locked_at: null,
        updated_at: new Date().toISOString(),
      },
      { onConflict: 'user_id' }
    );

  if (profileError) {
    console.error('Failed to upsert administrator profile:', profileError.message);
    process.exit(1);
  }

  // 3. Structured audit logging (Zero secrets in log)
  try {
    await supabase.from('audit_log').insert({
      table_name: 'profiles',
      record_id: userId,
      action: 'ADMIN_BOOTSTRAP',
      new_data: {
        event: 'ADMIN_ACCOUNT_BOOTSTRAPPED',
        email: cleanEmail,
        name,
        target_user_id: userId,
      },
      actor: userId,
    });
  } catch (auditErr) {
    console.warn('Audit logging note:', auditErr);
  }

  // 4. Output results to stdout (Printed ONCE)
  console.log('\n======================================================================');
  console.log('MIPS ERP - Administrative Account Provisioned Successfully');
  console.log('======================================================================');
  console.log(`User ID:              ${userId}`);
  console.log(`Name:                 ${name}`);
  console.log(`Email:                ${cleanEmail}`);
  console.log(`Role:                 admin`);
  console.log(`Must Change Password: true`);
  console.log(`Temporary Password:   ${temporaryPassword}`);
  console.log('======================================================================');
  console.log('[SECURITY NOTICE]');
  console.log('- Record this temporary password now. It will never be displayed again.');
  console.log('- The administrator will be required to change this password on first login.');
  console.log('- Never commit service-role keys or passwords to version control.');
  console.log('======================================================================\n');
}

main().catch(err => {
  console.error('Fatal bootstrap error:', err);
  process.exit(1);
});
