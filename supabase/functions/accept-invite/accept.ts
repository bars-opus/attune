// Spec 1 W4a (§4.5, D7): accept-invite's work, apart from Deno.serve so it
// can be tested. The decision is one SQL transaction,
// accept_relationship_invite_v2 (service role): it locks the acceptor's
// users row, then the invite; refuses with an invite:<code>; withdraws the
// acceptor's own pending invites; activates; records the acceptance; sets
// the acceptor's path to Relationship. This file maps its codes to today's
// statuses and messages (the app parses them) and then queues the
// best-effort invite_accepted push. Before the accept it spends the
// acceptor's attempt budget (note_invite_attempt, shared with the preview:
// 10 an hour, 30 a day), in its own request, because a refused accept rolls
// back and could not count itself. A deadlock abort (40P01, rare: e.g.
// seal_my_side at the same instant) rolled the whole accept back, so it is
// retried once, on the same attempt; a second one is a retryable 503.
import { HttpError, jsonResponse } from "../_shared/attune_auth.ts";
import { errorCode } from "../_shared/error_code.ts";
import { enqueuePush } from "../_shared/push_queue.ts";
import { ensureInviteAccount } from "../_shared/sign_up_guard.ts";

// Sync audit I-8: shown as is wherever the invite was entered by hand; the
// app matches its opening words (kAlreadyInRelationshipPrefix).
export const ALREADY_IN_RELATIONSHIP =
  "You're already in a relationship on Attune. End it first to join a new one.";

/// An accept refusal: today's status and message, plus the server's code,
/// which the W4b app reads first.
export class InviteRefusal extends HttpError {
  constructor(message: string, status: number, readonly code: string) {
    super(message, status);
    this.name = "InviteRefusal";
  }
}

const REFUSALS: Record<string, { status: number; message: string }> = {
  "invite:invalid": { status: 404, message: "Invite code is invalid" },
  "invite:own": { status: 409, message: "You cannot accept your own invite" },
  "invite:expired": { status: 410, message: "Invite code has expired" },
  "invite:already_accepted": { status: 409, message: "Invite has already been accepted" },
  "invite:already_in_relationship": { status: 409, message: ALREADY_IN_RELATIONSHIP },
  "invite:phone_required": { status: 403, message: "invite:phone_required" },
  "invite:age_required": { status: 428, message: "invite:age_required" },
  "invite:not_possible": { status: 403, message: "invite:not_possible" },
  // The acceptor's own open hold (Task 1 ruling I-3); an inviter's is the
  // uniform invite:invalid.
  "account:hold": { status: 403, message: "account:hold" },
};

/// Every code accept_relationship_invite_v2 raises (the Deno test checks
/// each one is mapped).
export const ACCEPT_REFUSAL_CODES = Object.keys(REFUSALS);

/// The refusal for a database error message, or null when it isn't one.
export function acceptRefusal(message: string): InviteRefusal | null {
  const refusal = REFUSALS[message];
  return refusal ? new InviteRefusal(refusal.message, refusal.status, message) : null;
}

/// Past the shared attempt budget (note_invite_attempt answered false).
export const TRY_LATER = "invite:try_later";

/// A second deadlock abort in a row: nothing was written; retryable.
export const TRY_AGAIN = "invite:try_again";

const DEADLOCK = "40P01";

/// An unexpected failure (a 500): which step and the SQLSTATE (errorCode)
/// or a fixed reason, so it can be diagnosed; never the database's text.
export class AcceptFailure extends Error {
  constructor(readonly step: "attempt" | "accept", readonly sqlstate: string) {
    super(`accept-invite ${step}: ${sqlstate}`);
    this.name = "AcceptFailure";
  }
}

