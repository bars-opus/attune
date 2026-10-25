// Spec 1 W2 interim guard (batch 5 review I-5; W4a's age checks replace
// it). Under flow_signin_v2 an account is created only at A5
// (complete_sign_up, which needs a date of birth, D8). The invite
// functions' service-role safety net, ensureUserRow, would create a users
// row without one, so with the flag on it never runs: a caller with no
// users row is told to finish signing up (409 signup:incomplete) before
// any invite or relationship is read or written. With the flag off,
// ensureUserRow runs exactly as before. A flag that can't be read is never
// taken as off (it fails closed: 503 flags:unavailable), so this reads it
// itself rather than through featureFlagEnabled, which treats doubt as off.
import { HttpError } from "./attune_auth.ts";

export const SIGN_IN_V2_FLAG = "flow_signin_v2";

/// The refusal's error code; the app keeps the invite and finishes
/// sign-up (relationship_invite_service.dart).
export const SIGNUP_INCOMPLETE = "signup:incomplete";

/// The refusal when the flag can't be read (fails closed); retryable, and
/// the app keeps the invite code.
export const FLAGS_UNAVAILABLE = "flags:unavailable";

/// Flag off (or no flag row): [ensureUserRow], today's insert of a missing
/// users row. Flag on: writes nothing; the caller's users row must already
/// exist, else HttpError(409, signup:incomplete). Flag unreadable: writes
/// nothing, HttpError(503, flags:unavailable).
export async function ensureInviteAccount(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  userId: string,
  ensureUserRow: () => Promise<void>,
): Promise<void> {
  if (!(await signInV2On(supabase))) {
    await ensureUserRow();
    return;
  }
  const { data, error } = await supabase
    .from("users")
    .select("id")
    .eq("id", userId)
    .maybeSingle();
  if (error) throw error;
  if (!data) throw new HttpError(SIGNUP_INCOMPLETE, 409);
}

// deno-lint-ignore no-explicit-any
async function signInV2On(supabase: any): Promise<boolean> {
  let result;
  try {
    result = await supabase
      .from("feature_flags")
      .select("enabled")
      .eq("key", SIGN_IN_V2_FLAG)
      .maybeSingle();
  } catch {
    throw new HttpError(FLAGS_UNAVAILABLE, 503);
  }
  if (result.error) throw new HttpError(FLAGS_UNAVAILABLE, 503);
  return result.data?.enabled === true;
}
