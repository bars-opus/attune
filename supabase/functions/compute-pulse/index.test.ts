// supabase/functions/compute-pulse/index.test.ts
import {
  assertEquals,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import { clamp, getWeekEnding, confidenceFrom, rollupConfidence } from "./index.ts";
import { computeChatWeight, applyChatSignals, type DimensionState, type ChatSignals } from "./index.ts";

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

Deno.test("computeChatWeight: below 25% coverage (7.5 days) is zero", () => {
  assertEquals(computeChatWeight(0), 0);
  assertEquals(computeChatWeight(5), 0);
  assertEquals(computeChatWeight(7.49), 0);
});

Deno.test("computeChatWeight: exactly 25% coverage is zero (boundary)", () => {
  assertEquals(computeChatWeight(7.5), 0);
});

Deno.test("computeChatWeight: 50% coverage (15 days) is partial", () => {
  const result = computeChatWeight(15);
  assertEquals(result > 0 && result < 1, true);
});

Deno.test("computeChatWeight: 75% coverage (22.5 days) reaches full weight", () => {
  assertEquals(computeChatWeight(22.5), 1);
});

Deno.test("computeChatWeight: 100% coverage (30 days) stays at full weight", () => {
  assertEquals(computeChatWeight(30), 1);
});

function emptyChatSignals(): ChatSignals {
  return {
    analysedCount: 0,
    avgTone: null,
    violationRate: null,
    severeRate: null,
    bidTurnRate: null,
    bidsTotal: 0,
    sessionCount: 0,
    avgEscalation: null,
    repairRate: null,
    attemptRate: null,
    stonewallRate: null,
    pursueWithdrawRate: null,
  };
}

function baseDimensions(): DimensionState {
  return {
    communication: 50,
    connection: 50,
    conflictHealth: 70,
    emotionalSafety: 50,
  };
}

Deno.test("applyChatSignals: no-op proof — zero chat signal leaves dimensions untouched", () => {
  const before = baseDimensions();
  const result = applyChatSignals(before, emptyChatSignals(), 0);
  assertEquals(result, before);
});

Deno.test("applyChatSignals: zero chatWeight leaves dimensions untouched even with real signal", () => {
  const before = baseDimensions();
  const signals: ChatSignals = {
    ...emptyChatSignals(),
    analysedCount: 50,
    avgTone: -0.8,
    violationRate: 0.5,
  };
  const result = applyChatSignals(before, signals, 0);
  assertEquals(result, before);
});

Deno.test("applyChatSignals: positive avgTone raises communication when analysedCount floor is met", () => {
  const before = baseDimensions();
  const signals: ChatSignals = { ...emptyChatSignals(), analysedCount: 10, avgTone: 0.5 };
  const result = applyChatSignals(before, signals, 1);
  assertEquals(result.communication > before.communication, true);
});

Deno.test("applyChatSignals: avgTone below the analysedCount floor of 10 has no effect", () => {
  const before = baseDimensions();
  const signals: ChatSignals = { ...emptyChatSignals(), analysedCount: 9, avgTone: 0.9 };
  const result = applyChatSignals(before, signals, 1);
  assertEquals(result.communication, before.communication);
});

Deno.test("applyChatSignals: violationRate lowers communication", () => {
  const before = baseDimensions();
  const signals: ChatSignals = { ...emptyChatSignals(), analysedCount: 10, violationRate: 0.2 };
  const result = applyChatSignals(before, signals, 1);
  assertEquals(result.communication < before.communication, true);
});

Deno.test("applyChatSignals: severeRate lowers BOTH communication (via violationRate) and emotionalSafety", () => {
  // Deliberate double-count per the design spec — contempt/character_attack
  // damage both clarity and safety.
  const before = baseDimensions();
  const signals: ChatSignals = {
    ...emptyChatSignals(),
    analysedCount: 10,
    violationRate: 0.1,
    severeRate: 0.1,
  };
  const result = applyChatSignals(before, signals, 1);
  assertEquals(result.communication < before.communication, true);
  assertEquals(result.emotionalSafety < before.emotionalSafety, true);
});

Deno.test("applyChatSignals: bidTurnRate above 0.5 raises connection", () => {
  const before = baseDimensions();
  const signals: ChatSignals = { ...emptyChatSignals(), bidsTotal: 10, bidTurnRate: 0.8 };
  const result = applyChatSignals(before, signals, 1);
  assertEquals(result.connection > before.connection, true);
});

Deno.test("applyChatSignals: bidTurnRate below 0.5 lowers connection", () => {
  const before = baseDimensions();
  const signals: ChatSignals = { ...emptyChatSignals(), bidsTotal: 10, bidTurnRate: 0.2 };
  const result = applyChatSignals(before, signals, 1);
  assertEquals(result.connection < before.connection, true);
});

Deno.test("applyChatSignals: bidTurnRate is null (below the bidsTotal floor of 5) has no effect on connection", () => {
  const before = baseDimensions();
  const signals: ChatSignals = { ...emptyChatSignals(), bidsTotal: 3, bidTurnRate: null };
  const result = applyChatSignals(before, signals, 1);
  assertEquals(result.connection, before.connection);
});

Deno.test("applyChatSignals: repairRate raises conflictHealth when sessionCount floor is met", () => {
  const before = baseDimensions();
  const signals: ChatSignals = {
    ...emptyChatSignals(),
    sessionCount: 3,
    repairRate: 1,
    attemptRate: 1,
  };
  const result = applyChatSignals(before, signals, 1);
  assertEquals(result.conflictHealth > before.conflictHealth, true);
});

Deno.test("applyChatSignals: avgEscalation above 0.4 lowers conflictHealth", () => {
  const before = baseDimensions();
  const signals: ChatSignals = { ...emptyChatSignals(), sessionCount: 3, avgEscalation: 0.9 };
  const result = applyChatSignals(before, signals, 1);
  assertEquals(result.conflictHealth < before.conflictHealth, true);
});

Deno.test("applyChatSignals: avgEscalation below 0.4 (healthy, normal escalation) does not penalize", () => {
  const before = baseDimensions();
  const signals: ChatSignals = { ...emptyChatSignals(), sessionCount: 3, avgEscalation: 0.1 };
  const result = applyChatSignals(before, signals, 1);
  assertEquals(result.conflictHealth >= before.conflictHealth, true);
});

Deno.test("applyChatSignals: stonewallRate lowers communication", () => {
  const before = baseDimensions();
  const signals: ChatSignals = { ...emptyChatSignals(), sessionCount: 3, stonewallRate: 1 };
  const result = applyChatSignals(before, signals, 1);
  assertEquals(result.communication < before.communication, true);
});

Deno.test("applyChatSignals: pursueWithdrawRate lowers emotionalSafety", () => {
  const before = baseDimensions();
  const signals: ChatSignals = { ...emptyChatSignals(), sessionCount: 3, pursueWithdrawRate: 1 };
  const result = applyChatSignals(before, signals, 1);
  assertEquals(result.emotionalSafety < before.emotionalSafety, true);
});

Deno.test("applyChatSignals: sessionCount below the floor of 3 has no session-level effect", () => {
  const before = baseDimensions();
  const signals: ChatSignals = {
    ...emptyChatSignals(),
    sessionCount: 2,
    avgEscalation: 0.9,
    stonewallRate: 1,
    pursueWithdrawRate: 1,
  };
  const result = applyChatSignals(before, signals, 1);
  assertEquals(result.conflictHealth, before.conflictHealth);
  assertEquals(result.communication, before.communication);
  assertEquals(result.emotionalSafety, before.emotionalSafety);
});

Deno.test("applyChatSignals: mid-analysis state — messages analysed, zero sessions — message-level signals still apply", () => {
  // The modal real-world state: Layer 1 (per-message) runs within
  // seconds; Layer 2 (per-session) only after a 30-min gap. This proves
  // a shared guard was NOT accidentally used for both signal levels.
  const before = baseDimensions();
  const signals: ChatSignals = {
    ...emptyChatSignals(),
    analysedCount: 10,
    avgTone: 0.5,
    sessionCount: 0,
  };
  const result = applyChatSignals(before, signals, 1);
  assertEquals(result.communication > before.communication, true);
  assertEquals(result.conflictHealth, before.conflictHealth); // no session data yet
});

Deno.test("applyChatSignals: results stay clamped to 0-100", () => {
  const before: DimensionState = { communication: 5, connection: 5, conflictHealth: 5, emotionalSafety: 5 };
  const signals: ChatSignals = {
    ...emptyChatSignals(),
    analysedCount: 10,
    violationRate: 1,
    severeRate: 1,
    sessionCount: 3,
    stonewallRate: 1,
    pursueWithdrawRate: 1,
  };
  const result = applyChatSignals(before, signals, 1);
  assertEquals(result.communication >= 0, true);
  assertEquals(result.emotionalSafety >= 0, true);
});
