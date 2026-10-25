// supabase/functions/send-sms-hook/handler.ts
//
// Spec 1 W2c (§3.3 A3/A4, §4.3, §4.5, review S-3): Supabase Auth's Send SMS
// Hook. Auth hands over the number and the code; this decides the channel
// and the providers through otp_take_send_decision, then delivers: the
// chosen channel's routes in order, then SMS. A channel other than SMS is
// used only when the decision chose it, and it chooses one only for a
// number with no account yet (final review I-2): it is asked with the
// account Auth signs the code in to, payload.user.id. "+999" (parked
// numbers) is refused before anything else. A refusal is the hook error
// the app reads:
// `otp:rate_limited:{seconds}` or `otp:unavailable`.
//
// How Auth reads the answer (supabase/auth internal/hooks/hookshttp and
// hookserrors): a status of 400 or above becomes a generic 500 for the
// app, and {error: {http_code, message}} is read only from a 200 or 202.
// So every refusal meant for the app is a 200 carrying its status in
// http_code; only a caller that isn't Auth (a bad signature) gets a plain
// 401.
//
// One delivery per code (review n-4, ruling M-1): Auth signs each retry
// afresh, with a new webhook-id but the same body, so the hook keys the
// delivery itself (an HMAC of the number and the code). A delivery is
// marked sent only after a provider accepted it; a retry or a replay of a
// sent delivery is answered as sent and sends nothing (the first attempt's
// code is the one Auth keeps), and the retry of one that sent nothing is
// decided and sent again. Never "sent" with nothing sent; the cost is a
// rare second SMS when two attempts overlap.
//
// Time (review M-3, M-6): Auth allows 5 s for the whole invocation, from
// before the request reaches us. The hook spends at most DELIVERY_BUDGET_MS
// from arrival; every database call and every provider call is bounded by
// what is left, and a call that runs out answers otp:unavailable, never a
// send.
//
// Logs categories only: never the number or the code.
import { callingPrefix, canonicalPhone, countryOf, hmacHex, phoneHmac } from "../_shared/otp_phone.ts";
import { verifyStandardWebhook } from "../_shared/standard_webhooks.ts";
import { smsText, voiceText } from "./messages.ts";
import { type Deliverer, type OutgoingCode, PROVIDER_TIMEOUT_MS } from "./providers.ts";

export interface Route {
  channel: "sms" | "whatsapp" | "voice";
  provider: string;
}

export interface Decision {
  allowed: boolean;
  reason: string | null;
  channel: "sms" | "whatsapp" | "voice" | null;
  platform: string | null;
  routes: Route[];
  retry_after_s: number | null;
}

export interface HookDeps {
  /// SEND_SMS_HOOK_SECRET ("v1,whsec_…"). Unset: every send fails closed.
  hookSecret: string | undefined;
  /// OTP_HMAC_KEY. Unset: every send fails closed (no limits without it).
  hmacKey: string | undefined;
  /// otp_hook_delivery_sent: has a provider already accepted this delivery
  /// (in the last 10 minutes)? [signal] aborts the call when its time is up.
  alreadySent(deliveryHmac: string, signal: AbortSignal): Promise<boolean>;
  /// otp_mark_hook_delivery_sent, once a provider accepted it. Best effort.
  markSent(deliveryHmac: string, signal: AbortSignal): Promise<void>;
  /// otp_take_send_decision, its own RPC (the prefix lock is held to commit).
  /// [userId]: the account the code signs in to (Auth's payload.user.id), or
  /// null when the payload has no usable one; an existing account, or
  /// null, gets SMS whatever was asked (final review I-2).
  decide(
    phoneHmac: string,
    country: string,
    prefix: string,
    userId: string | null,
    signal: AbortSignal,
  ): Promise<Decision>;
  providers: Record<string, Deliverer>;
  /// ANDROID_SMS_APP_HASHES, comma-separated; the first (the release
  /// signing key's) goes in Android messages.
  androidAppHashes: string[];
  bump(key: string, signal: AbortSignal): Promise<void>;
  nowSeconds(): number;
  /// Milliseconds, for the delivery budget (Date.now when omitted).
  nowMs?: () => number;
  log(category: string): void;
}

/// The whole answer must fit inside Auth's hook timeout (5 s for the whole
/// invocation, counted before the request arrives; review M-3 leaves 1 s
/// for boot and transit). Counted from the request's arrival: each provider
/// call gets at most what is left, and none starts with less than
/// MIN_ATTEMPT_MS.
export const DELIVERY_BUDGET_MS = 4000;
export const MIN_ATTEMPT_MS = 800;
/// The most any one database call may take (review M-6).
export const RPC_TIMEOUT_MS = 1000;

const RATE_REASONS = new Set(["number_hourly", "number_daily", "prefix_hourly"]);

/// Auth's user ids are UUIDs; anything else is asked as no user (null).
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

/// A refusal Auth passes on to the app (see the header).
const hookError = (httpCode: number, message: string) => json({ error: { http_code: httpCode, message } });

const unavailable = (httpCode = 503) => hookError(httpCode, "otp:unavailable");

const sent = () => json({});

