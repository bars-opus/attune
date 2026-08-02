import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { decideModerationOutcome } from "./google_vision.ts";

const config = { minFaceConfidence: 0.7, minFaceAreaRatio: 0.06 };

Deno.test("decideModerationOutcome: approves a clean, confident, well-framed face", () => {
  const result = {
    safeSearchFlags: { adult: "VERY_UNLIKELY", violence: "VERY_UNLIKELY", racy: "UNLIKELY", medical: "VERY_UNLIKELY", spoof: "VERY_UNLIKELY" },
    faceDetected: true,
    faceConfidence: 0.95,
    faceBlurred: false,
    faceUnderexposed: false,
    faceAreaRatio: 0.15, faceBoundingPolyVertices: null,
  };
  const outcome = decideModerationOutcome(result, config);
  assertEquals(outcome.state, "approved");
  assertEquals(outcome.reason, null);
});

Deno.test("decideModerationOutcome: rejects adult content at POSSIBLE", () => {
  const result = {
    safeSearchFlags: { adult: "POSSIBLE", violence: "VERY_UNLIKELY", racy: "UNLIKELY", medical: "VERY_UNLIKELY", spoof: "VERY_UNLIKELY" },
    faceDetected: true,
    faceConfidence: 0.95,
    faceBlurred: false,
    faceUnderexposed: false,
    faceAreaRatio: 0.15, faceBoundingPolyVertices: null,
  };
  const outcome = decideModerationOutcome(result, config);
  assertEquals(outcome.state, "rejected");
  assertEquals(outcome.reason, "adult_content_detected");
});

Deno.test("decideModerationOutcome: rejects racy only at LIKELY, not POSSIBLE", () => {
  const possible = {
    safeSearchFlags: { adult: "VERY_UNLIKELY", violence: "VERY_UNLIKELY", racy: "POSSIBLE", medical: "VERY_UNLIKELY", spoof: "VERY_UNLIKELY" },
    faceDetected: true, faceConfidence: 0.95, faceBlurred: false, faceUnderexposed: false, faceAreaRatio: 0.15, faceBoundingPolyVertices: null,
  };
  assertEquals(decideModerationOutcome(possible, config).state, "approved");

  const likely = { ...possible, safeSearchFlags: { ...possible.safeSearchFlags, racy: "LIKELY" } };
  assertEquals(decideModerationOutcome(likely, config).state, "rejected");
});

Deno.test("decideModerationOutcome: no face detected routes to needs_review, not rejected", () => {
  const result = {
    safeSearchFlags: { adult: "VERY_UNLIKELY", violence: "VERY_UNLIKELY", racy: "VERY_UNLIKELY", medical: "VERY_UNLIKELY", spoof: "VERY_UNLIKELY" },
    faceDetected: false,
    faceConfidence: null,
    faceBlurred: false,
    faceUnderexposed: false,
    faceAreaRatio: null, faceBoundingPolyVertices: null,
  };
  const outcome = decideModerationOutcome(result, config);
  assertEquals(outcome.state, "needs_review");
  assertEquals(outcome.reason, "no_face_detected");
});

Deno.test("decideModerationOutcome: low face confidence routes to needs_review", () => {
  const result = {
    safeSearchFlags: { adult: "VERY_UNLIKELY", violence: "VERY_UNLIKELY", racy: "VERY_UNLIKELY", medical: "VERY_UNLIKELY", spoof: "VERY_UNLIKELY" },
    faceDetected: true,
    faceConfidence: 0.4,
    faceBlurred: false,
    faceUnderexposed: false,
    faceAreaRatio: 0.15, faceBoundingPolyVertices: null,
  };
  const outcome = decideModerationOutcome(result, config);
  assertEquals(outcome.state, "needs_review");
  assertEquals(outcome.reason, "low_face_confidence");
});

Deno.test("decideModerationOutcome: blurred face rejects with specific reason", () => {
  const result = {
    safeSearchFlags: { adult: "VERY_UNLIKELY", violence: "VERY_UNLIKELY", racy: "VERY_UNLIKELY", medical: "VERY_UNLIKELY", spoof: "VERY_UNLIKELY" },
    faceDetected: true,
    faceConfidence: 0.9,
    faceBlurred: true,
    faceUnderexposed: false,
    faceAreaRatio: 0.15, faceBoundingPolyVertices: null,
  };
  const outcome = decideModerationOutcome(result, config);
  assertEquals(outcome.state, "rejected");
  assertEquals(outcome.reason, "face_blurred");
});

Deno.test("decideModerationOutcome: face too small in frame rejects with specific reason", () => {
  const result = {
    safeSearchFlags: { adult: "VERY_UNLIKELY", violence: "VERY_UNLIKELY", racy: "VERY_UNLIKELY", medical: "VERY_UNLIKELY", spoof: "VERY_UNLIKELY" },
    faceDetected: true,
    faceConfidence: 0.9,
    faceBlurred: false,
    faceUnderexposed: false,
    faceAreaRatio: 0.02, faceBoundingPolyVertices: null,
  };
  const outcome = decideModerationOutcome(result, config);
  assertEquals(outcome.state, "rejected");
  assertEquals(outcome.reason, "face_too_small");
});
