// supabase/functions/_shared/self_harm_pending.ts
//
// Spec 1 W9 fix round 1 (batch-7-review.md I-5): self-harm phrasings that
// the reviewed sessions corpus (_shared/ai_session_safety.ts, reused by
// _shared/self_disclosure.ts) does not catch. Those two files are never
// touched (global constraints) and are live in AI Sessions and ai-assist,
// so the writer-facing crisis check (_shared/writer_crisis_check.ts) runs
// this list next to them instead: the Journal (W9c) and Healing (W9e).
// Spec 1 W9e moved it here from analyse-journal-entry/
// journal_self_harm_pending.ts, unchanged (its name and config_version
// are the list the clinician signs); that file now re-exports it.
//
// PENDING CLINICIAN REVIEW: a W9c gate item, and W9e's (the same gate).
// The suicide-prevention reviewer rules on every phrase before
// journal_ai_insights or healing_ai_insights goes on in production, and
// the reviewed ones move into the shared corpus (carry to Spec 8).
// It runs always, like the reviewed self-harm list: a false positive only
// shows a support card, a miss sends crisis words to a provider.
//
// Phrases are in normalizeForTokenPhrase's form: lower case, ASCII, single
// spaces, straight apostrophes. They match on whole words. Patterns (W9 final
// re-review N-1) match the same form, between spaces, and cover the near
// variants a fixed phrase misses: filler words ("all of my"), other verbs
// ("swallowed") and "over-dose" / "over dose" (hyphens read as spaces).
import { normalizeForTokenPhrase } from "./chat_safety.ts";

export const JOURNAL_SELF_HARM_PENDING = {
  config_version: "journal_self_harm_pending-0.3.0",
  review_status: "PENDING CLINICIAN REVIEW (W9c gate)",
  phrases: [
    "want to die",
    "wanna die",
    "wish i was dead",
    "wish i were dead",
    "better off dead",
    "suicidal",
    "suicide",
    "ending my life",
    "end my own life",
    "take my own life",
    "taking my own life",
    "kill my self",
    "killmyself",
    "killing myself",
    "cutting myself",
    "cut myself",
    "hurting myself",
    "harming myself",
    "self harm",
    "selfharm",
    "self harming",
    "don't want to live",
    "dont want to live",
    "do not want to live",
    "dont want to be here anymore",
    "do not want to be here anymore",
    "can't go on",
    "cant go on",
    "cannot go on",
    "want it to end",
    "want it all to end",
    // W9 final I-2 (final-review.md): obvious crisis phrasings the first
    // list missed, and their plain variants. Still pending review.
    "end it all",
    "ending it all",
    "took all my pills",
    "take all my pills",
    "taking all my pills",
    "overdose",
    "overdosed",
    "overdosing",
    "no point living",
    "no point in living",
    "no reason to live",
    "nobody would miss me",
    "no one would miss me",
    "burden to everyone",
    "dont want to exist",
    "don't want to exist",
    "do not want to exist",
    "dont want to be here any more",
    "don't want to be here any more",
    "do not want to be here any more",
    "don't want to be here anymore",
  ],
  patterns: [
    // "took all my pills", "swallowed all of my tablets"
    / (took|take|taking|swallowed|swallow|swallowing) all (of )?my (pills|tablets) /,
    // "overdose", "over dose", "over-dose", "overdosed", "overdosing"
    / over ?dos(e|ed|es|ing) /,
    // "burden to everyone", "a burden to everybody"
    / burden to (everyone|everybody) /,
    // "nobody would miss me", "no one would even miss me"
    / (nobody|no one|noone) would (even )?miss me /,
  ],
} as const;

// Any dash or hyphen reads as a space, so "over-dose" is "over dose".
const HYPHENS = /[\-\u2010-\u2015\u2212]/g;

/// True when the pending list or one of its patterns matches [text]. Used
/// by the writer crisis check (Journal and Healing) and by the owner's one-off backfill.
export function matchesPendingSelfHarm(text: string): boolean {
  const normalized = normalizeForTokenPhrase(text.replace(HYPHENS, " "));
  return JOURNAL_SELF_HARM_PENDING.phrases.some((p) => normalized.includes(` ${p} `)) ||
    JOURNAL_SELF_HARM_PENDING.patterns.some((r) => r.test(normalized));
}
