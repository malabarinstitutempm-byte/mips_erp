// portal/scripts/test-perf-budgets.mjs
// Automated Performance Budget Regression Test Suite
// Verifies that request counts and payload sizes per screen do not exceed free-plan budget limits.

import { createClient } from '@supabase/supabase-js';

const SUPABASE_URL = process.env.VITE_SUPABASE_URL || 'https://evzehywyyqmcktszwmeg.supabase.co';
const SUPABASE_ANON_KEY =
  process.env.VITE_SUPABASE_ANON_KEY ||
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImV2emVoeXd5eXFtY2t0c3p3bWVnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTE5NjM0MTYsImV4cCI6MjEwNzUzOTQxNn0.xNfdyP9f9if2INEdDdzGR4U04oItnt8XVhdM1-2Jnk4';

// Screen budgets (free-tier budget targets)
export const SCREEN_BUDGETS = {
  'Auth: Login': { maxRequests: 1, maxPayloadBytes: 4096 },
  'Student: Initial Load': { maxRequests: 1, maxPayloadBytes: 8192 },
  'Student: Attendance Tab': { maxRequests: 1, maxPayloadBytes: 15360 },
  'Student: Results Tab': { maxRequests: 1, maxPayloadBytes: 15360 },
  'Student: Fees Tab': { maxRequests: 1, maxPayloadBytes: 15360 },
  'Student: Timetable Tab': { maxRequests: 1, maxPayloadBytes: 8192 },
  'Student: Notifications': { maxRequests: 1, maxPayloadBytes: 8192 },
  'Teacher: Initial Load': { maxRequests: 1, maxPayloadBytes: 8192 },
  'Teacher: Mark Attendance (Load)': { maxRequests: 2, maxPayloadBytes: 15360 },
  'Teacher: Mark Attendance (Submit)': { maxRequests: 1, maxPayloadBytes: 4096 },
  'Teacher: Mark Entry (Load)': { maxRequests: 2, maxPayloadBytes: 15360 },
  'Admin: Dashboard': { maxRequests: 1, maxPayloadBytes: 8192 },
  'Admin: Student List (Page)': { maxRequests: 1, maxPayloadBytes: 25600 },
  'Admin: Fee Collection': { maxRequests: 2, maxPayloadBytes: 15360 },
  'Admin: Reports': { maxRequests: 1, maxPayloadBytes: 25600 },
  'Admin: Promotion Preview': { maxRequests: 1, maxPayloadBytes: 15360 },
  'Admin: Announcements': { maxRequests: 1, maxPayloadBytes: 8192 },
  'Admin: Timetable': { maxRequests: 1, maxPayloadBytes: 8192 },
};

let currentScreen = 'Init';
const metrics = {};

function instrumentedFetch(baseFetch = fetch) {
  return async (input, init) => {
    const urlStr = typeof input === 'string' ? input : input instanceof URL ? input.toString() : input.url;
    const response = await baseFetch(input, init);
    const clone = response.clone();
    let bytes = 0;
    try {
      const text = await clone.text();
      bytes = Buffer.byteLength(text);
    } catch (_) {
      const cl = response.headers.get('content-length');
      if (cl) bytes = parseInt(cl, 10);
    }

    if (!metrics[currentScreen]) {
      metrics[currentScreen] = { requests: 0, bytes: 0 };
    }
    metrics[currentScreen].requests++;
    metrics[currentScreen].bytes += bytes;
    return response;
  };
}

const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
  global: { fetch: instrumentedFetch(fetch) },
});

