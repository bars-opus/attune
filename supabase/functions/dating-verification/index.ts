// supabase/functions/dating-verification/index.ts
// Spec 2 W4a (§4.7): the wiring for handler.ts. The caller is the signed-in
// person (their JWT); every write goes through the service functions. The
// x-attune-device header, sent only by the Dating-scoped client (S-7), is
// hashed here and only the hash is passed on (W4b's trusted devices).
// Errors answer fixed codes; only an error's code is ever logged.
import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { HttpError, jsonResponse, requireUser, serviceRoleClient } from "../_shared/attune_auth.ts";
import { errorCode } from "../_shared/error_code.ts";
import { providersFor } from "../_shared/age_assurance/providers.ts";
import { deviceHashOf, handleVerification, storageNotFound } from "./handler.ts";

serve(async (req) => {
  if (req.method === "OPTIONS") return jsonResponse({ ok: true });
  if (req.method !== "POST") return jsonResponse({ ok: false, reason: "invalid" }, 405);
  try {
    const user = await requireUser(req);
    const supabase = serviceRoleClient();
    const body = await req.json().catch(() => ({}));
    const answer = await handleVerification(body, {
      userId: user.id,
      deviceHash: await deviceHashOf(req.headers.get("x-attune-device")),
    }, {
      rpc: (fn, args) => supabase.rpc(fn, args),
      // Spec 2 W4 final (M-12): a missing object is null (photos_required);
      // any other Storage error throws (an outage, tried again).
      download: async (key) => {
        const { data, error } = await supabase.storage.from("dating-profile-photos").download(key);
        if (data) return new Uint8Array(await data.arrayBuffer());
        if (storageNotFound(error)) return null;
        throw new Error("storage_unavailable");
      },
      providers: (mode, environment) => providersFor(mode, environment, (name) => Deno.env.get(name)),
    });
    return jsonResponse(answer);
  } catch (error) {
    if (error instanceof HttpError) return jsonResponse({ ok: false, reason: "unauthorized" }, error.status);
    console.error("dating-verification failed:", errorCode(error));
    return jsonResponse({ ok: false, reason: "busy" }, 500);
  }
});
