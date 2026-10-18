// supabase/functions/end-relationship/index.ts
//
// Spec 3a (research 06 §3 F1 (1)): ending sends nothing to the other partner.
// They learn in-app, on their next open. The app now calls the
// end_relationship RPC directly; this endpoint stays for older app versions
// and runs the RPC as the caller (it reads auth.uid(), which a service-role
// client does not have).
import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";
import {
  HttpError,
  jsonResponse,
  requireEnv,
  requireUser,
} from "../_shared/attune_auth.ts";

serve(async (req) => {
  if (req.method === "OPTIONS") return jsonResponse({ ok: true });
  try {
    await requireUser(req);
    const body = await req.json().catch(() => ({}));
    const relationshipId = typeof body.relationship_id === "string"
      ? body.relationship_id
      : null;
    if (!relationshipId) {
      throw new HttpError("relationship_id is required", 400);
    }

    const asCaller = createClient(
      requireEnv("SUPABASE_URL"),
      requireEnv("SUPABASE_ANON_KEY"),
      {
        global: {
          headers: { Authorization: req.headers.get("Authorization") ?? "" },
        },
        auth: { persistSession: false, autoRefreshToken: false },
      },
    );

    const { error: rpcError } = await asCaller.rpc("end_relationship", {
      p_relationship_id: relationshipId,
    });
    if (rpcError) {
      const message = rpcError.message ?? "";
      if (message.includes("lifecycle:not_found")) {
        throw new HttpError("Relationship not found", 404);
      }
      if (message.includes("lifecycle:not_active")) {
        throw new HttpError("Relationship not found or not active", 409);
      }
      throw rpcError;
    }

    return jsonResponse({ success: true });
  } catch (error) {
    if (error instanceof HttpError) {
      return jsonResponse({ error: error.message }, error.status);
    }
    console.error(
      "end-relationship failed:",
      error instanceof Error ? error.name : typeof error,
    );
    return jsonResponse({ error: "Could not end relationship" }, 500);
  }
});
