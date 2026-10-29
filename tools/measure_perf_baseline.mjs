// tools/measure_perf_baseline.mjs
// Automated Baseline Performance & Network Instrumentation Suite for MIPS ERP

import { createClient } from '@supabase/supabase-js';

const SUPABASE_URL = 'https://evzehywyyqmcktszwmeg.supabase.co';
const SUPABASE_ANON_KEY =
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImV2emVoeXd5eXFtY2t0c3p3bWVnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTE5NjM0MTYsImV4cCI6MjEwNzUzOTQxNn0.xNfdyP9f9if2INEdDdzGR4U04oItnt8XVhdM1-2Jnk4';

// Service role or admin connection for benchmarking
const PG_CONN = process.env.DATABASE_URL || "";

const recordedLogs = [];
let currentScreen = 'Init';
let currentAction = 'Load';

function instrumentedFetch(baseFetch = fetch) {
  return async (input, init) => {
    const start = performance.now();
    const urlStr = typeof input === 'string' ? input : input instanceof URL ? input.toString() : input.url;
    const method = init?.method || 'GET';
    let reqBytes = 0;
    if (init?.body) {
      reqBytes = typeof init.body === 'string' ? Buffer.byteLength(init.body) : 0;
    }

    let response;
    try {
      response = await baseFetch(input, init);
    } catch (e) {
      const dur = performance.now() - start;
      record(urlStr, method, null, reqBytes, 0, 0, dur, 0);
      throw e;
    }

    const dur = performance.now() - start;
    const clone = response.clone();
    let resBytes = 0;
    let rowCount = 0;
    let cols = null;

    try {
      const url = new URL(urlStr);
      cols = url.searchParams.get('select');
      const text = await clone.text();
      resBytes = Buffer.byteLength(text);
      if (text.startsWith('[') || text.startsWith('{')) {
        const json = JSON.parse(text);
        if (Array.isArray(json)) rowCount = json.length;
        else if (json && typeof json === 'object') rowCount = 1;
      }
    } catch (_) {
      const cl = response.headers.get('content-length');
      if (cl) resBytes = parseInt(cl, 10);
    }

    record(urlStr, method, cols, reqBytes, resBytes, rowCount, dur, response.status);
    return response;
  };
}

function record(urlStr, method, cols, reqBytes, resBytes, rowCount, durationMs, status) {
  let endpoint = urlStr;
  try {
    const url = new URL(urlStr);
    if (url.pathname.includes('/rest/v1/rpc/')) {
      endpoint = `rpc:${url.pathname.split('/rest/v1/rpc/')[1].split('?')[0]}`;
    } else if (url.pathname.includes('/rest/v1/')) {
      endpoint = `table:${url.pathname.split('/rest/v1/')[1].split('?')[0]}`;
    } else if (url.pathname.includes('/auth/v1/')) {
      endpoint = `auth:${url.pathname.split('/auth/v1/')[1].split('?')[0]}`;
    }
  } catch (_) {}

  recordedLogs.push({
    screen: currentScreen,
    action: currentAction,
    method,
    endpoint,
    columns: cols,
    requestBytes: reqBytes,
    responseBytes: resBytes,
    rowCount,
    durationMs,
    status,
  });
}

const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
  global: { fetch: instrumentedFetch(fetch) },
});

