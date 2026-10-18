// Spec 8 (research 06 F15 (2); plan review C3, I6): a "no" is complete on
// its own. Understand and Assist never read meaning into a partner's
// refusal; a match returns a fixed, requester-only card before any provider
// call. Its own versioned corpus.
//
// Matching (review I6): the text is split into sentences BEFORE
// normalising; a phrase counts only in a short sentence (at most two
// words beyond the phrase; "don't want to talk" allows five, so "I don't
// want to talk about this right now" is a refusal while "I don't want to
// miss the bus" is not), and single words ("stop", "no") only in a
// sentence made of nothing but them and "please", "just", "I said" — so
// "can't stop thinking about you", "no worries at all", "No, I'm fine" and
// "no thanks" are not refusals (final review m-1).
import { CHAT_SAFETY_CONFIG, normalizeForTokenPhrase } from "./chat_safety.ts";

export const DO_NOT_INTERPRET_CONFIG = {
  config_version: "do_not_interpret-0.2.0",
  normalization_version: CHAT_SAFETY_CONFIG.normalization_version,
  phrases: [
    "not tonight",
    "not now",
    "i don't want to",
    "leave me alone",
    "no means no",
    "i said no",
    "i said stop",
    "please stop",
    "don't touch me",
  ],
  long_tail_phrases: ["don't want to talk"],
  short_sentence_tokens: ["stop", "no"],
  short_sentence_companions: ["please", "just", "i", "said"],
} as const;

function sentences(text: string): string[] {
  return text
    .split(/[.!?;\n\r]+/)
    .map((s) => normalizeForTokenPhrase(s))
    .filter((s) => s.trim().length > 0);
}

const words = (normalized: string) => normalized.trim().split(" ").filter(Boolean).length;

export function matchesDoNotInterpret(text: string): boolean {
  for (const s of sentences(text)) {
    const n = words(s);
    for (const p of DO_NOT_INTERPRET_CONFIG.phrases) {
      if (s.includes(` ${p} `) && n <= words(p) + 2) return true;
    }
    for (const p of DO_NOT_INTERPRET_CONFIG.long_tail_phrases) {
      if (s.includes(` ${p} `) && n <= words(p) + 5) return true;
    }
    const tokens: readonly string[] = DO_NOT_INTERPRET_CONFIG.short_sentence_tokens;
    const companions: readonly string[] = DO_NOT_INTERPRET_CONFIG.short_sentence_companions;
    const parts = s.trim().split(" ").filter(Boolean);
    if (parts.some((w) => tokens.includes(w)) && parts.every((w) => tokens.includes(w) || companions.includes(w))) {
      return true;
    }
  }
  return false;
}
