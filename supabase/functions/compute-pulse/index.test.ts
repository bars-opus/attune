// supabase/functions/compute-pulse/index.test.ts
import {
  assertEquals,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import { clamp, getWeekEnding, confidenceFrom, rollupConfidence } from "./index.ts";

Deno.test("clamp: clamps below min", () => {
  assertEquals(clamp(-5, 0, 100), 0);
});

Deno.test("clamp: clamps above max", () => {
  assertEquals(clamp(150, 0, 100), 100);
});

Deno.test("clamp: passes through in-range value", () => {
  assertEquals(clamp(42, 0, 100), 42);
});

Deno.test("getWeekEnding: a Wednesday rolls forward to the next Sunday", () => {
  const wed = new Date("2026-08-12T10:00:00Z"); // a Wednesday
  const result = getWeekEnding(wed);
  assertEquals(result.getDay(), 0); // Sunday
});

Deno.test("confidenceFrom: below 2 points is none", () => {
  assertEquals(confidenceFrom(1, false), "none");
  assertEquals(confidenceFrom(0, true), "none");
});

Deno.test("confidenceFrom: 2 to just under 5 points is low", () => {
  assertEquals(confidenceFrom(2, false), "low");
  assertEquals(confidenceFrom(4.9, false), "low");
});

Deno.test("confidenceFrom: 5 to just under 9 points is medium", () => {
  assertEquals(confidenceFrom(5, false), "medium");
  assertEquals(confidenceFrom(8.9, false), "medium");
});

Deno.test("confidenceFrom: 9+ points without chat signal caps at medium", () => {
  // This is the test that proves PULSE.md §7's "high requires chat" rule.
  assertEquals(confidenceFrom(20, false), "medium");
});

Deno.test("confidenceFrom: 9+ points WITH chat signal reaches high", () => {
  assertEquals(confidenceFrom(9, true), "high");
  assertEquals(confidenceFrom(20, true), "high");
});

Deno.test("rollupConfidence: matches PULSE.md §4.3 — 4+ high dimensions is high", () => {
  assertEquals(
    rollupConfidence(["high", "high", "high", "high", "medium"]),
    "high",
  );
});

Deno.test("rollupConfidence: 3+ medium (below the high threshold) is medium", () => {
  assertEquals(
    rollupConfidence(["medium", "medium", "medium", "low", "low"]),
    "medium",
  );
});

Deno.test("rollupConfidence: 1-2 medium is low", () => {
  assertEquals(
    rollupConfidence(["medium", "low", "low", "low", "none"]),
    "low",
  );
});

Deno.test("rollupConfidence: zero medium or high is none", () => {
  // This is the test that proves the 'none' rollup bug is fixed — the
  // shipped code's `lowCount >= 3 ? 'low' : 'none'` made this branch
  // nearly unreachable since every dimension starts at 'low'.
  assertEquals(
    rollupConfidence(["low", "low", "low", "low", "low"]),
    "none",
  );
});

Deno.test("rollupConfidence: zero of everything (all none) is none", () => {
  assertEquals(
    rollupConfidence(["none", "none", "none", "none", "none"]),
    "none",
  );
});
