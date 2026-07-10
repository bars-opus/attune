import {
  HttpError,
  jsonResponse,
  requireUser,
  serviceRoleClient,
} from "../_shared/attune_auth.ts";

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  try {
    const user = await requireUser(req);
    const body = await req.json().catch(() => ({}));
    const inviteCode = normalizeInviteCode(body.invite_code);
    if (!inviteCode) throw new HttpError("Invite code is required", 400);

    const supabase = serviceRoleClient();
    await ensureUserRow(supabase, user);

    const inviteCodeHash = await sha256Hex(inviteCode);
    const { data: accepted } = await supabase
      .from("relationship_invite_acceptances")
      .select("relationship_id, accepted_by, accepted_at")
      .eq("invite_code_hash", inviteCodeHash)
      .maybeSingle();

    if (accepted) {
      if (accepted.accepted_by !== user.id) {
        throw new HttpError("Invite has already been accepted", 409);
      }
      return jsonResponse({
        relationship_id: accepted.relationship_id,
        status: "active",
        idempotent: true,
      });
    }

    const nowIso = new Date().toISOString();
    const { data: relationship, error: lookupError } = await supabase
      .from("relationships")
      .select("id, user_a, user_b, status, invite_expires_at")
      .eq("invite_code", inviteCode)
      .eq("status", "pending")
      .maybeSingle();

    if (lookupError) throw lookupError;
    if (!relationship) throw new HttpError("Invite code is invalid", 404);
    if (relationship.user_a === user.id) {
      throw new HttpError("You cannot accept your own invite", 409);
    }
    if (
      relationship.invite_expires_at &&
      relationship.invite_expires_at < nowIso
    ) {
      throw new HttpError("Invite code has expired", 410);
    }

    const { data: updated, error: updateError } = await supabase
      .from("relationships")
      .update({
        user_b: user.id,
        status: "active",
        invite_code: null,
        invite_accepted_at: nowIso,
      })
      .eq("id", relationship.id)
      .eq("status", "pending")
      .select("id, status")
      .single();

    if (updateError) throw updateError;

    const { error: acceptanceError } = await supabase
      .from("relationship_invite_acceptances")
      .insert({
        invite_code_hash: inviteCodeHash,
        relationship_id: updated.id,
        accepted_by: user.id,
        accepted_at: nowIso,
      });

    if (acceptanceError) throw acceptanceError;

    return jsonResponse({
      relationship_id: updated.id,
      status: updated.status,
      idempotent: false,
    });
  } catch (error) {
    return handleError(error);
  }
});

async function ensureUserRow(
  supabase: ReturnType<typeof serviceRoleClient>,
  user: { id: string; email: string | null; phone: string | null },
) {
  const displayName = user.phone ?? user.email?.split("@")[0] ??
    `user-${user.id.slice(0, 8)}`;

  const { error } = await supabase
    .from("users")
    .upsert(
      {
        id: user.id,
        email: user.email,
        phone: user.phone,
        display_name: displayName,
        mode: "couples",
      },
      { onConflict: "id" },
    );
  if (error) throw error;
}

function normalizeInviteCode(raw: unknown): string | null {
  if (typeof raw !== "string") return null;
  const code = raw.trim().toUpperCase();
  return /^[A-Z0-9]{6,12}$/.test(code) ? code : null;
}

async function sha256Hex(input: string): Promise<string> {
  const bytes = new TextEncoder().encode(input);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

function handleError(error: unknown): Response {
  if (error instanceof HttpError) {
    return jsonResponse({ error: error.message }, error.status);
  }
  console.error(
    "accept-invite failed:",
    error instanceof Error ? error.name : typeof error,
  );
  return jsonResponse({ error: "Could not accept invite" }, 500);
}
