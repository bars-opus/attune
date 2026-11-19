// supabase/functions/_shared/age_assurance/types.ts
// Spec 2 W4a (§3.3.5): the four vendor seams the dating-verification edge
// function runs through, each with a fake and a real implementation, and
// the one age decision. Nothing here logs, stores or returns an image, a
// reference frame, an estimate or a date of birth beyond the call that
// needs it (§3.3.5, DPIA biometric section).

export type Mode = "fake" | "sandbox" | "live";

/// What a liveness session answered: passed with the reference frame
/// (held in memory by the caller and cleared after use), failed, still
/// running, or expired.
export interface LivenessResult {
  status: "passed" | "failed" | "pending" | "expired";
  reference: Uint8Array | null;
}

export interface LivenessProvider {
  readonly name: string;
  /// A new vendor session for the capture view; its id goes to the device.
  createSession(opts: { scenario?: string }): Promise<{ ref: string }>;
  results(ref: string): Promise<LivenessResult>;
}

/// An estimate is never stored or logged: only ageDecision reads it.
export interface AgeEstimate {
  age: number;
  /// The vendor's under-18 band with high confidence (§6.3, R8).
  under18HighConfidence: boolean;
  /// The vendor's own "not sure" (low confidence, a poor frame): never a
  /// pass and never an ending (R-13).
  uncertain?: boolean;
}

export interface AgeEstimationProvider {
  readonly name: string;
  /// null when there is no estimate to give (none is configured, or the
  /// vendor answered without one: uncertain, the ID route). Spec 2 W4 final
  /// (M-7): a vendor that can't be reached throws; that is
  /// vendor_unavailable and counts nothing against the person.
  estimate(frame: Uint8Array): Promise<AgeEstimate | null>;
}

/// An ID check (§3.3.1): the document is valid and its face matches the
/// person; its date of birth (YYYY-MM-DD) is compared on the server with
/// the declared one and then dropped. Spec 2 W4 final (I-2 ruling): "fail"
/// is final, so only a document judged not genuine or a confirmed
/// document-face mismatch; "retry" (unreadable, expired, unsupported, image
/// quality) is never final (the session waits for a person, who may ask
/// for another ID); "minor" is a document showing under 18 (Spec 1's hold,
/// R-8); "pending" is anything else (a person checks).
export interface IdResult {
  status: "pending" | "pass" | "fail" | "retry" | "minor";
  dob: string | null;
  faceMatch: boolean | null;
}

export interface IdDocumentProvider {
  readonly name: string;
  startJob(opts: { document: string; country: string; sessionId: string; scenario?: string }): Promise<{ ref: string }>;
  result(ref: string): Promise<IdResult>;
}

export interface FaceMatchProvider {
  readonly name: string;
  /// Whether [target] (photo [index], 0-based) shows the face in [source].
  compare(source: Uint8Array, target: Uint8Array, index: number): Promise<boolean>;
}

export interface Providers {
  liveness: LivenessProvider;
  age: AgeEstimationProvider;
  id: IdDocumentProvider;
  faceMatch: FaceMatchProvider;
}

/// §3.3.1, §3.3.2: the challenge age is 25. A pass only at or above it;
/// the vendor's high-confidence under-18 band is "far below 18" (Spec 1's
/// account hold). R-13 (owner ruling 2026-11-09): an estimate never ends
/// the check. Below the challenge age it needs the ID route; no estimate,
/// or one the vendor isn't sure of, is uncertain (the ID route too).
export const CHALLENGE_AGE = 25;

export type AgeDecision = "pass" | "needs_id" | "uncertain" | "far_below";

export function ageDecision(estimate: AgeEstimate | null, challengeAge = CHALLENGE_AGE): AgeDecision {
  if (estimate === null || !Number.isFinite(estimate.age) || estimate.uncertain === true) return "uncertain";
  if (estimate.under18HighConfidence) return "far_below";
  if (challengeAge < CHALLENGE_AGE) return "needs_id";
  return estimate.age >= challengeAge ? "pass" : "needs_id";
}

/// The fixed scenarios the fake providers play (development only; the
/// handler refuses a scenario in any other mode).
export const FAKE_SCENARIOS = [
  "pass", "liveness_fail", "under_25", "uncertain", "far_below", "photo_mismatch", "vendor_down",
  "id_pass", "id_fail", "id_dob_mismatch", "id_minor", "id_pending",
] as const;
export type FakeScenario = typeof FAKE_SCENARIOS[number];

export function isFakeScenario(value: unknown): value is FakeScenario {
  return typeof value === "string" && (FAKE_SCENARIOS as readonly string[]).includes(value);
}

/// Task 2 fix round 1 (M-2): [value] when it is a real calendar date
/// (YYYY-MM-DD that round-trips), else null. An ID's impossible date never
/// reaches the database (its cast error would carry it into the log).
export function calendarDate(value: unknown): string | null {
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return null;
  const t = Date.parse(`${value}T00:00:00Z`);
  return Number.isFinite(t) && new Date(t).toISOString().slice(0, 10) === value ? value : null;
}
