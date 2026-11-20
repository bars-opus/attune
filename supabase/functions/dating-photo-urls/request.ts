// supabase/functions/dating-photo-urls/request.ts
// Spec 2 W5b (§4.7) fix round 1 (T5 review M-3, M-4d): the HTTP wiring for
// handler.ts, kept out of index.ts so a test can drive it with the user
// check and the service client injected (index.ts only serves it). The
// caller is the signed-in person (their JWT); the keys come from the
// service function, Storage signs them in dating-profile-photos for 60
// seconds. The x-attune-device header (sent only by the Dating-scoped
// client) is hashed here and only the hash is passed on. Every answer,
// ok or refusal, is Cache-Control: no-store (it can carry bearer URLs).
// Only an error's code is ever logged.
import { HttpError } from "../_shared/attune_auth.ts";
import { errorCode } from "../_shared/error_code.ts";
import { deviceHashOf, handlePhotoUrls, type RpcResult } from "./handler.ts";

export const PHOTO_BUCKET = "dating-profile-photos";

/// The slice of the service-role client this function uses.
export interface PhotoClient {
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
  client(): PhotoClient;
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
    const result = await handlePhotoUrls(body, {
      userId: user.id,
      deviceHash: await deviceHashOf(req.headers.get("x-attune-device")),
    }, {
      rpc: (fn, args) => supabase.rpc(fn, args),
      sign: async (keys, seconds) => {
        const { data, error } = await supabase.storage.from(PHOTO_BUCKET).createSignedUrls(keys, seconds);
        if (error || !data) throw new Error("storage_unavailable");
        return data.map((d) => ({ path: d.path ?? null, signedUrl: d.signedUrl ?? null }));
      },
    });
    return answer(result);
  } catch (error) {
    if (error instanceof HttpError) return answer({ ok: false, reason: "unauthorized" }, error.status);
    console.error("dating-photo-urls failed:", errorCode(error));
    return answer({ ok: false, reason: "busy" }, 500);
  }
}
