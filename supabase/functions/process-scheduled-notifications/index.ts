import { serve } from "https://deno.land/std@0.177.0/http/server.ts";

import { jsonResponse, requireServiceRole, serviceRoleClient } from "../_shared/attune_auth.ts";
import { sendOneSignalPush } from "../_shared/onesignal_push.ts";
import { deactivatePushSubscriptions, loadPushSubscriptions } from "../_shared/push_targets.ts";
import { acceptAndRun } from "./accept.ts";
import { deliverPush } from "./deliver.ts";

const MAX_ATTEMPTS = 5;

serve(async (req) => {
  if (req.method === "OPTIONS") return jsonResponse({ ok: true });
  try {
    requireServiceRole(req);
    const supabase = serviceRoleClient();
    // Plan 1b final review M1: answered (202) once accepted; the batch runs
    // in the background, so a wake is not timed by the backlog.
    return await acceptAndRun(() => processDueBatch(supabase));
  } catch (error) {
    return jsonResponse({ success: false, error: errorCode(error) }, 500);
  }
});

async function processDueBatch(supabase: ReturnType<typeof serviceRoleClient>) {
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
      .select("id,user_id,retry_count,metadata,delivery_channel,status")
      .maybeSingle();
    if (claimError) throw claimError;
    // Spec 1b: the quiet-hours guard can bounce a claim back to 'pending'
    // (it goes out at 08:00 local); only a row that became 'processing' is
    // ours to send.
    if (!job || job.status !== "processing") continue;

    try {
      if (job.delivery_channel !== "push") {
        await finish(supabase, job.id, "skipped", job.retry_count, null);
        continue;
      }
      const metadata = asRecord(job.metadata);
      const title = stringValue(metadata.title, "Attune");
      const body = stringValue(metadata.body, "Open Attune to see your update.");
      const data = privacySafeData(metadata);
      // Chat review #18: to the person's registered devices only.
      const outcome = await deliverPush(
        { id: String(job.id), user_id: String(job.user_id) },
        { title, body, data },
        {
          loadSubscriptions: (userId) => loadPushSubscriptions(supabase, userId),
          send: (input) => sendOneSignalPush(input),
          deactivate: (ids) => deactivatePushSubscriptions(supabase, ids),
        },
      );
      await finish(supabase, job.id, outcome.status, job.retry_count, outcome.lastError);
      if (outcome.status === "sent") processed++;
    } catch (pushError) {
      const attempts = Number(job.retry_count ?? 0) + 1;
      const state = attempts >= MAX_ATTEMPTS ? "failed" : "pending";
      await finish(supabase, job.id, state, attempts, errorCode(pushError));
    }
  }
  return { processed };
}

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
    // Couples calendar reminder deep link (reminder-notifications feature).
    "reminder_id",
    // Dating mutual-match deep link.
    "match_id",
    // Planning deep link (poll and countdown pushes open the plan).
    "entry_id",
    // Together event alarm deep link (Together spec §6.1).
    "event_id",
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
