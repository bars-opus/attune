import { serve } from "https://deno.land/std@0.177.0/http/server.ts";

import {
  HttpError,
  jsonResponse,
  requireEnv,
  requireServiceRole,
  serviceRoleClient,
} from "../_shared/attune_auth.ts";
import {
  CHAT_SAFETY_CONFIG,
  computeSafetySourceEventKey,
  detectImmediateFamilies,
  detectTierThreeRuleIds,
} from "../_shared/chat_safety.ts";

const MAX_ATTEMPTS = 5;
const DEFAULT_LIMIT = 20;
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

    const jobs = await loadJobs(supabase, {
      messageId: typeof body.message_id === "string" ? body.message_id : undefined,
      limit: typeof body.limit === "number" ? body.limit : DEFAULT_LIMIT,
    });

    const results = [];
    for (const job of jobs) {
      const claimed = await claimJob(supabase, job.message_id);
      if (!claimed) continue;
      results.push(await processJob(supabase, claimed));
    }

    return jsonResponse({
      success: true,
      processed: results.length,
      results,
    });
  } catch (error) {
    const status = error instanceof HttpError ? error.status : 500;
    const message = error instanceof Error ? error.message : "Unknown error";
    return jsonResponse({ success: false, error: message }, status);
  }
});

async function loadJobs(
  supabase: ReturnType<typeof serviceRoleClient>,
  options: { messageId?: string; limit: number },
) {
  let query = supabase
    .from("message_safety_outbox")
    .select("*")
    .eq("state", "pending")
    .order("created_at", { ascending: true })
    .limit(Math.min(Math.max(options.limit, 1), 100));

  if (options.messageId) {
    query = query.eq("message_id", options.messageId);
  }

  const { data, error } = await query;
  if (error) throw error;
  return data ?? [];
}

async function claimJob(
  supabase: ReturnType<typeof serviceRoleClient>,
  messageId: string,
) {
  const { data: current, error: currentError } = await supabase
    .from("message_safety_outbox")
    .select("attempts")
    .eq("message_id", messageId)
    .eq("state", "pending")
    .maybeSingle();

  if (currentError) throw currentError;
  if (!current) return null;

  const { data, error } = await supabase
    .from("message_safety_outbox")
    .update({
      state: "processing",
      attempts: Number(current.attempts ?? 0) + 1,
      processing_started_at: new Date().toISOString(),
      completed_at: null,
      last_error_code: null,
    })
    .eq("message_id", messageId)
    .eq("state", "pending")
    .select("*")
    .maybeSingle();
  if (error) throw error;

  return data;
}

