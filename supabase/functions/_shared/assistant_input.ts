// Spec 8 (research 06 F15 (2); plan review C3, review §2.2 outcome table):
// one decision, made before consent, quota or any provider call, for
// Understand, Assist and the translator. Only the outcome travels — never a
// family, rule or tier (ai-assistant design §6.2: no deterministic match
// state is revealed).
//
//   partner's message  "no" / refusal       -> boundary (fixed card)
//   partner's message  self-harm            -> supporter card
//   partner's message  victimisation/threat -> unsafe_to_infer (as the model's own refusal)
//   requester's text   self-harm/victimisation -> writer_resources
//   requester's text   threat               -> unsafe_to_infer
//   anything else                          -> proceed
import { detectImmediateFamilies } from "./chat_safety.ts";
import { matchesDoNotInterpret } from "./do_not_interpret.ts";
import { detectSelfDisclosure } from "./self_disclosure.ts";

export type AssistantInputOutcome =
  | "proceed"
  | "boundary"
  | "supporter"
  | "unsafe_to_infer"
  | "writer_resources";

export function classifyAssistantInput(input: {
  targetContent: string;
  targetByRequester: boolean;
  instruction?: string | null;
  /** The private safety check's flag: the draft victimisation list runs
   * only with it on (final review I-6). Required, so no caller forgets. */
  draftLexicon: boolean;
}): { outcome: AssistantInputOutcome } {
  const lexicon = { victimisation: input.draftLexicon };
  const own = [input.instruction ?? "", input.targetByRequester ? input.targetContent : ""];
  for (const text of own) {
    if (detectSelfDisclosure(text, lexicon) !== null) return { outcome: "writer_resources" };
  }
  for (const text of own) {
    if (text && detectImmediateFamilies(text).length > 0) return { outcome: "unsafe_to_infer" };
  }
  if (!input.targetByRequester) {
    const family = detectSelfDisclosure(input.targetContent, lexicon);
    if (family === "self_harm") return { outcome: "supporter" };
    if (family === "victimisation" || detectImmediateFamilies(input.targetContent).length > 0) {
      return { outcome: "unsafe_to_infer" };
    }
    if (matchesDoNotInterpret(input.targetContent)) return { outcome: "boundary" };
  }
  return { outcome: "proceed" };
}
