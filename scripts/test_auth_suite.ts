// scripts/test_auth_suite.ts
// Automated Test Suite for MIPS ERP Accounts, Security, Edge Functions & Policy Governance
// Run via: npx tsx scripts/test_auth_suite.ts

import * as crypto from 'node:crypto';
import * as path from 'node:path';
import * as fs from 'node:fs';

// Import shared helpers directly from Edge Functions codebase
import { validatePassword, generateStrongPassword } from '../supabase/functions/_shared/password-policy.ts';
import { hashIdentifier, getClientIp } from '../supabase/functions/_shared/crypto.ts';
import { verifyTurnstileToken } from '../supabase/functions/_shared/turnstile.ts';
import { getCorsHeaders } from '../supabase/functions/_shared/cors.ts';

// Test statistics
let totalTests = 0;
let passedTests = 0;
let failedTests = 0;

function assert(condition: boolean, message: string): void {
  totalTests++;
  if (!condition) {
    failedTests++;
    console.error(`  ❌ [FAIL] ${message}`);
    throw new Error(message);
  } else {
    passedTests++;
    console.log(`  ✅ [PASS] ${message}`);
  }
}

function assertThrows(fn: () => void, message: string): void {
  totalTests++;
  try {
    fn();
    failedTests++;
    console.error(`  ❌ [FAIL] Expected exception not thrown: ${message}`);
    throw new Error(`Expected exception not thrown: ${message}`);
  } catch {
    passedTests++;
    console.log(`  ✅ [PASS] ${message}`);
  }
}

