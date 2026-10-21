// tools/measure_db_baseline.mjs
// Database Query Execution Profiler: EXPLAIN (ANALYZE, BUFFERS)

import pg from 'pg';

const connectionString = 'postgresql://postgres:AnzTzOTXxapp1Dys@db.evzehywyyqmcktszwmeg.supabase.co:5432/postgres';

async function main() {
  const client = new pg.Client({ connectionString });
  await client.connect();

  console.log('===============================================================');
  console.log('       MIPS ERP: POSTGRES EXPLAIN (ANALYZE, BUFFERS) AUDIT     ');
  console.log('===============================================================\n');

  // Insert mock admin profile if needed for function execution
  await client.query(`
    DO $$ BEGIN
      INSERT INTO profiles (user_id, role, active, full_name)
      VALUES ('00000000-0000-0000-0000-000000000001', 'admin', true, 'Perf Auditor')
      ON CONFLICT (user_id) DO UPDATE SET role = 'admin', active = true;
    EXCEPTION WHEN OTHERS THEN NULL;
    END $$;
  `);

  await client.query(`
    SELECT set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-000000000001', 'role', 'authenticated')::text, true);
  `);

  const queries = [
    {
      name: '1. Student List with Joins & Pagination (Admin)',
      sql: `EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)
        SELECT s.id, s.admission_number, s.name, s.status, b.batch_name, c.name as course_name
        FROM students s
        LEFT JOIN batches b ON b.id = s.batch_id
        LEFT JOIN courses c ON c.id = s.course_id
        WHERE s.deleted_at IS NULL AND s.status = 'active'
        ORDER BY s.admission_number ASC
        LIMIT 25;`
    },
    {
      name: '2. Fees Overview & Balances Ledger (Admin / Student Fees)',
      sql: `EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)
        SELECT f.id, f.student_id, f.total_fee_paise, f.paid_amount_paise, f.pending_amount_paise
        FROM fees f
        WHERE f.deleted_at IS NULL
        ORDER BY f.pending_amount_paise DESC
        LIMIT 25;`
    },
    {
      name: '3. Attendance Sessions by Batch & Date (Teacher / Student)',
      sql: `EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)
        SELECT ats.id, ats.batch_id, ats.date, ats.slot, ats.status
        FROM attendance_sessions ats
        WHERE ats.batch_id = 1 AND ats.date >= CURRENT_DATE - 30
        ORDER BY ats.date DESC, ats.slot ASC;`
    },
    {
      name: '4. Attendance Records for Session (Teacher Attendance Roster)',
      sql: `EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)
        SELECT ar.id, ar.session_id, ar.student_id, ar.status, ar.remarks
        FROM attendance_records ar
        WHERE ar.session_id = 1;`
    },
    {
      name: '5. Daily Timetable published today/tomorrow (Student & Teacher)',
      sql: `EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)
        SELECT dt.id, dt.date, dt.status, dte.course_name, dte.subject_name, dte.start_time, dte.end_time
        FROM daily_timetables dt
        JOIN daily_timetable_entries dte ON dte.daily_timetable_id = dt.id
        WHERE dt.status = 'published'
          AND dt.date >= CURRENT_DATE
          AND dt.date <= CURRENT_DATE + 1
        ORDER BY dt.date ASC, dte.sort_order ASC;`
    },
    {
      name: '6. Published Announcements Feed (Student Area)',
      sql: `EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)
        SELECT a.id, a.title, a.body, a.category, a.created_at
        FROM announcements a
        WHERE a.retracted_at IS NULL
        ORDER BY a.created_at DESC
        LIMIT 20;`
    },
    {
      name: '7. Student Attendance Summary Function (Period-aware)',
      sql: `EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)
        SELECT * FROM student_attendance_summary(1, 1, 1);`
    },
    {
      name: '8. Batch Promotion Preview Function',
      sql: `EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)
        SELECT * FROM preview_semester_promotion(1);`
    }
  ];

  console.log('| Query / Operation | Planning Time | Execution Time | Scan Type | Buffer Hits | Buffer Reads |');
  console.log('| :--- | :---: | :---: | :---: | :---: | :---: |');

  for (const q of queries) {
    try {
      const res = await client.query(q.sql);
      const plan = res.rows[0]['QUERY PLAN'][0];
      const pTime = `${plan['Planning Time'].toFixed(2)} ms`;
      const eTime = `${plan['Execution Time'].toFixed(2)} ms`;
      const scanType = plan.Plan['Node Type'];
      const hits = plan.Plan['Shared Hit Blocks'] || 0;
      const reads = plan.Plan['Shared Read Blocks'] || 0;
      console.log(`| **${q.name}** | ${pTime} | ${eTime} | ${scanType} | ${hits} | ${reads} |`);
    } catch (err) {
      console.log(`| **${q.name}** | - | Error: ${err.message.split('\n')[0]} | - | - | - |`);
    }
  }

  await client.end();
}

main().catch(console.error);
