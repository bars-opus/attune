// supabase/functions/_shared/age_assurance/fake.ts
// Spec 2 W4a (§3.3.5): the fake providers, for development and tests only
// (age_assurance_mode 'fake'; refused in production mode by the handler
// and by private.dating_verification_available()). Each plays the
// scenario named in its session reference (fake:<scenario>:<id>), so a
// tester can walk every outcome of §3.3.2 on a development build. They see
// no image: the "reference frame" is the scenario's own bytes.
import {
  type AgeEstimate,
  type AgeEstimationProvider,
  type FaceMatchProvider,
  type FakeScenario,
  type IdDocumentProvider,
  type IdResult,
  isFakeScenario,
  type LivenessProvider,
  type LivenessResult,
  type Providers,
} from "./types.ts";

const FRAME_PREFIX = "fake-frame:";

/// The date-of-birth answer the fake ID gives for id_pass: "the date the
/// person declared". Only the fake can say it; the handler takes it as a
/// match without reading any date (no DOB ever leaves the database).
export const FAKE_DECLARED_DOB = "declared";

function scenarioOf(ref: string): FakeScenario {
  const s = ref.split(":")[1];
  return isFakeScenario(s) ? s : "pass";
}

function frameScenario(frame: Uint8Array): FakeScenario {
  const text = new TextDecoder().decode(frame);
  const s = text.startsWith(FRAME_PREFIX) ? text.slice(FRAME_PREFIX.length) : "";
  return isFakeScenario(s) ? s : "pass";
}

export const fakeLiveness: LivenessProvider = {
  name: "fake",
  createSession({ scenario }) {
    if (scenario === "vendor_down") return Promise.reject(new Error("fake_vendor_down"));
    return Promise.resolve({ ref: `fake:${isFakeScenario(scenario) ? scenario : "pass"}:${crypto.randomUUID()}` });
  },
  results(ref): Promise<LivenessResult> {
    const s = scenarioOf(ref);
    if (s === "liveness_fail") return Promise.resolve({ status: "failed", reference: null });
    return Promise.resolve({ status: "passed", reference: new TextEncoder().encode(FRAME_PREFIX + s) });
  },
};

export const fakeAgeEstimation: AgeEstimationProvider = {
  name: "fake",
  estimate(frame): Promise<AgeEstimate | null> {
    const s = frameScenario(frame);
    if (s === "under_25") return Promise.resolve({ age: 22, under18HighConfidence: false });
    if (s === "uncertain") return Promise.resolve({ age: 31, under18HighConfidence: false, uncertain: true });
    if (s === "far_below") return Promise.resolve({ age: 13, under18HighConfidence: true });
    return Promise.resolve({ age: 31, under18HighConfidence: false });
  },
};

export const fakeFaceMatch: FaceMatchProvider = {
  name: "fake",
  compare(source, _target, index) {
    return Promise.resolve(!(frameScenario(source) === "photo_mismatch" && index === 1));
  },
};

export const fakeIdDocument: IdDocumentProvider = {
  name: "fake",
  startJob({ scenario }) {
    return Promise.resolve({ ref: `fake:${isFakeScenario(scenario) ? scenario : "id_pass"}:${crypto.randomUUID()}` });
  },
  result(ref): Promise<IdResult> {
    const s = scenarioOf(ref);
    const sixteen = new Date(Date.now() - 16 * 365.25 * 864e5).toISOString().slice(0, 10);
    switch (s) {
      case "id_pending":
        return Promise.resolve({ status: "pending", dob: null, faceMatch: null });
      case "id_fail":
        return Promise.resolve({ status: "fail", dob: null, faceMatch: null });
      case "id_dob_mismatch":
        return Promise.resolve({ status: "pass", dob: "1970-01-01", faceMatch: true });
      case "id_minor":
        return Promise.resolve({ status: "pass", dob: sixteen, faceMatch: true });
      default:
        return Promise.resolve({ status: "pass", dob: FAKE_DECLARED_DOB, faceMatch: true });
    }
  },
};

export const fakeProviders: Providers = {
  liveness: fakeLiveness,
  age: fakeAgeEstimation,
  id: fakeIdDocument,
  faceMatch: fakeFaceMatch,
};
