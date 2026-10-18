// Spec 8 (research 06 F11 (1), F15 (2); plan review I7): the writer-facing
// corpus — a person telling Attune they are being hurt, or may hurt
// themselves. When it is the requester's own text, no provider is called
// and the writer-facing resources card is shown (MASTER_SPEC constraint 14);
// nothing is persisted. When it is the partner's message, see
// assistant_input.ts.
//
// The victimisation list is a [DRAFT] pending DV-specialist review (P1);
// self-harm reuses the sessions corpus verbatim.
import { AI_SESSION_SAFETY_CONFIG } from "./ai_session_safety.ts";
import { normalizeForTokenPhrase } from "./chat_safety.ts";

export type SelfDisclosureFamily = "self_harm" | "victimisation";

export const SELF_DISCLOSURE_CONFIG = {
  config_version: "self_disclosure-0.1.0-draft",
  families: {
    self_harm: {
      phrases: AI_SESSION_SAFETY_CONFIG.tiers.self_harm.rules.map((r) => r.pattern),
    },
    victimisation: {
      // [DRAFT]
      phrases: [
        "hits me",
        // "hit me" alone also matches "the film hit me hard" (sync audit
        // corpus goldens): only with a subject.
        "he hit me",
        "she hit me",
        "they hit me",
        "partner hit me",
        "he hurt me",
        "she hurt me",
        "hurts me",
        "i'm scared of him",
        "i'm scared of her",
        "i'm afraid of him",
        "i'm afraid of her",
        "he won't let me",
        "she won't let me",
        "forced me",
        "he threatened me",
        "she threatened me",
        "chokes me",
        "choked me",
        // Final review m-2: not only he/she.
        "they hurt me",
        "partner hurt me",
        "husband hurt me",
        "wife hurt me",
        "boyfriend hurt me",
        "girlfriend hurt me",
        "i'm scared of them",
        "i'm afraid of them",
        "they won't let me",
        "they threatened me",
        "partner threatened me",
        "husband threatened me",
        "wife threatened me",
      ],
    },
  },
} as const;

/// `victimisation` is the [DRAFT] list: callers pass the private safety
/// check's flag, so it runs only where draft safety content is switched on
/// (final review I-6). Self-harm, the reviewed sessions corpus, always runs.
export function detectSelfDisclosure(
  text: string | null | undefined,
  opts: { victimisation: boolean },
): SelfDisclosureFamily | null {
  if (!text) return null;
  const normalized = normalizeForTokenPhrase(text);
  if (normalized.trim().length === 0) return null;
  const families = opts.victimisation ? (["self_harm", "victimisation"] as const) : (["self_harm"] as const);
  for (const family of families) {
    for (const p of SELF_DISCLOSURE_CONFIG.families[family].phrases) {
      if (normalized.includes(` ${p} `)) return family;
    }
  }
  return null;
}
