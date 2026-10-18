// src/lib/passwordPolicy.ts
// Client-side password validation matching institutional policy

export interface PasswordCheckResult {
  isValid: boolean;
  rules: {
    length: boolean;
    notUsername: boolean;
    notRegNo: boolean;
    notDob: boolean;
  };
  errors: string[];
}

export function evaluatePasswordPolicy(
  password: string,
  context?: {
    username?: string;
    registrationNumber?: string;
    dob?: string;
  }
): PasswordCheckResult {
  const p = password || '';
  const length = p.length >= 8;

  let notUsername = true;
  if (context?.username && context.username.trim().length >= 3) {
    if (p.toLowerCase().includes(context.username.trim().toLowerCase())) {
      notUsername = false;
    }
  }

  let notRegNo = true;
  if (context?.registrationNumber && context.registrationNumber.trim().length >= 3) {
    const cleanReg = context.registrationNumber.trim().toLowerCase().replace(/[^a-z0-9]/g, '');
    const cleanPass = p.toLowerCase().replace(/[^a-z0-9]/g, '');
    if (cleanPass.includes(cleanReg)) {
      notRegNo = false;
    }
  }

  let notDob = true;
  if (context?.dob) {
    // Check parts of DOB (e.g. YYYY, DDMM, etc.)
    const cleanDobDigits = context.dob.replace(/\D/g, '');
    if (cleanDobDigits.length >= 4 && p.includes(cleanDobDigits.slice(-4))) {
      // contains birth year
      notDob = false;
    }
    if (cleanDobDigits.length >= 8 && p.includes(cleanDobDigits)) {
      notDob = false;
    }
  }

  const errors: string[] = [];
  if (!length) errors.push('Must be at least 8 characters long');
  if (!notUsername) errors.push('Must not contain your username');
  if (!notRegNo) errors.push('Must not contain your register number');
  if (!notDob) errors.push('Must not contain your date of birth or birth year');

  return {
    isValid: length && notUsername && notRegNo && notDob,
    rules: {
      length,
      notUsername,
      notRegNo,
      notDob,
    },
    errors,
  };
}
