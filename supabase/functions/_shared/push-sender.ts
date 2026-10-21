// supabase/functions/_shared/push-sender.ts
// High-performance batch Web Push dispatcher with dead-endpoint pruning and event throttling

export interface PushMessagePayload {
  title: string;
  body: string;
  url?: string;
  tag?: string;
  eventId?: string;
}

export interface PushDispatchResult {
  totalRecipients: number;
  subscribedRecipients: number;
  sentCount: number;
  failedCount: number;
  prunedEndpoints: number;
}

/**
 * Dispatches Web Push notifications in batches from a single function run.
 * - Skips users with no subscription automatically.
 * - Deduplicates / throttles to at most 1 push per user per event.
 * - Automatically purges expired/unregistered endpoints (HTTP 404 or 410 from Web Push/FCM).
 * - Returns minimal summary metrics.
 */
export async function sendBatchPushNotifications(
  adminClient: any,
  userIds: string[],
  payload: PushMessagePayload
): Promise<PushDispatchResult> {
  if (!userIds || userIds.length === 0) {
    return {
      totalRecipients: 0,
      subscribedRecipients: 0,
      sentCount: 0,
      failedCount: 0,
      prunedEndpoints: 0,
    };
  }

  // 1. Throttle / Deduplicate: at most 1 push per user per event
  const uniqueUserIds = Array.from(new Set(userIds.filter(Boolean)));

  // 2. Fetch active subscriptions in one batch using get_batch_push_subscriptions
  // Users with NO subscription are automatically skipped at SQL level!
  const { data: subscriptions, error } = await adminClient.rpc('get_batch_push_subscriptions', {
    p_user_ids: uniqueUserIds,
  });

  if (error || !subscriptions || subscriptions.length === 0) {
    return {
      totalRecipients: uniqueUserIds.length,
      subscribedRecipients: 0,
      sentCount: 0,
      failedCount: 0,
      prunedEndpoints: 0,
    };
  }

  const deadEndpoints: string[] = [];
  let sentCount = 0;
  let failedCount = 0;

  // 3. Dispatch push notifications in chunks of 50 to avoid socket starvation
  const CHUNK_SIZE = 50;
  const pushBody = JSON.stringify({
    title: payload.title,
    body: payload.body,
    url: payload.url || '/',
    tag: payload.tag || payload.eventId || 'mips-notification',
  });

  for (let i = 0; i < subscriptions.length; i += CHUNK_SIZE) {
    const chunk = subscriptions.slice(i, i + CHUNK_SIZE);
    const promises = chunk.map(async (sub: any) => {
      try {
        const res = await fetch(sub.endpoint, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'TTL': '86400', // 24 hours
          },
          body: pushBody,
        });

        // HTTP 404 (Not Found) or 410 (Gone): Endpoint unregistered / expired
        if (res.status === 404 || res.status === 410) {
          deadEndpoints.push(sub.endpoint);
          failedCount++;
        } else if (res.ok || res.status === 201) {
          sentCount++;
        } else {
          failedCount++;
        }
      } catch (_) {
        failedCount++;
      }
    });

    await Promise.allSettled(promises);
  }

  // 4. Automatically remove dead / unregistered endpoints from database
  let prunedCount = 0;
  if (deadEndpoints.length > 0) {
    const { data: pruned } = await adminClient.rpc('prune_dead_push_endpoints', {
      p_endpoints: deadEndpoints,
    });
    prunedCount = typeof pruned === 'number' ? pruned : deadEndpoints.length;
  }

  return {
    totalRecipients: uniqueUserIds.length,
    subscribedRecipients: subscriptions.length,
    sentCount,
    failedCount,
    prunedEndpoints: prunedCount,
  };
}
