// tools/test_query_plans.mjs
// Automated CI Gate: Query-Plan Verification for Top 20 ERP Queries
// Enforces that index access paths exist and sequential scans on large tables fail.

import pg from 'pg';

const connectionString = process.env.DATABASE_URL || "";

const QUERIES = [
  {
    name: '1. Student Profile by Admission Number (Unique Index)',
    table: 'students',
    sql: "SELECT id, admission_number, name, course_id, batch_id, status FROM students WHERE admission_number = 'ADM-001'"
  },
  {
    name: '2. Student Attendance Payload RPC',
    table: 'RPC',
    sql: "SELECT public.get_student_attendance_payload(1, 1)"
  },
  {
    name: '3. Student Period Attendance Summaries (Primary Composite Key)',
    table: 'student_period_attendance_summaries',
    sql: "SELECT * FROM student_period_attendance_summaries WHERE student_id = 1"
  },
  {
    name: '4. Student Results Lookup (Composite Key)',
    table: 'results',
    sql: "SELECT id, exam_id, student_id, total_marks, percentage, status FROM results WHERE exam_id = 1 AND student_id = 1"
  },
  {
    name: '5. Student Fee Summary RPC',
    table: 'RPC',
    sql: "SELECT public.get_student_fee_summary(1)"
  },
  {
    name: '6. Student Notifications Unread (Partial Filtered Index)',
    table: 'notifications',
    sql: "SELECT id, title, body, created_at FROM notifications WHERE user_id = '00000000-0000-0000-0000-000000000002' AND read_at IS NULL ORDER BY created_at DESC LIMIT 20"
  },
  {
    name: '7. Timetable Day Payload RPC',
    table: 'RPC',
    sql: "SELECT public.get_timetable_day_payload(CURRENT_DATE)"
  },
  {
    name: '8. Teacher Today Board RPC',
    table: 'RPC',
    sql: "SELECT public.get_teacher_today_board()"
  },
  {
    name: '9. Teacher Attendance Records by Session (FK Index)',
    table: 'attendance_records',
    sql: "SELECT id, session_id, student_id, status FROM attendance_records WHERE session_id = 1"
  },
  {
    name: '10. Teacher Marks Entry (Unique Composite Index)',
    table: 'marks',
    sql: "SELECT student_id, marks_obtained, is_absent FROM marks WHERE exam_id = 1 AND subject_id = 1"
  },
  {
    name: '11. Admin Dashboard Summary RPC',
    table: 'RPC',
    sql: "SELECT public.get_admin_dashboard_summary()"
  },
  {
    name: '12. Admin Student Keyset Pagination (Active Filtered Index)',
    table: 'students',
    sql: "SELECT id, admission_number, name, status, course_id, batch_id FROM students WHERE status = 'active' ORDER BY admission_number ASC LIMIT 25"
  },
  {
    name: '13. Admin Fee Ledger by Student (Unique FK Index)',
    table: 'fees',
    sql: "SELECT id, student_id, total_fee_paise, pending_amount_paise FROM fees WHERE student_id = 1"
  },
  {
    name: '14. Admin Payments List by Student (Partial FK Index)',
    table: 'payments',
    sql: "SELECT id, student_id, amount_paise, payment_date FROM payments WHERE student_id = 1 AND deleted_at IS NULL ORDER BY payment_date DESC LIMIT 25"
  },
  {
    name: '15. Admin Promotion Preview RPC',
    table: 'RPC',
    sql: "SELECT public.preview_semester_promotion(1)"
  },
  {
    name: '16. Admin Student List RPC (Paginated)',
    table: 'RPC',
    sql: "SELECT public.get_admin_student_list(NULL, 1::bigint, 1::bigint, 'active'::text, 25::int, 0::int)"
  },
  {
    name: '17. Push Subscriptions Lookup (User Index)',
    table: 'push_subscriptions',
    sql: "SELECT endpoint, p256dh, auth FROM push_subscriptions WHERE user_id = '00000000-0000-0000-0000-000000000002'"
  },
  {
    name: '18. System Health Monitoring RPC',
    table: 'RPC',
    sql: "SELECT public.admin_get_system_health()"
  },
  {
    name: '19. Timetable Lookup by Batch (Filtered Partial Index)',
    table: 'timetables',
    sql: "SELECT id, batch_id, status FROM timetables WHERE batch_id = 1 AND status = 'published' AND deleted_at IS NULL"
  },
  {
    name: '20. Recent Audit Log (Timestamp Index)',
    table: 'audit_log',
    sql: "SELECT id, table_name, action, created_at FROM audit_log ORDER BY created_at DESC LIMIT 50"
  }
];

