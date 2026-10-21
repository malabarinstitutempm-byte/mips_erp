-- ==============================================================================
-- Migration 0024: System Health Monitoring & Resource Guard RPC
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.admin_get_system_health()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog
AS $$
DECLARE
  v_is_admin boolean;
  v_db_size bigint;
  v_db_limit bigint := 524288000; -- 500 MB Free Plan
  v_db_warning bigint := 367001600; -- 350 MB (70%)
  v_table_stats jsonb;
  v_audit_stats jsonb;
  v_notif_stats jsonb;
  v_push_stats jsonb;
  v_slow_queries jsonb := '[]'::jsonb;
  v_result jsonb;
BEGIN
  -- Verify administrator role (allows admin profile, service_role, and superuser)
  SELECT (
    CURRENT_USER IN ('postgres', 'supabase_admin')
    OR COALESCE(auth.role(), '') = 'service_role'
    OR public.is_admin()
  ) INTO v_is_admin;
  IF NOT COALESCE(v_is_admin, false) THEN
    RAISE EXCEPTION 'Access denied. Administrator privileges required.';
  END IF;

  -- 1. Database Size & Quotas
  v_db_size := pg_database_size(current_database());

  -- 2. Core Tables Size & Estimated Counts
  SELECT jsonb_agg(
    jsonb_build_object(
      'table_name', relname,
      'row_count', n_live_tup,
      'total_bytes', pg_total_relation_size(relid),
      'total_pretty', pg_size_pretty(pg_total_relation_size(relid)),
      'table_pretty', pg_size_pretty(pg_relation_size(relid)),
      'index_pretty', pg_size_pretty(pg_indexes_size(relid))
    ) ORDER BY pg_total_relation_size(relid) DESC
  )
  INTO v_table_stats
  FROM pg_stat_user_tables
  WHERE schemaname = 'public'
    AND relname IN (
      'students', 'attendance', 'marks', 'fees', 'payments', 'receipts',
      'courses', 'batches', 'audit_log', 'notifications', 'login_attempts',
      'push_subscriptions', 'student_period_attendance_summaries',
      'semesters', 'academic_years', 'timetables', 'profiles'
    );

  -- 3. Audit Log Detailed Metrics
  SELECT jsonb_build_object(
    'row_count', COUNT(*),
    'total_pretty', pg_size_pretty(pg_total_relation_size('public.audit_log'::regclass)),
    'oldest_record', MIN(created_at),
    'newest_record', MAX(created_at),
    'retention_policy', '12 Months Online (pg_cron daily purge)'
  )
  INTO v_audit_stats
  FROM public.audit_log;

  -- 4. Notifications Detailed Metrics
  SELECT jsonb_build_object(
    'row_count', COUNT(*),
    'unread_count', COUNT(*) FILTER (WHERE read_at IS NULL),
    'total_pretty', pg_size_pretty(pg_total_relation_size('public.notifications'::regclass)),
    'oldest_record', MIN(created_at),
    'retention_policy', '90 Days Read Retention (pg_cron daily purge)'
  )
  INTO v_notif_stats
  FROM public.notifications;

  -- 5. Push Subscriptions Metrics
  SELECT jsonb_build_object(
    'total_subscriptions', COUNT(*),
    'recent_subscriptions', COUNT(*) FILTER (WHERE created_at >= NOW() - INTERVAL '60 days'),
    'older_subscriptions', COUNT(*) FILTER (WHERE created_at < NOW() - INTERVAL '60 days')
  )
  INTO v_push_stats
  FROM public.push_subscriptions;

  -- 6. Top 5 Slowest / Heavy Queries (from pg_stat_statements if available)
  BEGIN
    SELECT jsonb_agg(
      jsonb_build_object(
        'calls', calls,
        'mean_ms', ROUND(mean_exec_time::numeric, 2),
        'total_ms', ROUND(total_exec_time::numeric, 2),
        'query_preview', LEFT(REGEXP_REPLACE(query, '\s+', ' ', 'g'), 120)
      )
    )
    INTO v_slow_queries
    FROM (
      SELECT calls, mean_exec_time, total_exec_time, query
      FROM pg_stat_statements
      WHERE query NOT ILIKE '%pg_stat%'
        AND query NOT ILIKE '%admin_get_system_health%'
        AND query NOT ILIKE '%pg_catalog%'
      ORDER BY mean_exec_time DESC
      LIMIT 5
    ) q;
  EXCEPTION WHEN OTHERS THEN
    v_slow_queries := '[]'::jsonb;
  END;

  -- Assemble Complete System Health Envelope
  v_result := jsonb_build_object(
    'timestamp', clock_timestamp(),
    'database', jsonb_build_object(
      'size_bytes', v_db_size,
      'size_pretty', pg_size_pretty(v_db_size),
      'limit_bytes', v_db_limit,
      'limit_pretty', '500 MB',
      'warning_threshold_bytes', v_db_warning,
      'warning_threshold_pretty', '350 MB (70%)',
      'usage_percent', ROUND((v_db_size::numeric / v_db_limit::numeric) * 100.0, 2),
      'is_warning', (v_db_size >= v_db_warning)
    ),
    'egress_quota', jsonb_build_object(
      'limit_pretty', '5 GB / Month',
      'warning_threshold_pretty', '3.5 GB (70%)',
      'status', 'Tracked on Supabase Cloud Edge'
    ),
    'edge_functions_quota', jsonb_build_object(
      'limit_monthly_calls', 500000,
      'limit_pretty', '500,000 calls / Month',
      'warning_threshold_calls', 350000,
      'warning_threshold_pretty', '350,000 (70%)'
    ),
    'storage_quota', jsonb_build_object(
      'limit_pretty', '1 GB',
      'warning_threshold_pretty', '700 MB (70%)',
      'strategy', 'WebP 75 transformed thumbnails + Local Documents'
    ),
    'table_stats', COALESCE(v_table_stats, '[]'::jsonb),
    'audit_log', v_audit_stats,
    'notifications', v_notif_stats,
    'push_subscriptions', v_push_stats,
    'recent_slow_queries', COALESCE(v_slow_queries, '[]'::jsonb),
    'supabase_usage_url', 'https://supabase.com/dashboard/project/evzehywyyqmcktszwmeg/settings/billing/usage'
  );

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_get_system_health() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_get_system_health() TO service_role;
