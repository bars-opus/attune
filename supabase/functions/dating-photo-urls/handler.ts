// supabase/functions/dating-photo-urls/handler.ts
// Spec 2 W5b (§3.4, §4.7; carries 12-14): short-lived photo URLs for the
// other person on an introduction or a match. The caller is the signed-in
// person; dating_photo_keys_for_viewer (the service role's) checks their
// phone first, then that the introduction is theirs to see now (or the
// match is active), that the other person hasn't kept photos for mutual
// interest, and lists only viewable photos (approved and cleared by the
// inline CSAM scan). Storage signs those keys for 60 seconds. The answer
// is {ok:true, photos:[{position, url}]} or {ok:false, reason} with a
// fixed code. A storage key is sent only inside its signed URL (Storage
// puts it in the URL's path); a server's text or an error is never sent and
// nothing is logged. No database call is open across the signing call.
// Fix round 1 (T5 review M-1..M-6): an id in either case; every listed key
// failing to sign is busy; the database and Storage calls are bounded.
export type RpcResult = { data: unknown; error: unknown };

export interface PhotoUrlDeps {
  rpc(fn: string, args: Record<string, unknown>): PromiseLike<RpcResult>;
  /// Signs [keys] for [seconds]; throws when Storage can't answer.
  sign(keys: string[], seconds: number): Promise<Array<{ path: string | null; signedUrl: string | null }>>;
  /// The database call's bound (default RPC_TIMEOUT_MS; tests pass their own).
  rpcTimeoutMs?: number;
  /// The signing call's bound (default SIGN_TIMEOUT_MS; tests pass their own).
  signTimeoutMs?: number;
}

export interface Caller {
  userId: string;
  deviceHash: string | null;
}

export type Answer =
  | { ok: true; photos: Array<{ position: number; url: string }> }
  | { ok: false; reason: string };

/// §3.4: signed URLs live 60 seconds.
export const SIGNED_URL_SECONDS = 60;
/// T5 review M-5: neither call may hold the request; a timeout is busy.
export const RPC_TIMEOUT_MS = 5_000;
export const SIGN_TIMEOUT_MS = 5_000;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const REFUSALS: ReadonlySet<string> = new Set(["reverify_device", "photos_unavailable"]);

/// The x-attune-device header's hash (as dating-verification computes it):
/// sha256 hex of a 32-hex install id; anything else is no device.
export async function deviceHashOf(header: string | null): Promise<string | null> {
  if (header === null || !/^[0-9a-f]{32}$/.test(header)) return null;
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(header)));
  return Array.from(digest, (b) => b.toString(16).padStart(2, "0")).join("");
}

function withTimeout<T>(p: PromiseLike<T>, ms: number): Promise<T> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  const late = new Promise<never>((_, reject) => {
    timer = setTimeout(() => reject(new Error("timeout")), ms);
  });
  return Promise.race([Promise.resolve(p), late]).finally(() => clearTimeout(timer));
}

export async function handlePhotoUrls(body: unknown, caller: Caller, deps: PhotoUrlDeps): Promise<Answer> {
  const b = (body ?? {}) as Record<string, unknown>;
  const kind = b.kind;
  // T5 review M-6: an upper-case id is the same id.
  const id = typeof b.id === "string" ? b.id.toLowerCase() : b.id;
  if ((kind !== "introduction" && kind !== "match") || typeof id !== "string" || !UUID.test(id)) {
    return { ok: false, reason: "invalid" };
  }
  // W4 fix round 1 (I-4): a phone with no install id can't be checked.
  if (caller.deviceHash === null) return { ok: false, reason: "device_unavailable" };
  let res: RpcResult;
  try {
    res = await withTimeout(deps.rpc("dating_photo_keys_for_viewer", {
      p_viewer: caller.userId,
      p_kind: kind,
      p_id: id,
      p_device_hash: caller.deviceHash,
    }), deps.rpcTimeoutMs ?? RPC_TIMEOUT_MS);
  } catch {
    return { ok: false, reason: "busy" };
  }
  if (res.error) return { ok: false, reason: "busy" };
  const d = res.data as { ok?: unknown; reason?: unknown; photos?: unknown } | null;
  if (d === null || typeof d !== "object") return { ok: false, reason: "busy" };
  if (d.ok !== true) {
    return { ok: false, reason: typeof d.reason === "string" && REFUSALS.has(d.reason) ? d.reason : "photos_unavailable" };
  }
  const listed = Array.isArray(d.photos) ? d.photos : [];
  const keys = new Map<string, number>();
  for (const p of listed) {
    const x = p as { position?: unknown; key?: unknown };
    if (typeof x.key === "string" && typeof x.position === "number") keys.set(x.key, x.position);
  }
  if (keys.size === 0) return { ok: true, photos: [] };
  let signed: Array<{ path: string | null; signedUrl: string | null }>;
  try {
    signed = await withTimeout(deps.sign([...keys.keys()], SIGNED_URL_SECONDS), deps.signTimeoutMs ?? SIGN_TIMEOUT_MS);
  } catch {
    return { ok: false, reason: "busy" };
  }
  const photos: Array<{ position: number; url: string }> = [];
  for (const s of signed) {
    const position = s.path === null ? undefined : keys.get(s.path);
    if (position !== undefined && typeof s.signedUrl === "string" && s.signedUrl.length > 0) {
      photos.push({ position, url: s.signedUrl });
    }
  }
  // T5 review M-2: one photo gone is dropped; none of them signed is an outage.
  if (photos.length === 0) return { ok: false, reason: "busy" };
  photos.sort((a, b) => a.position - b.position);
  return { ok: true, photos };
}
