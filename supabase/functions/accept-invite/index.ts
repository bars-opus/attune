import {
  jsonResponse,
  requireUser,
  serviceRoleClient,
} from "../_shared/attune_auth.ts";
import { acceptErrorResponse, acceptInvite } from "./accept.ts";

// Spec 1 W4a (§4.5, D7): the accept is one SQL transaction
// (accept_relationship_invite_v2); accept.ts maps its refusals and queues
// the push.
Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  try {
    const user = await requireUser(req);
    const body = await req.json().catch(() => ({}));
    const supabase = serviceRoleClient();
    const result = await acceptInvite(
      supabase,
      user.id,
      body.invite_code,
      () => ensureUserRow(supabase, user),
    );
    return jsonResponse(result);
  } catch (error) {
    return acceptErrorResponse(error);
  }
});

async function ensureUserRow(
  supabase: ReturnType<typeof serviceRoleClient>,
  user: { id: string; email: string | null; phone: string | null },
) {
  // Spec 1 W1a: users.mode is retired, so it is never written, and the name
  // is left empty for onboarding to fill: a phone number is never a display
  // name. ignoreDuplicates so this only ever INSERTs a missing row. The
  // phone passed is GoTrue getUser's, confirmed or not; the users insert
  // guard (users_phone_from_auth) stores the verified Auth phone or NULL.
  // Runs only with flow_signin_v2 off (sign_up_guard.ts).
  const { error } = await supabase
    .from("users")
    .upsert(
      {
        id: user.id,
        phone: user.phone,
        display_name: "",
      },
      { onConflict: "id", ignoreDuplicates: true },
    );
  if (error) throw error;
}
