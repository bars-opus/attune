// supabase/functions/end-relationship/index.ts
import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import {
  HttpError,
  jsonResponse,
  requireUser,
  serviceRoleClient,
} from "../_shared/attune_auth.ts";
import { sendOneSignalPush } from "../_shared/onesignal_push.ts";

serve(async (req) => {
  if (req.method === "OPTIONS") return jsonResponse({ ok: true });
  try {
    const user = await requireUser(req);
    const body = await req.json().catch(() => ({}));
    const relationshipId = typeof body.relationship_id === "string"
      ? body.relationship_id
      : null;
    if (!relationshipId) {
      throw new HttpError("relationship_id is required", 400);
    }

    const supabase = serviceRoleClient();

    // Fetch the other partner's id BEFORE ending it, since end_relationship
    // doesn't return the row and RLS still applies to a plain SELECT here
    // (service role bypasses RLS, but we still scope the WHERE clause to
    // the caller's own relationship rather than trusting relationship_id
    // blindly, matching this codebase's existing service-role caution).
    const { data: relationship, error: fetchError } = await supabase
      .from("relationships")
      .select("user_a, user_b")
      .eq("id", relationshipId)
      .eq("status", "active")
      .or(`user_a.eq.${user.id},user_b.eq.${user.id}`)
      .maybeSingle();
    if (fetchError) throw fetchError;
    if (!relationship) {
      throw new HttpError("Relationship not found or not active", 404);
    }

    const { error: rpcError } = await supabase.rpc("end_relationship", {
      p_relationship_id: relationshipId,
    });
    if (rpcError) throw rpcError;

    // Best-effort, same framing as accept-invite's push (Task 3) — a
    // failed push must never make this endpoint appear to fail, since the
    // RPC's effect already committed. See design spec
    // docs/superpowers/specs/2026-08-02-relationship-lifecycle-sync-design.md §3.
    const otherPartnerId = relationship.user_a === user.id
      ? relationship.user_b
      : relationship.user_a;
    if (otherPartnerId) {
      try {
        await sendOneSignalPush({
          userId: otherPartnerId,
          title: "Your relationship has ended",
          body: "Reach out if you have questions, or take some time — we're here when you're ready.",
          data: { type: "relationship_ended", screen: "home" },
        });
      } catch (pushError) {
        console.error(
          "end-relationship: push notification failed (non-fatal):",
          pushError instanceof Error ? pushError.message : "unknown",
        );
      }
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