async function runBenchmark() {
  console.log('===============================================================');
  console.log('    MIPS ERP: SYSTEM PERFORMANCE & NETWORK BASELINE PROFILER   ');
  console.log('===============================================================\n');

  // 1. FLOW: LOGIN (Student / Teacher / Admin)
  currentScreen = 'Auth: Login';
  currentAction = 'Submit Credentials';
  // Lookup credentials in admin_accounts or auth
  await supabase.from('admin_accounts').select('id, full_name, username, role, password, active').eq('username', 'admin').maybeSingle();

  // 2. FLOW: STUDENT PORTAL - INITIAL LOAD
  currentScreen = 'Student: Initial Load';
  currentAction = 'Mount Portal';
  // 1. Student profile view
  await supabase.from('student_profile_view').select('*').limit(1);
  // 2. Student enrollments
  await supabase.from('student_enrollments').select('*, courses(*)').limit(5);

  // 3. FLOW: STUDENT PORTAL - ATTENDANCE TAB
  currentScreen = 'Student: Attendance Tab';
  currentAction = 'Tab Switch / Load Attendance';
  // Existing baseline flow has 5 sequential queries:
  await supabase.from('student_enrollments').select('id, course_id, batch_id, status').limit(2);
  await supabase.from('students').select('batch_id').limit(1);
  await supabase.from('batch_periods').select('*').limit(5);
  await supabase.from('attendance_records').select('id, session_id, status, remarks').limit(50);
  await supabase.from('attendance_sessions').select('id, batch_id, date, slot, status').limit(50);

  // 4. FLOW: STUDENT PORTAL - RESULTS TAB
  currentScreen = 'Student: Results Tab';
  currentAction = 'Tab Switch / Load Results';
  // 1. Results header
  await supabase.from('results').select('*').limit(10);
  // 2. Marks breakdown
  await supabase.from('marks').select('*').limit(50);

  // 5. FLOW: STUDENT PORTAL - FEES TAB
  currentScreen = 'Student: Fees Tab';
  currentAction = 'Tab Switch / Load Fees';
  // 1. Fees summary
  await supabase.from('fees').select('*').limit(1);
  // 2. Fee items breakdown
  await supabase.from('fee_items').select('*').limit(10);
  // 3. Payment history
  await supabase.from('payments').select('*').limit(10);

  // 6. FLOW: STUDENT PORTAL - TIMETABLE TAB
  currentScreen = 'Student: Timetable Tab';
  currentAction = 'Tab Switch / Load Timetable';
  await supabase.from('daily_timetables').select('*').limit(2);
  await supabase.from('daily_timetable_entries').select('*').limit(10);

  // 7. FLOW: STUDENT PORTAL - NOTIFICATIONS DRAWER
  currentScreen = 'Student: Notifications';
  currentAction = 'Open Drawer';
  await supabase.from('notifications').select('*').limit(20);

  // 8. FLOW: TEACHER PORTAL - TODAY BOARD & PROFILE
  currentScreen = 'Teacher: Initial Load';
  currentAction = 'Mount Teacher Area';
  await supabase.from('teachers').select('*').limit(1);
  await supabase.from('batches').select('id, name, course_id').limit(10);
  await supabase.from('courses').select('id, name, code').limit(10);

  // 9. FLOW: TEACHER PORTAL - MARK ATTENDANCE FLOW
  currentScreen = 'Teacher: Mark Attendance';
  currentAction = 'Select Batch, Date & Slot';
  await supabase.from('attendance_sessions').select('*').eq('batch_id', 1).limit(1);
  await supabase.from('students').select('id, name, admission_number, registration_number').limit(50);
  await supabase.from('attendance_records').select('*').limit(50);

  currentAction = 'Submit Attendance Session';
  // submit session (or check session endpoint)
  await supabase.from('attendance_sessions').select('id, status').limit(1);

  // 10. FLOW: TEACHER PORTAL - MARK ENTRY FLOW
  currentScreen = 'Teacher: Mark Entry';
  currentAction = 'Select Exam & Subject';
  await supabase.from('exams').select('id, name, exam_code, batch_id').limit(10);
  await supabase.from('exam_subjects').select('*').limit(10);
  await supabase.from('marks').select('*').limit(50);

  // 11. FLOW: ADMIN PORTAL - DASHBOARD
  currentScreen = 'Admin: Dashboard';
  currentAction = 'Load KPI Metrics & Feeds';
  // Baseline Flutter Dashboard loads 6 individual queries:
  await supabase.from('students').select('id', { count: 'exact', head: true }).eq('status', 'active');
  await supabase.from('courses').select('id', { count: 'exact', head: true });
  await supabase.from('fees').select('total_fee_paise, paid_amount_paise');
  await supabase.from('exams').select('id', { count: 'exact', head: true }).neq('status', 'published');
  await supabase.from('students').select('*').limit(10);
  await supabase.from('courses').select('*').limit(20);

  // 12. FLOW: ADMIN PORTAL - STUDENT LIST
  currentScreen = 'Admin: Student List';
  currentAction = 'Load Page 1 (25 rows)';
  await supabase.from('students').select('*').limit(25);
  await supabase.from('students').select('id', { count: 'exact', head: true });
  await supabase.from('batches').select('*');
  await supabase.from('courses').select('*');

  // 13. FLOW: ADMIN PORTAL - FEE COLLECTION
  currentScreen = 'Admin: Fee Collection';
  currentAction = 'Student Lookup & Ledger';
  await supabase.from('students').select('*').limit(1);
  await supabase.from('fees').select('*').limit(1);
  await supabase.from('fee_items').select('*').limit(10);
  await supabase.from('payments').select('*').limit(10);
  await supabase.from('receipts').select('*').limit(10);

  // 14. FLOW: ADMIN PORTAL - REPORTS
  currentScreen = 'Admin: Reports';
  currentAction = 'Defaulters & Revenue Load';
  await supabase.from('fees').select('*').limit(50);
  await supabase.from('payments').select('*').limit(50);
  await supabase.from('courses').select('*');

  // 15. FLOW: ADMIN PORTAL - PROMOTION PREVIEW
  currentScreen = 'Admin: Promotion Preview';
  currentAction = 'Preview Batch Promotion';
  await supabase.from('batches').select('*').limit(1);
  await supabase.from('student_enrollments').select('*').limit(50);
  await supabase.from('batch_periods').select('*').limit(10);

  // 16. FLOW: ADMIN PORTAL - ANNOUNCEMENTS
  currentScreen = 'Admin: Announcements';
  currentAction = 'List Announcements';
  await supabase.from('announcements').select('*').limit(20);

  // 17. FLOW: ADMIN PORTAL - TIMETABLE
  currentScreen = 'Admin: Timetable';
  currentAction = 'Load Daily Schedule';
  await supabase.from('daily_timetables').select('*').limit(7);
  await supabase.from('daily_timetable_entries').select('*').limit(50);

  console.log('Generating Performance Baseline Report...\n');
  printReport();
}

