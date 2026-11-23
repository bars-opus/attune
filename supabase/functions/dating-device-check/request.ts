// supabase/functions/dating-device-check/request.ts
// Spec 2 W8b (§2.3, §4.7): the HTTP wiring for handler.ts, kept out of
// index.ts so a test drives it with the user check, the service client and
// the resolver injected. The caller's address is turned into a country
// here and dropped: it is never stored, logged, passed on or answered.
// Fix round 1 (I-2): only Cloudflare's own cf-connecting-ip, when it is an
// address, is looked up. Never an x-forwarded-for hop (client_ip.ts's
// fallback, right for a rate bucket, could be a gateway's address and so a
// wrong country); without it the country is null. The x-attune-device header is hashed and only the hash is
// passed on. Every answer is Cache-Control: no-store. Only an error's code
// is ever logged.
import { HttpError } from "../_shared/attune_auth.ts";
import { errorCode } from "../_shared/error_code.ts";
import { deviceHashOf } from "../dating-photo-urls/handler.ts";
import { handleDeviceCheck, type RpcResult } from "./handler.ts";
import { type IpCountryResolver, isIpLiteral } from "./ip_country.ts";

/// The slice of the service-role client this function uses.
export interface DeviceCheckClient {
  rpc(fn: string, args: Record<string, unknown>): PromiseLike<RpcResult>;
}

export interface Wiring {
  requireUser(req: Request): Promise<{ id: string }>;
  client(): DeviceCheckClient;
  resolver(): Promise<IpCountryResolver>;
}

function answer(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", "Cache-Control": "no-store" },
  });
}

export async function handleRequest(req: Request, wiring: Wiring): Promise<Response> {
  if (req.method === "OPTIONS") return answer({ ok: true });
  if (req.method !== "POST") return answer({ ok: false, reason: "invalid" }, 405);
  try {
    const user = await wiring.requireUser(req);
    const supabase = wiring.client();
    const body = await req.json().catch(() => ({}));
    let ipCountry: string | null = null;
    try {
      const ip = (req.headers.get("cf-connecting-ip") ?? "").trim().toLowerCase();
      ipCountry = isIpLiteral(ip) ? (await wiring.resolver()).country(ip) : null;
    } catch {
      ipCountry = null;
    }
    const result = await handleDeviceCheck(body, {
      userId: user.id,
      deviceHash: await deviceHashOf(req.headers.get("x-attune-device")),
      ipCountry,
    }, { rpc: (fn, args) => supabase.rpc(fn, args) });
    return answer(result);
  } catch (error) {
    if (error instanceof HttpError) return answer({ ok: false, reason: "unauthorized" }, error.status);
    console.error("dating-device-check failed:", errorCode(error));
    return answer({ ok: false, reason: "busy" }, 500);
  }
}
