// Spec 1 W4a (§4.5): what both invite functions check before anything else,
// replacing the W2 interim guard. The decision is the database's
// (public.relationship_invite_eligibility, service role), so the account,
// the date of birth and the consent are one answer. Since the 2026-11-27
// entry gates it no longer depends on flow_signin_v2 and no function here
// ever creates a users row (only complete_sign_up does, D8):
//   signup_incomplete  no users row: 409 signup:incomplete; nothing is
//                      written.
//   consent_required   EULA 2 or later not accepted: also 409
//                      signup:incomplete, which the app already resolves by
//                      finishing sign-up (the gate's consent step).
//   age_required       no date of birth (a pre-Spec-1 account).
//   not_possible       under 18.
//   ok                 an adult account that has consented.
// An answer that can't be read fails closed (503 flags:unavailable).
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
  | "ok"
  | "signup_incomplete"
  | "consent_required"
  | "age_required"
  | "not_possible";

const ANSWERS: readonly string[] = [
  "ok",
  "signup_incomplete",
  "consent_required",
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

/// No account, or no current consent: HttpError(409, signup:incomplete),
/// nothing written. Otherwise the answer, for the caller's own age rule.
export async function ensureInviteAccount(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  userId: string,
): Promise<InviteEligibility> {
  const eligibility = await readInviteEligibility(supabase, userId);
  if (eligibility === "signup_incomplete" || eligibility === "consent_required") {
    throw new HttpError(SIGNUP_INCOMPLETE, 409);
  }
  return eligibility;
}

/// The inviter's rule (create-relationship-invite): 428 without a date of
/// birth (the app asks for it, then retries), 403 under 18 (neutral).
export function requireInviterAge(eligibility: InviteEligibility): void {
  if (eligibility === "age_required") throw new HttpError(AGE_REQUIRED, 428);
  if (eligibility === "not_possible") throw new HttpError(NOT_POSSIBLE, 403);
}