async function processJob(
  supabase: ReturnType<typeof serviceRoleClient>,
  job: Record<string, unknown>,
) {
  const messageId = String(job.message_id);
  const attempts = Number(job.attempts ?? 0);

  try {
    const { data: message, error } = await supabase
      .from("messages")
      .select(`
        id,
        relationship_id,
        sender_id,
        content,
        created_at,
        relationships!inner (
          id,
          status,
          chat_archived_at,
          user_a,
          user_b
        )
      `)
      .eq("id", messageId)
      .maybeSingle();

    if (error) throw error;
    if (!message) {
      await finalizeJob(supabase, messageId, "done", "message_missing");
      return { message_id: messageId, status: "skipped", reason: "message_missing" };
    }

    const relationship = unwrapRelationship(message.relationships);
    const atRiskUserId = getRecipientId(relationship, String(message.sender_id));
    const text = typeof message.content === "string" ? message.content.trim() : "";

    if (!relationship || !atRiskUserId) {
      await markMessageSafetyComplete(supabase, messageId, "relationship_invalid");
      await finalizeJob(supabase, messageId, "done", "relationship_invalid");
      await dispatchLayerOneAnalysis(messageId);
      return { message_id: messageId, status: "skipped", reason: "relationship_invalid" };
    }

    if (relationship.status !== "active" || relationship.chat_archived_at) {
      await markMessageSafetyComplete(supabase, messageId, "relationship_inactive");
      await finalizeJob(supabase, messageId, "done", "relationship_inactive");
      await dispatchLayerOneAnalysis(messageId);
      return { message_id: messageId, status: "skipped", reason: "relationship_inactive" };
    }

    if (text.length === 0) {
      await markMessageSafetyComplete(supabase, messageId, null);
      await finalizeJob(supabase, messageId, "done", null);
      await dispatchLayerOneAnalysis(messageId);
      return { message_id: messageId, status: "completed", matched: false };
    }

    const sourceEventKey = await ensureSourceEventKey(supabase, messageId, job);
    const immediateMatches = detectImmediateFamilies(text);
    const tierThreeMatch = await resolveTierThreeMatch(
      supabase,
      relationship.id,
      atRiskUserId,
      sourceEventKey,
      String(message.created_at),
      text,
    );

    const allMatches = [...immediateMatches, ...(tierThreeMatch ? [tierThreeMatch] : [])]
      .sort((a, b) => a.highestTier - b.highestTier);

    const chosen = allMatches[0];
    if (!chosen) {
      await markMessageSafetyComplete(supabase, messageId, null);
      await finalizeJob(supabase, messageId, "done", null);
      await dispatchLayerOneAnalysis(messageId);
      return { message_id: messageId, status: "completed", matched: false };
    }

    const { data: insertedEvent, error: eventError } = await supabase
      .from("safety_events")
      .upsert({
        relationship_id: relationship.id,
        at_risk_user_id: atRiskUserId,
        source_event_key: sourceEventKey,
        trigger_tier: chosen.highestTier,
        trigger_family: chosen.family,
        config_version: CHAT_SAFETY_CONFIG.config_version,
        notification_status: "pending",
      }, { onConflict: "source_event_key" })
      .select("id, notification_status")
      .maybeSingle();

    if (eventError) throw eventError;

    if (insertedEvent?.id) {
      await maybeQueueSafetyNotification(supabase, insertedEvent.id, atRiskUserId);
    }

    await markMessageSafetyComplete(supabase, messageId, null);
    await finalizeJob(supabase, messageId, "done", null);
    await dispatchLayerOneAnalysis(messageId);
    return {
      message_id: messageId,
      status: "completed",
      matched: true,
      tier: chosen.highestTier,
      family: chosen.family,
    };
  } catch (error) {
    const code = errorCode(error);
    const nextState = attempts + 1 >= MAX_ATTEMPTS ? "dead_letter" : "pending";
    await markMessageSafetyFailure(
      supabase,
      messageId,
      code,
      nextState === "dead_letter",
    );
    await finalizeJob(supabase, messageId, nextState, code);
    if (nextState === "dead_letter") {
      await dispatchLayerOneAnalysis(messageId);
    }
    return { message_id: messageId, status: nextState, error: code };
  }
}

async function ensureSourceEventKey(
  supabase: ReturnType<typeof serviceRoleClient>,
  messageId: string,
  job: Record<string, unknown>,
) {
  const existing = typeof job.source_event_key === "string" ? job.source_event_key : null;
  if (existing && existing.length > 0) {
    return existing;
  }

  const secret = requireEnv("SAFETY_EVENT_HMAC_SECRET");
  const sourceEventKey = await computeSafetySourceEventKey(messageId, secret);
  const { error } = await supabase
    .from("message_safety_outbox")
    .update({ source_event_key: sourceEventKey })
    .eq("message_id", messageId);
  if (error) throw error;
  return sourceEventKey;
}

async function resolveTierThreeMatch(
  supabase: ReturnType<typeof serviceRoleClient>,
  relationshipId: string,
  atRiskUserId: string,
  sourceEventKey: string,
  occurredAt: string,
  content: string,
) {
  const ruleIds = detectTierThreeRuleIds(content);
  if (ruleIds.length === 0) return null;

  const familyConfig = CHAT_SAFETY_CONFIG.tiers.pattern_control;
  const windowDays = familyConfig.window_days ?? 30;
  const cutoff = new Date(Date.now() - windowDays * 24 * 60 * 60 * 1000).toISOString();

  for (const ruleId of ruleIds) {
    const insertResult = await supabase
      .from("safety_pattern_occurrences")
      .upsert({
        relationship_id: relationshipId,
        at_risk_user_id: atRiskUserId,
        rule_id: ruleId,
        config_version: CHAT_SAFETY_CONFIG.config_version,
        source_event_key: sourceEventKey,
        occurred_at: occurredAt,
      }, {
        onConflict: "at_risk_user_id,rule_id,config_version,source_event_key",
        ignoreDuplicates: true,
      });

    if (insertResult.error) throw insertResult.error;

    const { data: rows, error } = await supabase
      .from("safety_pattern_occurrences")
      .select("source_event_key")
      .eq("at_risk_user_id", atRiskUserId)
      .eq("rule_id", ruleId)
      .eq("config_version", CHAT_SAFETY_CONFIG.config_version)
      .gte("occurred_at", cutoff);

    if (error) throw error;

    const count = (rows ?? []).length;
    if (count === familyConfig.minimum_occurrences) {
      return {
        highestTier: familyConfig.tier,
        family: "pattern_control",
        matchedRuleIds: [ruleId],
        minimumOccurrences: familyConfig.minimum_occurrences,
        windowDays,
      };
    }
  }

  return null;
}

