// supabase/functions/otp-delivery-intent/handler.ts
//
// Spec 1 W2c (§3.3 A3, §4.3, §4.5, review S-3): the app asks for its next
// code to go by WhatsApp or a call. Stored only as HMACs and hashes, and
// only ever a request: send-sms-hook honours it when fresh, capped and
// from one device, and sends by SMS otherwise.
//
// Always 204, whatever happened (the answer never says whether a number is
// known or whether anything was stored). Logs categories only: never the
// number, the nonce or the IP.
import { clientIp } from "../_shared/client_ip.ts";
import { canonicalPhone, decodeNonce, hmacHex, phoneHmac, sha256Hex } from "../_shared/otp_phone.ts";

export interface IntentRecord {
  p_phone_hmac: string;
  p_channel: string;
  p_platform: string;
  p_locale: string;
  p_device_hash: string;
  p_ip_hash: string;
}

export interface IntentDeps {
  /// OTP_HMAC_KEY. Unset: nothing is stored, so every code goes by SMS.
  hmacKey: string | undefined;
  record(intent: IntentRecord): Promise<void>;
  log(category: string): void;
}

const CHANNELS = new Set(["sms", "whatsapp", "voice"]);

export const noContent = () => new Response(null, { status: 204 });

export async function handleIntent(req: Request, deps: IntentDeps): Promise<Response> {
  if (req.method !== "POST") return noContent();
  let body: Record<string, unknown>;
  try {
    const parsed = await req.json();
    if (!parsed || typeof parsed !== "object") return noContent();
    body = parsed as Record<string, unknown>;
  } catch {
    deps.log("intent:bad_json");
    return noContent();
  }

  const phone = canonicalPhone(body.phone);
  const channel = typeof body.channel === "string" && CHANNELS.has(body.channel) ? body.channel : null;
  const nonce = decodeNonce(body.device_nonce);
  if (!phone || !channel || !nonce) {
    deps.log("intent:invalid");
    return noContent();
  }
  if (!deps.hmacKey) {
    deps.log("intent:not_configured");
    return noContent();
  }

  const platform = body.platform === "ios" || body.platform === "android" ? body.platform : "other";
  const locale = typeof body.locale === "string" ? body.locale.slice(0, 35) : "";
  // The address Supabase's front door saw (review I-1), never the client's
  // own first x-forwarded-for entry.
  const ip = clientIp(req.headers);
  try {
    await deps.record({
      p_phone_hmac: await phoneHmac(deps.hmacKey, phone),
      p_channel: channel,
      p_platform: platform,
      p_locale: locale,
      p_device_hash: await sha256Hex(nonce),
      p_ip_hash: await hmacHex(deps.hmacKey, `ip:${ip}`),
    });
    deps.log("intent:recorded");
  } catch {
    deps.log("intent:record_failed");
  }
  return noContent();
}
