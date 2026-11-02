// Spec 1 W4a (§4.5): what both invite functions check before anything else,
// replacing the W2 interim guard. The decision is the database's
// (public.relationship_invite_eligibility, service role), so the flag read,
// the account and the date of birth are one answer:
//   legacy             flow_signin_v2 effectively off: today's ensureUserRow
//                      inserts a missing users row, exactly as before.
//   signup_incomplete  no users row: 409 signup:incomplete; nothing is
//                      written (D8: a users row is only ever made by
//                      complete_sign_up, which needs a date of birth).
//   age_required       no date of birth (a legacy account).
//   not_possible       under 18.
//   ok                 an adult account.
// An answer that can't be read fails closed (503 flags:unavailable): it is
// never taken as legacy, which would let ensureUserRow create a row with
// no date of birth.
import { HttpError } from "./attune_auth.ts";

/// The refusal for a signed-in caller with no account yet; the app keeps
/// the invite and finishes sign-up (relationship_invite_service.dart).
export const SIGNUP_INCOMPLETE = "signup:incomplete";

/// The refusal when the answer can't be read; retryable, and the app keeps
/// the invite code.
export const FLAGS_UNAVAILABLE = "flags:unavailable";

/// create-relationship-invite's refusals for an inviter (spec §4.5 W4a).
export const AGE_REQUIRED = "invite:age_required";
export const NOT_POSSIBLE = "invite:not_possible";

export type InviteEligibility =
  | "legacy"
  | "ok"
  | "signup_incomplete"
  | "age_required"
  | "not_possible";

const ANSWERS: readonly string[] = [
  "legacy",
  "ok",
  "signup_incomplete",
  "age_required",
  "not_possible",
];

// deno-lint-ignore no-explicit-any
export async function readInviteEligibility(supabase: any, userId: string): Promise<InviteEligibility> {
  let result;
  try {
    result = await supabase.rpc("relationship_invite_eligibility", { p_user: userId });
  } catch {
    throw new HttpError(FLAGS_UNAVAILABLE, 503);
  }
  if (result?.error || typeof result?.data !== "string" || !ANSWERS.includes(result.data)) {
    throw new HttpError(FLAGS_UNAVAILABLE, 503);
  }
  return result.data as InviteEligibility;
}

/// Legacy: runs [ensureUserRow]. No account: HttpError(409,
/// signup:incomplete), nothing written. Otherwise the answer, for the
/// caller's own age rule.
export async function ensureInviteAccount(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  userId: string,
  ensureUserRow: () => Promise<void>,
): Promise<InviteEligibility> {
  const eligibility = await readInviteEligibility(supabase, userId);
  if (eligibility === "legacy") {
    await ensureUserRow();
    return eligibility;
  }
  if (eligibility === "signup_incomplete") throw new HttpError(SIGNUP_INCOMPLETE, 409);
  return eligibility;
}

/// The inviter's rule (create-relationship-invite): 428 without a date of
/// birth (the app asks for it, then retries), 403 under 18 (neutral).
export function requireInviterAge(eligibility: InviteEligibility): void {
  if (eligibility === "age_required") throw new HttpError(AGE_REQUIRED, 428);
  if (eligibility === "not_possible") throw new HttpError(NOT_POSSIBLE, 403);
}
