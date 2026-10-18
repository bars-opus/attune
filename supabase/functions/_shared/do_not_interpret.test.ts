// Spec 8 (plan review I6; sync audit M-13): the do-not-interpret corpus,
// on its own. A "no" is never decoded; ordinary sentences that share its
// words are not refusals.
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { normalizeForTokenPhrase } from "./chat_safety.ts";
import { DO_NOT_INTERPRET_CONFIG, matchesDoNotInterpret } from "./do_not_interpret.ts";

const GOLDEN_REFUSALS = [
  "Not tonight.", "Not now", "Stop.", "stop", "No.", "No no no", "Please stop!", "Just stop.",
  "Leave me alone", "I said no.", "I said stop", "no means no", "Don't touch me.",
  "I don't want to", "I don't want to talk about it", "I don't want to talk about this right now.",
  "Okay. Not tonight, I'm tired.",
];
const GOLDEN_ORDINARY = [
  "I can't stop thinking about you", "Can you stop by the shop on the way?", "No worries at all",
  "There's no milk left, can you get some?", "I don't want to miss the bus", "Bus stop at 6?",
  "No, I'm fine", "no thanks", "No, I'm fine, thanks for asking!", "Not now but maybe after dinner we could plan the whole weekend",
];

Deno.test("golden refusals match", () => {
  for (const t of GOLDEN_REFUSALS) assert(matchesDoNotInterpret(t), t);
});

Deno.test("golden ordinary sentences do not", () => {
  for (const t of GOLDEN_ORDINARY) assert(!matchesDoNotInterpret(t), t);
});

Deno.test("versioned, and every pattern pre-normalised", () => {
  assertEquals(DO_NOT_INTERPRET_CONFIG.config_version, "do_not_interpret-0.2.0");
  for (
    const p of [
      ...DO_NOT_INTERPRET_CONFIG.phrases,
      ...DO_NOT_INTERPRET_CONFIG.long_tail_phrases,
      ...DO_NOT_INTERPRET_CONFIG.short_sentence_tokens,
      ...DO_NOT_INTERPRET_CONFIG.short_sentence_companions,
    ]
  ) {
    assertEquals(normalizeForTokenPhrase(p).trim(), p, p);
  }
});
