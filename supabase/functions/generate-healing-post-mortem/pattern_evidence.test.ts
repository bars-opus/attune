// Spec 3a (05 D.4 (a), R3-8): Stage 2 uses the snapshot taken at ending, so
// the 30-day window and the 12-month deletion never leave it without
// evidence; live patterns only when no snapshot exists (older endings).
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { pickPatternEvidence } from "./pattern_evidence.ts";

Deno.test("the snapshot wins", () => {
  assertEquals(pickPatternEvidence(["a", "b"], ["c"]), ["a", "b"]);
});
Deno.test("an empty snapshot is still the snapshot", () => {
  assertEquals(pickPatternEvidence([], ["c"]), []);
});
Deno.test("no snapshot: live patterns", () => {
  assertEquals(pickPatternEvidence(null, ["c"]), ["c"]);
});
Deno.test("never more than six, never a non-string", () => {
  assertEquals(
    pickPatternEvidence(["1", "2", "3", "4", "5", "6", "7", 8 as unknown as string], []),
    ["1", "2", "3", "4", "5", "6"],
  );
});
