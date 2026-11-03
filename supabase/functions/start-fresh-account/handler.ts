// supabase/functions/start-fresh-account/handler.ts
//
// Spec 1 W6a (§3.5 DM1, §4.5): "I'm new to Attune" on a recycled number.
// The access-token hook refused the code sign-in with
// account_dormant:<nonce>; the app sends that nonce here (no session:
// verify_jwt = false). consume_fresh_start takes it (once, within 15
// minutes, 5 tries an hour per IP), records the real number's HMAC and
// places a 180-day recovery_hold; then the old account's Auth number is
// parked on +999 and 12 digits from its id, retried on a collision, and
// phone_released_at is set. The old account's sessions need nothing: the
// hook refuses every token for a held account. The app then sends a new
// code, which makes a new account.
//
// Answers: 200 {ok:true}; 400 {error:'fresh_start:invalid'} (any nonce
// that isn't usable, never why); 429 {error:'fresh_start:try_later'};
// 503 {error:'fresh_start:unavailable'}. Logs categories only: never the
// nonce, the number, the account or the IP.
import { clientIp } from "../_shared/client_ip.ts";
import { hmacHex, sha256Hex } from "../_shared/otp_phone.ts";

type RpcResult = PromiseLike<{ data: unknown; error: { message: string } | null }>;

export interface FreshStartClient {
  rpc(
    fn: "consume_fresh_start" | "mark_fresh_start_parked",
    args: Record<string, unknown>,
  ): RpcResult;
  auth: {
    admin: {
      getUserById(id: string): PromiseLike<{
        data: { user: { phone?: string | null } | null };
        error: { message: string } | null;
      }>;
      updateUserById(
        id: string,
        attributes: { phone: string; phone_confirm: boolean },
      ): PromiseLike<{ error: { message: string; status?: number; code?: string } | null }>;
    };
  };
}

export interface FreshStartDeps {
  client: FreshStartClient;
  /// OTP_HMAC_KEY: the IP is kept only as an HMAC. Unset: 503.
  ipKey: string | undefined;
  log(category: string): void;
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const NONCE = /^[0-9a-f]{128}$/;
const PARKED = /^\+?999[0-9]{12}$/;
export const MAX_PARK_TRIES = 5;

function json(body: Record<string, unknown>, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

/// '+999' and 12 digits from SHA-256(`${userId}:${attempt}`): unassigned
/// (ITU), refused by the Send SMS Hook, and the same for a retry.
export async function parkedPhone(userId: string, attempt: number): Promise<string> {
  const hex = await sha256Hex(new TextEncoder().encode(`${userId}:${attempt}`));
  const digits = (BigInt(`0x${hex.slice(0, 16)}`) % 1_000_000_000_000n).toString().padStart(12, "0");
  return `+999${digits}`;
}

function isPhoneTaken(error: { message: string; status?: number; code?: string }): boolean {
  return error.code === "phone_exists" || /already (been )?registered|phone.*exists/i.test(error.message);
}

export async function handleFreshStart(req: Request, deps: FreshStartDeps): Promise<Response> {
  if (req.method === "OPTIONS") return json({ ok: true }, 200);
  if (req.method !== "POST") return json({ error: "fresh_start:invalid" }, 405);
  if (!deps.ipKey) {
    deps.log("fresh_start:not_configured");
    return json({ error: "fresh_start:unavailable" }, 503);
  }
  let nonce: unknown;
  try {
    nonce = (await req.json())?.nonce;
  } catch {
    nonce = null;
  }
  const ipHash = await hmacHex(deps.ipKey, `fresh-start-ip:${clientIp(req.headers)}`);
  // Rubbish still costs the IP a try: consume_fresh_start counts it.
  const { data, error } = await deps.client.rpc("consume_fresh_start", {
    p_nonce: typeof nonce === "string" && NONCE.test(nonce) ? nonce : "",
    p_ip_hash: ipHash,
  });
  if (error) {
    if (error.message.includes("fresh_start:try_later")) {
      deps.log("fresh_start:try_later");
      return json({ error: "fresh_start:try_later" }, 429);
    }
    deps.log("fresh_start:consume_failed");
    return json({ error: "fresh_start:unavailable" }, 503);
  }
  const userId = typeof data === "string" && UUID.test(data) ? data : null;
  if (!userId) {
    deps.log("fresh_start:invalid");
    return json({ error: "fresh_start:invalid" }, 400);
  }

  // Park the number (a retry of an unfinished park finds it parked already).
  const current = await deps.client.auth.admin.getUserById(userId);
  if (current.error) {
    deps.log("fresh_start:read_failed");
    return json({ error: "fresh_start:unavailable" }, 503);
  }
  let parked = PARKED.test(current.data.user?.phone ?? "");
  for (let attempt = 1; !parked && attempt <= MAX_PARK_TRIES; attempt++) {
    const { error: updateError } = await deps.client.auth.admin.updateUserById(userId, {
      phone: await parkedPhone(userId, attempt),
      phone_confirm: true,
    });
    if (!updateError) {
      parked = true;
    } else if (!isPhoneTaken(updateError)) {
      deps.log("fresh_start:park_failed");
      return json({ error: "fresh_start:unavailable" }, 503);
    }
  }
  if (!parked) {
    deps.log("fresh_start:park_collisions");
    return json({ error: "fresh_start:unavailable" }, 503);
  }
  const { error: markError } = await deps.client.rpc("mark_fresh_start_parked", { p_user: userId });
  if (markError) {
    deps.log("fresh_start:mark_failed");
    return json({ error: "fresh_start:unavailable" }, 503);
  }
  deps.log("fresh_start:parked");
  return json({ ok: true }, 200);
}