async function maybeQueueSafetyNotification(
  supabase: ReturnType<typeof serviceRoleClient>,
  safetyEventId: string,
  atRiskUserId: string,
) {
  const { data, error } = await supabase.rpc(
    "enqueue_safety_resource_notification",
    {
      p_safety_event_id: safetyEventId,
      p_user_id: atRiskUserId,
      p_title: SAFETY_PUSH_TITLE,
      p_body: SAFETY_PUSH_BODY,
    },
  );
  if (error) throw error;
  if (typeof data !== "string") {
    throw new Error("invalid_safety_notification_result");
  }
}

async function markMessageSafetyComplete(
  supabase: ReturnType<typeof serviceRoleClient>,
  messageId: string,
  errorCodeValue: string | null,
) {
  const payload: Record<string, unknown> = {
    safety_processed_at: new Date().toISOString(),
  };

  if (errorCodeValue) {
    payload.safety_error_at = new Date().toISOString();
    payload.safety_error_code = errorCodeValue;
  } else {
    payload.safety_error_at = null;
    payload.safety_error_code = null;
  }

  const { error } = await supabase
    .from("messages")
    .update(payload)
    .eq("id", messageId);
  if (error) throw error;
}

async function markMessageSafetyFailure(
  supabase: ReturnType<typeof serviceRoleClient>,
  messageId: string,
  code: string,
  handled: boolean,
) {
  const { error } = await supabase
    .from("messages")
    .update({
      safety_processed_at: handled ? new Date().toISOString() : null,
      safety_error_at: new Date().toISOString(),
      safety_error_code: code,
    })
    .eq("id", messageId);
  if (error) throw error;
}

async function finalizeJob(
  supabase: ReturnType<typeof serviceRoleClient>,
  messageId: string,
  state: "pending" | "done" | "dead_letter",
  lastErrorCode: string | null,
) {
  const payload: Record<string, unknown> = {
    state,
    last_error_code: lastErrorCode,
  };

  if (state === "done" || state === "dead_letter") {
    payload.completed_at = new Date().toISOString();
  } else {
    payload.processing_started_at = null;
  }

  const { error } = await supabase
    .from("message_safety_outbox")
    .update(payload)
    .eq("message_id", messageId);
  if (error) throw error;
}

function unwrapRelationship(value: unknown) {
  if (Array.isArray(value)) {
    return value[0] ?? null;
  }
  return value as {
    id: string;
    status: string;
    chat_archived_at: string | null;
    user_a: string;
    user_b: string;
  } | null;
}

function getRecipientId(
  relationship: { user_a: string; user_b: string } | null,
  senderId: string,
) {
  if (!relationship) return null;
  if (relationship.user_a === senderId) return relationship.user_b;
  if (relationship.user_b === senderId) return relationship.user_a;
  return null;
}

function errorCode(error: unknown) {
  if (error instanceof Error) {
    return error.message.slice(0, 120);
  }
  return "unknown_error";
}

async function dispatchLayerOneAnalysis(messageId: string) {
  const url = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !serviceRoleKey) {
    return;
  }

  try {
    await fetch(`${url}/functions/v1/analyse-message`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${serviceRoleKey}`,
        "apikey": serviceRoleKey,
      },
      body: JSON.stringify({ message_id: messageId }),
      signal: AbortSignal.timeout(3000),
    });
  } catch {
    // Best-effort dispatch only; backlog sweep remains the durable path.
  }
}
