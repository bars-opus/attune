// supabase/functions/_shared/whatsapp_client.ts
//
// Thin wrapper around Meta WhatsApp Cloud API v18. Used by whatsapp-send
// (Task 3) to dispatch template messages and by whatsapp-webhook (Task 4)
// to verify Meta-originated requests.
//
// Required env vars (set via `supabase secrets set`):
//   WHATSAPP_PHONE_NUMBER_ID   — the phone number id from Meta App Dashboard
//   WHATSAPP_ACCESS_TOKEN      — the system-user access token (long-lived)
//   WHATSAPP_APP_SECRET        — for webhook signature verification
//   WHATSAPP_VERIFY_TOKEN      — random string we make up; used by the
//                                Meta webhook handshake (Task 4)

const META_GRAPH_VERSION = "v18.0";

export interface SendTemplateInput {
  to: string;                  // E.164 phone, e.g. "+233201234567"
  templateName: string;        // e.g. "booking_confirmation_v1"
  languageCode?: string;       // default "en"
  bodyParams: string[];        // ordered values for {{1}}, {{2}}, …
}

export interface SendTemplateResult {
  messageId: string;
}

/**
 * Send a template-category WhatsApp message via Meta Cloud API.
 *
 * Throws WhatsAppTemplateNotFoundError when Meta reports the template is
 * not yet approved (caller can defer + retry). Throws plain Error on
 * other failures (transient or permanent).
 */
export async function sendWhatsAppTemplate(
  input: SendTemplateInput,
): Promise<SendTemplateResult> {
  const phoneNumberId = Deno.env.get("WHATSAPP_PHONE_NUMBER_ID");
  const accessToken = Deno.env.get("WHATSAPP_ACCESS_TOKEN");
  if (!phoneNumberId || !accessToken) {
    throw new Error(
      "WhatsApp env vars missing: WHATSAPP_PHONE_NUMBER_ID and WHATSAPP_ACCESS_TOKEN must be set"
    );
  }

  const url = `https://graph.facebook.com/${META_GRAPH_VERSION}/${phoneNumberId}/messages`;
  const body = {
    messaging_product: "whatsapp",
    to: input.to.replace(/^\+/, ""), // Meta wants digits-only
    type: "template",
    template: {
      name: input.templateName,
      language: { code: input.languageCode ?? "en" },
      components: input.bodyParams.length > 0
        ? [{
            type: "body",
            parameters: input.bodyParams.map((text) => ({ type: "text", text })),
          }]
        : undefined,
    },
  };

  // 10s timeout: Meta's Cloud API is normally <1s, but during incidents it
  // can hang for minutes. The scheduler retries with 30s/5min/30min backoff,
  // so it's safer to fail fast and retry than to block a worker invocation.
  const res = await fetch(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${accessToken}`,
    },
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(10_000),
  });

  const responseBody = await res.json().catch(() => ({}));

  if (!res.ok) {
    const code = responseBody?.error?.code;
    const subcode = responseBody?.error?.error_subcode;
    const errMsg = responseBody?.error?.message ?? "Unknown error";
    const userTitle = responseBody?.error?.error_user_title;
    const userMsg = responseBody?.error?.error_user_msg;
    if (code === 132001 || /template.*not found/i.test(errMsg)) {
      throw new WhatsAppTemplateNotFoundError(
        `Template not found or not approved: ${input.templateName}`,
      );
    }
    // Include code + subcode so operators can map directly to Meta's docs
    // (e.g. 131056 = recipient not in allowed list while in dev mode).
    const detail = [
      `code=${code ?? "?"}`,
      subcode ? `subcode=${subcode}` : null,
      userTitle ? `title=${userTitle}` : null,
      userMsg ? `userMsg=${userMsg}` : null,
    ]
      .filter(Boolean)
      .join(" ");
    throw new Error(`Meta API ${res.status}: ${errMsg} [${detail}]`);
  }

  const messageId = responseBody?.messages?.[0]?.id;
  if (!messageId) {
    throw new Error("Meta API returned no message id");
  }
  return { messageId };
}

export class WhatsAppTemplateNotFoundError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "WhatsAppTemplateNotFoundError";
  }
}

/**
 * Verify a Meta webhook signature (X-Hub-Signature-256 header) using the
 * App Secret. Used by the whatsapp-webhook handler (Task 4) to authenticate
 * inbound delivery receipts and (eventually) inbound messages.
 *
 * Returns false on any malformed input or mismatch. Throws only if the
 * app secret env var isn't set (a deployment misconfiguration).
 */
export async function verifyMetaSignature(
  rawBody: string,
  header: string,
): Promise<boolean> {
  if (!header || !header.startsWith("sha256=")) return false;
  const appSecret = Deno.env.get("WHATSAPP_APP_SECRET");
  if (!appSecret) {
    throw new Error("WHATSAPP_APP_SECRET not set");
  }

  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(appSecret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode(rawBody),
  );
  const computed =
    "sha256=" +
    Array.from(new Uint8Array(sig))
      .map((b) => b.toString(16).padStart(2, "0"))
      .join("");
  return timingSafeEqual(computed, header);
}

function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) {
    diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return diff === 0;
}
