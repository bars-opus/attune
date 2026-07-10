import { serve } from "https://deno.land/std@0.177.0/http/server.ts";

import { HttpError, jsonResponse, requireServiceRole, serviceRoleClient } from "../_shared/attune_auth.ts";

const DEFAULT_LIMIT = 20;
const MAX_ATTEMPTS = 5;
const CHAT_PUSH_TITLE = "New message in Attune";
const CHAT_PUSH_BODY = "Open Attune to read it.";

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
      outboxId: typeof body.outbox_id === "string" ? body.outbox_id : undefined,
      limit: typeof body.limit === "number" ? body.limit : DEFAULT_LIMIT,
    });

    const results = [];
    for (const job of jobs) {
      const claimed = await claimJob(supabase, String(job.id));
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
  options: { outboxId?: string; limit: number },
) {
  let query = supabase
    .from("message_notification_outbox")
    .select("*")
    .eq("state", "pending")
    .order("created_at", { ascending: true })
    .limit(Math.min(Math.max(options.limit, 1), 100));

  if (options.outboxId) {
    query = query.eq("id", options.outboxId);
  }

  const { data, error } = await query;
  if (error) throw error;
  return data ?? [];
}

async function claimJob(
  supabase: ReturnType<typeof serviceRoleClient>,
  outboxId: string,
) {
  const { data: current, error: currentError } = await supabase
    .from("message_notification_outbox")
    .select("attempts")
    .eq("id", outboxId)
    .eq("state", "pending")
    .maybeSingle();

  if (currentError) throw currentError;
  if (!current) return null;

  const { data, error } = await supabase
    .from("message_notification_outbox")
    .update({
      state: "processing",
      attempts: Number(current.attempts ?? 0) + 1,
      processing_started_at: new Date().toISOString(),
      completed_at: null,
      last_error_code: null,
    })
    .eq("id", outboxId)
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
  const outboxId = String(job.id);
  const attempts = Number(job.attempts ?? 0);

  try {
    const { data: message, error } = await supabase
      .from("messages")
      .select(`
        id,
        relationship_id,
        sender_id,
        content,
        media_type,
        relationships!inner (
          id,
          status,
          chat_archived_at,
          user_a,
          user_b
        )
      `)
      .eq("id", String(job.message_id))
      .maybeSingle();

    if (error) throw error;
    if (!message) {
      await finalizeJob(supabase, outboxId, "done", "message_missing");
      return { outbox_id: outboxId, status: "skipped", reason: "message_missing" };
    }

    const relationship = unwrapRelationship(message.relationships);
    const recipientId = String(job.recipient_id);
    const senderId = String(job.sender_id);

    if (
      !relationship ||
      relationship.status !== "active" ||
      relationship.chat_archived_at ||
      senderId === recipientId ||
      !isRelationshipMember(relationship, senderId) ||
      !isRelationshipMember(relationship, recipientId)
    ) {
      await finalizeJob(supabase, outboxId, "done", "suppressed_relationship_state");
      return {
        outbox_id: outboxId,
        status: "suppressed",
        reason: "suppressed_relationship_state",
      };
    }

    const { data: settings, error: settingsError } = await supabase
      .from("notification_settings")
      .select("push_enabled, booking_reminders_enabled, chat_message_preview_enabled")
      .eq("user_id", recipientId)
      .maybeSingle();

    if (settingsError) throw settingsError;

    if (
      settings &&
      (settings.push_enabled === false ||
          settings.booking_reminders_enabled === false)
    ) {
      await finalizeJob(
        supabase,
        outboxId,
        "done",
        "suppressed_notifications_disabled",
      );
      return { outbox_id: outboxId, status: "suppressed", reason: "suppressed_push_disabled" };
    }

    // Spec 9.2: do not send a push if the recipient is already actively
    // viewing this conversation. The in-app tick below is still recorded (the
    // spec notes in-app ticks are sufficient) — only the push is suppressed.
    let suppressPush = false;
    {
      const { data: viewing, error: viewingError } = await supabase.rpc(
        "is_actively_viewing",
        {
          p_user_id: recipientId,
          p_relationship_id: relationship.id,
          p_window_seconds: 30,
        },
      );
      // On error, fail open (send the push) rather than silently drop it.
      if (!viewingError && viewing === true) suppressPush = true;
    }

    const previewEnabled = settings?.chat_message_preview_enabled === true;
    const title = CHAT_PUSH_TITLE;
    const body = previewEnabled ? previewBody(message) : CHAT_PUSH_BODY;
    const now = new Date().toISOString();

    const inAppResult = await supabase
      .from("in_app_notifications")
      .insert({
        user_id: recipientId,
        title,
        body,
        data: {
          type: "new_message",
          relationship_id: relationship.id,
          outbox_id: outboxId,
        },
      });
    if (inAppResult.error) throw inAppResult.error;

    if (suppressPush) {
      await finalizeJob(supabase, outboxId, "done", "suppressed_actively_viewing");
      return {
        outbox_id: outboxId,
        status: "completed",
        push: "suppressed_actively_viewing",
      };
    }

    const scheduledResult = await supabase
      .from("scheduled_notifications")
      .insert({
        user_id: recipientId,
        notification_type: "immediate",
        scheduled_for: now,
        status: "pending",
        metadata: {
          title,
          body,
          type: "new_message",
          relationship_id: relationship.id,
          outbox_id: outboxId,
        },
        created_at: now,
        updated_at: now,
      });
    if (scheduledResult.error) throw scheduledResult.error;

    await finalizeJob(supabase, outboxId, "done", null);
    return { outbox_id: outboxId, status: "completed" };
  } catch (error) {
    const code = errorCode(error);
    const nextState = attempts + 1 >= MAX_ATTEMPTS ? "dead_letter" : "pending";
    await finalizeJob(supabase, outboxId, nextState, code);
    return { outbox_id: outboxId, status: nextState, error: code };
  }
}

async function finalizeJob(
  supabase: ReturnType<typeof serviceRoleClient>,
  outboxId: string,
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
    .from("message_notification_outbox")
    .update(payload)
    .eq("id", outboxId);
  if (error) throw error;
}

function previewBody(message: Record<string, unknown>) {
  if (typeof message.content === "string" && message.content.trim().length > 0) {
    return message.content.trim().slice(0, 140);
  }
  if (message.media_type === "image") {
    return "Photo";
  }
  return CHAT_PUSH_BODY;
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

function isRelationshipMember(
  relationship: { user_a: string; user_b: string } | null,
  userId: string,
) {
  if (!relationship) return false;
  return relationship.user_a === userId || relationship.user_b === userId;
}

function errorCode(error: unknown) {
  if (error instanceof Error) {
    return error.message.slice(0, 120);
  }
  return "unknown_error";
}
