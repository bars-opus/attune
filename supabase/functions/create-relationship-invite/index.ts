import {
  HttpError,
  jsonResponse,
  requireUser,
  serviceRoleClient,
} from "../_shared/attune_auth.ts";

const INVITE_TTL_DAYS = 7;
const INVITE_CODE_LENGTH = 6;
const INVITE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  try {
    const user = await requireUser(req);
    const supabase = serviceRoleClient();

    await ensureUserRow(supabase, user);

    const nowIso = new Date().toISOString();
    const { data: existing, error: existingError } = await supabase
      .from("relationships")
      .select("id, invite_code, invite_expires_at, status")
      .eq("user_a", user.id)
      .eq("status", "pending")
      .is("user_b", null)
      .gt("invite_expires_at", nowIso)
      .order("created_at", { ascending: false })
      .limit(1)
      .maybeSingle();

    if (existingError) throw existingError;
    if (existing?.invite_code) {
      return jsonResponse({
        relationship_id: existing.id,
        invite_code: existing.invite_code,
        invite_expires_at: existing.invite_expires_at,
      });
    }

    const expiresAt = new Date(
      Date.now() + INVITE_TTL_DAYS * 24 * 60 * 60 * 1000,
    ).toISOString();

    for (let attempt = 0; attempt < 5; attempt++) {
      const inviteCode = generateInviteCode();
      const { data, error } = await supabase
        .from("relationships")
        .insert({
          user_a: user.id,
          status: "pending",
          invite_code: inviteCode,
          invite_expires_at: expiresAt,
        })
        .select("id, invite_code, invite_expires_at")
        .single();

      if (!error && data) {
        return jsonResponse({
          relationship_id: data.id,
          invite_code: data.invite_code,
          invite_expires_at: data.invite_expires_at,
        });
      }

      if (!isUniqueViolation(error)) throw error;
    }

    throw new HttpError("Could not create invite code", 500);
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

function generateInviteCode(): string {
  const values = crypto.getRandomValues(new Uint32Array(INVITE_CODE_LENGTH));
  return Array.from(values)
    .map((value) => INVITE_ALPHABET[value % INVITE_ALPHABET.length])
    .join("");
}

function isUniqueViolation(error: unknown): boolean {
  return Boolean(
    error &&
      typeof error === "object" &&
      "code" in error &&
      (error as { code?: string }).code === "23505",
  );
}

function handleError(error: unknown): Response {
  if (error instanceof HttpError) {
    return jsonResponse({ error: error.message }, error.status);
  }
  console.error(
    "create-relationship-invite failed:",
    error instanceof Error ? error.name : typeof error,
  );
  return jsonResponse({ error: "Could not create relationship invite" }, 500);
}
