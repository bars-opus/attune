import { serve } from "https://deno.land/std@0.177.0/http/server.ts";

import {
  HttpError,
  jsonResponse,
  requireServiceRole,
  serviceRoleClient,
} from "../_shared/attune_auth.ts";
import {
  CHAT_SAFETY_CONFIG,
  detectImmediateFamilies,
} from "../_shared/chat_safety.ts";

// Scans Truth or Dare answers with the SAME detector as chat messages.
//
// TRUTH_OR_DARE.md §4.4: truth answers are free text and may carry
// distressing content, so they run through the same hard-coded keyword
// check, surfacing resources privately to the READER rather than the
// writer, with the game continuing uninterrupted.
//
// The detector is imported from _shared/chat_safety.ts rather than
// reimplemented: two wordlists would drift, and the one that drifted
// would be the one nobody was watching.
const DEFAULT_LIMIT = 20;
const MAX_ATTEMPTS = 5;
const SAFETY_PUSH_TITLE = "Private update in Attune";
const SAFETY_PUSH_BODY = "Open Attune for support resources.";

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return jsonResponse({ ok: true });
  }

  try {
    requireServiceRole(req);
    const supabase = serviceRoleClient();
    const body = req.method === "POST"
      ? await req.json().catch((): Record<string, unknown> => ({}))
      : {};

    const limit = typeof body.limit === "number" ? body.limit : DEFAULT_LIMIT;

    const { data: jobs, error } = await supabase
      .from("truth_answer_safety_outbox")
      .select("round_id, relationship_id, answering_user_id, source_event_key, attempts")
      .eq("state", "pending")
      .order("created_at", { ascending: true })
      .limit(limit);

    if (error) throw error;

    const results = [];
    for (const job of jobs ?? []) {
      results.push(await processJob(supabase, job));
    }

    return jsonResponse({ success: true, processed: results.length, results });
  } catch (error) {
    const status = error instanceof HttpError ? error.status : 500;
    const message = error instanceof Error ? error.message : "Unknown error";
    return jsonResponse({ success: false, error: message }, status);
  }
});

async function processJob(
  supabase: ReturnType<typeof serviceRoleClient>,
  job: Record<string, unknown>,
) {
  const roundId = String(job.round_id);
  const attempts = Number(job.attempts ?? 0);

  try {
    const { data: round, error: roundError } = await supabase
      .from("game_session_rounds")
      .select("id, answer_a, answer_b, chosen_type")
      .eq("id", roundId)
      .maybeSingle();

    if (roundError) throw roundError;
    if (!round) {
      await finalize(supabase, roundId, "done", "round_missing");
      return { round_id: roundId, status: "skipped", reason: "round_missing" };
    }

    const { data: relationship, error: relError } = await supabase
      .from("relationships")
      .select("id, user_a, user_b")
      .eq("id", String(job.relationship_id))
      .maybeSingle();

    if (relError) throw relError;
    if (!relationship) {
      await finalize(supabase, roundId, "done", "relationship_missing");
      return { round_id: roundId, status: "skipped" };
    }

    const answeringUserId = String(job.answering_user_id);

    // The at-risk user is the READER — the partner about to see this
    // answer — not the person who wrote it. §4.4 is explicit: resources go
    // to the reader, privately, and the writer is never told.
    const atRiskUserId = relationship.user_a === answeringUserId
      ? String(relationship.user_b)
      : String(relationship.user_a);

    // The answering partner's own text, never the reveal sentinel in the
    // other slot.
    const text = (relationship.user_a === answeringUserId
      ? round.answer_a
      : round.answer_b) ?? "";

    const matches = detectImmediateFamilies(String(text).trim())
      .sort((a, b) => a.highestTier - b.highestTier);
    const chosen = matches[0];

    if (!chosen) {
      await finalize(supabase, roundId, "done", null);
      return { round_id: roundId, status: "completed", matched: false };
    }

    const { data: event, error: eventError } = await supabase
      .from("safety_events")
      .upsert({
        relationship_id: relationship.id,
        at_risk_user_id: atRiskUserId,
        source_event_key: String(job.source_event_key),
        trigger_tier: chosen.highestTier,
        trigger_family: chosen.family,
        config_version: CHAT_SAFETY_CONFIG.config_version,
        notification_status: "pending",
      }, { onConflict: "source_event_key" })
      .select("id")
      .maybeSingle();

    if (eventError) throw eventError;

    if (event?.id) {
      const { error: notifyError } = await supabase.rpc(
        "enqueue_safety_resource_notification",
        {
          p_safety_event_id: event.id,
          p_user_id: atRiskUserId,
          p_title: SAFETY_PUSH_TITLE,
          p_body: SAFETY_PUSH_BODY,
        },
      );
      if (notifyError) throw notifyError;
    }

    // Recorded on the round so the client can show the reader their
    // resources in place, without re-scanning the text on the device.
    const { error: flagError } = await supabase
      .from("game_session_rounds")
      .update({ safety_triggered: true })
      .eq("id", roundId);
    if (flagError) throw flagError;

    await finalize(supabase, roundId, "done", null);
    return {
      round_id: roundId,
      status: "completed",
      matched: true,
      tier: chosen.highestTier,
    };
  } catch (error) {
    const code = error instanceof Error ? error.message : "unknown";
    const nextState = attempts + 1 >= MAX_ATTEMPTS ? "dead_letter" : "pending";
    await finalize(supabase, roundId, nextState, code, attempts + 1);
    return { round_id: roundId, status: nextState, error: code };
  }
}

async function finalize(
  supabase: ReturnType<typeof serviceRoleClient>,
  roundId: string,
  state: string,
  errorCode: string | null,
  attempts?: number,
) {
  const payload: Record<string, unknown> = {
    state,
    last_error_code: errorCode,
    completed_at: state === "done" ? new Date().toISOString() : null,
    updated_at: new Date().toISOString(),
  };

  // Incremented only on a failure. Without this the count never moves and
  // MAX_ATTEMPTS never trips, so a permanently failing row is retried
  // forever instead of dead-lettering.
  if (attempts !== undefined) payload.attempts = attempts;

  await supabase
    .from("truth_answer_safety_outbox")
    .update(payload)
    .eq("round_id", roundId);
}
