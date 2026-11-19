// supabase/functions/_shared/age_assurance/providers.ts
// Spec 2 W4a (§3.3.5): which providers a mode runs. fake: the fakes, and
// only in development on the development project's or a local host
// (anything else refuses it). sandbox and live: AWS
// Face Liveness and CompareFaces (AWS_REKOGNITION_*), Smile ID
// (SMILE_ID_*, its sandbox host in sandbox mode) and the estimation
// vendor. R-9: the UK-recognised estimation vendor is not chosen yet
// (spec §10.1); until its adapter lands with the contract, estimation
// answers "unavailable", which never passes and sends the person to the ID
// route. A mode whose credentials are missing runs nothing (unavailable).
import { isDevelopmentProjectUrl } from "../csam_matcher.ts";
import { awsConfigFrom, awsFaceMatch, awsLiveness } from "./aws.ts";
import { fakeProviders } from "./fake.ts";
import { smileIdConfigFrom, smileIdDocument } from "./smile_id.ts";
import type { AgeEstimationProvider, Mode, Providers } from "./types.ts";

/// R-9: no vendor configured. Never a pass.
export const unconfiguredAgeEstimation: AgeEstimationProvider = {
  name: "unconfigured",
  estimate: () => Promise.resolve(null),
};

export function providersFor(
  mode: Mode,
  environment: string,
  env: (name: string) => string | undefined,
  f?: typeof fetch,
): Providers | null {
  // The Spec 1 W7b rule (csam_matcher's stub): fake needs BOTH the
  // environment reading development AND SUPABASE_URL's host being exactly
  // the development project's or a local-serve host. Anything else, an
  // unset or unparsable URL included, runs nothing.
  if (mode === "fake") {
    return environment === "development" && isDevelopmentProjectUrl(env("SUPABASE_URL")) ? fakeProviders : null;
  }
  // Task 2 fix round 1 (M-6 ruling): sandbox answers are not real
  // verification; sandbox runs only in development. Spec 2 W4 final (M-9):
  // and only on the development project's or a local host, as fake: a
  // production project whose environment was never set reads development.
  if (mode === "sandbox" && (environment !== "development" || !isDevelopmentProjectUrl(env("SUPABASE_URL")))) return null;
  const aws = awsConfigFrom(env, f);
  const smile = smileIdConfigFrom(env, mode === "live", f);
  if (aws === null || smile === null) return null;
  return {
    liveness: awsLiveness(aws),
    age: unconfiguredAgeEstimation,
    id: smileIdDocument(smile),
    faceMatch: awsFaceMatch(aws),
  };
}
