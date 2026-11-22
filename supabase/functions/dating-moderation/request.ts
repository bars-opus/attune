// supabase/functions/dating-moderation/request.ts
// Spec 2 W7b (§6.4): the HTTP wiring for handler.ts, kept out of index.ts so
// a test drives it with the user check, the service client and the
// console's origin injected. The caller is the signed-in moderator (their
// JWT, checked by Auth); the session's aal comes from that token. Only the
// console's own origin (the DATING_CONSOLE_ORIGIN secret) gets CORS
// headers; with none set, no browser origin is allowed. Every answer is
// no-store. Only an error's code is ever logged, a database error's too.
// Fix round 1: a timeout logs the function's name and a Storage failure its
// code (review M-5); the secret is read as an origin (M-6); the preflight is
// cached for 10 minutes (M-7).
import { HttpError } from "../_shared/attune_auth.ts";
import { errorCode } from "../_shared/error_code.ts";
import { aalOf, handleModeration, type RpcResult } from "./handler.ts";

/// The slice of the service-role client this function uses.
export interface ModerationClient {
  rpc(fn: string, args: Record<string, unknown>): PromiseLike<RpcResult>;
  storage: {
    from(bucket: string): {
      createSignedUrls(keys: string[], seconds: number): Promise<{
        data: Array<{ path: string | null; signedUrl: string | null }> | null;
        error: unknown;
      }>;
    };
  };
}

export interface Wiring {
  requireUser(req: Request): Promise<{ id: string }>;
  client(): ModerationClient;
  origin: string | null;
  /// The handler's rpc timeout (tests only; the default is RPC_TIMEOUT_MS).
  rpcTimeoutMs?: number;
}

/// DATING_CONSOLE_ORIGIN as an origin (scheme://host[:port], lower case, no
/// trailing slash or path), so a slash in the secret doesn't silently turn
/// the console's CORS off; null for anything that isn't an http(s) URL.
export function consoleOrigin(raw: string | null | undefined): string | null {
  const v = (raw ?? "").trim();
  if (!/^https?:\/\//i.test(v)) return null;
  try {
    return new URL(v).origin;
  } catch {
    return null;
  }
}

function headers(req: Request, origin: string | null): Record<string, string> {
  const h: Record<string, string> = { "Content-Type": "application/json", "Cache-Control": "no-store" };
  if (origin !== null && req.headers.get("Origin") === origin) {
    h["Access-Control-Allow-Origin"] = origin;
    h["Access-Control-Allow-Headers"] = "authorization, content-type, apikey, x-client-info";
    h["Access-Control-Allow-Methods"] = "POST, OPTIONS";
    h["Access-Control-Max-Age"] = "600";
    h["Vary"] = "Origin";
  }
  return h;
}

export async function handleRequest(req: Request, wiring: Wiring): Promise<Response> {
  const answer = (body: Record<string, unknown>, status = 200) =>
    new Response(JSON.stringify(body), { status, headers: headers(req, wiring.origin) });
  if (req.method === "OPTIONS") return answer({ ok: true });
  if (req.method !== "POST") return answer({ ok: false, reason: "invalid" }, 405);
  try {
    const user = await wiring.requireUser(req);
    const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "").trim();
    const supabase = wiring.client();
    const body = await req.json().catch(() => ({}));
    const result = await handleModeration(body, { userId: user.id, aal: aalOf(token) }, {
      // Task 6: a database error (a lock or a timeout among them: console
      // writes have no busy answer of their own) is answered busy by the
      // handler; only its code is logged here.
      rpc: (fn, args) =>
        Promise.resolve(supabase.rpc(fn, args)).then((res) => {
          if (res.error) console.error("dating-moderation rpc failed:", errorCode(res.error));
          return res;
        }, (error) => {
          console.error("dating-moderation rpc failed:", errorCode(error));
          throw error;
        }),
      sign: async (bucket, keys, seconds) => {
        let signed: Awaited<ReturnType<ReturnType<ModerationClient["storage"]["from"]>["createSignedUrls"]>>;
        try {
          signed = await supabase.storage.from(bucket).createSignedUrls(keys, seconds);
        } catch (error) {
          console.error("dating-moderation sign failed:", errorCode(error));
          throw new Error("storage_unavailable");
        }
        if (signed.error || !signed.data) {
          console.error("dating-moderation sign failed:", errorCode(signed.error));
          throw new Error("storage_unavailable");
        }
        return signed.data.map((d) => ({ path: d.path ?? null, signedUrl: d.signedUrl ?? null }));
      },
      onTimeout: (fn) => console.error("dating-moderation timeout:", fn),
      rpcTimeoutMs: wiring.rpcTimeoutMs,
    });
    return answer(result);
  } catch (error) {
    if (error instanceof HttpError) return answer({ ok: false, reason: "unauthorized" }, error.status);
    console.error("dating-moderation failed:", errorCode(error));
    return answer({ ok: false, reason: "busy" }, 500);
  }
}
