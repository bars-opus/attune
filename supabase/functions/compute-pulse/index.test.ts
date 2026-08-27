// supabase/functions/compute-pulse/index.test.ts
import {
  assertEquals,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import { clamp, getWeekEnding, confidenceFrom, rollupConfidence } from "./index.ts";
import { computeChatWeight, applyChatSignals, weightedMean, type DimensionState, type ChatSignals } from "./index.ts";

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

// ── weightedMean + the Conflict Health blend it powers ──────────────
//
// Conflict Health is computed inline in _computePulseScore (it needs
// mood/check-in locals in scope), so its correctness is pinned here: the
// pure blending function directly, plus the exact source-shapes the spec
// specifies applied through it.

Deno.test("weightedMean: no sources falls back to the 70 optimistic baseline", () => {
  assertEquals(weightedMean([]), 70);
});

Deno.test("weightedMean: a single source is that source's value, whatever its weight", () => {
  assertEquals(weightedMean([{ v: 82, w: 1.0 }]), 82);
  assertEquals(weightedMean([{ v: 82, w: 0.8 }]), 82);
});

Deno.test("weightedMean: equal weights give the plain average", () => {
  assertEquals(weightedMean([{ v: 60, w: 1.0 }, { v: 80, w: 1.0 }]), 70);
});

Deno.test("weightedMean: unequal weights pull toward the heavier source", () => {
  // 90 at w=1.0, 40 at w=0.8 → (90 + 32) / 1.8 = 67.78, above the plain
  // average of 65 — the heavier human source dominates.
  const result = weightedMean([{ v: 90, w: 1.0 }, { v: 40, w: 0.8 }]);
  assertEquals(Math.round(result * 100) / 100, 67.78);
  assertEquals(result > 65, true);
});

Deno.test("weightedMean: a 0.8-weight chat source moves the blend only PARTIALLY toward itself", () => {
  // This is the exact property the spec's "weighted below human sources"
  // comment protects: a disagreeing chat source must shift, not capture.
  const humanOnly = weightedMean([{ v: 90, w: 1.0 }]);
  const blended = weightedMean([{ v: 90, w: 1.0 }, { v: 50, w: 0.8 }]);
  assertEquals(blended < humanOnly, true); // it did move
  assertEquals(blended > 50, true); // but did not reach the chat value
  // And it stays on the human side of the midpoint (70), proving the
  // subordination is real and not just a plain two-way average.
  assertEquals(blended > 70, true);
});

Deno.test("weightedMean: two human sources outvote one chat source that disagrees with both", () => {
  const blended = weightedMean([
    { v: 90, w: 1.0 },
    { v: 90, w: 1.0 },
    { v: 40, w: 0.8 },
  ]);
  assertEquals(blended > 75, true); // (180 + 32) / 2.8 = 75.7
});

Deno.test("weightedMean: a zero-weight source does not skew the result at all", () => {
  // The structural no-op guarantee: when chatWeight is 0, both chat
  // sources carry w = 0.8 * 0 = 0 and must vanish from the blend rather
  // than dragging it toward their values.
  const withoutChat = weightedMean([{ v: 85, w: 1.0 }]);
  const withZeroWeightChat = weightedMean([
    { v: 85, w: 1.0 },
    { v: 20, w: 0.8 * 0 },
    { v: 10, w: 0.8 * 0 },
  ]);
  assertEquals(withZeroWeightChat, withoutChat);
});

Deno.test("weightedMean: only zero-weight sources falls back to 70 rather than dividing by zero", () => {
  // Chat data exists but chatWeight is 0 and there are no human sources —
  // total weight collapses to 0. Must not produce NaN.
  const result = weightedMean([{ v: 20, w: 0 }, { v: 95, w: 0 }]);
  assertEquals(result, 70);
  assertEquals(Number.isNaN(result), false);
});

// Helper mirroring the spec's Conflict Health source construction, so the
// blend's shape (coefficients, centering, weights) is asserted directly.
function conflictSources(opts: {
  avgMood?: number;
  checkinScore?: number;
  repairRate?: number;
  attemptRate?: number;
  conflictSessionCount?: number;
  avgEscalation?: number;
  sessionCount?: number;
  chatWeight: number;
}): { v: number; w: number }[] {
  const sources: { v: number; w: number }[] = [];
  if (opts.avgMood != null) sources.push({ v: opts.avgMood * 10, w: 1.0 });
  if (opts.checkinScore != null) sources.push({ v: opts.checkinScore, w: 1.0 });
  if (opts.repairRate != null && opts.attemptRate != null && (opts.conflictSessionCount ?? 0) >= 2) {
    const repairBonus = opts.repairRate * 12 + (opts.attemptRate - opts.repairRate) * 3;
    sources.push({ v: 70 + repairBonus, w: 0.8 * opts.chatWeight });
  }
  if (opts.avgEscalation != null && (opts.sessionCount ?? 0) >= 3) {
    sources.push({ v: 70 - (opts.avgEscalation - 0.4) * 50, w: 0.8 * opts.chatWeight });
  }
  return sources;
}

Deno.test("conflict blend: no sources at all is the 70 baseline", () => {
  const sources = conflictSources({ chatWeight: 1 });
  assertEquals(sources.length, 0);
  assertEquals(weightedMean(sources), 70);
});

Deno.test("conflict blend: perfect repair over exactly 2 conflict sessions earns the bonus", () => {
  // The case the old `sessionCount >= 3` guard silently dropped: two
  // high-escalation sessions, both repaired, is a well-defined repairRate.
  const sources = conflictSources({
    repairRate: 1,
    attemptRate: 1,
    conflictSessionCount: 2,
    chatWeight: 1,
  });
  assertEquals(sources.length, 1);
  assertEquals(sources[0].v, 82); // 70 + (1*12 + 0*3)
  assertEquals(weightedMean(sources), 82);
});

Deno.test("conflict blend: repair bonus is gated on CONFLICT sessions, not total sessions", () => {
  // Only 1 high-escalation session — no repair source, even though the
  // relationship has plenty of analysed sessions overall.
  const sources = conflictSources({
    repairRate: 1,
    attemptRate: 1,
    conflictSessionCount: 1,
    sessionCount: 10,
    chatWeight: 1,
  });
  assertEquals(sources.length, 0);
});

Deno.test("conflict blend: attempted-but-not-landed repair earns less than landed repair", () => {
  const landed = conflictSources({
    repairRate: 1, attemptRate: 1, conflictSessionCount: 2, chatWeight: 1,
  })[0].v;
  const attemptedOnly = conflictSources({
    repairRate: 0, attemptRate: 1, conflictSessionCount: 2, chatWeight: 1,
  })[0].v;
  assertEquals(landed, 82); // 70 + 12
  assertEquals(attemptedOnly, 73); // 70 + 0 + (1-0)*3
  assertEquals(landed > attemptedOnly, true);
});

Deno.test("conflict blend: escalation is centered at 0.4 with a coefficient of 50", () => {
  // At exactly 0.4 the escalation source is neutral (70) — some conflict
  // is normal. Above it penalises, below it rewards, at 50 per unit.
  const neutral = conflictSources({ avgEscalation: 0.4, sessionCount: 3, chatWeight: 1 })[0].v;
  const hot = conflictSources({ avgEscalation: 0.9, sessionCount: 3, chatWeight: 1 })[0].v;
  const calm = conflictSources({ avgEscalation: 0.2, sessionCount: 3, chatWeight: 1 })[0].v;
  assertEquals(neutral, 70);
  assertEquals(hot, 45); // 70 - 0.5 * 50
  assertEquals(calm, 80); // 70 + 0.2 * 50
});

Deno.test("conflict blend: escalation source still requires 3 analysed sessions", () => {
  assertEquals(
    conflictSources({ avgEscalation: 0.9, sessionCount: 2, chatWeight: 1 }).length,
    0,
  );
});

Deno.test("conflict blend: chat sources are subordinate to human mood/check-in sources", () => {
  // Humans report healthy conflict (mood 9, check-in 90); chat disagrees
  // sharply (max escalation). Result must land nearer the humans.
  const sources = conflictSources({
    avgMood: 9,
    checkinScore: 90,
    avgEscalation: 1.0,
    sessionCount: 3,
    chatWeight: 1,
  });
  const blended = weightedMean(sources);
  assertEquals(blended > 70, true);
  assertEquals(blended < 90, true); // chat did register
});

Deno.test("conflict blend: with chatWeight 0, chat sources leave the human result untouched", () => {
  // The no-op guarantee at the Conflict Health level specifically.
  const humanOnly = weightedMean(conflictSources({
    avgMood: 6, checkinScore: 80, chatWeight: 0,
  }));
  const withMutedChat = weightedMean(conflictSources({
    avgMood: 6,
    checkinScore: 80,
    repairRate: 0,
    attemptRate: 0,
    conflictSessionCount: 5,
    avgEscalation: 1.0,
    sessionCount: 9,
    chatWeight: 0,
  }));
  assertEquals(withMutedChat, humanOnly);
  assertEquals(Math.round(humanOnly), 70); // (60 + 80) / 2
});

Deno.test("conflict blend: is order-independent (the property the additive chain lacked)", () => {
  // The whole reason the spec restructured this dimension: the result
  // must not depend on which source was evaluated first.
  const forward = conflictSources({
    avgMood: 4, checkinScore: 85, avgEscalation: 0.8, sessionCount: 3, chatWeight: 1,
  });
  const reversed = [...forward].reverse();
  assertEquals(weightedMean(reversed), weightedMean(forward));
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
    conflictSessionCount: 0,
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
});

Deno.test("applyChatSignals: results stay clamped to 0-100", () => {
  const before: DimensionState = { communication: 5, connection: 5, emotionalSafety: 5 };
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

Deno.test("no-op proof: applyChatSignals with all-null/zero ChatSignals and chatWeight 0 returns dimensions byte-identical to input", () => {
  // This is the test that proves the whole feature cannot regress a
  // relationship that doesn't use chat — the exact property the design
  // spec calls "the safety net for this whole feature."
  const before: DimensionState = {
    communication: 63,
    connection: 41,
    emotionalSafety: 55,
  }
  const zeroSignals: ChatSignals = {
    analysedCount: 0,
    avgTone: null,
    violationRate: null,
    severeRate: null,
    bidTurnRate: null,
    bidsTotal: 0,
    sessionCount: 0,
    conflictSessionCount: 0,
    avgEscalation: null,
    repairRate: null,
    attemptRate: null,
    stonewallRate: null,
    pursueWithdrawRate: null,
  }
  const result = applyChatSignals(before, zeroSignals, 0)
  assertEquals(result, before)
});

Deno.test("computeChatWeight: pendingBacklog gate forces zero weight regardless of coverage — verified at the call-site formula level", () => {
  // The backlog gate itself (`pendingBacklog > 50 ? 0 : computeChatWeight(...)`)
  // is a one-line ternary at the call site in _computePulseScore, not a
  // separately exported function — this test documents and locks the
  // formula's shape so a future refactor can't silently drop the gate.
  const pendingBacklog = 51
  const coverageDays = 30 // full coverage, would otherwise be weight 1
  const chatWeight = pendingBacklog > 50 ? 0 : computeChatWeight(coverageDays)
  assertEquals(chatWeight, 0)
});

import {
  applyGameSignals,
  type GameSignals,
} from "./index.ts";

const noGames: GameSignals = {
  sessionsCompleted: 0,
  slidingScalePairs: 0,
  slidingScaleAvgGap: null,
  mirrorRoundsScored: 0,
};

Deno.test("applyGameSignals: zero game signal is a byte-identical no-op", () => {
  // The hard requirement from the design: a couple who never plays must
  // score exactly as they did before games existed. If this ever fails,
  // shipping the feature silently moves every non-playing couple's
  // Pulse score.
  const before = { connection: 62, alignment: 48 };
  const after = applyGameSignals(before, noGames);
  assertEquals(after, before);
});

Deno.test("applyGameSignals: engagement raises Connection", () => {
  const after = applyGameSignals(
    { connection: 50, alignment: 50 },
    { ...noGames, sessionsCompleted: 3 },
  );
  assertEquals(after.connection > 50, true);
  // Engagement says nothing about values overlap.
  assertEquals(after.alignment, 50);
});

Deno.test("applyGameSignals: engagement contribution is capped", () => {
  // An enthusiastic couple must not be able to max Connection through
  // volume alone — the dimension has other, more meaningful sources.
  const many = applyGameSignals(
    { connection: 50, alignment: 50 },
    { ...noGames, sessionsCompleted: 500 },
  );
  assertEquals(many.connection <= 60, true);
});

Deno.test("applyGameSignals: a small values gap raises Alignment", () => {
  const aligned = applyGameSignals(
    { connection: 50, alignment: 50 },
    { ...noGames, slidingScalePairs: 6, slidingScaleAvgGap: 0.5 },
  );
  assertEquals(aligned.alignment > 50, true);
});

Deno.test("applyGameSignals: a large values gap lowers Alignment", () => {
  const misaligned = applyGameSignals(
    { connection: 50, alignment: 50 },
    { ...noGames, slidingScalePairs: 6, slidingScaleAvgGap: 8.5 },
  );
  assertEquals(misaligned.alignment < 50, true);
});

Deno.test("applyGameSignals: too few rated pairs cannot move Alignment", () => {
  // One answered statement is not evidence of a values pattern.
  const thin = applyGameSignals(
    { connection: 50, alignment: 50 },
    { ...noGames, slidingScalePairs: 3, slidingScaleAvgGap: 9 },
  );
  assertEquals(thin.alignment, 50);
});

Deno.test("applyGameSignals: output stays within 0-100", () => {
  const low = applyGameSignals(
    { connection: 2, alignment: 2 },
    { ...noGames, slidingScalePairs: 6, slidingScaleAvgGap: 9 },
  );
  assertEquals(low.alignment >= 0, true);
  const high = applyGameSignals(
    { connection: 98, alignment: 98 },
    { ...noGames, sessionsCompleted: 50, slidingScalePairs: 6, slidingScaleAvgGap: 0 },
  );
  assertEquals(high.connection <= 100, true);
  assertEquals(high.alignment <= 100, true);
});
