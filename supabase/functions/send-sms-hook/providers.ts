// supabase/functions/send-sms-hook/providers.ts
//
// Spec 1 W2c (§4.5): one adapter per provider named in private.otp_routes.
// Each says "sent", "failed" (the next route is tried), "unconfigured"
// (its secrets aren't set, or the channel is off: skipped) or "machine" (a
// call an answering machine took: no other call, the code goes by SMS).
// Secrets are the owner's environment variables; nothing here logs a
// number, a code or a response body.

export type DeliveryResult = "sent" | "failed" | "unconfigured" | "machine";

export interface OutgoingCode {
  channel: "sms" | "whatsapp" | "voice";
  /// E.164, with the '+'.
  to: string;
  otp: string;
  /// The words for SMS and voice (messages.ts); WhatsApp uses its template.
  text: string;
}

/// [timeoutMs]: what is left of the hook's budget for this call, at most
/// PROVIDER_TIMEOUT_MS (the default).
export type Deliverer = (code: OutgoingCode, timeoutMs?: number) => Promise<DeliveryResult>;

type Env = (name: string) => string | undefined;
type Fetch = (input: string, init: RequestInit) => Promise<Response>;

/// Each call is bounded: the hook's whole answer must fit Auth's timeout.
/// Two full calls fit the hook's 4-second budget (review M-3).
export const PROVIDER_TIMEOUT_MS = 2000;

/// The most of a provider's answer read when its body decides (M-5).
const MAX_ANSWER_BYTES = 4096;

/// [accepted]: when given, a 2xx is "sent" only if it says yes to the
/// parsed body (a provider that answers 200 for a refusal).
async function post(
  fetchFn: Fetch,
  url: string,
  init: RequestInit,
  timeoutMs = PROVIDER_TIMEOUT_MS,
  accepted?: (body: unknown) => boolean,
): Promise<DeliveryResult> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), Math.min(timeoutMs, PROVIDER_TIMEOUT_MS));
  try {
    const response = await fetchFn(url, { ...init, method: "POST", signal: controller.signal });
    if (!response.ok || !accepted) {
      await response.body?.cancel();
      return response.ok ? "sent" : "failed";
    }
    const text = await boundedText(response);
    if (text === null) return "failed";
    try {
      return accepted(JSON.parse(text)) ? "sent" : "failed";
    } catch {
      return "failed";
    }
  } catch {
    return "failed";
  } finally {
    clearTimeout(timer);
  }
}

/// The body as text, or null past MAX_ANSWER_BYTES (never parsed then).
async function boundedText(response: Response): Promise<string | null> {
  const reader = response.body?.getReader();
  if (!reader) return "";
  const chunks: Uint8Array[] = [];
  let size = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    size += value.length;
    if (size > MAX_ANSWER_BYTES) {
      await reader.cancel().catch(() => {});
      return null;
    }
    chunks.push(value);
  }
  const bytes = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.length;
  }
  return new TextDecoder().decode(bytes);
}

function xmlEscape(text: string): string {
  return text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}

/// Calls are hard-disabled in W2 (batch 7 ruling M-4): no environment
/// variable turns them on. A code must never be spoken to voicemail, and
/// Twilio's answering-machine detection reports only after the phone has
/// rung and been answered, long after Auth's 5-second hook budget, so this
/// hook can't learn "machine" in time to fall back to SMS. Turning calls on
/// is a code change that adds real answering-machine handling (a TwiML Url
/// that hangs up on AnsweredBy=machine_*), not a setting. Until then a
/// decision of voice goes by SMS (the voice route is "unconfigured").
const VOICE_CALLS: boolean = false;