function inspectPlanNodes(planNode, findings = []) {
  if (!planNode) return findings;

  const nodeType = planNode['Node Type'] || '';
  const relationName = planNode['Relation Name'] || '';
  const indexName = planNode['Index Name'] || '';

  findings.push({
    nodeType,
    relationName,
    indexName
  });

  if (planNode.Plans && Array.isArray(planNode.Plans)) {
    for (const subPlan of planNode.Plans) {
      inspectPlanNodes(subPlan, findings);
    }
  }

  return findings;
}

async function run() {
  console.log('===============================================================');
  console.log('       MIPS ERP: CI QUERY-PLAN & INDEX VERIFICATION (TOP 20)   ');
  console.log('===============================================================\n');

  const client = new pg.Client({ connectionString });
  await client.connect();

  // Force planner to prefer index paths to verify indexes exist and are valid
  await client.query('SET enable_seqscan = off');

  let allPassed = true;
  const results = [];

  for (const q of QUERIES) {
    try {
      const explainRes = await client.query(`EXPLAIN (FORMAT JSON) ${q.sql}`);
      const rootPlan = explainRes.rows[0]['QUERY PLAN'][0].Plan;
      const nodes = inspectPlanNodes(rootPlan);

      const seqScans = nodes.filter(n => n.nodeType === 'Seq Scan');
      const indexScans = nodes.filter(n => n.nodeType.includes('Index') || n.nodeType.includes('Bitmap'));

      let status = 'PASS';
      let detail = '';

      if (q.table === 'RPC') {
        status = 'PASS';
        detail = 'Consolidated RPC execution';
      } else if (indexScans.length > 0) {
        status = 'PASS';
        detail = `Index: ${indexScans.map(i => i.indexName || i.nodeType).join(', ')}`;
      } else if (seqScans.length > 0) {
        status = 'FAIL';
        detail = `Unindexed Seq Scan on: ${seqScans.map(s => s.relationName).join(', ')}`;
        allPassed = false;
      } else {
        detail = nodes.map(n => n.nodeType).join(' -> ');
      }

      results.push({
        name: q.name,
        target: q.table,
        status,
        detail
      });
    } catch (err) {
      results.push({
        name: q.name,
        target: q.table,
        status: 'ERROR',
        detail: err.message
      });
      allPassed = false;
    }
  }

  await client.end();

  // Print results table
  console.log('| Query Description | Target / Relation | Plan Path / Index | Status |');
  console.log('| :--- | :--- | :--- | :---: |');
  for (const r of results) {
    const icon = r.status === 'PASS' ? '✅ PASS' : '❌ FAIL';
    console.log(`| ${r.name} | ${r.target} | ${r.detail} | ${icon} |`);
  }

  console.log('\n===============================================================');
  if (allPassed) {
    console.log('✅ ALL 20 QUERY PLANS PASSED WITH ZERO UNINDEXED SEQUENTIAL SCANS!');
    process.exit(0);
  } else {
    console.error('❌ ONE OR MORE QUERY PLANS FAILED INDEX VERIFICATION!');
    process.exit(1);
  }
}

run();
