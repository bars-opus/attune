// Spec 8 (F15 (1); plan review I12, I14): under suppression Pulse reads no
// chat at all, indistinguishable from a couple with no chat data yet; with
// the hostility flag off (the default), stonewalling and contempt never
// move a score.
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  applyChatSignals,
  type ChatSignals,
  computeChatWeight,
  gateChatInputs,
  NO_CHAT_SIGNALS,
} from "./index.ts";

const busy: ChatSignals = {
  analysedCount: 80,
  avgTone: -0.4,
  violationRate: 0.3,
  severeRate: 0.2,
  bidTurnRate: 0.3,
  bidsTotal: 20,
  sessionCount: 9,
  conflictSessionCount: 5,
  avgEscalation: 0.8,
  repairRate: 0.2,
  attemptRate: 0.5,
  stonewallRate: 0.6,
  pursueWithdrawRate: 0.4,
};

Deno.test("suppressed: exactly the no-chat-data inputs", () => {
  const gated = gateChatInputs(
    { signals: busy, coverageDays: 30, pendingBacklog: 400 },
    { suppressed: true, hostilitySignals: true },
  );
  assertEquals(gated, { signals: NO_CHAT_SIGNALS, coverageDays: 0, pendingBacklog: 0 });
  assertEquals(computeChatWeight(gated.coverageDays), 0);
  assertEquals(NO_CHAT_SIGNALS.analysedCount, 0);
  assertEquals(NO_CHAT_SIGNALS.sessionCount, 0);
});

Deno.test("hostility off: stonewalling and contempt are dropped, the rest kept", () => {
  const gated = gateChatInputs(
    { signals: busy, coverageDays: 30, pendingBacklog: 3 },
    { suppressed: false, hostilitySignals: false },
  );
  assertEquals(gated.signals.stonewallRate, null);
  assertEquals(gated.signals.severeRate, null);
  assertEquals(gated.signals.avgTone, busy.avgTone);
  assertEquals(gated.coverageDays, 30);
  const base = { communication: 70, connection: 70, emotionalSafety: 70 };
  const withoutHostility = applyChatSignals(base, { ...busy, stonewallRate: null, severeRate: null }, 1);
  assertEquals(applyChatSignals(base, gated.signals, 1), withoutHostility);
});

Deno.test("hostility on: nothing dropped", () => {
  const gated = gateChatInputs(
    { signals: busy, coverageDays: 30, pendingBacklog: 3 },
    { suppressed: false, hostilitySignals: true },
  );
  assertEquals(gated.signals, busy);
});

Deno.test("the score path asks both questions, failing closed", async () => {
  const src = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
  for (const needle of ["relationshipAiSuppressed(", "hostilitySignalsEnabled(", "gateChatInputs("]) {
    if (!src.includes(needle)) throw new Error(`compute-pulse does not call ${needle}`);
  }
});
