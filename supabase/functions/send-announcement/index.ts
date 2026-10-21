// supabase/functions/send-announcement/index.ts
// Administrative Announcement Dispatch with Recipient Resolution and Web Push

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { handleCors } from '../_shared/cors.ts';
import { getAdminClient } from '../_shared/supabase-client.ts';
import { jsonResponse, errorResponse } from '../_shared/response.ts';
import { requireAdmin } from '../_shared/auth-guard.ts';

interface AnnouncementPayload {
  category: 'programme' | 'exam' | 'fee_reminder' | 'timetable' | 'general';
  title: string;
  body: string;
  audience_type: 'all_students' | 'course' | 'batch' | 'teachers' | 'fee_defaulters';
  audience_ids?: (number | string)[];
  min_balance_paise?: number;
  dry_run?: boolean;
}

serve(async (req: Request) => {
  const corsResponse = handleCors(req);
  if (corsResponse) return corsResponse;

  if (req.method !== 'POST') {
    return errorResponse('Method not allowed. Use POST.', 405, undefined, req);
  }

  // Require admin privilege
  const { errorResponse: authError, auth } = await requireAdmin(req);
  if (authError || !auth) {
    return authError || errorResponse('Forbidden.', 403, undefined, req);
  }

  try {
    const payload: AnnouncementPayload = await req.json().catch(() => ({}));
    const { category, title, body, audience_type } = payload;

    if (!category || !title || !body || !audience_type) {
      return errorResponse(
        'Missing required fields: category, title, body, and audience_type are required.',
        400,
        undefined,
        req
      );
    }

    const adminClient = getAdminClient();

    // Call stored procedure send_announcement
    const { data, error } = await adminClient.rpc('send_announcement', {
      p_payload: payload,
    });

    if (error) {
      console.error('[send-announcement] RPC error:', error);
      return errorResponse(error.message, 500, undefined, req);
    }

    let pushSummary = null;
    if (!payload.dry_run && data?.announcement_id) {
      // 1. Fetch user IDs for this announcement in 1 query
      const { data: recipientRows } = await adminClient
        .from('notifications')
        .select('user_id')
        .eq('announcement_id', data.announcement_id);

      const userIds: string[] = (recipientRows || [])
        .map((r: any) => r.user_id)
        .filter(Boolean);

      if (userIds.length > 0) {
        // 2. Dispatch batch push with auto-skip and dead-endpoint pruning
        const { sendBatchPushNotifications } = await import('../_shared/push-sender.ts');
        pushSummary = await sendBatchPushNotifications(adminClient, userIds, {
          title,
          body,
          url: '/student/notifications',
          eventId: `announcement_${data.announcement_id}`,
        });
      }
    }

    return jsonResponse(
      {
        success: true,
        data,
        push: pushSummary,
      },
      200,
      undefined,
      req
    );
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : String(err);
    console.error('[send-announcement] Unexpected error:', err);
    return errorResponse(`Internal error: ${msg}`, 500, undefined, req);
  }
});
