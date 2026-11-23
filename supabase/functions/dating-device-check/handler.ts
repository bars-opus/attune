// supabase/functions/dating-device-check/handler.ts
// Spec 2 W8b (§2.3, §2.5, §3.11, §4.7; R-71..R-76): where the person is,
// in the moment. The caller is the signed-in person; the IP's country
// (resolved in request.ts, the address dropped there) and, on Android, the
// network country the app sends go to record_dating_device_check (the
// service role's) with the phone's hash; it records the session context
// (at most once per 15 minutes) and answers whether this phone is trusted,
// whether Dating is hidden here, and, while the place restricts, its
// country for the in-app note's words. The answer is {ok:true, trusted,
// away, note: null | {country}} or {ok:false, reason} with a fixed code.
// Never an address, a server's text or an error; nothing is logged.
export type RpcResult = { data: unknown; error: unknown };

export interface DeviceCheckDeps {
  rpc(fn: string, args: Record<string, unknown>): PromiseLike<RpcResult>;
  /// The database call's bound (default RPC_TIMEOUT_MS; tests pass their own).
  rpcTimeoutMs?: number;
}

export interface Caller {
  userId: string;
  deviceHash: string | null;
  /// The request's IP country (null: not resolved, as for a VPN).
  ipCountry: string | null;
}

export type Answer =
  | { ok: true; trusted: boolean; away: boolean; note: { country: string } | null }
  | { ok: false; reason: string };

export const RPC_TIMEOUT_MS = 5_000;
const CODE = /^[A-Z]{2}$/;
const REFUSALS: ReadonlySet<string> = new Set(["invalid", "unavailable"]);

function withTimeout<T>(p: PromiseLike<T>, ms: number): Promise<T> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  const late = new Promise<never>((_, reject) => {
    timer = setTimeout(() => reject(new Error("timeout")), ms);
  });
  return Promise.race([Promise.resolve(p), late]).finally(() => clearTimeout(timer));
}

export async function handleDeviceCheck(body: unknown, caller: Caller, deps: DeviceCheckDeps): Promise<Answer> {
  const b = (body ?? {}) as Record<string, unknown>;
  const net = b.network_country;
  if (net !== undefined && net !== null && (typeof net !== "string" || !CODE.test(net))) {
    return { ok: false, reason: "invalid" };
  }
  // W4 fix round 1 (I-4): a phone with no install id can't be checked.
  if (caller.deviceHash === null) return { ok: false, reason: "device_unavailable" };
  const ip = caller.ipCountry !== null && CODE.test(caller.ipCountry) ? caller.ipCountry : null;
  let res: RpcResult;
  try {
    res = await withTimeout(deps.rpc("record_dating_device_check", {
      p_user: caller.userId,
      p_device_hash: caller.deviceHash,
      p_ip_country: ip,
      p_network_country: typeof net === "string" ? net : null,
    }), deps.rpcTimeoutMs ?? RPC_TIMEOUT_MS);
  } catch {
    return { ok: false, reason: "busy" };
  }
  if (res.error) return { ok: false, reason: "busy" };
  const d = res.data as { ok?: unknown; reason?: unknown; trusted?: unknown; away?: unknown; here?: unknown } | null;
  if (d === null || typeof d !== "object") return { ok: false, reason: "busy" };
  if (d.ok !== true) {
    return { ok: false, reason: typeof d.reason === "string" && REFUSALS.has(d.reason) ? d.reason : "busy" };
  }
  return {
    ok: true,
    trusted: d.trusted === true,
    away: d.away === true,
    note: typeof d.here === "string" && CODE.test(d.here) ? { country: d.here } : null,
  };
}
