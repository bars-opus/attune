import { serve } from "https://deno.land/std@0.177.0/http/server.ts";

import { HttpError, jsonResponse, requireServiceRole, serviceRoleClient } from "../_shared/attune_auth.ts";

const DEFAULT_LIMIT = 20;
const MAX_ATTEMPTS = 5;
const CHAT_PUSH_TITLE = "New message in Attune";
const CHAT_PUSH_BODY = "Open Attune to read it.";
const REACTION_PUSH_TITLE = "New reaction";

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
      // Deliberately NOT marked delivered. A recipient with push disabled
      // still receives the message, but nothing here observes their device
      // getting it -- their own client marks it delivered when it does.
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

    const isReaction = job.notification_type === "message_reaction";
    const previewEnabled = settings?.chat_message_preview_enabled === true;
    const title = isReaction ? REACTION_PUSH_TITLE : CHAT_PUSH_TITLE;
    const body = isReaction
      ? reactionBody(job, previewEnabled ? previewBody(message) : null)
      : (previewEnabled ? previewBody(message) : CHAT_PUSH_BODY);
    const now = new Date().toISOString();

    const inAppResult = await supabase
      .from("in_app_notifications")
      .insert({
        user_id: recipientId,
        title,
        body,
        data: {
          type: isReaction ? "message_reaction" : "new_message",
          relationship_id: relationship.id,
          outbox_id: outboxId,
        },
      });
    if (inAppResult.error) throw inAppResult.error;

    if (suppressPush) {
      // Suppressed because the recipient is actively viewing this
      // conversation — which means it HAS reached them. Their client marks
      // it delivered too, and the RPC only writes a null delivered_at, so
      // whichever lands first wins and the other is a no-op.
      await markDelivered(supabase, String(job.message_id), recipientId);
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
          type: isReaction ? "message_reaction" : "new_message",
          relationship_id: relationship.id,
          outbox_id: outboxId,
        },
        created_at: now,
        updated_at: now,
      });
    if (scheduledResult.error) throw scheduledResult.error;

    // NOT marked delivered here. Queuing a push is not delivery: this
    // point is reached whether the recipient's device is reachable or
    // switched off, so stamping delivered_at here showed the sender two
    // checks for a message sitting in a queue nobody had received.
    //
    // Delivery is claimed only where it is actually observed -- the
    // recipient's own client calls markDelivered once the row is on their
    // device (_markPartnerMessagesDelivered), and the suppressed-because-
    // actively-viewing branch above, where the recipient is demonstrably
    // looking at the conversation.

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

function reactionBody(job: Record<string, unknown>, messagePreview: string | null) {
  const emoji = typeof job.reaction_emoji === "string" ? job.reaction_emoji : "❤️";
  if (messagePreview) {
    return `${emoji} reacted to "${messagePreview.slice(0, 60)}"`;
  }
  return `${emoji} reacted to your message`;
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

/// Marks a message delivered at the moment its notification is dispatched.
///
/// Delivery was previously recorded only when the recipient opened that
/// conversation, so a message sat on one tick until then — and opening
/// also marks it read, so the delivered state was rarely seen at all.
///
/// Never fatal: a message that was pushed but not marked delivered is a
/// cosmetic receipt problem, while failing the job here would retry a push
/// the recipient has already received.
async function markDelivered(
  supabase: ReturnType<typeof serviceRoleClient>,
  messageId: string,
  recipientId: string,
) {
  const { error } = await supabase.rpc("mark_delivered_for_recipient", {
    p_message_id: messageId,
    p_recipient_id: recipientId,
  });
  if (error) {
    console.error("mark_delivered_for_recipient failed", error.message);
  }
}