export async function runPerfBudgetCheck() {
  console.log('===============================================================');
  console.log('         MIPS ERP: PER-SCREEN REQUEST BUDGET AUDIT             ');
  console.log('===============================================================\n');

  // Simulate current application screen behaviors:
  currentScreen = 'Auth: Login';
  await supabase.from('admin_accounts').select('id, full_name, username, role, password, active').eq('username', 'admin').maybeSingle();

  currentScreen = 'Student: Initial Load';
  await supabase.from('student_profile_view').select('*').limit(1);
  await supabase.from('student_enrollments').select('*, courses(*)').limit(5);

  currentScreen = 'Student: Attendance Tab';
  await supabase.from('student_enrollments').select('id, course_id, batch_id, status').limit(2);
  await supabase.from('students').select('batch_id').limit(1);
  await supabase.from('batch_periods').select('*').limit(5);
  await supabase.from('attendance_records').select('id, session_id, status, remarks').limit(50);
  await supabase.from('attendance_sessions').select('id, batch_id, date, slot, status').limit(50);

  currentScreen = 'Student: Results Tab';
  await supabase.from('results').select('*').limit(10);
  await supabase.from('marks').select('*').limit(50);

  currentScreen = 'Student: Fees Tab';
  await supabase.from('fees').select('*').limit(1);
  await supabase.from('fee_items').select('*').limit(10);
  await supabase.from('payments').select('*').limit(10);

  currentScreen = 'Student: Timetable Tab';
  await supabase.from('daily_timetables').select('*').limit(2);
  await supabase.from('daily_timetable_entries').select('*').limit(10);

  currentScreen = 'Student: Notifications';
  await supabase.from('notifications').select('*').limit(20);

  currentScreen = 'Teacher: Initial Load';
  await supabase.from('teachers').select('*').limit(1);
  await supabase.from('batches').select('id, name, course_id').limit(10);
  await supabase.from('courses').select('id, name, code').limit(10);

  currentScreen = 'Teacher: Mark Attendance (Load)';
  await supabase.from('attendance_sessions').select('*').limit(1);
  await supabase.from('students').select('id, name, admission_number, registration_number').limit(50);
  await supabase.from('attendance_records').select('*').limit(50);

  currentScreen = 'Teacher: Mark Attendance (Submit)';
  await supabase.from('attendance_sessions').select('id, status').limit(1);

  currentScreen = 'Teacher: Mark Entry (Load)';
  await supabase.from('exams').select('id, name, exam_code, batch_id').limit(10);
  await supabase.from('exam_subjects').select('*').limit(10);
  await supabase.from('marks').select('*').limit(50);

  currentScreen = 'Admin: Dashboard';
  await supabase.from('students').select('id', { count: 'exact', head: true }).eq('status', 'active');
  await supabase.from('courses').select('id', { count: 'exact', head: true });
  await supabase.from('fees').select('total_fee_paise, paid_amount_paise');
  await supabase.from('exams').select('id', { count: 'exact', head: true }).neq('status', 'published');
  await supabase.from('students').select('*').limit(10);
  await supabase.from('courses').select('*').limit(20);

  currentScreen = 'Admin: Student List (Page)';
  await supabase.from('students').select('*').limit(25);
  await supabase.from('students').select('id', { count: 'exact', head: true });
  await supabase.from('batches').select('*');
  await supabase.from('courses').select('*');

  currentScreen = 'Admin: Fee Collection';
  await supabase.from('students').select('*').limit(1);
  await supabase.from('fees').select('*').limit(1);
  await supabase.from('fee_items').select('*').limit(10);
  await supabase.from('payments').select('*').limit(10);
  await supabase.from('receipts').select('*').limit(10);

  currentScreen = 'Admin: Reports';
  await supabase.from('fees').select('*').limit(50);
  await supabase.from('payments').select('*').limit(50);
  await supabase.from('courses').select('*');

  currentScreen = 'Admin: Promotion Preview';
  await supabase.from('batches').select('*').limit(1);
  await supabase.from('student_enrollments').select('*').limit(50);
  await supabase.from('batch_periods').select('*').limit(10);

  currentScreen = 'Admin: Announcements';
  await supabase.from('announcements').select('*').limit(20);

  currentScreen = 'Admin: Timetable';
  await supabase.from('daily_timetables').select('*').limit(7);
  await supabase.from('daily_timetable_entries').select('*').limit(50);

  let failCount = 0;
  console.log('| Screen | Actual Requests | Budget | Actual Payload | Budget Payload | Status |');
  console.log('| :--- | :---: | :---: | :---: | :---: | :---: |');

  for (const [screen, budget] of Object.entries(SCREEN_BUDGETS)) {
    const act = metrics[screen] || { requests: 0, bytes: 0 };
    const reqOk = act.requests <= budget.maxRequests;
    const byteOk = act.bytes <= budget.maxPayloadBytes;
    const passed = reqOk && byteOk;

    if (!passed) failCount++;

    const statusStr = passed ? '✅ PASS' : '❌ EXCEEDED';
    console.log(
      `| ${screen} | ${act.requests} | ${budget.maxRequests} | ${(act.bytes / 1024).toFixed(2)} KB | ${(budget.maxPayloadBytes / 1024).toFixed(2)} KB | ${statusStr} |`
    );
  }

  console.log(`\nBudget Results: ${Object.keys(SCREEN_BUDGETS).length - failCount} Passed, ${failCount} Exceeded.`);
  return { failCount, totalScreens: Object.keys(SCREEN_BUDGETS).length };
}

// If executed directly
if (process.argv[1]?.endsWith('test-perf-budgets.mjs')) {
  runPerfBudgetCheck().then(({ failCount }) => {
    if (failCount > 0) {
      console.log(`\n[Baseline Check] ${failCount} screens exceed optimization budget (Expected in Baseline O1).`);
      process.exit(0); // Exit 0 for baseline reporting; will enforce strictly in CI/O6
    }
  });
}
