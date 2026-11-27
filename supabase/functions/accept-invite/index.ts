import {
  jsonResponse,
  requireUser,
  serviceRoleClient,
} from "../_shared/attune_auth.ts";
import { acceptErrorResponse, acceptInvite } from "./accept.ts";

// Spec 1 W4a (§4.5, D7): the accept is one SQL transaction
// (accept_relationship_invite_v2); accept.ts maps its refusals and queues
// the push. Entry gates 2026-11-27: no users row is ever created here
// (the flag-off users-row safety net is gone); a caller without a complete
// account gets the guard's refusal.
Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  try {
    const user = await requireUser(req);
    const body = await req.json().catch(() => ({}));
    const supabase = serviceRoleClient();
    const result = await acceptInvite(supabase, user.id, body.invite_code);
    return jsonResponse(result);
  } catch (error) {
    return acceptErrorResponse(error);
  }
});
