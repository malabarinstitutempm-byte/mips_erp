-- ==============================================================================
-- Migration 0025: Query Plan Guard Missing Indexes
-- ==============================================================================

-- 1. Index for push_subscriptions by user_id
CREATE INDEX IF NOT EXISTS idx_push_subscriptions_user_id
  ON public.push_subscriptions (user_id);

-- 2. Index for audit_log chronological ordering & retention window scanning
CREATE INDEX IF NOT EXISTS idx_audit_log_created_at
  ON public.audit_log (created_at DESC);