/// What accept-invite answers for an error: a refusal {error, code} with
/// its status (the W4b app reads code first), any other HttpError {error},
/// anything else a generic 500 whose log is the step and the SQLSTATE.
export function acceptErrorResponse(error: unknown): Response {
  if (error instanceof InviteRefusal) {
    return jsonResponse({ error: error.message, code: error.code }, error.status);
  }
  if (error instanceof HttpError) {
    return jsonResponse({ error: error.message }, error.status);
  }
  const step = error instanceof AcceptFailure ? error.step : "unknown";
  const sqlstate = error instanceof AcceptFailure ? error.sqlstate : errorCode(error);
  console.error(`accept-invite failed: step=${step} sqlstate=${sqlstate}`);
  return jsonResponse({ error: "Could not accept invite" }, 500);
}

export function normalizeInviteCode(raw: unknown): string | null {
  if (typeof raw !== "string") return null;
  const code = raw.replace(/\s+/g, "").toUpperCase();
  return /^[A-Z0-9]{6,12}$/.test(code) ? code : null;
}

export type AcceptResult = {
  relationship_id: string;
  status: string;
  idempotent: boolean;
};

export async function acceptInvite(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  userId: string,
  rawCode: unknown,
  ensureUserRow: () => Promise<void>,
): Promise<AcceptResult> {
  const inviteCode = normalizeInviteCode(rawCode);
  if (!inviteCode) throw new HttpError("Invite code is required", 400);

  // Flag off: today's missing-row insert. Flag on: an account must exist
  // (409 signup:incomplete); the ages are the SQL function's.
  await ensureInviteAccount(supabase, userId, ensureUserRow);

  // The attempt, before the accept and only once: true is the go-ahead;
  // false is past the limit; anything else fails closed (no accept).
  let attempt;
  try {
    attempt = await supabase.rpc("note_invite_attempt", { p_user: userId });
  } catch (thrown) {
    throw new AcceptFailure("attempt", errorCode(thrown));
  }
  if (attempt?.error) throw new AcceptFailure("attempt", errorCode(attempt.error));
  if (attempt?.data === false) throw new InviteRefusal(TRY_LATER, 429, TRY_LATER);
  if (attempt?.data !== true) throw new AcceptFailure("attempt", "unexpected_answer");

  // A thrown call is never retried: its accept may have committed.
  const call = async () => {
    try {
      return await supabase.rpc("accept_relationship_invite_v2", {
        p_acceptor: userId,
        p_invite_code: inviteCode,
      });
    } catch (thrown) {
      throw new AcceptFailure("accept", errorCode(thrown));
    }
  };
  let { data, error } = await call();
  if (error?.code === DEADLOCK) {
    console.warn("accept-invite: deadlock, retrying once:", DEADLOCK);
    ({ data, error } = await call());
    if (error?.code === DEADLOCK) {
      console.warn("accept-invite: deadlock again:", DEADLOCK);
      throw new InviteRefusal(TRY_AGAIN, 503, TRY_AGAIN);
    }
  }
  if (error) {
    const refusal = acceptRefusal(String(error.message ?? ""));
    if (refusal) throw refusal;
    throw new AcceptFailure("accept", errorCode(error));
  }
  if (!data || typeof data.relationship_id !== "string") {
    throw new AcceptFailure("accept", "unexpected_answer");
  }

  // Best-effort: a failed push must never make this endpoint appear to
  // fail to the accepting user: the relationship already committed, and
  // the home state's resync is the correctness guarantee, not this push
  // (docs/superpowers/specs/2026-08-02-relationship-lifecycle-sync-design.md
  // §2). A replay sends nothing again.
  if (data.idempotent !== true && typeof data.inviter_id === "string") {
    try {
      // Spec 1b: queued, so quiet hours apply; the worker sends it.
      await enqueuePush(supabase, {
        userId: data.inviter_id,
        type: "invite_accepted",
        title: "Your partner joined Attune",
        body: "You can start chatting now.",
        data: { relationship_id: data.relationship_id },
        sourceKey: `invite_accepted:${data.relationship_id}`,
      });
    } catch (pushError) {
      console.error(
        "accept-invite: push notification failed (non-fatal):",
        pushError instanceof Error ? pushError.message : "unknown",
      );
    }
  }

  return {
    relationship_id: data.relationship_id,
    status: String(data.status ?? "active"),
    idempotent: data.idempotent === true,
  };
}