/// SMS through Twilio's REST API (and, once VOICE_CALLS is real, voice).
export function twilio(env: Env, fetchFn: Fetch): Deliverer {
  return (code, timeoutMs) => {
    const sid = env("TWILIO_ACCOUNT_SID");
    const token = env("TWILIO_AUTH_TOKEN");
    if (!sid || !token) return Promise.resolve("unconfigured");
    const auth = `Basic ${btoa(`${sid}:${token}`)}`;
    const base = `https://api.twilio.com/2010-04-01/Accounts/${sid}`;
    const form = new URLSearchParams({ To: code.to });
    if (code.channel === "sms") {
      const service = env("TWILIO_MESSAGING_SERVICE_SID");
      const from = env("TWILIO_SMS_FROM");
      if (service) form.set("MessagingServiceSid", service);
      else if (from) form.set("From", from);
      else return Promise.resolve("unconfigured");
      form.set("Body", code.text);
      return post(fetchFn, `${base}/Messages.json`, {
        headers: { Authorization: auth, "Content-Type": "application/x-www-form-urlencoded" },
        body: form.toString(),
      }, timeoutMs);
    }
    if (code.channel === "voice") {
      // Unreachable in W2 (M-4): kept for the answering-machine follow-up.
      if (!VOICE_CALLS) return Promise.resolve("unconfigured");
      const from = env("TWILIO_VOICE_FROM");
      if (!from) return Promise.resolve("unconfigured");
      form.set("From", from);
      form.set("Twiml", `<Response><Say>${xmlEscape(code.text)}</Say></Response>`);
      return post(fetchFn, `${base}/Calls.json`, {
        headers: { Authorization: auth, "Content-Type": "application/x-www-form-urlencoded" },
        body: form.toString(),
      }, timeoutMs);
    }
    return Promise.resolve("failed");
  };
}

/// WhatsApp through Meta's Cloud API, with the approved authentication
/// template (copy-code button; Android one-tap is set on the template).
export function meta(env: Env, fetchFn: Fetch): Deliverer {
  return (code, timeoutMs) => {
    const token = env("WHATSAPP_ACCESS_TOKEN");
    const phoneId = env("WHATSAPP_PHONE_NUMBER_ID");
    if (!token || !phoneId) return Promise.resolve("unconfigured");
    if (code.channel !== "whatsapp") return Promise.resolve("failed");
    return post(fetchFn, `https://graph.facebook.com/v21.0/${phoneId}/messages`, {
      headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        messaging_product: "whatsapp",
        to: code.to.replace(/^\+/, ""),
        type: "template",
        template: {
          name: env("WHATSAPP_TEMPLATE_NAME") ?? "attune_code",
          language: { code: env("WHATSAPP_TEMPLATE_LANGUAGE") ?? "en" },
          components: [
            { type: "body", parameters: [{ type: "text", text: code.otp }] },
            {
              type: "button",
              sub_type: "url",
              index: "0",
              parameters: [{ type: "text", text: code.otp }],
            },
          ],
        },
      }),
    }, timeoutMs);
  };
}

/// Arkesel's v2 send answers 200 {"status": "success", "data": [{recipient,
/// id}, …]} (an invalid number comes back as success with only
/// {"invalid numbers": […]}) and {"status": "error", "message": …} for a
/// refusal (402 balance/coverage, 403 gateway, 422, 500): developers.
/// arkesel.com, spec/api_spec.v2.4.0.yaml, POST /api/v2/sms/send. Sent means
/// "success" with an id for the message; anything else fails over (M-5).
function arkeselAccepted(body: unknown): boolean {
  if (!body || typeof body !== "object") return false;
  const { status, data } = body as { status?: unknown; data?: unknown };
  return status === "success" && Array.isArray(data) &&
    data.some((entry) =>
      !!entry && typeof entry === "object" && typeof (entry as { id?: unknown }).id === "string" &&
      (entry as { id: string }).id.length > 0
    );
}

/// SMS inside Ghana through Arkesel (the registered alphanumeric sender).
export function arkesel(env: Env, fetchFn: Fetch): Deliverer {
  return (code, timeoutMs) => {
    const key = env("ARKESEL_API_KEY");
    const sender = env("ARKESEL_SENDER_ID");
    if (!key || !sender) return Promise.resolve("unconfigured");
    if (code.channel !== "sms") return Promise.resolve("failed");
    return post(fetchFn, "https://sms.arkesel.com/api/v2/sms/send", {
      headers: { "api-key": key, "Content-Type": "application/json" },
      body: JSON.stringify({
        sender,
        message: code.text,
        recipients: [code.to.replace(/^\+/, "")],
      }),
    }, timeoutMs, arkeselAccepted);
  };
}

export function providersFrom(env: Env, fetchFn: Fetch = fetch): Record<string, Deliverer> {
  return { twilio: twilio(env, fetchFn), meta: meta(env, fetchFn), arkesel: arkesel(env, fetchFn) };
}
