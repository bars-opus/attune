import {
  HttpError,
  jsonResponse,
  requireUser,
  serviceRoleClient,
} from "../_shared/attune_auth.ts";
import { enqueuePush } from "../_shared/push_queue.ts";

// Sync audit I-8: shown as is wherever the invite was entered by hand.
const ALREADY_IN_RELATIONSHIP =
  "You're already in a relationship on Attune. End it first to join a new one.";

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

    // Sync audit I-8: someone in an active or paused relationship cannot
    // join another; accepting while paused used to end and archive the
    // paused space without a word. Ending first is instant and silent.
    const { data: openRelationship, error: openError } = await supabase
      .from("relationships")
      .select("id")
      .in("status", ["active", "paused"])
      .or(`user_a.eq.${user.id},user_b.eq.${user.id}`)
      .limit(1)
      .maybeSingle();
    if (openError) throw openError;
    if (openRelationship) {
      throw new HttpError(ALREADY_IN_RELATIONSHIP, 409);
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

    if (updateError) {
      // The database guard (relationship_one_open_chapter_guard) covers a
      // race with another acceptance.
      if (String(updateError.message ?? "").includes("relationship:already_open")) {
        throw new HttpError(ALREADY_IN_RELATIONSHIP, 409);
      }
      throw updateError;
    }

    const { error: acceptanceError } = await supabase
      .from("relationship_invite_acceptances")
      .insert({
        invite_code_hash: inviteCodeHash,
        relationship_id: updated.id,
        accepted_by: user.id,
        accepted_at: nowIso,
      });

    if (acceptanceError) throw acceptanceError;

    // Best-effort: a failed push must never make this endpoint appear to
    // fail to the accepting user — the relationship update already
    // committed, and HomeScreen._syncRelationshipMode's resume-resync is
    // the correctness guarantee, not this push. See design spec
    // docs/superpowers/specs/2026-08-02-relationship-lifecycle-sync-design.md §2.
    try {
      // Spec 1b: queued, so quiet hours apply; the worker sends it.
      await enqueuePush(supabase, {
        userId: relationship.user_a,
        type: "invite_accepted",
        title: "Your partner joined Attune",
        body: "You can start chatting now.",
        data: { relationship_id: updated.id },
        sourceKey: `invite_accepted:${updated.id}`,
      });
    } catch (pushError) {
      console.error(
        "accept-invite: push notification failed (non-fatal):",
        pushError instanceof Error ? pushError.message : "unknown",
      );
    }

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

  // public.users has no `email` column (20260606133000_phone_only_auth.sql
  // dropped it — launch auth is phone OTP only). ignoreDuplicates so this
  // only ever INSERTs a missing row; it must never overwrite an existing
  // user's `mode` on every invite acceptance.
  const { error } = await supabase
    .from("users")
    .upsert(
      {
        id: user.id,
        phone: user.phone,
        display_name: displayName,
        mode: "couples",
      },
      { onConflict: "id", ignoreDuplicates: true },
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
