// Webhook event-ID dedup.
//
// Call at the top of every webhook handler, immediately after signature
// verification and before any side-effect. Returns true if this is the first
// time we've seen the event, false if it's a replay (handler should return 200
// without doing anything).
//
// Uses ON CONFLICT DO NOTHING semantics via Supabase upsert with
// ignoreDuplicates: true.

import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";

export async function markEventProcessed(
  supabase: SupabaseClient,
  provider: "paystack" | "stripe" | "whatsapp",
  eventId: string,
  eventType?: string,
): Promise<{ firstTime: boolean; error?: string }> {
  if (!eventId) {
    // No event_id to dedupe on — log and let the handler proceed. Better
    // than failing closed and dropping legitimate events.
    return { firstTime: true, error: "missing event_id" };
  }

  const { data, error } = await supabase
    .from("processed_webhook_events")
    .upsert(
      { provider, event_id: eventId, event_type: eventType ?? null },
      { onConflict: "provider,event_id", ignoreDuplicates: true },
    )
    .select("event_id");

  if (error) {
    // DB error — fail open (proceed with handler) so we don't drop the event.
    // The handler-level idempotency checks (booking row, transfer ref) are
    // our backup.
    return { firstTime: true, error: error.message };
  }

  // ignoreDuplicates returns an empty array on conflict, non-empty on insert.
  return { firstTime: (data?.length ?? 0) > 0 };
}