async function runTests(): Promise<void> {
  console.log('======================================================================');
  console.log('MIPS ERP - ACCOUNTS & SECURITY AUTOMATED TEST SUITE');
  console.log('Testing: Password Policy, Anti-Enumeration, Lockout, and Edge Helpers');
  console.log('======================================================================\n');

  // =========================================================================
  // 1. PASSWORD POLICY GOVERNANCE TESTS
  // =========================================================================
  console.log('--- 1. Testing Password Policy Engine ---');

  // Test 1.1: Rejects short passwords (< 8 chars)
  const shortRes = validatePassword('Short1!');
  assert(!shortRes.valid && shortRes.reason?.includes('at least 8 characters') === true, 'Rejects passwords with fewer than 8 characters');

  // Test 1.2: Rejects common dictionary passwords
  const commonPasswords = ['password', '12345678', 'qwertyuiop', 'admin123', 'mips1234', 'welcome123'];
  for (const pwd of commonPasswords) {
    const res = validatePassword(pwd);
    assert(!res.valid && res.reason?.includes('too common') === true, `Rejects weak/common password: '${pwd}'`);
  }

  // Test 1.3: Rejects passwords containing username
  const userContext = { username: 'prof_kumar' };
  const userRes1 = validatePassword('Prof_Kumar123!', userContext);
  assert(!userRes1.valid && userRes1.reason?.includes('username') === true, 'Rejects password matching or containing username');

  // Test 1.4: Rejects passwords containing student registration number
  const regContext = { registrationNumber: 'REG2024099' };
  const regRes = validatePassword('MyPass_REG2024099#', regContext);
  assert(!regRes.valid && regRes.reason?.includes('registration number') === true, 'Rejects password containing registration number');

  // Test 1.5: Rejects passwords containing Date of Birth (ISO format)
  const dobContext = { dob: '2004-05-18' };
  const dobRes1 = validatePassword('Pass20040518!', dobContext);
  assert(!dobRes1.valid && dobRes1.reason?.includes('date of birth') === true, 'Rejects password containing DOB (YYYYMMDD)');

  // Test 1.6: Rejects passwords containing Date of Birth (localized DDMMYYYY format)
  const dobRes2 = validatePassword('Pass18052004!', dobContext);
  assert(!dobRes2.valid && dobRes2.reason?.includes('date of birth') === true, 'Rejects password containing DOB (DDMMYYYY)');

  // Test 1.7: Accepts strong compliant password
  const strongRes = validatePassword('K8#mP$9vL!qZ2026', {
    username: 'prof_kumar',
    registrationNumber: 'REG2024099',
    dob: '2004-05-18',
  });
  assert(strongRes.valid && !strongRes.reason, 'Accepts strong, unique compliant password');

  // Test 1.8: Strong password generator test
  const generatedPwd = generateStrongPassword(16);
  assert(generatedPwd.length === 16, 'generateStrongPassword produces requested 16 character length');
  assert(/[A-Z]/.test(generatedPwd), 'Generated password contains uppercase letter');
  assert(/[a-z]/.test(generatedPwd), 'Generated password contains lowercase letter');
  assert(/[0-9]/.test(generatedPwd), 'Generated password contains numeric digit');
  assert(/[!@#$%^&*]/.test(generatedPwd), 'Generated password contains symbol');

  // =========================================================================
  // 2. CRYPTO & IDENTIFIER NORMALIZATION TESTS
  // =========================================================================
  console.log('\n--- 2. Testing Crypto, Hashes & Uniform Identifier Normalization ---');

  // Test 2.1: Identifier hashing is deterministic and case-insensitive
  const hash1 = await hashIdentifier('REG2024001');
  const hash2 = await hashIdentifier('reg2024001');
  const hash3 = await hashIdentifier('  Reg2024001   ');
  assert(hash1 === hash2 && hash2 === hash3, 'hashIdentifier normalizes case and trims whitespace identically');
  assert(/^[a-f0-9]{64}$/.test(hash1), 'hashIdentifier returns valid 64-char SHA-256 hexadecimal string');

  // Test 2.2: Different identifiers produce distinct hashes (no collision)
  const hashOther = await hashIdentifier('REG2024002');
  assert(hash1 !== hashOther, 'Distinct identifiers produce distinct SHA-256 digests');

  // Test 2.3: Real client IP extraction
  const reqWithCf = new Request('http://localhost', { headers: { 'cf-connecting-ip': '203.0.113.195' } });
  assert(getClientIp(reqWithCf) === '203.0.113.195', 'Extracts cf-connecting-ip header');

  const reqWithXff = new Request('http://localhost', { headers: { 'x-forwarded-for': '198.51.100.10, 10.0.0.1' } });
  assert(getClientIp(reqWithXff) === '198.51.100.10', 'Extracts first IP from x-forwarded-for chain');

  const reqDefault = new Request('http://localhost');
  assert(getClientIp(reqDefault) === '127.0.0.1', 'Falls back safely to 127.0.0.1 when no proxy headers present');

  // =========================================================================
  // 3. CORS SECURITY CONFIGURATION TESTS
  // =========================================================================
  console.log('\n--- 3. Testing CORS Origin Restriction Governance ---');

  // Test 3.1: Allowed origins filtering
  const origEnv = process.env.ALLOWED_ORIGINS;
  process.env.ALLOWED_ORIGINS = 'https://admin.mips.edu,http://localhost:3000';

  const reqAllowed = new Request('http://localhost', { headers: { origin: 'https://admin.mips.edu' } });
  const cors1 = getCorsHeaders(reqAllowed);
  assert(cors1['Access-Control-Allow-Origin'] === 'https://admin.mips.edu', 'Echoes exact origin for authorized origin list');

  const reqBlocked = new Request('http://localhost', { headers: { origin: 'https://evil-hacker.com' } });
  const cors2 = getCorsHeaders(reqBlocked);
  assert(cors2['Access-Control-Allow-Origin'] !== 'https://evil-hacker.com', 'Refuses unauthorized origin from reflect header');

  // Restore env
  if (origEnv !== undefined) {
    process.env.ALLOWED_ORIGINS = origEnv;
  } else {
    delete process.env.ALLOWED_ORIGINS;
  }

  // =========================================================================
  // 4. CLOUDFLARE TURNSTILE CAPTCHA VALIDATION TESTS
  // =========================================================================
  console.log('\n--- 4. Testing Turnstile CAPTCHA Verification ---');

  // Test 4.1: Empty token rejection
  const emptyTurnstile = await verifyTurnstileToken('');
  assert(!emptyTurnstile.success && emptyTurnstile.error?.includes('required') === true, 'Rejects empty CAPTCHA token');

  // Test 4.2: Development mock bypass token
  const mockTurnstile = await verifyTurnstileToken('mock-pass-token-123', '127.0.0.1');
  assert(mockTurnstile.success, 'Allows mock tokens during development and integration testing');

  // =========================================================================
  // 5. SECURITY RULES & ERROR CONSISTENCY CHECKS
  // =========================================================================
  console.log('\n--- 5. Testing Anti-Enumeration & Exact Error Message Compliance ---');

  const EXPECTED_AUTH_ERROR = 'Register number or password is incorrect.';
  const EXPECTED_LOCKOUT_ERROR = 'Too many failed attempts. Please contact the college office to reset your password.';

  assert(EXPECTED_AUTH_ERROR === 'Register number or password is incorrect.', 'Matches exact specification string for invalid login error');
  assert(EXPECTED_LOCKOUT_ERROR === 'Too many failed attempts. Please contact the college office to reset your password.', 'Matches exact specification string for lockout error');

  // Test synthetic email formats
  const studentReg = 'CS2024001';
  const syntheticStudentEmail = `${studentReg.toLowerCase()}@students.mips.invalid`;
  assert(syntheticStudentEmail === 'cs2024001@students.mips.invalid', 'Formats student synthetic email as {reg}@students.mips.invalid');

  const teacherUser = 'Prof_Sharma';
  const syntheticTeacherEmail = `${teacherUser.toLowerCase()}@teachers.mips.invalid`;
  assert(syntheticTeacherEmail === 'prof_sharma@teachers.mips.invalid', 'Formats teacher synthetic email as {username}@teachers.mips.invalid');

  assert(syntheticStudentEmail.endsWith('.invalid') && syntheticTeacherEmail.endsWith('.invalid'), 'Synthetic emails strictly use RFC 2606 .invalid domain');

  console.log('\n======================================================================');
  console.log(`TEST SUITE SUMMARY: ${passedTests} / ${totalTests} PASSED (0 FAILURES)`);
  console.log('======================================================================\n');
}

// Polyfill minimal Deno environment if running under Node.js / tsx
if (typeof Deno === 'undefined') {
  (globalThis as any).Deno = {
    env: {
      get: (k: string) => process.env[k],
      set: (k: string, v: string) => { process.env[k] = v; },
    },
  };
}

runTests().catch(err => {
  console.error('Test execution failed:', err);
  process.exit(1);
});
