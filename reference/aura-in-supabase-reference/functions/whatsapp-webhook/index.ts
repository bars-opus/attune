// supabase/functions/whatsapp-webhook/index.ts
//
// Public edge function (verify_jwt = false). Two paths:
//
// 1. GET ?hub.mode=subscribe&hub.verify_token=<x>&hub.challenge=<n>
//    Meta sends this when configuring/re-verifying the webhook URL.
//    We compare hub.verify_token against WHATSAPP_VERIFY_TOKEN env and
//    echo hub.challenge on match (200), else 403.
//
// 2. POST events
//    Signature-verified via X-Hub-Signature-256 header (HMAC-SHA256 of the
//    raw body using WHATSAPP_APP_SECRET).
//    - status updates -> patch scheduled_notifications.status by message_id
//    - inbound messages -> log only; foundation for future WhatsApp agent

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient, SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";
import { verifyMetaSignature } from "../_shared/whatsapp_client.ts";
import { redactError, redactPhone } from "../_shared/sanitize.ts";

let _supabase: SupabaseClient | null = null;
function getSupabase(): SupabaseClient {
  if (!_supabase) {
    _supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );
  }
  return _supabase;
}

export async function handler(req: Request): Promise<Response> {
  if (req.method === "GET") return handleHandshake(req);
  if (req.method === "POST") return handleEvent(req);
  return new Response("Method not allowed", { status: 405 });
}

async function handleHandshake(req: Request): Promise<Response> {
  const url = new URL(req.url);
  const mode = url.searchParams.get("hub.mode");
  const token = url.searchParams.get("hub.verify_token");
  const challenge = url.searchParams.get("hub.challenge");
  const expected = Deno.env.get("WHATSAPP_VERIFY_TOKEN");

  if (mode === "subscribe" && expected && token === expected && challenge) {
    return new Response(challenge, { status: 200 });
  }
  return new Response("Forbidden", { status: 403 });
}

async function handleEvent(req: Request): Promise<Response> {
  const rawBody = await req.text();
  const signature = req.headers.get("X-Hub-Signature-256") ?? "";

  // verifyMetaSignature throws only if WHATSAPP_APP_SECRET is unset.
  // For all other cases (no header, wrong digest, malformed) it returns false.
  let isValid = false;
  try {
    isValid = await verifyMetaSignature(rawBody, signature);
  } catch (e) {
    console.error("WhatsApp signature check failed:", redactError(e));
    return new Response("Misconfigured", { status: 500 });
  }
  if (!isValid) {
    console.error("WhatsApp: invalid signature");
    return new Response("Forbidden", { status: 403 });
  }

  let event: any;
  try { event = JSON.parse(rawBody); } catch {
    return new Response("Invalid JSON", { status: 400 });
  }

  for (const entry of event.entry ?? []) {
    for (const change of entry.changes ?? []) {
      const value = change.value;
      // Delivery / read / failed status updates
      for (const status of value.statuses ?? []) {
        await handleDeliveryStatus(status);
      }
      // Inbound messages — v1: log only. Future Spec 4 processes these.
      // Do NOT log the full message payload — it contains the sender's full
      // phone number and message text (PII per checklist 4.4). Log only the
      // shape we need to confirm receipt.
      for (const msg of value.messages ?? []) {
        console.log("Inbound WhatsApp:", {
          from: redactPhone(msg.from),
          type: msg.type,
          wamid: msg.id,
          timestamp: msg.timestamp,
        });
      }
    }
  }

  return new Response(JSON.stringify({ received: true }), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
}

async function handleDeliveryStatus(status: any): Promise<void> {
  // status.id is the wamid we returned from whatsapp-send. We stored it in
  // scheduled_notifications.metadata.message_id for matching (Task 5 worker).
  const messageId = status.id;
  const newStatus = status.status; // 'sent' | 'delivered' | 'read' | 'failed'
  if (!messageId) return;

  // Map Meta status -> our status. We treat 'failed' as failed; everything
  // else (sent/delivered/read) collapses to 'sent' since v1 doesn't track
  // read receipts beyond a coarse delivery indicator.
  const dbStatus = newStatus === "failed" ? "failed" : "sent";

  const supabase = getSupabase();
  const { error } = await supabase
    .from("scheduled_notifications")
    .update({
      status: dbStatus,
      updated_at: new Date().toISOString(),
    })
    .eq("metadata->>message_id", messageId);

  if (error) {
    console.error("scheduled_notifications status update failed:", redactError(error));
  }
}

serve(handler);
