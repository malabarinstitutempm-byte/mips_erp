import pg from 'pg';

const connectionString = process.env.DATABASE_URL || "";

async function main() {
  const client = new pg.Client({ connectionString });
  await client.connect();

  console.log('=== INDEXES AND USAGE STATS ===');
  const res = await client.query(`
    SELECT
      schemaname,
      relname AS table_name,
      indexrelname AS index_name,
      idx_scan,
      idx_tup_read,
      idx_tup_fetch
    FROM pg_stat_user_indexes
    WHERE schemaname = 'public'
    ORDER BY relname, indexrelname;
  `);
  console.log(`Total public indexes: ${res.rows.length}`);
  console.table(res.rows.slice(0, 40));

  console.log('\n=== INDEX DEFINITIONS ===');
  const defs = await client.query(`
    SELECT tablename, indexname, indexdef
    FROM pg_indexes
    WHERE schemaname = 'public'
    ORDER BY tablename, indexname;
  `);
  for (const row of defs.rows) {
    console.log(`${row.tablename}.${row.indexname}: ${row.indexdef}`);
  }

  await client.end();
}

main().catch(console.error);