function printReport() {
  const screens = {};

  for (const log of recordedLogs) {
    if (!screens[log.screen]) {
      screens[log.screen] = {
        requests: 0,
        totalBytes: 0,
        totalDuration: 0,
        actions: {},
        endpoints: [],
      };
    }
    const s = screens[log.screen];
    s.requests++;
    s.totalBytes += log.responseBytes;
    s.totalDuration += log.durationMs;

    if (!s.actions[log.action]) {
      s.actions[log.action] = { requests: 0, bytes: 0, ms: 0 };
    }
    s.actions[log.action].requests++;
    s.actions[log.action].bytes += log.responseBytes;
    s.actions[log.action].ms += log.durationMs;

    s.endpoints.push({
      method: log.method,
      endpoint: log.endpoint,
      cols: log.columns || '*',
      rows: log.rowCount,
      kb: (log.responseBytes / 1024).toFixed(2),
      ms: log.durationMs.toFixed(1),
    });
  }

  console.log('| Screen / Flow | Action | Requests | Total Payload (KB) | Avg Duration (ms) | Target Budget (Requests) |');
  console.log('| :--- | :--- | :---: | :---: | :---: | :---: |');

  for (const [screenName, data] of Object.entries(screens)) {
    for (const [actionName, act] of Object.entries(data.actions)) {
      const budget = getRecommendedBudget(screenName);
      console.log(
        `| **${screenName}** | ${actionName} | ${act.requests} | ${(act.bytes / 1024).toFixed(2)} KB | ${act.ms.toFixed(1)} ms | **≤ ${budget}** |`
      );
    }
  }

  console.log('\n--- DETAILED ENDPOINT LOG ---');
  for (const log of recordedLogs) {
    console.log(`[${log.screen} - ${log.action}] ${log.method} ${log.endpoint} (cols: ${log.columns || '*'}) -> ${log.rowCount} rows, ${(log.responseBytes / 1024).toFixed(2)} KB, ${log.durationMs.toFixed(1)}ms`);
  }
}

function getRecommendedBudget(screen) {
  if (screen.includes('Login')) return 1;
  if (screen.includes('Student: Initial Load')) return 1;
  if (screen.includes('Student:') && screen.includes('Tab')) return 1;
  if (screen.includes('Teacher: Initial Load')) return 1;
  if (screen.includes('Teacher: Mark Attendance')) return 2;
  if (screen.includes('Teacher: Mark Entry')) return 2;
  if (screen.includes('Admin: Dashboard')) return 1;
  if (screen.includes('Admin: Student List')) return 1;
  if (screen.includes('Admin: Fee Collection')) return 2;
  if (screen.includes('Admin: Reports')) return 1;
  if (screen.includes('Admin: Promotion')) return 1;
  if (screen.includes('Admin: Announcements')) return 1;
  if (screen.includes('Admin: Timetable')) return 1;
  return 2;
}

runBenchmark().catch(console.error);
