import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { crypto } from "https://deno.land/std@0.224.0/crypto/mod.ts";

// ── Config ────────────────────────────────────────────────────────────────────

const SENDBIRD_WEBHOOK_TOKEN = Deno.env.get("SENDBIRD_WEBHOOK_TOKEN"); // optional but recommended
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-sendbird-signature",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

// ── Signature validation ──────────────────────────────────────────────────────

async function verifySignature(
  rawBody: string,
  signature: string,
  secret: string
): Promise<boolean> {
  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"]
  );
  const sig = await crypto.subtle.sign("HMAC", key, encoder.encode(rawBody));
  const hexSig = Array.from(new Uint8Array(sig))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
  return hexSig === signature;
}

// ── Push helper ───────────────────────────────────────────────────────────────

async function sendPush(
  userId: string,
  title: string,
  body: string,
  data: Record<string, string>
): Promise<void> {
  const res = await fetch(
    `${SUPABASE_URL}/functions/v1/send-onesignal-push`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ userId, title, body, data, priority: "high" }),
    }
  );

  if (!res.ok) {
    const err = await res.text();
    console.error(`Push failed for ${userId}:`, err);
  }
}

// ── Handler ───────────────────────────────────────────────────────────────────

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const rawBody = await req.text();

  // Validate Sendbird webhook signature when token is configured.
  if (SENDBIRD_WEBHOOK_TOKEN) {
    const signature = req.headers.get("x-sendbird-signature") ?? "";
    const valid = await verifySignature(rawBody, signature, SENDBIRD_WEBHOOK_TOKEN);
    if (!valid) {
      console.error("Invalid Sendbird webhook signature");
      return new Response(JSON.stringify({ error: "Forbidden" }), {
        status: 403,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }
  }

  let event: Record<string, unknown>;
  try {
    event = JSON.parse(rawBody);
  } catch {
    return new Response(JSON.stringify({ error: "Invalid JSON" }), {
      status: 400,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const category = event.category as string | undefined;

  // Only process new message events in group channels.
  if (category !== "group_channel:message_send") {
    return new Response(
      JSON.stringify({ skipped: true, category }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }

  const sender = event.sender as { user_id: string; nickname?: string } | undefined;
  const channel = event.channel as { channel_url: string; name?: string } | undefined;
  const payload = event.payload as {
    type?: string;
    message?: string;
    name?: string;
  } | undefined;
  // Sendbird includes channel members with real-time online status in the webhook body.
  const members = (event.members ?? []) as Array<{
    user_id: string;
    nickname?: string;
    is_online: boolean;
    is_push_enabled: boolean;
  }>;

  if (!sender || !channel || !payload) {
    console.error("Malformed webhook payload", event);
    return new Response(JSON.stringify({ error: "Malformed payload" }), {
      status: 400,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const senderUserId = sender.user_id;
  const senderName = sender.nickname || "Someone";
  const channelUrl = channel.channel_url;

  // Build a concise notification body.
  let notifBody: string;
  if (payload.type === "FILE") {
    notifBody = `${senderName} sent a file`;
  } else {
    const text = (payload.message ?? "").trim();
    notifBody = text.length > 100 ? `${text.slice(0, 97)}…` : text || "New message";
  }

  const notifData = {
    type: "new_message",
    channel_url: channelUrl,
    sender_id: senderUserId,
  };

  // Send to every offline member except the sender.
  // is_online reflects Sendbird connection status at the moment the webhook fires.
  // Online users already receive the message in real-time via the SDK.
  const pushJobs = members
    .filter((m) => m.user_id !== senderUserId)
    .filter((m) => !m.is_online)
    .filter((m) => m.is_push_enabled !== false)
    .map((m) => sendPush(m.user_id, senderName, notifBody, notifData));

  await Promise.allSettled(pushJobs);

  console.log(
    `Processed message in ${channelUrl} from ${senderUserId}, ` +
      `notified ${pushJobs.length} offline member(s)`
  );

  return new Response(
    JSON.stringify({ success: true, notified: pushJobs.length }),
    { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
  );
});