/// [work] with an AbortSignal that fires after [ms]; rejects then, whether
/// or not [work] listens (a late answer is never used).
async function bounded<T>(ms: number, work: (signal: AbortSignal) => Promise<T>): Promise<T> {
  const controller = new AbortController();
  let timer: ReturnType<typeof setTimeout> | undefined;
  const timeout = new Promise<never>((_, reject) => {
    timer = setTimeout(() => {
      controller.abort();
      reject(new Error("timeout"));
    }, Math.max(0, ms));
  });
  try {
    return await Promise.race([work(controller.signal), timeout]);
  } finally {
    clearTimeout(timer);
  }
}

export async function handleSendSms(req: Request, deps: HookDeps): Promise<Response> {
  const now = deps.nowMs ?? Date.now;
  const started = now();
  const left = () => DELIVERY_BUDGET_MS - (now() - started);
  if (req.method !== "POST") return json({ error: { http_code: 405, message: "method_not_allowed" } }, 405);
  const body = await req.text();
  if (!deps.hookSecret) {
    deps.log("hook:not_configured");
    return unavailable(500);
  }
  if (!(await verifyStandardWebhook(deps.hookSecret, req.headers, body, deps.nowSeconds()))) {
    deps.log("hook:bad_signature");
    return json({ error: { http_code: 401, message: "unauthorized" } }, 401);
  }

  let payload: { user?: { id?: unknown; phone?: unknown }; sms?: { otp?: unknown; phone?: unknown } };
  try {
    payload = JSON.parse(body);
  } catch {
    deps.log("hook:bad_json");
    return unavailable(400);
  }
  // sms.phone is where Auth wants the code (a phone change's new number);
  // user.phone where it doesn't say.
  const phone = canonicalPhone(payload.sms?.phone ?? payload.user?.phone);
  const otp = typeof payload.sms?.otp === "string" && /^\d{4,10}$/.test(payload.sms.otp)
    ? payload.sms.otp
    : null;
  if (!phone || !otp) {
    deps.log("hook:bad_payload");
    return unavailable(400);
  }
  if (phone.startsWith("+999")) {
    deps.log("hook:parked_number");
    return unavailable(400);
  }
  if (!deps.hmacKey) {
    deps.log("hook:no_hmac_key");
    return unavailable(500);
  }

  const delivery = await hmacHex(deps.hmacKey, `delivery:${phone}:${otp}`);
  try {
    if (await bounded(Math.min(RPC_TIMEOUT_MS, left()), (signal) => deps.alreadySent(delivery, signal))) {
      deps.log("hook:duplicate");
      return sent();
    }
  } catch {
    deps.log("hook:delivery_check_failed");
    return unavailable();
  }

  const country = countryOf(phone);
  const hmac = await phoneHmac(deps.hmacKey, phone);
  // The account this code signs in to (I-2); never logged.
  const userId = typeof payload.user?.id === "string" && UUID.test(payload.user.id) ? payload.user.id : null;
  // The decision records a send: ask it only with time left to make one.
  const forDecision = Math.min(RPC_TIMEOUT_MS, left() - MIN_ATTEMPT_MS);
  if (forDecision <= 0) {
    deps.log("hook:budget_spent");
    return unavailable();
  }
  let decision: Decision;
  try {
    decision = await bounded(
      forDecision,
      (signal) => deps.decide(hmac, country, callingPrefix(phone), userId, signal),
    );
  } catch {
    deps.log("hook:decision_failed");
    return unavailable();
  }
  if (!decision.allowed) {
    deps.log(`hook:refused:${decision.reason}`);
    if (decision.reason && RATE_REASONS.has(decision.reason)) {
      return hookError(429, `otp:rate_limited:${Math.max(1, decision.retry_after_s ?? 60)}`);
    }
    return unavailable(400);
  }

  const allowedChannels = new Set(["sms", decision.channel]);
  const appHash = deps.androidAppHashes[0];
  let machineAnswered = false;
  for (const route of decision.routes) {
    if (!allowedChannels.has(route.channel)) continue;
    // A machine took the call: no other call, the code goes by SMS.
    if (machineAnswered && route.channel === "voice") continue;
    const deliver = deps.providers[route.provider];
    if (!deliver) continue;
    const remaining = left();
    if (remaining < MIN_ATTEMPT_MS) {
      deps.log("hook:budget_spent");
      break;
    }
    const code: OutgoingCode = {
      channel: route.channel,
      to: phone,
      otp,
      text: route.channel === "voice"
        ? voiceText(otp)
        : route.channel === "sms"
        ? smsText(otp, decision.platform ?? "other", appHash)
        : "",
    };
    const result = await deliver(code, Math.min(PROVIDER_TIMEOUT_MS, remaining));
    deps.log(`hook:${route.channel}:${route.provider}:${result}`);
    if (result === "machine") machineAnswered = true;
    if (result === "sent") {
      // Marked only now, after a provider accepted it (M-1). A failed mark
      // still answers sent: the code went; a retry may send it twice.
      try {
        await bounded(Math.min(RPC_TIMEOUT_MS, left()), (signal) => deps.markSent(delivery, signal));
      } catch {
        deps.log("hook:mark_failed");
      }
      try {
        const key = `otp_sent:${country.toLowerCase()}:${route.channel}:${route.provider}`;
        await bounded(Math.min(RPC_TIMEOUT_MS, left()), (signal) => deps.bump(key, signal));
      } catch {
        // A metric never fails a send.
      }
      return sent();
    }
  }
  deps.log("hook:all_routes_failed");
  return unavailable();
}
