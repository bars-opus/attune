// supabase/functions/_shared/writer_crisis_check.ts
//
// Spec 1 W9c and W9e (spec 4.5; D12; owner approval O2): the writer-facing
// crisis check, one implementation for the Journal (analyse-journal-entry)
// and Healing (generate-healing-portrait, generate-healing-post-mortem).
// Deterministic: no provider, no model. Self-harm (the reviewed sessions
// corpus, through detectSelfDisclosure) and the pending-review list
// (self_harm_pending.ts) always run; the [DRAFT] victimisation list only
// when the caller passes private_safety_check on (review A-4). The fold
// and the check moved here from analyse-journal-entry/journal_handlers.ts
// in W9e, unchanged. Hyphens read as spaces: normalizeForTokenPhrase keeps
// only letters, digits, apostrophes and spaces, and the pending matcher
// folds every dash first (W9 final re-review N-1).
import { detectSelfDisclosure } from "./self_disclosure.ts";
import { matchesPendingSelfHarm } from "./self_harm_pending.ts";

// Review I-2: typographic apostrophes (iOS smart punctuation, pasted text)
// and quotes become ASCII, so "don\u2019t" matches the corpus's "don't".
const APOSTROPHES = /[\u2018\u2019\u201B\u02BB\u02BC\uFF07\u0060\u00B4\u2032]/g;
const QUOTES = /[\u201C\u201D\u201E\u201F\u2033\uFF02\u00AB\u00BB]/g;
// Review M-1: invisible characters. The shared normaliser drops some of
// them (joining "kill\u200Bmyself" into one word); the text is checked both
// with them removed and with them as spaces.
const INVISIBLE = /[\u200B-\u200D\u2060\uFEFF\u00AD]/g;

/// Typographic apostrophes to ', typographic double quotes to ".
export function foldTypography(text: string): string {
  return text.replace(APOSTROPHES, "'").replace(QUOTES, '"');
}

/// True for a match, and for anything that stops the check from running:
/// [victimisation] null (the private_safety_check read threw, so it is
/// unknown) or a detector that throws. The writer is offered support and
/// nothing reaches a provider (fail safe).
export function writerTextDiscloses(text: string, victimisation: boolean | null): boolean {
  if (victimisation === null) return true;
  try {
    const folded = foldTypography(text);
    for (const t of [folded.replace(INVISIBLE, ""), folded.replace(INVISIBLE, " ")]) {
      if (detectSelfDisclosure(t, { victimisation }) !== null) return true;
      if (matchesPendingSelfHarm(t)) return true;
    }
    return false;
  } catch {
    return true;
  }
}
