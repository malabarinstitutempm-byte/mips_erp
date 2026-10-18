// supabase/functions/_shared/password-policy.ts
// Strict Password Governance for MIPS ERP

const COMMON_PASSWORDS = new Set([
  'password',
  'password123',
  '12345678',
  '123456789',
  '1234567890',
  'qwertyuiop',
  'qwerty123',
  'admin123',
  'admin@123',
  'mips1234',
  'mips@1234',
  'welcome1',
  'welcome123',
  'college123',
  'student123',
  'teacher123',
  'iloveyou',
  'changeme',
  'abc12345',
  'letmein1',
]);

export interface PasswordContext {
  username?: string;
  registrationNumber?: string;
  dob?: string;
  name?: string;
}

export interface PasswordValidationResult {
  valid: boolean;
  reason?: string;
}

/**
 * Validates a password according to MIPS ERP security policy:
 * 1. Minimum 8 characters.
 * 2. Not equal to or containing username (if provided).
 * 3. Not equal to or containing registration number (if provided).
 * 4. Not equal to or containing date of birth in standard formats (if provided).
 * 5. Rejects common / dictionary passwords.
 */
export function validatePassword(
  password: string,
  context?: PasswordContext
): PasswordValidationResult {
  if (!password || typeof password !== 'string') {
    return { valid: false, reason: 'Password is required.' };
  }

  if (password.length < 8) {
    return { valid: false, reason: 'Password must be at least 8 characters in length.' };
  }

  const lowerPwd = password.toLowerCase();

  // Reject common passwords
  if (COMMON_PASSWORDS.has(lowerPwd)) {
    return {
      valid: false,
      reason: 'Password is too common and easily guessed. Please choose a more complex password.',
    };
  }

  if (context) {
    // Check username
    if (context.username && context.username.trim().length >= 3) {
      const u = context.username.trim().toLowerCase();
      if (lowerPwd === u || lowerPwd.includes(u)) {
        return {
          valid: false,
          reason: 'Password cannot contain or match your username.',
        };
      }
    }

    // Check registration number
    if (context.registrationNumber && context.registrationNumber.trim().length >= 3) {
      const r = context.registrationNumber.trim().toLowerCase();
      if (lowerPwd === r || lowerPwd.includes(r)) {
        return {
          valid: false,
          reason: 'Password cannot contain or match your registration number.',
        };
      }
    }

    // Check date of birth
    if (context.dob && context.dob.trim().length >= 4) {
      const dobRaw = context.dob.trim();
      const dobDigits = dobRaw.replace(/\D/g, ''); // e.g. 20040518

      if (dobDigits.length >= 6) {
        if (lowerPwd.includes(dobDigits) || lowerPwd.includes(dobRaw)) {
          return {
            valid: false,
            reason: 'Password cannot contain your date of birth.',
          };
        }

        // Also test reverse format (DDMMYYYY vs YYYYMMDD)
        if (dobDigits.length === 8) {
          const yyyymmdd = dobDigits;
          const ddmmyyyy = dobDigits.slice(6, 8) + dobDigits.slice(4, 6) + dobDigits.slice(0, 4);
          if (lowerPwd.includes(yyyymmdd) || lowerPwd.includes(ddmmyyyy)) {
            return {
              valid: false,
              reason: 'Password cannot contain your date of birth.',
            };
          }
        }
      }
    }
  }

  return { valid: true };
}

/**
 * Generates a cryptographically strong random temporary password.
 */
export function generateStrongPassword(length = 12): string {
  const upper = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
  const lower = 'abcdefghijkmnopqrstuvwxyz';
  const digits = '23456789';
  const symbols = '!@#$%^&*';
  const all = upper + lower + digits + symbols;

  const array = new Uint32Array(length);
  crypto.getRandomValues(array);

  // Ensure at least one of each required character class
  const passwordChars = [
    upper[array[0] % upper.length],
    lower[array[1] % lower.length],
    digits[array[2] % digits.length],
    symbols[array[3] % symbols.length],
  ];

  for (let i = 4; i < length; i++) {
    passwordChars.push(all[array[i] % all.length]);
  }

  // Shuffle array using Fisher-Yates
  for (let i = passwordChars.length - 1; i > 0; i--) {
    const j = array[i] % (i + 1);
    [passwordChars[i], passwordChars[j]] = [passwordChars[j], passwordChars[i]];
  }

  return passwordChars.join('');
}
