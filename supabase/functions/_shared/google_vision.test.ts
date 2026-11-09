import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { decideModerationOutcome, type VisionModerationResult } from "./google_vision.ts";

const base: VisionModerationResult = {
  safeSearchFlags: { adult: "VERY_UNLIKELY", violence: "VERY_UNLIKELY", racy: "UNLIKELY", medical: "UNLIKELY", spoof: "UNLIKELY" },
  faceDetected: true,
  faceConfidence: 0.95,
  faceBlurred: false,
  faceUnderexposed: false,
  faceAreaRatio: 0.2,
  faceBoundingPolyVertices: null,
  childLabelScore: null,
};
const config = { minFaceConfidence: 0.7, minFaceAreaRatio: 0.06, childLabelReject: 0.7, childLabelReview: 0.5 };

Deno.test("a clear, recent photo of one adult is approved", () => {
  assertEquals(decideModerationOutcome(base, config), { state: "approved", reason: null });
});
Deno.test("SafeSearch: unsafe", () => {
  for (const flags of [{ adult: "POSSIBLE" }, { violence: "POSSIBLE" }, { racy: "LIKELY" }]) {
    assertEquals(decideModerationOutcome({ ...base, safeSearchFlags: { ...base.safeSearchFlags, ...flags } }, config), { state: "rejected", reason: "unsafe" });
  }
});
Deno.test("children: at 0.7 rejected, from 0.5 to a person, below untouched", () => {
  assertEquals(decideModerationOutcome({ ...base, childLabelScore: 0.7 }, config), { state: "rejected", reason: "contains_child" });
  assertEquals(decideModerationOutcome({ ...base, childLabelScore: 0.5 }, config), { state: "needs_review", reason: "needs_review" });
  assertEquals(decideModerationOutcome({ ...base, childLabelScore: 0.49 }, config).state, "approved");
});
Deno.test("no face or a low confidence: a person looks", () => {
  assertEquals(decideModerationOutcome({ ...base, faceDetected: false }, config), { state: "needs_review", reason: "needs_review" });
  assertEquals(decideModerationOutcome({ ...base, faceConfidence: 0.5 }, config), { state: "needs_review", reason: "needs_review" });
});
Deno.test("blurred, dark or a tiny face: face_unclear", () => {
  for (const r of [{ faceBlurred: true }, { faceUnderexposed: true }, { faceAreaRatio: 0.01 }, { faceAreaRatio: null }]) {
    assertEquals(decideModerationOutcome({ ...base, ...r }, config), { state: "rejected", reason: "face_unclear" });
  }
});
