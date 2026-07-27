import { serve } from "https://deno.land/std@0.177.0/http/server.ts";

import { jsonResponse, requireServiceRole, serviceRoleClient } from "../_shared/attune_auth.ts";
import { sendOneSignalPush } from "../_shared/onesignal_push.ts";

const MAX_ATTEMPTS = 5;

serve(async (req) => {
  if (req.method === "OPTIONS") return jsonResponse({ ok: true });
  try {
    requireServiceRole(req);
    const supabase = serviceRoleClient();
    const { data: candidates, error } = await supabase
      .from("scheduled_notifications")
      .select("id")
      .eq("status", "pending")
      .lte("scheduled_for", new Date().toISOString())
      .order("scheduled_for", { ascending: true })
      .limit(50);
    if (error) throw error;

    let processed = 0;
    for (const candidate of candidates ?? []) {
      const { data: job, error: claimError } = await supabase
        .from("scheduled_notifications")
        .update({ status: "processing", updated_at: new Date().toISOString() })
        .eq("id", candidate.id)
        .eq("status", "pending")
        .select("id,user_id,retry_count,metadata,delivery_channel")
        .maybeSingle();
      if (claimError) throw claimError;
      if (!job) continue;

      try {
        if (job.delivery_channel !== "push") {
          await finish(supabase, job.id, "skipped", job.retry_count, null);
          continue;
        }
        const metadata = asRecord(job.metadata);
        const title = stringValue(metadata.title, "Attune");
        const body = stringValue(metadata.body, "Open Attune to see your update.");
        const data = privacySafeData(metadata);
        await sendOneSignalPush({
          userId: String(job.user_id),
          title,
          body,
          data,
          idempotencyKey: String(job.id),
        });
        await finish(supabase, job.id, "sent", job.retry_count, null);
        processed++;
      } catch (pushError) {
        const attempts = Number(job.retry_count ?? 0) + 1;
        const state = attempts >= MAX_ATTEMPTS ? "failed" : "pending";
        await finish(supabase, job.id, state, attempts, errorCode(pushError));
      }
    }
    return jsonResponse({ success: true, processed });
  } catch (error) {
    return jsonResponse({ success: false, error: errorCode(error) }, 500);
  }
});

async function finish(
  supabase: ReturnType<typeof serviceRoleClient>,
  id: string,
  status: "pending" | "sent" | "failed" | "skipped",
  retryCount: number,
  lastError: string | null,
) {
  const { error } = await supabase.from("scheduled_notifications").update({
    status,
    retry_count: retryCount,
    last_error: lastError,
    updated_at: new Date().toISOString(),
  }).eq("id", id).eq("status", "processing");
  if (error) throw error;
}

function privacySafeData(metadata: Record<string, unknown>) {
  const allowed = [
    "type",
    "relationship_id",
    "journey_id",
    "session_id",
    "chapter",
    // Forum/Opinions deep links (FORUM.md §10). These are content ids, never
    // actor ids — the anonymous forum's notifications deliberately carry no
    // information about WHO liked/commented/replied.
    "opinion_id",
    "comment_id",
    "forum_post_id",
    // Forum activity/quiet notifications (§10 #5/#6) deep-link to the topic.
    "topic_id",
  ];
  return Object.fromEntries(
    allowed.filter((key) => metadata[key] != null).map((key) => [key, metadata[key]]),
  );
}

function asRecord(value: unknown): Record<string, unknown> {
  return value && typeof value === "object" ? value as Record<string, unknown> : {};
}

function stringValue(value: unknown, fallback: string) {
  return typeof value === "string" && value.trim() ? value : fallback;
}

function errorCode(error: unknown) {
  const message = error instanceof Error ? error.message : "unknown_error";
  return message.slice(0, 120);
}
