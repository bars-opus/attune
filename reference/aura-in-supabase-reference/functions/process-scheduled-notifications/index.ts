import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";
import { redactError } from "../_shared/sanitize.ts";
import {
  sendWhatsAppTemplate,
  WhatsAppTemplateNotFoundError,
} from "../_shared/whatsapp_client.ts";

// ── Config ────────────────────────────────────────────────────────────────────

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ONE_SIGNAL_APP_ID = Deno.env.get("ONE_SIGNAL_APP_ID")!;
const ONE_SIGNAL_API_KEY = Deno.env.get("ONE_SIGNAL_API_KEY")!;
const BATCH_LIMIT = 50;

// Uses service role: bypasses RLS so the scheduler can read all pending rows.
const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
  auth: { persistSession: false },
});

// ── OneSignal delivery ────────────────────────────────────────────────────────

async function sendPush(
  userId: string,
  title: string,
  body: string,
  data: Record<string, unknown>
): Promise<void> {
  const resp = await fetch("https://onesignal.com/api/v1/notifications", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Basic ${ONE_SIGNAL_API_KEY}`,
    },
    signal: AbortSignal.timeout(10_000),
    body: JSON.stringify({
      app_id: ONE_SIGNAL_APP_ID,
      include_external_user_ids: [userId],
      headings: { en: title },
      contents: { en: body },
      data,
      priority: 5,
    }),
  });

  if (!resp.ok) {
    const err = await resp.json();
    throw new Error(`OneSignal error: ${JSON.stringify(err)}`);
  }
}

// ── User settings check ───────────────────────────────────────────────────────

async function isPushEnabled(userId: string): Promise<boolean> {
  const { data } = await supabase
    .from("notification_settings")
    .select("push_enabled")
    .eq("user_id", userId)
    .maybeSingle();

  // Default to true when no settings row exists yet.
  return data?.push_enabled !== false;
}

// ── WhatsApp delivery ─────────────────────────────────────────────────────────
//
// Rows with delivery_channel='whatsapp' are inserted by Plan A's webhooks
// (paystack-webhook / stripe-webhook) for guest bookings. The worker calls
// the internal whatsapp-send function with service-role auth, then persists
// the returned message_id into metadata so whatsapp-webhook can match
// delivery receipts back to this row.
//
// Failure modes:
//   - template_not_found (HTTP 202 from whatsapp-send): defer 6 h and retry,
//     because Meta template approval is async — the template may be approved
//     by the next attempt.
//   - transient error: exponential backoff (30 s, 5 min, 30 min), max 3 attempts.
//   - permanent error after 3 retries: mark failed.

interface ScheduledNotificationRow {
  id: string;
  user_id?: string | null;
  guest_profile_id?: string | null;
  notification_type?: string | null;
  delivery_channel?: string | null;
  whatsapp_template?: string | null;
  whatsapp_params?: Record<string, string> | null;
  metadata?: Record<string, unknown> | null;
  retry_count?: number | null;
}

async function dispatchWhatsApp(
  row: ScheduledNotificationRow
): Promise<void> {
  const meta = (row.metadata as Record<string, unknown> | null) ?? {};
  const phone = typeof meta.phone === "string" ? meta.phone : undefined;
  const template = row.whatsapp_template;
  const params = row.whatsapp_params ?? {};

  if (!phone || !template) {
    await markFailed(row.id, "missing phone or template");
    return;
  }

  // Call Meta directly — avoids a function-to-function hop that requires
  // forwarding the platform JWT (the auto-injected SUPABASE_SERVICE_ROLE_KEY
  // in the edge runtime didn't validate against whatsapp-send's verify_jwt
  // gate). Both functions wrap the same _shared/whatsapp_client helper,
  // so the contract is identical.
  const orderedParams = Object.keys(params)
    .sort((a, b) => parseInt(a) - parseInt(b))
    .map((k) => (params as Record<string, string>)[k]);

  let messageId: string;
  try {
    const result = await sendWhatsAppTemplate({
      to: phone,
      templateName: template,
      bodyParams: orderedParams,
    });
    messageId = result.messageId;
  } catch (err) {
    if (err instanceof WhatsAppTemplateNotFoundError) {
      // Template not yet approved at Meta — defer 6 h and retry.
      await deferNotification(row.id, 6 * 60 * 60 * 1000);
      return;
    }
    await incrementWhatsAppRetryOrFail(
      row.id,
      row.retry_count ?? 0,
      meta,
      `Meta send failed: ${redactError(err)}`,
    );
    return;
  }

  // Synthesize the old shape so the success path below stays unchanged.
  const res = { ok: true, status: 200 } as { ok: boolean; status: number };
  const body = { success: true, messageId } as {
    success?: boolean;
    error?: string;
    message?: string;
    messageId?: string;
  };

  if (!res.ok || !body.success) {
    await incrementWhatsAppRetryOrFail(
      row.id,
      row.retry_count ?? 0,
      meta,
      body.message ?? `whatsapp-send returned ${res.status}`
    );
    return;
  }

  // Success — record message_id for whatsapp-webhook receipt matching.
  await markSentWithMessageId(row.id, body.messageId ?? "", meta);
}

async function markSentWithMessageId(
  id: string,
  messageId: string,
  prevMetadata: Record<string, unknown>
): Promise<void> {
  await supabase
    .from("scheduled_notifications")
    .update({
      status: "sent",
      metadata: { ...prevMetadata, message_id: messageId },
      updated_at: new Date().toISOString(),
    })
    .eq("id", id);
}

async function markFailed(id: string, reason: string): Promise<void> {
  await supabase
    .from("scheduled_notifications")
    .update({
      status: "failed",
      last_error: reason,
      updated_at: new Date().toISOString(),
    })
    .eq("id", id);
}

async function deferNotification(id: string, deferMs: number): Promise<void> {
  await supabase
    .from("scheduled_notifications")
    .update({
      scheduled_for: new Date(Date.now() + deferMs).toISOString(),
      status: "pending",
      updated_at: new Date().toISOString(),
    })
    .eq("id", id);
}

async function incrementWhatsAppRetryOrFail(
  id: string,
  prevRetryCount: number,
  prevMetadata: Record<string, unknown>,
  reason: string
): Promise<void> {
  const retryCount = (prevRetryCount ?? 0) + 1;
  if (retryCount >= 3) {
    await markFailed(id, `${reason} (after ${retryCount} attempts)`);
    return;
  }

  // Exponential backoff: 30 s, 5 min, 30 min.
  const backoffs = [30_000, 5 * 60_000, 30 * 60_000];
  const delayMs = backoffs[retryCount - 1] ?? 30 * 60_000;
  await supabase
    .from("scheduled_notifications")
    .update({
      scheduled_for: new Date(Date.now() + delayMs).toISOString(),
      status: "pending",
      retry_count: retryCount,
      last_error: reason,
      metadata: { ...prevMetadata },
      updated_at: new Date().toISOString(),
    })
    .eq("id", id);
}

// ── Handler ───────────────────────────────────────────────────────────────────

serve(async () => {
  try {
    // Claim a batch atomically: flip status to 'processing' so a concurrent
    // run of this cron cannot pick up the same rows.
    const now = new Date().toISOString();

    // Atomic claim — single statement transitions rows from pending→processing
    // via FOR UPDATE SKIP LOCKED, so overlapping cron runs can't grab the same
    // rows. See migration 20260601130000_atomic_claim_scheduled_notifications.
    const { data: pending, error: fetchError } = await supabase
      .rpc("claim_pending_notifications", { p_limit: BATCH_LIMIT, p_now: now });

    if (fetchError) throw fetchError;
    if (!pending || pending.length === 0) {
      return new Response(
        JSON.stringify({ success: true, processed: 0, total: 0 }),
        { headers: { "Content-Type": "application/json" } }
      );
    }

    let processed = 0;

    for (const notification of pending) {
      try {
        // Branch by delivery channel. Default ('push' or missing) keeps the
        // existing OneSignal flow; 'whatsapp' rows are inserted by Plan A's
        // webhooks and routed to the WhatsApp dispatcher.
        if (notification.delivery_channel === "whatsapp") {
          await dispatchWhatsApp(notification as ScheduledNotificationRow);
          processed++;
          continue;
        }

        // Respect the user's push preference.
        const enabled = await isPushEnabled(notification.user_id);
        if (!enabled) {
          await supabase
            .from("scheduled_notifications")
            .update({ status: "skipped", updated_at: new Date().toISOString() })
            .eq("id", notification.id);
          continue;
        }

        const { title, body, ...rest } = notification.metadata ?? {};

        if (!title || !body) {
          throw new Error("Notification metadata missing title or body");
        }

        await sendPush(notification.user_id, title, body, rest);

        await supabase
          .from("scheduled_notifications")
          .update({ status: "sent", updated_at: new Date().toISOString() })
          .eq("id", notification.id);

        processed++;
      } catch (err) {
        const retryCount = (notification.retry_count ?? 0) + 1;
        // Exponential backoff: on next run only pick up notifications whose
        // scheduled_for has passed. We bump scheduled_for forward so they
        // naturally sit out until the back-off window expires.
        const backoffMinutes = Math.pow(2, retryCount); // 2, 4, 8 …
        const nextAttempt = new Date(
          Date.now() + backoffMinutes * 60 * 1000
        ).toISOString();

        const newStatus = retryCount >= 5 ? "failed" : "pending";

        await supabase
          .from("scheduled_notifications")
          .update({
            status: newStatus,
            retry_count: retryCount,
            last_error: redactError(err),
            scheduled_for: newStatus === "pending" ? nextAttempt : undefined,
            updated_at: new Date().toISOString(),
          })
          .eq("id", notification.id);

        console.error(
          `Notification ${notification.id} failed (attempt ${retryCount}):`,
          redactError(err),
        );
      }
    }

    return new Response(
      JSON.stringify({ success: true, processed, total: pending.length }),
      { headers: { "Content-Type": "application/json" } }
    );
  } catch (error) {
    console.error("process-scheduled-notifications error:", redactError(error));
    return new Response(
      JSON.stringify({ success: false, error: "internal_error" }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }
});
